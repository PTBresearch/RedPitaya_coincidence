/**
 * original: $Id: red_pitaya_pid_block.v 961 2014-01-21 11:40:39Z matej.oblak $
 * changed:  $Id: red_pitaya_pi_block.v 2018-07 PTB $ Julia Fenske
 *
 * @brief Red Pitaya PI controller.
 *
 * @Author Matej Oblak
 * Changes by PTB: 
 *      - reg's expanded to 32 bit
 *      - derivative removed
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
 * Proportional-integral (PI) controller.
 *
 *
 *        /---\         /---\      /-----------\
 *   IN --| - |----+--> | P | ---> | SUM & SAT | ---> OUT
 *        \---/    |    \---/      \-----------/
 *          ^      |                   ^  
 *          |      |    /---\          |  
 *   set ----      |--> | I | ---------   
 *   point              \---/             
 *                                       

 *
 *
 * Proportional-integral (PI) controller is made from two parts. 
 *
 * Error which is difference between set point and input signal is driven into
 * propotional and integral part. Each calculates its own value which
 * is then summed and saturated before given to output.
 *
 * Integral part has also separate input to reset integrator value to 0.
 * 
 */

module red_pitaya_pi_block #(
   parameter     PSR = 32         ,
   parameter     ISR = 32                   
)
(
   // data
   input                 clk_i           ,  // clock
   input                 rstn_i          ,  // reset - active low
   input      [ 32-1: 0] dat_i           ,  // input data
   output     [ 32-1: 0] dat_o           ,  // output data

   // settings
   input      [ 32-1: 0] set_sp_i        ,  // set point
   input      [ 32-1: 0] set_kp_i        ,  // Kp
   input      [ 32-1: 0] set_ki_i        ,  // Ki
   input                 int_rst_i          // integrator reset
);

//---------------------------------------------------------------------------------
//  Set point error calculation

reg   [ 32-1: 0] error        ;
wire  [ 33-1: 0] error2       ;
    
always @(posedge clk_i) begin
   if (rstn_i == 1'b0) begin
       error <= 32'h0 ;
   end
   else if ({error2[33-1],|error2[33-2]} == 2'b01) //positive overflow
       error <= 32'h7FFFFFFF ;
   else if ({error2[33-1],&error2[33-2]} == 2'b10) //negative overflow
       error <= 32'h80000000 ;
   else
       error  <= $signed(error2[32-1: 0]);
end
     
assign error2 = $signed(set_sp_i) - $signed(dat_i);


//---------------------------------------------------------------------------------
//  Proportional part
//  PSR -> 32

reg   [64-PSR-1: 0]  kp_reg         ;
reg   [64-1: 0]      kp_mult_64     ;
//wire  [    64-1: 0]  kp_mult        ;

always @(posedge clk_i) begin
   if (rstn_i == 1'b0) begin
      kp_reg  <= {64-PSR{1'b0}};
   end
   else if ({kp_mult_64[64-1],|kp_mult_64[64-2]} == 2'b01) //positive overflow
       kp_reg <= 32'h7FFFFFFF ;
   else if ({kp_mult_64[64-1],&kp_mult_64[64-2]} == 2'b10) //negative overflow
       kp_reg <= 32'h80000000 ;
   else    
         kp_reg <= kp_mult_64[64-1:PSR] ; 
end
always @(posedge clk_i) begin
   kp_mult_64    <= $signed(error) * ($signed(set_kp_i));
end
//assign kp_mult = $signed(error) * $signed(set_kp_i);


//---------------------------------------------------------------------------------
//  Integrator

reg   [    64-1: 0] ki_mult       ;
reg   [    65-1: 0] int_sum       ;
reg   [    64-1: 0] int_reg       ;
reg   [64-ISR-1: 0] int_shr       ;

always @(posedge clk_i) begin
   if (rstn_i == 1'b0) begin
      ki_mult  <= {64{1'b0}};
      int_reg  <= {64{1'b0}};
   end
   else begin
      ki_mult <= $signed(error) * $signed(set_ki_i) ;

      if (int_rst_i)
         int_reg <= 64'h0; // reset
      else if (int_sum[65-1:65-2] == 2'b01) // positive saturation
         int_reg <= 64'h7FFFFFFFFFFFFFFF; // max positive
      else if (int_sum[65-1:65-2] == 2'b10) // negative saturation
         int_reg <= 64'h8000000000000000; // max negative
      else
         int_reg <= int_sum[64-1:0]; // use sum as it is
   end
end
always @(posedge clk_i) begin
   int_sum <= $signed(ki_mult) + $signed(int_reg) ;
   int_shr <= int_reg[64-1:ISR] ;
end
//assign int_sum = $signed(ki_mult) + $signed(int_reg) ;
//assign int_shr = int_reg[64-1:ISR] ;


//---------------------------------------------------------------------------------
//  Sum together - saturate output

wire  [   33-1: 0] pid_sum     ; // biggest posible bit-width
reg   [   32-1: 0] pid_out     ;

always @(posedge clk_i) begin
   if (rstn_i == 1'b0) begin
      pid_out    <= 32'b0 ;
   end
   else begin
      if ({pid_sum[33-1],|pid_sum[33-2]} == 2'b01) //positive overflow
         pid_out <= 32'h7FFFFFFF ;
      else if ({pid_sum[33-1],&pid_sum[33-2]} == 2'b10) //negative overflow
         pid_out <= 32'h80000000 ;
      else
         pid_out <= pid_sum[32-1:0] ;
   end
end

assign pid_sum = $signed(kp_reg) + $signed(int_shr) ;


assign dat_o = pid_out ;

endmodule