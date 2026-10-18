// Dual-clock FIFO. Gray pointers cross clocks; synchronous BRAM read prefetch.
module audio_pcm_fifo(input wire wr_clk,rd_clk,wr_rst,rd_rst,input wire push,input wire [31:0] din,
 input wire pop,output wire [31:0] dout,output wire empty,output wire [11:0] used);
 (* ram_style="bram" *) reg [31:0] mem[0:2047];
 reg [11:0] wb,rb,wg,rg;
 (* ASYNC_REG="TRUE" *) reg [11:0] rg1,rg2,wg1,wg2;
 reg [31:0] q; integer i;reg [11:0] synced_rb;
 always @* begin synced_rb[11]=rg2[11];for(i=10;i>=0;i=i-1) synced_rb[i]=synced_rb[i+1]^rg2[i];end
 assign used=wb-synced_rb;assign empty=rg==wg2;assign dout=q;
 always @(posedge wr_clk or posedge wr_rst) begin
  if(wr_rst) begin wb<=0;wg<=0;rg1<=0;rg2<=0;end
  else begin rg1<=rg;rg2<=rg1;if(push && used<2048) begin mem[wb[10:0]]<=din;wb<=wb+1'b1;wg<=((wb+12'd1)>>1)^(wb+12'd1);end end
 end
 always @(posedge rd_clk) q<=mem[rb[10:0]];
 always @(posedge rd_clk or posedge rd_rst) begin
  if(rd_rst) begin rb<=0;rg<=0;wg1<=0;wg2<=0;end
  else begin wg1<=wg;wg2<=wg1;if(pop && !empty) begin rb<=rb+1'b1;rg<=((rb+12'd1)>>1)^(rb+12'd1);end end
 end
endmodule

// Canonical RIFF/WAVE: PCM16 stereo 48000 Hz, 44-byte header. Loop data.
module wav_read(input wire clk,rst,start,abort,play,input wire [31:0] base_sector,
 output reg ready,error,output reg req,output reg [31:0] addr,
 input wire [7:0] data,input wire valid,sector_end,
 input wire [15:0] av_frame_count,output wire [31:0] av_position,
 output reg [21:0] playback_samples,output wire [21:0] total_audio_samples,
 input wire audio_clk,tick,output reg [23:0] left_pcm,right_pcm,output reg underrun);
 reg [3:0] state;reg header_ok_reg;
 (* ram_style="bram" *) reg [7:0] sector_bytes[0:511];reg [7:0] sector_q;reg [31:0] header_total;
 always @(posedge clk) begin sector_q<=sector_bytes[pos];if(state==2 && valid) sector_bytes[pos]<=data;end
 reg [8:0] pos;reg [31:0] sector,remaining,data_size;
 reg [7:0] header[0:43];reg [23:0] word_low;reg [1:0] sample_byte;
 reg push;reg [31:0] din;wire [31:0] dout;wire [11:0] used;wire empty;
 reg stream_valid;reg [1:0] play_sync;reg [1:0] valid_sync;
 wire fifo_reset=rst|abort;
 reg [1:0] wr_release,rd_release;
 always @(posedge clk or posedge fifo_reset) begin if(fifo_reset) wr_release<=3;else wr_release<={wr_release[0],1'b0};end
 always @(posedge audio_clk or posedge fifo_reset) begin if(fifo_reset) rd_release<=3;else rd_release<={rd_release[0],1'b0};end
 cdc_status_bus #(.WIDTH(22)) u_duration(.src_clk(clk),.src_rst(rst),.src_data(stream_valid ? data_size[23:2] : 22'd0),.dst_clk(audio_clk),.dst_rst(rst),.dst_data(total_audio_samples));
 always @(posedge audio_clk or posedge rd_release[1]) begin
  if(rd_release[1]) playback_samples<=0;
  else if(pop) playback_samples<=(total_audio_samples!=0 && playback_samples+1'b1>=total_audio_samples) ? 22'd0 : playback_samples+1'b1;
 end
 wire [15:0] av_frames_audio;
 reg [12:0] samples_in_frame;reg [15:0] av_epoch,av_frame;
 assign av_position={av_epoch,av_frame};
 cdc_status_bus #(.WIDTH(16)) u_av_frames(.src_clk(clk),.src_rst(rst),.src_data(av_frame_count),.dst_clk(audio_clk),.dst_rst(rst),.dst_data(av_frames_audio));
 always @(posedge audio_clk or posedge rd_release[1]) begin
  if(rd_release[1]) begin samples_in_frame<=0;av_epoch<=0;av_frame<=0;end
  else if(pop) begin
   if(samples_in_frame==4799) begin samples_in_frame<=0;av_epoch<=av_epoch+1'b1;av_frame<=(av_frame+1'b1>=av_frames_audio) ? 16'd0 : av_frame+1'b1;end
   else samples_in_frame<=samples_in_frame+1'b1;
  end
 end
 wire pop=tick && play_sync[1] && valid_sync[1] && !empty;
 audio_pcm_fifo fifo(.wr_clk(clk),.rd_clk(audio_clk),.wr_rst(wr_release[1]),.rd_rst(rd_release[1]),.push(push),.din(din),.pop(pop),.dout(dout),.empty(empty),.used(used));
 always @(posedge audio_clk or posedge rd_release[1]) begin
  if(rd_release[1]) begin play_sync<=0;valid_sync<=0;left_pcm<=0;right_pcm<=0;underrun<=0;end
  else begin
   play_sync<={play_sync[0],play};valid_sync<={valid_sync[0],stream_valid};
   if(tick) begin
    left_pcm<=0;right_pcm<=0;
    if(play_sync[1] && valid_sync[1]) begin
     if(!empty) begin left_pcm<={dout[15:0],8'd0};right_pcm<={dout[31:16],8'd0};end
     else underrun<=1;
    end
   end
  end
 end
 wire header_ok={header[3],header[2],header[1],header[0]}==32'h46464952 &&
 {header[7],header[6],header[5],header[4]}==header_total &&
 {header[11],header[10],header[9],header[8]}==32'h45564157 &&
 {header[15],header[14],header[13],header[12]}==32'h20746d66 &&
 {header[19],header[18],header[17],header[16]}==16 &&
 {header[21],header[20]}==1 && {header[23],header[22]}==2 &&
 {header[27],header[26],header[25],header[24]}==48000 &&
 {header[31],header[30],header[29],header[28]}==192000 &&
 {header[33],header[32]}==4 && {header[35],header[34]}==16 &&
 {header[39],header[38],header[37],header[36]}==32'h61746164 &&
 {header[43],header[42],header[41],header[40]}>=2048 &&
 {header[43],header[42],header[41],header[40]}<=16777172 && header[40][1:0]==0;
 always @(posedge clk or posedge rst) begin
  if(rst) begin header_ok_reg<=0;state<=0;pos<=0;sector<=0;remaining<=0;data_size<=0;sample_byte<=0;word_low<=0;push<=0;din<=0;req<=0;addr<=0;ready<=1;error<=0;stream_valid<=0;end
  else if(abort) begin state<=0;req<=0;ready<=1;error<=0;push<=0;stream_valid<=0;sample_byte<=0;end
  else begin
   push<=0;
   if(!ready && used>=512) begin ready<=1;stream_valid<=1;end
   case(state)
    0:if(start) begin sector<=0;remaining<=0;data_size<=0;sample_byte<=0;stream_valid<=0;ready<=0;error<=0;state<=1;end
    1:if(used<=1900) begin addr<=base_sector+sector;req<=1;pos<=0;state<=2;end
    2:begin
     if(valid) begin pos<=pos+1'b1;if(sector==0 && pos<44) header[pos]<=data;end
     if(sector_end) begin req<=0;pos<=0;if(sector==0) state<=3;else state<=7;end
    end
    3:begin header_total<={header[43],header[42],header[41],header[40]}+32'd36;state<=9;end
    9:begin header_ok_reg<=header_ok;state<=6;end
    6:begin
     if(header_ok_reg) begin data_size<={header[43],header[42],header[41],header[40]};remaining<={header[43],header[42],header[41],header[40]};pos<=44;state<=7;end
     else begin error<=1;ready<=1;state<=5;end
    end
    7:state<=8;
    8:begin
     if(remaining!=0) begin
      remaining<=remaining-1'b1;sample_byte<=sample_byte+1'b1;
      case(sample_byte) 0:word_low[7:0]<=sector_q;1:word_low[15:8]<=sector_q;2:word_low[23:16]<=sector_q;
       3:begin din<={sector_q,word_low};push<=1;end endcase
     end
     if(pos==511 || remaining<=1) state<=4;
     else begin pos<=pos+1'b1;state<=7;end
    end
    4:begin if(remaining==0) sector<=0;else sector<=sector+1'b1;state<=1;end
    5:begin end
    default:state<=0;
   endcase
  end
 end
endmodule

