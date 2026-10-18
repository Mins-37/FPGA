// Two registered compositor stages. RGB/DE/VS share the same latency.
// 5x7 glyphs scaled 2x; translucent panels retain the underlying picture.
module video_osd #(parameter CLK_HZ=25000000, ENABLE_CLEAN=0)(
 input wire clk,input wire rst,input wire in_vs,input wire in_de,
 input wire [3:0] volume,input wire muted,
 input wire [9:0] elapsed_tenths,total_tenths,input wire [8:0] progress_fill,input wire progress_valid,
 input wire [23:0] in_rgb,input wire [16:0] status,input wire [3:0] controls,input wire [7:0] debug_status,
 output reg out_vs,output reg out_de,output reg [23:0] out_rgb, input wire hide_overlays
);
 reg hide_frame;
 reg vs_d,de_d;
 reg [9:0] x,y;
 reg [24:0] second_count;
 reg [3:0] h10,h1,m10,m1,s10,s1;
 reg [3:0] h10f,h1f,m10f,m1f,s10f,s1f;
 reg [15:0] elapsed_digits,total_digits;reg [8:0] progress_frame;reg progress_visible;
 reg [16:0] status_frame;
 reg [3:0] controls_frame;reg [3:0] volume_frame;reg muted_frame;
 reg [3:0] idx_tens,idx_ones,count_tens,count_ones;
 wire [5:0] shown_index={1'b0,status[4:0]}+1'b1;
 function [3:0] tens(input [5:0] n); begin tens=n>=30 ? 3 : n>=20 ? 2 : n>=10 ? 1 : 0;end endfunction
 function [3:0] ones(input [5:0] n); begin ones=n>=30 ? n-30 : n>=20 ? n-20 : n>=10 ? n-10 : n;end endfunction
 function [15:0] time_digits(input [9:0] n);
 reg [9:0] r;reg [3:0] m,st,so,tenth;
 begin
  m=n>=600 ? 1:0;r=n>=600 ? n-600:n;
  st=r>=500 ? 5:r>=400 ? 4:r>=300 ? 3:r>=200 ? 2:r>=100 ? 1:0;r=r-st*10'd100;
  so=r>=90 ? 9:r>=80 ? 8:r>=70 ? 7:r>=60 ? 6:r>=50 ? 5:r>=40 ? 4:r>=30 ? 3:r>=20 ? 2:r>=10 ? 1:0;tenth=r-so*10'd10;
  time_digits={m,st,so,tenth};
 end endfunction
 function [7:0] progress_char(input [5:0] col);
 begin case(col)
  0,10:progress_char="0";
  1:progress_char="0"+elapsed_digits[15:12];
  2,12:progress_char=":";
  3:progress_char="0"+elapsed_digits[11:8];
  4:progress_char="0"+elapsed_digits[7:4];
  5,15:progress_char=".";
  6:progress_char="0"+elapsed_digits[3:0];
  8:progress_char="/";
  11:progress_char="0"+total_digits[15:12];
  13:progress_char="0"+total_digits[11:8];
  14:progress_char="0"+total_digits[7:4];
  16:progress_char="0"+total_digits[3:0];
  default:progress_char=" ";
 endcase end endfunction
 reg [7:0] debug_frame;
 reg [9:0] scroll;
 wire frame_edge=in_vs && !vs_d;
 localparam MESSAGE_WIDTH=672;
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   hide_frame<=0;vs_d<=0;de_d<=0;x<=0;y<=0;second_count<=0;
   h10<=0;h1<=0;m10<=0;m1<=0;s10<=0;s1<=0;
   h10f<=0;h1f<=0;m10f<=0;m1f<=0;s10f<=0;s1f<=0;
   elapsed_digits<=0;total_digits<=0;progress_frame<=0;progress_visible<=0;status_frame<=0;volume_frame<=8;muted_frame<=0;idx_tens<=0;idx_ones<=0;count_tens<=0;count_ones<=0;scroll<=0;controls_frame<=0;debug_frame<=0;
  end else begin
   vs_d<=in_vs;de_d<=in_de;
   if(in_vs!=vs_d) begin x<=0;y<=0;end
   else if(in_de) x<=x+1'b1;
   else begin x<=0;if(de_d) y<=y+1'b1;end
   if(frame_edge) begin
    hide_frame<=ENABLE_CLEAN && hide_overlays;
    elapsed_digits<=time_digits(elapsed_tenths);total_digits<=time_digits(total_tenths);progress_frame<=progress_fill;progress_visible<=progress_valid && status[15];
    idx_tens<=tens(shown_index);idx_ones<=ones(shown_index);count_tens<=tens(status[10:5]);count_ones<=ones(status[10:5]);
    status_frame<=status;volume_frame<=volume;muted_frame<=muted;controls_frame<=controls;debug_frame<=debug_status;
    h10f<=h10;h1f<=h1;m10f<=m10;m1f<=m1;s10f<=s10;s1f<=s1;
    scroll <= scroll==MESSAGE_WIDTH-1 ? 0 : scroll+1'b1;
   end
   if(second_count==CLK_HZ-1) begin
    second_count<=0;
    if(s1!=9) s1<=s1+1'b1;
    else begin s1<=0;
     if(s10!=5) s10<=s10+1'b1;
     else begin s10<=0;
      if(m1!=9) m1<=m1+1'b1;
      else begin m1<=0;
       if(m10!=5) m10<=m10+1'b1;
       else begin m10<=0;
        if(h1!=9) h1<=h1+1'b1;
        else begin h1<=0;h10<=h10==9 ? 0 : h10+1'b1;end
       end
      end
     end
    end
   end else second_count<=second_count+1'b1;
  end
 end
 function [34:0] glyph(input [7:0] c);
 begin case(c)
8'd46: glyph=35'b00000000000000000000000000010000100;
8'd43: glyph=35'b00000001000010011111001000010000000;
8'd45: glyph=35'b00000000000000011111000000000000000;
8'd47: glyph=35'b00001000100001000100010000100010000;
8'd48: glyph=35'b01110100011001110101110011000101110;
8'd49: glyph=35'b00100011000010000100001000010001110;
8'd50: glyph=35'b01110100010000100010001000100011111;
8'd51: glyph=35'b11110000010000101110000010000111110;
8'd52: glyph=35'b00010001100101010010111110001000010;
8'd53: glyph=35'b11111100001000011110000010000111110;
8'd54: glyph=35'b01110100001000011110100011000101110;
8'd55: glyph=35'b11111000010001000100010000100001000;
8'd56: glyph=35'b01110100011000101110100011000101110;
8'd57: glyph=35'b01110100011000101111000010000101110;
8'd58: glyph=35'b00000001000010000000001000010000000;
8'd65: glyph=35'b01110100011000111111100011000110001;
8'd66: glyph=35'b11110100011000111110100011000111110;
8'd67: glyph=35'b01110100011000010000100001000101110;
8'd68: glyph=35'b11110100011000110001100011000111110;
8'd69: glyph=35'b11111100001000011110100001000011111;
8'd70: glyph=35'b11111100001000011110100001000010000;
8'd71: glyph=35'b01110100011000010111100011000101110;
8'd72: glyph=35'b10001100011000111111100011000110001;
8'd73: glyph=35'b11111001000010000100001000010011111;
8'd75: glyph=35'b10001100101010011000101001001010001;
8'd76: glyph=35'b10000100001000010000100001000011111;
8'd77: glyph=35'b10001110111010110101100011000110001;
8'd78: glyph=35'b10001110011010110011100011000110001;
8'd79: glyph=35'b01110100011000110001100011000101110;
8'd80: glyph=35'b11110100011000111110100001000010000;
8'd82: glyph=35'b11110100011000111110101001001010001;
8'd83: glyph=35'b01111100001000001110000010000111110;
8'd84: glyph=35'b11111001000010000100001000010000100;
8'd85: glyph=35'b10001100011000110001100011000101110;
8'd86: glyph=35'b10001100011000110001100010101000100;
8'd87: glyph=35'b10001100011000110101101011101110001;
8'd88: glyph=35'b10001100010101000100010101000110001;
8'd89: glyph=35'b10001100010101000100001000010000100;
8'd90: glyph=35'b11111000010001000100010001000011111;
8'd124: glyph=35'b00100001000010000100001000010000100;
8'd37: glyph=35'b11001110100001000100010001001100011;
 default:glyph=0;
 endcase end endfunction
 function [7:0] header_char(input [5:0] col);
 begin case(col)
6'd0: header_char=8'd85;
6'd1: header_char=8'd80;
6'd2: header_char=8'd32;
6'd3: header_char=8'd48 + h10f;
6'd4: header_char=8'd48 + h1f;
6'd5: header_char=8'd58;
6'd6: header_char=8'd48 + m10f;
6'd7: header_char=8'd48 + m1f;
6'd8: header_char=8'd58;
6'd9: header_char=8'd48 + s10f;
6'd10: header_char=8'd48 + s1f;
6'd11: header_char=8'd32;
6'd12: header_char=8'd32;
6'd13: header_char=status_frame[16] ? 8'd86 : status_frame[15] ? 8'd87 : status_frame[14] ? 8'd65 : 8'd73;
6'd14: header_char=status_frame[16] ? 8'd73 : status_frame[15] ? 8'd65 : status_frame[14] ? 8'd78 : 8'd77;
6'd15: header_char=status_frame[16] ? 8'd68 : status_frame[15] ? 8'd86 : status_frame[14] ? 8'd77 : 8'd71;
6'd16: header_char=8'd32;
6'd17: header_char=(status_frame[13] || status_frame[15]) ? 8'd48+idx_tens : 8'd45;
6'd18: header_char=(status_frame[13] || status_frame[15]) ? 8'd48+idx_ones : 8'd45;
6'd19: header_char=8'd47;
6'd20: header_char=8'd48+count_tens;
6'd21: header_char=8'd48+count_ones;
6'd22: header_char=8'd32;
6'd23: header_char=(status_frame[14] || status_frame[15]) ? (8'd80) : (status_frame[11] ? 8'd65 : 8'd77);
6'd24: header_char=(status_frame[14] || status_frame[15]) ? (status_frame[11] ? 8'd76 : 8'd65) : (status_frame[11] ? 8'd85 : 8'd65);
6'd25: header_char=(status_frame[14] || status_frame[15]) ? (status_frame[11] ? 8'd65 : 8'd85) : (status_frame[11] ? 8'd84 : 8'd78);
6'd26: header_char=(status_frame[14] || status_frame[15]) ? (status_frame[11] ? 8'd89 : 8'd83) : (status_frame[11] ? 8'd79 : 8'd85);
6'd27: header_char=(status_frame[14] || status_frame[15]) ? (status_frame[11] ? 8'd32 : 8'd69) : (status_frame[11] ? 8'd32 : 8'd65);
6'd28: header_char=(status_frame[14] || status_frame[15]) ? (8'd32) : (status_frame[11] ? 8'd32 : 8'd76);
 default:header_char=8'd32;
 endcase end endfunction
 function [7:0] slogan_char(input [5:0] col);
 begin case(col)
