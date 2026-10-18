`timescale 1ns/1ps
module tb_audio_controls;
 reg clk=0,rst=1,kn=1,kp=1,ka=1;always #5 clk=~clk;
 wire nn,pn,an,mute;wire [3:0] vol;
 audio_controls #(.CLK_HZ(1000),.DB_MS(3),.LONG_MS(30),.REPEAT_MS(12),.PULSE_MS(8)) dut(clk,rst,kn,kp,ka,nn,pn,an,vol,mute,,1'b0,);
 wire np,pp,ap;
 key_press_debounce #(.CLK_FREQ_HZ(1000),.DEBOUNCE_MS(5)) dn(clk,rst,nn,np),dp(clk,rst,pn,pp),da(clk,rst,an,ap);
 integer nc=0,pc=0,ac=0;
 wire np2,pp2,ap2;integer nc2=0,pc2=0,ac2=0;
 key_event_sync sn(clk,rst,nn,np2),sp(clk,rst,pn,pp2),sa(clk,rst,an,ap2);
 always @(posedge clk) if(!rst) begin if(np2)nc2<=nc2+1;if(pp2)pc2<=pc2+1;if(ap2)ac2<=ac2+1;end
 always @(posedge clk) if(!rst) begin if(np)nc<=nc+1;if(pp)pc<=pc+1;if(ap)ac<=ac+1;end
 task ticks(input integer n);begin repeat(n)@(negedge clk);end endtask
 initial begin
  ticks(4);rst=0;ticks(12);
  // Bounce shorter than debounce must never emit an event.
  kn=0;ticks(1);kn=1;ticks(1);kn=0;ticks(1);kn=1;ticks(20);
  if(nc || pc || ac)$fatal(1,"Bounce leaked");
  kn=0;ticks(20);kn=1;ticks(20);kp=0;ticks(20);kp=1;ticks(20);
  if(nc!=1 || pc!=1 || ac!=0)$fatal(1,"Navigation counts");
  ka=0;ticks(15);ka=1;ticks(25);
  if(ac!=1 || mute)$fatal(1,"Short KEY4 must only pause");
  ka=0;ticks(50);ka=1;ticks(25);
  if(!mute || ac!=1)$fatal(1,"Long KEY4 must only mute");
  ka=0;ticks(12);kp=0;ticks(8);kp=1;ticks(8);
  if(vol!=7)$fatal(1,"Volume down first step %d",vol);
  kp=0;ticks(110);ka=1;ticks(15);kp=1;ticks(25);
  if(vol!=0 || !mute || nc!=1 || pc!=1 || ac!=1)$fatal(1,"Down chord leakage/clamp %d",vol);
  ka=0;ticks(12);kn=0;ticks(130);kn=1;ticks(12);ka=1;ticks(25);
  if(vol!=8 || !mute || nc!=1 || pc!=1 || ac!=1)$fatal(1,"Up chord leakage/clamp");
  ka=0;ticks(12);kn=0;kp=0;ticks(50);kn=1;kp=1;ka=1;ticks(25);
  if(vol!=8 || nc!=1 || pc!=1 || ac!=1 || !mute)$fatal(1,"Both chord keys");
  ka=0;ticks(50);ka=1;ticks(25);if(mute || ac!=1)$fatal(1,"Unmute");
  kp=0;ticks(20);kp=1;ticks(20);if(pc!=2)$fatal(1,"Navigation did not recover");
  if(nc2!=nc || pc2!=pc || ac2!=ac)$fatal(1,"Clean-event CDC counts differ from legacy debounced receiver");
  $display("PASS key bounce, next/previous, short pause, long mute, volume chords/repeat/clamp, release order, no navigation leakage, clean-event CDC");$finish;
 end
endmodule
