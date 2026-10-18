`timescale 1ns/1ps
module tb_fat_osd;
reg clk=0,rst=1,vs=0;reg [13:0] status=0;always #5 clk=~clk;
video_osd dut(.clk(clk),.rst(rst),.in_vs(vs),.in_de(1'b0),.in_rgb(24'd0),.status(status),.controls(4'd0),.debug_status(8'd0),.out_vs(),.out_de(),.out_rgb());
task frame;begin @(negedge clk);vs=1;repeat(3) @(negedge clk);vs=0;repeat(3) @(negedge clk);end endtask
initial begin
 repeat(3) @(negedge clk);rst=0;status={1'b1,1'b0,1'b1,6'd32,5'd31};frame();
 if(dut.header_char(17)!="3" || dut.header_char(18)!="2" || dut.header_char(19)!="/" || dut.header_char(20)!="3" || dut.header_char(21)!="2" || dut.header_char(23)!="A") $fatal(1,"32/32 AUTO OSD failed");
 status={1'b1,1'b0,1'b0,6'd5,5'd4};repeat(5) @(negedge clk);
 if(dut.header_char(17)!="3") $fatal(1,"OSD changed before frame boundary");
 frame();
 if(dut.header_char(17)!="0" || dut.header_char(18)!="5" || dut.header_char(20)!="0" || dut.header_char(21)!="5" || dut.header_char(23)!="M") $fatal(1,"05/05 MANUAL OSD failed");
 $display("PASS: OSD 32/32 AUTO, 05/05 MANUAL and frame-latched update");$finish;
end
endmodule