6'd0: slogan_char=8'd72;
6'd1: slogan_char=8'd88;
6'd2: slogan_char=8'd52;
6'd3: slogan_char=8'd83;
6'd4: slogan_char=8'd50;
6'd5: slogan_char=8'd48;
6'd6: slogan_char=8'd32;
6'd7: slogan_char=8'd124;
6'd8: slogan_char=8'd32;
6'd9: slogan_char=8'd80;
6'd10: slogan_char=8'd72;
6'd11: slogan_char=8'd79;
6'd12: slogan_char=8'd84;
6'd13: slogan_char=8'd79;
6'd14: slogan_char=8'd32;
6'd15: slogan_char=8'd83;
6'd16: slogan_char=8'd76;
6'd17: slogan_char=8'd73;
6'd18: slogan_char=8'd68;
6'd19: slogan_char=8'd69;
6'd20: slogan_char=8'd83;
6'd21: slogan_char=8'd72;
6'd22: slogan_char=8'd79;
6'd23: slogan_char=8'd87;
6'd24: slogan_char=8'd32;
6'd25: slogan_char=8'd124;
6'd26: slogan_char=8'd32;
6'd27: slogan_char=8'd72;
6'd28: slogan_char=8'd68;
6'd29: slogan_char=8'd77;
6'd30: slogan_char=8'd73;
6'd31: slogan_char=8'd32;
6'd32: slogan_char=8'd86;
6'd33: slogan_char=8'd73;
6'd34: slogan_char=8'd68;
6'd35: slogan_char=8'd69;
6'd36: slogan_char=8'd79;
6'd37: slogan_char=8'd32;
6'd38: slogan_char=8'd43;
6'd39: slogan_char=8'd32;
6'd40: slogan_char=8'd52;
6'd41: slogan_char=8'd56;
6'd42: slogan_char=8'd75;
6'd43: slogan_char=8'd72;
6'd44: slogan_char=8'd90;
6'd45: slogan_char=8'd32;
6'd46: slogan_char=8'd65;
6'd47: slogan_char=8'd85;
6'd48: slogan_char=8'd68;
6'd49: slogan_char=8'd73;
6'd50: slogan_char=8'd79;
6'd51: slogan_char=8'd32;
6'd52: slogan_char=8'd124;
6'd53: slogan_char=8'd32;
6'd54: slogan_char=8'd32;
6'd55: slogan_char=8'd32;
 default:slogan_char=8'd32;
 endcase end endfunction
 function [7:0] control_char(input [5:0] col);
 begin case(col)
