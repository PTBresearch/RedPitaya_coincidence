//##############################################################################################
//  https://www.controlpaths.com/2021/04/19/implementing-a-digital-biquad-filter-in-verilog/
//##############################################################################################



`timescale 1ns/1ps

module axis_biquad_tb ();

  reg aclk;
  reg aclk_div2;
  reg resetn;
  reg ce;
  wire signed   [16-1:0] output_data;  //16
  integer f;
  reg   signed [14-1: 0]   test_sig = 0;

  initial begin
    test_sig <= 1'b0;
    #5;
    forever begin
      test_sig <= 1000;
      #1500;
      test_sig <= -1000;
      #1500;
    end
  end

  initial begin
    aclk <= 1'b0;
    #5;
    forever begin
      aclk <= ~aclk;
      #5;
    end
  end

  initial begin
    aclk_div2 <= 1'b0;
    #20;
    forever begin
      aclk_div2 <= ~aclk_div2;
      #20;
    end
  end

  initial begin
    resetn <= 1'b0;
    #100;
    resetn <= 1'b1;
  end

  initial begin
    ce <= 1'b0;
    #10000
    forever begin
      ce <= 1'b1;
      #10
      ce <= 1'b0;
      #(10000-10);
    end
  end
  
  
wire    [10-1: 0]   dds_o;
wire    signed  [10-1: 0]   sin;
wire    signed  [25-1: 0]   sin_25;
wire    signed  [16-1: 0]   sin_16;

signal_generator i_dds(
  .clock_i  (aclk),                

    .ftw_i(48'h147AE147AE1),       // 0,5 MHz  
//  .ftw_i(48'h28F5C28F5C2),       // 1 MHz
//  .ftw_i(48'h7AE147AE147),       // 3 MHz
//  .ftw_i(48'hF5C28F5C28F),       // 6 MHz
   
  .sigout_I_o(dds_o)
);
assign sin = $signed(dds_o) - $signed(10'h200);

reg     signed  [14-1: 0]   sin_old = 0;
wire    signed  [14-1: 0]   sin_d_dt;
always @(posedge aclk_div2)begin
    sin_old <= sin;
end
assign sin_d_dt = (sin - sin_old) << 0;

//assign sin_25 = $signed(sin_d_dt) << 4;
assign sin_25 = $signed(sin) << 4;
assign sin_16 = $signed(sin) << 2;

parameter productWidth = 42;        // original, works
parameter coeffWidth = 18;          // original, works
parameter sig1Width = 25;           // original, works

wire signed [sig1Width-1: 0] IIR1in_a ;     // 14 bit benutzen
wire signed [sig1Width-1: 0] IIR1out_a ;    // 14 bit benutzen

wire signed [sig1Width-1: 0] out_1 ;    // 14 bit benutzen
wire signed [sig1Width-1: 0] in_2  ;    // 14 bit benutzen
wire signed [sig1Width-1: 0] out_2 ;    // 14 bit benutzen
wire signed [sig1Width-1: 0] in_3  ;    // 14 bit benutzen
wire signed [sig1Width-1: 0] out_3 ;    // 14 bit benutzen
wire signed [sig1Width-1: 0] in_4  ;    // 14 bit benutzen
wire signed [sig1Width-1: 0] out_4 ;    // 14 bit benutzen
wire signed [sig1Width-1: 0] in_5  ;    // 14 bit benutzen
wire signed [sig1Width-1: 0] out_5 ;    // 14 bit benutzen
wire signed [sig1Width-1: 0] in_6  ;    // 14 bit benutzen

ptb_biquad  
#(
  .coeffWidth ( coeffWidth ),
  .productWidth (productWidth),
  .sig1Width (sig1Width )
) biquadModule1
( .IIRoutput_o ( out_1     ) ,
  .IIRclk_i    ( aclk      ) ,
  .modeReset_i ( 1'b0      ) ,  
  .IIRinput_i  ( sin_25    ) ,
  
  .b0_i        ( 18'd65042    ) ,
  .b1_i        ( 18'd134435   ) ,
  .b2_i        ( 18'd63854    ) ,
  .NEGa1_i     ( 18'd109973   ) ,
  .NEGa2_i     ( 18'd209848   )
) ;      

ptb_biquad  
#(
  .coeffWidth ( coeffWidth ),
  .productWidth (productWidth),
  .sig1Width (sig1Width )
) biquadModule2
( .IIRoutput_o ( out_2 ) ,
  .IIRclk_i    ( aclk      ) ,
  .modeReset_i ( 1'b0      ) ,  
  .IIRinput_i  ( in_2      ) ,
  
  .b0_i        ( 18'd65042    ) ,
  .b1_i        ( 18'd134435   ) ,
  .b2_i        ( 18'd63854    ) ,
  .NEGa1_i     ( 18'd128205   ) ,
  .NEGa2_i     ( 18'd197787   )
) ;      

ptb_biquad  
#(
  .coeffWidth ( coeffWidth ),
  .productWidth (productWidth),
  .sig1Width (sig1Width )
) biquadModule3
( .IIRoutput_o ( out_3 ) ,
  .IIRclk_i    ( aclk      ) ,
  .modeReset_i ( 1'b0      ) ,  
  .IIRinput_i  ( in_3      ) ,
  
  .b0_i        ( 18'd65042    ) ,
  .b1_i        ( 18'd0   ) ,
  .b2_i        ( 18'd0    ) ,
  .NEGa1_i     ( 18'd0   ) ,
  .NEGa2_i     ( 18'd0   )
) ;      

ptb_biquad  
#(
  .coeffWidth ( coeffWidth ),
  .productWidth (productWidth),
  .sig1Width (sig1Width )
) biquadModule4
( .IIRoutput_o ( out_4 ) ,
  .IIRclk_i    ( aclk      ) ,
  .modeReset_i ( 1'b0      ) ,  
  .IIRinput_i  ( in_4      ) ,
  
  .b0_i        ( 18'd65042    ) ,
  .b1_i        ( 18'd0   ) ,
  .b2_i        ( 18'd0    ) ,
  .NEGa1_i     ( 18'd0   ) ,
  .NEGa2_i     ( 18'd0   )
) ;      
ptb_biquad  
#(
  .coeffWidth ( coeffWidth ),
  .productWidth (productWidth),
  .sig1Width (sig1Width )
) biquadModule5
( .IIRoutput_o ( out_5 ) ,
  .IIRclk_i    ( aclk      ) ,
  .modeReset_i ( 1'b0      ) ,  
  .IIRinput_i  ( in_5      ) ,
  
  .b0_i        ( 18'd65042    ) ,
  .b1_i        ( 18'd0   ) ,
  .b2_i        ( 18'd0    ) ,
  .NEGa1_i     ( 18'd0   ) ,
  .NEGa2_i     ( 18'd0   )
) ;      
ptb_biquad  
#(
  .coeffWidth ( coeffWidth ),
  .productWidth (productWidth),
  .sig1Width (sig1Width )
) biquadModule6
( .IIRoutput_o ( IIR1out_a ) ,
  .IIRclk_i    ( aclk      ) ,
  .modeReset_i ( 1'b0      ) ,  
  .IIRinput_i  ( in_6      ) ,
  
  .b0_i        ( 18'd65042    ) ,
  .b1_i        ( 18'd0   ) ,
  .b2_i        ( 18'd0    ) ,
  .NEGa1_i     ( 18'd0   ) ,
  .NEGa2_i     ( 18'd0   )
) ;      


assign in_2 = out_1;
assign in_3 = out_2;
assign in_4 = out_3;
assign in_5 = out_4;
assign in_6 = out_5;


//  HP 3 MHz 0.5 LpEps
//0a1     109973
//0a2     209848
//0b0     63854
//0b1     134435
//0b2     63854

//1a1     130486
//1a2     197005
//1b0     65042
//1b1     132060
//1b2     65042


  axis_biquad_v1_0 #(
  .inout_width(16),     //16
  .inout_decimal_width(15),
  .coefficient_width(20),
  .coefficient_decimal_width(18),
  .internal_width(20),
  .internal_decimal_width(18)
  ) uut (
  .aclk(aclk),
  .resetn(resetn),
  /* slave axis interface */
  .s_axis_tdata( sin_16 ),
  .s_axis_tlast(1'b0),
  .s_axis_tvalid(ce),
  .s_axis_tready(),
  /* master axis interface */
  .m_axis_tdata(output_data),
  .m_axis_tlast(),
  .m_axis_tvalid(),
  .m_axis_tready(1'b1),
  
  
  /* coefficients 1 pol, 3 MHz*/
//  .b0(20'd493255),
//  .b1(-20'd493255),
//  .b2(20'd0),
//  .a1(-20'd462222),
//  .a2(20'd0)

//  /* coefficients 2 pol, 3 MHz*/
//  .b0(20'd482825),
//  .b1(-20'd963663),
//  .b2(20'd482825),
//  .a1(-20'd963663),
//  .a2(20'd443349)
  
  /* coefficients 1 pol, 15 MHz*/
  .b0(20'd693729),
  .b1(-20'd693729),
  .b2(20'd0),
  .a1(-20'd338882),
  .a2(20'd0)
  
  );

//Sect 0, 1 pol, 3 MHz
//a0   1,000000000000000000
//a1   -0,881618592363189069
//a2   0.000000000000000000
//b0   0,940809296181594479
//b1   -0,940809296181594479
//b2   0.000000000000000000

//Sect 0, 2 pol, 3 MHz
//a0   1,000000000000000000
//a1   -1,838042544821611330
//a2   0,845622350014394009
//b0   0,920916223709001391
//b1   -1,841832447418002780
//b2   0,920916223709001391

//Sect 0, 1 pol, 15 MHz
//a0   1,000000000000000000
//a1   -0,323183950992213587
//a2   0.000000000000000000
//b0   0,661591975496106821
//b1   -0,661591975496106821
//b2   0.000000000000000000


//  /* log data on biquad_simu.sim/sim_1/behav/xsim*/
//  initial begin
//    f = $fopen("data.txt","w");
//  end

//  initial
//    forever begin
//      #10000;
//      $fwrite(f,"%d\n",output_data);
//    end

//  initial begin
//      #1500000
//      $fclose(f);
//      $finish;
//  end


wire signed     [16-1: 0]   sin_dds_1;
wire signed     [16-1: 0]   cos_dds_1;
reg             [48-1: 0]   ftw_dds_1 = 48'h666666666666;
reg             [48-1: 0]   phase_dds_1 = 0;
wire            [48-1: 0]   phase_output;

dds_1 dds_1_inst (
  .aclk(aclk),                                      // input wire aclk
  .s_axis_config_tvalid(1'b1),                      // input wire s_axis_config_tvalid
  .s_axis_config_tdata({phase_dds_1, ftw_dds_1}),   // input wire [95 : 0] s_axis_config_tdata
  
  .m_axis_data_tvalid(),                            // output wire m_axis_data_tvalid
  .m_axis_data_tdata({sin_dds_1, cos_dds_1}),       // output wire [31 : 0] m_axis_data_tdata (sin & cos)
  .m_axis_phase_tvalid(),                           // output wire m_axis_phase_tvalid
  .m_axis_phase_tdata(phase_output)                 // output wire [47 : 0] m_axis_phase_tdata
);


wire signed     [16-1: 0]   sin_dds_2;
wire signed     [16-1: 0]   cos_dds_2;
reg             [48-1: 0]   ftw_dds_2 = 48'h666666666666;
reg             [48-1: 0]   phase_dds_2 = 0;

dds_1 dds_2_inst (
  .aclk(aclk),                                      // input wire aclk
  .s_axis_config_tvalid(1'b1),                      // input wire s_axis_config_tvalid
  .s_axis_config_tdata({phase_dds_2, ftw_dds_2}),   // input wire [95 : 0] s_axis_config_tdata
  
  .m_axis_data_tvalid(),                            // output wire m_axis_data_tvalid
  .m_axis_data_tdata({sin_dds_2, cos_dds_2}),       // output wire [31 : 0] m_axis_data_tdata (sin & cos)
  .m_axis_phase_tvalid(),                           // output wire m_axis_phase_tvalid
  .m_axis_phase_tdata()                             // output wire [47 : 0] m_axis_phase_tdata
);


////////////////////////////////////////////////////////////////////////////////
// Inphase component (cos)
////////////////////////////////////////////////////////////////////////////////
reg signed[32-1: 0]  I_unfiltered = 0;
always @(posedge aclk) begin
    I_unfiltered <= $signed(sin_dds_1) * $signed(sin_dds_2);       
end   

////////////////////////////////////////////////////////////////////////////////
// Quadrature component (sin)
////////////////////////////////////////////////////////////////////////////////
reg signed[32-1: 0]  Q_unfiltered = 0;   
always @(posedge aclk) begin
    Q_unfiltered <= $signed(sin_dds_1) * $signed(cos_dds_2);     
end


wire signed [32-1: 0]  I_filtered;              // Filter output I 1
lowp4 cic_I(
.signal_in          (I_unfiltered[32-1: 4]),    // product
.signal_out         (I_filtered[32-1: 4]),
.clock_in           (aclk),
.reset              (1'b0)
);

wire signed [32-1: 0]  Q_filtered;             // Filter output Q 1
lowp4 cic_Q(
.signal_in          (Q_unfiltered[32-1: 4]),    // product 
.signal_out         (Q_filtered[32-1: 4]),
.clock_in           (aclk),
.reset              (1'b0)
);


//---------------------------------------------------------------------------------
//  slow clock

reg [32-1: 0]   cnt_wait    = 0;
reg [32-1: 0]   time_wait   = 2000;

reg             slow_clock = 0;
reg [32-1: 0]   cnt_clock  = 0;
reg [32-1: 0]   cnt_reg    = 4;

always @(posedge aclk) begin
    if(cnt_clock < cnt_reg - 1)begin
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
wire    [1-1: 0]    exp_p_dat_i = 0;
wire rise_edge_sig;
reg rise_level_sig_ff_1;
reg rise_level_sig_ff_2;

always @(posedge slow_clock) begin

    rise_level_sig_ff_1 <= exp_p_dat_i[0];
    rise_level_sig_ff_2 <= rise_level_sig_ff_1; 
end
assign rise_edge_sig = exp_p_dat_i[0] & (~rise_level_sig_ff_2);

//############ Falling Edge Detection :
wire fall_edge_sig;
reg fall_level_sig_ff_1;
reg fall_level_sig_ff_2;

always @(posedge slow_clock) begin
    fall_level_sig_ff_1 <= exp_p_dat_i[0];
    fall_level_sig_ff_2 <= fall_level_sig_ff_1;
end
assign fall_edge_sig = (~exp_p_dat_i[0]) & fall_level_sig_ff_2;


//---------------------------------------------------------------------------------
reg [14-1: 0]   addra = 0;
reg [14-1: 0]   addrb = 0;
reg [16-1: 0]   data_a_high = 0;
reg [32-1: 0]   data_a_low  = 0;
//reg [16-1: 0]   data_b_high = 16'h28F;              // 1 MHz    192A7371 = 150 Hz
//reg [32-1: 0]   data_b_low  = 32'h28F5C28F5C2;      // 1 MHz      0x400000000000 25 MHz
reg [16-1: 0]   data_b_high = 16'h0;              
reg [32-1: 0]   data_b_low  = 32'h192A7371;      
//reg [16-1: 0]   data_b_high = 16'h2000;              
//reg [32-1: 0]   data_b_low  = 32'h0;      

reg             wea = 1;
reg             enb = 1;

reg [32-1: 0]   time_x10_ns = 0;
reg [2 -1: 0]   start = 2;
reg [2 -1: 0]   state = 2;
reg [2 -1: 0]   state_break = 2;
reg [16-1: 0]   data_a_high_init = 0;
reg [32-1: 0]   data_a_low_init = 0;
reg [48-1: 0]   ftw_dds_1_init = 48'h666666666666;
//reg             [48-1: 0]   ftw_dds_1 = 0;
reg             reached = 0;

always @(posedge slow_clock)begin

     case(state)
    
        2'd0:   begin
                    // increment address
                    if((addrb < 14'd15000) && (reached == 0)) begin
                        addrb <= addrb + 1;
                        ftw_dds_1 <= ftw_dds_1_init + {data_b_high, data_b_low};
                        //data_b_low <= data_b_low + 32'h192A7371;
                        if(addrb == 14'd14999) begin
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
                            //data_b_low <= data_b_low - 10;
                            if(addrb == 14'd1) begin 
                                reached <= 0;
                                state <= 2;
                            end    
                        end
                    end
                end
                
        2'd1:   begin
                    // increment address
                    if((addrb < 14'd15000) && (reached == 0)) begin
                        addrb <= addrb + 1;
                        ftw_dds_1 <= ftw_dds_1_init - {data_b_high, data_b_low};
                        //data_b_low <= data_b_low + 10;
                        if(addrb == 14'd14999) begin
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
                            //data_b_low <= data_b_low - 10;
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
                    ftw_dds_1 <= ftw_dds_1_init;
                    ftw_dds_2 <= ftw_dds_1_init;

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

 localparam PHASE_RESOLUTION_360 = 16;                      // xx Bit represent 360 Degree ATTENTION: when you change this value adapt dsp_phase_measure.sv correspondingly 
 localparam MAGNITUDE_RESOLUTION = PHASE_RESOLUTION_360;    // equivalent to phase resolution because of the common cordic
 localparam PHASE_RESOLUTION_UNWRAPPED = 32;                // Resolution of the phase after unwrapping (fullscale)
 localparam PHASE_RESOLUTION_UNWRAPPED_SATURATED = 19;      // Resolution of the phase after unwrapping and saturation (for limited phase resolution for the controller calculations)

wire signed    [PHASE_RESOLUTION_360-1:0]                   DSP_PHASE_MEASURE_phase;
wire signed    [PHASE_RESOLUTION_UNWRAPPED-1:0]             PHASE_UNWRAPPER_phase_fullscale;
wire                                                        set_phase_unwrapped_zero_trigger;
wire signed    [64-1: 0]   phase_unwrapped;
reg reset = 0;
wire signed [16-1: 0]  phase;      

phase_unwrapper 
    #(
    .WIDTH_OF_PHASE_INPUT (PHASE_RESOLUTION_360),
    .WIDTH_OF_FULLSCALE_PHASE_OUTPUT (PHASE_RESOLUTION_UNWRAPPED),
    .WIDTH_OF_SATURATED_PHASE_OUTPUT (PHASE_RESOLUTION_UNWRAPPED_SATURATED)
    ) 
    phase_unwrapper_inst(
    .i_clk(aclk),
    .i_set_phase_unwrapped_zero_trigger(reset),
    .i_phase_valid(1'b1),
    .i_phase(phase),                                        // input from cordic 16 bit signed!
    .o_unwrapping_risk_of_overflow(/*todo handle this?*/),
    .o_phase_unwrapped_fullscale(phase_unwrapped)           // phase error signal 64 bit
    );

////////////////////////////////////////////////////////////////////////////////
// CORDIC (IP-core): arc tan (Q/I) = Cordic 
////////////////////////////////////////////////////////////////////////////////
// Functional Selection: Translate


wire signed [16-1: 0]  magnitude;                                                                         
wire                   phase_tvalid;
wire        [80-1:0]   cordic_data_raw;

cordic_0 cordic_0_inst (
  .aclk(aclk),                                                          // input wire aclk
  .s_axis_cartesian_tvalid(1'b1),                                       // input wire s_axis_cartesian_tvalid
  .s_axis_cartesian_tdata({I_filtered[32-1: 16], Q_filtered[32-1: 16]}),// input wire [32 : 0] s_axis_cartesian_tdata: IMAG(31:16), REAL(15:0)
  .m_axis_dout_tvalid(phase_tvalid),                                    // output wire m_axis_dout_tvalid
  .m_axis_dout_tdata(cordic_data_raw)                                   // output vector, phase/magnitude
);
assign phase      = cordic_data_raw[42-1:24];       // 18 bit, 16 useable
assign magnitude  = cordic_data_raw[18-1: 0];       // 18 bit, 16 useable



endmodule
