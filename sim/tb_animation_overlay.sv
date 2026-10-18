`timescale 1ns/1ps
module tb_animation_overlay;
reg clk=0,rst=1,vs=0,bypass=1,busy=1;reg [14:0] status=0;always #5 clk=~clk;
wire [23:0] rgb;wire black;
video_osd osd(.clk(clk),.rst(rst),.in_vs(vs),.in_de(1'b1),.in_rgb(24'h806040),.status(status),.controls(4'd0),.debug_status(8'd0),.out_vs(),.out_de(),.out_rgb());
video_fade fade(.clk(clk),.rst(rst),.image_valid(1'b1),.load_busy(busy),.bypass(bypass),.in_vs(vs),.in_de(1'b1),.in_rgb(24'h806040),.out_vs(),.out_de(),.out_rgb(rgb),.black(black));
task frame;begin @(negedge clk);vs=1;repeat(4) @(negedge clk);vs=0;repeat(4) @(negedge clk);end endtask
initial begin
 repeat(3) @(negedge clk);rst=0;status={1'b1,1'b1,1'b1,1'b1,6'd6,5'd5};frame();
 if(osd.header_char(13)!="A" || osd.header_char(14)!="N" || osd.header_char(15)!="M" || osd.header_char(23)!="P" || osd.header_char(24)!="L" || osd.header_char(26)!="Y") $fatal(1,"ANM PLAY label failed");
 if(rgb!==24'h806040 || black) $fatal(1,"Animation was faded during frame load");
 status[11]=0;frame();
 if(osd.header_char(24)!="A" || osd.header_char(25)!="U" || osd.header_char(26)!="S" || osd.header_char(27)!="E") $fatal(1,"PAUSE label failed");
 bypass=0;status[14]=0;frame();frame();
 if(fade.gain>=32) $fatal(1,"Picture fade was not restored");
 $display("PASS: ANM PLAY/PAUSE OSD, no per-frame fade, picture fade restored");$finish;
end
endmodule
