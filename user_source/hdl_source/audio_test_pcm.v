// 25MHz pixel clock -> 48kHz average PCM; stereo 1kHz sine, -18.06dBFS.
// N=6144, CTS=25000: Fs = 25MHz*N/(128*CTS) = 48000Hz.
// All 48 samples span exactly 25000 pixel cycles, so ACR is exact in this clock domain.
module audio_test_pcm(
 input wire clk, input wire rst,
 output reg sample_valid,
 output reg [23:0] left_pcm, output reg [23:0] right_pcm,
 output reg acr_valid, output reg [19:0] acr_cts, output reg [19:0] acr_n
);
 reg [24:0] sample_acc;
 wire [25:0] next_acc = {1'b0,sample_acc} + 26'd48000;
 reg [5:0] phase;
 reg [5:0] acr_count;
 function signed [23:0] sine(input [5:0] p);
 begin case(p)
        6'd0: sine = 24'sd0;
        6'd1: sine = 24'sd136867;
        6'd2: sine = 24'sd271391;
        6'd3: sine = 24'sd401273;
        6'd4: sine = 24'sd524288;
        6'd5: sine = 24'sd638333;
        6'd6: sine = 24'sd741455;
        6'd7: sine = 24'sd831891;
        6'd8: sine = 24'sd908093;
        6'd9: sine = 24'sd968758;
        6'd10: sine = 24'sd1012847;
        6'd11: sine = 24'sd1039605;
        6'd12: sine = 24'sd1048576;
        6'd13: sine = 24'sd1039605;
        6'd14: sine = 24'sd1012847;
        6'd15: sine = 24'sd968758;
        6'd16: sine = 24'sd908093;
        6'd17: sine = 24'sd831891;
        6'd18: sine = 24'sd741455;
        6'd19: sine = 24'sd638333;
        6'd20: sine = 24'sd524288;
        6'd21: sine = 24'sd401273;
        6'd22: sine = 24'sd271391;
        6'd23: sine = 24'sd136867;
        6'd24: sine = 24'sd0;
        6'd25: sine = -24'sd136867;
        6'd26: sine = -24'sd271391;
        6'd27: sine = -24'sd401273;
        6'd28: sine = -24'sd524288;
        6'd29: sine = -24'sd638333;
        6'd30: sine = -24'sd741455;
        6'd31: sine = -24'sd831891;
        6'd32: sine = -24'sd908093;
        6'd33: sine = -24'sd968758;
        6'd34: sine = -24'sd1012847;
        6'd35: sine = -24'sd1039605;
        6'd36: sine = -24'sd1048576;
        6'd37: sine = -24'sd1039605;
        6'd38: sine = -24'sd1012847;
        6'd39: sine = -24'sd968758;
        6'd40: sine = -24'sd908093;
        6'd41: sine = -24'sd831891;
        6'd42: sine = -24'sd741455;
        6'd43: sine = -24'sd638333;
        6'd44: sine = -24'sd524288;
        6'd45: sine = -24'sd401273;
        6'd46: sine = -24'sd271391;
        6'd47: sine = -24'sd136867;
 default:sine=24'sd0;
 endcase end endfunction
 always @(posedge clk or posedge rst) begin
   if(rst) begin
     sample_acc<=0;phase<=0;acr_count<=0;
     sample_valid<=0;left_pcm<=0;right_pcm<=0;
     acr_valid<=0;acr_cts<=0;acr_n<=0;
   end else begin
     sample_valid<=0;acr_valid<=0;
     if(next_acc>=26'd25000000) begin
       sample_acc<=next_acc-26'd25000000;
       sample_valid<=1;
       left_pcm<=sine(phase);right_pcm<=sine(phase);
       phase <= (phase==47) ? 0 : phase+1'b1;
       if(acr_count==47) begin
         acr_count<=0;acr_valid<=1;acr_cts<=20'd25000;acr_n<=20'd6144;
       end else acr_count<=acr_count+1'b1;
     end else sample_acc<=next_acc[24:0];
   end
 end
endmodule
