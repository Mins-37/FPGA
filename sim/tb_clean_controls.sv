`timescale 1ns/1ps
module tb_clean_controls;
 reg clk=0,rst=1,kn=1,kp=1,ka=1,opened=0;always #5 clk=~clk;
 wire nn,pn,an,mute,menu,clean;wire [3:0] vol;
 audio_controls #(.CLK_HZ(1000),.DB_MS(3),.LONG_MS(30),.REPEAT_MS(12),.PULSE_MS(8),.MENU_MS(40),.CLEAN_MS(40),.ENABLE_CLEAN(1)) dut(clk,rst,kn,kp,ka,nn,pn,an,vol,mute,menu,opened,clean);
 integer nc=0,pc=0,ac=0,mc=0,cc=0;reg on=1,op=1,oa=1;
 always @(posedge clk) if(!rst)begin
  on<=nn;op<=pn;oa<=an;
  if(on&&!nn)nc<=nc+1;if(op&&!pn)pc<=pc+1;if(oa&&!an)ac<=ac+1;
  if(menu)mc<=mc+1;if(clean)cc<=cc+1;
 end
 task ticks(input integer n);begin repeat(n)@(negedge clk);end endtask
 initial begin
  ticks(4);rst=0;ticks(12);
  kn=0;ticks(16);kn=1;ticks(24);if(nc!=1||cc)$fatal(1,"short next");
  kn=0;ticks(180);if(cc||nc!=1)$fatal(1,"wait for long release");kn=1;ticks(24);
  if(cc!=1||nc!=1)$fatal(1,"one clean toggle, no next");
  kn=0;ticks(65);kn=1;ticks(24);if(cc!=2||nc!=1)$fatal(1,"clean exit");
  kn=0;ticks(65);kp=0;ticks(100);kn=1;ticks(12);kp=1;ticks(24);
  if(mc!=1||cc!=2||nc!=1||pc)$fatal(1,"late menu chord priority");
  kn=0;kp=0;ticks(100);kp=1;ticks(65);kn=1;ticks(24);
  if(mc!=2||cc!=2||nc!=1)$fatal(1,"pair release priority");
  opened=1;kn=0;ticks(100);kn=1;ticks(24);opened=0;
  if(nc!=2||cc!=2)$fatal(1,"menu long down remains navigation");
  ka=0;ticks(12);kp=0;ticks(20);kp=1;ticks(12);ka=1;ticks(24);
  if(vol>=8||cc!=2||pc||ac||mc!=2)$fatal(1,"volume down conflict");
  ka=0;ticks(12);kn=0;ticks(100);kn=1;ticks(12);ka=1;ticks(24);
  if(vol!=8||cc!=2||nc!=2||ac)$fatal(1,"volume up conflict");
  kn=0;ticks(65);ka=0;ticks(25);ka=1;ticks(15);kn=1;ticks(24);
  if(cc!=2||nc!=2||ac)$fatal(1,"late volume modifier conflict");
  ka=0;ticks(65);ka=1;ticks(24);if(!mute||ac)$fatal(1,"mute preserved");
  kp=0;ticks(16);kp=1;ticks(24);if(pc!=1)$fatal(1,"previous preserved");
  kn=0;ticks(1);kn=1;ticks(24);if(cc!=2||nc!=2)$fatal(1,"bounce");
  $display("PASS clean long/release/one-shot, short next, menu priority/late chord/release order, menu navigation, volume/mute priority, previous, bounce");$finish;
 end
endmodule
