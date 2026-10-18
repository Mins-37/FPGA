`timescale 1ns/1ps
module tb_clean_video;
 reg clk=0,rst=1,vs=0,de=0,hide=0;reg [23:0] rgb=0;always #5 clk=~clk;
 reg [1:0] hide_pipe=0;always @(posedge clk)if(rst)hide_pipe<=0;else hide_pipe<={hide_pipe[0],hide};
 wire wv,wd,ov,od;wire [23:0] wr,orr;
 audio_waveform #(.ENABLE_CLEAN(1)) w(.clk(clk),.rst(rst),.sample_valid(1'b0),.pcm(24'd0),.spectrum_levels(64'h3030303030303030),.spectrum_stable(1'b1),.in_vs(vs),.in_de(de),.in_rgb(rgb),.out_vs(wv),.out_de(wd),.out_rgb(wr),.hide_overlays(hide));
 video_osd #(.ENABLE_CLEAN(1)) o(.clk(clk),.rst(rst),.in_vs(wv),.in_de(wd),.in_rgb(wr),.volume(4'd8),.muted(1'b0),.elapsed_tenths(10'd15),.total_tenths(10'd92),.progress_fill(9'd200),.progress_valid(1'b1),.status(17'h1a000),.controls(4'd0),.debug_status(8'd0),.out_vs(ov),.out_de(od),.out_rgb(orr),.hide_overlays(hide_pipe[1]));
 reg [23:0] eq[0:3];reg [3:0] dq=0,vq=0,cq=0;reg expected_clean=0;
 integer i,f,x,y,clean_pixels=0,normal_changes=0;
 always @(posedge clk)begin
  if(rst)begin dq=0;vq=0;cq=0;for(i=0;i<4;i=i+1)eq[i]=0;end
  else begin
   for(i=3;i>0;i=i-1)begin eq[i]=eq[i-1];dq[i]=dq[i-1];vq[i]=vq[i-1];cq[i]=cq[i-1];end
   eq[0]=rgb;dq[0]=de;vq[0]=vs;cq[0]=expected_clean;
   #1;
   if(od!==dq[3]||ov!==vq[3])$fatal(1,"RGB/DE/VS latency changed");
   if(od && cq[3])begin clean_pixels=clean_pixels+1;if(orr!==eq[3])$fatal(1,"Clean frame changed pixel expected %h got %h",eq[3],orr);end
   if(od && !cq[3] && orr!==eq[3])normal_changes=normal_changes+1;
  end
 end
 task tick;begin @(negedge clk);end endtask
 initial begin
  repeat(5)tick();rst=0;repeat(8)tick();
  for(f=0;f<4;f=f+1)begin
   expected_clean=f==1 || f==3;if(f==3)hide=1;vs=1;if(f==3)begin tick();hide=0;repeat(9)tick();end else repeat(10)tick();vs=0;repeat(10)tick();
   for(y=0;y<480;y=y+1)begin
    if(y==100 && f<3)hide=f==0;
    for(x=0;x<640;x=x+1)begin de=1;rgb={x[7:0],y[7:0],8'hb9};tick();end
    de=0;repeat(8)tick();
   end
   repeat(20)tick();
  end
  if(clean_pixels!=614400||normal_changes<10000)$fatal(1,"Clean coverage/overlay restore %d %d",clean_pixels,normal_changes);
  $display("PASS full 640x480 clean exact RGB, mid-frame and VS-boundary deferred toggle, normal overlays restored, unchanged RGB/DE/VS latency (%0d pixels)",clean_pixels);$finish;
 end
endmodule
