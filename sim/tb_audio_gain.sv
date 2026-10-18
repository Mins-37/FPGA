`timescale 1ns/1ps
module tb_audio_gain;
 reg clk=0,rst=1,v=0,mute=0;reg [3:0] volume=8;
 reg signed [23:0] l=0,r=0;wire ov;wire signed [23:0] ol,orr;
 always #5 clk=~clk;
 audio_gain dut(clk,rst,v,l,r,volume,mute,ov,ol,orr);
 reg signed [23:0] el[0:8191],er[0:8191];integer sent=0,seen=0,gain=256,target,k,j;
 reg signed [63:0] product;
 always @(negedge clk) if(!rst && ov) begin
  if(seen>=sent || ol!==el[seen] || orr!==er[seen]) $fatal(1,"PCM mismatch sample %0d L=%0d/%0d R=%0d/%0d",seen,ol,el[seen],orr,er[seen]);
  seen=seen+1;
 end
 task send(input signed [23:0] left,right);begin
  @(negedge clk);l=left;r=right;v=1;
  product=$signed(left)*gain;el[sent]=product>>>8;
  product=$signed(right)*gain;er[sent]=product>>>8;sent=sent+1;
  target=mute ? 0:volume*32;
  if(gain<target) gain=gain+1;else if(gain>target) gain=gain-1;
  @(negedge clk);v=0;repeat(3)@(negedge clk);
 end endtask
 initial begin
  repeat(4)@(negedge clk);rst=0;
  send(24'sh7fffff,24'sh800000);send(-1,1);send(0,0);
  for(k=0;k<=8;k=k+1) begin volume=k;for(j=0;j<280;j=j+1) send($random,$random);end
  mute=1;for(j=0;j<280;j=j+1)send(24'sh7fffff,24'sh800000);
  if(ol!==0 || orr!==0)$fatal(1,"Mute not exact zero");
  repeat(40)@(negedge clk);if(ov || dut.gain!=0)$fatal(1,"Invalid idle or ramp advanced without samples");
  mute=0;for(j=0;j<280;j=j+1)send($random,$random);
  send(24'sh7fffff,24'sh800000);repeat(4)@(negedge clk);
  if(seen!=sent || ol!==24'sh7fffff || orr!==24'sh800000)$fatal(1,"Full scale or valid count");
  $display("PASS signed stereo gain: %0d exact samples, all nine levels, smooth mute/unmute, idle, extrema, valid alignment",seen);$finish;
 end
endmodule
