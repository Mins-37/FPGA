// Eight real frequency measurements from the HDMI left channel, not an animated pattern.
// 256-sample rectangular Goertzel windows at 48kHz. A shared multiplier processes all bins.
// Centers: 187.5,375,750,1500,3000,6000,12000,18000Hz. Q14 coefficients.
module audio_spectrum(
 input wire clk,rst,sample_valid,input wire signed [23:0] pcm,
 output reg [63:0] levels,output reg overrun,output wire levels_stable
);
 // No asynchronous reset on state memories: infer small synchronous RAMs.
 // For 256 signed 8-bit inputs, |state| < 256*129/sin(acos(32758/32768))
 // < 1.34 million including truncation error: signed 22 bits has ample headroom.
 (* ram_style="bram" *) reg signed [21:0] z1[0:7],z2[0:7];
 reg signed [21:0] a,b,next_z,real_part,imag_part;
 reg signed [15:0] coefficient;
 reg signed [37:0] product;
 reg signed [7:0] sample;
 reg [7:0] count;reg [2:0] bin;reg [3:0] state;
 assign levels_stable=state<5;
 integer j;
 function signed [15:0] twice_cos(input [2:0] n);
 begin case(n)
  0:twice_cos=32758;1:twice_cos=32729;2:twice_cos=32610;3:twice_cos=32138;
  4:twice_cos=30274;5:twice_cos=23170;6:twice_cos=0;7:twice_cos=-23170;
 endcase end endfunction
 function signed [15:0] sine(input [2:0] n);
 begin case(n)
  0:sine=402;1:sine=804;2:sine=1606;3:sine=3196;
  4:sine=6270;5:sine=11585;6:sine=16384;7:sine=11585;
 endcase end endfunction
 wire [21:0] abs_real=real_part[21] ? -real_part:real_part;
 wire [21:0] abs_imag=imag_part[21] ? -imag_part:imag_part;
 wire [22:0] magnitude={1'b0,abs_real}+{1'b0,abs_imag};
 wire signed [21:0] multiplier_a=state==2 ? a:b;
 always @(posedge clk) begin
  a<=z1[bin];b<=z2[bin];
  if(!rst) begin
   if(state==4) begin z1[bin]<=next_z;z2[bin]<=a;end
   else if(state==10 || state==11) begin z1[bin]<=0;z2[bin]<=0;end
  end
 end
 // Logarithmic display, four pixels per factor of two (~6dB), capped at 56px.
 function [7:0] height(input [24:0] mag);
 integer n;reg found;reg [7:0] h;
 begin h=0;found=0;
  for(n=15;n>=3;n=n-1) if(!found && mag[n]) begin
   found=1;h=(n-2)*4+((mag>>(n-2))&3);
  end
  height=(|mag[24:16]) ? 56:h;
 end endfunction
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   next_z<=0;real_part<=0;imag_part<=0;coefficient<=0;product<=0;
   sample<=0;count<=0;bin<=0;state<=11;levels<=0;overrun<=0;
  end else begin
   if(state==2 || state==6 || state==8) product<=multiplier_a*coefficient;
   if(sample_valid && state!=0) overrun<=1;
   case(state)
    0:if(sample_valid) begin sample<=pcm[23:16];bin<=0;state<=1;end
    1:begin coefficient<=twice_cos(bin);state<=2;end
    2:begin state<=3;end
    3:begin next_z<=$signed(sample)+(product>>>14)-b;state<=4;end
    4:begin
     if(bin==7) begin
      bin<=0;
      if(count==255) begin count<=0;state<=5;end
      else begin count<=count+1'b1;state<=0;end
     end else begin bin<=bin+1'b1;state<=1;end
    end
    5:begin coefficient<=twice_cos(bin)>>>1;state<=6;end
    6:begin state<=7;end
    7:begin real_part<=a-(product>>>14);coefficient<=sine(bin);state<=8;end
    8:begin state<=9;end
    9:begin imag_part<=product>>>14;state<=10;end
    10:begin
     levels[bin*8+:8]<=height(magnitude);
     if(bin==7) begin state<=0;end
     else begin bin<=bin+1'b1;state<=5;end
    end
    11:begin if(bin==7)begin bin<=0;state<=0;end else bin<=bin+1'b1;end
    default:state<=0;
   endcase
  end
 end
endmodule
