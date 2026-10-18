`timescale 1ns/1ps
module tb_media_progress;
 reg clk=0,rst=1,active=0;reg [21:0] played=0,duration=0;always #20 clk=~clk;
 wire [9:0] elapsed,total;wire [8:0] fill;wire valid;
 media_progress dut(.clk(clk),.rst(rst),.active(active),.played(played),.duration(duration),.elapsed_tenths(elapsed),.total_tenths(total),.fill(fill),.valid(valid));
 integer cases=0,i,p,d,ep,ef;
 task check(input integer pp,input integer dd);begin
  @(negedge clk);played=pp;duration=dd;active=1;repeat(220)@(negedge clk);
  ep=pp>dd ? dd:pp;ef=(ep*400)/dd;
  if(!valid ||elapsed!==ep/4800 ||total!==dd/4800 ||fill!==ef)$fatal(1,"Progress p=%0d d=%0d got %0d/%0d fill%0d expected %0d/%0d fill%0d",pp,dd,elapsed,total,fill,ep/4800,dd/4800,ef);
  cases=cases+1;
 end endtask
 initial begin
  repeat(4)@(negedge clk);rst=0;
  check(0,441600);check(220800,441600);check(441599,441600);check(441600,441600);check(500000,441600);
  check(4194292,4194293);check(1440000,1440000);check(48000,1440000);
  for(i=0;i<60;i=i+1)begin d=$urandom_range(4190000,512);p=$urandom_range(d,0);check(p,d);end
  p=played;d=duration;repeat(1000)@(negedge clk);if(elapsed!==p/4800 ||fill!==(p*400)/d)$fatal(1,"Paused time advanced");
  check(0,441600);@(negedge clk);active=0;repeat(3)@(negedge clk);if(valid ||fill!=0)$fatal(1,"Inactive progress remained visible");
  active=1;duration=0;repeat(110)@(negedge clk);if(valid)$fatal(1,"Zero duration divide");
  $display("PASS %0d progress arithmetic cases, pause, loop reset, inactive/zero duration",cases);$finish;
 end
endmodule
