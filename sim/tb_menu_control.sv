`timescale 1ns/1ps
module tb_menu_control;
 reg clk=0,sdclk=0,rst=1,kn=1,kp=1,ka=1;always #5 clk=~clk;always #7 sdclk=~sdclk;
 reg ready=1;reg [5:0] count=13;reg [4:0] current=7;
 wire nn,pn,an,mute,toggle,opened,forward_n,forward_p,forward_a,request,ack,valid;wire [3:0] volume;wire [4:0] selected,page,index,target;
 audio_controls #(.CLK_HZ(1000),.DB_MS(3),.LONG_MS(30),.REPEAT_MS(12),.PULSE_MS(8),.MENU_MS(40),.CLEAN_MS(40),.ENABLE_CLEAN(1)) keys(clk,rst,kn,kp,ka,nn,pn,an,volume,mute,toggle,opened,);
 media_menu_control menu(clk,rst,toggle,nn,pn,an,ready,count,current,ack,opened,selected,page,forward_n,forward_p,forward_a,request,index);
 media_jump_cdc command(clk,rst,request,index,ack,sdclk,rst,valid,target);
 integer next_count=0,prev_count=0,auto_count=0,toggles=0,commands=0,i;reg old_n=1,old_p=1,old_a=1;
 always @(posedge clk)if(!rst)begin
  if(old_n && !forward_n)next_count<=next_count+1;
  if(old_p && !forward_p)prev_count<=prev_count+1;
  if(old_a && !forward_a)auto_count<=auto_count+1;
  if(toggle)toggles<=toggles+1;
  old_n<=forward_n;old_p<=forward_p;old_a<=forward_a;
 end
 always @(posedge sdclk)if(!rst && valid)begin commands<=commands+1;if(target!==index)$fatal(1,"Bundled command index corrupted");end
 task ticks(input integer n);begin repeat(n)@(negedge clk);end endtask
 task down;begin kn=0;ticks(12);kn=1;ticks(24);end endtask
 task up;begin kp=0;ticks(12);kp=1;ticks(24);end endtask
 task short_auto;begin ka=0;ticks(15);ka=1;ticks(24);end endtask
 task pair;begin kn=0;ticks(8);kp=0;ticks(100);kn=1;ticks(10);kp=1;ticks(24);end endtask
 initial begin
  ticks(4);rst=0;ticks(12);
  kn=0;ticks(20);if(next_count)$fatal(1,"Navigation fired before release");kn=1;ticks(24);
  if(next_count!=1)$fatal(1,"Standalone next on release");up();if(prev_count!=1)$fatal(1,"Standalone previous");
  pair();if(!opened || toggles!=1 || selected!=7 || page!=6 || next_count!=1 || prev_count!=1)$fatal(1,"Open gesture leaked navigation or initial page");
  down();if(selected!=8 || page!=6)$fatal(1,"Menu down");up();if(selected!=7)$fatal(1,"Menu up");
  for(i=0;i<7;i=i+1)up();if(selected!=0 || page!=0)$fatal(1,"First page");
  up();if(selected!=12 || page!=12)$fatal(1,"13-file wrap/last page");down();if(selected!=0)$fatal(1,"Wrap to first");
  count=32;ticks(4);up();if(selected!=31 || page!=30)$fatal(1,"32-file selection boundary");
  short_auto();if(opened || commands!=1 || index!=31 || auto_count!=0 || next_count!=1 || prev_count!=1)$fatal(1,"Confirmation leaked pause/nav or wrong jump");
  ticks(20);if(ack!=request)$fatal(1,"Command not acknowledged");short_auto();if(auto_count!=1)$fatal(1,"Playback pause did not recover");
  pair();if(!opened)$fatal(1,"Reopen");ka=0;ticks(12);kp=0;ticks(30);kp=1;ticks(12);ka=1;ticks(24);
  if(volume>=8 || !opened || commands!=1 || auto_count!=1)$fatal(1,"Menu volume chord leaked confirmation");
  ka=0;ticks(50);ka=1;ticks(24);if(!mute || !opened || commands!=1)$fatal(1,"Menu mute leaked confirmation");
  ready=0;ticks(4);down();short_auto();if(commands!=1 || selected!=0)$fatal(1,"Scanning must not jump");
  ready=1;count=0;ticks(4);down();short_auto();if(commands!=1)$fatal(1,"Empty must not jump");
  count=1;current=0;ticks(4);down();up();if(selected!=0 || page!=0)$fatal(1,"One-file clamp");
  pair();if(opened || toggles!=3 || next_count!=1 || prev_count!=1 || auto_count!=1)$fatal(1,"Close gesture leaked actions");
  kn=0;kp=0;ticks(20);kn=1;ticks(8);kp=1;ticks(24);if(opened || next_count!=1 || prev_count!=1)$fatal(1,"Short pair leaked skip");
  down();if(next_count!=2)$fatal(1,"Navigation not restored after close");
  $display("PASS physical key gestures, no pre-release skip, one toggle per hold, six-row paging, 0/1/13/32 entries, current vs selection, volume/mute, acknowledged exact jump and no close/confirm leakage");$finish;
 end
 initial begin #1000000;$fatal(1,"Timeout");end
endmodule
