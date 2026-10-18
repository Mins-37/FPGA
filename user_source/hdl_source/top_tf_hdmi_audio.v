
module top(
    input wire [3:0] sw,
    input                       clk,
    input                       rst_n,
    input                       key3,           // KEY3: previous media
    input                       key1,           // 手动下一张
    input                       key2,           // 自动播放 开/关

	output [5:0]                seg_sel,
	output [7:0]                seg_data,

    // HDMI TMDS
    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    // HDMI DDC
    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    // TF card SPI
    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso
);

parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter FRAME_PIXELS  = 24'd307200;   // 640*480
parameter BUF0_ADDR     = 24'd0;
parameter BUF1_ADDR     = FRAME_PIXELS;

wire Sdr_init_done;
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sd_card_clk;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;

wire hs;
wire vs;
wire de;

wire [23:0] vout_data_raw;
wire [23:0] vout_data;
wire        display_valid;
wire [16:0] osd_status_sd, osd_status_video;
wire [23:0] wav_left,wav_right,tone_left,tone_right;wire audio_mode,audio_underrun;reg [1:0] audio_mode_sync;
 wire [21:0] playback_samples,total_audio_samples;
 wire [9:0] elapsed_tenths,total_tenths;wire [8:0] progress_fill;wire progress_valid;
 wire pixel_write_ready;wire [1:0] reader_buffer_active;
wire clean_toggle;reg clean_mode;reg [1:0] clean_mode_pipe;
 always @(posedge video_clk or posedge rst_all) begin
  if(rst_all) begin clean_mode<=0;clean_mode_pipe<=0;end
  else begin
   clean_mode_pipe<={clean_mode_pipe[0],clean_mode};
   if(clean_toggle) clean_mode<=~clean_mode;
  end
 end
 wire menu_toggle,menu_open,player_next_n,player_prev_n,player_auto_n;
wire [4:0] menu_selected,menu_page,command_index,menu_jump_index;wire command_toggle,command_ack,menu_jump_valid;
wire menu_name_we;wire [8:0] menu_name_wr_addr,menu_name_rd_addr;wire [7:0] menu_name_wr_data,menu_name_rd_data;
wire [6:0] menu_catalogue_sd,menu_catalogue_video;
wire [23:0] menu_rgb;wire menu_vs,menu_de;
wire [7:0] osd_debug_sd,osd_debug_video;
wire [23:0] osd_rgb;
wire osd_de, osd_vs;
wire [23:0] adjusted_rgb;
wire adjusted_vs, adjusted_de;
wire [3:0] image_controls;
wire [23:0] waveform_rgb;
wire waveform_vs,waveform_de;
wire [23:0] faded_rgb;
wire faded_vs,faded_de,fade_black;

wire [3:0] state_code,state_code_50;
 cdc_status_bus #(.WIDTH(4)) u_seg_status(.src_clk(sd_card_clk),.src_rst(rst_all),.src_data(state_code),.dst_clk(ext_mem_clk),.dst_rst(rst_all),.dst_data(state_code_50));
wire [6:0]  seg_data_0;

wire        video_read_req;
wire        video_read_req_ack;
wire        video_read_en;
wire [31:0] video_read_data;

wire        sd_card_write_en;
wire [31:0] sd_card_write_data;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
wire        frame_write_finish;
reg         frame_write_toggle_mem;

wire [1:0]  write_buf_idx;
wire [1:0]  disp_buf_idx;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

wire hs_0;
wire vs_0;
wire de_0;

// HDMI 1.4b 相关
wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

// 统一复位：TF 图像链路 + HDMI 链路
wire sys_pll_lock;
wire video_pll_lock;
wire rst_all;

reg [19:0] rst_cnt = 20'd0;
reg rst_all_reg = 1'b1;

