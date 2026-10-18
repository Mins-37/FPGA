`timescale 1ns/1ps
module tb_audio_test_pcm;
 reg clk=0,rst=1;
 always #20 clk=~clk;
 wire valid,acr_valid;
 wire [23:0] left_pcm,right_pcm;
 wire [19:0] cts,n;
 audio_test_pcm dut(clk,rst,valid,left_pcm,right_pcm,acr_valid,cts,n);
 integer cycle,samples,acrs,last_sample;
 initial begin
   repeat(3) @(negedge clk);
   rst=0;samples=0;acrs=0;last_sample=0;
   for(cycle=1;cycle<=250000;cycle=cycle+1) begin
     @(negedge clk);
     if(valid) begin
       if(samples>0 && cycle-last_sample!=520 && cycle-last_sample!=521)
         $fatal(1,"Sample spacing");
       if(left_pcm!==right_pcm) $fatal(1,"Stereo mismatch");
       if($signed(left_pcm)>1048576 || $signed(left_pcm)<-1048576)
         $fatal(1,"PCM range");
       samples=samples+1;last_sample=cycle;
     end
     if(acr_valid) begin
       acrs=acrs+1;
       if(cycle%25000 || cts!=25000 || n!=6144)
         $fatal(1,"ACR rate/parameters");
     end
   end
   if(samples!=480 || acrs!=10) $fatal(1,"Sample or ACR count");
   rst=1;@(negedge clk);
   if(valid || acr_valid || left_pcm || right_pcm) $fatal(1,"Reset");
   $display("PASS: 480 samples and 10 ACR packets per 10ms; stereo and reset");
   $finish;
 end
 initial begin #11000000; $fatal(1,"Timeout");end
endmodule
