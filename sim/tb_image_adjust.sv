`timescale 1ns/1ps
module tb_image_adjust;
 reg clk=0,rst=1,vs=0,de=0;
 reg [3:0] sw=0;
 reg [23:0] rgb=0;
 wire out_vs,out_de;
 wire [23:0] out_rgb;
 wire [3:0] controls;
 always #20 clk=~clk;
 image_adjust #(.DEBOUNCE_CYCLES(4)) dut(
 .clk(clk),.rst(rst),.sw(sw),.in_vs(vs),.in_de(de),.in_rgb(rgb),
 .out_vs(out_vs),.out_de(out_de),.out_rgb(out_rgb),.active_controls(controls));
 function automatic [7:0] expected(input integer c,input integer setting);
 integer gain,bri,product,value;
 begin
  case(setting>>2) 0:gain=4;1:gain=3;2:gain=5;3:gain=6;endcase
  case(setting&3) 0:bri=0;1:bri=32;2:bri=-32;3:bri=64;endcase
  product=(c-128)*gain;
  value=(product<0 ? -((-product+3)/4) : product/4)+128+bri;
  expected=value<0 ? 0 : (value>255 ? 255 : value);
 end endfunction
 integer setting,c;
 reg [23:0] want;
 initial begin
  repeat(3) @(negedge clk);rst=0;
  for(setting=0;setting<16;setting=setting+1) begin
   @(negedge clk);sw=setting;
   repeat(12) @(negedge clk);
   // Changes must wait for the next frame edge.
   vs=1;@(negedge clk);vs=0;
   if(controls!==setting[3:0]) $fatal(1,"Frame control latch");
   for(c=0;c<256;c=c+1) begin
    @(negedge clk);de=1;rgb={8'(c),8'(255-c),8'd123};
    want={expected(c,setting),expected(255-c,setting),expected(123,setting)};
    @(posedge clk);#1;
    if(out_rgb!==want || !out_de || out_vs!==vs)
      $fatal(1,"Pixel mismatch setting=%0d value=%0d got=%h want=%h",setting,c,out_rgb,want);
   end
   @(negedge clk);de=0;
   @(posedge clk);#1;if(out_rgb!==0 || out_de) $fatal(1,"Blanking");
  end
  $display("PASS: all 4096 scalar settings, RGB, clipping, blanking, frame controls");
  $finish;
 end
 initial begin #1000000;$fatal(1,"Timeout");end
endmodule
