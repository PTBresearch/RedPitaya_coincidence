// SPDX-FileCopyrightText: 2024 Physikalisch-Technische Bundesanstalt (PTB), German National Metrology Institute
// SPDX-License-Identifier: Apache-2.0


 
module acqu #(
  parameter RSZ = 4,            // RAM size 2^RSZ 
  parameter DWE = 8             // data width for extension connector
)(
   // input
   input                 clk_i              ,  // clock
   input                 rstn_i             ,  // reset - active low
   input logic[ 48-1: 0] ftw_itracker_1_i   ,  // 
   input logic[ 48-1: 0] ftw_itracker_2_i   ,  // 
      
   // output
      
  // Expansion connector
   input  logic[DWE-1:0] exp_p_dat_i,        // exp. con. input data
   output logic[DWE-1:0] exp_p_dat_o,        // exp. con. output data
   output logic[DWE-1:0] exp_p_dir_o,        // exp. con. 1-output enable   
   
   // System bus record
   input      [ 32-1: 0] sys_addr           ,    // bus address
   input      [ 32-1: 0] sys_wdata          ,    // bus write data
   input                 sys_wen            ,    // bus write enable
   input                 sys_ren            ,    // bus read enable
   output reg [ 32-1: 0] sys_rdata          ,    // bus read data
   output reg            sys_err            ,    // bus error indicator
   output reg            sys_ack            ,    // bus acknowledge signal
   // System bus avg module 1
   input  wire[ 32-1: 0] sys_addr_avg_1      ,    // bus address
   input  wire[ 32-1: 0] sys_wdata_avg_1     ,    // bus write data
   input  wire           sys_wen_avg_1       ,    // bus write enable
   input  wire           sys_ren_avg_1       ,    // bus read enable
   output reg [ 32-1: 0] sys_rdata_avg_1     ,    // bus read data
   output reg            sys_err_avg_1       ,    // bus error indicator
   output reg            sys_ack_avg_1       ,    // bus acknowledge signal
   // System bus avg module 2
   input  wire[ 32-1: 0] sys_addr_avg_2      ,    // bus address
   input  wire[ 32-1: 0] sys_wdata_avg_2     ,    // bus write data
   input  wire           sys_wen_avg_2       ,    // bus write enable
   input  wire           sys_ren_avg_2       ,    // bus read enable
   output reg [ 32-1: 0] sys_rdata_avg_2     ,    // bus read data
   output reg            sys_err_avg_2       ,    // bus error indicator
   output reg            sys_ack_avg_2            // bus acknowledge signal   
);

logic   [8-1: 0]        ctrl_acquire ;
initial                 exp_p_dir_o <= 8'b00000100;         // all p pins input, pin 2 output ( trig. out)  
logic   [27-1 : 0]      set_dec;                            // sample count 
logic                   rstn_avg;                           // reset 
logic                   rstn_sm;                            // reset avg module - active high
logic[DWE-1:0]          exp_p_dat_i_reg;                    // exp. con. input data

always @(posedge clk_i)begin 
    exp_p_dat_i_reg <= exp_p_dat_i;
end

// 1st Module 
LAvgModule i_avg_module_1 (
    .CLK            (clk_i              ),  // clock
    .reset          (rstn_sm            ),  // reset - active high
//    .data_valid     (data_valid        ),
    .data_in        (ftw_itracker_1_i   ),  // in 3
     // System bus
  .sys_addr        (sys_addr_avg_1      ),
  .sys_wdata       (sys_wdata_avg_1     ),
  .sys_wen         (sys_wen_avg_1       ),
  .sys_ren         (sys_ren_avg_1       ),
  .sys_rdata       (sys_rdata_avg_1     ),
  .sys_err         (sys_err_avg_1       ),
  .sys_ack         (sys_ack_avg_1       )
);

// 2nd Module 
LAvgModule i_avg_module_2 (
    .CLK            (clk_i              ),  // clock
    .reset          (rstn_sm            ),  // reset - active high
    .data_in        (ftw_itracker_2_i   ),  // in 3    
     // System bus
  .sys_addr        (sys_addr_avg_2      ),
  .sys_wdata       (sys_wdata_avg_2     ),
  .sys_wen         (sys_wen_avg_2       ),
  .sys_ren         (sys_ren_avg_2       ),
  .sys_rdata       (sys_rdata_avg_2     ),
  .sys_err         (sys_err_avg_2       ),
  .sys_ack         (sys_ack_avg_2       )
);

