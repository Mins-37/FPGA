// Oscilloscope display from the actual left PCM passed to the HDMI transmitter.
// Positive zero-cross trigger; retain the full 48kHz sample rate for smooth curves.
// Two 128-sample banks swap only at VS: capture never writes the displayed bank.
module audio_waveform(
 input wire clk,input wire rst,input wire sample_valid,input wire signed [23:0] pcm,
 input wire in_vs,input wire in_de,input wire [23:0] in_rgb,
 output reg out_vs,output reg out_de,output reg [23:0] out_rgb
);
 reg [6:0] samples[0:255];
 reg display_bank,write_bank,display_valid,capture,ready,was_negative;
 reg [6:0] write_index;
 reg vs_d,de_d;
 reg [9:0] x,y;
 wire frame_edge=in_vs && !vs_d;
 wire signed [23:0] amplitude=pcm>>>15;
 wire [6:0] sample_y=(amplitude>24'sd40) ? 7'd0 :
                     (amplitude< -24'sd40) ? 7'd80 : (24'sd40-amplitude);
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   display_bank<=0;write_bank<=1;display_valid<=0;
   capture<=0;ready<=0;was_negative<=0;write_index<=0;
   vs_d<=0;de_d<=0;x<=0;y<=0;
  end else begin
   vs_d<=in_vs;de_d<=in_de;
   if(in_vs!=vs_d) begin x<=0;y<=0;end
   else if(in_de) x<=x+1'b1;
   else begin x<=0;if(de_d) y<=y+1'b1;end
   if(frame_edge && ready) begin
    display_bank<=write_bank;write_bank<=~write_bank;display_valid<=1;
    ready<=0;capture<=0;write_index<=0;
   end
   if(sample_valid) begin
    was_negative<=pcm[23];
    if(!ready) begin
     if(!capture) begin
      if(was_negative && !pcm[23]) begin
       samples[{write_bank,7'd0}]<=sample_y;
       capture<=1;write_index<=1;
      end
     end else begin
      samples[{write_bank,write_index}]<=sample_y;
      if(write_index==127) begin ready<=1;capture<=0;end
      else write_index<=write_index+1'b1;
     end
    end
   end
  end
 end
 wire plot=(x>=480 && x<608 && y>=340 && y<=420);
 wire panel=(x>=464 && x<624 && y>=312 && y<432);
 wire [6:0] col=x-480;
 wire [6:0] previous_col=(col==0) ? 0 : col-1'b1;
 wire [6:0] current_y=display_valid ? samples[{display_bank,col}] : 7'd40;
 wire [6:0] previous_y=display_valid ? samples[{display_bank,previous_col}] : 7'd40;
 wire [9:0] row=y-340;
 wire trace=(current_y<=previous_y) ? (row>=current_y && row<=previous_y) :
                                              (row>=previous_y && row<=current_y);
 wire border=panel && (x==464 || x==623 || y==312 || y==431);
 wire grid=plot && (col[4:0]==0 || row==0 || row==20 || row==40 || row==60 || row==80);
 reg [23:0] mix;
 always @* begin
  mix=in_rgb;
  if(panel) mix={2'b00,in_rgb[23:18],2'b00,in_rgb[15:10],2'b00,in_rgb[7:2]};
  if(grid) mix=24'h24505D;
  if(border) mix=24'h7DE8FF;
  if(plot && trace) mix=24'h80FF70;
 end
 always @(posedge clk or posedge rst) begin
  if(rst) begin out_vs<=0;out_de<=0;out_rgb<=0;end
  else begin out_vs<=in_vs;out_de<=in_de;out_rgb<=in_de ? mix : 24'd0;end
 end
endmodule
