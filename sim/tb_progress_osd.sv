`timescale 1ns/1ps
module tb_progress_osd;
 reg clk=0,rst=1,vs=0;always #20 clk=~clk;
 reg [16:0] status=17'h1e907;reg [9:0] elapsed=46,total=92;reg [8:0] fill=200;reg valid=1;reg [9:0] px=30,py=420;
 wire [23:0] rgb;
 video_osd dut(.clk(clk),.rst(rst),.in_vs(vs),.in_de(1'b1),.in_rgb(24'h123456),.status(status),.controls(4'd0),.debug_status(8'd0),.elapsed_tenths(elapsed),.total_tenths(total),.progress_fill(fill),.progress_valid(valid),.out_vs(),.out_de(),.out_rgb(rgb));
 task frame;begin @(negedge clk);vs=1;repeat(3)@(negedge clk);vs=0;repeat(3)@(negedge clk);end endtask
 task pixel(input [9:0] x,y,input [23:0] expected);begin @(negedge clk);px=x;py=y;repeat(4)@(negedge clk);if(rgb!==expected)$fatal(1,"OSD pixel %0d/%0d got %h expected %h",x,y,rgb,expected);end endtask
 initial begin
  force dut.x=px;force dut.y=py;
  repeat(3)@(negedge clk);rst=0;status[15]=1;status[11]=1;frame();
  if(dut.progress_char(4)!="4" ||dut.progress_char(6)!="6" ||dut.progress_char(14)!="9" ||dut.progress_char(16)!="2")$fatal(1,"Time label 00:04.6/00:09.2");
  pixel(30,420,24'h65e0ad);pixel(300,420,24'h253546);pixel(23,417,24'h7de8ff);
  elapsed=873;if(dut.progress_char(4)!="4")$fatal(1,"Time changed mid-frame");frame();
  if(dut.progress_char(1)!="1" ||dut.progress_char(3)!="2" ||dut.progress_char(4)!="7" ||dut.progress_char(6)!="3")$fatal(1,"Minute time label");
  status[11]=0;frame();pixel(30,420,24'hffe7a3);
  valid=0;frame();pixel(30,420,24'h123456);
  $display("PASS time label tenths/minutes, frame latch, progress fill/track/border, pause color, inactive hide");$finish;
 end
endmodule
