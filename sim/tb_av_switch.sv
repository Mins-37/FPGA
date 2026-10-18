`timescale 1ns/1ps
module tb_av_switch;
reg aclk=0;always #20 aclk=~aclk;wire tick;wire [23:0] al,ar;wire audio_mode,under;
audio_test_pcm clock48(.clk(aclk),.rst(rst),.sample_valid(tick),.left_pcm(),.right_pcm(),.acr_valid(),.acr_cts(),.acr_n());
reg clk=0,rst=1,key_next=1,key_auto=1;always #5 clk=~clk;
reg frame_sync=1;integer phase=0,vblanks=0;
wire valid,req,en;wire [31:0] data;wire [1:0] wb,db;wire [16:0] status;wire [7:0] debug;
reg [1:0] reader_active=0;reg fin=0,ack=0;reg [7:0] req_pipe=0;
integer cycles=0;wire pixel_ready=cycles%997>=90;
sd_card_bmp #(.CLK_FREQ_HZ(1000)) dut(.clk(clk),.rst(rst),.key_next(key_next),.key_auto(key_auto),.audio_clk(aclk),.audio_tick(tick),.wav_left(al),.wav_right(ar),.audio_mode(audio_mode),.audio_underrun(under),
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
   if(status[16]) begin
    if(dut.presented_frame!=(dut.presented_epoch%2))$fatal(1,"Frame/epoch mismatch");
    if($signed(dut.audio_epoch-dut.presented_epoch)<0 ||dut.audio_epoch-dut.presented_epoch>1)$fatal(1,"AV sync epoch %0d video %0d",dut.audio_epoch,dut.presented_epoch);
   end
   last_commit_blank=vblanks;anim_commits=anim_commits+1;
   $display("ANM commit %0d: frame %0d, blank %0d",anim_commits,dut.presented_frame,vblanks);
  end
  old_valid<=valid;old_db<=db;auto_d<=status[11];anim_d<=status[14];
  if(under)$fatal(1,"Audio underrun");
  if(debug[3]) $fatal(1,"Player error debug %h FAT %0d",debug,dut.fat_error_code);
 end
end
task press_next;begin @(negedge clk);key_next=0;repeat(80) @(negedge clk);key_next=1;repeat(80) @(negedge clk);end endtask
task press_auto;begin @(negedge clk);key_auto=0;repeat(80) @(negedge clk);key_auto=1;repeat(80) @(negedge clk);end endtask
integer samples=0,n,held_samples,held_commits;reg checking_audio=0;
always @(posedge aclk)if(dut.u_wav.pop && checking_audio)begin
 n=((samples%9600)*17)&65535;#1;
 if(al!=={n[15:0],8'd0} ||ar!=={~n[15:0],8'd0})$fatal(1,"AV PCM sample %0d got %h/%h",samples,al,ar);
 samples=samples+1;
end
reg watch_initial=0;
always @(posedge aclk)if(watch_initial &&dut.load_busy &&!dut.load_continuation &&dut.u_wav.pop)$fatal(1,"New AVM audio started before initial video commit");
initial begin
 checking_audio=1;repeat(5)@(negedge clk);rst=0;wait(status[16] &&!debug[2]);wait(samples==100);
 checking_audio=0;press_next();wait(dut.audio_stopped);
 wait(dut.load_start_pulse &&dut.load_idx==1);samples=0;checking_audio=1;watch_initial=1;
 wait(status[4:0]==1 &&!debug[2]);wait(samples==100);watch_initial=0;
 if(!status[16] ||!status[11])$fatal(1,"Second AVM state");
 press_auto();wait(!status[11]);repeat(5)@(negedge aclk);held_samples=samples;
 repeat(1000)@(negedge aclk);if(samples!=held_samples)$fatal(1,"Second AVM pause");
 press_auto();wait(samples>=held_samples+50);
 $display("PASS AVM-to-AVM handoff: cancel prefetch, reset audio timeline, no new audio before initial frame commit, exact PCM restart and pause/resume");$finish;
end
initial forever begin #10000000; $display("PROGRESS cycles=%0d status=%h pixels=%0d commits=%0d FAT=%0d BMP=%0d ANM=%0d",cycles,status,pixels,anim_commits,dut.u_fat32.state,dut.bmp_read_m0.state,dut.u_anm_read.state); end
initial begin #1000000000;$fatal(1,"Animation player timeout: status %h commits %0d",status,anim_commits);end
endmodule

// Physical-sector card model only; real FAT32 and scheduler/decoder RTL above.
module sd_card_top(input clk,rst,output SD_nCS,SD_DCLK,SD_MOSI,input SD_MISO,
 output reg sd_init_done,input sd_sec_read,input [31:0] sd_sec_read_addr,
 output reg [7:0] sd_sec_read_data,output reg sd_sec_read_data_valid,sd_sec_read_end,
 input sd_sec_write,input [31:0] sd_sec_write_addr,input [7:0] sd_sec_write_data,
 output sd_sec_write_data_req,sd_sec_write_end);
reg [31:0] lbas[0:8191];reg [7:0] bytes[0:4194303];reg [1023:0] lp,bp;
integer n,j,lookup,selected,ptr=0,state=0,pause=0,init_cnt=0;
assign SD_nCS=1;assign SD_DCLK=0;assign SD_MOSI=1;assign sd_sec_write_data_req=0;assign sd_sec_write_end=0;
initial begin
 if(!$value$plusargs("LBAS=%s",lp)||!$value$plusargs("BYTES=%s",bp)||!$value$plusargs("N=%d",n)) $fatal(1,"Missing card image");
 $readmemh(lp,lbas,0,n-1);$readmemh(bp,bytes,0,n*512-1);
end
always @(negedge clk) begin
 if(rst) begin state=0;sd_init_done=0;init_cnt=0;sd_sec_read_data_valid=0;sd_sec_read_end=0;end
 else if(!sd_init_done) begin init_cnt=init_cnt+1;if(init_cnt==10) sd_init_done=1;end
 else case(state)
 0:begin sd_sec_read_data_valid=0;sd_sec_read_end=0;if(sd_sec_read) begin
 lookup=-1;for(j=0;j<n;j=j+1) if(lbas[j]==sd_sec_read_addr) lookup=j;
 if(lookup<0) $fatal(1,"Unexpected card address %0d",sd_sec_read_addr);
 selected=lookup;ptr=0;pause=0;state=1;end end
 1:begin
 if(pause) begin sd_sec_read_data_valid=0;pause=pause-1;end
 else begin sd_sec_read_data_valid=1;sd_sec_read_data=bytes[selected*512+ptr];pause=1;if(ptr==511) state=2;else ptr=ptr+1;end end
 2:begin sd_sec_read_data_valid=0;sd_sec_read_end=1;state=3;end
 3:begin sd_sec_read_end=0;if(!sd_sec_read) state=0;end
 endcase
end
endmodule
