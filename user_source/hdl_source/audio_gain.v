// Stereo signed 24-bit gain; 0..8 = 0..100%. A 256-sample ramp avoids hard steps.
// Data and valid share two pipeline registers. HDMI ACR and source consumption stay unchanged.
module audio_gain(
 input wire clk,rst,input wire sample_valid,input wire signed [23:0] left_in,right_in,
 input wire [3:0] volume,input wire mute,
 output reg out_valid,output reg signed [23:0] left_out,right_out
);
 reg [8:0] gain;
 wire [8:0] target=mute ? 9'd0 : (volume>=8 ? 9'd256 : {volume[2:0],5'd0});
 reg signed [33:0] left_product,right_product;
 reg valid_d;
 always @(posedge clk or posedge rst) begin
  if(rst) begin gain<=256;valid_d<=0;out_valid<=0;left_product<=0;right_product<=0;left_out<=0;right_out<=0;end
  else begin
   valid_d<=sample_valid;out_valid<=valid_d;
   if(sample_valid) begin
    if(gain<target) gain<=gain+1'b1;else if(gain>target) gain<=gain-1'b1;
    left_product<=left_in*$signed({1'b0,gain});right_product<=right_in*$signed({1'b0,gain});
   end
   if(valid_d) begin left_out<=left_product>>>8;right_out<=right_product>>>8;end
  end
 end
endmodule
