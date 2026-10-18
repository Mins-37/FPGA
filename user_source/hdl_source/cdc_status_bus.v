// Bundled-data toggle/ack handshake. Source data stays stable until acknowledged.
module cdc_status_bus #(parameter WIDTH=8)(
 input wire src_clk,input wire src_rst,input wire [WIDTH-1:0] src_data,
 input wire dst_clk,input wire dst_rst,output reg [WIDTH-1:0] dst_data
);
 reg [WIDTH-1:0] held;
 reg req,ack;
 reg [1:0] ack_sync;
 reg [2:0] req_sync;
 always @(posedge src_clk or posedge src_rst) begin
  if(src_rst) begin held<=0;req<=0;ack_sync<=0;end
  else begin
   ack_sync<={ack_sync[0],ack};
   if(req==ack_sync[1] && held!=src_data) begin held<=src_data;req<=~req;end
  end
 end
 always @(posedge dst_clk or posedge dst_rst) begin
  if(dst_rst) begin req_sync<=0;ack<=0;dst_data<=0;end
  else begin
   req_sync<={req_sync[1:0],req};
   if(req_sync[2]!=ack) begin dst_data<=held;ack<=req_sync[2];end
  end
 end
endmodule
