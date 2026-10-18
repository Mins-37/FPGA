`timescale 1ns/1ps
module tb_audiofx_chain;
 reg clk=0,rst=1,mute=0;always #20 clk=~clk;
 wire tick,acr;wire [23:0] tone_l,tone_r;wire [19:0] cts,n;
 audio_test_pcm tone(clk,rst,tick,tone_l,tone_r,acr,cts,n);
 reg tick_d;reg [23:0] left_d,right_d;
 always @(posedge clk) if(rst)begin tick_d<=0;left_d<=0;right_d<=0;end else begin tick_d<=tick;left_d<=tone_l;right_d<=tone_r;end
 wire valid;wire [23:0] left_out,right_out;wire [63:0] levels;wire overrun;
 audio_gain gain(clk,rst,tick_d,left_d,right_d,4'd8,mute,valid,left_out,right_out);
 audio_spectrum spectrum(clk,rst,valid,left_out,levels,overrun,);
 integer count=0,cycles=0,last_cycle=0,i,best;reg [63:0] snapshot;
 always @(posedge clk) if(!rst)cycles<=cycles+1;
 always @(negedge clk) if(!rst && valid)begin
  if(count>0 && cycles-last_cycle!=520 && cycles-last_cycle!=521)$fatal(1,"48kHz cadence changed");
  if(left_out!==right_out)$fatal(1,"Stereo mismatch");
  last_cycle=cycles;count=count+1;
 end
 initial begin
  repeat(4)@(negedge clk);rst=0;
  wait(count>=1100);@(negedge clk);
  best=0;for(i=1;i<8;i=i+1)if(levels[i*8+:8]>levels[best*8+:8])best=i;
  if(best!=2 || levels[23:16]==0 || overrun)$fatal(1,"1kHz real HDMI tone did not show near 750Hz bin: %h",levels);
  mute=1;wait(count>=2000);@(negedge clk);
  if(left_out!==0 || right_out!==0 || levels!==0 || overrun)$fatal(1,"Mute did not reach both PCM and measured spectrum");
  mute=0;wait(count>=3100);@(negedge clk);
  if(levels[23:16]==0 || overrun || n!=6144 || cts!=25000)$fatal(1,"Unmute/ACR failed");
  $display("PASS actual 25MHz->48kHz tone/gain/spectrum chain, 3100 output samples, mute/unmute and unchanged ACR/cadence");$finish;
 end
 initial begin #100000000;$fatal(1,"Timeout");end
endmodule
