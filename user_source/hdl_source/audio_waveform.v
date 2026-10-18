// Oscilloscope display from the actual left PCM passed to the HDMI transmitter.
// Positive zero-cross trigger; retain the full 48kHz sample rate for smooth curves.
// Two 128-sample banks swap only at VS: capture never writes the displayed bank.
module audio_waveform #(parameter ENABLE_CLEAN=0)(
 input wire clk,input wire rst,input wire sample_valid,input wire signed [23:0] pcm,
 input wire [63:0] spectrum_levels,
 input wire spectrum_stable,
 input wire in_vs,input wire in_de,input wire [23:0] in_rgb,
 output reg out_vs,output reg out_de,output reg [23:0] out_rgb, input wire hide_overlays
);
 (* ram_style="bram" *) reg [6:0] samples[0:255],samples_prev[0:255];
 reg display_bank,write_bank,display_valid,capture,ready,was_negative;
 reg [6:0] write_index;
 reg [7:0] silence_count;
 reg [47:0] spectrum_frame;integer band;
 reg hide_frame;
 reg vs_d,de_d;
 reg [9:0] x,y;
 wire frame_edge=in_vs && !vs_d;
 wire signed [23:0] amplitude=pcm>>>15;
 wire [6:0] sample_y=(amplitude>24'sd40) ? 7'd0 :
                     (amplitude< -24'sd40) ? 7'd80 : (24'sd40-amplitude);
 wire capture_write=sample_valid && !ready && (capture || (was_negative && !pcm[23]));
 wire [7:0] capture_addr={write_bank,capture ? write_index:7'd0};
 always @(posedge clk) if(!rst && capture_write) begin samples[capture_addr]<=sample_y;samples_prev[capture_addr]<=sample_y;end
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   display_bank<=0;write_bank<=1;display_valid<=0;
   capture<=0;ready<=0;was_negative<=0;write_index<=0;
   silence_count<=0;
   spectrum_frame<=0;hide_frame<=0;
   vs_d<=0;de_d<=0;x<=0;y<=0;
  end else begin
   vs_d<=in_vs;de_d<=in_de;
   if(frame_edge) hide_frame<=ENABLE_CLEAN && hide_overlays;
   if(frame_edge && spectrum_stable) begin
    for(band=0;band<8;band=band+1) begin
     if(spectrum_levels[band*8+:6]>=spectrum_frame[band*6+:6]) spectrum_frame[band*6+:6]<=spectrum_levels[band*8+:6];
     else spectrum_frame[band*6+:6]<=spectrum_frame[band*6+:6]>2 ? spectrum_frame[band*6+:6]-6'd2:6'd0;
    end
   end
   if(in_vs!=vs_d) begin x<=0;y<=0;end
   else if(in_de) x<=x+1'b1;
   else begin x<=0;if(de_d) y<=y+1'b1;end
   if(frame_edge && ready) begin
    display_bank<=write_bank;write_bank<=~write_bank;display_valid<=1;
    ready<=0;capture<=0;write_index<=0;
   end
   if(sample_valid) begin
    if(pcm[23:8]==16'd0 || pcm[23:8]==16'hffff) begin
     if(silence_count!=255) silence_count<=silence_count+1'b1;
    end else silence_count<=0;
    was_negative<=pcm[23];
    if(!ready) begin
     if(!capture) begin
      if(was_negative && !pcm[23]) begin
       capture<=1;write_index<=1;
      end
     end else begin
      if(write_index==127) begin ready<=1;capture<=0;end
      else write_index<=write_index+1'b1;
     end
    end
    if(silence_count==255 && (pcm[23:8]==16'd0 || pcm[23:8]==16'hffff)) begin
     display_valid<=0;capture<=0;ready<=0;write_index<=0;
    end
   end
  end
 end
 wire [6:0] col=x-480;
 wire [6:0] previous_col=(col==0) ? 0 : col-1'b1;
 reg [6:0] current_q,previous_q;
 always @(posedge clk) begin current_q<=samples[{display_bank,col}];previous_q<=samples_prev[{display_bank,previous_col}];end
 reg [9:0] render_x,render_y;reg render_valid,render_vs,render_de;reg [23:0] render_rgb;
 wire [6:0] render_col=render_x-480;
 always @(posedge clk or posedge rst) begin
  if(rst)begin render_x<=0;render_y<=0;render_valid<=0;render_vs<=0;render_de<=0;render_rgb<=0;end
  else begin render_x<=x;render_y<=y;render_valid<=display_valid;render_vs<=in_vs;render_de<=in_de;render_rgb<=in_rgb;end
 end
 wire plot=(render_x>=480 && render_x<608 && render_y>=340 && render_y<=420);
 wire panel=(render_x>=464 && render_x<624 && render_y>=216 && render_y<432);
 wire [6:0] current_y=render_valid ? current_q : 7'd40;
 wire [6:0] previous_y=render_valid ? previous_q : 7'd40;
 wire [9:0] row=render_y-340;
 wire trace=(current_y<=previous_y) ? (row>=current_y && row<=previous_y) :
                                              (row>=previous_y && row<=current_y);
 wire border=panel && (render_x==464 || render_x==623 || render_y==216 || render_y==308 || render_y==431);
 wire grid=plot && (render_col[4:0]==0 || row==0 || row==20 || row==40 || row==60 || row==80);
 reg [23:0] mix;
 wire spectrum_panel=render_x>=464 && render_x<624 && render_y>=216 && render_y<308;
 wire [9:0] spectrum_col=render_x-480;
 wire [3:0] spectrum_bin=spectrum_col[7:4];
 wire [3:0] spectrum_x=spectrum_col[3:0];
 wire [5:0] spectrum_height=spectrum_bin<8 ? spectrum_frame[spectrum_bin*6+:6]:6'd0;
 always @* begin
  mix=render_rgb;
  if(panel) mix={2'b00,render_rgb[23:18],2'b00,render_rgb[15:10],2'b00,render_rgb[7:2]};
  if(grid) mix=24'h24505D;
  if(border) mix=24'h7DE8FF;
  if(plot && trace) mix=24'h80FF70;
  if(spectrum_panel) begin
   mix={2'b00,render_rgb[23:18],2'b00,render_rgb[15:10],2'b00,render_rgb[7:2]};
   if(render_x==464 || render_x==623 || render_y==216) mix=24'h7DE8FF;
   else if(render_x>=480 && render_x<608 && (render_y==244 || render_y==272 || render_y==300)) mix=24'h24505D;
   if(render_x>=480 && render_x<608 && spectrum_bin<8 && spectrum_x<12 && render_y<300 && render_y>=244 && render_y>=300-spectrum_height)
    mix=render_y<260 ? 24'hFF8050:render_y<276 ? 24'hFFE070:24'h65E0AD;
  end
 end
 always @(posedge clk or posedge rst) begin
  if(rst) begin out_vs<=0;out_de<=0;out_rgb<=0;end
  else begin out_vs<=render_vs;out_de<=render_de;out_rgb<=render_de ? (hide_frame ? render_rgb : mix) : 24'd0;end
 end
endmodule
