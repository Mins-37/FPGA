`timescale 1ns/1ps
module tb_audio_only;
 reg clk=0,rst=1,key_next=1,key_auto=1,aclk=0,tick=0;always #5 clk=~clk;always #20 aclk=~aclk;
 integer div=0;always @(negedge aclk)begin tick=0;if(div==519)begin div=0;tick=1;end else div=div+1;end
 wire valid,req,en,mode,under;wire [31:0] data;wire [23:0] l,r;wire [1:0] wb,db;wire [15:0] status;wire [7:0] debug;
 reg fin=0,ack=0;reg [7:0] req_pipe=0;
 sd_card_bmp #(.CLK_FREQ_HZ(1000)) dut(.clk(clk),.rst(rst),.key_next(key_next),.key_auto(key_auto),.audio_clk(aclk),.audio_tick(tick),.wav_left(l),.wav_right(r),.audio_mode(mode),.audio_underrun(under),
 .bmp_width(16'd640),.bmp_height(16'd480),.display_valid(valid),.osd_status(status),.osd_debug(debug),.state_code(),
 .write_finish_toggle(fin),.frame_sync(1'b1),.pixel_write_ready(1'b1),.reader_buffer_active(db),.fade_black(1'b1),.write_buf_idx(wb),.disp_buf_idx(db),
 .write_req(req),.write_req_ack(ack),.write_en(en),.write_data(data),.SD_nCS(),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1));
 integer count=0,frames=0,samples=0,n,hold_samples;reg checking=0;reg [1:0] saved_db;
 always @(posedge clk)begin
  if(rst)begin req_pipe<=0;ack<=0;fin<=0;count=0;end
  else begin
   req_pipe<={req_pipe[6:0],req};ack<=req_pipe[7];
   if(req && !ack)count=0;
   if(en)begin if(dut.load_is_audio)$fatal(1,"Audio wrote video");count=count+1;if(count==307200)begin fin<=~fin;frames=frames+1;end end
   if(debug[3])$fatal(1,"Player error %h FAT %0d",debug,dut.fat_error_code);
   if(under)$fatal(1,"PCM underrun");
  end
 end
 always @(posedge aclk)if(dut.u_wav.pop && checking)begin n=(samples%1024)*17;#1;if(l!=={n[15:0],8'd0} ||r!=={~n[15:0],8'd0})$fatal(1,"Mixed PCM mismatch %0d %h",samples,l);samples=samples+1;end
 task next;begin @(negedge clk);key_next=0;repeat(80)@(negedge clk);key_next=1;repeat(80)@(negedge clk);end endtask
 task pause_play;begin @(negedge clk);key_auto=0;repeat(80)@(negedge clk);key_auto=1;repeat(80)@(negedge clk);end endtask
 initial begin
  checking=1;repeat(5)@(negedge clk);rst=0;wait(status[15] &&!debug[2]);
  if(valid ||status[10:5]!=1 || !status[11] ||frames!=0)$fatal(1,"Audio-only initial state");
  wait(samples==100);pause_play();wait(!status[11]);repeat(5)@(negedge aclk);hold_samples=samples;
  repeat(2000)@(negedge aclk);if(samples!=hold_samples)$fatal(1,"Audio-only pause");
  pause_play();wait(samples==150);
  if(valid || frames!=0)$fatal(1,"Audio-only touched framebuffer");
  $display("PASS audio-only FAT32 boot, PCM, black background, pause/resume with one file");$finish;
 end
 initial begin #500000000;$fatal(1,"Timeout %h FAT%0d wav%0d",status,dut.u_fat32.state,dut.u_wav.state);end
endmodule
