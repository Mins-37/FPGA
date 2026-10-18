module sd_card_bmp #(parameter integer CLK_FREQ_HZ=100_000_000,parameter KEYS_PREDEBOUNCED=0,parameter ENABLE_MENU=0)(
 input wire audio_clk,audio_tick,output wire [23:0] wav_left,wav_right,output wire audio_mode,audio_underrun,
 output wire [21:0] playback_samples,total_audio_samples,
 input wire menu_jump_valid,input wire [4:0] menu_jump_index,
 output wire menu_name_valid,output wire [8:0] menu_name_addr,output wire [7:0] menu_name_data,output wire [6:0] menu_catalogue,
 input wire clk,rst,key_next,key_auto,key_prev,input wire [15:0] bmp_width,bmp_height,
 output reg display_valid,output wire [16:0] osd_status,output wire [7:0] osd_debug,
 output wire [3:0] state_code,
 input wire write_finish_toggle,fade_black,frame_sync,pixel_write_ready,
 input wire [1:0] reader_buffer_active,
 output reg [1:0] write_buf_idx,disp_buf_idx,
 output wire write_req,input wire write_req_ack,output wire write_en,output wire [31:0] write_data,
 output wire SD_nCS,SD_DCLK,SD_MOSI,input wire SD_MISO
);
 wire key_next_press,key_auto_press,key_prev_press;reg nav_previous;reg [1:0] nav_delay;reg [4:0] next_index_r,prev_index_r;
 generate if(KEYS_PREDEBOUNCED) begin:clean_keys
  key_event_sync p(.clk(clk),.rst(rst),.button_in(key_prev),.press_pulse(key_prev_press));
  key_event_sync n(.clk(clk),.rst(rst),.button_in(key_next),.press_pulse(key_next_press));
  key_event_sync a(.clk(clk),.rst(rst),.button_in(key_auto),.press_pulse(key_auto_press));
 end else begin:raw_keys
  key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(50)) u_key_prev(.clk(clk),.rst(rst),.button_in(key_prev),.press_pulse(key_prev_press));
  key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(50)) u_key_next(.clk(clk),.rst(rst),.button_in(key_next),.press_pulse(key_next_press));
  key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(50)) u_key_auto(.clk(clk),.rst(rst),.button_in(key_auto),.press_pulse(key_auto_press));
 end endgenerate
 reg nav_absolute;reg [4:0] nav_target;
 wire menu_command=ENABLE_MENU && menu_jump_valid && scan_done && {1'b0,menu_jump_index}<img_found_count;
 assign menu_catalogue={scan_done,img_found_count};
 wire sd_init_done,card_req,card_valid,card_end;wire [31:0] card_addr;wire [7:0] card_data;
 wire scan_done,scan_found_valid,scan_found_animation,scan_found_audio;wire [31:0] scan_found_sector;
 wire fat_mount_error,fat_read_error;wire [3:0] fat_error_code;
 reg scan_start_pulse,scan_kicked,load_start_pulse,load_abort;
 reg [5:0] img_found_count;reg [4:0] img_idx,load_idx;
 reg [31:0] animation_mask,audio_mask,load_sector;
 reg load_is_audio,current_audio,audio_stopped;reg [1:0] underrun_sync;
 wire wav_ready,wav_error,wav_req;wire [31:0] wav_addr;
 assign audio_mode=load_is_audio;
 wire load_is_av=load_is_audio && load_is_anim;
 reg current_av,av_audio_started,av_play_armed;
 reg [1:0] wav_start_pipeline;reg [15:0] wav_frame_sectors;
 reg [31:0] av_wav_base;reg [15:0] presented_epoch,load_epoch;
 wire [31:0] av_position_audio,av_position_sd;
 wire [15:0] audio_epoch=av_position_sd[31:16],audio_frame=av_position_sd[15:0];
 wire av_due=$signed(audio_epoch-load_epoch)>=0;
 wire anim_metadata,anim_highres;
 cdc_status_bus #(.WIDTH(32)) u_av_position(.src_clk(audio_clk),.src_rst(rst),.src_data(av_position_audio),.dst_clk(clk),.dst_rst(rst),.dst_data(av_position_sd));
 reg load_is_anim,current_animation,load_continuation;
 reg [15:0] load_frame,presented_frame,animation_frames;
 reg [7:0] animation_fps;
 reg load_busy,auto_play_en,next_req_pending;
 reg source_started,source_done_seen,write_done_seen;
 reg [1:0] pending_buf_idx;
 reg [31:0] load_timeout_cnt,recovery_count,auto_cnt;
 reg key_next_seen,key_auto_seen,load_error_seen;
 reg [2:0] wrfin_tgl_sync,vs_sync;
 reg [1:0] write_ack_sync,fade_black_sync,reader_index_s0,reader_index_s1;
 reg [3:0] cadence_frames;
 wire write_finish_pulse=wrfin_tgl_sync[2]^wrfin_tgl_sync[1];
 wire frame_pulse=vs_sync[2] && !vs_sync[1];
 wire reader_safe=reader_index_s1==disp_buf_idx;
 wire animation_due=animation_fps==5 ? cadence_frames>=11 : cadence_frames>=5;
 wire [4:0] next_from_current=nav_absolute ? nav_target:(nav_previous ? prev_index_r : next_index_r);
 always @(posedge clk or posedge rst) begin if(rst) begin next_index_r<=0;prev_index_r<=0;end else begin next_index_r<=next_index_limited(img_idx,img_found_count);prev_index_r<=prev_index_limited(img_idx,img_found_count);end end
 wire [15:0] sequential_frame=(presented_frame+1'b1>=animation_frames) ? 16'd0 : presented_frame+1'b1;
 wire [15:0] next_animation_frame=(current_av && audio_epoch!=presented_epoch) ? audio_frame : sequential_frame;
 wire bmp_ready_raw,still_ready,anim_ready,anim_error;
 wire [15:0] anim_count;wire [7:0] anim_fps;
 wire still_req,anim_req,still_wr_req,anim_wr_req,still_en,anim_en;
 wire [31:0] still_addr,anim_addr;wire [23:0] still_pixel,anim_pixel;
 wire [3:0] state_code_i;
 wire sd_sec_read;wire [31:0] sd_sec_read_addr;wire [7:0] sd_sec_read_data;
 wire sd_sec_read_data_valid,sd_sec_read_end;
 reg bmp_ready;
 assign bmp_ready_raw=load_is_av ? (anim_ready && wav_ready) : load_is_audio ? wav_ready : load_is_anim ? anim_ready : still_ready;
 // Sector arbiter: retain ownership through file_end and the client's release.
 reg [2:0] av_arb_state;reg av_arb_audio;
 assign sd_sec_read=load_is_av ? (av_arb_state==1) : (load_is_audio ? wav_req : load_is_anim ? anim_req : still_req);
 assign sd_sec_read_addr=load_is_av ? (av_arb_audio ? wav_addr : anim_addr) : (load_is_audio ? wav_addr : load_is_anim ? anim_addr : still_addr);
 wire av_wav_route=load_is_audio && (!load_is_av || (av_arb_state==1 && av_arb_audio));
 wire av_anim_route=load_is_anim && (!load_is_av || (av_arb_state==1 && !av_arb_audio));
 always @(posedge clk or posedge rst) begin
  if(rst) begin av_arb_state<=0;av_arb_audio<=0;end
  else if(load_abort || !load_is_av || audio_stopped) av_arb_state<=0;
  else case(av_arb_state)
   0:if(wav_req || anim_req) begin av_arb_audio<=wav_req;av_arb_state<=1;end
   1:if(sd_sec_read_end) av_arb_state<=2;
   2:if(!(av_arb_audio ? wav_req : anim_req)) av_arb_state<=3;
   3:av_arb_state<=0;
   default:av_arb_state<=0;
  endcase
 end
 assign write_req=load_is_anim ? anim_wr_req : load_is_audio ? 1'b0 : still_wr_req;
 assign write_en=load_is_anim ? anim_en : load_is_audio ? 1'b0 : still_en;
 assign write_data=load_is_anim ? {anim_pixel,8'd0} : {still_pixel,8'd0};
 assign osd_status={current_av,current_audio,current_animation,display_valid,load_busy,auto_play_en,img_found_count,img_idx};
 assign osd_debug={fat_error_code,(load_error_seen|fat_mount_error|underrun_sync[1]),load_busy,key_auto_seen,key_next_seen};
 assign state_code=load_busy ? (load_is_anim ? 4'd6 : state_code_i) : 4'd1;
 function [4:0] next_index_limited(input [4:0] cur,input [5:0] count);
 begin next_index_limited=({1'b0,cur}+6'd1>=count) ? 5'd0 : cur+5'd1;end endfunction
 function [4:0] prev_index_limited(input [4:0] cur,input [5:0] count);
 begin prev_index_limited=(count<=1) ? 5'd0 : (cur==0 ? count[4:0]-5'd1 : cur-5'd1);end endfunction
 task start_media(input [4:0] index,input [15:0] frame_number,input continuation);
 begin
  if(!continuation) begin av_audio_started<=0;av_play_armed<=0;load_epoch<=0;presented_epoch<=0;end
  else load_epoch<=current_av && audio_epoch!=presented_epoch ? audio_epoch : presented_epoch+1'b1;
  load_idx<=index;load_sector<={12'd0,index,15'd0};load_frame<=frame_number;
  load_is_audio<=audio_mask[index];audio_stopped<=0;load_is_anim<=animation_mask[index];load_continuation<=continuation;
  pending_buf_idx<=display_valid ? (disp_buf_idx^2'd1) : 2'd0;
  write_buf_idx<=display_valid ? (disp_buf_idx^2'd1) : 2'd0;
  load_start_pulse<=1;load_busy<=1;load_timeout_cnt<=0;
  source_started<=0;source_done_seen<=0;write_done_seen<=0;
  next_req_pending<=0;auto_cnt<=0;
 end endtask
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   wrfin_tgl_sync<=0;vs_sync<=3'b111;write_ack_sync<=0;fade_black_sync<=0;
   reader_index_s0<=0;reader_index_s1<=0;bmp_ready<=0;underrun_sync<=0;
  end else begin
   wrfin_tgl_sync<={wrfin_tgl_sync[1:0],write_finish_toggle};
   vs_sync<={vs_sync[1:0],frame_sync};write_ack_sync<={write_ack_sync[0],write_req_ack};
   fade_black_sync<={fade_black_sync[0],fade_black};reader_index_s0<=reader_buffer_active;reader_index_s1<=reader_index_s0;
   bmp_ready<=bmp_ready_raw;underrun_sync<={underrun_sync[0],audio_underrun};
  end
 end
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   nav_absolute<=0;nav_target<=0;nav_delay<=0;nav_previous<=0;current_av<=0;av_audio_started<=0;av_play_armed<=0;wav_start_pipeline<=0;wav_frame_sectors<=0;av_wav_base<=0;presented_epoch<=0;load_epoch<=0;display_valid<=0;write_buf_idx<=0;disp_buf_idx<=0;pending_buf_idx<=0;
   scan_start_pulse<=0;scan_kicked<=0;load_start_pulse<=0;load_abort<=0;
   load_is_audio<=0;current_audio<=0;audio_stopped<=0;audio_mask<=0;img_found_count<=0;img_idx<=0;load_idx<=0;animation_mask<=0;load_sector<=0;
   load_is_anim<=0;current_animation<=0;load_continuation<=0;load_frame<=0;presented_frame<=0;animation_frames<=0;animation_fps<=10;
   load_busy<=0;auto_play_en<=0;next_req_pending<=0;source_started<=0;source_done_seen<=0;write_done_seen<=0;
   load_timeout_cnt<=0;recovery_count<=0;auto_cnt<=0;cadence_frames<=0;
   key_next_seen<=0;key_auto_seen<=0;load_error_seen<=0;
  end else begin
   scan_start_pulse<=0;load_start_pulse<=0;load_abort<=0;
   if(nav_delay!=0) nav_delay<=nav_delay-1'b1;
   wav_start_pipeline<={wav_start_pipeline[0],1'b0};
   if(anim_metadata && load_is_av && !av_audio_started) begin
    wav_frame_sectors<=anim_highres ? anim_count[8:0]*16'd192 : anim_count[8:0]*16'd75;wav_start_pipeline<=1;av_audio_started<=1;
   end
   if(wav_start_pipeline[0]) av_wav_base<=load_sector+{16'd0,wav_frame_sectors}+32'd1;
   if(current_av && reader_safe && !(load_busy && !load_continuation)) av_play_armed<=1;
   if(load_abort || !sd_init_done) begin av_audio_started<=0;av_play_armed<=0;wav_start_pipeline<=0;end
   if(recovery_count!=0) recovery_count<=recovery_count-1'b1;
   if(key_next_press) key_next_seen<=~key_next_seen;
   if(key_auto_press) key_auto_seen<=~key_auto_seen;
   if(!sd_init_done) begin
    current_av<=0;load_is_audio<=0;current_audio<=0;audio_stopped<=0;audio_mask<=0;scan_kicked<=0;img_found_count<=0;animation_mask<=0;display_valid<=0;current_animation<=0;
    load_busy<=0;auto_play_en<=0;next_req_pending<=0;load_abort<=0;source_started<=0;source_done_seen<=0;write_done_seen<=0;
   end else begin
    if(!scan_kicked && bmp_ready) begin scan_start_pulse<=1;scan_kicked<=1;end
    if(scan_found_valid && img_found_count<32) begin
     img_found_count<=img_found_count+1'b1;animation_mask[scan_found_sector[19:15]]<=scan_found_animation;audio_mask[scan_found_sector[19:15]]<=scan_found_audio;
    end
    if(key_next_press && scan_done && img_found_count!=0) begin next_req_pending<=1;nav_previous<=0;nav_absolute<=0;nav_delay<=2;end
    if(key_prev_press && scan_done && img_found_count!=0) begin next_req_pending<=1;nav_previous<=1;nav_absolute<=0;nav_delay<=2;end
    if(menu_command) begin next_req_pending<=1;nav_target<=menu_jump_index;nav_absolute<=1;nav_delay<=2;end
    if(key_auto_press && scan_done && (current_audio || current_animation || img_found_count>1)) begin auto_play_en<=~auto_play_en;auto_cnt<=0;end
    if(frame_pulse && current_animation && cadence_frames<12) cadence_frames<=cadence_frames+1'b1;
    if(display_valid && !current_animation && !current_audio && auto_play_en && !load_busy && !next_req_pending && !menu_command && img_found_count>1) begin
     if(auto_cnt==CLK_FREQ_HZ*3-1) begin auto_cnt<=0;next_req_pending<=1;nav_previous<=0;nav_absolute<=0;nav_delay<=2;end
     else auto_cnt<=auto_cnt+1'b1;
    end else auto_cnt<=0;
    if(current_audio && (fat_read_error || wav_error)) begin load_error_seen<=1;load_abort<=1;audio_stopped<=1;auto_play_en<=0;end
    if(current_audio && next_req_pending && !audio_stopped && !load_busy) begin load_abort<=1;audio_stopped<=1;recovery_count<=CLK_FREQ_HZ/100;end
    if(load_busy) begin
     if(!bmp_ready) source_started<=1;
     if(source_started && bmp_ready) source_done_seen<=1;
     if(write_finish_pulse || (load_is_audio && !load_is_anim)) write_done_seen<=1;
     if(current_av && next_req_pending && source_done_seen && write_done_seen) begin
      load_busy<=0;load_abort<=1;audio_stopped<=1;recovery_count<=CLK_FREQ_HZ/100;
      source_started<=0;source_done_seen<=0;write_done_seen<=0;
     end else if(fat_read_error || (load_is_audio && wav_error) || (load_is_anim && anim_error) || load_timeout_cnt>=CLK_FREQ_HZ*5-1) begin
      load_busy<=0;load_abort<=1;load_error_seen<=1;recovery_count<=CLK_FREQ_HZ/100;
      source_started<=0;source_done_seen<=0;write_done_seen<=0;load_timeout_cnt<=0;
     end else if(source_done_seen && write_done_seen &&
      (!display_valid || load_is_audio || current_audio || current_animation || fade_black_sync[1]) &&
      (!(current_animation || load_is_anim) || (frame_pulse && (!load_continuation || (load_is_av ? av_due : animation_due))))) begin
      load_busy<=0;if(load_is_anim || !load_is_audio) disp_buf_idx<=pending_buf_idx;img_idx<=load_idx;nav_delay<=2;if(load_is_anim || !load_is_audio) display_valid<=1;current_audio<=load_is_audio;current_av<=load_is_av;presented_epoch<=load_epoch;
      current_animation<=load_is_anim;presented_frame<=load_frame;cadence_frames<=0;
      if(load_is_anim) begin animation_frames<=anim_count;animation_fps<=anim_fps;end
      if(load_is_audio && !load_continuation) auto_play_en<=1;
      else if(load_is_anim && !current_animation) auto_play_en<=1;
      else if(!load_is_anim && (current_animation || current_audio)) auto_play_en<=0;
      source_started<=0;source_done_seen<=0;write_done_seen<=0;load_timeout_cnt<=0;
     end else if(card_valid || write_en || write_finish_pulse || (source_done_seen && write_done_seen)) load_timeout_cnt<=0;
     else load_timeout_cnt<=load_timeout_cnt+1'b1;
    end else if(scan_done && bmp_ready && !load_abort && recovery_count==0 && img_found_count!=0 && !menu_command) begin
     if(!display_valid && !current_audio) start_media(0,0,0);
     else if(next_req_pending && nav_delay==0 && (!current_audio || audio_stopped) && (!current_animation || reader_safe)) start_media(next_from_current,0,0);
     else if(current_animation && auto_play_en && reader_safe && !next_req_pending) start_media(img_idx,next_animation_frame,1);
    end
   end
  end
 end
 fat32_store #(.ENABLE_MENU(ENABLE_MENU)) u_fat32(
  .scan_name_valid(menu_name_valid),.scan_name_addr(menu_name_addr),.scan_name_data(menu_name_data),
  .clk(clk),.rst(rst),.sd_init_done(sd_init_done),.scan_start(scan_start_pulse),.load_abort(load_abort),
  .scan_done(scan_done),.scan_found_valid(scan_found_valid),.scan_found_sector(scan_found_sector),.scan_found_animation(scan_found_animation),.scan_found_audio(scan_found_audio),
  .mount_error(fat_mount_error),.read_error(fat_read_error),.error_code(fat_error_code),
  .file_req(sd_sec_read),.file_addr(sd_sec_read_addr),.file_data(sd_sec_read_data),.file_valid(sd_sec_read_data_valid),.file_end(sd_sec_read_end),
  .card_req(card_req),.card_addr(card_addr),.card_data(card_data),.card_valid(card_valid),.card_end(card_end));
 bmp_read bmp_read_m0(
  .clk(clk),.rst(rst),.ready(still_ready),.scan_start(1'b0),.scan_start_sector(32'd0),.scan_max_sector(32'd0),.scan_target_count(3'd0),
  .scan_done(),.scan_found_valid(),.scan_found_sector(),.scan_found_total(),
  .load_start(load_start_pulse && !load_is_anim && !load_is_audio),.load_abort(load_abort),.load_sector(load_sector),.sd_init_done(sd_init_done),.state_code(state_code_i),
  .bmp_width(bmp_width),.bmp_height(bmp_height),.write_req(still_wr_req),.write_req_ack(write_ack_sync[1]),
  .sd_sec_read(still_req),.sd_sec_read_addr(still_addr),.sd_sec_read_data(sd_sec_read_data),.sd_sec_read_data_valid(sd_sec_read_data_valid && !load_is_anim && !load_is_audio),.sd_sec_read_end(sd_sec_read_end && !load_is_anim && !load_is_audio),
  .bmp_data_wr_en(still_en),.bmp_data(still_pixel));
 anm_read u_anm_read(
  .av_mode(load_is_av),.metadata_valid(anim_metadata),.frame_is_highres(anim_highres),
  .clk(clk),.rst(rst),.load_start(load_start_pulse && load_is_anim),.load_abort(load_abort || !sd_init_done),.load_sector(load_sector),.frame_index(load_frame),
  .ready(anim_ready),.error(anim_error),.frame_count(anim_count),.frame_rate(anim_fps),
  .write_req(anim_wr_req),.write_req_ack(write_ack_sync[1]),.pixel_ready(pixel_write_ready),
  .sd_sec_read(anim_req),.sd_sec_read_addr(anim_addr),.sd_sec_read_data(sd_sec_read_data),.sd_sec_read_data_valid(sd_sec_read_data_valid && av_anim_route),.sd_sec_read_end(sd_sec_read_end && av_anim_route),
  .bmp_data_wr_en(anim_en),.bmp_data(anim_pixel));
 wav_read u_wav(.playback_samples(playback_samples),.total_audio_samples(total_audio_samples),.clk(clk),.rst(rst),.av_frame_count(anim_count),.av_position(av_position_audio),.start((load_start_pulse && load_is_audio && !load_is_anim) || wav_start_pipeline[1]),
  .abort(load_abort || !sd_init_done || !load_is_audio || audio_stopped),.play(current_audio && auto_play_en && (!load_busy || (current_av && load_continuation)) && (!current_av || av_play_armed)),.base_sector(load_is_av ? av_wav_base : load_sector),
  .ready(wav_ready),.error(wav_error),.req(wav_req),.addr(wav_addr),.data(sd_sec_read_data),
  .valid(sd_sec_read_data_valid && av_wav_route),.sector_end(sd_sec_read_end && av_wav_route),
  .audio_clk(audio_clk),.tick(audio_tick),.left_pcm(wav_left),.right_pcm(wav_right),.underrun(audio_underrun));
 sd_card_top sd_card_top_m0(
  .clk(clk),.rst(rst),.SD_nCS(SD_nCS),.SD_DCLK(SD_DCLK),.SD_MOSI(SD_MOSI),.SD_MISO(SD_MISO),.sd_init_done(sd_init_done),
  .sd_sec_read(card_req),.sd_sec_read_addr(card_addr),.sd_sec_read_data(card_data),.sd_sec_read_data_valid(card_valid),.sd_sec_read_end(card_end),
  .sd_sec_write(1'b0),.sd_sec_write_addr(32'd0),.sd_sec_write_data(),.sd_sec_write_data_req(),.sd_sec_write_end());
endmodule

// Already-debounced stretched events still need a destination-domain synchronizer.
module key_event_sync(input wire clk,rst,button_in,output wire press_pulse);
 reg [2:0] sync;
 always @(posedge clk or posedge rst) if(rst)sync<=3'b111;else sync<={sync[1:0],button_in};
 assign press_pulse=sync[2] && !sync[1];
endmodule

module key_press_debounce #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst,
    input  wire button_in,    // 默认：松开=1，按下=0
    output reg  press_pulse
);

localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

reg button_sync0;
reg button_sync1;
reg button_stable;
reg [31:0] cnt;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        button_sync0  <= 1'b1;
        button_sync1  <= 1'b1;
        button_stable <= 1'b1;
        cnt           <= 32'd0;
        press_pulse   <= 1'b0;
    end else begin
        button_sync0 <= button_in;
        button_sync1 <= button_sync0;
        press_pulse  <= 1'b0;

        if (button_sync1 == button_stable) begin
            cnt <= 32'd0;
        end else begin
            if (cnt >= DEBOUNCE_CYCLES - 1) begin
                if (button_stable && !button_sync1)
                    press_pulse <= 1'b1;
                button_stable <= button_sync1;
                cnt           <= 32'd0;
            end else begin
                cnt <= cnt + 32'd1;
            end
        end
    end
end

endmodule
