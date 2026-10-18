`timescale 1ns/1ps
module tb_audiofx_overlay;
 reg clk=0,rst=1,vs=0;always #5 clk=~clk;
 reg [63:0] levels=64'h0810182028303838;reg [3:0] volume=8;reg muted=0,stable=1;
 wire [23:0] wave_rgb,osd_rgb;reg [9:0] px=0,py=0;
 audio_waveform wave(.clk(clk),.rst(rst),.sample_valid(1'b0),.pcm(24'sd0),.spectrum_levels(levels),.spectrum_stable(stable),.in_vs(vs),.in_de(1'b1),.in_rgb(24'h804020),.out_vs(),.out_de(),.out_rgb(wave_rgb));
 video_osd osd(.clk(clk),.rst(rst),.in_vs(vs),.in_de(1'b1),.volume(volume),.muted(muted),.elapsed_tenths(10'd0),.total_tenths(10'd0),.progress_fill(9'd0),.progress_valid(1'b0),.in_rgb(24'h804020),.status(17'd0),.controls(4'd0),.debug_status(8'd0),.out_vs(),.out_de(),.out_rgb(osd_rgb));
 task frame;begin @(negedge clk);vs=1;repeat(3)@(negedge clk);vs=0;repeat(3)@(negedge clk);end endtask
 task pixel(input [9:0] x,y,input [23:0] expected);begin @(negedge clk);px=x;py=y;repeat(4)@(negedge clk);if(wave_rgb!==expected)$fatal(1,"Spectrum pixel %d/%d got %h expected %h",x,y,wave_rgb,expected);end endtask
 initial begin
  force wave.x=px;force wave.y=py;
  repeat(4)@(negedge clk);rst=0;frame();
  if(wave.spectrum_frame[5:0]!==levels[5:0] || wave.spectrum_frame[47:42]!==levels[61:56])$fatal(1,"Spectrum snapshot");
  pixel(464,250,24'h7de8ff);pixel(482,295,24'h65e0ad);pixel(482,265,24'hffe070);pixel(482,250,24'hff8050);
  pixel(494,295,24'h201008);pixel(604,244,24'h24505d);pixel(10,200,24'h804020);
  pixel(300,330,24'h804020);pixel(240,300,24'h804020);pixel(623,350,24'h7de8ff);pixel(500,308,24'h7de8ff);pixel(470,310,24'h201008);
  if(osd.spectrum_char(5)!="0" || osd.spectrum_char(8)!="-" || osd.spectrum_char(11)!="K")$fatal(1,"Compact title");
  levels=0;repeat(10)@(negedge clk);if(wave.spectrum_frame[5:0]!=56)$fatal(1,"Spectrum changed mid-frame");
  stable=0;frame();if(wave.spectrum_frame[5:0]!=56)$fatal(1,"Partial spectrum must not be displayed");stable=1;
  frame();if(wave.spectrum_frame[5:0]!=54)$fatal(1,"Spectrum release decay");
  if(osd.volume_char(4)!="1" || osd.volume_char(5)!="0" || osd.volume_char(6)!="0" || osd.volume_char(9)!=" ")$fatal(1,"Volume label 100%%");
  volume=3;muted=1;frame();
  if(osd.volume_char(4)!=" " || osd.volume_char(5)!="3" || osd.volume_char(6)!="8" || osd.volume_char(9)!="M" || osd.volume_char(12)!="E")$fatal(1,"38%% MUTE label");
  volume=0;muted=0;frame();if(osd.volume_char(5)!="0" || osd.volume_char(6)!="0")$fatal(1,"Zero volume label");
  $display("PASS spectrum panel colors, gaps, grid, frame snapshot/decay, passthrough, volume percent/mute text");$finish;
 end
endmodule