logic [32-1: 0]     cnt;
always @(posedge clk_i) begin
     if(cnt < 32'd100000000) begin
        cnt     <= cnt + 1'b1;
     end
     else begin          // do every second...
     
        cnt     <= 32'b0;
     end 
 end

 

//#####################################################################################################
// Control trigger source
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
            rstn_avg    <= 1'b1;            // or direct trigger (bit 1 in ctrl_acquire) is sensitiv...
    end else begin
            rstn_avg    <= 1'b0;
    end
end
always @(posedge clk_i)begin//  ## pps reached 1 ###  ext. trigger is on  ### immediately is set ####
    if((rstn_avg == 1'b1) && ((pps_cnt == 1) || (exp_p_dat_i_reg[1] == 1) || (ctrl_acquire[1] == 1'b1))) begin    // now look for trigger source...  
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
logic prev_exp_p_dat_i;

always @(posedge clk_i)begin
    if ((rstn_avg == 1'b0))begin
        pps_cnt <= 0;
    end else if ((prev_exp_p_dat_i == 1'b0) && (exp_p_dat_i_reg[0] == 1'b1)) begin  // exp_p_dat_i[0] is trigger in pps
        // if posedge on exp_p_pin 0       ________|---------
       if(pps_cnt < 1)begin
            pps_cnt <= pps_cnt + 1;
        end
    end
   prev_exp_p_dat_i <= exp_p_dat_i_reg[0]; 
end

//#################################################################################################
// Control trigger output pin (extended port pin 2)
// condition is:
//                  - rstn_acquire must be 1 (controlled by software set)
//                  - trigger signal trig_o must be 1 "OR"
//                  - pps_cnt is 2 after trigger watch is activ !!!
//#################################################################################################
assign exp_p_dat_o[2] = ((trig_o == 1) || (exp_p_dat_i_reg[1] == 1));   

//#################################################################################################
// Switch record machine on / off
// condition is:
//                  - rstn_acquire must be 1 (controlled by software set)
//                  - trig_o "OR" pin 1 from extended port exp_p_dat_i[1] must be 1
//                  - if burst mode is active burst is control the record machine
//#################################################################################################


logic           delay_flag;
logic [32-1: 0] delay_cnt;
logic           delay_reached;
logic [32-1: 0] ctrl_delay_pps;

always @(posedge clk_i)begin
    if(delay_flag) begin
        delay_cnt <= delay_cnt + 1;
    end else begin
        delay_cnt       <= 32'b0;       
        delay_reached   <=  1'b0; 
    end
    if(delay_cnt == ctrl_delay_pps) begin
        delay_reached <= 1'b1;
    end
end

always @(posedge clk_i)begin
    if(((rstn_avg == 1'b1) && ((trig_o == 1) || (exp_p_dat_i_reg[1] == 1) ))) begin  
    
        delay_flag <= 1'b1;
        if(delay_reached) begin
            rstn_sm <= 1'b0;                // start record machine
        end                        
    end else begin
        rstn_sm <= 1'b1;                    // stop record machine
        delay_flag <= 1'b0;
    end
end

//---------------------------------------------------------------------------------
//  System bus Acquire Module connection for writing FPGA data to CPU and vise versa
//---------------------------------------------------------------------------------
wire sys_en;
assign sys_en = sys_wen | sys_ren;

always @(posedge clk_i)            
if (rstn_i == 1'b0) begin
    set_dec <=  27'd100000000;
end else begin
    if (sys_wen) begin
      if (sys_addr[19:0]==16'h14)    set_dec         <= sys_wdata[27-1:0] ;         // sample count
      if (sys_addr[19:0]==20'h2C)    ctrl_acquire    <= sys_wdata[8-1: 0] ;         // control record machine
      if (sys_addr[19:0]==20'h50)    ctrl_delay_pps  <= sys_wdata[32-1:0] ;         // control delay after pps
      
    end
end

always @(posedge clk_i)        
if (rstn_i == 1'b0) begin
   sys_err <= 1'b0 ;
   sys_ack <= 1'b0 ;
end else begin
   sys_err <= 1'b0 ;

   casez (sys_addr[19:0])
      // config addresss    
     20'h00014  : begin sys_ack <= sys_en;       sys_rdata <= set_dec                ; end           // sample count
     20'h0002C  : begin sys_ack <= sys_en;       sys_rdata <= ctrl_acquire           ; end           // control record machine
     20'h00030  : begin sys_ack <= sys_en;       sys_rdata <= exp_p_dat_i_reg        ; end           // LED Anzeige in GUI (8 bit)
     20'h00050  : begin sys_ack <= sys_en;       sys_rdata <= ctrl_delay_pps         ; end           // delay after pps (32 bit)
          
     // data address

     // default 
     default    : begin sys_ack <= sys_en;       sys_rdata <=  32'h12345             ; end
   endcase
end

endmodule