always @(posedge clk) begin
    if (!rst_n) begin
        rst_cnt <= 20'd0;
        rst_all_reg <= 1'b1;
    end else if (!rst_all_reg) begin
        // 一旦复位释放，忽略后续微小的 PLL 抖动，防止系统在使用时随机复位
        rst_all_reg <= 1'b0;
    end else if (sys_pll_lock && video_pll_lock) begin
        // 等待 PLL 连续稳定 20ms @ 50MHz
        if (rst_cnt < 20'd1_000_000) begin
            rst_cnt <= rst_cnt + 1'b1;
            rst_all_reg <= 1'b1;
        end else begin
            rst_all_reg <= 1'b0;
        end
    end else begin
        rst_cnt <= 20'd0;
        rst_all_reg <= 1'b1;
    end
end

assign rst_all = rst_all_reg;

// 保持你原来的 TF / SDRAM / video 时钟
sys_pll sys_pll_m0(
    .refclk     (clk),
    .reset      (1'b0),
    .extlock    (sys_pll_lock),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft)
);

video_pll video_pll_m0(
    .refclk     (clk),
    .reset      (1'b0),
    .extlock    (video_pll_lock),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk)
);

// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同步
always @(posedge ext_mem_clk or posedge rst_all) begin
    if (rst_all)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

// ===================== TF 多图扫描与缓存（双缓冲） =====================
sd_card_bmp #(
    .CLK_FREQ_HZ (100_000_000),.KEYS_PREDEBOUNCED(1),.ENABLE_MENU(1)
) sd_card_bmp_m0(
    .menu_jump_valid(menu_jump_valid),.menu_jump_index(menu_jump_index),
    .menu_name_valid(menu_name_we),.menu_name_addr(menu_name_wr_addr),.menu_name_data(menu_name_wr_data),.menu_catalogue(menu_catalogue_sd),
    .audio_clk(video_clk),.audio_tick(audio_valid),.wav_left(wav_left),.wav_right(wav_right),.audio_mode(audio_mode),.audio_underrun(audio_underrun),
    .clk               (sd_card_clk),
    .rst               (rst_all),
    .key_next          (player_next_n),
    .key_auto          (player_auto_n),.key_prev(player_prev_n),.playback_samples(playback_samples),.total_audio_samples(total_audio_samples),
    .frame_sync        (vs_0),
    .pixel_write_ready (pixel_write_ready),
    .reader_buffer_active(reader_buffer_active),
    .state_code        (state_code),
    .bmp_width         (16'd640),
    .bmp_height        (16'd480),
    .display_valid     (display_valid),
    .osd_status        (osd_status_sd),
    .osd_debug         (osd_debug_sd),

    .write_finish_toggle(frame_write_toggle_mem),
    .fade_black        (fade_black),
    .write_buf_idx     (write_buf_idx),
    .disp_buf_idx      (disp_buf_idx),

    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_en          (sd_card_write_en),


    .write_data        (sd_card_write_data),
    .SD_nCS            (sd_ncs),
    .SD_DCLK           (sd_dclk),
    .SD_MOSI           (sd_mosi),
    .SD_MISO           (sd_miso)
);

seg_decoder seg_decoder_m0(
    .bin_data          (state_code_50),
    .seg_data          (seg_data_0)
);

seg_scan seg_scan_m0(
    .clk               (ext_mem_clk),
    .rst_n             (rst_n && !rst_all),
    .seg_sel           (seg_sel),
    .seg_data          (seg_data),
    .seg_data_0        ({1'b1,7'b1111_111}),
    .seg_data_1        ({1'b1,7'b1111_111}),
    .seg_data_2        ({1'b1,7'b1111_111}),
    .seg_data_3        ({1'b1,7'b1111_111}),
    .seg_data_4        ({1'b1,7'b1111_111}),
    .seg_data_5        ({1'b1,seg_data_0})
);

// ===================== 原图像时序与帧缓存 =====================
video_timing_data video_timing_data_m0(
    .video_clk         (video_clk),
    .rst               (rst_all),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0)
);

video_delay video_delay_m0(
    .video_clk         (video_clk),
    .rst               (rst_all),
    .read_en           (video_read_en),
    .read_data         (video_read_data[31:8]),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .hs_r              (hs),
    .vs_r              (vs),
    .de_r              (de),
    .vout_data         (vout_data_raw)
);

// 首图提交前黑屏；提交后一直显示当前显示缓冲区内容
assign vout_data = osd_status_video[13] ? vout_data_raw : 24'd0;

frame_read_write #(
    .WRITE_V_FLIP     (0),
    .FRAME_WIDTH      (640),
    .FRAME_HEIGHT     (480)
) frame_read_write_m0(
    .mem_clk           (ext_mem_clk),
    .rst               (rst_all),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .read_finish       (),
    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (24'd0),
    .read_addr_3       (24'd0),
    .read_addr_index   (disp_buf_idx),
    .read_len          (FRAME_PIXELS),
    .read_en           (video_read_en),
    .read_data         (video_read_data),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    .write_addr_0      (BUF0_ADDR),
    .write_addr_1      (BUF1_ADDR),
    .write_addr_2      (24'd0),
    .write_addr_3      (24'd0),
    .write_addr_index  (write_buf_idx),
    .write_len         (FRAME_PIXELS),
    .write_en          (sd_card_write_en),
    .write_ready       (pixel_write_ready),
    .read_buffer_active(reader_buffer_active),
    .write_data        (sd_card_write_data)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (rst_all),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

// PCM is generated in the pixel domain: no I2S CDC or audio PLL required.
wire nav_next_n,nav_prev_n,nav_auto_n;wire [3:0] volume_level;wire audio_mute;
audio_controls #(.ENABLE_CLEAN(1)) u_audio_controls(.clk(video_clk),.rst(rst_all),.key_next(key1),.key_prev(key3),.key_auto(key2),
 .next_n(nav_next_n),.prev_n(nav_prev_n),.auto_n(nav_auto_n),.volume(volume_level),.mute(audio_mute),.menu_toggle(menu_toggle),.menu_open(menu_open),.clean_toggle(clean_toggle));
media_menu_control u_menu_control(.clk(video_clk),.rst(rst_all),.toggle(menu_toggle),.next_n(nav_next_n),.prev_n(nav_prev_n),.auto_n(nav_auto_n),
 .ready(menu_catalogue_video[6]),.count(menu_catalogue_video[5:0]),.current_index(osd_status_video[4:0]),.command_ack(command_ack),
 .opened(menu_open),.selected(menu_selected),.page_base(menu_page),.player_next_n(player_next_n),.player_prev_n(player_prev_n),.player_auto_n(player_auto_n),.command_toggle(command_toggle),.command_index(command_index));
media_jump_cdc u_menu_command(.src_clk(video_clk),.src_rst(rst_all),.request(command_toggle),.index(command_index),.acknowledge(command_ack),
 .dst_clk(sd_card_clk),.dst_rst(rst_all),.valid(menu_jump_valid),.target(menu_jump_index));
cdc_status_bus #(.WIDTH(7)) u_menu_catalogue(.src_clk(sd_card_clk),.src_rst(rst_all),.src_data(menu_catalogue_sd),.dst_clk(video_clk),.dst_rst(rst_all),.dst_data(menu_catalogue_video));
media_name_ram u_menu_names(.wr_clk(sd_card_clk),.we(menu_name_we),.wr_addr(menu_name_wr_addr),.wr_data(menu_name_wr_data),.rd_clk(video_clk),.rd_addr(menu_name_rd_addr),.rd_data(menu_name_rd_data));
wire audio_valid;reg hdmi_audio_valid;reg [23:0] tone_left_d,tone_right_d;
 always @(posedge video_clk or posedge rst_all) begin
  if(rst_all) begin audio_mode_sync<=0;hdmi_audio_valid<=0;tone_left_d<=0;tone_right_d<=0;end
  else begin audio_mode_sync<={audio_mode_sync[0],audio_mode};hdmi_audio_valid<=audio_valid;tone_left_d<=tone_left;tone_right_d<=tone_right;end
 end
 wire [23:0] raw_left=audio_mode_sync[1] ? wav_left : tone_left_d;
 wire [23:0] raw_right=audio_mode_sync[1] ? wav_right : tone_right_d;
wire [23:0] audio_left_data, audio_right_data;wire output_audio_valid;
audio_gain u_audio_gain(.clk(video_clk),.rst(rst_all),.sample_valid(hdmi_audio_valid),.left_in(raw_left),.right_in(raw_right),
 .volume(volume_level),.mute(audio_mute),.out_valid(output_audio_valid),.left_out(audio_left_data),.right_out(audio_right_data));
wire [63:0] spectrum_levels;wire spectrum_overrun,spectrum_stable;
audio_spectrum u_audio_spectrum(.clk(video_clk),.rst(rst_all),.sample_valid(output_audio_valid),.pcm(audio_left_data),.levels(spectrum_levels),.overrun(spectrum_overrun),.levels_stable(spectrum_stable));
wire acr_valid;
wire [19:0] acr_cts, acr_n;
reg [1:0] audio_picture_valid;
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) audio_picture_valid <= 2'b00;
    else audio_picture_valid <= {audio_picture_valid[0], (display_valid || audio_mode)};
end
audio_test_pcm u_audio_test_pcm(
    .clk(video_clk), .rst(rst_all | !audio_picture_valid[1]),
    .sample_valid(audio_valid),
    .left_pcm(tone_left), .right_pcm(tone_right),
    .acr_valid(acr_valid), .acr_cts(acr_cts), .acr_n(acr_n)
);

// Stable bundled-data status transfer; no independent synchronization of image bits.
cdc_status_bus #(.WIDTH(17)) u_osd_status(
 .src_clk(sd_card_clk), .src_rst(rst_all), .src_data(osd_status_sd),
 .dst_clk(video_clk), .dst_rst(rst_all), .dst_data(osd_status_video)
);
cdc_status_bus u_osd_debug(
 .src_clk(sd_card_clk),.src_rst(rst_all),.src_data(osd_debug_sd),
 .dst_clk(video_clk),.dst_rst(rst_all),.dst_data(osd_debug_video)
);
image_adjust u_image_adjust(
 .clk(video_clk), .rst(rst_all), .sw(sw),
 .in_vs(vs), .in_de(de), .in_rgb(vout_data),
 .out_vs(adjusted_vs), .out_de(adjusted_de), .out_rgb(adjusted_rgb),
 .active_controls(image_controls)
);
video_fade u_video_fade(
 .clk(video_clk),.rst(rst_all),
 .image_valid(osd_status_video[13]),.bypass(osd_status_video[14] || osd_status_video[15]),.load_busy(osd_debug_video[2]),
 .in_vs(adjusted_vs),.in_de(adjusted_de),.in_rgb(adjusted_rgb),
 .out_vs(faded_vs),.out_de(faded_de),.out_rgb(faded_rgb),.black(fade_black)
);
audio_waveform #(.ENABLE_CLEAN(1)) u_audio_waveform(.hide_overlays(clean_mode),
 .clk(video_clk),.rst(rst_all),
 .spectrum_levels(spectrum_levels),.spectrum_stable(spectrum_stable),.sample_valid(output_audio_valid),.pcm(audio_left_data),
 .in_vs(faded_vs),.in_de(faded_de),.in_rgb(faded_rgb),
 .out_vs(waveform_vs),.out_de(waveform_de),.out_rgb(waveform_rgb)
);
media_progress u_media_progress(.clk(video_clk),.rst(rst_all),.active(osd_status_video[15]),
 .played(playback_samples),.duration(total_audio_samples),.elapsed_tenths(elapsed_tenths),.total_tenths(total_tenths),.fill(progress_fill),.valid(progress_valid));
video_osd #(.ENABLE_CLEAN(1)) u_video_osd(.hide_overlays(clean_mode_pipe[1]),.volume(volume_level),.muted(audio_mute),.elapsed_tenths(elapsed_tenths),.total_tenths(total_tenths),.progress_fill(progress_fill),.progress_valid(progress_valid),
 .clk(video_clk), .rst(rst_all), .in_vs(waveform_vs), .in_de(waveform_de),
 .in_rgb(waveform_rgb), .status(osd_status_video), .controls(image_controls), .debug_status(osd_debug_video),
 .out_vs(osd_vs), .out_de(osd_de), .out_rgb(osd_rgb)
);

media_menu_osd u_media_menu(.clk(video_clk),.rst(rst_all),.in_vs(osd_vs),.in_de(osd_de),.in_rgb(osd_rgb),
 .opened(menu_open),.ready(menu_catalogue_video[6]),.count(menu_catalogue_video[5:0]),.selected(menu_selected),.page_base(menu_page),.current_index(osd_status_video[4:0]),
 .name_addr(menu_name_rd_addr),.name_data(menu_name_rd_data),.out_vs(menu_vs),.out_de(menu_de),.out_rgb(menu_rgb));

// ===================== RGB/DE 转 AXIS 视频 =====================
video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_vs          (menu_vs),
    .I_de          (menu_de),
    .I_rgb         (menu_rgb),
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);

// 上电后自动打一拍，触发一次 EDID 读取
startup_pulse #(
    .CNT_MAX(20'd100000)
) u_startup_pulse (
    .I_clk   (video_clk),
    .I_rst   (rst_all),
    .O_pulse (edid_trig)
);

// ===================== HDMI 1.4b 发射 =====================
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( 800        ),
    .HSA                    ( 96         ),
    .HFP                    ( 16         ),
    .HBP                    ( 48         ),
    .HACTIVE                ( 640        ),
    .VTOTAL                 ( 525        ),
    .VSA                    ( 2          ),
    .VFP                    ( 10         ),
    .VBP                    ( 33         ),
    .VACTIVE                ( 480        ),
    .VIDEO_VIC              ( 1          ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 250        )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (video_clk),
    .I_rst              (rst_all),
    .I_edid_read_trig   (edid_trig),
    .O_edid_read_valid  (edid_valid),
    .O_edid_read_data   (edid_data),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready),

    .I_audio_valid      (output_audio_valid),
    .I_audio_left_data  (audio_left_data),
    .I_audio_right_data (audio_right_data),
    .I_acr_valid        (acr_valid),
    .I_acr_cts          (acr_cts),
    .I_acr_n            (acr_n),

    .O_video_locked     (),
    .O_ddc_scl          (HDMI_DDC_SCL),
    .IO_ddc_sda         (HDMI_DDC_SDA),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (rst_all),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

endmodule
