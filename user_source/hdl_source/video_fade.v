// Fade-through-black, 32 frame steps each way. Runs only on the picture layer.
// SD controller holds a completed background image until black has been synchronized.
// Then three black frames allow the frame reader to select/refill the new buffer.
module video_fade #(parameter SETTLE_FRAMES=3)(
 input wire clk,input wire rst,input wire image_valid,input wire load_busy,input wire bypass,
 input wire in_vs,input wire in_de,input wire [23:0] in_rgb,
 output reg out_vs,output reg out_de,output reg [23:0] out_rgb,output wire black
);
 localparam IDLE=0,FADE_OUT=1,WAIT_BLACK=2,FADE_IN=3;
 reg [1:0] state;
 reg [5:0] gain;
 reg [2:0] settling;
 reg vs_d;
 wire frame_edge=in_vs && !vs_d;
 assign black=(gain==0);
 always @(posedge clk or posedge rst) begin
  if(rst) begin state<=WAIT_BLACK;gain<=0;settling<=0;vs_d<=0;end
  else begin
   vs_d<=in_vs;
   if(frame_edge) begin
    if(!image_valid) begin state<=WAIT_BLACK;gain<=0;settling<=0;end
    else if(bypass) begin state<=IDLE;gain<=32;settling<=0;end
    else case(state)
     IDLE: begin
      gain<=32;
      if(load_busy) state<=FADE_OUT;
     end
     FADE_OUT: begin
      if(!load_busy) state<=FADE_IN; // aborted load: restore the current image
      else if(gain>1) gain<=gain-1'b1;
      else begin gain<=0;settling<=0;state<=WAIT_BLACK;end
     end
     WAIT_BLACK: begin
      gain<=0;
      if(load_busy) settling<=0;
      else if(settling==SETTLE_FRAMES-1) begin settling<=0;state<=FADE_IN;end
      else settling<=settling+1'b1;
     end
     FADE_IN: begin
      if(load_busy) state<=FADE_OUT;
      else if(gain<32) gain<=gain+1'b1;
      else state<=IDLE;
     end
     default:begin state<=WAIT_BLACK;gain<=0;settling<=0;end
    endcase
   end
  end
 end
 reg vs1,de1;
 reg [13:0] red_product,green_product,blue_product;
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   vs1<=0;de1<=0;red_product<=0;green_product<=0;blue_product<=0;
   out_vs<=0;out_de<=0;out_rgb<=0;
  end else begin
   vs1<=in_vs;de1<=in_de;
   red_product<=in_rgb[23:16]*gain;
   green_product<=in_rgb[15:8]*gain;
   blue_product<=in_rgb[7:0]*gain;
   out_vs<=vs1;out_de<=de1;
   out_rgb<=de1 ? {red_product[12:5],green_product[12:5],blue_product[12:5]} : 24'd0;
  end
 end
endmodule
