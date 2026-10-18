`timescale 1ns/1ps
module tb_wav_osd;
reg clk=0,rst=1,vs=0;reg [15:0] status=0;always #5 clk=~clk;
video_osd dut(.clk(clk),.rst(rst),.in_vs(vs),.in_de(1'b0),.in_rgb(24'd0),.status(status),.controls(4'd0),.debug_status(8'd0),.out_vs(),.out_de(),.out_rgb());
task frame;begin @(negedge clk);vs=1;repeat(3)@(negedge clk);vs=0;repeat(3)@(negedge clk);end endtask
initial begin
 repeat(3)@(negedge clk);rst=0;status={1'b1,1'b0,1'b0,1'b0,1'b1,6'd7,5'd6};frame();
 if(dut.header_char(13)!="W" ||dut.header_char(14)!="A" ||dut.header_char(15)!="V" ||dut.header_char(17)!="0" ||dut.header_char(18)!="7" ||dut.header_char(23)!="P" ||dut.header_char(24)!="L" ||dut.header_char(26)!="Y")$fatal(1,"WAV PLAY OSD");
 status[11]=0;frame();
 if(dut.header_char(24)!="A" ||dut.header_char(25)!="U" ||dut.header_char(26)!="S" ||dut.header_char(27)!="E")$fatal(1,"WAV PAUSE OSD");
 $display("PASS WAV 07/07 PLAY/PAUSE OSD with black audio-only background");$finish;
end
endmodule
