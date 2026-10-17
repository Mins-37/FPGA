// Four hardware switches, debounced as a vector. Settings apply at frame boundaries.
// SW2:SW1 brightness = 00:0, 01:+32, 10:-32, 11:+64.
// SW4:SW3 contrast = 00:100%, 01:75%, 10:125%, 11:150%.
module image_adjust #(parameter DEBOUNCE_CYCLES=125000)(
 input wire clk,input wire rst,input wire [3:0] sw,
 input wire in_vs,input wire in_de,input wire [23:0] in_rgb,
 output reg out_vs,output reg out_de,output reg [23:0] out_rgb,
 output reg [3:0] active_controls
);
 reg [3:0] sync0,sync1,candidate,stable;
 reg [16:0] debounce;
 reg vs_d;
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   sync0<=0;sync1<=0;candidate<=0;stable<=0;debounce<=0;
   vs_d<=0;active_controls<=0;
  end else begin
   sync0<=sw;sync1<=sync0;vs_d<=in_vs;
   if(sync1!=candidate) begin candidate<=sync1;debounce<=0;end
   else if(debounce<DEBOUNCE_CYCLES-1) debounce<=debounce+1'b1;
   else stable<=candidate;
   if(in_vs && !vs_d) active_controls<=stable;
  end
 end
 function [7:0] adjust(input [7:0] c,input [3:0] ctrl);
 reg signed [11:0] centered,product,brightness,result;
 begin
  centered=$signed({4'b0000,c})-12'sd128;
  case(ctrl[3:2])
   0:product=centered<<<2;
   1:product=(centered<<<1)+centered;
   2:product=(centered<<<2)+centered;
   default:product=(centered<<<2)+(centered<<<1);
  endcase
  case(ctrl[1:0])
   0:brightness=0;
   1:brightness=32;
   2:brightness=-32;
   default:brightness=64;
  endcase
  result=(product>>>2)+12'sd128+brightness;
  if(result<0) adjust=0;
  else if(result>255) adjust=255;
  else adjust=result[7:0];
 end endfunction
 always @(posedge clk or posedge rst) begin
  if(rst) begin out_vs<=0;out_de<=0;out_rgb<=0;end
  else begin
   out_vs<=in_vs;out_de<=in_de;
   if(in_de) out_rgb<={adjust(in_rgb[23:16],active_controls),
                      adjust(in_rgb[15:8],active_controls),
                      adjust(in_rgb[7:0],active_controls)};
   else out_rgb<=0;
  end
 end
endmodule
