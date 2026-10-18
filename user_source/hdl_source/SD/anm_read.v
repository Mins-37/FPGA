// HXA1: 512-byte header + frames of 160x120 little-endian RGB565.
// Each frame is exactly 75 sectors. One sector cache plus one source-line cache.
// Expand 4x in each direction into the existing 640x480 SDRAM framebuffer.
module anm_read(
 input wire clk,rst,load_start,load_abort,av_mode,
 output reg metadata_valid,frame_is_highres,
 input wire [31:0] load_sector,input wire [15:0] frame_index,
 output wire ready,output reg error,
 output reg [15:0] frame_count,output reg [7:0] frame_rate,
 output reg write_req,input wire write_req_ack,pixel_ready,
 output reg sd_sec_read,output reg [31:0] sd_sec_read_addr,
 input wire [7:0] sd_sec_read_data,input wire sd_sec_read_data_valid,sd_sec_read_end,
 output reg bmp_data_wr_en,output reg [23:0] bmp_data
);
 localparam IDLE=0,HDR_ISSUE=1,HDR_WAIT=2,HDR_CHECK=3,FRAME_BASE=4,
 WRITE_ACK=5,WRITE_RELEASE=6,LINE_FETCH=7,SECTOR_WAIT=8,LINE_WORD=9,
 PIX_FETCH=10,PIX_EMIT=11,PIX_HOLD1=12,PIX_HOLD2=13,PIX_ADV=14,HDR_MUL=15,HDR_SIZE=16,HDR_PRECHECK=17;
 reg [4:0] state;reg [31:0] base;reg [15:0] selected_frame,frame_sectors,frame_offset;
 reg [24:0] expected_bytes;reg header_shape_ok,header_size_ok,header_audio_bad;
 reg issue,io_done;reg [1:0] io_state;reg [31:0] request_sector;
 reg [8:0] byte_index;reg [7:0] low_byte;
 reg [31:0] magic,frame_bytes,total_bytes,av_tag,av_rate;reg [15:0] av_channels,av_bits;
 reg [15:0] width,height,fps,frames,format,version;
 (* ram_style="bram" *) reg [15:0] sector_words[0:255];
 (* ram_style="bram" *) reg [15:0] line_words[0:255];
 reg [15:0] sector_q,line_q;
 reg cache_valid;reg [31:0] data_sector,cached_sector;
 reg [7:0] word_offset,fill_x,source_row,display_source_x;reg [2:0] horizontal_phase;
 reg [9:0] out_x;reg [1:0] repeat_row;
 wire [4:0] r5=line_q[15:11],b5=line_q[4:0];wire [5:0] g6=line_q[10:5];
 assign ready=state==IDLE;
 always @(posedge clk) begin
  sector_q<=sector_words[word_offset];
  line_q<=line_words[frame_is_highres ? display_source_x : out_x[9:2]];
  if(io_state==1 && sd_sec_read_data_valid && byte_index[0])
   sector_words[byte_index[8:1]]<={sd_sec_read_data,low_byte};
  if(state==LINE_WORD) line_words[fill_x]<=sector_q;
 end
 always @(posedge clk or posedge rst) begin
  if(rst) begin io_state<=0;sd_sec_read<=0;sd_sec_read_addr<=0;io_done<=0;byte_index<=0;low_byte<=0;end
  else if(load_abort) begin io_state<=0;sd_sec_read<=0;io_done<=0;byte_index<=0;end
  else begin
   io_done<=0;
   case(io_state)
    0:if(issue) begin sd_sec_read_addr<=request_sector;sd_sec_read<=1;byte_index<=0;io_state<=1;end
    1:begin
     if(sd_sec_read_data_valid) begin
      byte_index<=byte_index+1'b1;
      if(!byte_index[0]) low_byte<=sd_sec_read_data;
     end
     if(sd_sec_read_end) begin sd_sec_read<=0;io_state<=2;end
    end
    2:begin io_done<=1;io_state<=0;end
   endcase
  end
 end
 // Header fields are streamed separately from the sector cache.
 always @(posedge clk or posedge rst) begin
  if(rst) begin av_tag<=0;av_rate<=0;av_channels<=0;av_bits<=0;magic<=0;width<=0;height<=0;fps<=0;frames<=0;frame_bytes<=0;total_bytes<=0;format<=0;version<=0;end
  else if(state==HDR_WAIT && io_state==1 && sd_sec_read_data_valid) begin
   case(byte_index)
    0:magic[7:0]<=sd_sec_read_data;1:magic[15:8]<=sd_sec_read_data;2:magic[23:16]<=sd_sec_read_data;3:magic[31:24]<=sd_sec_read_data;
    4:width[7:0]<=sd_sec_read_data;5:width[15:8]<=sd_sec_read_data;
    6:height[7:0]<=sd_sec_read_data;7:height[15:8]<=sd_sec_read_data;
    8:fps[7:0]<=sd_sec_read_data;9:fps[15:8]<=sd_sec_read_data;
    10:frames[7:0]<=sd_sec_read_data;11:frames[15:8]<=sd_sec_read_data;
    12:frame_bytes[7:0]<=sd_sec_read_data;13:frame_bytes[15:8]<=sd_sec_read_data;14:frame_bytes[23:16]<=sd_sec_read_data;15:frame_bytes[31:24]<=sd_sec_read_data;
    16:total_bytes[7:0]<=sd_sec_read_data;17:total_bytes[15:8]<=sd_sec_read_data;18:total_bytes[23:16]<=sd_sec_read_data;19:total_bytes[31:24]<=sd_sec_read_data;
    20:format[7:0]<=sd_sec_read_data;21:format[15:8]<=sd_sec_read_data;
    22:version[7:0]<=sd_sec_read_data;23:version[15:8]<=sd_sec_read_data;
    24:av_tag[7:0]<=sd_sec_read_data;25:av_tag[15:8]<=sd_sec_read_data;26:av_tag[23:16]<=sd_sec_read_data;27:av_tag[31:24]<=sd_sec_read_data;
    28:av_rate[7:0]<=sd_sec_read_data;29:av_rate[15:8]<=sd_sec_read_data;30:av_rate[23:16]<=sd_sec_read_data;31:av_rate[31:24]<=sd_sec_read_data;
    32:av_channels[7:0]<=sd_sec_read_data;33:av_channels[15:8]<=sd_sec_read_data;
    34:av_bits[7:0]<=sd_sec_read_data;35:av_bits[15:8]<=sd_sec_read_data;
   endcase
  end
 end
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   header_shape_ok<=0;header_size_ok<=0;header_audio_bad<=0;frame_is_highres<=0;display_source_x<=0;horizontal_phase<=0;metadata_valid<=0;state<=IDLE;base<=0;selected_frame<=0;frame_sectors<=0;frame_offset<=0;expected_bytes<=0;issue<=0;request_sector<=0;error<=0;
   frame_count<=0;frame_rate<=10;write_req<=0;bmp_data_wr_en<=0;bmp_data<=0;
   cache_valid<=0;data_sector<=0;cached_sector<=0;word_offset<=0;fill_x<=0;source_row<=0;out_x<=0;repeat_row<=0;
  end else begin
   metadata_valid<=0;issue<=0;error<=0;bmp_data_wr_en<=0;
   if(load_abort) begin state<=IDLE;write_req<=0;cache_valid<=0;end
   else case(state)
    IDLE:if(load_start) begin base<=load_sector;selected_frame<=frame_index;frame_offset<=0;state<=HDR_ISSUE;end
    HDR_ISSUE:begin request_sector<=base;issue<=1;state<=HDR_WAIT;end
    HDR_WAIT:if(io_done) state<=HDR_MUL;
    HDR_MUL:begin frame_sectors<=width==256 ? frames[8:0]*16'd192 : frames[8:0]*16'd75;frame_offset<=width==256 ? selected_frame[8:0]*16'd192+16'd1 : selected_frame[8:0]*16'd75+16'd1;state<=HDR_SIZE;end
    HDR_SIZE:begin expected_bytes<={frame_sectors,9'd0}+25'd512;state<=HDR_PRECHECK;end
    HDR_PRECHECK:begin
     header_shape_ok<=magic==32'h31415848 && ((width==160 && height==120) || (width==256 && height==192)) &&
      (width!=256 || frames<=140) && (fps==5 || fps==10) && frames>=1 && frames<=400 &&
      frame_bytes==(width==256 ? 32'd98304 : 32'd38400) && format==1 && version==1;
     header_size_ok<=selected_frame<frames && total_bytes=={7'd0,expected_bytes};
     header_audio_bad<=av_mode && (fps!=10 || av_tag!=32'h314d5641 || av_rate!=48000 || av_channels!=2 || av_bits!=16);
     state<=HDR_CHECK;
    end
    HDR_CHECK:begin
     if(!header_shape_ok || !header_size_ok || header_audio_bad) begin error<=1;state<=IDLE;end
     else begin frame_is_highres<=width==256;metadata_valid<=1;frame_count<=frames;frame_rate<=fps[7:0];state<=FRAME_BASE;end
    end
    FRAME_BASE:begin
     data_sector<=base+frame_offset;cache_valid<=0;word_offset<=0;
     display_source_x<=0;horizontal_phase<=0;fill_x<=0;source_row<=0;write_req<=1;state<=WRITE_ACK;
    end
    WRITE_ACK:if(write_req_ack) begin write_req<=0;state<=WRITE_RELEASE;end
    WRITE_RELEASE:if(!write_req_ack) state<=LINE_FETCH;
    LINE_FETCH:begin
     if(!cache_valid || cached_sector!=data_sector) begin request_sector<=data_sector;issue<=1;state<=SECTOR_WAIT;end
     else state<=LINE_WORD;
    end
    SECTOR_WAIT:if(io_done) begin cache_valid<=1;cached_sector<=data_sector;state<=LINE_FETCH;end
    LINE_WORD:begin
     if(word_offset==255) begin word_offset<=0;data_sector<=data_sector+1'b1;end
     else word_offset<=word_offset+1'b1;
     if(fill_x==(frame_is_highres ? 8'd255 : 8'd159)) begin out_x<=0;repeat_row<=0;state<=PIX_FETCH;end
     else begin fill_x<=fill_x+1'b1;state<=LINE_FETCH;end
    end
    PIX_FETCH:state<=PIX_EMIT;
    PIX_EMIT:if(pixel_ready) begin
     bmp_data<={r5,r5[4:2],g6,g6[5:4],b5,b5[4:2]};bmp_data_wr_en<=1;state<=PIX_HOLD1;
    end
    PIX_HOLD1:state<=PIX_HOLD2;
    PIX_HOLD2:state<=PIX_ADV;
    PIX_ADV:begin
     if(out_x==639) begin
      out_x<=0;display_source_x<=0;horizontal_phase<=0;
      if(repeat_row!=(frame_is_highres ? (source_row[0] ? 2'd1 : 2'd2) : 2'd3)) begin repeat_row<=repeat_row+1'b1;state<=PIX_FETCH;end
      else if(source_row==(frame_is_highres ? 8'd191 : 8'd119)) state<=IDLE;
      else begin source_row<=source_row+1'b1;fill_x<=0;state<=LINE_FETCH;end
     end else begin out_x<=out_x+1'b1;state<=PIX_FETCH;
      if(frame_is_highres) begin if(horizontal_phase==2 || horizontal_phase==4) display_source_x<=display_source_x+1'b1;horizontal_phase<=horizontal_phase==4 ? 3'd0 : horizontal_phase+1'b1;end
     end
    end
    default:begin state<=IDLE;write_req<=0;end
   endcase
  end
 end
endmodule
