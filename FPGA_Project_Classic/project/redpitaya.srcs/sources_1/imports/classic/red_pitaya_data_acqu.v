/**
 * original: $Id: red_pitaya_scope.v 965 2014-01-24 13:39:56Z matej.oblak $
 * changed:  $Id: red_pitaya_data_acqu.v 2018-07 PTB $ Julia Fenske
 *
 * @brief Red Pitaya oscilloscope application, used for capturing ADC data
 *        into BRAMs, which can be later read by SW.
 *
 * @Author Matej Oblak
 *
 * (c) Red Pitaya  http://www.redpitaya.com
 *
 * This part of code is written in Verilog hardware description language (HDL).
 * Please visit http://en.wikipedia.org/wiki/Verilog
 * for more details on the language used herein.
 */
/**
 * GENERAL DESCRIPTION:
 *
 * This is simple data aquisition module.
 *
 *
 *                   /-----------\            /-----\
 *   DAT CHA ------> | AVG & DEC | ---------> | BUF | --->  SW
 *                   \-----------/     |      \-----/
 *                                     ˇ         ^
 *                                  /------\      |
 *      trigger SW ---------------> | TRIG | -----+
 *                                  \------/      |
 *                                     ^         ˇ
 *                   /-----------\     |      /-----\
 *   DAT CHB ------> | AVG & DEC | ---------> | BUF | --->  SW
 *                   \-----------/            \-----/ 
 *
 *                   /-----------\            /-----\
 *   DAT CHC ------> | AVG & DEC | ---------> | BUF | --->  SW
 *                   \-----------/     |      \-----/
 *                                     ˇ         ^
 *                                  /------\      |
 *      trigger SW ---------------> | TRIG | -----+
 *                                  \------/      |
 *                                     ^         ˇ
 *                   /-----------\     |      /-----\
 *   DAT CHD ------> | AVG & DEC | ---------> | BUF | --->  SW
 *                   \-----------/            \-----/ 
 * 
 *
 * Input data is optionaly averaged and decimated via average filter.
 *
 * Data capture buffer is realized with BRAM. Writing into ram is done with 
 * arm/trig logic. With dat_arm_do signal (SW) writing is enabled, this is active
 * until trigger arrives and adc_dly_cnt counts to zero. Value adc_wp_trig
 * serves as pointer which shows when trigger arrived. This is used to show
 * pre-trigger data.
 * 
 */
 
module red_pitaya_data_acqu #(
  parameter RSZ  = 13,          // RAM size 2^RSZ        ge�ndert von 16k auf 8k ring buffer, Mattias
  parameter DWE = 8             // data width for extension connector
//  parameter RSZ2 = 14  
)(
   // input
   input                 clk_i         ,  // clock
   input                 rstn_i        ,  // reset - active low
   input      [ 14-1: 0] dat_a_i       ,  // data A
   input      [ 14-1: 0] dat_b_i       ,  // data B
   input      [ 32-1: 0] dat_c_i       ,  // data C
   input      [ 32-1: 0] dat_d_i       ,  // data D
   input      [ 32-1: 0] Q_filtered_i  ,  // data Q_filtered
   input      [ 8 -1: 0] cycle_flags   ,  // data G
   
  // Expansion connector
   input      [DWE-1:0] exp_p_dat_i,  // exp. con. input data
   output wire[DWE-1:0] exp_p_dat_o,  // exp. con. output data
   output reg [DWE-1:0] exp_p_dir_o,  // exp. con. 1-output enable   
   // System bus
   input      [ 32-1: 0] sys_addr      ,  // bus address
   input      [ 32-1: 0] sys_wdata     ,  // bus write data
   input      [  4-1: 0] sys_sel       ,  // bus write byte select
   input                 sys_wen       ,  // bus write enable
   input                 sys_ren       ,  // bus read enable
   output reg [ 32-1: 0] sys_rdata     ,  // bus read data
   output reg            sys_err       ,  // bus error indicator
   output reg            sys_ack          // bus acknowledge signal
);

reg             dat_arm_do   ;
reg             dat_rst_do   ;
reg   [8-1: 0]  ctrl_acquire ;

initial exp_p_dir_o <= 8'b00000100; // all p pins input, pin 2 output ( trig. out)  

//---------------------------------------------------------------------------------
//  Decimate input data
//---------------------------------------------------------------------------------
reg  [ 14-1: 0] dat_a_dat     ;
reg  [ 14-1: 0] dat_b_dat     ;
reg  [ 64-1: 0] dat_c_dat     ;
reg  [ 64-1: 0] dat_d_dat     ;

reg  [ 32-1: 0] dat_a_sum     ;
reg  [ 32-1: 0] dat_b_sum     ;
reg  [ 64-1: 0] dat_c_sum     ;
reg  [ 64-1: 0] dat_d_sum     ;

