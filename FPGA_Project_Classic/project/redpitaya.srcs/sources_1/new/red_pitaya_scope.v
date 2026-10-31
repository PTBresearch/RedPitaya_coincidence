// SPDX-FileCopyrightText: 2024 Physikalisch-Technische Bundesanstalt (PTB), German National Metrology Institute
// SPDX-License-Identifier: Apache-2.0



//
module red_pitaya_scope #(
  parameter RSZ = 15  // RAM size 2^RSZ      
)(
   // ADC
   input                           adc_clk_i       ,  // ADC clock
   input                           adc_rstn_i      ,  // ADC reset - active low
   input  wire signed   [ 14-1: 0] adc_a_i         ,  // ADC data CHA,    Quelle immer ADC 1
   input  wire signed   [ 14-1: 0] adc_b_i         ,  // ADC data CHB,    Quelle immer ADC 2
   output wire signed   [ 14-1: 0] dac_dat_a_o     ,
   output wire signed   [ 14-1: 0] dac_dat_b_o     ,

   
   // trigger sources
   input                 trig_ext_i      ,  // external trigger
   input                 trig_asg_i      ,  // ASG trigger
   
// Expansion connector
   input wire [8-1:0]    exp_p_dat_i     ,  // exp. con. input data
   

   // System bus
   input      [ 32-1: 0] sys_addr      ,  // bus saddress
   input      [ 32-1: 0] sys_wdata     ,  // bus write data
   input                 sys_wen       ,  // bus write enable
   input                 sys_ren       ,  // bus read enable
   output reg [ 32-1: 0] sys_rdata     ,  // bus read data
   output reg            sys_err       ,  // bus error indicator
   output reg            sys_ack          // bus acknowledge signal
);
reg [8-1:0]     reg_exp_p_dat_i = 0;
reg [1-1: 0]    reg_soft_p_dat = 0;
reg [1-1:0]     en_exp_p_dat = 0;


always @(posedge adc_clk_i)begin
    if(en_exp_p_dat)begin
        reg_exp_p_dat_i <= ~exp_p_dat_i;
    end else
    begin
       reg_exp_p_dat_i <= reg_soft_p_dat; 
    end
end
////////////////////////////////////////////////////////////////////////////////
// Disturbe DDS
////////////////////////////////////////////////////////////////////////////////
wire signed     [16-1: 0]   sin_dds_1;
wire signed     [16-1: 0]   cos_dds_1;
reg             [48-1: 0]   ftw_dds_1 = 0;
reg             [48-1: 0]   phase_dds_1 = 0;
reg             [1-1 : 0]   dds_reset = 0;          // active low

