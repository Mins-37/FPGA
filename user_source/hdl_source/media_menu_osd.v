// Six-row SFN browser. A single byte-wide dual-clock name RAM is enough for 32 files.
// Row metadata is prefetched during vertical blank; text RAM/font/RGB have matched latency.
module media_menu_osd(
 input wire clk,rst,in_vs,in_de,input wire [23:0] in_rgb,
 input wire opened,ready,input wire [5:0] count,input wire [4:0] selected,page_base,current_index,
 output wire [8:0] name_addr,input wire [7:0] name_data,
 output reg out_vs,out_de,output reg [23:0] out_rgb
);
 reg vs_d,de_d;reg [9:0] x,y;
 reg open_f,ready_f;reg [5:0] count_f;reg [4:0] selected_f,base_f,current_f;
 reg [7:0] meta[0:5];reg [1:0] fetch_state;reg [2:0] fetch_row;
 wire edge_frame=in_vs && !vs_d;
 wire [4:0] fetch_index=base_f+fetch_row;
 reg [8:0] text_addr;
 assign name_addr=fetch_state!=0 ? {fetch_index,4'd11}:text_addr;
 integer r;
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   vs_d<=0;de_d<=0;x<=0;y<=0;open_f<=0;ready_f<=0;count_f<=0;selected_f<=0;base_f<=0;current_f<=0;fetch_state<=0;fetch_row<=0;
   for(r=0;r<6;r=r+1)meta[r]<=0;
  end else begin
   vs_d<=in_vs;de_d<=in_de;
   if(in_vs!=vs_d)begin x<=0;y<=0;end
   else if(in_de)x<=x+1'b1;
   else begin x<=0;if(de_d)y<=y+1'b1;end
   if(edge_frame)begin
    open_f<=opened;ready_f<=ready;count_f<=count;selected_f<=selected;base_f<=page_base;current_f<=current_index;
    fetch_row<=0;fetch_state<=opened && ready && count!=0 ? 1:0;
   end else case(fetch_state)
    1:fetch_state<=2;
    2:begin meta[fetch_row]<=name_data;if(fetch_row==5)fetch_state<=0;else begin fetch_row<=fetch_row+1'b1;fetch_state<=1;end end
    default:fetch_state<=0;
   endcase
  end
 end
 function [3:0] tens(input [5:0] n);begin tens=n>=30 ? 3:n>=20 ? 2:n>=10 ? 1:0;end endfunction
 function [3:0] ones(input [5:0] n);begin ones=n>=30 ? n-30:n>=20 ? n-20:n>=10 ? n-10:n;end endfunction
 function [2:0] page_number(input [4:0] n);begin page_number=n>=30 ? 5:n>=24 ? 4:n>=18 ? 3:n>=12 ? 2:n>=6 ? 1:0;end endfunction
 function [7:0] thumb_size(input [5:0] n);begin thumb_size=n>30 ? 30:n>24 ? 36:n>18 ? 45:n>12 ? 60:n>6 ? 90:180;end endfunction
 wire [7:0] scroll_size=thumb_size(count_f);
 wire [9:0] scroll_top=10'd156+page_number(base_f)*scroll_size;
 wire [5:0] first_number=count_f==0 ? 0:{1'b0,base_f}+6'd1;
 wire [5:0] last_number=({1'b0,base_f}+6'd6>count_f) ? count_f:{1'b0,base_f}+6'd6;
 function [7:0] info_char(input [5:0] col);
 begin case(col)
  0:info_char="0"+tens(count_f);1:info_char="0"+ones(count_f);
  3:info_char="F";4:info_char="I";5:info_char="L";6:info_char="E";7:info_char="S";
  10:info_char="0"+tens(first_number);11:info_char="0"+ones(first_number);12:info_char="-";
  13:info_char="0"+tens(last_number);14:info_char="0"+ones(last_number);
  default:info_char=" ";
 endcase end endfunction
 function [7:0] title_char(input [5:0] col);
 begin case(col)
  0:title_char=8'd77;
  1:title_char=8'd69;
  2:title_char=8'd68;
  3:title_char=8'd73;
  4:title_char=8'd65;
  6:title_char=8'd76;
  7:title_char=8'd73;
  8:title_char=8'd66;
  9:title_char=8'd82;
  10:title_char=8'd65;
  11:title_char=8'd82;
  12:title_char=8'd89;
  default:title_char=" ";
 endcase end endfunction
 function [7:0] footer_char(input [5:0] col);
 begin case(col)
  0:footer_char=8'd75;
  1:footer_char=8'd50;
  3:footer_char=8'd68;
  4:footer_char=8'd79;
  5:footer_char=8'd87;
  6:footer_char=8'd78;
  8:footer_char=8'd75;
  9:footer_char=8'd51;
  11:footer_char=8'd85;
  12:footer_char=8'd80;
  14:footer_char=8'd75;
  15:footer_char=8'd52;
  17:footer_char=8'd80;
  18:footer_char=8'd76;
  19:footer_char=8'd65;
  20:footer_char=8'd89;
  default:footer_char=" ";
 endcase end endfunction
 function [7:0] close_char(input [5:0] col);
 begin case(col)
  0:close_char=8'd72;
  1:close_char=8'd79;
  2:close_char=8'd76;
  3:close_char=8'd68;
  5:close_char=8'd75;
  6:close_char=8'd50;
  7:close_char=8'd43;
  8:close_char=8'd75;
  9:close_char=8'd51;
  11:close_char=8'd84;
  12:close_char=8'd79;
  14:close_char=8'd67;
  15:close_char=8'd76;
  16:close_char=8'd79;
  17:close_char=8'd83;
  18:close_char=8'd69;
  default:close_char=" ";
 endcase end endfunction
 function [7:0] scan_char(input [5:0] col);
 begin case(col)
  0:scan_char=8'd83;
  1:scan_char=8'd67;
  2:scan_char=8'd65;
  3:scan_char=8'd78;
  4:scan_char=8'd78;
  5:scan_char=8'd73;
  6:scan_char=8'd78;
  7:scan_char=8'd71;
  8:scan_char=8'd46;
  9:scan_char=8'd46;
  10:scan_char=8'd46;
  default:scan_char=" ";
 endcase end endfunction
 function [7:0] empty_char(input [5:0] col);
 begin case(col)
  0:empty_char=8'd78;
  1:empty_char=8'd79;
  3:empty_char=8'd77;
  4:empty_char=8'd69;
  5:empty_char=8'd68;
  6:empty_char=8'd73;
  7:empty_char=8'd65;
  default:empty_char=" ";
 endcase end endfunction

 function [7:0] kind_char(input [1:0] kind,input [1:0] col);
 begin case(kind)
  0:case(col)0:kind_char="B";1:kind_char="M";default:kind_char="P";endcase
  1:case(col)0:kind_char="A";1:kind_char="N";default:kind_char="M";endcase
  2:case(col)0:kind_char="W";1:kind_char="A";default:kind_char="V";endcase
  3:case(col)0:kind_char="V";1:kind_char="I";default:kind_char="D";endcase
 endcase end endfunction
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
8'd74:glyph=35'b00111000100001000010100101001001100;
8'd81:glyph=35'b01110100011000110001101011001001101;
8'd95:glyph=35'b00000000000000000000000000000011111;
8'd126:glyph=35'b00000010011011000000000000000000000;
8'd32:glyph=0;
default:glyph=35'b01110100010001000100001000000000100;
 endcase end endfunction
 reg [23:0] mix,ink_color;reg [7:0] ch;reg name_char;reg [3:0] gx,gy;
 reg [10:0] text_pos;reg [9:0] text_y,row_start;reg [5:0] col,number;reg [4:0] file_index;
 reg [3:0] length,display_col;reg [7:0] row_meta;
 reg is_row,selected_row,playing_row;integer row_id;
 always @*begin
  mix=in_rgb;ink_color=24'h7DE8FF;ch=32;name_char=0;gx=0;gy=0;text_addr=0;
  text_pos=0;text_y=0;col=0;number=0;file_index=0;length=0;display_col=0;row_meta=0;
  is_row=0;selected_row=0;playing_row=0;row_start=0;
  if(open_f && x>=16 && x<304 && y>=96 && y<384)begin
   mix={2'b00,in_rgb[23:18],2'b00,in_rgb[15:10],2'b00,in_rgb[7:2]};
   if(x==16 || x==303 || y==96 || y==383 || y==152 || y==338)mix=24'h7DE8FF;
   if(x>=28 && x<292)begin
    text_pos=x-28;col=text_pos/12;gx=(text_pos%12)>>1;
    if(y>=108 && y<122)begin ch=title_char(col);text_y=y-108;gy=text_y>>1;end
    else if(y>=132 && y<146)begin ch=info_char(col);text_y=y-132;gy=text_y>>1;end
    else if(y>=344 && y<358)begin ch=footer_char(col);text_y=y-344;gy=text_y>>1;end
    else if(y>=364 && y<378)begin ch=close_char(col);text_y=y-364;gy=text_y>>1;end
   end
   if(!ready_f && x>=32 && x<248 && y>=164 && y<178)begin
    text_pos=x-32;col=text_pos/12;gx=(text_pos%12)>>1;text_y=y-164;gy=text_y>>1;ch=scan_char(col);
   end else if(ready_f && count_f==0 && x>=32 && x<248 && y>=164 && y<178)begin
    text_pos=x-32;col=text_pos/12;gx=(text_pos%12)>>1;text_y=y-164;gy=text_y>>1;ch=empty_char(col);
   end else if(ready_f && count_f!=0)begin
    for(row_id=0;row_id<6;row_id=row_id+1)begin
     if(y>=158+row_id*30 && y<184+row_id*30 && {1'b0,base_f}+row_id<count_f)begin
      is_row=1;row_start=164+row_id*30;file_index=base_f+row_id;row_meta=meta[row_id];length=row_meta[5:2];
      number={1'b0,file_index}+6'd1;selected_row=file_index==selected_f;playing_row=file_index==current_f;
     end
    end
    if(is_row)begin
     if(selected_row && x>=24 && x<292)begin
      mix=24'h164858;ink_color=24'hFFFFFF;
      if(x==24 || x==291 || y==row_start-6 || y==row_start+19)mix=24'h7DE8FF;
     end else if(playing_row)ink_color=24'h70EE80;
     if(playing_row && x>=26 && x<34 && y>=row_start+2 && y<row_start+12 && x-26<8-((y>row_start+6) ? y-row_start-6:row_start+6-y))mix=24'h70EE80;
     if(x>=32 && x<272 && y>=row_start && y<row_start+14)begin
      text_pos=x-32;col=text_pos/12;gx=(text_pos%12)>>1;text_y=y-row_start;gy=text_y>>1;
      case(col)
       1:ch="0"+tens(number);2:ch="0"+ones(number);
       4,5,6,7,8,9,10,11,12,13,14,15:begin
        display_col=col-4;
        if(display_col<length)begin name_char=1;text_addr={file_index,display_col};end
        else if(display_col==length)ch=".";
        else if(display_col<=length+3)begin name_char=1;text_addr={file_index,4'd8+(display_col-length-1'b1)};end
        else ch=32;
       end
       17,18,19:ch=kind_char(row_meta[1:0],col-17);
       default:ch=32;
      endcase
     end
    end
    if(x>=296 && x<300 && y>=156 && y<336)begin
     mix=24'h24505D;if(y>=scroll_top && y<scroll_top+scroll_size)mix=24'h7DE8FF;
    end
   end
  end
 end
 reg [23:0] mix0,mix1,color0,color1;reg vs0,vs1,de0,de1,name0;
 reg [7:0] ch0,ch1;reg [3:0] gx0,gx1,gy0,gy1;
 wire [7:0] normalized_name=(name_data>=97 && name_data<=122) ? name_data-8'd32:name_data;
 wire [34:0] bits=glyph(ch1);
 wire ink=(gx1<5 && gy1<7) ? bits[34-gy1*5-gx1]:1'b0;
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   mix0<=0;mix1<=0;color0<=0;color1<=0;vs0<=0;vs1<=0;de0<=0;de1<=0;name0<=0;ch0<=32;ch1<=32;gx0<=0;gx1<=0;gy0<=0;gy1<=0;out_vs<=0;out_de<=0;out_rgb<=0;
  end else begin
   mix0<=mix;color0<=ink_color;vs0<=in_vs;de0<=in_de;name0<=name_char;ch0<=ch;gx0<=gx;gy0<=gy;
   mix1<=mix0;color1<=color0;vs1<=vs0;de1<=de0;ch1<=name0 ? normalized_name:ch0;gx1<=gx0;gy1<=gy0;
   out_vs<=vs1;out_de<=de1;out_rgb<=de1 ? (ink ? color1:mix1):24'd0;
  end
 end
endmodule
