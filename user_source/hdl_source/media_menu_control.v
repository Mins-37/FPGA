// The browser never changes the current stream until confirmation.
module media_menu_control(
 input wire clk,rst,toggle,next_n,prev_n,auto_n,
 input wire ready,input wire [5:0] count,input wire [4:0] current_index,
 input wire command_ack,
 output reg opened,output reg [4:0] selected,output wire [4:0] page_base,
 output wire player_next_n,player_prev_n,player_auto_n,
 output reg command_toggle,output reg [4:0] command_index
);
 reg old_next,old_prev,old_auto,old_ready,guard;
 wire next_event=old_next && !next_n,prev_event=old_prev && !prev_n,confirm=old_auto && !auto_n;
 wire blocked=opened || guard || toggle;
 assign player_next_n=blocked ? 1'b1:next_n;
 assign player_prev_n=blocked ? 1'b1:prev_n;
 assign player_auto_n=blocked ? 1'b1:auto_n;
 assign page_base=selected>=30 ? 5'd30:selected>=24 ? 5'd24:selected>=18 ? 5'd18:selected>=12 ? 5'd12:selected>=6 ? 5'd6:5'd0;
 always @(posedge clk or posedge rst) begin
  if(rst)begin opened<=0;selected<=0;old_next<=1;old_prev<=1;old_auto<=1;old_ready<=0;guard<=1;command_toggle<=0;command_index<=0;end
  else begin
   old_next<=next_n;old_prev<=prev_n;old_auto<=auto_n;old_ready<=ready;
   if(next_n && prev_n && auto_n)guard<=0;
   if(toggle)begin
    opened<=~opened;guard<=1;
    if(!opened)selected<=ready && {1'b0,current_index}<count ? current_index:5'd0;
   end else if(opened)begin
    if(!ready || count==0)selected<=0;
    else if(!old_ready || {1'b0,selected}>=count)selected<=({1'b0,current_index}<count) ? current_index:5'd0;
    else begin
     if(next_event)selected<=({1'b0,selected}+6'd1>=count) ? 5'd0:selected+5'd1;
     if(prev_event)selected<=selected==0 ? count[4:0]-5'd1:selected-5'd1;
     if(confirm && command_ack==command_toggle)begin command_index<=selected;command_toggle<=~command_toggle;opened<=0;guard<=1;end
    end
   end
  end
 end
endmodule

// Bundled index remains stable until the destination acknowledges its toggle.
module media_jump_cdc(
 input wire src_clk,src_rst,request,input wire [4:0] index,output wire acknowledge,
 input wire dst_clk,dst_rst,output reg valid,output reg [4:0] target
);
 reg [2:0] request_sync;reg ack;reg [1:0] ack_sync;
 assign acknowledge=ack_sync[1];
 always @(posedge src_clk or posedge src_rst)if(src_rst)ack_sync<=0;else ack_sync<={ack_sync[0],ack};
 always @(posedge dst_clk or posedge dst_rst)begin
  if(dst_rst)begin request_sync<=0;ack<=0;valid<=0;target<=0;end
  else begin
   request_sync<={request_sync[1:0],request};valid<=0;
   if(request_sync[2]!=ack)begin target<=index;valid<=1;ack<=request_sync[2];end
  end
 end
endmodule

module media_name_ram(
 input wire wr_clk,we,input wire [8:0] wr_addr,input wire [7:0] wr_data,
 input wire rd_clk,input wire [8:0] rd_addr,output reg [7:0] rd_data
);
 (* ram_style="bram" *) reg [7:0] names[0:511];
 always @(posedge wr_clk)if(we)names[wr_addr]<=wr_data;
 always @(posedge rd_clk)rd_data<=names[rd_addr];
endmodule
