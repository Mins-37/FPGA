`timescale 1ns/1ps
// Synthetic contiguous BMP device plus a pixel-by-pixel independent fit oracle.
module tb_bmp_scaler;
 parameter W=3,H=2,TOP_DOWN=0,BYTE_GAP=0;
 localparam STRIDE=((W*3+3)/4)*4,FILELEN=54+STRIDE*H,BASE=64;
 reg clk=0,rst=1,scan_start=0,load_start=0;
 always #5 clk=~clk;
 wire ready,done,found,write_req,read_req,wr_en;
 reg ack=0; reg [7:0] req_pipe=0;
 always @(posedge clk) begin req_pipe<={req_pipe[6:0],write_req}; ack<=req_pipe[7]; end
 always @(posedge clk) if(wr_en && ack) $fatal(1,"Pixel emitted while writer FIFO still in reset");
 wire [31:0] found_sector,read_addr;
 wire [2:0] total;
 wire [23:0] pixel;
 reg [7:0] sd_data=0;
 reg sd_valid=0,sd_end=0;
 bmp_read dut(.clk(clk),.rst(rst),.ready(ready),
 .scan_start(scan_start),.scan_start_sector(32'(BASE)),.scan_max_sector(32'd131071),
 .scan_target_count(3'd1),.scan_done(done),.scan_found_valid(found),
 .scan_found_sector(found_sector),.scan_found_total(total),
 .load_start(load_start),.load_abort(1'b0),.load_sector(32'(BASE)),
 .sd_init_done(1'b1),.state_code(),.bmp_width(16'd640),.bmp_height(16'd480),
 .write_req(write_req),.write_req_ack(ack),.sd_sec_read(read_req),
 .sd_sec_read_addr(read_addr),.sd_sec_read_data(sd_data),
 .sd_sec_read_data_valid(sd_valid),.sd_sec_read_end(sd_end),
 .bmp_data_wr_en(wr_en),.bmp_data(pixel));
 function automatic [7:0] at_byte(input integer n);
 integer stored_height,k,physical_row,source_row,source_x,component;
 begin
  stored_height=TOP_DOWN ? -H : H;at_byte=0;
  case(n)
   0:at_byte=8'h42;1:at_byte=8'h4d;
   2,3,4,5:at_byte=(FILELEN>>((n-2)*8))&255;
   10:at_byte=54;14:at_byte=40;
   18,19,20,21:at_byte=(W>>((n-18)*8))&255;
   22,23,24,25:at_byte=(stored_height>>((n-22)*8))&255;
   26:at_byte=1;28:at_byte=24;
   default:begin
    if(n>=54 && n<FILELEN) begin
     k=n-54;physical_row=k/STRIDE;
     source_row=TOP_DOWN ? physical_row : H-1-physical_row;
     source_x=(k%STRIDE)/3;component=(k%STRIDE)%3;
     if(source_x<W) case(component)
      0:at_byte=(source_x^source_row)&255;
      1:at_byte=source_x&255;
      2:at_byte=source_row&255;
     endcase
    end
   end
  endcase
 end endfunction
 integer device_state=0,byte_number=0,sector,pause_count=0;
 always @(negedge clk) begin
  if(rst) begin device_state=0;sd_valid=0;sd_end=0;end
  else case(device_state)
   0:begin sd_valid=0;sd_end=0;if(read_req) begin sector=read_addr;byte_number=0;pause_count=0;device_state=1;end end
   1:begin
    if(pause_count!=0) begin sd_valid=0;pause_count=pause_count-1;end
    else begin
     sd_valid=1;sd_data=at_byte((sector-BASE)*512+byte_number);pause_count=BYTE_GAP;
     if(byte_number==511) device_state=2;else byte_number=byte_number+1;
    end
   end
   2:begin sd_valid=0;sd_end=1;device_state=3;end
   3:begin sd_end=0;if(!read_req) device_state=0;end
  endcase
 end
 integer dw,dh,ox,oy,count=0,x,y,sx,sy;
 reg [23:0] expected;
 initial begin
  if(W*480>=H*640) begin dw=640;dh=H*640/W;if(dh==0) dh=1;end
  else begin dh=480;dw=W*480/H;if(dw==0) dw=1;end
  ox=(640-dw)/2;oy=(480-dh)/2;
  repeat(3) @(negedge clk);rst=0;
  @(negedge clk);scan_start=1;@(negedge clk);scan_start=0;
  wait(done && ready);@(negedge clk);
  if(total!=1 || found_sector!=BASE) $fatal(1,"Scan failed");
  load_start=1;@(negedge clk);load_start=0;
  wait(count==307200);wait(ready);@(negedge clk);
  $display("PASS: %0dx%0d top_down=%0d -> %0dx%0d, 307200 RGB pixels",W,H,TOP_DOWN,dw,dh);
  $finish;
 end
 always @(posedge clk) if(!rst && wr_en) begin
  x=count%640;y=count/640;expected=0;
  if(x>=ox && x<ox+dw && y>=oy && y<oy+dh) begin
   sx=(x-ox)*W/dw;sy=(y-oy)*H/dh;
   expected={8'(sy),8'(sx),8'(sx^sy)};
  end
  if(pixel!==expected) $fatal(1,"Pixel %0d (%0d,%0d): got %h expected %h",count,x,y,pixel,expected);
  count=count+1;
  if(count>307200) $fatal(1,"Extra output pixel");
 end
 initial begin #100000000;$fatal(1,"Timeout");end
endmodule
