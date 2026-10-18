`timescale 1ns/1ps
module tb_animation_player;
reg clk=0,rst=1,key_next=1,key_auto=1;always #5 clk=~clk;
reg frame_sync=1;integer phase=0,vblanks=0;
wire valid,req,en;wire [31:0] data;wire [1:0] wb,db;wire [14:0] status;wire [7:0] debug;
reg [1:0] reader_active=0;reg fin=0,ack=0;reg [7:0] req_pipe=0;
integer cycles=0;wire pixel_ready=cycles%997>=90;
sd_card_bmp #(.CLK_FREQ_HZ(1000)) dut(.clk(clk),.rst(rst),.key_next(key_next),.key_auto(key_auto),
 .bmp_width(16'd640),.bmp_height(16'd480),.display_valid(valid),.osd_status(status),.osd_debug(debug),.state_code(),
 .write_finish_toggle(fin),.fade_black(1'b1),.frame_sync(frame_sync),.pixel_write_ready(pixel_ready),.reader_buffer_active(reader_active),.write_buf_idx(wb),.disp_buf_idx(db),
 .write_req(req),.write_req_ack(ack),.write_en(en),.write_data(data),.SD_nCS(),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1));
// The reader deliberately observes buffer selection one vertical edge later.
// The writer must wait for that acknowledgement before reusing the old buffer.
always @(negedge clk) begin
 if(rst) begin phase=0;frame_sync=1;reader_active=0;vblanks=0;end
 else begin
  if(phase==399999) begin phase=0;frame_sync=0;reader_active=db;vblanks=vblanks+1;end
  else begin phase=phase+1;if(phase==20) frame_sync=1;end
 end
end
integer pixels=0,written_frames=0,x,y,sx,sy,r,g,b,frame_number,old_frame_number=-1;
integer anim_commits=0,last_commit_blank=-1,paused_frames;
reg [1:0] old_db=0;reg old_valid=0,req_d=0,auto_d=0,anim_d=0;reg ready_d=0;reg [23:0] expected;
reg strict_cadence=0;
always @(posedge clk) begin
 if(rst) begin req_pipe<=0;ack<=0;fin<=0;pixels=0;cycles<=0;end
 else begin
  cycles<=cycles+1;req_pipe<={req_pipe[6:0],req};ack<=req_pipe[7];req_d<=req;ready_d<=pixel_ready;
  if(req && !req_d) begin
   if(status[14] && reader_active!=db) $fatal(1,"Old display buffer reused before reader handoff");
   pixels=0;frame_number=dut.load_frame;
  end
  if(en) begin
   if(ack) $fatal(1,"Pixel during FIFO reset");
   if(dut.load_is_anim) begin
    if(!ready_d) $fatal(1,"Animation ignored backpressure");
    sx=(pixels%640)/4;sy=(pixels/640)/4;r=(sx+frame_number*3)&31;g=(sy+frame_number*5)&63;b=(sx^sy^frame_number)&31;
    expected={r[4:0],r[4:2],g[5:0],g[5:4],b[4:0],b[4:2]};
   end else begin
    x=pixels%640;y=pixels/640;expected=0;
    // 17x11 -> 640x414, top/bottom 33 pixels.
    if(y>=33 && y<447) begin sx=x*17/640;sy=(y-33)*11/414;expected={8'(sx),8'(sy),8'(sx^sy)};end
   end
   if(data!=={expected,8'd0}) $fatal(1,"Frame %0d pixel %0d got %h expected %h",frame_number,pixels,data,{expected,8'd0});
   pixels=pixels+1;
   if(pixels==307200) begin fin<=~fin;written_frames=written_frames+1;end
   if(pixels>307200) $fatal(1,"Extra pixel");
  end
  if(valid && (!old_valid || db!=old_db) && status[14]) begin
   if(frame_sync!==0) $fatal(1,"Animation committed outside vertical blank");
   if(strict_cadence && last_commit_blank>=0 && vblanks-last_commit_blank!=6) $fatal(1,"Animation cadence is %0d vsyncs",vblanks-last_commit_blank);
   last_commit_blank=vblanks;anim_commits=anim_commits+1;
   $display("ANM commit %0d: frame %0d, blank %0d",anim_commits,dut.presented_frame,vblanks);
  end
  old_valid<=valid;old_db<=db;auto_d<=status[11];anim_d<=status[14];
  if(debug[3]) $fatal(1,"Player error debug %h FAT %0d",debug,dut.fat_error_code);
 end
end
task press_next;begin @(negedge clk);key_next=0;repeat(80) @(negedge clk);key_next=1;repeat(80) @(negedge clk);end endtask
task press_auto;begin @(negedge clk);key_auto=0;repeat(80) @(negedge clk);key_auto=1;repeat(80) @(negedge clk);end endtask
initial begin
 repeat(5) @(negedge clk);rst=0;wait(valid && !debug[2]);@(negedge clk);
 if(status[10:5]!=2 || status[14] || status[4:0]!=0) $fatal(1,"Mixed catalogue initial state wrong");
 press_next();wait(status[14]);strict_cadence=1;
 wait(anim_commits==3);strict_cadence=0;
 if(dut.presented_frame!=0) $fatal(1,"Animation did not wrap 0->1->0");
 press_auto();wait(!status[11]);wait(!debug[2]);paused_frames=written_frames;
 repeat(3200000) @(negedge clk);
 if(written_frames!=paused_frames || status[11]) $fatal(1,"Pause did not hold the last frame");
 press_auto();wait(status[11]);wait(anim_commits>=5);
 press_next();wait(!status[14] && status[4:0]==0 && !debug[2]);@(negedge clk);
 if(status[11]) $fatal(1,"Returning to pictures did not restore manual mode");
 $display("PASS: mixed FAT32 BMP/ANM playback, RGB pixels, 6-vsync cadence, loop, pause/resume, safe buffer handoff and return to picture");$finish;
end
initial forever begin #10000000; $display("PROGRESS cycles=%0d status=%h pixels=%0d commits=%0d FAT=%0d BMP=%0d ANM=%0d",cycles,status,pixels,anim_commits,dut.u_fat32.state,dut.bmp_read_m0.state,dut.u_anm_read.state); end
initial begin
 #1000000;
 if(!dut.scan_done || status[10:5]!=2) $fatal(1,"Startup catalogue scan was skipped");
 if($test$plusargs("SCAN_ONLY")) begin $display("PASS: startup catalogue scan survives SD initialization release");$finish;end
end
initial begin #1000000000;$fatal(1,"Animation player timeout: status %h commits %0d",status,anim_commits);end
endmodule
