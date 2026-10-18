`timescale 1ns/1ps
module tb_waveform_pipeline;
 reg clk=0,rst=1,vs=0,de=0;reg [23:0] rgb=0;always #5 clk=~clk;
 wire ov,od;wire [23:0] out_rgb;
 audio_waveform dut(.clk(clk),.rst(rst),.sample_valid(1'b0),.pcm(24'sd0),.spectrum_levels(64'd0),.spectrum_stable(1'b1),.in_vs(vs),.in_de(de),.in_rgb(rgb),.out_vs(ov),.out_de(od),.out_rgb(out_rgb));
 integer n;reg pv=0,pd=0;reg [23:0] prgb=0;
 initial begin
  force dut.x=10'd10;force dut.y=10'd200;
  repeat(4)@(negedge clk);rst=0;
  for(n=0;n<128;n=n+1)begin
   @(negedge clk);de=n%5!=0;vs=n%17==0;rgb=$random;
   @(posedge clk);#1;
   if(ov!==pv || od!==pd || out_rgb!==(pd ? prgb:24'd0))$fatal(1,"RGB/VS/DE latency mismatch %0d",n);
   pv=vs;pd=de;prgb=rgb;
  end
  $display("PASS synchronous waveform RAM compositor: 128 random RGB/DE/VS inputs share exact two-stage latency");$finish;
 end
endmodule
