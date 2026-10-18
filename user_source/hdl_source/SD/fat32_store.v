// Read-only FAT32 root-directory catalogue and fragmented-file sector mapper.
// Virtual sector = {file_index[4:0], sector_in_file[14:0]}.
// SFN sorting; first 32 BMP entries. One FAT-sector cache and sparse chain index.
module fat32_store #(parameter ENABLE_MENU=0)(
 input wire clk,rst,sd_init_done,scan_start,load_abort,
 output reg scan_done,scan_found_valid,output reg [31:0] scan_found_sector,output reg scan_found_animation,output reg scan_found_audio,
 output reg scan_name_valid,output reg [8:0] scan_name_addr,output reg [7:0] scan_name_data,
 output reg mount_error,read_error,output reg [3:0] error_code,
 input wire file_req,input wire [31:0] file_addr,
 output wire [7:0] file_data,output wire file_valid,file_end,
 output reg card_req,output reg [31:0] card_addr,
 input wire [7:0] card_data,input wire card_valid,card_end
);
 localparam K_BOOT=0,K_DIR=1,K_FAT=2,K_DATA=3;
 localparam IDLE=0,BOOT_WAIT=1,BOOT_CHECK=2,GEO1=3,GEO2=4,GEO3=5,
 DIR_ISSUE=6,DIR_WAIT=7,DIR_NEXT=8,FAT_GET=9,FAT_WAIT=10,FAT_LOOK=11,FAT_TAKE=12,
 ROOT_NEXT=13,SORT_READ=14,SORT_CMP=15,SORT_SWAP=16,SORT_ADV=17,EMIT=18,
 READY=19,FILE_SETUP=20,BUILD=21,BUILD_NEXT=22,SEEK=23,SEEK_LOOK=24,
 SEEK_STEP=25,SEEK_NEXT=26,DATA_ISSUE=27,DATA_WAIT=28,RELEASE=29,DRAIN=30,FAILED=31,SORT_SWAP2=32,SORT_A_WAIT=33,SORT_A_TAKE=34,SORT_B_WAIT=35,SORT_B_TAKE=36,FILE_LOOK=37,GEO_CHECK=38,GEO_APPLY=39,DIR_ADDR=40,DIR_GO=41,DATA_GO=42,FILE_SIZE=43,EMIT_WAIT=44,EMIT_SEND=45,SEEK_CACHE=46,HOT_LOOKUP=47,FAT_VALIDATE=48;
 reg [5:0] state,after_fat;
 localparam EMIT_NAME=49;reg [87:0] emit_name;reg [3:0] emit_name_pos,emit_name_length;
 function [3:0] basename_length(input [87:0] name);
 integer n;begin basename_length=0;for(n=0;n<8;n=n+1)if(name[87-n*8-:8]!=8'h20)basename_length=n+1;end
 endfunction
 reg issue,io_done;reg [1:0] kind,io_kind,io_state;reg [31:0] request_sector;
 reg [8:0] byte_no;reg [23:0] word_low;
 reg [15:0] bps,reserved,root_entries,fat16,flags,version;
 reg [7:0] spc,nfats,sig0,sig1;
 reg [31:0] total,fatsz,root,part_base,partition_lba[0:3];
 reg [7:0] partition_type[0:3];reg boot_partition;
 reg [31:0] overhead,data_base,fat_base,cluster_count,cluster_limit,fat_required,volume_end,dir_lba,data_lba;reg geometry_valid;reg [6:0] file_offset,cluster_mask;
 reg [3:0] spc_shift;
 reg [31:0] dir_cluster;reg [7:0] dir_sector_offset;reg [15:0] dir_hops;
 reg directory_end;
 reg [87:0] entry_name;reg [7:0] entry_first,entry_attr;
 reg [31:0] entry_cluster,entry_size;
 (* ram_style="bram" *) reg [151:0] catalogue[0:31];reg [151:0] catalogue_q;reg [4:0] catalogue_addr;
 reg [5:0] count,emit_index,sort_pass;reg [4:0] sort_index;
 reg [87:0] name_a,name_b,compare_a,compare_b;reg [3:0] compare_byte;
 reg [31:0] start_a,start_b,size_a,size_b;
 reg [31:0] fat_cluster,fat_value;reg [27:0] fat_words[0:127];
 reg fat_cache_valid;reg [31:0] fat_tag;reg [27:0] fat_q;
 reg [27:0] checkpoints[0:2047];reg [27:0] checkpoint_q;
 reg [31:0] hot_cluster0,hot_cluster1;reg [15:0] hot_index0,hot_index1;reg hot_valid0,hot_valid1,hot_victim,hot_slot,hot_hit0,hot_hit1;reg legal_cluster,fat_eoc,fat_self_dir,fat_self_walk;
 reg chain_valid;reg [4:0] chain_file,requested_file;
 reg [15:0] chain_index,chain_length,target_index,walk_index;
 reg [31:0] walk_cluster,file_sector,cluster_delta;reg [15:0] sector_count;
 wire [31:0] complete_size={card_data,entry_size[23:0]};
 wire [31:0] incoming_word={card_data,word_low};
 
 wire boot_shape=(bps==512 && root_entries==0 && fat16==0 && reserved!=0 &&
  (nfats==1 || nfats==2) && fatsz!=0 && version==0 &&
  (spc==1 || spc==2 || spc==4 || spc==8 || spc==16 || spc==32 || spc==64 || spc==128));
 assign file_data=card_data;
 assign file_valid=card_valid && io_kind==K_DATA && io_state==1;
 assign file_end=io_done && io_kind==K_DATA;
 always @(posedge clk) begin
  fat_q<=fat_words[fat_cluster[6:0]];
  checkpoint_q<=checkpoints[target_index[14:4]];
 end
 wire cat_dir_write=io_state==1 && card_valid && io_kind==K_DIR && byte_no[4:0]==31 &&
  !directory_end && entry_first!=8'he5 && (entry_attr&8'h18)==0 && (entry_name[23:0]==24'h424d50 || entry_name[23:0]==24'h414e4d || entry_name[23:0]==24'h574156 || entry_name[23:0]==24'h41564d) &&
  entry_cluster>=2 && complete_size>=54 && complete_size<=32'd16777216 && count<32;
 wire cat_sort_write=state==SORT_SWAP || state==SORT_SWAP2;
 wire [4:0] cat_write_addr=cat_sort_write ? (state==SORT_SWAP ? sort_index : sort_index+5'd1) : count[4:0];
 wire [151:0] cat_write_data=cat_sort_write ? (state==SORT_SWAP ? {name_b,start_b,size_b} : {name_a,start_a,size_a}) : {entry_name,entry_cluster,complete_size};
 always @(posedge clk) begin
  if(!rst && (cat_dir_write || cat_sort_write)) catalogue[cat_write_addr]<=cat_write_data;
  catalogue_q<=catalogue[catalogue_addr];
 end
 integer i;
 // Physical-sector request handshake: finish the transaction before reusing SD.
 always @(posedge clk or posedge rst) begin
  if(rst) begin io_state<=0;card_req<=0;card_addr<=0;io_done<=0;byte_no<=0;io_kind<=0;word_low<=0;end
  else if(!sd_init_done) begin io_state<=0;card_req<=0;io_done<=0;byte_no<=0;end
  else begin
   io_done<=0;
   case(io_state)
    0:if(issue) begin card_req<=1;card_addr<=request_sector;io_kind<=kind;byte_no<=0;io_state<=1;end
    1:begin
     if(card_valid) begin
      byte_no<=byte_no+1'b1;
      case(byte_no[1:0]) 0:word_low[7:0]<=card_data;1:word_low[15:8]<=card_data;2:word_low[23:16]<=card_data;endcase
     end
     if(card_end) begin card_req<=0;io_state<=2;end
    end
    2:begin io_done<=1;io_state<=0;end
    default:begin io_state<=0;card_req<=0;end
   endcase
  end
 end
 // Stream BPB fields, directory records and FAT words. No asynchronous byte RAM.
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   bps<=0;reserved<=0;root_entries<=0;fat16<=0;flags<=0;version<=0;
   spc<=0;nfats<=0;sig0<=0;sig1<=0;total<=0;fatsz<=0;root<=0;
   entry_name<=0;entry_first<=0;entry_attr<=0;entry_cluster<=0;entry_size<=0;
   count<=0;directory_end<=0;
   for(i=0;i<4;i=i+1) begin partition_lba[i]<=0;partition_type[i]<=0;end
  end else begin
   if(scan_start) begin count<=0;directory_end<=0;end
   if(io_state==1 && card_valid) begin
    if(io_kind==K_BOOT) begin
     case(byte_no)
      11:bps[7:0]<=card_data;12:bps[15:8]<=card_data;13:spc<=card_data;
      14:reserved[7:0]<=card_data;15:reserved[15:8]<=card_data;16:nfats<=card_data;
      17:root_entries[7:0]<=card_data;18:root_entries[15:8]<=card_data;
      22:fat16[7:0]<=card_data;23:fat16[15:8]<=card_data;
      32:total[7:0]<=card_data;33:total[15:8]<=card_data;34:total[23:16]<=card_data;35:total[31:24]<=card_data;
      36:fatsz[7:0]<=card_data;37:fatsz[15:8]<=card_data;38:fatsz[23:16]<=card_data;39:fatsz[31:24]<=card_data;
      40:flags[7:0]<=card_data;41:flags[15:8]<=card_data;42:version[7:0]<=card_data;43:version[15:8]<=card_data;
      44:root[7:0]<=card_data;45:root[15:8]<=card_data;46:root[23:16]<=card_data;47:root[31:24]<=card_data;
      510:sig0<=card_data;511:sig1<=card_data;
     endcase
     if(byte_no>=446 && byte_no<510) begin
      case(byte_no[3:0])
       2:partition_type[(byte_no-446)>>4]<=card_data;
       6:partition_lba[(byte_no-446)>>4][7:0]<=card_data;
       7:partition_lba[(byte_no-446)>>4][15:8]<=card_data;
       8:partition_lba[(byte_no-446)>>4][23:16]<=card_data;
       9:partition_lba[(byte_no-446)>>4][31:24]<=card_data;
      endcase
     end
    end
    if(io_kind==K_FAT && byte_no[1:0]==3) fat_words[byte_no[8:2]]<=incoming_word[27:0];
    if(io_kind==K_DIR) begin
     if(byte_no[4:0]<11) entry_name<={entry_name[79:0],card_data};
     case(byte_no[4:0])
      0:begin entry_first<=card_data;if(card_data==0) directory_end<=1;end
      11:entry_attr<=card_data;
      20:entry_cluster[23:16]<=card_data;21:entry_cluster[31:24]<={4'd0,card_data[3:0]};
      26:entry_cluster[7:0]<=card_data;27:entry_cluster[15:8]<=card_data;
      28:entry_size[7:0]<=card_data;29:entry_size[15:8]<=card_data;30:entry_size[23:16]<=card_data;
      31:begin
       entry_size[31:24]<=card_data;
       if(!directory_end && entry_first!=8'he5 && (entry_attr&8'h18)==0 &&
        (entry_name[23:0]==24'h424d50 || entry_name[23:0]==24'h414e4d || entry_name[23:0]==24'h574156 || entry_name[23:0]==24'h41564d) && entry_cluster>=2 && complete_size>=54 &&
        complete_size<=32'd16777216 && count<32) begin
        count<=count+1'b1;
       end
      end
     endcase
    end
   end
   // Catalogue swap is mutually exclusive with directory streaming.


  end
 end
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   hot_hit0<=0;hot_hit1<=0;legal_cluster<=0;fat_eoc<=0;fat_self_dir<=0;fat_self_walk<=0;hot_cluster0<=0;hot_cluster1<=0;hot_index0<=0;hot_index1<=0;hot_valid0<=0;hot_valid1<=0;hot_victim<=0;hot_slot<=0;state<=IDLE;after_fat<=0;issue<=0;kind<=0;request_sector<=0;
   scan_name_valid<=0;scan_name_addr<=0;scan_name_data<=0;emit_name<=0;emit_name_pos<=0;emit_name_length<=0;
   scan_done<=0;scan_found_valid<=0;scan_found_sector<=0;scan_found_animation<=0;scan_found_audio<=0;mount_error<=0;read_error<=0;error_code<=0;
   part_base<=0;boot_partition<=0;overhead<=0;data_base<=0;fat_base<=0;cluster_count<=0;cluster_limit<=0;fat_required<=0;volume_end<=0;geometry_valid<=0;dir_lba<=0;data_lba<=0;file_offset<=0;cluster_mask<=0;spc_shift<=0;
   dir_cluster<=0;dir_sector_offset<=0;dir_hops<=0;emit_index<=0;sort_pass<=0;sort_index<=0;
   catalogue_addr<=0;name_a<=0;name_b<=0;compare_a<=0;compare_b<=0;compare_byte<=0;start_a<=0;start_b<=0;size_a<=0;size_b<=0;
   fat_cluster<=0;fat_value<=0;fat_cache_valid<=0;fat_tag<=0;
   chain_valid<=0;chain_file<=0;requested_file<=0;chain_index<=0;chain_length<=0;
   target_index<=0;walk_index<=0;walk_cluster<=0;file_sector<=0;sector_count<=0;cluster_delta<=0;
  end else begin
   issue<=0;scan_found_valid<=0;scan_name_valid<=0;read_error<=0;
   if(!sd_init_done) begin hot_valid0<=0;hot_valid1<=0;state<=IDLE;scan_done<=0;fat_cache_valid<=0;chain_valid<=0;end
   else if(load_abort) begin hot_valid0<=0;hot_valid1<=0;state<=DRAIN;chain_valid<=0;end
   else case(state)
    IDLE:if(scan_start) begin
     hot_valid0<=0;hot_valid1<=0;
     part_base<=0;boot_partition<=0;mount_error<=0;error_code<=0;scan_done<=0;chain_valid<=0;fat_cache_valid<=0;
     request_sector<=0;kind<=K_BOOT;issue<=1;state<=BOOT_WAIT;
    end
    BOOT_WAIT:if(io_done) state<=BOOT_CHECK;
    BOOT_CHECK:begin
     if(sig0!=8'h55 || sig1!=8'haa) begin mount_error<=1;error_code<=1;state<=FAILED;end
     else if(boot_shape) begin
      case(spc) 1:spc_shift<=0;2:spc_shift<=1;4:spc_shift<=2;8:spc_shift<=3;16:spc_shift<=4;32:spc_shift<=5;64:spc_shift<=6;128:spc_shift<=7;endcase
      state<=GEO1;
     end else if(!boot_partition) begin
      boot_partition<=1;
      if(partition_type[0]==8'h0b || partition_type[0]==8'h0c || partition_type[0]==8'h1b || partition_type[0]==8'h1c) begin part_base<=partition_lba[0];request_sector<=partition_lba[0];issue<=1;state<=BOOT_WAIT;end
      else if(partition_type[1]==8'h0b || partition_type[1]==8'h0c || partition_type[1]==8'h1b || partition_type[1]==8'h1c) begin part_base<=partition_lba[1];request_sector<=partition_lba[1];issue<=1;state<=BOOT_WAIT;end
      else if(partition_type[2]==8'h0b || partition_type[2]==8'h0c || partition_type[2]==8'h1b || partition_type[2]==8'h1c) begin part_base<=partition_lba[2];request_sector<=partition_lba[2];issue<=1;state<=BOOT_WAIT;end
      else if(partition_type[3]==8'h0b || partition_type[3]==8'h0c || partition_type[3]==8'h1b || partition_type[3]==8'h1c) begin part_base<=partition_lba[3];request_sector<=partition_lba[3];issue<=1;state<=BOOT_WAIT;end
      else begin mount_error<=1;error_code<=2;state<=FAILED;end
     end else begin mount_error<=1;error_code<=2;state<=FAILED;end
    end
    GEO1:begin overhead<=reserved+(nfats==2 ? (fatsz<<1) : fatsz);state<=GEO2;end
    GEO2:begin
     data_base<=part_base+overhead;fat_base<=part_base+reserved+((flags[7] && flags[3:0]==1) ? fatsz : 0);
     cluster_count<=(total-overhead)>>spc_shift;state<=GEO3;
    end
    GEO3:begin cluster_limit<=cluster_count+2;fat_required<=(cluster_count+129)>>7;volume_end<=part_base+total;cluster_mask<=spc[6:0]-1'b1;state<=GEO_CHECK;end
    GEO_CHECK:begin
     geometry_valid<=total>overhead && cluster_count>=65525 && cluster_count<=32'h0ffffff5 &&
      root>=2 && root<cluster_limit && (!flags[7] || flags[3:0]<nfats) &&
      fatsz>=fat_required && data_base>=part_base && volume_end>=part_base;
     state<=GEO_APPLY;
    end
    GEO_APPLY:begin
     if(!geometry_valid) begin mount_error<=1;error_code<=3;state<=FAILED;end
     else begin dir_cluster<=root;dir_sector_offset<=0;dir_hops<=0;state<=DIR_ISSUE;end
    end
    DIR_ISSUE:begin cluster_delta<=(dir_cluster-2)<<spc_shift;state<=DIR_ADDR;end
    DIR_ADDR:begin dir_lba<=data_base+cluster_delta;state<=DIR_GO;end
    DIR_GO:begin request_sector<=dir_lba+dir_sector_offset;kind<=K_DIR;issue<=1;state<=DIR_WAIT;end
    DIR_WAIT:if(io_done) state<=DIR_NEXT;
    DIR_NEXT:begin
     if(directory_end || count==32) begin sort_pass<=0;sort_index<=0;state<=SORT_READ;end
     else if(dir_sector_offset+1<spc) begin dir_sector_offset<=dir_sector_offset+1'b1;state<=DIR_ISSUE;end
     else begin fat_cluster<=dir_cluster;after_fat<=ROOT_NEXT;state<=FAT_GET;end
    end
    FAT_GET:begin
     if(fat_cache_valid && fat_tag==(fat_base+(fat_cluster>>7))) state<=FAT_LOOK;
     else begin fat_tag<=fat_base+(fat_cluster>>7);request_sector<=fat_base+(fat_cluster>>7);kind<=K_FAT;issue<=1;state<=FAT_WAIT;end
    end
    FAT_WAIT:if(io_done) begin fat_cache_valid<=1;state<=FAT_LOOK;end
    FAT_LOOK:state<=FAT_TAKE;
    FAT_TAKE:begin fat_value<={4'd0,fat_q};state<=FAT_VALIDATE;end
    FAT_VALIDATE:begin legal_cluster<=(fat_value>=2 && fat_value<cluster_limit);fat_eoc<=fat_value>=32'h0ffffff8;fat_self_dir<=fat_value==dir_cluster;fat_self_walk<=fat_value==walk_cluster;state<=after_fat;end
    ROOT_NEXT:begin
     if(fat_eoc) begin sort_pass<=0;sort_index<=0;state<=SORT_READ;end
     else if(!legal_cluster || dir_hops==65535 || fat_self_dir) begin mount_error<=1;error_code<=4;state<=FAILED;end
     else begin dir_cluster<=fat_value;dir_sector_offset<=0;dir_hops<=dir_hops+1'b1;state<=DIR_ISSUE;end
    end
    SORT_READ:begin
     if(count<2 || sort_pass>=count-1'b1) begin emit_index<=0;state<=EMIT;end
     else begin catalogue_addr<=sort_index;state<=SORT_A_WAIT;end
    end
    SORT_A_WAIT:state<=SORT_A_TAKE;
    SORT_A_TAKE:begin {name_a,start_a,size_a}<=catalogue_q;catalogue_addr<=sort_index+5'd1;state<=SORT_B_WAIT;end
    SORT_B_WAIT:state<=SORT_B_TAKE;
    SORT_B_TAKE:begin
     {name_b,start_b,size_b}<=catalogue_q;
     compare_a<=name_a;compare_b<=catalogue_q[151:64];compare_byte<=0;state<=SORT_CMP;
    end
    SORT_CMP:begin
     if(compare_a[87:80]>compare_b[87:80]) state<=SORT_SWAP;
     else if(compare_a[87:80]<compare_b[87:80] || compare_byte==10) state<=SORT_ADV;
     else begin compare_a<=compare_a<<8;compare_b<=compare_b<<8;compare_byte<=compare_byte+1'b1;end
    end
    SORT_SWAP:state<=SORT_SWAP2;
    SORT_SWAP2:state<=SORT_ADV;
    SORT_ADV:begin
     if({1'b0,sort_index}+2>=count-sort_pass) begin sort_index<=0;sort_pass<=sort_pass+1'b1;end
     else sort_index<=sort_index+1'b1;
     state<=SORT_READ;
    end
    EMIT:begin
     if(emit_index<count) begin catalogue_addr<=emit_index[4:0];state<=EMIT_WAIT;end
     else begin scan_done<=1;state<=READY;end
    end
    EMIT_WAIT:state<=EMIT_SEND;
    EMIT_SEND:begin
     scan_found_sector<={12'd0,emit_index[4:0],15'd0};scan_found_animation<=(catalogue_q[87:64]==24'h414e4d || catalogue_q[87:64]==24'h41564d);scan_found_audio<=(catalogue_q[87:64]==24'h574156 || catalogue_q[87:64]==24'h41564d);
     scan_found_valid<=1;
     if(ENABLE_MENU)begin emit_name<=catalogue_q[151:64];emit_name_pos<=0;emit_name_length<=basename_length(catalogue_q[151:64]);state<=EMIT_NAME;end
     else begin emit_index<=emit_index+1'b1;state<=EMIT;end
    end
    EMIT_NAME:begin
     scan_name_valid<=1;scan_name_addr<={emit_index[4:0],emit_name_pos};scan_name_data<=emit_name_pos==11 ? {2'd0,emit_name_length,scan_found_audio,scan_found_animation}:emit_name[87:80];emit_name<=emit_name<<8;
     if(emit_name_pos==11)begin emit_index<=emit_index+1'b1;state<=EMIT;end else emit_name_pos<=emit_name_pos+1'b1;
    end
    READY:if(file_req) begin
     catalogue_addr<=file_addr[19:15];requested_file<=file_addr[19:15];file_sector<={17'd0,file_addr[14:0]};
     if(file_addr[31:20]!=0 || {1'b0,file_addr[19:15]}>=count) begin read_error<=1;error_code<=5;state<=DRAIN;end
     else state<=FILE_LOOK;
    end
    FILE_LOOK:state<=FILE_SETUP;
    FILE_SETUP:begin
     sector_count<=(catalogue_q[24:0]+25'd511)>>9;file_offset<=file_sector[6:0]&cluster_mask;
     target_index<=file_sector>>spc_shift;
     if(chain_valid && chain_file==requested_file) state<=SEEK;
     else begin
      hot_valid0<=0;hot_valid1<=0;chain_valid<=0;chain_file<=requested_file;walk_cluster<=catalogue_q[63:32];chain_index<=0;
      state<=FILE_SIZE;
     end
    end
    FILE_SIZE:begin chain_length<=({1'b0,sector_count}+{9'd0,spc}-17'd1)>>spc_shift;state<=BUILD;end
    BUILD:begin
     if(chain_index[3:0]==0) checkpoints[chain_index[14:4]]<=walk_cluster[27:0];
     if(walk_cluster<2 || walk_cluster>=cluster_limit || chain_length==0) begin read_error<=1;error_code<=6;state<=DRAIN;end
     else if(chain_index+1>=chain_length) begin chain_valid<=1;state<=SEEK;end
     else begin fat_cluster<=walk_cluster;after_fat<=BUILD_NEXT;state<=FAT_GET;end
    end
    BUILD_NEXT:begin
     if(!legal_cluster || fat_self_walk) begin read_error<=1;error_code<=6;state<=DRAIN;end
     else begin walk_cluster<=fat_value;chain_index<=chain_index+1'b1;state<=BUILD;end
    end
    SEEK:begin
     if(file_sector>=sector_count || target_index>=chain_length) begin read_error<=1;error_code<=7;state<=DRAIN;end
     else begin walk_index<={target_index[15:4],4'd0};state<=SEEK_CACHE;end
    end
    SEEK_CACHE:begin
     hot_hit0<=hot_valid0 && (target_index==hot_index0 || target_index==hot_index0+16'd1);
     hot_hit1<=hot_valid1 && (target_index==hot_index1 || target_index==hot_index1+16'd1);
     state<=HOT_LOOKUP;
    end
    HOT_LOOKUP:begin
     if(hot_hit0) begin walk_index<=hot_index0;walk_cluster<=hot_cluster0;hot_slot<=0;state<=SEEK_STEP;end
     else if(hot_hit1) begin walk_index<=hot_index1;walk_cluster<=hot_cluster1;hot_slot<=1;state<=SEEK_STEP;end
     else begin hot_slot<=hot_victim;state<=SEEK_LOOK;end
    end
    SEEK_LOOK:begin walk_cluster<={4'd0,checkpoint_q};state<=SEEK_STEP;end
    SEEK_STEP:begin
     if(walk_index==target_index) begin
      if(hot_slot) begin hot_valid1<=1;hot_index1<=target_index;hot_cluster1<=walk_cluster;end
      else begin hot_valid0<=1;hot_index0<=target_index;hot_cluster0<=walk_cluster;end
      hot_victim<=~hot_slot;
      cluster_delta<=(walk_cluster-2)<<spc_shift;state<=DATA_ISSUE;end
     else begin fat_cluster<=walk_cluster;after_fat<=SEEK_NEXT;state<=FAT_GET;end
    end
    SEEK_NEXT:begin
     if(!legal_cluster) begin read_error<=1;error_code<=6;state<=DRAIN;end
     else begin walk_cluster<=fat_value;walk_index<=walk_index+1'b1;state<=SEEK_STEP;end
    end
    DATA_ISSUE:begin data_lba<=data_base+cluster_delta;state<=DATA_GO;end
    DATA_GO:begin request_sector<=data_lba+file_offset;kind<=K_DATA;issue<=1;state<=DATA_WAIT;end
    DATA_WAIT:if(io_done) state<=RELEASE;
    RELEASE:if(!file_req) state<=READY;
    DRAIN:if(io_state==0 && !file_req) state<=READY;
    FAILED:begin end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