6'd0: control_char=8'd66;
6'd1: control_char=8'd82;
6'd2: control_char=8'd73;
6'd3: control_char=8'd32;
6'd4: control_char=controls_frame[1:0]==2'd2 ? 8'd45 : 8'd43;
6'd5: control_char=controls_frame[1:0]==0 ? 8'd48 : (controls_frame[1:0]==3 ? 8'd54 : 8'd51);
6'd6: control_char=controls_frame[1:0]==0 ? 8'd48 : (controls_frame[1:0]==3 ? 8'd52 : 8'd50);
6'd7: control_char=8'd32;
6'd8: control_char=8'd32;
6'd9: control_char=8'd32;
6'd10: control_char=8'd67;
6'd11: control_char=8'd79;
6'd12: control_char=8'd78;
6'd13: control_char=8'd32;
6'd14: control_char=controls_frame[3:2]==1 ? 8'd48 : 8'd49;
6'd15: control_char=controls_frame[3:2]==0 ? 8'd48 : (controls_frame[3:2]==1 ? 8'd55 : (controls_frame[3:2]==2 ? 8'd50 : 8'd53));
6'd16: control_char=(controls_frame[3:2]==1 || controls_frame[3:2]==2) ? 8'd53 : 8'd48;
6'd17: control_char=8'd37;
 default:control_char=8'd32;
 endcase end endfunction
 function [7:0] debug_char(input [5:0] col);
 begin case(col)
6'd0: debug_char=8'd75;
6'd1: debug_char=8'd50;
6'd2: debug_char=8'd58;
6'd3: debug_char=8'd48 + {7'd0,debug_frame[0]} ;
6'd4: debug_char=8'd32;
6'd5: debug_char=8'd75;
6'd6: debug_char=8'd52;
6'd7: debug_char=8'd58;
6'd8: debug_char=8'd48 + {7'd0,debug_frame[1]} ;
6'd9: debug_char=8'd32;
6'd10: debug_char=8'd66;
6'd11: debug_char=8'd85;
6'd12: debug_char=8'd83;
6'd13: debug_char=8'd89;
6'd14: debug_char=8'd58;
6'd15: debug_char=8'd48 + {7'd0,debug_frame[2]} ;
6'd16: debug_char=8'd32;
6'd17: debug_char=8'd69;
6'd18: debug_char=8'd82;
6'd19: debug_char=8'd82;
6'd20: debug_char=8'd58;
6'd21: debug_char=8'd48 + {7'd0,debug_frame[3]} ;
 default:debug_char=8'd32;
 endcase end endfunction
 function [7:0] wave_label(input [5:0] col);
 begin case(col)
6'd0: wave_label=8'd65;
6'd1: wave_label=8'd85;
6'd2: wave_label=8'd68;
6'd3: wave_label=8'd73;
6'd4: wave_label=8'd79;
6'd5: wave_label=8'd32;
6'd6: wave_label=8'd52;
6'd7: wave_label=8'd56;
6'd8: wave_label=8'd75;
 default:wave_label=8'd32;
 endcase end endfunction
 function [7:0] volume_char(input [5:0] col);
 begin case(col)
  0:volume_char="V";1:volume_char="O";2:volume_char="L";
  4:volume_char=volume_frame==8 ? "1":" ";
  5:case(volume_frame)
   1:volume_char="1";2:volume_char="2";3:volume_char="3";4:volume_char="5";
   5:volume_char="6";6:volume_char="7";7:volume_char="8";default:volume_char="0";
  endcase
  6:case(volume_frame)
   1,5:volume_char="3";2,6:volume_char="5";3,7:volume_char="8";default:volume_char="0";
  endcase
  7:volume_char="%";
  9:volume_char=muted_frame ? "M":" ";10:volume_char=muted_frame ? "U":" ";
  11:volume_char=muted_frame ? "T":" ";12:volume_char=muted_frame ? "E":" ";
  default:volume_char=" ";
 endcase end endfunction
 function [7:0] spectrum_char(input [5:0] col);
 begin case(col)
  0:spectrum_char="S";1:spectrum_char="P";2:spectrum_char="E";3:spectrum_char="C";
  5:spectrum_char="0";6:spectrum_char=".";7:spectrum_char="2";
  8:spectrum_char="-";9:spectrum_char="1";10:spectrum_char="8";11:spectrum_char="K";
  default:spectrum_char=" ";
 endcase end endfunction
 reg [10:0] text_pos,wrapped;
 reg [9:0] text_row;
 reg [7:0] ch;
 reg [34:0] bits;
 reg [3:0] gx,gy;
 reg panel,pixel;
 reg [23:0] mix;
 always @* begin
  text_pos=0;wrapped=0;text_row=0;ch=32;bits=0;gx=0;gy=0;
  panel=0;pixel=0;mix=in_rgb;
  if(y>=8 && y<40) begin
   panel=1;
   if(x>=16 && x<16+348 && y>=16 && y<30) begin
    text_pos=x-16;text_row=y-16;
    ch=header_char(text_pos/12);gx=(text_pos%12)>>1;gy=text_row>>1;
   end else if(x>=400 && x<556 && y>=16 && y<30) begin
    text_pos=x-400;text_row=y-16;ch=volume_char(text_pos/12);gx=(text_pos%12)>>1;gy=text_row>>1;
   end
  end else if(y>=48 && y<80) begin
   panel=1;
   if(x>=16 && x<232 && y>=56 && y<70) begin
    text_pos=x-16;text_row=y-56;
    ch=control_char(text_pos/12);gx=(text_pos%12)>>1;gy=text_row>>1;
   end else if(x>=304 && x<568 && y>=56 && y<70) begin
    text_pos=x-304;text_row=y-56;
    ch=debug_char(text_pos/12);gx=(text_pos%12)>>1;gy=text_row>>1;
   end
  end else if(y>=224 && y<238 && x>=472 && x<616) begin
   panel=1;text_pos=x-472;text_row=y-224;ch=spectrum_char(text_pos/12);gx=(text_pos%12)>>1;gy=text_row>>1;
  end else if(y>=320 && y<334 && x>=472 && x<580) begin
   panel=1;text_pos=x-472;text_row=y-320;
   ch=wave_label(text_pos/12);gx=(text_pos%12)>>1;gy=text_row>>1;
  end else if(progress_visible && x>=16 && x<440 && y>=390 && y<432) begin
   panel=1;
   if(x>=24 && x<228 && y>=396 && y<410) begin
    text_pos=x-24;text_row=y-396;ch=progress_char(text_pos/12);gx=(text_pos%12)>>1;gy=text_row>>1;
   end
  end else if(y>=440 && y<472) begin
   panel=1;
   if(y>=448 && y<462) begin
    text_pos={1'b0,x}+{1'b0,scroll};
    wrapped=text_pos>=MESSAGE_WIDTH ? text_pos-MESSAGE_WIDTH : text_pos;
    text_row=y-448;ch=slogan_char(wrapped/12);
    gx=(wrapped%12)>>1;gy=text_row>>1;
   end
  end

  if(panel) mix={2'b00,in_rgb[23:18],2'b00,in_rgb[15:10],2'b00,in_rgb[7:2]};
  if(progress_visible && x>=22 && x<426 && y>=416 && y<428) begin
   mix=24'h7DE8FF;
   if(x>=24 && x<424 && y>=418 && y<426) mix=x<24+progress_frame ? (status_frame[11] ? 24'h65E0AD : 24'hFFE7A3) : 24'h253546;
  end

 end
 reg vs1,de1,panel1,top1;
 reg [23:0] mix1;
 reg [7:0] ch1;
 reg [3:0] gx1,gy1;
 wire [34:0] font_bits=glyph(ch1);
 wire ink=(gx1<5 && gy1<7) ? font_bits[34-gy1*5-gx1] : 1'b0;
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   vs1<=0;de1<=0;panel1<=0;top1<=0;mix1<=0;ch1<=32;gx1<=0;gy1<=0;
   out_vs<=0;out_de<=0;out_rgb<=0;
  end else begin
   vs1<=in_vs;de1<=in_de;panel1<=panel && !hide_frame;top1<=y<40;
   mix1<=hide_frame ? in_rgb : mix;ch1<=ch;gx1<=gx;gy1<=gy;
   out_vs<=vs1;out_de<=de1;
   out_rgb<=de1 ? ((ink && panel1) ? (top1 ? 24'hFFE7A3 : 24'h7DE8FF) : mix1) : 24'd0;
  end
 end
endmodule
