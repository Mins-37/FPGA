`timescale 1ns/1ps
module tb_reader_handoff;
reg clk=0,rst=1,req=0;reg [1:0] index=1;always #10 clk=~clk;
wire ack;wire [1:0] active;wire [20:0] addr;wire app;
frame_fifo_read #(.BURST_SIZE(4)) dut(.rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),.Sdr_rd_en(1'b0),.App_wr_busy(1'b0),.O_rd_busy(),.App_rd_en(app),.App_rd_addr(addr),.read_req(req),.read_req_ack(ack),.read_finish(),.read_addr_0(21'd0),.read_addr_1(21'd307200),.read_addr_2(21'd0),.read_addr_3(21'd0),.read_addr_index(index),.read_buffer_active(active),.read_len(21'd16),.fifo_aclr(),.wrusedw(10'd0));
initial begin
 repeat(3) @(negedge clk);rst=0;req=1;wait(ack);repeat(2) @(negedge clk);
 if(active!=1 || addr!=307200) $fatal(1,"Initial reader selection not applied");
 req=0;wait(!ack);wait(app);@(negedge clk);index=0;repeat(8) @(negedge clk);
 if(active!=1) $fatal(1,"Reader buffer changed in an active burst");
 req=1;wait(ack);repeat(2) @(negedge clk);
 if(active!=0 || addr!=0) $fatal(1,"Next reader selection not acknowledged");
 $display("PASS: reader buffer acknowledgement changes only with frame request and stays fixed during active read");$finish;
end
initial begin #100000;$fatal(1,"Reader handoff timeout");end
endmodule
