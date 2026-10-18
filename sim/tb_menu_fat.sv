`timescale 1ns/1ps
module tb_menu_fat;
reg clk=0,rst=1,scan_start=0,req=0,abort_load=0;
always #5 clk=~clk;
wire done,found,merr,rerr,cr,cvalid_out,cend_out;wire [3:0] code;
wire [31:0] found_sector,ca;wire [7:0] dout;
reg [31:0] addr=0;reg [7:0] din=0;reg dv=0,de=0;
wire name_we;wire [8:0] name_addr;wire [7:0] name_data;reg [7:0] expected_names[0:511];reg [1023:0] names_path;integer name_count=0;
fat32_store #(.ENABLE_MENU(1)) dut(.scan_name_valid(name_we),.scan_name_addr(name_addr),.scan_name_data(name_data),.clk(clk),.rst(rst),.sd_init_done(1'b1),.scan_start(scan_start),.load_abort(abort_load),
 .scan_done(done),.scan_found_valid(found),.scan_found_sector(found_sector),.mount_error(merr),.read_error(rerr),.error_code(code),
 .file_req(req),.file_addr(addr),.file_data(dout),.file_valid(cvalid_out),.file_end(cend_out),
 .card_req(cr),.card_addr(ca),.card_data(din),.card_valid(dv),.card_end(de));
reg [31:0] lbas[0:8191],requests[0:1023];reg [7:0] bytes[0:4194303];
reg [1023:0] lp,bp,rp;
integer n,nreq,expected_count,expect_mount,expect_read;
integer dev=0,ptr=0,selected=0,j,lookup,pause=0;
always @(negedge clk) begin
 if(rst) begin dev=0;dv=0;de=0;end
 else case(dev)
  0:begin dv=0;de=0;if(cr) begin
   lookup=-1;for(j=0;j<n;j=j+1) if(lbas[j]==ca) lookup=j;
   if(lookup<0) $fatal(1,"Unexpected physical LBA %0d state %0d",ca,dut.state);
   selected=lookup;ptr=0;pause=0;dev=1;
  end end
  1:begin
   if(pause) begin dv=0;pause=0;end
   else begin dv=1;din=bytes[selected*512+ptr];pause=1;if(ptr==511) dev=2;else ptr=ptr+1;end
  end
  2:begin dv=0;de=1;dev=3;end
  3:begin de=0;if(!cr) dev=0;end
 endcase
end
integer found_count=0,received=0,expected_slot=0,request_index;
reg got_error=0;
always @(posedge clk) if(!rst) begin
 if(name_we)begin
  if(name_addr!==(name_count/12)*16+name_count%12 || name_data!==expected_names[name_addr])$fatal(1,"Sorted name/meta mismatch byte %0d address %0d got %h expected %h",name_count,name_addr,name_data,expected_names[name_addr]);
  name_count=name_count+1;
 end
 if(found) begin
  if(found_sector!==found_count*32768) $fatal(1,"Wrong catalogue virtual address");
  found_count=found_count+1;
 end
 if(rerr) got_error=1;
 if(cvalid_out) begin
  if(received>=512 || dout!==bytes[expected_slot*512+received]) $fatal(1,"Data mismatch request %0d byte %0d",request_index,received);
  received=received+1;
 end
end
initial begin
 if(!$value$plusargs("LBAS=%s",lp) || !$value$plusargs("BYTES=%s",bp) || !$value$plusargs("REQ=%s",rp) ||
 !$value$plusargs("N=%d",n) || !$value$plusargs("COUNT=%d",expected_count) || !$value$plusargs("NREQ=%d",nreq) ||
 !$value$plusargs("MERR=%d",expect_mount) || !$value$plusargs("RERR=%d",expect_read)) $fatal(1,"Missing arguments");
 if(!$value$plusargs("NAMES=%s",names_path))$fatal(1,"Expected names missing");$readmemh(names_path,expected_names);
 $readmemh(lp,lbas,0,n-1);$readmemh(bp,bytes,0,n*512-1);
 if(nreq>0) $readmemh(rp,requests,0,nreq*2-1);
 repeat(4) @(negedge clk);rst=0;scan_start=1;@(negedge clk);scan_start=0;
 wait(done || merr);@(negedge clk);
 if(expect_mount) begin if(!merr) $fatal(1,"Invalid volume accepted");$display("PASS: invalid FAT32 volume rejected, code %0d",code);$finish;end
 if(merr || found_count!=expected_count) $fatal(1,"Catalogue count got %0d expected %0d error %0d",found_count,expected_count,code);
 if(name_count!=expected_count*12)$fatal(1,"Missing serialized names %0d",name_count);
 for(request_index=0;request_index<nreq;request_index=request_index+1) begin
  wait(dut.state==19);@(negedge clk);addr=requests[request_index*2];received=0;got_error=0;
  for(j=0;j<n;j=j+1) if(lbas[j]==requests[request_index*2+1]) expected_slot=j;
  req=1;
  if(expect_read) begin wait(got_error);@(negedge clk);req=0;abort_load=1;@(negedge clk);abort_load=0;repeat(5) @(negedge clk);if(!done) $fatal(1,"Catalogue lost on abort");$display("PASS: bad file chain rejected, catalogue preserved, code %0d",code);$finish;end
  wait(cend_out);@(negedge clk);req=0;
  if(received!=512) $fatal(1,"Wrong byte count %0d",received);
 end
 $display("PASS: sorted SFN+length+type for %0d files, %0d real fragmented-sector requests",found_count,nreq);$finish;
end
initial begin #1000000000;$fatal(1,"Timeout state %0d io %0d code %0d",dut.state,dut.io_state,code);end
endmodule
