// Contiguous 24-bit BI_RGB BMP -> 640x480, aspect-fit, nearest-neighbour.
// One synchronous source-line cache; emits TOP-DOWN pixels (writer V_FLIP=0).
module bmp_read(
 input wire clk,rst,output wire ready,
 input wire scan_start,input wire [31:0] scan_start_sector,scan_max_sector,
 input wire [2:0] scan_target_count,output reg scan_done,scan_found_valid,
 output reg [31:0] scan_found_sector,output reg [2:0] scan_found_total,
 input wire load_start,load_abort,input wire [31:0] load_sector,
 input wire sd_init_done,output reg [3:0] state_code,
 input wire [15:0] bmp_width,bmp_height,
 output reg write_req,input wire write_req_ack,
 output reg sd_sec_read,output reg [31:0] sd_sec_read_addr,
 input wire [7:0] sd_sec_read_data,input wire sd_sec_read_data_valid,sd_sec_read_end,
 output reg bmp_data_wr_en,output reg [23:0] bmp_data
);
 localparam IDLE=0,SCAN_ISSUE=1,SCAN_WAIT=2,HDR_ISSUE=3,HDR_WAIT=4,
 VA=5,VB=6,VC=7,GEOMETRY=8,DIV_WAIT=9,GEOM_FINISH=10,WRITE_ACK=11,
 ROW_SELECT=12,ROW_MULT=13,ROW_ADD=14,ROW_READ=15,ROW_WAIT=16,
 PIX_FETCH=17,PIX_EMIT=18,X_ADV=19,PIX_HOLD=20,ROW_END=21,Y_ADV=22,WRITE_RELEASE=23,HDR_SUM=24,HDR_CHECK=25;
 reg [4:0] state;
 reg checking_scan;
 reg [31:0] scan_sector,load_base,requested_sector;
 reg read_start,sector_done;
 reg [1:0] reader_state;
 reg [8:0] byte_index;
 // Each sector request is held until completion, followed by a low gap.
 always @(posedge clk or posedge rst) begin
  if(rst) begin reader_state<=0;sd_sec_read<=0;sd_sec_read_addr<=0;sector_done<=0;byte_index<=0;end
  else if(!sd_init_done || load_abort) begin reader_state<=0;sd_sec_read<=0;sector_done<=0;byte_index<=0;end
  else begin
   sector_done<=0;
   case(reader_state)
    0:begin
     sd_sec_read<=0;
     if(read_start) begin sd_sec_read_addr<=requested_sector;byte_index<=0;sd_sec_read<=1;reader_state<=1;end
    end
    1:begin
     if(sd_sec_read_data_valid) byte_index<=byte_index+1'b1;
     if(sd_sec_read_end) begin sd_sec_read<=0;reader_state<=2;end
    end
    2:begin sector_done<=1;reader_state<=0;end
    default:begin reader_state<=0;sd_sec_read<=0;end
   endcase
  end
 end
 reg [7:0] magic0,magic1;
 reg [31:0] file_len,pixel_offset,dib_size,width,height,compression;
 reg [15:0] planes,bit_count;
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   magic0<=0;magic1<=0;file_len<=0;pixel_offset<=0;dib_size<=0;
   width<=0;height<=0;planes<=0;bit_count<=0;compression<=0;
  end else if((state==SCAN_WAIT || state==HDR_WAIT) && reader_state==1 && sd_sec_read_data_valid) begin
   case(byte_index)
    0:magic0<=sd_sec_read_data;1:magic1<=sd_sec_read_data;
    2:file_len[7:0]<=sd_sec_read_data;3:file_len[15:8]<=sd_sec_read_data;
    4:file_len[23:16]<=sd_sec_read_data;5:file_len[31:24]<=sd_sec_read_data;
    10:pixel_offset[7:0]<=sd_sec_read_data;11:pixel_offset[15:8]<=sd_sec_read_data;
    12:pixel_offset[23:16]<=sd_sec_read_data;13:pixel_offset[31:24]<=sd_sec_read_data;
    14:dib_size[7:0]<=sd_sec_read_data;15:dib_size[15:8]<=sd_sec_read_data;
    16:dib_size[23:16]<=sd_sec_read_data;17:dib_size[31:24]<=sd_sec_read_data;
    18:width[7:0]<=sd_sec_read_data;19:width[15:8]<=sd_sec_read_data;
    20:width[23:16]<=sd_sec_read_data;21:width[31:24]<=sd_sec_read_data;
    22:height[7:0]<=sd_sec_read_data;23:height[15:8]<=sd_sec_read_data;
    24:height[23:16]<=sd_sec_read_data;25:height[31:24]<=sd_sec_read_data;
    26:planes[7:0]<=sd_sec_read_data;27:planes[15:8]<=sd_sec_read_data;
    28:bit_count[7:0]<=sd_sec_read_data;29:bit_count[15:8]<=sd_sec_read_data;
    30:compression[7:0]<=sd_sec_read_data;31:compression[15:8]<=sd_sec_read_data;
    32:compression[23:16]<=sd_sec_read_data;33:compression[31:24]<=sd_sec_read_data;
   endcase
  end
 end
 reg [31:0] abs_height,stride;
 reg [23:0] payload_bytes;
 reg [31:0] required_bytes; reg header_valid;
 wire header_ok=magic0==8'h42 && magic1==8'h4d && width>=1 && width<=1920 &&
  abs_height>=1 && abs_height<=1080 && planes==1 && bit_count==24 && compression==0 &&
  dib_size>=40 && dib_size<=124 && pixel_offset>=54 && pixel_offset>=14+dib_size &&
  pixel_offset<=4096 && file_len>=required_bytes && file_len<=32'd16777216;
 wire [31:0] next_scan=header_valid ? scan_sector+((file_len+511)>>9) : scan_sector+1'b1;
 reg div_start,fit_width;
 reg [19:0] dividend;
 reg [10:0] divisor;
 wire div_done;
 wire [19:0] quotient;
 bmp_div20 divider(.clk(clk),.rst(rst|load_abort|!sd_init_done),.start(div_start),
  .dividend(dividend),.divisor(divisor),.done(div_done),.quotient(quotient));
 reg [9:0] scaled_w,scaled_h,x_offset,y_offset,out_x,out_y;
 reg [10:0] source_x,source_y,cached_y,physical_row,fill_x;
 reg [12:0] x_acc,y_acc,remaining;
 reg cache_valid,row_black;
 reg [23:0] row_product;
 reg [31:0] row_file_byte;
 reg [8:0] skip;
 reg [1:0] byte_phase;
 reg [7:0] blue,green;
 reg [23:0] line_buffer[0:2047];
 reg [23:0] line_pixel;
 always @(posedge clk) line_pixel<=line_buffer[source_x];
 wire active_x=out_x>=x_offset && out_x<x_offset+scaled_w;
 wire active_y=out_y>=y_offset && out_y<y_offset+scaled_h;
 assign ready=state==IDLE;
 always @* begin
  if(state==IDLE) state_code=1;
  else if(state<=GEOM_FINISH) state_code=2;
  else if(state==WRITE_ACK) state_code=3;
  else state_code=4;
 end
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   state<=IDLE;checking_scan<=0;scan_sector<=0;load_base<=0;
   scan_done<=0;scan_found_valid<=0;scan_found_sector<=0;scan_found_total<=0;
   read_start<=0;requested_sector<=0;write_req<=0;bmp_data_wr_en<=0;bmp_data<=0;
   abs_height<=0;stride<=0;payload_bytes<=0;required_bytes<=0;header_valid<=0;div_start<=0;dividend<=0;divisor<=1;fit_width<=0;
   scaled_w<=640;scaled_h<=480;x_offset<=0;y_offset<=0;out_x<=0;out_y<=0;
   source_x<=0;source_y<=0;cached_y<=0;physical_row<=0;x_acc<=0;y_acc<=0;
   cache_valid<=0;row_black<=1;row_product<=0;row_file_byte<=0;
   skip<=0;remaining<=0;fill_x<=0;byte_phase<=0;blue<=0;green<=0;
  end else begin
   read_start<=0;div_start<=0;bmp_data_wr_en<=0;scan_found_valid<=0;
   if(!sd_init_done) begin
    state<=IDLE;scan_done<=0;scan_found_total<=0;write_req<=0;cache_valid<=0;
   end else if(load_abort) begin
    // A load abort must preserve the completed scan catalogue.
    state<=IDLE;write_req<=0;cache_valid<=0;
   end else case(state)
    IDLE:begin
     write_req<=0;
     if(scan_start) begin checking_scan<=1;scan_sector<=scan_start_sector;scan_done<=0;scan_found_total<=0;state<=SCAN_ISSUE;end
     else if(load_start) begin checking_scan<=0;load_base<=load_sector;state<=HDR_ISSUE;end
    end
    SCAN_ISSUE:begin requested_sector<=scan_sector;read_start<=1;state<=SCAN_WAIT;end
    SCAN_WAIT:if(sector_done) state<=VA;
    HDR_ISSUE:begin requested_sector<=load_base;read_start<=1;state<=HDR_WAIT;end
    HDR_WAIT:if(sector_done) state<=VA;
    VA:begin abs_height<=height[31] ? (~height+1'b1) : height;stride<=(width*3+3)&32'hfffffffc;state<=VB;end
    VB:begin payload_bytes<=stride[12:0]*abs_height[10:0];state<=HDR_SUM;end
    HDR_SUM:begin required_bytes<=pixel_offset+payload_bytes;state<=HDR_CHECK;end
    HDR_CHECK:begin header_valid<=header_ok;state<=VC;end
    VC:begin
     if(checking_scan) begin
      if(header_valid) begin scan_found_valid<=1;scan_found_sector<=scan_sector;scan_found_total<=scan_found_total+1'b1;end
      if((header_valid && scan_found_total+1'b1>=scan_target_count) || scan_sector>=scan_max_sector || next_scan>scan_max_sector) begin
       scan_done<=1;state<=IDLE;
      end else begin scan_sector<=next_scan;state<=SCAN_ISSUE;end
     end else if(header_valid) state<=GEOMETRY;
     else state<=IDLE;
    end
    GEOMETRY:begin
     if(width[10:0]*20'd480 >= abs_height[10:0]*20'd640) begin
      scaled_w<=640;dividend<=abs_height[10:0]*20'd640;divisor<=width[10:0];fit_width<=1;
     end else begin scaled_h<=480;dividend<=width[10:0]*20'd480;divisor<=abs_height[10:0];fit_width<=0;end
     div_start<=1;state<=DIV_WAIT;
    end
    DIV_WAIT:if(div_done) begin
     if(fit_width) scaled_h<=quotient==0 ? 10'd1 : quotient[9:0];
     else scaled_w<=quotient==0 ? 10'd1 : quotient[9:0];
     state<=GEOM_FINISH;
    end
    GEOM_FINISH:begin x_offset<=(640-scaled_w)>>1;y_offset<=(480-scaled_h)>>1;write_req<=1;cache_valid<=0;state<=WRITE_ACK;end
    WRITE_ACK:if(write_req_ack) begin write_req<=0;state<=WRITE_RELEASE;end
    // The memory-domain FIFO remains in reset until the request drops.
    // Wait for the synchronized acknowledgement to drop before emitting pixels.
    WRITE_RELEASE:if(!write_req_ack) begin out_y<=0;source_y<=0;y_acc<=0;state<=ROW_SELECT;end
    ROW_SELECT:begin
     out_x<=0;source_x<=0;x_acc<=0;row_black<=!active_y;
     if(!active_y || (cache_valid && cached_y==source_y)) state<=PIX_FETCH;
     else begin physical_row<=height[31] ? source_y : abs_height[10:0]-1'b1-source_y;state<=ROW_MULT;end
    end
    ROW_MULT:begin row_product<=physical_row*stride[12:0];state<=ROW_ADD;end
    ROW_ADD:begin row_file_byte<=pixel_offset+row_product;state<=ROW_READ;end
    ROW_READ:begin
     requested_sector<=load_base+(row_file_byte>>9);skip<=row_file_byte[8:0];
     remaining<=width[10:0]*3;fill_x<=0;byte_phase<=0;read_start<=1;state<=ROW_WAIT;
    end
    ROW_WAIT:begin
     if(sd_sec_read_data_valid && reader_state==1) begin
      if(skip!=0) skip<=skip-1'b1;
      else if(remaining!=0) begin
       remaining<=remaining-1'b1;
       case(byte_phase)
        0:begin blue<=sd_sec_read_data;byte_phase<=1;end
        1:begin green<=sd_sec_read_data;byte_phase<=2;end
        2:begin line_buffer[fill_x]<={sd_sec_read_data,green,blue};fill_x<=fill_x+1'b1;byte_phase<=0;end
       endcase
      end
     end
     if(sector_done) begin
      if(remaining==0) begin cache_valid<=1;cached_y<=source_y;state<=PIX_FETCH;end
      else begin requested_sector<=requested_sector+1'b1;read_start<=1;end
     end
    end
    PIX_FETCH:state<=PIX_EMIT;
    PIX_EMIT:begin
     bmp_data<=(!row_black && active_x) ? line_pixel : 24'd0;bmp_data_wr_en<=1;
     if(out_x==639) state<=ROW_END;
     else begin out_x<=out_x+1'b1;if(!row_black && active_x) x_acc<=x_acc+width[10:0];state<=X_ADV;end
    end
    X_ADV:begin
     if(!row_black && x_acc>=scaled_w) begin x_acc<=x_acc-scaled_w;source_x<=source_x+1'b1;end
     else state<=PIX_HOLD;
    end
    PIX_HOLD:state<=PIX_FETCH;
    ROW_END:begin
     if(out_y==479) state<=IDLE;
     else begin out_y<=out_y+1'b1;if(active_y) begin y_acc<=y_acc+abs_height[10:0];state<=Y_ADV;end else state<=ROW_SELECT;end
    end
    Y_ADV:begin
     if(y_acc>=scaled_h) begin y_acc<=y_acc-scaled_h;source_y<=source_y+1'b1;end
     else state<=ROW_SELECT;
    end
    default:begin state<=IDLE;write_req<=0;end
   endcase
  end
 end
endmodule

// Iterative divider: small 12-bit subtract path, 20 clocks per geometry calculation.
module bmp_div20(input wire clk,rst,start,input wire [19:0] dividend,
 input wire [10:0] divisor,output reg done,output reg [19:0] quotient);
 reg busy;
 reg [19:0] work;
 reg [10:0] denominator;
 reg [11:0] remainder;
 reg [4:0] count;
 wire [11:0] shifted={remainder[10:0],work[19]};
 wire subtract=shifted>={1'b0,denominator};
 wire [19:0] next_work={work[18:0],subtract};
 always @(posedge clk or posedge rst) begin
  if(rst) begin busy<=0;done<=0;quotient<=0;work<=0;denominator<=1;remainder<=0;count<=0;end
  else begin
   done<=0;
   if(start && !busy) begin busy<=1;work<=dividend;denominator<=divisor;remainder<=0;count<=0;end
   else if(busy) begin
    work<=next_work;remainder<=subtract ? shifted-{1'b0,denominator} : shifted;
    if(count==19) begin quotient<=next_work;done<=1;busy<=0;end else count<=count+1'b1;
   end
  end
 end
endmodule
