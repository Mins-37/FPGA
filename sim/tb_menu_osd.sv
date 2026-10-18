`timescale 1ns/1ps
module tb_menu_osd;
 reg clk=0,wclk=0,rst=1,vs=0,de=1,opened=1,ready=1;always #5 clk=~clk;always #7 wclk=~wclk;
 reg [5:0] count=13;reg [4:0] selected=8,base=6,current=7;reg [23:0] bg=24'h804020;
 reg we=0;reg [8:0] wa=0;reg [7:0] wd=0;wire [8:0] ra;wire [7:0] rd;wire ov,od;wire [23:0] rgb;
 reg [9:0] px=10,py=200;
 media_name_ram names(wclk,we,wa,wd,clk,ra,rd);
 media_menu_osd dut(clk,rst,vs,de,bg,opened,ready,count,selected,base,current,ra,rd,ov,od,rgb);
 function [7:0] value(input integer f,b);
 reg [63:0] longname;reg [23:0] ext;begin
  longname="LONGNA~1";
  case(f%4)0:ext="BMP";1:ext="ANM";2:ext="WAV";3:ext="AVM";endcase
  if(b==11)value={(f==5 ? 6'd8:6'd3),2'(f%4)};
  else if(b>=8)value=ext[23-(b-8)*8-:8];
  else if(f==5)value=longname[63-b*8-:8];
  else case(b)0:value="0";1:value="0"+(f+1)/10;2:value="0"+(f+1)%10;default:value=" ";endcase
 end endfunction
 task frame;begin @(negedge clk);vs=1;repeat(5)@(negedge clk);vs=0;repeat(25)@(negedge clk);end endtask
 task position(input [9:0] a,b);begin @(negedge clk);px=a;py=b;repeat(5)@(negedge clk);end endtask
 task pixel(input [9:0] a,b,input [23:0] expected);begin position(a,b);if(rgb!==expected)$fatal(1,"Menu pixel %0d/%0d %h expected %h",a,b,rgb,expected);end endtask
 task character(input [9:0] a,b,input [7:0] expected);begin position(a,b);if(dut.ch1!==expected)$fatal(1,"Menu character %0d/%0d got %h expected %h",a,b,dut.ch1,expected);end endtask
 integer f,b,n;reg pv0=0,pv1=0,pd0=0,pd1=0;reg [23:0] pr0=0,pr1=0;
 initial begin
  force dut.x=px;force dut.y=py;
  for(f=0;f<32;f=f+1)for(b=0;b<12;b=b+1)begin @(negedge wclk);we=1;wa=f*16+b;wd=value(f,b);end
  @(negedge wclk);we=0;repeat(4)@(negedge clk);rst=0;frame();
  if(dut.meta[0]!==value(6,11) || dut.meta[5]!==value(11,11))$fatal(1,"Metadata prefetch from byte RAM");
  if(dut.info_char(0)!="1" || dut.info_char(1)!="3" || dut.info_char(11)!="7" || dut.info_char(13)!="1" || dut.info_char(14)!="2")$fatal(1,"Page info 13 files 07-12");
  pixel(16,200,24'h7de8ff);pixel(25,218,24'h7de8ff);pixel(38,220,24'h164858);pixel(27,200,24'h70ee80);pixel(320,220,24'h804020);pixel(500,300,24'h804020);
  character(80,164,"0");character(92,164,"0");character(104,164,"7");character(116,164,".");character(128,164,"W");character(140,164,"A");character(152,164,"V");character(164,164," ");
  character(236,164,"W");character(248,164,"A");character(260,164,"V");
  base=0;selected=5;frame();character(80,314,"L");character(152,314,"~");character(164,314,"1");character(176,314,".");character(188,314,"A");
  base=12;selected=12;frame();character(104,164,"3");pixel(200,194,24'h201008);
  count=32;base=30;selected=31;frame();character(92,194,"3");character(104,194,"2");character(236,194,"V");character(248,194,"I");character(260,194,"D");
  count=0;base=0;selected=0;frame();character(32,164,"N");character(44,164,"O");
  ready=0;frame();character(32,164,"S");
  opened=0;frame();pixel(100,164,24'h804020);
  de=0;vs=0;repeat(5)@(negedge clk);px=10;py=200;
  for(n=0;n<128;n=n+1)begin
   @(negedge clk);de=n%5!=0;vs=n%17==0;bg=$random;@(posedge clk);#1;
   if(ov!==pv1 || od!==pd1 || rgb!==(pd1 ? pr1:24'd0))$fatal(1,"Menu RGB/DE/VS latency %0d",n);
   pv1=pv0;pv0=vs;pd1=pd0;pd0=de;pr1=pr0;pr0=bg;
  end
  $display("PASS real dual-clock names RAM, SFN compact names and tilde, 6-row metadata fetch, 13/32-file pages, types/play marker/highlight, empty/scanning/closed and RGB/DE/VS 3-stage alignment");$finish;
 end
 initial begin #1000000;$fatal(1,"Timeout");end
endmodule
