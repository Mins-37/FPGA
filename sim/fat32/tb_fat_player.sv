`timescale 1ns/1ps
module tb_fat_player;
reg clk=0,rst=1,key_next=1,key_auto=1;always #5 clk=~clk;
wire valid,req,en;wire [31:0] data;wire [1:0] wb,db;wire [14:0] status;wire [7:0] debug;
reg fin=0,ack=0;reg [7:0] req_pipe=0;
sd_card_bmp #(.CLK_FREQ_HZ(1000)) dut(.clk(clk),.rst(rst),.key_next(key_next),.key_auto(key_auto),
 .bmp_width(16'd640),.bmp_height(16'd480),.display_valid(valid),.osd_status(status),.osd_debug(debug),.state_code(),
 .write_finish_toggle(fin),.frame_sync(1'b1),.pixel_write_ready(1'b1),.reader_buffer_active(db),.fade_black(1'b1),.write_buf_idx(wb),.disp_buf_idx(db),
 .write_req(req),.write_req_ack(ack),.write_en(en),.write_data(data),.SD_nCS(),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1));
function integer width(input integer k);case(k) 0:width=32;1:width=96;2:width=48;3:width=64;default:width=17;endcase endfunction
function integer height(input integer k);case(k) 0:height=24;1:height=54;2:height=80;3:height=48;default:height=11;endcase endfunction
integer count=0,frames=0,frame_id,w,h,dw,dh,ox,oy,x,y,sx,sy;
reg [23:0] expected;
always @(posedge clk) begin
 if(rst) begin req_pipe<=0;ack<=0;fin<=0;count=0;end
 else begin
  req_pipe<={req_pipe[6:0],req};ack<=req_pipe[7];
  if(req && !ack) begin
   count=0;frame_id=dut.load_idx;w=width(frame_id);h=height(frame_id);
   if(w*480>=h*640) begin dw=640;dh=h*640/w;end else begin dh=480;dw=w*480/h;end
   ox=(640-dw)/2;oy=(480-dh)/2;
  end
  if(en) begin
   if(ack) $fatal(1,"Pixel during FIFO clear");
   x=count%640;y=count/640;expected=0;
   if(x>=ox && x<ox+dw && y>=oy && y<oy+dh) begin
    sx=(x-ox)*w/dw;sy=(y-oy)*h/dh;
    expected={8'(sx+17*frame_id),8'(sy+23*frame_id),8'(sx^sy^frame_id)};
   end
   if(data!=={expected,8'd0}) $fatal(1,"Frame %0d pixel %0d got %h expected %h",frame_id,count,data,{expected,8'd0});
   count=count+1;
   if(count==307200) begin fin<=~fin;frames=frames+1;$display("Frame %0d (%0d) verified",frames,frame_id);end
   if(count>307200) $fatal(1,"Extra pixel");
  end
  if(debug[3]) $fatal(1,"Player error %h, FAT code %0d",debug,dut.fat_error_code);
 end
end
integer k;
initial begin
 repeat(5) @(negedge clk);rst=0;
 wait(valid && !debug[2]);@(negedge clk);
 if(status[10:5]!=5 || status[4:0]!=0) $fatal(1,"Wrong initial count/index %h",status);
 for(k=1;k<5;k=k+1) begin
  key_next=0;repeat(80) @(negedge clk);key_next=1;
  wait(!debug[2] && status[4:0]==k);repeat(80) @(negedge clk);
 end
 if(dut.next_index_limited(31,32)!=0 || dut.next_index_limited(30,32)!=31 || dut.next_index_limited(0,1)!=0) $fatal(1,"Index wrap failed");
 key_auto=0;repeat(80) @(negedge clk);key_auto=1;
 wait(status[11]);wait(!debug[2] && status[4:0]==0);@(negedge clk);
 if(frames!=6) $fatal(1,"Wrong frame count %0d",frames);
 $display("PASS: FAT32 -> scheduler -> fragmented BMP -> 6 x 307200 RGB pixels, manual next and auto wrap");$finish;
end
initial begin #1000000000;$fatal(1,"Player timeout status %h FATstate %0d BMPstate %0d",status,dut.u_fat32.state,dut.bmp_read_m0.state);end
endmodule

// Physical-sector card model only; real FAT32 and scheduler/decoder RTL above.
module sd_card_top(input clk,rst,output SD_nCS,SD_DCLK,SD_MOSI,input SD_MISO,
 output reg sd_init_done,input sd_sec_read,input [31:0] sd_sec_read_addr,
 output reg [7:0] sd_sec_read_data,output reg sd_sec_read_data_valid,sd_sec_read_end,
 input sd_sec_write,input [31:0] sd_sec_write_addr,input [7:0] sd_sec_write_data,
 output sd_sec_write_data_req,sd_sec_write_end);
reg [31:0] lbas[0:8191];reg [7:0] bytes[0:4194303];reg [1023:0] lp,bp;
integer n,j,lookup,selected,ptr=0,state=0,pause=0,init_cnt=0;
assign SD_nCS=1;assign SD_DCLK=0;assign SD_MOSI=1;assign sd_sec_write_data_req=0;assign sd_sec_write_end=0;
initial begin
 if(!$value$plusargs("LBAS=%s",lp)||!$value$plusargs("BYTES=%s",bp)||!$value$plusargs("N=%d",n)) $fatal(1,"Missing card image");
 $readmemh(lp,lbas,0,n-1);$readmemh(bp,bytes,0,n*512-1);
end
always @(negedge clk) begin
 if(rst) begin state=0;sd_init_done=0;init_cnt=0;sd_sec_read_data_valid=0;sd_sec_read_end=0;end
 else if(!sd_init_done) begin init_cnt=init_cnt+1;if(init_cnt==10) sd_init_done=1;end
 else case(state)
 0:begin sd_sec_read_data_valid=0;sd_sec_read_end=0;if(sd_sec_read) begin
 lookup=-1;for(j=0;j<n;j=j+1) if(lbas[j]==sd_sec_read_addr) lookup=j;
 if(lookup<0) $fatal(1,"Unexpected card address %0d",sd_sec_read_addr);
 selected=lookup;ptr=0;pause=0;state=1;end end
 1:begin
 if(pause) begin sd_sec_read_data_valid=0;pause=0;end
 else begin sd_sec_read_data_valid=1;sd_sec_read_data=bytes[selected*512+ptr];pause=1;if(ptr==511) state=2;else ptr=ptr+1;end end
 2:begin sd_sec_read_data_valid=0;sd_sec_read_end=1;state=3;end
 3:begin sd_sec_read_end=0;if(!sd_sec_read) state=0;end
 endcase
end
endmodule
