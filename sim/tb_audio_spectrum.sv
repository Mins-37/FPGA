`timescale 1ns/1ps
module tb_audio_spectrum;
 reg clk=0,rst=1,v=0;reg signed [23:0] pcm=0;always #5 clk=~clk;
 wire [63:0] levels;wire overrun;
 audio_spectrum dut(clk,rst,v,pcm,levels,overrun,);
 reg [23:0] samples[0:8191];reg [63:0] expected[0:31];reg [1023:0] sample_file,level_file;
 integer blocks,b,n;
 initial begin
  if(!$value$plusargs("PCM=%s",sample_file)||!$value$plusargs("LEVELS=%s",level_file)||!$value$plusargs("BLOCKS=%d",blocks))$fatal(1,"Fixtures missing");
  $readmemh(sample_file,samples,0,blocks*256-1);$readmemh(level_file,expected,0,blocks-1);
  repeat(4)@(negedge clk);rst=0;repeat(12)@(negedge clk);
  for(b=0;b<blocks;b=b+1) begin
   for(n=0;n<256;n=n+1) begin
    @(negedge clk);pcm=samples[b*256+n];v=1;@(negedge clk);v=0;
    repeat(519)@(negedge clk);
   end
   if(levels!==expected[b] || overrun)$fatal(1,"Spectrum block %0d got %h expected %h overrun=%b",b,levels,expected[b],overrun);
   repeat(100)@(negedge clk);if(levels!==expected[b])$fatal(1,"Spectrum moved during pause");
  end
  rst=1;repeat(3)@(negedge clk);rst=0;repeat(10)@(negedge clk);
  if(levels!=0 || overrun)$fatal(1,"Reset did not clear spectrum");
  $display("PASS %0d Goertzel blocks: all 8 centers, off-bin, multitone, noise, silence, gain scaling, exact independent integer model, pause/reset",blocks);$finish;
 end
 initial begin #60000000;$fatal(1,"Timeout");end
endmodule