dds_1 dds_1_inst (
  .aclk(adc_clk_i),                                 // input wire aclk
  .aresetn(dds_reset),                              // input wire aresetn
  .s_axis_config_tvalid(1'b1),                      // input wire s_axis_config_tvalid
  .s_axis_config_tdata({phase_dds_1, ftw_dds_1}),   // input wire [95 : 0] s_axis_config_tdata
  
  .m_axis_data_tvalid(),                            // output wire m_axis_data_tvalid
  .m_axis_data_tdata({sin_dds_1, cos_dds_1}),       // output wire [31 : 0] m_axis_data_tdata (sin & cos)
  .m_axis_phase_tvalid(),                           // output wire m_axis_phase_tvalid
  .m_axis_phase_tdata()                             // output wire [47 : 0] m_axis_phase_tdata
);

////////////////////////////////////////////////////////////////////////////////
// Referenz DDS
////////////////////////////////////////////////////////////////////////////////
wire signed     [16-1: 0]   sin_dds_2;
wire signed     [16-1: 0]   cos_dds_2;
reg             [48-1: 0]   ftw_dds_2 = 0;
reg             [48-1: 0]   phase_dds_2 = 0;

dds_1 dds_2_inst (
  .aclk(adc_clk_i),                                 // input wire aclk
  .aresetn(dds_reset),                              // input wire aresetn
  .s_axis_config_tvalid(1'b1),                      // input wire s_axis_config_tvalid
  .s_axis_config_tdata({phase_dds_2, ftw_dds_2}),   // input wire [95 : 0] s_axis_config_tdata
  
  .m_axis_data_tvalid(),                            // output wire m_axis_data_tvalid
  .m_axis_data_tdata({sin_dds_2, cos_dds_2}),       // output wire [31 : 0] m_axis_data_tdata (sin & cos)
  .m_axis_phase_tvalid(),                           // output wire m_axis_phase_tvalid
  .m_axis_phase_tdata()                             // output wire [47 : 0] m_axis_phase_tdata
);

assign dac_dat_a_o = $signed(sin_dds_1[16-1: 2]);
assign dac_dat_b_o = $signed(sin_dds_2[16-1: 2]);


////////////////////////////////////////////////////////////////////////////////
// Inphase component (cos)
////////////////////////////////////////////////////////////////////////////////
reg signed[32-1: 0]  I_unfiltered;
always @(posedge adc_clk_i) begin
    I_unfiltered <= $signed(sin_dds_1) * $signed(sin_dds_2);       
end   

////////////////////////////////////////////////////////////////////////////////
// Quadrature component (sin)
////////////////////////////////////////////////////////////////////////////////
reg signed[32-1: 0]  Q_unfiltered;   
always @(posedge adc_clk_i) begin
    Q_unfiltered <= $signed(sin_dds_1) * $signed(cos_dds_2);     
end


wire signed [32-1: 0]  I_filtered;              // Filter output I 1
lowp4 cic_I(
.signal_in          (I_unfiltered[32-1: 4]),    // product
.signal_out         (I_filtered[32-1: 4]),
.clock_in           (adc_clk_i),
.reset              (1'b0)
);

wire signed [32-1: 0]  Q_filtered;             // Filter output Q 1
lowp4 cic_Q(
.signal_in          (Q_unfiltered[32-1: 4]),    // product 
.signal_out         (Q_filtered[32-1: 4]),
.clock_in           (adc_clk_i),
.reset              (1'b0)
);


reg [15-1: 0]   addra = 0;
reg [15-1: 0]   addrb = 0;
reg [16-1: 0]   data_a_high = 0;
reg [32-1: 0]   data_a_low  = 0 ;
wire[16-1: 0]   data_b_high;
wire[32-1: 0]   data_b_low ;
reg             wea = 1;
reg             enb = 1;
reg [15-1: 0]   steps;

blk_mem_gen_0 disturber (
  .clka(adc_clk_i),    
  .wea(wea),                            // input wire [0 : 0] write enable a
  .addra(addra),                        // input wire [13 : 0] addra
  .dina({data_a_high, data_a_low}),     // input wire [47 : 0] dina
  
  .clkb(adc_clk_i),    
  .enb(enb),                            // input wire read enable b
  .addrb(addrb),                        // input wire [13 : 0] addrb
  .doutb({data_b_high, data_b_low})     // output wire [47 : 0] doutb
);



//---------------------------------------------------------------------------------
//  slow clock

reg             slow_clock  = 0;
reg [32-1: 0]   cnt_clock   = 0;
reg [32-1: 0]   cnt_wait    = 0;
reg [32-1: 0]   time_x10_ns = 200;
reg [32-1: 0]   time_wait   = 1;


always @(posedge adc_clk_i) begin
    if(cnt_clock < time_x10_ns - 1)begin
        cnt_clock <= cnt_clock + 1; 
    end
    else begin
        slow_clock <= ~slow_clock;
        cnt_clock <= 0; 
    end
end


//---------------------------------------------------------------------------------
//  External trigger

//############ Rising Edge Detection :
wire rise_edge_sig;
reg rise_level_sig_ff_1;
reg rise_level_sig_ff_2;

always @(posedge slow_clock) begin
//    if(en_exp_p_dat)begin
        rise_level_sig_ff_1 <= reg_exp_p_dat_i[0];
        rise_level_sig_ff_2 <= rise_level_sig_ff_1;
//    end 
end
assign rise_edge_sig = reg_exp_p_dat_i[0] & (~rise_level_sig_ff_2);

//############ Falling Edge Detection :
wire fall_edge_sig;
reg fall_level_sig_ff_1;
reg fall_level_sig_ff_2;

always @(posedge slow_clock) begin
//    if(en_exp_p_dat)begin
        fall_level_sig_ff_1 <= reg_exp_p_dat_i[0];
        fall_level_sig_ff_2 <= fall_level_sig_ff_1;
//    end        
end
assign fall_edge_sig = (~reg_exp_p_dat_i[0]) & fall_level_sig_ff_2;


//---------------------------------------------------------------------------------

reg [2 -1: 0]   state = 2;
reg [2 -1: 0]   state_break = 2;

reg [16-1: 0]   data_a_high_init = 0;
reg [32-1: 0]   data_a_low_init  = 0;
reg [16-1: 0]   data_b_high_init = 0;
reg [32-1: 0]   data_b_low_init  = 0;
wire[48-1: 0]   ftw_dds_1_init;
wire[48-1: 0]   ftw_dds_2_init;
reg [1-1 : 0]   reached = 0;

always @(posedge slow_clock)begin
     case(state)
        2'd0:   begin
                    // increment address
                    if((addrb < steps) && (reached == 0)) begin
                        addrb <= addrb + 1;
                        ftw_dds_1 <= ftw_dds_1_init + {data_b_high, data_b_low};
                        if(addrb == steps -1) begin
                            reached <= 1;
                            state_break <= state;       // remember state
                            state       <= 3;           // wait...
                        end    
                    end 
                    else begin
                        // decrement address
                        if((addrb > 14'd0) && (reached == 1)) begin
                            addrb <= (addrb) - (1);
                            ftw_dds_1 <= ftw_dds_1_init + {data_b_high, data_b_low};
                            if(addrb == 14'd1) begin 
                                reached <= 0;
                                state <= 2;
                            end    
                        end
                    end
                end
        2'd1:   begin
                    // increment address
                    if((addrb < steps) && (reached == 0)) begin
                        addrb <= addrb + 1;
                        ftw_dds_1 <= ftw_dds_1_init - {data_b_high, data_b_low};
                        if(addrb == steps -1) begin
                            reached <= 1;
                            state_break <= state;       // remember state
                            state       <= 3;           // wait...
                        end     
                    end 
                    else begin
                        // decrement address
                        if((addrb > 14'd0) && (reached == 1)) begin
                            addrb <= (addrb) - (1);
                            ftw_dds_1 <= ftw_dds_1_init - {data_b_high, data_b_low};
                            if(addrb == 14'd1) begin 
                                reached <= 0;
                                state <= 2;
                            end    
                        end
                    end
                end
        2'd2:   begin
                    if(rise_edge_sig) state <= 0;                       // run positive form 
                    if(fall_edge_sig) state <= 1;                       // run negative form
                    
                    if(dds_reset == 0)begin
                        ftw_dds_1   <= 48'd0;  
                        ftw_dds_2   <= 48'd0;
                    end else begin
                        ftw_dds_1 <= ftw_dds_1_init;
                        ftw_dds_2 <= ftw_dds_2_init;
                    end                    
                 end
        2'd3:   begin
                    if(cnt_wait < time_wait - 1)begin
                        cnt_wait <= cnt_wait + 1; 
                    end
                    else begin
                        cnt_wait <= 0;
                        state <= state_break;       // zurueck springen 
                    end                    
                end
    endcase        
end

assign ftw_dds_1_init = {data_a_high_init, data_a_low_init};
assign ftw_dds_2_init = {data_b_high_init, data_b_low_init};
 

 localparam PHASE_RESOLUTION_360 = 16;                      // xx Bit represent 360 Degree ATTENTION: when you change this value adapt dsp_phase_measure.sv correspondingly 
 localparam MAGNITUDE_RESOLUTION = PHASE_RESOLUTION_360;    // equivalent to phase resolution because of the common cordic
 localparam PHASE_RESOLUTION_UNWRAPPED = 64;                // Resolution of the phase after unwrapping (fullscale)
 localparam PHASE_RESOLUTION_UNWRAPPED_SATURATED = 19;      // Resolution of the phase after unwrapping and saturation (for limited phase resolution for the controller calculations)

wire signed    [PHASE_RESOLUTION_360-1:0]                   DSP_PHASE_MEASURE_phase;
wire signed    [PHASE_RESOLUTION_UNWRAPPED-1:0]             PHASE_UNWRAPPER_phase_fullscale;
wire                                                        set_phase_unwrapped_zero_trigger;
wire signed    [64-1: 0]   phase_unwrapped;
reg cordic_reset;
wire signed [16-1: 0]  phase;      

phase_unwrapper 
    #(
    .WIDTH_OF_PHASE_INPUT (PHASE_RESOLUTION_360),
    .WIDTH_OF_FULLSCALE_PHASE_OUTPUT (PHASE_RESOLUTION_UNWRAPPED),
    .WIDTH_OF_SATURATED_PHASE_OUTPUT (PHASE_RESOLUTION_UNWRAPPED_SATURATED)
    ) 
    phase_unwrapper_inst(
    .i_clk(adc_clk_i),
    .i_set_phase_unwrapped_zero_trigger(cordic_reset),
    .i_phase_valid(1'b1),
    .i_phase(phase),                                                    // input from cordic 16 bit signed!
    .o_valid(/*todo handle this?*/),
    .o_phase_unwrapped_fullscale(phase_unwrapped)                       // phase error signal 64 bit
    );

////////////////////////////////////////////////////////////////////////////////
// CORDIC (IP-core): arc tan (Q/I) = Cordic 
////////////////////////////////////////////////////////////////////////////////
// Functional Selection: Translate

wire signed [16-1: 0]  magnitude;                                           
reg  signed [16-1: 0]  phase_old;                                
wire                   phase_tvalid;
wire        [80-1:0]   cordic_data_raw;

cordic_0 cordic_0_inst (
  .aclk(adc_clk_i),                                                     // input wire aclk
  .s_axis_cartesian_tvalid(1'b1),                                       // input wire s_axis_cartesian_tvalid
  .s_axis_cartesian_tdata({I_filtered[32-1: 16], Q_filtered[32-1: 16]}),// input wire [32 : 0] s_axis_cartesian_tdata: IMAG(31:16), REAL(15:0)
  .m_axis_dout_tvalid(phase_tvalid),                                    // output wire m_axis_dout_tvalid
  .m_axis_dout_tdata(cordic_data_raw)                                   // output vector, phase/magnitude
);
assign phase      = cordic_data_raw[42-1:24];       // 18 bit, 16 useable
assign magnitude  = cordic_data_raw[18-1: 0];       // 18 bit, 16 useable

always @(posedge adc_clk_i) begin
    phase_old <= phase;                             // for servo
end


//  System bus connection

always @(posedge adc_clk_i)
if (adc_rstn_i == 1'b0) begin

end else begin
   if (sys_wen) begin
      if (sys_addr[19:0]==20'h00)    wea                <= sys_wdata[1-1: 0] ;
      if (sys_addr[19:0]==20'h04)    enb                <= sys_wdata[1-1: 0] ;
      if (sys_addr[19:0]==20'h100)   addra              <= sys_wdata[15-1:0] ;
      if (sys_addr[19:0]==20'h104)   cordic_reset       <= sys_wdata[1-1: 0] ;
      if (sys_addr[19:0]==20'h108)   dds_reset          <= sys_wdata[1-1: 0] ;

      if (sys_addr[19:0]==20'h200)   data_a_high        <= sys_wdata[16-1:0] ;
      if (sys_addr[19:0]==20'h204)   data_a_low         <= sys_wdata[32-1:0] ;
      if (sys_addr[19:0]==20'h300)   time_x10_ns        <= sys_wdata[32-1:0] ;
      if (sys_addr[19:0]==20'h304)   time_wait          <= sys_wdata[32-1:0] ;
      
      if (sys_addr[19:0]==20'h400)   data_a_high_init   <= sys_wdata[16-1:0] ;
      if (sys_addr[19:0]==20'h404)   data_a_low_init    <= sys_wdata[32-1:0] ;
      if (sys_addr[19:0]==20'h408)   data_b_high_init   <= sys_wdata[16-1:0] ;
      if (sys_addr[19:0]==20'h40C)   data_b_low_init    <= sys_wdata[32-1:0] ;

      if (sys_addr[19:0]==20'h500)   en_exp_p_dat       <= sys_wdata[1-1:0 ] ;
      if (sys_addr[19:0]==20'h504)   reg_soft_p_dat     <= sys_wdata[1-1:0 ] ;

      
      if (sys_addr[19:0]==20'h600)   steps              <= sys_wdata[32-1:0] ;     
            
   end
end

wire sys_en;
assign sys_en = sys_wen | sys_ren;

always @(posedge adc_clk_i)
if (adc_rstn_i == 1'b0) begin
   sys_err <= 1'b0 ;
   sys_ack <= 1'b0 ;
end else begin
   sys_err <= 1'b0 ;

   casez (sys_addr[19:0])

     20'h00000 : begin sys_ack <= sys_en;          sys_rdata <=  phase_unwrapped[64-1:32]         ; end
     20'h00004 : begin sys_ack <= sys_en;          sys_rdata <=  phase_unwrapped[32-1: 0]         ; end

     20'h00500 : begin sys_ack <= sys_en;          sys_rdata <=  exp_p_dat_i[0]     ; end
     20'h00020 : begin sys_ack <= sys_en;          sys_rdata <=  state              ; end


     default : begin sys_ack <= sys_en;          sys_rdata <=  32'h0                 ; end
   endcase
end

endmodule
