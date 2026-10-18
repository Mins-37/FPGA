// Display-only arithmetic in the 25MHz pixel domain. Three restoring divides
// share one engine; outputs update together. Time comes from consumed PCM.
module media_progress(input wire clk,rst,active,input wire [21:0] played,duration,
 output reg [9:0] elapsed_tenths,total_tenths,output reg [8:0] fill,output reg valid);
 reg busy;reg [1:0] phase;reg [5:0] bits_left;
 reg [31:0] numerator,denominator,quotient;
 reg [32:0] remainder;
 reg [21:0] played_snapshot,duration_snapshot;
 reg [9:0] elapsed_hold,total_hold;
 wire [32:0] shifted={remainder[31:0],numerator[31]};
 wire subtract=shifted>={1'b0,denominator};
 wire [32:0] remainder_next=subtract ? shifted-{1'b0,denominator} : shifted;
 wire [31:0] quotient_next={quotient[30:0],subtract};
 always @(posedge clk or posedge rst) begin
  if(rst) begin busy<=0;phase<=0;bits_left<=0;numerator<=0;denominator<=1;quotient<=0;remainder<=0;
   played_snapshot<=0;duration_snapshot<=0;elapsed_hold<=0;total_hold<=0;elapsed_tenths<=0;total_tenths<=0;fill<=0;valid<=0;end
  else if(!active || duration==0) begin busy<=0;valid<=0;elapsed_tenths<=0;total_tenths<=0;fill<=0;end
  else if(!busy) begin
   played_snapshot<=played<duration ? played : duration;duration_snapshot<=duration;
   numerator<={10'd0,(played<duration ? played : duration)};denominator<=4800;quotient<=0;remainder<=0;bits_left<=32;phase<=0;busy<=1;
  end else begin
   numerator<={numerator[30:0],1'b0};quotient<=quotient_next;remainder<=remainder_next;bits_left<=bits_left-1'b1;
   if(bits_left==1) begin
    quotient<=0;remainder<=0;bits_left<=32;
    case(phase)
     0:begin elapsed_hold<=quotient_next[9:0];numerator<={10'd0,duration_snapshot};denominator<=4800;phase<=1;end
     1:begin total_hold<=quotient_next[9:0];numerator<=played_snapshot*32'd400;denominator<={10'd0,duration_snapshot};phase<=2;end
     2:begin elapsed_tenths<=elapsed_hold;total_tenths<=total_hold;fill<=quotient_next>400 ? 9'd400 : quotient_next[8:0];valid<=1;busy<=0;end
     default:busy<=0;
    endcase
   end
  end
 end
endmodule
