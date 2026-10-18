`timescale 1ns/1ps
module tb_wav_progress;
 parameter BAD=0;parameter GAP=31;
 reg clk=0,aclk=0;always #5 clk=~clk;always #20 aclk=~aclk;
 reg rst=1,abort=1,start=0,play=0,tick=0;
 wire ready,error,req,underrun;wire [31:0] addr;wire [23:0] l,r;
 reg [7:0] data=0;reg valid=0,sector_end=0;
 wav_read dut(.clk(clk),.rst(rst),.start(start),.abort(abort),.play(play),.base_sector(32'd0),.ready(ready),.error(error),.req(req),.addr(addr),.data(data),.valid(valid),.sector_end(sector_end),.audio_clk(aclk),.tick(tick),.left_pcm(l),.right_pcm(r),.underrun(underrun));
 reg [7:0] bytes[0:4607];integer i,n,b,delay_count=0,at=0,base=0;reg busy=0;
 task put32(input integer pos,input [31:0] x);begin bytes[pos]=x[7:0];bytes[pos+1]=x[15:8];bytes[pos+2]=x[23:16];bytes[pos+3]=x[31:24];end endtask
 initial begin
  for(i=0;i<4608;i=i+1)bytes[i]=0;
  put32(0,32'h46464952);put32(4,4132);put32(8,32'h45564157);put32(12,32'h20746d66);put32(16,16);put32(20,32'h00020001);put32(24,BAD==1 ? 44100 :48000);put32(28,192000);put32(32,32'h00100004);put32(36,32'h61746164);put32(40,4096);
  if(BAD==2)bytes[0]=0;
  for(i=0;i<1024;i=i+1)begin n=i*17;put32(44+i*4,{~n[15:0],n[15:0]});end
  #100;rst=0;#100;abort=0;#100;start=1;#10;start=0;
  if(BAD!=0) begin wait(error);#100;if(!ready)$fatal(1,"bad header not released");$display("PASS invalid WAV %0d",BAD);$finish;end
  wait(!ready);wait(ready);play=1;
 end
 // Card model requires request release before accepting the next sector.
 reg releasing=0;
 always @(negedge clk)begin
  valid=0;sector_end=0;
  if(releasing)begin if(!req)releasing=0;end
  else if(!busy && req)begin busy=1;base=addr*512;at=0;delay_count=0;end
  else if(busy)begin
   if(delay_count!=0)delay_count=delay_count-1;
   else if(at<512)begin data=bytes[base+at];valid=1;at=at+1;delay_count=GAP;end
   else begin busy=0;sector_end=1;releasing=1;end
  end
 end
 integer div=0,count=0,expected,paused_samples=0;reg paused=0;
 always @(negedge aclk)begin
  tick=0;
  if(!rst)begin
   if(div==519)begin div=0;tick=1;end else div=div+1;
   if(play && count==700 && !paused)begin play=0;paused=1;paused_samples=count;fork begin repeat(2000)@(negedge aclk);play=1;end join_none end
  end
 end
 always @(posedge aclk)begin
  if(dut.pop)begin
   expected=(count%1024)*17;
   #1;
   if(l!=={expected[15:0],8'd0} || r!=={~expected[15:0],8'd0})$fatal(1,"PCM mismatch sample %0d L=%h R=%h expect=%h",count,l,r,expected[15:0]);
   if(dut.playback_samples!==((count+1)%1024) ||dut.total_audio_samples!==1024)$fatal(1,"WAV consumed-sample timeline mismatch");
   count=count+1;
   if(count==2300)begin if(underrun)$fatal(1,"underrun");$display("PASS PCM stereo, sign, 2 loop boundaries, pause/resume, no underrun GAP=%0d",GAP);$finish;end
  end
 end
 initial begin #100000000;$fatal(1,"timeout samples=%0d state=%0d used=%0d",count,dut.state,dut.used);end
endmodule
