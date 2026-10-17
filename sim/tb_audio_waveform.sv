`timescale 1ns/1ps
module tb_audio_waveform;
 reg clk=0,rst=1,vs=0,de=0;
 wire valid,acr;
 wire [23:0] left_pcm,right_pcm;
 wire [19:0] cts,n;
 wire out_vs,out_de;
 wire [23:0] out_rgb;
 always #20 clk=~clk;
 audio_test_pcm tone(clk,rst,valid,left_pcm,right_pcm,acr,cts,n);
 audio_waveform dut(clk,rst,valid,left_pcm,vs,de,24'h804020,out_vs,out_de,out_rgb);
 integer i;
 reg first_bank;
 initial begin
  repeat(3) @(negedge clk);rst=0;
  wait(dut.ready);@(negedge clk);
  if(dut.display_valid) $fatal(1,"Bank committed before frame boundary");
  if(dut.write_index!=127) $fatal(1,"Incomplete capture");
  first_bank=dut.write_bank;
  for(i=0;i<128;i=i+1)
   if(dut.samples[{first_bank,7'(i)}]>80)
    $fatal(1,"Waveform coordinate outside plot");
  vs=1;@(negedge clk);vs=0;@(negedge clk);
  if(!dut.display_valid || dut.display_bank!=first_bank || dut.write_bank==first_bank)
    $fatal(1,"Frame swap/bank separation");
  wait(dut.ready);
  repeat(10) @(negedge clk);
  if(dut.display_bank!=first_bank) $fatal(1,"Bank changed during frame");
  $display("PASS: full captures, frame-only commit, write/display bank separation");
  $finish;
 end
 always @(posedge clk) if(!rst && dut.display_valid && dut.capture)
   if(dut.display_bank==dut.write_bank) $fatal(1,"Write touched displayed buffer");
 initial begin #40000000;$fatal(1,"Timeout");end
endmodule