reg  [ 27-1: 0] set_dec       ;
reg  [ 27-1: 0] dat_dec_cnt   ;
reg             set_avg_en    ;
reg  [ 2-1:  0] set_avg_mode  ;
reg             adc_dv        ;
reg  [ 1-1:  0] rstn_acquire  ;
reg rstn_sm                   ; // reset record maschine

//###################################################################
//  Multiplier for lamda averaging 
//###################################################################
//reg  [15-1: 0] lamda_multiplier;
reg  [1-1 : 0] lambda_block_toggle;
reg  [64-1: 0] lambda_sum_1_c;
reg  [64-1: 0] lambda_sum_2_c;
reg  [64-1: 0] lambda_sum_1_d;
reg  [64-1: 0] lambda_sum_2_d;


always @(posedge clk_i)            

if ((rstn_sm == 1'b0) ) begin 
   dat_b_sum   <= 64'h0 ;
   dat_c_sum   <= 64'h0 ;
   dat_d_sum   <= 64'h0 ;
   lambda_sum_1_c <= 64'h0 ;
   lambda_sum_2_c <= 64'h0 ;
   lambda_sum_1_d <= 64'h0 ;
   lambda_sum_2_d <= 64'h0 ;
   dat_dec_cnt <= 27'h0 ;
   adc_dv      <=  1'b0 ;
   lambda_block_toggle <= 1'b0 ;
end else begin
   if ((dat_dec_cnt >= set_dec) || dat_arm_do) begin // start again or arm
      dat_dec_cnt <= 27'h1 ;
      lambda_block_toggle <= ~lambda_block_toggle ;
      dat_a_sum   <= $signed(dat_a_i) ;
      dat_b_sum   <= $signed(dat_b_i) ;
      dat_c_sum   <= $signed(dat_c_i) ;
      dat_d_sum   <= $signed(dat_d_i) ;

   end else begin
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// PI averaging       +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
      dat_dec_cnt <= dat_dec_cnt + 27'h1 ;
      dat_a_sum   <= $signed(dat_a_sum) + $signed(dat_a_i) ;
      dat_b_sum   <= $signed(dat_b_sum) + $signed(dat_b_i) ;
//      dat_c_sum   <= $signed(dat_c_sum) + $signed(dat_c_i) ;          // Pi averaging
//      dat_d_sum   <= $signed(dat_d_sum) + $signed(dat_d_i) ;          // Pi averaging
   end
   
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// Lambda averaging   +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   
   if ((dat_dec_cnt == 27'h1) && (lambda_block_toggle == 1'b0)) begin
      // beginning of first, even block
      lambda_sum_1_c <= dat_c_i ;
      lambda_sum_1_d <= dat_d_i ;
   end else begin
      if (lambda_block_toggle == 1'b0) begin 
         // weight even block with rising ramp when toggle == 0
         lambda_sum_1_c <= $signed(lambda_sum_1_c) + $signed(dat_c_i) * $signed(dat_dec_cnt);
         lambda_sum_1_d <= $signed(lambda_sum_1_d) + $signed(dat_d_i) * $signed(dat_dec_cnt);
      end else begin
         // weight even block with falling ramp when toggle == 1
         lambda_sum_1_c <= $signed(lambda_sum_1_c) + $signed(dat_c_i) * $signed((set_dec) - $signed(dat_dec_cnt)) ;
         lambda_sum_1_d <= $signed(lambda_sum_1_d) + $signed(dat_d_i) * $signed((set_dec) - $signed(dat_dec_cnt)) ;

      end
   end
  
   if ((dat_dec_cnt == 27'h1) && (lambda_block_toggle == 1'b1))  begin
      // beginning of second, odd block (overlapping first block by set_dec)
      lambda_sum_2_c <= $signed(dat_c_i) ;
      lambda_sum_2_d <= $signed(dat_d_i) ;
   end else begin
      if (lambda_block_toggle == 1'b1) begin
         // weight odd block with rising ramp when toggle == 1
         lambda_sum_2_c <= $signed(lambda_sum_2_c) + $signed(dat_c_i) * $signed(dat_dec_cnt) ;
         lambda_sum_2_d <= $signed(lambda_sum_2_d) + $signed(dat_d_i) * $signed(dat_dec_cnt) ;
      end else begin
         // weight odd block with falling ramp when toggle == 0
         lambda_sum_2_c <= $signed(lambda_sum_2_c) + $signed(dat_c_i) * $signed((set_dec) - $signed(dat_dec_cnt)) ;
         lambda_sum_2_d <= $signed(lambda_sum_2_d) + $signed(dat_d_i) * $signed((set_dec) - $signed(dat_dec_cnt)) ;

      end
   end
   
   if (!dat_arm_do && (dat_dec_cnt >= set_dec)) begin
      // when writing sample on next tick and using decimation: select which sum to store
      if (lambda_block_toggle == 1'b0) begin
//         // when counter >= max and toggle == 0: odd block has ended
         dat_c_sum <= $signed(lambda_sum_2_c);
         dat_d_sum <= $signed(lambda_sum_2_d);
      end else begin
         // when counter >= max and toggle == 1: even block has ended
         dat_c_sum <= $signed(lambda_sum_1_c);
         dat_d_sum <= $signed(lambda_sum_1_d);
      end
   end
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// END Lambda averaging   +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

   adc_dv <= (dat_dec_cnt >= set_dec) ;     // and logic for write pointer increment

   case (set_dec & {27{set_avg_en}})
   17'h0     : begin dat_a_dat <= dat_a_i;                   dat_b_dat <= dat_b_i;        			
					 dat_c_dat <= dat_c_i;                   dat_d_dat <= dat_d_i;				 
					 end
   17'h1     : begin dat_a_dat <= dat_a_sum[15+0 :  0];      dat_b_dat <= dat_b_sum[15+0 :  0];         // decimate by 1
					 dat_c_dat <= dat_c_i;                   dat_d_dat <= dat_d_i;  
                     end
   17'h2     : begin dat_a_dat <= dat_a_sum[15+1 :  1];      dat_b_dat <= dat_b_sum[15+1 :  1];  		// decimate by 2
					 dat_c_dat <= dat_c_sum[64-1 :  0];      dat_d_dat <= dat_d_sum[64-1 :  0];  	  
					 end
   17'h4     : begin dat_a_dat <= dat_a_sum[15+2 :  2];      dat_b_dat <= dat_b_sum[15+2 :  2];  		// decimate by 4
					 dat_c_dat <= dat_c_sum[64-1 :  0];      dat_d_dat <= dat_d_sum[64-1 :  0];  	  
					 end
   17'h5     : begin dat_a_dat <= dat_a_sum[15+2 :  2];      dat_b_dat <= dat_b_sum[15+2 :  2];  		// decimate by 5
					 dat_c_dat <= dat_c_sum[64-1 :  0];      dat_d_dat <= dat_d_sum[64-1 :  0];  	  
					 end
   17'h8     : begin dat_a_dat <= dat_a_sum[15+3 :  3];      dat_b_dat <= dat_b_sum[15+3 :  3];  		// decimate by 8
					 dat_c_dat <= dat_c_sum[64-1 :  0];      dat_d_dat <= dat_d_sum[64-1 :  0];  	  
					 end
   17'hA     : begin dat_a_dat <= dat_a_sum[15+3 :  3];      dat_b_dat <= dat_b_sum[15+3 :  3];  		// decimate by 10
					 dat_c_dat <= dat_c_sum[64-1 :  0];      dat_d_dat <= dat_d_sum[64-1 :  0];  	  
					 end
   17'h10    : begin dat_a_dat <= dat_a_sum[15+4 :  4];      dat_b_dat <= dat_b_sum[15+4 :  4];  		// decimate by 16
					 dat_c_dat <= dat_c_sum[64-1 :  0];      dat_d_dat <= dat_d_sum[64-1 :  0];  	
					 end 
   17'h14    : begin dat_a_dat <= dat_a_sum[15+4 :  4];      dat_b_dat <= dat_b_sum[15+4 :  4];  		// decimate by 20
					 dat_c_dat <= dat_c_sum[64-1 :  0];      dat_d_dat <= dat_d_sum[64-1 :  0];  	  
					 end					 
   17'h20    : begin dat_a_dat <= dat_a_sum[15+5 :  5];      dat_b_dat <= dat_b_sum[15+5 :  5];  		// decimate by 32
					 dat_c_dat <= dat_c_sum[64-1 :  0];      dat_d_dat <= dat_d_sum[64-1 :  0];  	
					 end
   17'h40    : begin dat_a_dat <= dat_a_sum[15+6 :  6];      dat_b_dat <= dat_b_sum[15+6 :  6];  		// decimate by 64
					 dat_c_dat <= dat_c_sum[64-1 :  0];      dat_d_dat <= dat_d_sum[64-1 :  0];  	
					 end  
   17'h64    : begin dat_a_dat <= dat_a_sum[15+6 :  6];      dat_b_dat <= dat_b_sum[15+6 :  6];  		// decimate by 100
                     dat_c_dat <= dat_c_sum[64-1 :  0];      dat_d_dat <= dat_d_sum[64-1 :  0];  	
                     end					                                                            
   17'h80    : begin dat_a_dat <= dat_a_sum[15+7 :  7];      dat_b_dat <= dat_b_sum[15+7 :  7];  		// decimate by 128
                     dat_c_dat <= dat_c_sum[64-1 :  0];      dat_d_dat <= dat_d_sum[64-1 :  0];  	
                     end
   17'hC8    : begin dat_a_dat <= dat_a_sum[15+7 :  7];      dat_b_dat <= dat_b_sum[15+7 :  7];  		// decimate by 200
                     dat_c_dat <= dat_c_sum[64-1 :  0];      dat_d_dat <= dat_d_sum[64-1 :  0];  	
                     end					                                                                             
   17'hFA    : begin dat_a_dat <= dat_a_sum[15+7 :  7];      dat_b_dat <= dat_b_sum[15+7 :  7];  		// decimate by 250
                     dat_c_dat <= dat_c_sum[64-1 :  0];      dat_d_dat <= dat_d_sum[64-1 :  0];  	
                     end					                                                                                                      
   17'h100   : begin dat_a_dat <= dat_a_sum[15+8 :  8];      dat_b_dat <= dat_b_sum[15+8 :  8];  		// decimate by 256
                     dat_c_dat <= dat_c_sum[64-1 :  0];      dat_d_dat <= dat_d_sum[64-1 :  0];  	
                     end
   17'h1F4   : begin dat_a_dat <= dat_a_sum[15+8 :  8];      dat_b_dat <= dat_b_sum[15+8 :  8];  		// decimate by 500
                     dat_c_dat <= dat_c_sum[64-1 :  0];      dat_d_dat <= dat_d_sum[64-1 :  0];  	
                     end                     
   17'h200   : begin dat_a_dat <= dat_a_sum[15+9 :  9];      dat_b_dat <= dat_b_sum[15+9 :  9];  		// decimate by 512
                     dat_c_dat <= dat_c_sum[64-1 :  0];      dat_d_dat <= dat_d_sum[64-1 :  0];  	
                     end
   17'h3E8   : begin dat_a_dat <= dat_a_sum[15+9 :  9];      dat_b_dat <= dat_b_sum[15+9:   9];   		// decimate by 1000
                     dat_c_dat <= dat_c_sum[64-1: 0];        dat_d_dat <= dat_d_sum[64-1 :  0];         //                        	
                     end
   17'h400   : begin dat_a_dat <= dat_a_sum[15+10: 10];      dat_b_dat <= dat_b_sum[15+10: 10];			// decimate by 1024
					 dat_c_dat <= dat_c_sum[64-1 : 0];       dat_d_dat <= dat_d_sum[64-1:   0];  	
					 end
   17'h4E2   : begin dat_a_dat <= dat_a_sum[15+10: 10];      dat_b_dat <= dat_b_sum[15+10: 10];   		// decimate by 1250
                     dat_c_dat <= dat_c_sum[64-1: 0];        dat_d_dat <= dat_d_sum[64-1 :  0];         //                        	
                     end                     
   17'h1388   : begin dat_a_dat <= dat_a_sum[15+12: 12];      dat_b_dat <= dat_b_sum[15+12: 12];   		// decimate by 5000
                     dat_c_dat <= dat_c_sum[64-1: 0];        dat_d_dat <= dat_d_sum[64-1  :  0];        //                        	
                     end	
   17'h186A   : begin dat_a_dat <= dat_a_sum[15+12: 12];      dat_b_dat <= dat_b_sum[15+12: 12];   		// decimate by 6250
                     dat_c_dat <= dat_c_sum[64-1: 0];        dat_d_dat <= dat_d_sum[64-1  :  0];        //                        	
                     end                     				 
   17'h2000  : begin dat_a_dat <= dat_a_sum[15+13: 13];      dat_b_dat <= dat_b_sum[15+13: 13];    		// decimate by 8192
                     dat_c_dat <= dat_c_sum[64-1:   0];      dat_d_dat <= dat_d_sum[64-1 :  0];  	
                     end
   17'h2710   : begin dat_a_dat <= dat_a_sum[15+13: 13];      dat_b_dat <= dat_b_sum[15+13: 13];   		// decimate by 10000
                     dat_c_dat <= dat_c_sum[64-1: 0];        dat_d_dat <= dat_d_sum[64-1  :  0];        //                        	
                     end
   17'h30D4   : begin dat_a_dat <= dat_a_sum[15+13: 13];      dat_b_dat <= dat_b_sum[15+13: 13];   		// decimate by 12500
                     dat_c_dat <= dat_c_sum[64-1: 0];        dat_d_dat <= dat_d_sum[64-1  :  0];        //                        	
                     end                     
   17'h8000  : begin dat_a_dat <= dat_a_sum[15+15: 15];      dat_b_dat <= dat_b_sum[15+15: 15];    		// decimate by 32768
                     dat_c_dat <= dat_c_sum[64-1:   0];      dat_d_dat <= dat_d_sum[64-1:   0];  	
                     end
   17'hC350  : begin dat_a_dat <= dat_a_sum[15+15: 15];      dat_b_dat <= dat_b_sum[15+15: 15];   		// decimate by 50000
                     dat_c_dat <= dat_c_sum[64-1: 0];        dat_d_dat <= dat_d_sum[64-1 :  0];         //                        	
                     end
   17'hF424  : begin dat_a_dat <= dat_a_sum[15+15: 15];      dat_b_dat <= dat_b_sum[15+15: 15];   		// decimate by 62500
                     dat_c_dat <= dat_c_sum[64-1: 0];        dat_d_dat <= dat_d_sum[64-1 :  0];         //                        	
                     end                     
   17'h10000 : begin dat_a_dat <= dat_a_sum[15+16: 16];      dat_b_dat <= dat_b_sum[15+16: 16];   		// decimate by 65536
                     dat_c_dat <= dat_c_sum[64-1: 0];        dat_d_dat <= dat_d_sum[64-1 :  0];         //                        	
                     end
    default   : begin dat_a_dat <= dat_a_sum[15+0 :  0];      dat_b_dat <= dat_b_sum[15+0 :  0];  
					 dat_c_dat <= dat_c_sum[64-1 :  0];      dat_d_dat <= dat_d_sum[64-1 :   0];   
					 end 

endcase
end

//---------------------------------------------------------------------------------
//  ADC buffer RAM
//---------------------------------------------------------------------------------
reg   [  14-1: 0] dat_a_buf             [0:(1<<RSZ)-1] ;
reg   [  14-1: 0] dat_b_buf             [0:(1<<RSZ)-1] ;
reg   [  64-1: 0] dat_c_buf             [0:(1<<RSZ)-1] ;
reg   [  64-1: 0] dat_d_buf             [0:(1<<RSZ)-1] ;
reg   [  8 -1: 0] dat_cycle_slip_buf    [0:(1<<RSZ)-1] ;
reg   [  14-1: 0] dat_a_rd              ;
reg   [  14-1: 0] dat_b_rd              ;
reg   [  64-1: 0] dat_c_rd              ;
reg   [  64-1: 0] dat_d_rd              ;
reg   [  32-1: 0] dat_cycle_slip_rd     ;
reg   [ RSZ-1: 0] adc_wp                ;                   
reg   [ RSZ-1: 0] adc_raddr             ;
reg   [ RSZ-1: 0] dat_a_raddr           ;                   
reg   [ RSZ-1: 0] dat_b_raddr           ;
reg   [ RSZ-1: 0] dat_c_raddr           ;                   
reg   [ RSZ-1: 0] dat_d_raddr           ;
reg   [ RSZ-1: 0] dat_cycle_slip_raddr  ;
reg   [   4-1: 0] adc_rval              ;
wire              adc_rd_dv             ;
reg               adc_we                ;
reg               adc_we_keep           ;
reg               adc_trig              ;

reg   [ RSZ-1: 0] adc_wp_trig           ;
reg   [ RSZ-1: 0] adc_wp_cur        ;
reg   [  32-1: 0] set_dly           ;
reg   [  32-1: 0] adc_we_cnt        ;
reg   [  32-1: 0] adc_dly_cnt       ;
reg               adc_dly_do        ;

// Write data into ring buffer
always @(posedge clk_i) begin                     
   if ((rstn_sm == 1'b0)) begin 
      adc_wp      <= {RSZ{1'b0}};
      adc_we      <=  1'b0      ;
      adc_wp_trig <= {RSZ{1'b0}};
      adc_wp_cur  <= {RSZ{1'b0}};
      adc_we_cnt  <= 32'h0      ;
      adc_dly_cnt <= 32'h0      ;
      adc_dly_do  <=  1'b0      ;
   end
   else begin
      if (dat_arm_do)
         adc_we <= 1'b1 ;
      else if (((adc_dly_do || adc_trig) && (adc_dly_cnt == 32'h0) && ~adc_we_keep ) || dat_rst_do) //delayed reached or reset
         adc_we <= 1'b0 ;

      // count how much data was written into the buffer before trigger
      if (dat_rst_do | dat_arm_do)
         adc_we_cnt <= 32'h0;
      if (adc_we & ~adc_dly_do & adc_dv & ~&adc_we_cnt)
         adc_we_cnt <= adc_we_cnt + 1;

      if (dat_rst_do)
         adc_wp <= {RSZ{1'b0}};     // write pointer reset (to zerro)
      else if (adc_we && adc_dv)
         adc_wp <= adc_wp + 1;

      if (dat_rst_do)
         adc_wp_trig <= {RSZ{1'b0}};
      else if (adc_trig && !adc_dly_do)
         adc_wp_trig <= adc_wp_cur ; // save write pointer at trigger arrival

      if (dat_rst_do)
         adc_wp_cur <= {RSZ{1'b0}};
      else if (adc_we && adc_dv)
         adc_wp_cur <= adc_wp ; // save current write pointer


      if (adc_trig)
         adc_dly_do  <= 1'b1 ;
      else if ((adc_dly_do && (adc_dly_cnt == 32'b0)) || dat_rst_do || dat_arm_do) //delayed reached or reset
         adc_dly_do  <= 1'b0 ;

      if (adc_dly_do && adc_we && adc_dv)
         adc_dly_cnt <= adc_dly_cnt - 1;
      else if (!adc_dly_do)
         adc_dly_cnt <= set_dly ;

   end
end
reg [8-1: 0] p_dat;
always @(posedge clk_i) begin   
   // store data with OR logic every tick
   p_dat <= p_dat | {cycle_flags[4-1: 0], exp_p_dat_i[3], exp_p_dat_i[2], exp_p_dat_i[1], exp_p_dat_i[0]};       
   if (adc_we && adc_dv) begin
   // write al data in ring buffer when average is reached
      dat_a_buf[adc_wp]                 <= $signed(dat_a_dat) ;     
      dat_b_buf[adc_wp]                 <= $signed(dat_b_dat) ;
      dat_c_buf[adc_wp]                 <= $signed(dat_c_dat) ;     
      dat_d_buf[adc_wp]                 <= $signed(dat_d_dat) ;
      dat_cycle_slip_buf[adc_wp]        <= p_dat;
      p_dat                             <= {cycle_flags[4-1: 0], exp_p_dat_i[3], exp_p_dat_i[2], exp_p_dat_i[1], exp_p_dat_i[0]};    // data without decimation, direct from modul input
   end
end

// Read
always @(posedge clk_i) begin          
   if ((rstn_i == 1'b0))                                   
      adc_rval <= 4'h0 ;
   else
      adc_rval <= {adc_rval[2:0], (sys_ren || sys_wen)};
end
assign adc_rd_dv = adc_rval[3];

always @(posedge clk_i) begin          
	adc_raddr              <= sys_addr[RSZ+1:2] ; // address synchronous to clock
	dat_a_raddr            <= adc_raddr     ;     // double register 
	dat_b_raddr            <= adc_raddr     ;     // otherwise memory corruption at reading
	dat_c_raddr            <= adc_raddr     ;     // double register 
	dat_d_raddr            <= adc_raddr     ;     // otherwise memory corruption at reading
    dat_cycle_slip_raddr   <= adc_raddr     ;
    
    dat_a_rd    <= $signed(dat_a_buf[dat_a_raddr]) ;
    dat_b_rd    <= $signed(dat_b_buf[dat_b_raddr]) ;
	dat_c_rd    <= $signed(dat_c_buf[dat_c_raddr]) ;
	dat_d_rd    <= $signed(dat_d_buf[dat_d_raddr]) ;
    dat_cycle_slip_rd <= dat_cycle_slip_buf[dat_cycle_slip_raddr] ;
end

//---------------------------------------------------------------------------------
//  Trigger source selector  (original)
//---------------------------------------------------------------------------------
reg               adc_trig_sw      ;
reg   [   4-1: 0] set_trig_src     ;
reg               toggle_flag      ;
always @(posedge clk_i)                
if (rstn_i == 1'b0) begin
//   dat_arm_do    <= 1'b0 ;
   dat_rst_do    <= 1'b0 ;
   adc_trig_sw   <= 1'b0 ;
   set_trig_src  <= 4'h0 ;
   adc_trig      <= 1'b0 ;
   toggle_flag <= 1'b0 ;
end else begin

//#################################################################################################
// dat_arm_do is now controlled by record maschine...
//#################################################################################################
    if((rstn_sm == 1'b1) && (dat_arm_do == 1'b0) && (toggle_flag == 1'b0)) begin
            dat_arm_do  <= 1'b1;
            toggle_flag <= 1'b1;
        end else begin           
            dat_arm_do  <= 1'b0;
        end
    if(rstn_sm == 1'b0) begin
            toggle_flag <= 1'b0;
    end
    
//#################################################################################################
// This is the old dat_arm_do control...
//#################################################################################################
//   dat_arm_do  <= sys_wen && (sys_addr[19:0]==20'h0) && sys_wdata[0] ; // SW ARM
//   dat_rst_do  <= sys_wen && (sys_addr[19:0]==20'h0) && sys_wdata[1] ;
   
   adc_trig_sw <= sys_wen && (sys_addr[19:0]==20'h4) && (sys_wdata[3:0]==4'h1); // SW trigger
      if (sys_wen && (sys_addr[19:0]==20'h4))
         set_trig_src <= sys_wdata[3:0] ;
      else if (((adc_dly_do || adc_trig) && (adc_dly_cnt == 32'h0)) || dat_rst_do) //delayed reached or reset
         set_trig_src <= 4'h0 ;
   case (set_trig_src)
       4'd1 : adc_trig <= adc_trig_sw   ; // manual
    default : adc_trig <= 1'b0          ;
   endcase
end

//#####################################################################################################
// Control trigger sourse
// condition is:
//                  - ctrl_acquire is controlled by software
//                      - ..001 -> only rstn_acquire is going on (watch pps signal and extern trigger)
//                      - ..011 -> rstn_acquire and start immediately is going on
//                      - ..101 -> rstn_acquire and start burst mode is going on
//                  - trig_o is controlled by second block see below...
//#####################################################################################################

reg trig_o;
reg [2-1: 0] pps_cnt; 

always @(posedge clk_i)begin        
    if((ctrl_acquire[0] == 1'b1) ) begin    // start trigger source watching, pps (pin p_0) , ext trigger (pin p_1) 
            rstn_acquire    <= 1'b1;        // or direct trigger (bit 1 in ctrl_acquire) is sensitiv...
    end else begin
            rstn_acquire    <= 1'b0;
    end
end
always @(posedge clk_i)begin//  ## pps reached 1 ###  ext. trigger is on  ### immediately is set ####
    if((rstn_acquire == 1'b1) && ((pps_cnt == 1) || (exp_p_dat_i[1] == 1) || (ctrl_acquire[1] == 1'b1))) begin    // now look for trigger source...  
        trig_o <= 1'b1;          // trigger out set
    end else begin
        trig_o <= 1'b0;          // trigger out reset
    end
end

//####################################################################################################
// Count the pps input pin after rstn_acquire is active
// if posedge on exp_p_pin 0                 |---------
//                                  _________|
//####################################################################################################
reg prev_exp_p_dat_i;
reg burst_reached;

always @(posedge clk_i)begin
    if ((rstn_acquire == 1'b0) || (burst_reached == 1'b1))begin
        pps_cnt <= 0;
    end else if ((prev_exp_p_dat_i == 1'b0) && (exp_p_dat_i[0] == 1'b1)) begin  // exp_p_dat_i[0] is trigger in pps
        // if posedge on exp_p_pin 0       ________|---------
       if(pps_cnt < 1)begin
            pps_cnt <= pps_cnt + 1;
        end
    end
   prev_exp_p_dat_i <= exp_p_dat_i[0]; 
end

//#################################################################################################
// Control trigger output pin (extended port pin 2)
// condition is:
//                  - rstn_acquire must be 1 (controlled by software set)
//                  - trigger signal trig_o must be 1 "OR"
//                  - pps_cnt is 2 after trigger watch is activ !!!
//#################################################################################################
assign exp_p_dat_o[2] = ((trig_o == 1) || (exp_p_dat_i[1] == 1));   

//#################################################################################################
// Switch record maschine on / off
// condition is:
//                  - rstn_acquire must be 1 (controlled by software set)
//                  - trig_o "OR" pin 1 from extended port exp_p_dat_i[1] must be 1
//                  - if burst mode is active burst is control the record maschine
//#################################################################################################

always @(posedge clk_i)begin
    if(((rstn_acquire == 1'b1) && ((trig_o == 1) || (exp_p_dat_i[1] == 1) ))) begin  
        rstn_sm <= 1'b1;                // start record emaschine
    end else begin
        rstn_sm <= 1'b0;                // stop record maschine
    end
end
always @(posedge clk_i)begin
    if((ctrl_acquire[2] == 1'b1) && (adc_wp == 13'h1FFF))begin
        burst_reached <= 1'b1;
    end else begin
        burst_reached <= 1'b0;
    end
end


/**
 * ILA to check if the data acquire works
 * view the 
*/
   ila_data_acqu ila_inst (
        .clk      (clk_i),                    // input wire clk
        .probe0   ({
//                    pps_cnt_0,                  // 1
//                    pps_cnt_1,                  // 1
//                    dat_arm_do,                 // 1
//                    exp_p_dat_i,                // 8          // input pin from E1 connector
                    ctrl_acquire,               // 2            // set by software
                    lambda_block_toggle,        // 1
//                    lambda_sum_1_c,             // 64
//                    lambda_sum_2_c,             // 64
//                    dat_c_sum,                  // 64
                    dat_a_i,                    //14
                    dat_a_dat,                   // 14           // adc value after average
//                    dat_dec_cnt,                // 27           // number of average 
//                    rstn_sm,             // 1            // when pps cnt == 2, by next tick posedge
                    adc_wp                      // 13           // ram write pointer
                    })           // input wire [230-1 :0] probe0
    );


//---------------------------------------------------------------------------------
//  System bus connection for reading CPU data to FPGA
//---------------------------------------------------------------------------------
wire sys_en;
assign sys_en = sys_wen | sys_ren;

always @(posedge clk_i)            
if (rstn_i == 1'b0) begin
   adc_we_keep   <=   1'b0      ;
   set_dly       <=  32'd0      ;
   set_dec       <=  27'd1      ;
   set_avg_en    <=   1'b1      ;
   set_avg_mode  <=  2'b00      ;
end else begin
   if (sys_wen) begin
//      if (sys_addr[19:0]==20'h00)   adc_we_keep   <= sys_wdata[     3] ;
      if (sys_addr[19:0]==20'h10)   set_dly             <= sys_wdata[32-1:0] ;
      if (sys_addr[19:0]==20'h14)   set_dec             <= sys_wdata[27-1:0] ;
      if (sys_addr[19:0]==20'h28)   set_avg_en          <= sys_wdata[     0] ;
      if (sys_addr[19:0]==20'h08)   set_avg_mode        <= sys_wdata[     0] ;
      if (sys_addr[19:0]==20'h2C) begin  
                                        ctrl_acquire    <= sys_wdata[8-1: 0] ;          // control record maschine
                                        adc_we_keep     <= sys_wdata[     0] ;
                                  end
               // f�r LED Anzeige in GUI                                  
   end
end

//---------------------------------------------------------------------------------
//  System bus connection for writing FPGA data to CPU
//---------------------------------------------------------------------------------
always @(posedge clk_i)        
if (rstn_i == 1'b0) begin
   sys_err <= 1'b0 ;
   sys_ack <= 1'b0 ;
end else begin
   sys_err <= 1'b0 ;

   casez (sys_addr[19:0])
     20'h00000 : begin sys_ack <= sys_en;          sys_rdata <= {{32- 4{1'b0}}, adc_we_keep               // do not disarm on 
                                                                              , adc_dly_do                // trigger status
                                                                              , 1'b0                      // reset
                                                                              , adc_we}             ; end // arm

     20'h00004 : begin sys_ack <= sys_en;          sys_rdata <= {{32- 4{1'b0}}, set_trig_src}       ; end 
     20'h00008 : begin sys_ack <= sys_en;          sys_rdata <=                 set_avg_mode        ; end       
     20'h00010 : begin sys_ack <= sys_en;          sys_rdata <= {               set_dly}            ; end
     20'h00014 : begin sys_ack <= sys_en;          sys_rdata <= {{32-6 {1'b0}}, set_dec}            ; end
     20'h00018 : begin sys_ack <= sys_en;          sys_rdata <= {{32-RSZ{1'b0}}, adc_wp_cur}        ; end
     20'h0001C : begin sys_ack <= sys_en;          sys_rdata <= {{32-RSZ{1'b0}}, adc_wp_trig}       ; end
     20'h00028 : begin sys_ack <= sys_en;          sys_rdata <= {{32- 1{1'b0}}, set_avg_en}         ; end
     20'h0002C : begin sys_ack <= sys_en;          sys_rdata <=                 ctrl_acquire        ; end           // control record maschine
     20'h00030 : begin sys_ack <= sys_en;          sys_rdata <=                 exp_p_dat_i         ; end           // LED Anzeige in GUI (8 bit)
     20'h1???? : begin sys_ack <= adc_rd_dv;       sys_rdata <= {16'h0, 2'h0,dat_a_rd}              ; end           // 14 bit data
     20'h2???? : begin sys_ack <= adc_rd_dv;       sys_rdata <= {16'h0, 2'h0,dat_b_rd}              ; end           // 14 bit data
     
     20'h3???? : begin sys_ack <= adc_rd_dv;       sys_rdata <=              dat_c_rd[64-1: 32]   	; end
     20'h4???? : begin sys_ack <= adc_rd_dv;       sys_rdata <=              dat_c_rd[31: 0]       	; end
     20'h5???? : begin sys_ack <= adc_rd_dv;       sys_rdata <=              dat_d_rd[64-1: 32]   	; end
     20'h6???? : begin sys_ack <= adc_rd_dv;       sys_rdata <=              dat_d_rd[31: 0]       	; end
     20'h7???? : begin sys_ack <= adc_rd_dv;       sys_rdata <=              dat_cycle_slip_rd      ; end
          
       default : begin sys_ack <= sys_en;          sys_rdata <=  32'h0                              ; end
   endcase
end

endmodule
