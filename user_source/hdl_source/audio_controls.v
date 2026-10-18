// Board KEY2/3 navigation; KEY4 modifier provides volume without using image switches.
// Sanitized 80ms active-low pulses are accepted by the existing SD-domain debounce.
module audio_controls #(parameter CLK_HZ=25000000, DB_MS=10, LONG_MS=700, REPEAT_MS=250, PULSE_MS=80, MENU_MS=1000, ENABLE_CLEAN=0, CLEAN_MS=1000)(
 input wire clk,rst,input wire key_next,key_prev,key_auto,
 output wire next_n,prev_n,auto_n,output reg [3:0] volume,output reg mute,output reg menu_toggle, input wire menu_open, output reg clean_toggle
);
 localparam DB=DB_MS, LONG=LONG_MS, REPEAT=REPEAT_MS, PULSE=PULSE_MS;
 localparam MS_CYCLES=CLK_HZ/1000;
 reg [$clog2(MS_CYCLES+1)-1:0] ms_count;
 wire ms_tick=ms_count==MS_CYCLES-1;
 reg [2:0] sync0,sync1,candidate,stable,old;
 reg [$clog2(DB+1)-1:0] debounce;
 reg [$clog2(LONG+1)-1:0] held;
 reg [$clog2(REPEAT+1)-1:0] repeat_count;
 reg [$clog2(PULSE+1)-1:0] next_count,prev_count,auto_count;
 reg chord;reg [1:0] direction;
 reg [1:0] nav_pending;reg nav_pair,nav_latched;
 reg [$clog2(MENU_MS+1)-1:0] nav_held;
 reg [$clog2(CLEAN_MS+1)-1:0] clean_held;reg clean_pending,clean_blocked;
 wire [2:0] pressed=old & ~stable;
 wire auto_release=!old[2] && stable[2];
 wire [1:0] request=stable[2] ? 2'd0 : (!stable[0] && stable[1]) ? 2'd1 : (stable[0] && !stable[1]) ? 2'd2 : 2'd0;
 assign next_n=next_count==0;assign prev_n=prev_count==0;assign auto_n=auto_count==0;
 always @(posedge clk or posedge rst) begin
  if(rst) begin clean_toggle<=0;clean_held<=0;clean_pending<=0;clean_blocked<=0;menu_toggle<=0;nav_pending<=0;nav_pair<=0;nav_latched<=0;nav_held<=0;ms_count<=0;sync0<=7;sync1<=7;candidate<=7;stable<=7;old<=7;debounce<=0;held<=0;repeat_count<=0;direction<=0;chord<=0;next_count<=0;prev_count<=0;auto_count<=0;volume<=8;mute<=0;end
  else begin
   menu_toggle<=0;clean_toggle<=0;
   sync0<={key_auto,key_prev,key_next};sync1<=sync0;
   if(ms_tick) ms_count<=0;else ms_count<=ms_count+1'b1;
   if(ms_tick) begin
   old<=stable;
   if(sync1!=candidate) begin candidate<=sync1;debounce<=0;end
   else if(debounce<DB-1) debounce<=debounce+1'b1;
   else stable<=candidate;
   if(next_count!=0) next_count<=next_count-1'b1;
   if(prev_count!=0) prev_count<=prev_count-1'b1;
   if(auto_count!=0) auto_count<=auto_count-1'b1;
   if(!stable[2]) begin
    if(held<LONG) held<=held+1'b1;
    if(!stable[0] || !stable[1]) chord<=1;
   end else begin
    held<=0;
    if(auto_release && !chord) begin
     if(held>=LONG) mute<=~mute;
     else auto_count<=PULSE;
    end
    if(stable[1:0]==3 && !auto_release) chord<=0;
   end
   // Resolve the standalone long key on release: a later pair/modifier wins.
   if(ENABLE_CLEAN) begin
    if(!stable[0] && stable[1] && stable[2] && !chord && !nav_pair && !menu_open && !clean_blocked) begin
     if(clean_held<CLEAN_MS) clean_held<=clean_held+1'b1;
     if(clean_held==CLEAN_MS-1) clean_pending<=1;
    end
    if(!stable[1] || !stable[2] || chord || menu_open) begin clean_held<=0;clean_pending<=0;clean_blocked<=1;end
    if(stable[1:0]==3) begin
     if(clean_pending && !clean_blocked && !nav_pair && stable[2] && !chord && !menu_open) clean_toggle<=1;
     clean_held<=0;clean_pending<=0;clean_blocked<=0;
    end
   end
   // Navigation is resolved on release, so a simultaneous long pair never leaks a skip.
   if(pressed[1:0]!=0) nav_pending<=nav_pending|pressed[1:0];
   if(stable[1:0]==0) nav_pair<=1;
   if(stable[1:0]==0 && stable[2] && !chord) begin
    if(nav_held<MENU_MS) nav_held<=nav_held+1'b1;
    if(nav_held==MENU_MS-1 && !nav_latched) begin menu_toggle<=1;nav_latched<=1;end
   end else nav_held<=0;
   if(stable[1:0]==3) begin
    if(stable[2] && !chord && !nav_pair) begin
     if(nav_pending==1 && !(ENABLE_CLEAN && clean_pending && !clean_blocked)) next_count<=PULSE;
     if(nav_pending==2) prev_count<=PULSE;
    end
    nav_pending<=0;nav_pair<=0;nav_latched<=0;
   end
   direction<=request;
   if(request==0) repeat_count<=0;
   else if(request!=direction || repeat_count==REPEAT-1) begin
    repeat_count<=0;
    if(request==1 && volume<8) volume<=volume+1'b1;
    if(request==2 && volume>0) volume<=volume-1'b1;
   end else repeat_count<=repeat_count+1'b1;
   end
  end
 end
endmodule
