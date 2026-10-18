`timescale 1ns/1ps
// Regression: aborting a load must not invalidate an already scanned catalogue.
module tb_bmp_abort;
 reg clk=0,rst=1,start=0,abort_load=0,valid=0,ending=0;
 reg [7:0] data=0;
 always #5 clk=~clk;
 wire ready,done,found,read_req;
 wire [31:0] found_sector,read_addr;
 wire [2:0] total;
 bmp_read dut(.clk(clk),.rst(rst),.ready(ready),
 .scan_start(start),.scan_start_sector(32'd100),.scan_max_sector(32'd1000),
 .scan_target_count(3'd1),.scan_done(done),.scan_found_valid(found),
 .scan_found_sector(found_sector),.scan_found_total(total),
 .load_start(1'b0),.load_abort(abort_load),.load_sector(32'd100),
 .sd_init_done(1'b1),.state_code(),.bmp_width(16'd640),.bmp_height(16'd480),
 .write_req(),.write_req_ack(1'b0),.sd_sec_read(read_req),
 .sd_sec_read_addr(read_addr),.sd_sec_read_data(data),
 .sd_sec_read_data_valid(valid),.sd_sec_read_end(ending),
 .bmp_data_wr_en(),.bmp_data());
 function automatic [7:0] header(input integer n);
 begin case(n)
  0:header=8'h42;1:header=8'h4d;
  2:header=8'h36;3:header=8'h10;4:header=8'h0e;
  10:header=54;14:header=40;
  18:header=8'h80;19:header=8'h02;
  22:header=8'he0;23:header=8'h01;
  26:header=1;28:header=24;
  default:header=0;
 endcase end endfunction
 integer i;
 initial begin
  repeat(3) @(negedge clk);rst=0;
  @(negedge clk);start=1;@(negedge clk);start=0;
  wait(read_req);@(negedge clk);
  for(i=0;i<512;i=i+1) begin valid=1;data=header(i);@(negedge clk);end
  valid=0;ending=1;@(negedge clk);ending=0;
  wait(done && ready);@(negedge clk);
  if(!done || total!=1 || !ready) $fatal(1,"Catalogue setup failed");
  abort_load=1;@(negedge clk);abort_load=0;
  wait(done && ready);@(negedge clk);
  if(!done || total!=1 || !ready) $fatal(1,"Load abort erased catalogue");
  rst=1;@(negedge clk);
  if(done || total!=0) $fatal(1,"Reset must clear catalogue");
  $display("PASS: load abort preserves catalogue, system reset clears it");
  $finish;
 end
 initial begin #100000;$fatal(1,"Timeout");end
endmodule
