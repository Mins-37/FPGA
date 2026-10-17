`timescale 1ns/1ps
module tb_video_fade;
 reg clk=0,rst=1,valid=0,busy=0,vs=0,de=1;
 wire ovs,ode,black;
 wire [23:0] rgb;
 always #20 clk=~clk;
 video_fade dut(clk,rst,valid,busy,vs,de,24'h804020,ovs,ode,rgb,black);
 task frame;
 begin
  @(negedge clk);vs=1;
  repeat(2) @(negedge clk);
  vs=0;repeat(2) @(negedge clk);
 end endtask
 integer i,last_gain;
 initial begin
  repeat(3) @(negedge clk);rst=0;
  frame;if(!black) $fatal(1,"Startup must be black");
  valid=1;
  repeat(38) frame;
  if(dut.gain!=32 || rgb!==24'h804020) $fatal(1,"Full gain must preserve RGB");
  busy=1;frame;
  last_gain=32;
  for(i=0;i<32;i=i+1) begin
   frame;
   if(dut.gain>last_gain) $fatal(1,"Fade out not monotone");
   last_gain=dut.gain;
  end
  if(!black || rgb!==0) $fatal(1,"Commit permitted before black");
  repeat(4) frame;
  if(!black) $fatal(1,"Must hold black while load is busy");
  busy=0;
  repeat(3) begin frame;if(!black) $fatal(1,"Reader settling interval");end
  repeat(35) frame;
  if(dut.gain!=32) $fatal(1,"Failed to fade back in");
  // Load abort before the image is dark must restore the old picture.
  busy=1;repeat(10) frame;busy=0;repeat(38) frame;
  if(dut.gain!=32 || rgb!==24'h804020) $fatal(1,"Abort recovery");
  $display("PASS: startup, full gain, fade-out, black hold, settling, fade-in, abort recovery");
  $finish;
 end
 initial begin #1000000;$fatal(1,"Timeout");end
endmodule
