`timescale 1ns/1ps
module tb_av_header;
parameter FRAME=2,FRAMES=3,FPS=10,BAD=0,ABORT=0,STALL=1,BYTE_GAP=1;
localparam BASE=32768;
reg clk=0,rst=1,start=0,abort_load=0;always #5 clk=~clk;
wire ready,error,wr_req,rd_req,en;wire [31:0] rd_addr;wire [23:0] pixel;wire [15:0] frames;wire [7:0] fps;
reg ack=0;reg [7:0] req_pipe=0;integer cycles=0;
wire pixel_ready=!STALL || cycles%997>=90;
reg ready_d=0;reg [7:0] din=0;reg dv=0,de=0;
anm_read dut(.av_mode(1'b1),.clk(clk),.rst(rst),.load_start(start),.load_abort(abort_load),.load_sector(32'(BASE)),.frame_index(16'(FRAME)),
 .ready(ready),.error(error),.frame_count(frames),.frame_rate(fps),.write_req(wr_req),.write_req_ack(ack),.pixel_ready(pixel_ready),
 .sd_sec_read(rd_req),.sd_sec_read_addr(rd_addr),.sd_sec_read_data(din),.sd_sec_read_data_valid(dv),.sd_sec_read_end(de),.bmp_data_wr_en(en),.bmp_data(pixel));
always @(posedge clk) begin req_pipe<={req_pipe[6:0],wr_req};ack<=req_pipe[7];cycles<=cycles+1;ready_d<=pixel_ready;end
function automatic [7:0] at_byte(input integer n);
integer total,k,f,x,y,c;reg [15:0] packed_pixel;
begin
 at_byte=0;total=512+FRAMES*38400;
 case(n)
 0:at_byte=BAD==1 ? 0 : "H";1:at_byte="X";2:at_byte="A";3:at_byte="1";
 4:at_byte=160;6:at_byte=120;8:at_byte=BAD==4 ? 8 : BAD==9 ? 5 : FPS;
 10:at_byte=FRAMES&255;11:at_byte=FRAMES>>8;
 12,13,14,15:at_byte=(38400>>((n-12)*8))&255;
 16,17,18,19:at_byte=((total+(BAD==3 ? 1 : 0))>>((n-16)*8))&255;
 20:at_byte=BAD==2 ? 2 : 1;22:at_byte=1;
 24:at_byte=BAD==5 ? 0 : "A";25:at_byte="V";26:at_byte="M";27:at_byte="1";
 28,29,30,31:at_byte=((BAD==6 ? 44100 : 48000)>>((n-28)*8))&255;
 32:at_byte=BAD==7 ? 1 :2;34:at_byte=BAD==8 ? 24:16;
 default:if(n>=512) begin
  k=n-512;f=k/38400;x=(k%38400)/2%160;y=(k%38400)/320;
  packed_pixel={5'((x+f*3)&31),6'((y+f*5)&63),5'((x^y^f)&31)};
  at_byte=n%2 ? packed_pixel[15:8] : packed_pixel[7:0];
 end
 endcase
end endfunction
integer dev=0,ptr,sector,pause=0,reads=0,j;
always @(negedge clk) begin
 if(rst) begin dev=0;dv=0;de=0;end
 else case(dev)
 0:begin dv=0;de=0;if(rd_req) begin
  sector=rd_addr;ptr=0;pause=0;dev=1;
  if(reads==0 && sector!=BASE) $fatal(1,"Header seek error");
  if(reads>0 && sector!=BASE+1+FRAME*75+reads-1) $fatal(1,"Repeated/skipped data sector %0d after %0d reads",sector,reads);
  reads=reads+1;
 end end
 1:begin
  if(pause) begin dv=0;pause=pause-1;end
  else begin dv=1;din=at_byte((sector-BASE)*512+ptr);pause=BYTE_GAP;if(ptr==511) dev=2;else ptr=ptr+1;end
 end
 2:begin dv=0;de=1;dev=3;end
 3:begin de=0;if(!rd_req) dev=0;end
 endcase
end
integer count=0,x,y,r,g,b;reg [23:0] expected;reg error_seen=0;
always @(posedge clk) if(!rst) begin
 if(error) error_seen=1;
 if(en && !abort_load) begin
  if(ack || !ready_d) $fatal(1,"Pixel ignored FIFO handshake/backpressure");
  x=(count%640)/4;y=(count/640)/4;r=(x+FRAME*3)&31;g=(y+FRAME*5)&63;b=(x^y^FRAME)&31;
  expected={r[4:0],r[4:2],g[5:0],g[5:4],b[4:0],b[4:2]};
  if(pixel!==expected) $fatal(1,"Pixel %0d got %h expected %h",count,pixel,expected);
  count=count+1;
  if(count>307200) $fatal(1,"Extra pixel");
 end
end
initial begin
 repeat(5) @(negedge clk);rst=0;start=1;@(negedge clk);start=0;
 if(ABORT) begin
  wait(count==1000);@(negedge clk);abort_load=1;repeat(2) @(negedge clk);abort_load=0;repeat(5) @(negedge clk);
  if(!ready || wr_req || en || rd_req) $fatal(1,"Abort failed");$display("PASS: animation abort releases source and writer");$finish;
 end
 if(BAD || FRAME>=FRAMES) begin
  wait(error_seen);wait(ready);repeat(3) @(negedge clk);
  if(count!=0 || reads!=1 || wr_req) $fatal(1,"Invalid header emitted data");$display("PASS: invalid animation/header frame rejected");$finish;
 end
 wait(count==307200);wait(ready);@(negedge clk);
 if(error_seen || frames!=FRAMES || fps!=FPS || reads!=76) $fatal(1,"Metadata/read count failed");
 if(BYTE_GAP==31 && cycles>=10000000) $fatal(1,"Source missed 100ms target at 100MHz");
 $display("PASS: ANM frame %0d/%0d fps=%0d, 307200 RGB565-expanded pixels, 76 sector reads, stalls=%0d, byte_gap=%0d, cycles=%0d",FRAME,FRAMES,FPS,STALL,BYTE_GAP,cycles);$finish;
end
initial begin #100000000;$fatal(1,"ANM timeout state %0d pixels %0d",dut.state,count);end
endmodule
