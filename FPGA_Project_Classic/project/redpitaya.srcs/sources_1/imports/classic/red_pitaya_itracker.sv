/**
 * $Id: red_pitaya_itracker.v 28.06.2018 Mattias Misera, Julia Fenske (PTB) $
 *
 * @brief Intelligent tracker.
 *
 * @Author Mattias Misera, Julia Fenske (PTB)
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
 * Intelligent tracker and I-/Q-detection.
 *
 *
 *  INPUT                                                                    OUTPUT
 *                 /---\   I                /-----\  I
 *   CHA -----+--> | X | -------------------| FIR | --------------+
 *            |    \---/                    \-----/               |  
 *            |      ^                                            |  
 *            |      |cos                                         |  
 *            |      ------------------|--------------------------|--------> CHA                  
 *            |    /---\   Q           |    /-----\  Q            |  
 *            |--> | X | --------------|----| FIR | -----------------+-----> CHB
 *                 \---/               |    \-----/               |  |
 *                   ^                 |                          |  |
 *                   |-sin             |                          |  |       /---------\
 *                   --------------|   |                          |  +-----> | Arc Tan | 
 *                                 |   |                          +--------> |  (Q/I)  |----+--> phase         
 *                                 |   |                          |  |       \---------/    |
 *                             /-----------\ pinc+  /-------\     |  |                 d/dt |
 *                             |    DDS    | <--+-- | PI 1  | <-----------------------------|   
 *                             \-----------/    |   \-------/     |  |  
 *                                              |   /-------\     |  |       /-------\    /---\    /----\
 *                                              --- | PI 2  | <------+-----> |  Q^2  |--->| + |--->|Sqrt|---> amplitude
 *                                                  \-------/     |          \-------/    \---/    \----/  
 *                                                                |                         ^                         
 *                                                                |          /-------\      |
 *                                                                |--------> |  I^2  |------|
 *                                                                           \-------/
 * 
 */

module red_pitaya_itracker #(
parameter DWE = 8,                  // data width for extension connector
parameter productWidth = 42,        // original, works
parameter coeffWidth = 18,          // original, works
parameter sig1Width = 25            // original, works
)(   
   // signals
   input                 clk_i2x         ,
   input                 clk_i           ,  //!< processing clock
   input                 rstn_i          ,  //!< processing reset - active low
   input      [ 14-1: 0] dat_a_i         ,  //!< input data CHA
   input      [ 14-1: 0] dat_b_i         ,  //!< input data CHB

   output     [ 14-1: 0] record_a_o      ,  //!< output data CHA        record a  ->
   output     [ 14-1: 0] record_b_o      ,  //!< output data CHB        record b  ->
   output     [ 14-1: 0] record_c_o      ,  //!< output data CHA        record c  ->
   output     [ 14-1: 0] record_d_o      ,  //!< output data CHB        record d  ->
   output     [ 14-1: 0] record_e_o      ,  //!< output data CHA        record e  ->
   output     [ 14-1: 0] record_f_o      ,  //!< output data CHB        record f  ->
   output     [ 14-1: 0] dat_a_o         ,  //!< output data CHA        DAC 1 ->
   output     [ 14-1: 0] dat_b_o         ,  //!< output data CHB        DAC 2 ->
   output     [ 48-1: 0] dat_c_o         ,  //!< output data CHC
   output     [ 48-1: 0] dat_d_o         ,  //!< output data CHD
   output     [ 32-1: 0] dat_g_o         ,  //!< output data CHG
   output logic   cycle_slip_flag_1_o    ,  // flag that is set, if I or Q out of threshold bounds
   output logic   cycle_slip_flag_2_o    ,  // flag that is set, if I or Q out of threshold bounds  
   output logic  signed [16-1: 0] phase_1,  // cordic output for cycle slip
   output logic  signed [16-1: 0] phase_2,  // cordic output for servo 
   output logic set_phase_unwrapped_zero_trigger_o,
   input  logic [19-1: 0]   PHASE_UNWRAPPER_phase_saturated_i,
   input  logic [32-1: 0]   PHASE_UNWRAPPER_phase_fullscale_i,
   
// Expansion connector
   input  logic [DWE-1:0] exp_n_dat_i,  // exp. con. input data
   output logic [DWE-1:0] exp_n_dat_o,  // exp. con. output data
   output logic [DWE-1:0] exp_n_dir_o,  // exp. con. 1-output enable
// Expansion connector
   input  logic [DWE-1:0] exp_p_dat_i,  // exp. con. input data
   output logic [DWE-1:0] exp_p_dat_o,  // exp. con. output data
   output logic [DWE-1:0] exp_p_dir_o,  // exp. con. 1-output enable

   // system bus
   input      [ 32-1: 0] sys_addr        ,  //!< bus address
   input      [ 32-1: 0] sys_wdata       ,  //!< bus write data
   input                 sys_wen         ,  //!< bus write enable
   input                 sys_ren         ,  //!< bus read enable
   output logic [ 32-1: 0] sys_rdata     ,  //!< bus read data
   output logic            sys_err       ,  //!< bus error indicator
   output logic            sys_ack            //!< bus acknowledge signal
);

localparam  PSR = 32;
localparam  ISR = 32;
logic signed    [ 48-1: 0] pi_2_out;
logic signed    [ 48-1: 0] pi_2_out_2;

logic  signed   [ 32-1: 0] I_thld               ;  // I_threshold 
logic  signed   [ 32-1: 0] Q_thld               ;  // Q_threshold 
logic  signed   [ 16-1: 0] phase_thld           ;  // phase_threshold
logic  signed   [ 32-1: 0] I_thld_2             ;  // I_threshold 
logic  signed   [ 32-1: 0] Q_thld_2             ;  // Q_threshold 
logic  signed   [ 16-1: 0] phase_thld_2         ;  // phase_threshold
logic  signed   [ 32-1: 0] ampl_thld            ;  // ampl_threshold 
logic  signed   [ 32-1: 0] ampl_thld_2          ;  // ampl threshold 

logic           [ 14-1: 0]  offset_cha          ; // Offset channel A 
logic           [ 14-1: 0]  offset_chb          ; // Offset channel B
logic           [  1-1: 0]  sign_cha            ; // sign channel A 
logic           [  1-1: 0]  sign_chb            ; // sign channel B

//logic           [ 32-1: 0]  cycle_slip_limit    ; // limit that cycle_slip_det is compared to
logic                       cycle_slip_flag     ; // flag that is set, if phase slips a cycle
logic                       cycle_slip_flag_pos ; // flag set if cycle slip occurs with f_dat_i < f_DDS
logic                       cycle_slip_flag_neg ; // flag set if cycle slip occurs with f_dat_i > f_DDS
logic                       omega_limit         ; // flag set if omega > limit || omega < -limit  

logic           [  3-1: 0]  flag_hold           ; // saves cycle slip high status for 125 cycles 
reg                         dds_dac1_en         ;
reg                         dds_dac2_en         ;
reg                         phase_dac1_en       ;
reg                         ampl_dac2_en        ;
reg                         dacs_en             ;

////////////////////////////////////////////////////////////////////////////////
// Biquad IIR Filter (IP-core) iTracker 1
////////////////////////////////////////////////////////////////////////////////

reg                           modeReset_a ;
logic signed [sig1Width-1: 0] IIR1in_a ;
logic signed [sig1Width-1: 0] IIR1out_a ;
logic signed [sig1Width-1: 0] IIR2in_a ;
logic signed [sig1Width-1: 0] IIR2out_a ;
logic signed [sig1Width-1: 0] IIR3in_a ;
logic signed [sig1Width-1: 0] IIR3out_a ;
logic signed [sig1Width-1: 0] IIR4in_a ;
logic signed [sig1Width-1: 0] IIR4out_a ;
logic signed [sig1Width-1: 0] IIR5in_a ;
logic signed [sig1Width-1: 0] IIR5out_a ;
logic signed [sig1Width-1: 0] IIR6in_a ;
logic signed [sig1Width-1: 0] IIR6out_a ;

reg                           modeReset_b ;
logic signed [sig1Width-1: 0] IIR1in_b ;
logic signed [sig1Width-1: 0] IIR1out_b ;
logic signed [sig1Width-1: 0] IIR2in_b ;
logic signed [sig1Width-1: 0] IIR2out_b ;
logic signed [sig1Width-1: 0] IIR3in_b ;
logic signed [sig1Width-1: 0] IIR3out_b ;
logic signed [sig1Width-1: 0] IIR4in_b ;
logic signed [sig1Width-1: 0] IIR4out_b ;
logic signed [sig1Width-1: 0] IIR5in_b ;
logic signed [sig1Width-1: 0] IIR5out_b ;
logic signed [sig1Width-1: 0] IIR6in_b ;
logic signed [sig1Width-1: 0] IIR6out_b ;

reg signed [coeffWidth-1: 0] IIR1b0 ;
reg signed [coeffWidth-1: 0] IIR1b1 ;
reg signed [coeffWidth-1: 0] IIR1b2 ;
reg signed [coeffWidth-1: 0] IIR1NEGa1 ;
reg signed [coeffWidth-1: 0] IIR1NEGa2 ;       
ptb_biquad  
#(
  .coeffWidth ( coeffWidth ),
  .productWidth (productWidth),
  .sig1Width (sig1Width )
) biquadModule1
( .IIRoutput_o ( IIR1out_a ) ,
  .IIRclk_i    ( clk_i     ) ,
  .modeReset_i ( modeReset_a ) ,  
  .IIRinput_i  ( IIR1in_a  ) ,
  .b0_i        ( IIR1b0    ) ,
  .b1_i        ( IIR1b1    ) ,
  .b2_i        ( IIR1b2    ) ,
  .NEGa1_i     ( IIR1NEGa1 ) ,
  .NEGa2_i     ( IIR1NEGa2 )
) ;      

reg signed [coeffWidth-1: 0] IIR2b0 ;
reg signed [coeffWidth-1: 0] IIR2b1 ;
reg signed [coeffWidth-1: 0] IIR2b2 ;
reg signed [coeffWidth-1: 0] IIR2NEGa1 ;
reg signed [coeffWidth-1: 0] IIR2NEGa2 ;       

ptb_biquad 
#(
  .coeffWidth ( coeffWidth ),
  .productWidth (productWidth),
  .sig1Width (sig1Width )
) biquadModule2
( .IIRoutput_o ( IIR2out_a ) ,
  .IIRclk_i    ( clk_i     ) ,
  .modeReset_i ( modeReset_a ) ,  
  .IIRinput_i  ( IIR2in_a  ) ,
  .b0_i        ( IIR2b0    ) ,
  .b1_i        ( IIR2b1    ) ,
  .b2_i        ( IIR2b2    ) ,
  .NEGa1_i     ( IIR2NEGa1 ) ,
  .NEGa2_i     ( IIR2NEGa2 )
) ;      

reg signed [coeffWidth-1: 0] IIR3b0 ;
reg signed [coeffWidth-1: 0] IIR3b1 ;
reg signed [coeffWidth-1: 0] IIR3b2 ;
reg signed [coeffWidth-1: 0] IIR3NEGa1 ;
reg signed [coeffWidth-1: 0] IIR3NEGa2 ;       

ptb_biquad  
#(
  .coeffWidth ( coeffWidth ),
  .productWidth (productWidth),
  .sig1Width (sig1Width )
) biquadModule3
( .IIRoutput_o ( IIR3out_a ) ,
  .IIRclk_i    ( clk_i     ) ,
  .modeReset_i ( modeReset_a ) ,  
  .IIRinput_i  ( IIR3in_a  ) ,
  .b0_i        ( IIR3b0    ) ,
  .b1_i        ( IIR3b1    ) ,
  .b2_i        ( IIR3b2    ) ,
  .NEGa1_i     ( IIR3NEGa1 ) ,
  .NEGa2_i     ( IIR3NEGa2 )
) ;      

reg signed [coeffWidth-1: 0] IIR4b0 ;
reg signed [coeffWidth-1: 0] IIR4b1 ;
reg signed [coeffWidth-1: 0] IIR4b2 ;
reg signed [coeffWidth-1: 0] IIR4NEGa1 ;
reg signed [coeffWidth-1: 0] IIR4NEGa2 ;       

ptb_biquad  
#(
  .coeffWidth ( coeffWidth ),
  .productWidth (productWidth),
  .sig1Width (sig1Width )
) biquadModule4
( .IIRoutput_o ( IIR4out_a ) ,
  .IIRclk_i    ( clk_i     ) ,
  .modeReset_i ( modeReset_a ) ,  
  .IIRinput_i  ( IIR4in_a  ) ,
  .b0_i        ( IIR4b0    ) ,
  .b1_i        ( IIR4b1    ) ,
  .b2_i        ( IIR4b2    ) ,
  .NEGa1_i     ( IIR4NEGa1 ) ,
  .NEGa2_i     ( IIR4NEGa2 )
) ;

reg signed [coeffWidth-1: 0] IIR5b0 ;
reg signed [coeffWidth-1: 0] IIR5b1 ;
reg signed [coeffWidth-1: 0] IIR5b2 ;
reg signed [coeffWidth-1: 0] IIR5NEGa1 ;
reg signed [coeffWidth-1: 0] IIR5NEGa2 ;       

ptb_biquad  
#(
  .coeffWidth ( coeffWidth ),
  .productWidth (productWidth),
  .sig1Width (sig1Width )
) biquadModule5
( .IIRoutput_o ( IIR5out_a ) ,
  .IIRclk_i    ( clk_i     ) ,
  .modeReset_i ( modeReset_a ) ,  
  .IIRinput_i  ( IIR5in_a  ) ,
  .b0_i        ( IIR5b0    ) ,
  .b1_i        ( IIR5b1    ) ,
  .b2_i        ( IIR5b2    ) ,
  .NEGa1_i     ( IIR5NEGa1 ) ,
  .NEGa2_i     ( IIR5NEGa2 )
) ;      

reg signed [coeffWidth-1: 0] IIR6b0 ;
reg signed [coeffWidth-1: 0] IIR6b1 ;
reg signed [coeffWidth-1: 0] IIR6b2 ;
reg signed [coeffWidth-1: 0] IIR6NEGa1 ;
reg signed [coeffWidth-1: 0] IIR6NEGa2 ;       

ptb_biquad 
#(
  .coeffWidth ( coeffWidth ),
  .productWidth (productWidth),
  .sig1Width (sig1Width )
) biquadModule6
( .IIRoutput_o ( IIR6out_a ) ,
  .IIRclk_i    ( clk_i     ) ,
  .modeReset_i ( modeReset_a ) ,  
  .IIRinput_i  ( IIR6in_a  ) ,
  .b0_i        ( IIR6b0    ) ,
  .b1_i        ( IIR6b1    ) ,
  .b2_i        ( IIR6b2    ) ,
  .NEGa1_i     ( IIR6NEGa1 ) ,
  .NEGa2_i     ( IIR6NEGa2 )
) ;
      

reg signed [coeffWidth-1: 0] IIR7b0 ;
reg signed [coeffWidth-1: 0] IIR7b1 ;
reg signed [coeffWidth-1: 0] IIR7b2 ;
reg signed [coeffWidth-1: 0] IIR7NEGa1 ;
reg signed [coeffWidth-1: 0] IIR7NEGa2 ;       

ptb_biquad  
#(
  .coeffWidth ( coeffWidth ),
  .productWidth (productWidth),
  .sig1Width (sig1Width )
) biquadModule7
( .IIRoutput_o ( IIR1out_b ) ,
  .IIRclk_i    ( clk_i     ) ,
  .modeReset_i ( modeReset_b ) ,  
  .IIRinput_i  ( IIR1in_b  ) ,
  .b0_i        ( IIR7b0    ) ,
  .b1_i        ( IIR7b1    ) ,
  .b2_i        ( IIR7b2    ) ,
  .NEGa1_i     ( IIR7NEGa1 ) ,
  .NEGa2_i     ( IIR7NEGa2 )
) ;      

reg signed [coeffWidth-1: 0] IIR8b0 ;
reg signed [coeffWidth-1: 0] IIR8b1 ;
reg signed [coeffWidth-1: 0] IIR8b2 ;
reg signed [coeffWidth-1: 0] IIR8NEGa1 ;
reg signed [coeffWidth-1: 0] IIR8NEGa2 ;       

ptb_biquad  
#(
  .coeffWidth ( coeffWidth ),
  .productWidth (productWidth),
  .sig1Width (sig1Width )
) biquadModule8
( .IIRoutput_o ( IIR2out_b ) ,
  .IIRclk_i    ( clk_i     ) ,
  .modeReset_i ( modeReset_b ) ,  
  .IIRinput_i  ( IIR2in_b  ) ,
  .b0_i        ( IIR8b0    ) ,
  .b1_i        ( IIR8b1    ) ,
  .b2_i        ( IIR8b2    ) ,
  .NEGa1_i     ( IIR8NEGa1 ) ,
  .NEGa2_i     ( IIR8NEGa2 )
) ;

reg signed [coeffWidth-1: 0] IIR9b0 ;
reg signed [coeffWidth-1: 0] IIR9b1 ;
reg signed [coeffWidth-1: 0] IIR9b2 ;
reg signed [coeffWidth-1: 0] IIR9NEGa1 ;
reg signed [coeffWidth-1: 0] IIR9NEGa2 ;       

ptb_biquad  
#(
  .coeffWidth ( coeffWidth ),
  .productWidth (productWidth),
  .sig1Width (sig1Width )
) biquadModule9
( .IIRoutput_o ( IIR3out_b ) ,
  .IIRclk_i    ( clk_i     ) ,
  .modeReset_i ( modeReset_b ) ,  
  .IIRinput_i  ( IIR3in_b  ) ,
  .b0_i        ( IIR9b0    ) ,
  .b1_i        ( IIR9b1    ) ,
  .b2_i        ( IIR9b2    ) ,
  .NEGa1_i     ( IIR9NEGa1 ) ,
  .NEGa2_i     ( IIR9NEGa2 )
) ;

reg signed [coeffWidth-1: 0] IIR10b0 ;
reg signed [coeffWidth-1: 0] IIR10b1 ;
reg signed [coeffWidth-1: 0] IIR10b2 ;
reg signed [coeffWidth-1: 0] IIR10NEGa1 ;
reg signed [coeffWidth-1: 0] IIR10NEGa2 ;       

ptb_biquad  
#(
  .coeffWidth ( coeffWidth ),
  .productWidth (productWidth),
  .sig1Width (sig1Width )
) biquadModule10
( .IIRoutput_o ( IIR4out_b ) ,
  .IIRclk_i    ( clk_i     ) ,
  .modeReset_i ( modeReset_b ) ,  
  .IIRinput_i  ( IIR4in_b  ) ,
  .b0_i        ( IIR10b0    ) ,
  .b1_i        ( IIR10b1    ) ,
  .b2_i        ( IIR10b2    ) ,
  .NEGa1_i     ( IIR10NEGa1 ) ,
  .NEGa2_i     ( IIR10NEGa2 )
) ;

reg signed [coeffWidth-1: 0] IIR11b0 ;
reg signed [coeffWidth-1: 0] IIR11b1 ;
reg signed [coeffWidth-1: 0] IIR11b2 ;
reg signed [coeffWidth-1: 0] IIR11NEGa1 ;
reg signed [coeffWidth-1: 0] IIR11NEGa2 ;       

ptb_biquad  
#(
  .coeffWidth ( coeffWidth ),
  .productWidth (productWidth),
  .sig1Width (sig1Width )
) biquadModule11
( .IIRoutput_o ( IIR5out_b ) ,
  .IIRclk_i    ( clk_i     ) ,
  .modeReset_i ( modeReset_b ) ,  
  .IIRinput_i  ( IIR5in_b  ) ,
  .b0_i        ( IIR11b0    ) ,
  .b1_i        ( IIR11b1    ) ,
  .b2_i        ( IIR11b2    ) ,
  .NEGa1_i     ( IIR11NEGa1 ) ,
  .NEGa2_i     ( IIR11NEGa2 )
) ;

reg signed [coeffWidth-1: 0] IIR12b0 ;
reg signed [coeffWidth-1: 0] IIR12b1 ;
reg signed [coeffWidth-1: 0] IIR12b2 ;
reg signed [coeffWidth-1: 0] IIR12NEGa1 ;
reg signed [coeffWidth-1: 0] IIR12NEGa2 ;       

ptb_biquad  
#(
  .coeffWidth ( coeffWidth ),
  .productWidth (productWidth),
  .sig1Width (sig1Width )
) biquadModule12
( .IIRoutput_o ( IIR6out_b ) ,
  .IIRclk_i    ( clk_i     ) ,
  .modeReset_i ( modeReset_b ) ,  
  .IIRinput_i  ( IIR6in_b  ) ,
  .b0_i        ( IIR12b0    ) ,
  .b1_i        ( IIR12b1    ) ,
  .b2_i        ( IIR12b2    ) ,
  .NEGa1_i     ( IIR12NEGa1 ) ,
  .NEGa2_i     ( IIR12NEGa2 )
) ;

//################################################################################
//  Connections for biquad IIR filter CH 1     ###################################
//################################################################################

logic        [ 1-1: 0]  adc_a_input_mux = 1;    // select input source for iTracker ( ADC or ADC-filtered)
logic signed [14-1: 0]  dat_a_i_mux;            // is going to mixer
logic signed [14-1: 0]  dat_a_i_reg;            // IIR output
//logic signed [14-1: 0]  dat_a_i_offset;         // ADC offset
logic signed [14-1: 0]  dat_a_o_reg;            //

always @(posedge clk_i) begin
    dat_a_i_reg <= $signed(dat_a_i);// + $signed(dat_a_i_offset);            // 14 bit orginal ADC value
    dat_a_o_reg <= IIR6out_a;    
end

always @(posedge clk_i) begin
    case (adc_a_input_mux)
        1'd0:   dat_a_i_mux <= dat_a_o_reg;     // ADC filtered
        1'd1:   dat_a_i_mux <= dat_a_i_reg;     // ADC direct
    endcase
end

assign        IIR1in_a   = $signed(dat_a_i_reg);// 14 bit orginal ADC value
assign        IIR2in_a   = IIR1out_a;
assign        IIR3in_a   = IIR2out_a;
assign        IIR4in_a   = IIR3out_a;
assign        IIR5in_a   = IIR4out_a;
assign        IIR6in_a   = IIR5out_a;

//#############################################################################
//  Connections for biquad IIR filter CH 2
//#############################################################################

logic        [ 1-1: 0]  adc_b_input_mux = 1;    // select input source for iTracker ( ADC or ADC-filtered)
logic signed [14-1: 0]  dat_b_i_mux;            // IIR output
logic signed [14-1: 0]  dat_b_i_reg;            // IIR output
//logic signed [14-1: 0]  dat_b_i_offset;         // ADC offset
logic signed [14-1: 0]  dat_b_o_reg;            //

always @(posedge clk_i) begin
    dat_b_i_reg <= $signed(dat_b_i);// + $signed(dat_b_i_offset);            // 14 bit orginal ADC value
    dat_b_o_reg <= IIR6out_b;
end

always @(posedge clk_i) begin
    case (adc_b_input_mux)
        1'd0:   dat_b_i_mux <= dat_b_o_reg;     // ADC filtered
        1'd1:   dat_b_i_mux <= dat_b_i_reg;     // ADC direct
    endcase
end

assign        IIR1in_b   = $signed(dat_b_i_reg);// 14 bit orginal ADC value
assign        IIR2in_b   = IIR1out_b;
assign        IIR3in_b   = IIR2out_b;
assign        IIR4in_b   = IIR3out_b;
assign        IIR5in_b   = IIR4out_b;
assign        IIR6in_b   = IIR5out_b;


//################################################################################
//  I + Q after biquad filter ####################################################
//################################################################################
/* 
////////////////////////////////////////////////////////////////////////////////
// Inphase component (cos)
////////////////////////////////////////////////////////////////////////////////
logic signed [30-1: 0]  I_unfiltered_a_biquad;                      //
always @(posedge clk_i) begin
    I_unfiltered_a_biquad <= ( $signed(dat_a_i_mux) ) * -$signed(dds_o[15: 0]);    
end

////////////////////////////////////////////////////////////////////////////////
// Quadrature component (sin)
////////////////////////////////////////////////////////////////////////////////
logic signed [30-1: 0]  Q_unfiltered_a_biquad;                      //   
always @(posedge clk_i) begin
    Q_unfiltered_a_biquad <= ( $signed(dat_a_i_mux) ) * $signed(dds_o[31: 16]);
end

////////////////////////////////////////////////////////////////////////////////
// PTB LP filter (IP core): Inphase component (cos)
////////////////////////////////////////////////////////////////////////////////
// 10 MHz LPF - Decimate 4 IIR
// Clock frequency = Input Sampling Frequency: 100 MHz
// Input data width: 32 bit
// Output width: 32 bit 
// Cycle Latency: 4
logic signed [32-1: 0]  I_filtered_a_biquad;                      //
logic                   I_filtered_a_tvalid_biquad;
CIC_Filter i_cic_I_A(
   .CLK          (clk_i),
   .reset        (1'b0),
   .data_in      (I_unfiltered_a_biquad << 2),
   .data_out     (I_filtered_a_biquad),
   .data_out_vld (I_filtered_a_tvalid_biquad)
);

////////////////////////////////////////////////////////////////////////////////
// PTB LP filter (IP core): Quadrature component (sin)
////////////////////////////////////////////////////////////////////////////////
logic signed [32-1: 0]  Q_filtered_a_biquad;                      //
logic                   Q_filtered_a_tvalid_biquad;
CIC_Filter i_cic_Q_A(
   .CLK          (clk_i),
   .reset        (1'b0),
   .data_in      (Q_unfiltered_a_biquad << 2),
   .data_out     (Q_filtered_a_biquad),
   .data_out_vld (Q_filtered_a_tvalid_biquad)
);
*/

//######################################################################################################################
//
// I/Q filter for slip detection..

//-----------------------------------------------------------------------------
// iTracker 1
logic   signed  [28-1: 0]   I_filtered_lowp_a;
logic   signed  [28-1: 0]   Q_filtered_lowp_a;
logic   signed  [28-1: 0]   I_filtered_lowp_b;
logic   signed  [28-1: 0]   Q_filtered_lowp_b;
logic           [ 4-1: 0]   filter_select_a;
logic           [ 4-1: 0]   filter_select_b;

lowpass LP_I_a(
.clk_i              (clk_i),
.reset              (1'b0),
.filter_select_i    (filter_select_a),
.signal_i           (I_filtered[32-1: 4]),
.signal_o           (I_filtered_lowp_a)
);
lowpass LP_Q_a(
.clk_i              (clk_i),
.reset              (1'b0),
.filter_select_i    (filter_select_a),
.signal_i           (Q_filtered[32-1: 4]),
.signal_o           (Q_filtered_lowp_a)
);

//-----------------------------------------------------------------------------
// iTracker 2
lowpass LP_I_b(
.clk_i              (clk_i),
.reset              (1'b0),
.filter_select_i    (filter_select_b),
.signal_i           (I_filtered_2[32-1: 4]),
.signal_o           (I_filtered_lowp_b)
);
lowpass LP_Q_b(
.clk_i              (clk_i),
.reset              (1'b0),
.filter_select_i    (filter_select_b),
.signal_i           (Q_filtered_2[32-1: 4]),
.signal_o           (Q_filtered_lowp_b)
);


////////////////////////////////////////////////////////////////////////////////
// DDS (IP-core)
////////////////////////////////////////////////////////////////////////////////
// Configuration Option: Phase Generator and SIN/COS LUT (DDS)
// System clock: f_clk = 125 MHz
// Phase increment: streaming -> s_axis_phase_tdata (s_axis_phase_tdata: [31 : 0] pinc)
// Phase offset: none
// Output selection: -sin + cos (dds output: [31 : 16] sin, [15 : 0] cos)
// Output width: 16 bit (sign extended)
// Phase width: 32 bit
// Max. output frequency: f_out = (f_clk * max.increment) / 2^(32) = (f_clk * 2^(31)) / 2^(32) = 62.5 MHz
// Frequency resolution: delta_f = f_clk / (2^(phase width)) = 125MHz / 2^(32) = 0.03 Hz
// Latency: 3

logic [32-1: 0] dds_o;       // dds output: [31 : 16] sin, [15 : 0] cos
logic [32-1: 0] dds_ftw_high;
logic [32-1: 0] dds_ftw_low;
logic [64-1: 0] dds_pinc;    // phase increment
logic           dds_tvalid;

//logic   [10-1: 0]   I;
//logic   [10-1: 0]   Q;
//signal_generator i_dds(
//.clock_i        (clk_i),
//.ftw_i          (dds_pinc[48-1: 0]),
//.sigout_I_o     (I),
//.sigout_Q_o     (Q)
//);
//assign dds_o[32-1: 22] = $signed(I) - $signed(512);
//assign dds_o[16-1:  6] = $signed(Q) - $signed(512);

dds_compiler_0 i_dds(
  .aclk(clk_i),                                    // input wire aclk
  .s_axis_phase_tvalid(rstn_i),                    // input wire s_axis_phase_tvalid
  .s_axis_phase_tdata(dds_pinc[48-1: 0]),          // input wire [31 : 0] s_axis_phase_tdata
  .m_axis_data_tvalid(dds_tvalid),                 // output wire m_axis_data_tvalid
  .m_axis_data_tdata(dds_o)                        // output wire [31 : 0] m_axis_data_tdata
);

////////////////////////////////////////////////////////////////////////////////
// DDS (IP-core) 2
////////////////////////////////////////////////////////////////////////////////
// Configuration Option: Phase Generator and SIN/COS LUT (DDS)
// System clock: f_clk = 125 MHz
// Phase increment: streaming -> s_axis_phase_tdata (s_axis_phase_tdata: [31 : 0] pinc)
// Phase offset: none
// Output selection: -sin + cos (dds output: [31 : 16] sin, [15 : 0] cos)
// Output width: 16 bit (sign extended)
// Phase width: 32 bit
// Max. output frequency: f_out = (f_clk * max.increment) / 2^(32) = (f_clk * 2^(31)) / 2^(32) = 62.5 MHz
// Frequency resolution: delta_f = f_clk / (2^(phase width)) = 125MHz / 2^(32) = 0.03 Hz
// Latency: 3

logic [32-1: 0] dds_o_2;       // dds output: [31 : 16] sin, [15 : 0] cos
logic [32-1: 0] dds_ftw_high_2;
logic [32-1: 0] dds_ftw_low_2;
logic [64-1: 0] dds_pinc_2;    // phase increment
logic           dds_tvalid_2;

dds_compiler_0 i_dds_2(
  .aclk(clk_i),                                    // input wire aclk
  .s_axis_phase_tvalid(rstn_i),                    // input wire s_axis_phase_tvalid
  .s_axis_phase_tdata(dds_pinc_2[48-1: 0]),        // input wire [31 : 0] s_axis_phase_tdata
  .m_axis_data_tvalid(dds_tvalid_2),               // output wire m_axis_data_tvalid
  .m_axis_data_tdata(dds_o_2)                      // output wire [31 : 0] m_axis_data_tdata
);

////////////////////////////////////////////////////////////////////////////////
// Inphase component (cos), CH1
////////////////////////////////////////////////////////////////////////////////
// A operand width: 14 bit
// B operand width: 16 bit
// Output width: 30 bit 

logic signed[30-1: 0]  I_unfiltered;   
always @(posedge clk_i) begin
    I_unfiltered <= ( $signed(dat_a_i_mux) ) * -$signed(dds_o[15: 0]);           // ADC mux, ADC direct oder ueber Filter...
end

////////////////////////////////////////////////////////////////////////////////
// Quadrature component (sin) CH1
////////////////////////////////////////////////////////////////////////////////
logic signed[30-1: 0]  Q_unfiltered;   
always @(posedge clk_i) begin
    Q_unfiltered <= ( $signed(dat_a_i_mux) ) * $signed(dds_o[31: 16]);           // ADC mux, ADC direct oder ueber Filter...
end

////////////////////////////////////////////////////////////////////////////////
// Inphase component (cos), CH2
////////////////////////////////////////////////////////////////////////////////
// A operand width: 14 bit
// B operand width: 16 bit
// Output width: 30 bit 

logic signed[30-1: 0]  I_unfiltered_2;
always @(posedge clk_i) begin
    I_unfiltered_2 <= ( $signed(dat_b_i_mux) ) * -$signed(dds_o_2[15: 0]);       // ADC mux
end   

////////////////////////////////////////////////////////////////////////////////
// Quadrature component (sin), CH2
////////////////////////////////////////////////////////////////////////////////
logic signed[30-1: 0]  Q_unfiltered_2;   
always @(posedge clk_i) begin
    Q_unfiltered_2 <= ( $signed(dat_b_i_mux) ) * $signed(dds_o_2[31: 16]);       // ADC mux
end

////////////////////////////////////////////////////////////////////////////////
// PTB LP filter (IP core): Inphase component (cos)
////////////////////////////////////////////////////////////////////////////////
// 10 MHz LPF - Decimate 4 IIR
// Clock frequency = Input Sampling Frequency: 100 MHz
// Input data width: 32 bit
// Output width: 32 bit 
// Cycle Latency: 4

//CIC_Filter i_cic_I(
//   .CLK          (clk_i),
//   .reset        (1'b0),
//   .data_in      (I_unfiltered << 2),
//   .data_out     (I_filtered),
//   .data_out_vld (I_filtered_tvalid)
//);
logic signed [32-1: 0]  I_filtered;                             // Filter output I 1
logic                   I_filtered_tvalid;
lowp4 i_cic_I(
.signal_in          (I_unfiltered[30-1: 2]),                    // product (ADC * NCO)
.signal_out         (I_filtered[32-1: 4]),
.clock_in           (clk_i),
.reset              (1'b0)
);

////////////////////////////////////////////////////////////////////////////////
// PTB LP filter (IP core): Quadrature component (sin)
////////////////////////////////////////////////////////////////////////////////

//CIC_Filter i_cic_Q(
//   .CLK          (clk_i),
//   .reset        (1'b0),
//   .data_in      (Q_unfiltered << 2),
//   .data_out     (Q_filtered),
//   .data_out_vld (Q_filtered_tvalid)
//);
logic signed [32-1: 0]  Q_filtered;                     // Filter output Q 1
logic                   Q_filtered_tvalid;
lowp4 i_cic_Q(
.signal_in          (Q_unfiltered[30-1: 2]),
.signal_out         (Q_filtered[32-1: 4]),
.clock_in           (clk_i),
.reset              (1'b0)
);

////////////////////////////////////////////////////////////////////////////////
// PTB LP filter (IP core): Inphase component (cos) 2
////////////////////////////////////////////////////////////////////////////////
// 10 MHz LPF - Decimate 4 LP
// Clock frequency = Input Sampling Frequency: 100 MHz
// Input data width: 32 bit
// Output width: 32 bit 
// Cycle Latency: 4

//CIC_Filter i_cic_I_2(
//   .CLK          (clk_i),
//   .reset        (1'b0),
//   .data_in      (I_unfiltered_2 << 2),
//   .data_out     (I_filtered_2),
//   .data_out_vld (I_filtered_tvalid_2)
//);
logic signed [32-1: 0]  I_filtered_2;                   // Filter output I 2
logic                   I_filtered_tvalid_2;
lowp4 i_cic_I_2(
.signal_in          (I_unfiltered_2[30-1: 2]),
.signal_out         (I_filtered_2[32-1: 4]),
.clock_in           (clk_i),
.reset              (1'b0)
);

////////////////////////////////////////////////////////////////////////////////
// PTB LP filter (IP core): Quadrature component (sin) 2
////////////////////////////////////////////////////////////////////////////////

//CIC_Filter i_cic_Q_2(
//   .CLK          (clk_i),
//   .reset        (1'b0),
//   .data_in      (Q_unfiltered_2 << 2),
//   .data_out     (Q_filtered_2),
//   .data_out_vld (Q_filtered_tvalid_2)
//);
logic signed [32-1: 0]  Q_filtered_2;                   // Filter output Q 2
logic                   Q_filtered_tvalid_2;
lowp4 i_cic_Q_2(
.signal_in          (Q_unfiltered_2[30-1: 2]),
.signal_out         (Q_filtered_2[32-1: 4]),
.clock_in           (clk_i),
.reset              (1'b0)
);

////////////////////////////////////////////////////////////////////////////////
// CORDIC_0 (IP-core): arc tan (Q/I) = Cordic CH1 for cycle slip detection
////////////////////////////////////////////////////////////////////////////////
// Functional Selection: Translate

//logic  signed [16-1: 0]  phase_1;                       // Cordic phase output
logic  signed [16-1: 0]  magnitude_1;                   // Cordic magnitude output
logic  signed [16-1: 0]  phase_1_old;                   // Cordic phase output old
logic                    phase_1_tvalid;
logic         [80-1:0]   cordic_1_data_raw;             // Cordic raw data

cordic_0 i_cordic_arctan (
  .aclk(clk_i),                                                                         // input wire aclk
  .s_axis_cartesian_tvalid(1'b1),                                                       // input wire s_axis_cartesian_tvalid     // Mattias  
  .s_axis_cartesian_tdata({Q_filtered_lowp_a[28-1: 12],I_filtered_lowp_a[28-1: 12]}),   // input wire [32 : 0] s_axis_cartesian_tdata: IMAG(31:16), REAL(15:0)
  .m_axis_dout_tvalid(phase_1_tvalid),                                                  // output wire m_axis_dout_tvalid
  .m_axis_dout_tdata(cordic_1_data_raw)                                                 // output vector, phase/magnitude 
);
assign phase_1      = cordic_1_data_raw[42-1:24];   // 18 bit, 16 useable
assign magnitude_1  = cordic_1_data_raw[18-1: 0];   // 18 bit, 16 useable
 
always @(posedge clk_i) begin
    phase_1_old <= phase_1;                         // for cycle slip detection
end

////////////////////////////////////////////////////////////////////////////////
// CORDIC_0 (IP-core): arc tan (Q/I) = Cordic CH 1 for servo
////////////////////////////////////////////////////////////////////////////////
// Functional Selection: Translate

//logic signed [16-1: 0]  phase_2;      
logic signed [16-1: 0]  magnitude_2;                                           
logic signed [16-1: 0]  phase_2_old;                                
logic                   phase_2_tvalid;
logic        [80-1:0]   cordic_2_data_raw;

cordic_0 i_cordic_arctan_2 (
  .aclk(clk_i),                                                                         // input wire aclk
  .s_axis_cartesian_tvalid(1'b1),                                                       // input wire s_axis_cartesian_tvalid
  .s_axis_cartesian_tdata({Q_filtered[32-1: 16],I_filtered[32-1: 16]}),                 // input wire [32 : 0] s_axis_cartesian_tdata: IMAG(31:16), REAL(15:0)
  .m_axis_dout_tvalid(phase_2_tvalid),                                                  // output wire m_axis_dout_tvalid
  .m_axis_dout_tdata(cordic_2_data_raw)                                                 // output vector, phase/magnitude
);
assign phase_2      = cordic_2_data_raw[42-1:24];       // 18 bit, 16 useable
assign magnitude_2  = cordic_2_data_raw[18-1: 0];       // 18 bit, 16 useable

always @(posedge clk_i) begin
    phase_2_old <= phase_2;                             // for servo
end


////////////////////////////////////////////////////////////////////////////////
// Inphase^2
////////////////////////////////////////////////////////////////////////////////

logic [32-1: 0]  I_2; 

always @(posedge clk_i) begin                    
//    I_2 <= $signed(I_filtered_lowp_a[28-1: 12]) * $signed(I_filtered_lowp_a[28-1: 12]);
end

////////////////////////////////////////////////////////////////////////////////
// Quadrature^2
////////////////////////////////////////////////////////////////////////////////

logic[32-1: 0]  Q_2;        

always @(posedge clk_i) begin                    
//    Q_2 <= $signed(Q_filtered_lowp_a[28-1: 12]) * $signed(Q_filtered_lowp_a[28-1: 12]);
end

////////////////////////////////////////////////////////////////////////////////
// CORDIC_1 (IP-core): square root (I  + Q ) = amplitude
////////////////////////////////////////////////////////////////////////////////

logic [32-1: 0]  ampl_sum;     
logic [16-1: 0]  ampl;

always @(posedge clk_i) begin                    
//    ampl_sum <= (I_2 + Q_2) >> 1;
end

////////////////////////////////////////////////////////////////////////////////
// Inphase^2
////////////////////////////////////////////////////////////////////////////////

logic [32-1: 0]  I_2_2; 

always @(posedge clk_i) begin                    
//    I_2_2 <= $signed(I_filtered_lowp_b[28-1: 12]) * $signed(I_filtered_lowp_b[28-1: 12]);
end

////////////////////////////////////////////////////////////////////////////////
// Quadrature^2
////////////////////////////////////////////////////////////////////////////////

logic[32-1: 0]  Q_2_2;        

always @(posedge clk_i) begin                    
//    Q_2_2 <= $signed(Q_filtered_lowp_b[28-1: 12]) * $signed(Q_filtered_lowp_b[28-1: 12]);
end

////////////////////////////////////////////////////////////////////////////////
// CORDIC_1 (IP-core): square root (I  + Q ) = amplitude
////////////////////////////////////////////////////////////////////////////////

logic [32-1: 0]  ampl_sum_2;     
logic [16-1: 0]  ampl_2;

always @(posedge clk_i) begin                    
//    ampl_sum_2 <= (I_2_2 + Q_2_2) >> 1;
end
    

////////////////////////////////////////////////////////////////////////////////
// PI 2, CH1 Servo for Q signal
////////////////////////////////////////////////////////////////////////////////

logic  [ 32-1: 0] set_2_sp    ;
logic  [ 32-1: 0] set_2_kp    ;
logic  [ 32-1: 0] set_2_ki    ;
logic  [ 32-1: 0] set_2_kp_phi;
logic  [ 32-1: 0] set_2_ki_phi;
logic             set_2_irst  ;
logic             int_rst_2_total;

logic [32-1: 0]     Q_filtered_pipe_1;
logic [32-1: 0]     Q_filtered_pipe_2;
logic [32-1: 0]     Q_filtered_pipe_3;
logic [32-1: 0]     Q_filtered_pipe_4;
logic [32-1: 0]     Q_filtered_pipe_5;
logic [32-1: 0]     Q_filtered_pipe_6;
logic [32-1: 0]     Q_filtered_pipe_7;
logic [32-1: 0]     Q_filtered_pipe_8;
logic [32-1: 0]     Q_filtered_pipe_9;
logic [32-1: 0]     Q_filtered_pipe_10;
logic [32-1: 0]     Q_filtered_pipe_11;
logic [32-1: 0]     Q_filtered_pipe_12;
logic [32-1: 0]     Q_filtered_pipe_13;
logic [32-1: 0]     Q_filtered_pipe_14;
logic [32-1: 0]     Q_filtered_pipe_15;
logic [32-1: 0]     Q_filtered_pipe_16;
logic [32-1: 0]     Q_filtered_pipe_17;
logic [32-1: 0]     Q_filtered_pipe_18;
logic [32-1: 0]     Q_filtered_pipe_19;
logic [32-1: 0]     Q_filtered_pipe_20;
logic [32-1: 0]     Q_filtered_pipe_21;
logic [32-1: 0]     Q_filtered_pipe_22;
logic [32-1: 0]     Q_filtered_pipe_23;
logic [32-1: 0]     Q_filtered_pipe_24;

//always @(clk_i) begin
//    Q_filtered_pipe_1 <= Q_filtered;
//    Q_filtered_pipe_2  <= Q_filtered_pipe_1;
//    Q_filtered_pipe_3  <= Q_filtered_pipe_2;
//    Q_filtered_pipe_4  <= Q_filtered_pipe_3;
//    Q_filtered_pipe_5  <= Q_filtered_pipe_4;
//    Q_filtered_pipe_6  <= Q_filtered_pipe_5;
//    Q_filtered_pipe_7  <= Q_filtered_pipe_6;
//    Q_filtered_pipe_8  <= Q_filtered_pipe_7;
//    Q_filtered_pipe_9  <= Q_filtered_pipe_8;
//    Q_filtered_pipe_10 <= Q_filtered_pipe_9;
//    Q_filtered_pipe_11 <= Q_filtered_pipe_10;
//    Q_filtered_pipe_12 <= Q_filtered_pipe_11;
//    Q_filtered_pipe_13 <= Q_filtered_pipe_12;
//    Q_filtered_pipe_14 <= Q_filtered_pipe_13;
//    Q_filtered_pipe_15 <= Q_filtered_pipe_14;
//    Q_filtered_pipe_16 <= Q_filtered_pipe_15;
//    Q_filtered_pipe_17 <= Q_filtered_pipe_16;
//    Q_filtered_pipe_18 <= Q_filtered_pipe_17;
//    Q_filtered_pipe_19 <= Q_filtered_pipe_18;
//    Q_filtered_pipe_20 <= Q_filtered_pipe_19;
//    Q_filtered_pipe_21 <= Q_filtered_pipe_20;
//    Q_filtered_pipe_22 <= Q_filtered_pipe_21;
//    Q_filtered_pipe_23 <= Q_filtered_pipe_22;
//    Q_filtered_pipe_24 <= Q_filtered_pipe_23;

//end

logic   signed  [32-1: 0]   Q_filtered_old;
logic   signed  [32-1: 0]   Q_filtered_ddt;

always @(clk_i) begin
    Q_filtered_old  <= Q_filtered;
end
assign  Q_filtered_ddt  = ($signed(Q_filtered) - $signed(Q_filtered_old)) << 4;

PI_PTB i_pi2 ( 
// PL Connections
.CLK            (clk_i              ),
.reset          (int_rst_2_total    ),  // active high.
// Data INput
.sensor_in      ($signed(Q_filtered_ddt)),  // input data 32 bit
// PI Controller Inputs
.set_point      (  set_2_sp         ),  // set point
.P_gain         (  set_2_kp         ),  // Kp 16 bit
.I_gain         (  set_2_ki         ),  // Ki 16 bit
// Output
.ctrl_sig       (  pi_2_out         )   // output data 48 bit
);
////////////////////////////////////////////////////////////////////////////////
// PI 2, CH1 PI servo for unwrapper !!!!!!!!!!!!!!!!!!!!!!
////////////////////////////////////////////////////////////////////////////////


logic   signed  [32-1: 0]   error;
logic   signed  [32-1: 0]   error_old;

always @(clk_i) begin
    error       <= PHASE_UNWRAPPER_phase_fullscale_i;
    error_old   <= error;
end


logic   signed  [48-1: 0]   PHASE_UNWRAPPER_servo;
PI_PTB i_pi2_unwrapper ( 
// PL Connections
.CLK            (clk_i              ),
.reset          (int_rst_2_total    ),  // active high.
// Data INput
.sensor_in      ($signed(PHASE_UNWRAPPER_phase_fullscale_i)),           // 32 bit input data unwrapper
//.sensor_in      ($signed(error) - $signed(error_old)),                // 32 bit input data unwrapper d/dt

// PI Controller Inputs
.set_point      (  set_2_sp         ),  // set point
.P_gain         (  set_2_kp_phi     ),  // Kp 16 bit
.I_gain         (  set_2_ki_phi     ),  // Ki 16 bit
// Output
.ctrl_sig       (  PHASE_UNWRAPPER_servo)   // output data 48 bit unwrapper
);

assign set_phase_unwrapped_zero_trigger_o = int_rst_2_total;

////////////////////////////////////////////////////////////////////////////////
// PI 2, CH2
////////////////////////////////////////////////////////////////////////////////

logic  [ 32-1: 0] set_2_sp_2    ;
logic  [ 32-1: 0] set_2_kp_2    ;
logic  [ 32-1: 0] set_2_ki_2    ;
logic             set_2_irst_2  ;
logic            int_rst_2_total_2;

PI_PTB i_pi2_2 ( 
// PL Connections
.CLK            (clk_i                  ),  
.reset          (int_rst_2_total_2      ),  // active high.
// Data INput
.sensor_in      ($signed(Q_filtered_2   )), // input data
// PI Controller Inputs
.set_point      (  set_2_sp_2           ),  // set point
.P_gain         (  set_2_kp_2           ),  // Kp 16 bit
.I_gain         (  set_2_ki_2           ),  // Ki 16 bit
// Output
.ctrl_sig       (  pi_2_out_2           )   // output data 48 bit
);


////////////////////////////////////////////////////////////////////////////////
// Calc phase increment: pinc = old value + PI1 + PI2
////////////////////////////////////////////////////////////////////////////////
//assign dds_pinc =  $signed({dds_ftw_high, dds_ftw_low}) + (($signed(pi_2_out))) ;                              // for iTracker ch1 PI servo
//assign dds_pinc =  $signed({dds_ftw_high, dds_ftw_low}) + $signed(PHASE_UNWRAPPER_servo);                      // for iTracker ch1 unwrapper server
  assign dds_pinc =  $signed({dds_ftw_high, dds_ftw_low}) + $signed(pi_2_out) + $signed(PHASE_UNWRAPPER_servo);  // for iTracker ch1 PI + unwrapper servo

//assign dds_pinc =  $signed({dds_ftw_high, dds_ftw_low});                                                       // for DPLL (NIST)

////////////////////////////////////////////////////////////////////////////////
// Calc phase increment: pinc 2 = old value 2 + PI1 2 + PI2 2
////////////////////////////////////////////////////////////////////////////////
  assign dds_pinc_2 =  $signed({dds_ftw_high_2, dds_ftw_low_2}) + (($signed(pi_2_out_2))) ;                      // for iTracker ch2 PI servo
//assign dds_pinc_2 =  $signed({dds_ftw_high_2, dds_ftw_low_2});                                                 // for DPLL (NIST)


////////////////////////////////////////////////////////////////////////////////
// Cycle-slip detection alternative (window discriminator)
////////////////////////////////////////////////////////////////////////////////

logic trig_flag;

logic Q_comp_1;
logic I_comp_1;
logic Q_comp_2;
logic I_comp_2;
logic Omega_comp_1;
logic Omega_comp_2;
logic Cycle_comp_1;
logic Cycle_comp_2;
logic [32-1: 0]     cnt_Q_comp_1; 
logic [32-1: 0]     cnt_Q_comp_1_prev;
logic [32-1: 0]     cnt_I_comp_1;
logic [32-1: 0]     cnt_I_comp_1_prev;
logic [32-1: 0]     cnt_Omega_comp_1;
logic [32-1: 0]     cnt_Omega_comp_1_min;
logic [32-1: 0]     cnt_Omega_comp_1_prev_s;
logic [32-1: 0]     cnt_Omega_comp_1_prev_min;
logic [32-1: 0]     cnt_Cycle_comp_1;
logic [32-1: 0]     cnt_cycle_slip_1_prev;
logic [32-1: 0]     cnt_Q_comp_2;
logic [32-1: 0]     cnt_Q_comp_2_prev;
logic [32-1: 0]     cnt_I_comp_2;
logic [32-1: 0]     cnt_I_comp_2_prev;
logic [32-1: 0]     cnt_Omega_comp_2;
logic [32-1: 0]     cnt_Omega_comp_2_min;
logic [32-1: 0]     cnt_Omega_comp_2_prev_s;
logic [32-1: 0]     cnt_Omega_comp_2_prev_min;
logic [32-1: 0]     cnt_Cycle_comp_2;
logic [32-1: 0]     cnt_cycle_slip_2_prev;
logic [32-1: 0]     cnt;
logic [32-1: 0]     cnt_sec;


logic [4-1: 0]      clk_i_2;
always @(posedge clk_i) begin
    clk_i_2 <= clk_i_2 + 1;
end

always @(posedge clk_i_2[1]) begin
 cnt_sec <= cnt_sec + 1'b1;
 // do every min...
 if(cnt_sec == 32'd1500000000) begin
    cnt_Omega_comp_1_prev_min   <= cnt_Omega_comp_1_min;
    cnt_Omega_comp_2_prev_min   <= cnt_Omega_comp_2_min;
    cnt_Omega_comp_1_min        <= 32'b0;
    cnt_Omega_comp_2_min        <= 32'b0;
    cnt_sec                     <= 32'b0;       
    end else begin
    if(Omega_comp_1) begin
        cnt_Omega_comp_1_min<= cnt_Omega_comp_1_min + 1'b1;
    end
    if(Omega_comp_2) begin
        cnt_Omega_comp_2_min<= cnt_Omega_comp_2_min + 1'b1;
    end
 end
end

always @(posedge clk_i) begin
 cnt <= cnt + 1'b1;
 // do every second...
 if(cnt == 32'd100000000) begin
      cnt_Q_comp_1_prev         <= cnt_Q_comp_1;
      cnt_I_comp_1_prev         <= cnt_I_comp_1;
      cnt_Omega_comp_1_prev_s   <= cnt_Omega_comp_1;
      cnt_cycle_slip_1_prev     <= cnt_Cycle_comp_1;
      cnt_Q_comp_2_prev         <= cnt_Q_comp_2;
      cnt_I_comp_2_prev         <= cnt_I_comp_2;
      cnt_Omega_comp_2_prev_s   <= cnt_Omega_comp_2;
      cnt_cycle_slip_2_prev     <= cnt_Cycle_comp_2;
      cnt_Q_comp_1              <= 32'b0;
      cnt_I_comp_1              <= 32'b0;
      cnt_Omega_comp_1          <= 32'b0;
      cnt_Cycle_comp_1          <= 32'b0;
      cnt_Q_comp_2              <= 32'b0;
      cnt_I_comp_2              <= 32'b0;
      cnt_Omega_comp_2          <= 32'b0;
      cnt_Cycle_comp_2          <= 32'b0;
      cnt                       <= 32'b0;
    end else begin
//################## iTracker 1 ####################################       
//       if (($signed(Q_filtered) > $signed(Q_thld)) || ($signed(Q_filtered) < -$signed(Q_thld))) begin
//        Q_comp_1        <= 1'b1;
//        cnt_Q_comp_1    <= cnt_Q_comp_1 + 1'b1;
//       end else begin
//        Q_comp_1 <= 1'b0;
//       end    
//       if (($signed(I_filtered) < -$signed(I_thld)) || ($signed(I_filtered) > $signed(I_thld))) begin
//        I_comp_1        <= 1'b1;
//        cnt_I_comp_1    <= cnt_I_comp_1 + 1'b1;
//       end else begin
//        I_comp_1 <= 1'b0;
//       end    
       if (($signed(phase_1) > $signed(phase_thld)) || ($signed(phase_1) < -$signed(phase_thld)) || ((magnitude_1[16-1: 0]) < (ampl_thld))) begin
            Omega_comp_1        <= 1'b1;
            cnt_Omega_comp_1    <= cnt_Omega_comp_1 + 1'b1;
       end else begin
            Omega_comp_1 <= 1'b0;
       end    
//       if ((($signed(phase_1_old) >= 0) && ($signed(phase_1) < 0)) || (($signed(phase_1_old) < 0) && ($signed(phase_1) >= 0)) && Omega_comp_1 ) begin   
//            Cycle_comp_1        <= 1'b1;
//            cnt_Cycle_comp_1    <= cnt_Cycle_comp_1 + 1'b1;
//            end else begin
//            Cycle_comp_1 <= 1'b0;
//       end    

//################## iTracker 2 ####################################            
//       if (($signed(Q_filtered_2) > $signed(Q_thld_2)) || ($signed(Q_filtered_2) < -$signed(Q_thld_2))) begin
//        Q_comp_2        <= 1'b1;
//        cnt_Q_comp_2    <= cnt_Q_comp_2 + 1'b1;
//       end else begin
//        Q_comp_2 <= 1'b0;
//       end    
//       if (($signed(I_filtered_2) < -$signed(I_thld_2)) || ($signed(I_filtered_2) > $signed(I_thld_2))) begin
//        I_comp_2 <= 1'b1;
//        cnt_I_comp_2    <= cnt_I_comp_2 + 1'b1;
//       end else begin
//        I_comp_2 <= 1'b0;
//       end  
       if (($signed(phase_2) > $signed(phase_thld_2)) || ($signed(phase_2) < -$signed(phase_thld_2)) || ((magnitude_2[16-1: 0]) < (ampl_thld_2))) begin
        Omega_comp_2        <= 1'b1;
        cnt_Omega_comp_2    <= cnt_Omega_comp_2 + 1'b1;
       end else begin
        Omega_comp_2 <= 1'b0;
       end    
//       if ((($signed(phase_2_old) < 0) && ($signed(phase_2) >= 0)) || (($signed(phase_2_old) > 0) && ($signed(phase_2) <= 0)) && Omega_comp_2 ) begin
//        Cycle_comp_2        <= 1'b1;
//        cnt_Cycle_comp_2    <= cnt_Cycle_comp_2 + 1'b1;
//       end else begin
//        Cycle_comp_2 <= 1'b0;
//       end         
    end
end


assign cycle_slip_flag_1_o  = Omega_comp_1;     // wird fuer trigger (scope modul) verwendet...
assign cycle_slip_flag_2_o  = Omega_comp_2;
//assign exp_p_dat_o[2]       = Omega_comp_1;

////////////////////////////////////////////////////////////////////////////////
// Expansion connector
////////////////////////////////////////////////////////////////////////////////
/*
   logic   [    14-1: 0] count      ;
   logic   [    14-1: 0] count0     ;
   logic   [    14-1: 0] count1     ;
   logic   [    14-1: 0] count2     ;
   logic   [    14-1: 0] hold_time  ;
   
   always @(posedge clk_i) begin
      if (rstn_i == 1'b0) begin
         exp_n_dat_o  <= {DWE{1'b0}};
         exp_n_dir_o  <= {DWE{1'b1}}; // output
         count        <= {14{1'b0}};
         count0       <= {14{1'b0}};
         count1       <= {14{1'b0}};
         count2       <= {14{1'b0}};
         hold_time    <= 5;
      end
      else begin
         if (Q_comp_1) begin
            exp_n_dat_o[2]  <= Q_comp_1; 
            count           <= hold_time; 
         end 
         else if ($signed(count) > 0) 
            count <= $signed(count) - 1; 
         else if (($signed(count) == 0) && (!Q_comp_1))
            exp_n_dat_o[2]  <= {1'b0};
                   
         if (I_comp_1) begin
            exp_n_dat_o[3]  <= I_comp_1; 
            count0          <= hold_time; 
         end 
         else if ($signed(count0) > 0) 
             count0 <= $signed(count0) - 1; 
         else if (($signed(count0) == 0) && (!I_comp_1))
             exp_n_dat_o[3]  <= {1'b0};  
                  
         if (Q_comp_2) begin
            exp_n_dat_o[0]  <= Q_comp_2;   
            count1          <= hold_time;
         end
         else if ($signed(count1) > 0) 
            count1 <= $signed(count1) - 1; 
         else if (($signed(count1) == 0) && (!Q_comp_2)) 
            exp_n_dat_o[0]  <= {1'b0}; 
         
         if (I_comp_2) begin
            exp_n_dat_o[1]  <= I_comp_2; 
            count2          <= hold_time; 
         end   
         else if ($signed(count2) > 0) 
            count2 <= $signed(count2) - 1;    
         else if (($signed(count2) == 0) && (!I_comp_2))
            exp_n_dat_o[1]  <= {1'b0};                        
      end
   end
*/

////////////////////////////////////////////////////////////////////////////////
// MUX output signal for DACs
////////////////////////////////////////////////////////////////////////////////
logic signed    [ 14-1: 0] dac1_out;
logic signed    [ 14-1: 0] dac2_out;
logic           [  4-1: 0] dac1_mux;
logic           [  4-1: 0] dac2_mux;

 always@(posedge clk_i)
  case (dac1_mux)
  4'b0: dac1_out <= $signed(0);                          // off
  4'd1: dac1_out <= $signed(dds_o[16-1: 2]);             // NCO 1
  4'd2: dac1_out <= $signed(I_filtered[32-1-0: 18-0]);   // I filtered 1
  4'd3: dac1_out <= $signed(I_filtered_2[32-1-0: 18-0]); // I filtered 2  
  4'd4: dac1_out <= $signed(phase_1[16-1: 2]);           // Omega 1
  4'd5: dac1_out <= $signed(dat_a_i_mux);                // ADC 1 input with biquad filtered  
  endcase
 
 always@(posedge clk_i)
  case (dac2_mux)
  4'd0: dac2_out <= $signed(0);                          // off
  4'd1: dac2_out <= $signed(dds_o_2[16-1: 2]);           // NCO 2
  4'd2: dac2_out <= $signed(Q_filtered[32-1-0: 18-0]);   // Q filtered 1
  4'd3: dac2_out <= $signed(Q_filtered_2[32-1-0: 18-0]); // Q filtered 2  
  4'd4: dac2_out <= $signed(phase_2[16-1: 2]);           // Omega 2
  4'd5: dac2_out <= $signed(dat_b_i_mux);                // ADC 2 input with biquad filtered
  endcase
   
////////////////////////////////////////////////////////////////////////////////
// MUX output signal for record
////////////////////////////////////////////////////////////////////////////////

 logic [ 14-1: 0] record1_out;
 logic [ 14-1: 0] record2_out;
 logic [ 4-1 : 0] record1_sel;
 logic [ 4-1 : 0] record2_sel;
 
 always@(posedge clk_i)
  case (record1_sel)
    3'b000: record1_out <= $signed(dds_o         [16-1:  2]);
    3'b001: record1_out <= $signed(I_filtered    [32-1: 18]); 
    3'b010: record1_out <= $signed(I_filtered_2  [32-1: 18]);
    3'b011: record1_out <= $signed(Q_filtered    [32-1: 18]);
    3'b100: record1_out <= $signed(Q_filtered_ddt[32-1: 18]);                       // nur fuer tests...
    3'b101: record1_out <= $signed(PHASE_UNWRAPPER_phase_fullscale_i[32-1: 18]);    // nur fuer tests...
//    3'b100: record1_out <= $signed(phase_1       [16-1:  2]);
//    3'b101: record1_out <= $signed(dat_a_i_mux);      
    3'b110: record1_out <= $signed(magnitude_1   [16-1:  2]);
    3'b111: record1_out <= 0;    

  endcase
 
 always@(posedge clk_i)
  case (record2_sel)
    3'b000: record2_out <= $signed(dds_o_2       [16-1:  2]);
    3'b001: record2_out <= $signed(Q_filtered    [32-1: 18]); 
    3'b010: record2_out <= $signed(Q_filtered_2  [32-1: 18]);
    3'b011: record2_out <= $signed(I_filtered_2  [32-1: 18]);
    3'b100: record2_out <= $signed(phase_2       [16-1:  2]);
    3'b101: record2_out <= $signed(dat_b_i_mux);
    3'b110: record2_out <= $signed(magnitude_2   [16-1:  2]);
    3'b111: record2_out <= 0;     
  endcase   

assign record_a_o = $signed(record1_out);                       // Daten landen immer an Adresse 0x2_0000, wird in scope.v ausgewaehlt
assign record_b_o = $signed(record2_out);                       // Daten landen immer an Adresse 0x2_0000, wird in scope.v ausgewaehlt

assign record_c_o = $signed(I_filtered_lowp_a[28-1: 14]);       // Daten landen immer an Adresse 0x3_0000
assign record_d_o = $signed(Q_filtered_lowp_a[28-1: 14]);       // Daten landen immer an Adresse 0x4_0000
assign record_e_o = $signed(I_filtered_lowp_b[28-1: 14]);       // Daten landen immer an Adresse 0x3_0000
assign record_f_o = $signed(Q_filtered_lowp_b[28-1: 14]);       // Daten landen immer an Adresse 0x4_0000


logic [4-1: 0]     int_reset_total;
assign int_rst_2_total   = int_reset_total[2];
assign int_rst_2_total_2 = int_reset_total[0];

//---------------------------------------------------------------------------------
//  Sum and saturation

logic signed [ 15-1: 0] out_1_sum   ;
logic signed [ 14-1: 0] out_1_sat   ;
logic signed [ 15-1: 0] out_2_sum   ;
logic signed [ 14-1: 0] out_2_sat   ;

always @(posedge clk_i) begin
   if (rstn_i == 1'b0) begin
      out_1_sat <= 14'd0 ;
      out_2_sat <= 14'd0 ;
   end
   else begin
      if (out_1_sum[15-1:15-2]==2'b01) // postitive sat
         out_1_sat <= 14'h1FFF ;
      else if (out_1_sum[15-1:15-2]==2'b10) // negative sat
         out_1_sat <= 14'h2000 ;
      else
         out_1_sat <= $signed(out_1_sum[14-1:0]) ;

      if (out_2_sum[15-1:15-2]==2'b01) // postitive sat
         out_2_sat <= 14'h1FFF ;
      else if (out_2_sum[15-1:15-2]==2'b10) // negative sat
         out_2_sat <= 14'h2000 ;
      else
         out_2_sat <= $signed(out_2_sum[14-1:0]) ;
   end
end

// for iTracker operation...
assign out_1_sum = $signed(dac1_out);
assign out_2_sum = $signed(dac2_out);

// for DPLL operation...
//always @(posedge clk_i) begin
//    case(sign_cha)
//    1'b0:    out_1_sum <=    $signed(pi_2_out[48-1: 34]) + $signed(offset_cha);
//    1'b1:    out_1_sum <=  -($signed(pi_2_out[48-1: 34]) + $signed(offset_cha));
//    endcase   
//end
//always @(posedge clk_i) begin
//    case(sign_chb)
//    1'b0:    out_2_sum <=    $signed(pi_2_out_2[48-1: 34]) + $signed(offset_chb);
//    1'b1:    out_2_sum <=  -($signed(pi_2_out_2[48-1: 34]) + $signed(offset_chb));
//    endcase   
//end

assign dat_a_o = $signed(out_1_sat) ;   // DAC 1 output
assign dat_b_o = $signed(out_2_sat) ;   // DAC 2 output
assign dat_c_o = dds_pinc  [48-1: 0];   // compute the frequency ch1 -> avg modul input
assign dat_d_o = dds_pinc_2[48-1: 0];   // compute the frequency ch2 -> avg modul input
assign dat_g_o = exp_n_dat_o;

//-------------------------------------------------------------------------
//  calculate the frequency to display the actual value in the GUI

logic   [74-1: 0]   dds_pinc_avg_sum;
logic   [74-1: 0]   dds_pinc_2_avg_sum;
logic   [48-1: 0]   dds_pinc_avg;
logic   [48-1: 0]   dds_pinc_2_avg;
logic   [32-1: 0]   cnt_avg;

always @(posedge clk_i) begin
    // ~ 0,64s
    if(cnt_avg < 67108864)begin
        dds_pinc_avg_sum    <= dds_pinc_avg_sum + dds_pinc[48-1: 0];
        dds_pinc_2_avg_sum  <= dds_pinc_2_avg_sum + dds_pinc_2[48-1: 0];
        cnt_avg <= cnt_avg + 1;
    end else begin
        dds_pinc_avg        <= dds_pinc_avg_sum >> 26;
        dds_pinc_2_avg      <= dds_pinc_2_avg_sum >> 26;
        dds_pinc_avg_sum    <= 0;
        dds_pinc_2_avg_sum  <= 0;
        cnt_avg             <= 0;
    end
end

//---------------------------------------------------------------------------------
//
//  System bus connection
logic             set_1_irst  ;

always @(posedge clk_i) begin
   if (rstn_i == 1'b0) begin
      adc_a_input_mux <=  1'd1 ;        // ADC select direct
      adc_b_input_mux <=  1'd1 ;        // ADC select direct
      set_2_irst    <=  1'b1 ;
      set_2_irst_2  <=  1'b1 ;
      set_2_sp      <= 32'd0 ;
      set_2_kp      <= 32'd0 ;
      set_2_ki      <= 32'd0 ;
      set_2_kp_phi  <= 32'd0 ;
      set_2_ki_phi  <= 32'd0 ;
      dds_dac1_en   <=  1'b0 ;
      dds_dac2_en   <=  1'b0 ;
      phase_dac1_en <=  1'b0 ;
      ampl_dac2_en  <=  1'b0 ;
      offset_cha    <= 14'd0 ;
      offset_chb    <= 14'd0 ;
      I_thld        <= 32'd0 ;
      Q_thld        <= 32'd0 ;
      phase_thld    <= 16'd12500;
      phase_thld_2  <= 16'd12500;      
      ampl_thld     <= 32'd500 ;
      ampl_thld_2   <= 32'd500 ;
//      dat_a_i_offset <= 14'd0;
//      dat_b_i_offset <= 14'd0;

   end
   else begin
      if (sys_wen) begin
         if (sys_addr[19:0]==16'h0)    {dacs_en, ampl_dac2_en, phase_dac1_en, dds_dac2_en, dds_dac1_en, set_2_irst, set_1_irst} <= sys_wdata[ 7-1:0] ; 
         if (sys_addr[19:0]==16'h04)    int_reset_total <= sys_wdata[4-1: 0] ;
         if (sys_addr[19:0]==16'h08)    adc_a_input_mux <= sys_wdata[1-1: 0] ;
         if (sys_addr[19:0]==16'h0C)    adc_b_input_mux <= sys_wdata[1-1: 0] ;
         if (sys_addr[19:0]==16'h10)    dac1_mux        <= sys_wdata[4-1: 0] ;
         if (sys_addr[19:0]==16'h14)    dac2_mux        <= sys_wdata[4-1: 0] ;
         if (sys_addr[19:0]==16'h18)    record1_sel     <= sys_wdata[4-1: 0] ;
         if (sys_addr[19:0]==16'h1C)    record2_sel     <= sys_wdata[4-1: 0] ;         
         if (sys_addr[19:0]==16'h100)   dds_ftw_high    <= sys_wdata[32-1:0] ;
         if (sys_addr[19:0]==16'h104)   dds_ftw_low     <= sys_wdata[32-1:0] ;
//         if (sys_addr[19:0]==16'h110)   dat_a_i_offset  <= sys_wdata[14-1:0] ;
         
         if (sys_addr[19:0]==16'h20)    set_2_sp        <= sys_wdata[32-1:0] ;
         if (sys_addr[19:0]==16'h24)    set_2_kp        <= sys_wdata[32-1:0] ;
         if (sys_addr[19:0]==16'h28)    set_2_ki        <= sys_wdata[32-1:0] ;
         if (sys_addr[19:0]==16'h124)   set_2_kp_phi    <= sys_wdata[32-1:0] ;
         if (sys_addr[19:0]==16'h128)   set_2_ki_phi    <= sys_wdata[32-1:0] ;
         if (sys_addr[19:0]==16'h200)   dds_ftw_high_2  <= sys_wdata[32-1:0] ;
         if (sys_addr[19:0]==16'h204)   dds_ftw_low_2   <= sys_wdata[32-1:0] ;
//         if (sys_addr[19:0]==16'h210)   dat_b_i_offset  <= sys_wdata[14-1:0] ;
         
         if (sys_addr[19:0]==16'h220)    set_2_sp_2        <= sys_wdata[32-1:0] ;
         if (sys_addr[19:0]==16'h224)    set_2_kp_2        <= sys_wdata[32-1:0] ;
         if (sys_addr[19:0]==16'h228)    set_2_ki_2        <= sys_wdata[32-1:0] ;
         
         if (sys_addr[19:0]==16'h30)    I_thld           <= sys_wdata[32-1:0] ;
         if (sys_addr[19:0]==16'h34)    Q_thld           <= sys_wdata[32-1:0] ;
         if (sys_addr[19:0]==16'h38)    phase_thld       <= sys_wdata[32-1:0] ;
         if (sys_addr[19:0]==16'h3C)    ampl_thld        <= sys_wdata[32-1:0] ;         
          
         if (sys_addr[19:0]==16'h230)    I_thld_2           <= sys_wdata[32-1:0] ;
         if (sys_addr[19:0]==16'h234)    Q_thld_2           <= sys_wdata[32-1:0] ;
         if (sys_addr[19:0]==16'h238)    phase_thld_2       <= sys_wdata[32-1:0] ;         
         if (sys_addr[19:0]==16'h23C)    ampl_thld_2        <= sys_wdata[32-1:0] ;         
         
         if (sys_addr[19:0]==16'h1000)    offset_cha       <= sys_wdata[14-1:0] ;
         if (sys_addr[19:0]==16'h1004)    offset_chb       <= sys_wdata[14-1:0] ;
         if (sys_addr[19:0]==16'h1010)    sign_cha         <= sys_wdata[ 1-1:0] ;
         if (sys_addr[19:0]==16'h1014)    sign_chb         <= sys_wdata[ 1-1:0] ;

//    ############ Filter  coefficients  ############################################################# 
          if (sys_addr[19:0]==20'h1040)  modeReset_a <= sys_wdata[1-1: 0] ;
          if (sys_addr[19:0]==20'h1044)  IIR1NEGa1 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h1048)  IIR1NEGa2 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h104C)  IIR1b0 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h1050)  IIR1b1 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h1054)  IIR1b2 <= sys_wdata[18-1: 0] ;
          
          if (sys_addr[19:0]==20'h1064)  IIR2NEGa1 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h1068)  IIR2NEGa2 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h106C)  IIR2b0 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h1070)  IIR2b1 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h1074)  IIR2b2 <= sys_wdata[18-1: 0] ;
    
          if (sys_addr[19:0]==20'h1084)  IIR3NEGa1 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h1088)  IIR3NEGa2 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h108C)  IIR3b0 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h1090)  IIR3b1 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h1094)  IIR3b2 <= sys_wdata[18-1: 0] ;
          
          if (sys_addr[19:0]==20'h10A4)  IIR4NEGa1 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h10A8)  IIR4NEGa2 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h10AC)  IIR4b0 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h10B0)  IIR4b1 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h10B4)  IIR4b2 <= sys_wdata[18-1: 0] ;       
            
          if (sys_addr[19:0]==20'h10C4)  IIR5NEGa1 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h10C8)  IIR5NEGa2 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h10CC)  IIR5b0 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h10D0)  IIR5b1 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h10D4)  IIR5b2 <= sys_wdata[18-1: 0] ;
          
          if (sys_addr[19:0]==20'h10E4)  IIR6NEGa1 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h10E8)  IIR6NEGa2 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h10EC)  IIR6b0 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h10F0)  IIR6b1 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h10F4)  IIR6b2 <= sys_wdata[18-1: 0] ;

          if (sys_addr[19:0]==20'h2040)  modeReset_b <= sys_wdata[1-1: 0] ;          
          
          if (sys_addr[19:0]==20'h2044)  IIR7NEGa1 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h2048)  IIR7NEGa2 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h204C)  IIR7b0 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h2050)  IIR7b1 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h2054)  IIR7b2 <= sys_wdata[18-1: 0] ;
          
          if (sys_addr[19:0]==20'h2064)  IIR8NEGa1 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h2068)  IIR8NEGa2 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h206C)  IIR8b0 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h2070)  IIR8b1 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h2074)  IIR8b2 <= sys_wdata[18-1: 0] ;
    
          if (sys_addr[19:0]==20'h2084)  IIR9NEGa1 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h2088)  IIR9NEGa2 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h208C)  IIR9b0 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h2090)  IIR9b1 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h2094)  IIR9b2 <= sys_wdata[18-1: 0] ;
          
          if (sys_addr[19:0]==20'h20A4)  IIR10NEGa1 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h20A8)  IIR10NEGa2 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h20AC)  IIR10b0 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h20B0)  IIR10b1 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h20B4)  IIR10b2 <= sys_wdata[18-1: 0] ;       
            
          if (sys_addr[19:0]==20'h20C4)  IIR11NEGa1 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h20C8)  IIR11NEGa2 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h20CC)  IIR11b0 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h20D0)  IIR11b1 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h20D4)  IIR11b2 <= sys_wdata[18-1: 0] ;
          
          if (sys_addr[19:0]==20'h20E4)  IIR12NEGa1 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h20E8)  IIR12NEGa2 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h20EC)  IIR12b0 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h20F0)  IIR12b1 <= sys_wdata[18-1: 0] ;
          if (sys_addr[19:0]==20'h20F4)  IIR12b2 <= sys_wdata[18-1: 0] ;

          if (sys_addr[19:0]==20'h3000)  filter_select_a <= sys_wdata[ 4-1: 0] ;                        // filter select BW IQ show
          if (sys_addr[19:0]==20'h3004)  filter_select_b <= sys_wdata[ 4-1: 0] ;                        // filter select BW IQ show
//        if (sys_addr[19:0]==20'h3010)  set_phase_unwrapped_zero_trigger_o <= sys_wdata[ 1-1: 0] ;     // unwrapper set to zero     
                                                                                                        // ist mit int reset verbunden           
       end
   end
end

wire sys_en;
assign sys_en = sys_wen | sys_ren;

always @(posedge clk_i)
if (rstn_i == 1'b0) begin
   sys_err <= 1'b0 ;
   sys_ack <= 1'b0 ;
end else begin
   sys_err <= 1'b0 ;

   casez (sys_addr[19:0])

      20'h00 : begin sys_ack <= sys_en;          sys_rdata <= {{32-7{1'b0}}, dacs_en, ampl_dac2_en, phase_dac1_en, dds_dac2_en, dds_dac1_en, set_2_irst, set_1_irst}       ; end 
      20'h20 : begin sys_ack <= sys_en;          sys_rdata <= {set_2_sp}           ; end 
      20'h24 : begin sys_ack <= sys_en;          sys_rdata <= {set_2_kp}           ; end 
      20'h28 : begin sys_ack <= sys_en;          sys_rdata <= {set_2_ki}           ; end 
      20'h124: begin sys_ack <= sys_en;          sys_rdata <= {set_2_kp_phi}       ; end 
      20'h128: begin sys_ack <= sys_en;          sys_rdata <= {set_2_ki_phi}       ; end 

      20'h220 : begin sys_ack <= sys_en;          sys_rdata <= {set_2_sp_2}        ; end 
      20'h224 : begin sys_ack <= sys_en;          sys_rdata <= {set_2_kp_2}        ; end 
      20'h228 : begin sys_ack <= sys_en;          sys_rdata <= {set_2_ki_2}        ; end 
//      20'h324: begin sys_ack <= sys_en;          sys_rdata <= {set_2_kp_phi_2}   ; end 
//      20'h328: begin sys_ack <= sys_en;          sys_rdata <= {set_2_ki_phi_2}   ; end 
      
      20'h30 : begin sys_ack <= sys_en;          sys_rdata <= {I_thld   }          ; end 
      20'h34 : begin sys_ack <= sys_en;          sys_rdata <= {Q_thld   }          ; end 
      20'h38 : begin sys_ack <= sys_en;          sys_rdata <= {phase_thld}         ; end 
      
      20'h230 : begin sys_ack <= sys_en;          sys_rdata <= {I_thld_2   }       ; end 
      20'h234 : begin sys_ack <= sys_en;          sys_rdata <= {Q_thld_2   }       ; end 
      20'h238 : begin sys_ack <= sys_en;          sys_rdata <= {phase_thld_2}      ; end 
             
      20'h40 : begin sys_ack <= sys_en;          sys_rdata <= {I_comp_1, Q_comp_1, I_comp_2, Q_comp_2}   ; end    // if I or Q cycle flag is on
      20'h4C : begin sys_ack <= sys_en;          sys_rdata <= {exp_n_dat_o}        ; end  // cycle_slip_flags
      
      20'h50 : begin sys_ack <= sys_en;          sys_rdata <= {dds_pinc_avg  [48-1:   32]}   ; end  // current pinc value high
      20'h54 : begin sys_ack <= sys_en;          sys_rdata <= {dds_pinc_avg  [31  :    0]}   ; end  // current pinc value low
      20'h58 : begin sys_ack <= sys_en;          sys_rdata <= {dds_pinc_2_avg[48-1:   32]}   ; end  // current pinc 2 value high
      20'h5C : begin sys_ack <= sys_en;          sys_rdata <= {dds_pinc_2_avg[31  :    0]}   ; end  // current pinc 2 value low

//      20'h110 : begin sys_ack <= sys_en;          sys_rdata <= {dat_a_i}                    ; end  // current ADC value
//      20'h210 : begin sys_ack <= sys_en;          sys_rdata <= {dat_b_i}                    ; end  // current ADC value

//      20'h60 : begin sys_ack <= sys_en;          sys_rdata <= {I_filtered}              ; end  // current I value
//      20'h64 : begin sys_ack <= sys_en;          sys_rdata <= {Q_filtered}              ; end  // current Q value
//      20'h68 : begin sys_ack <= sys_en;          sys_rdata <= {I_filtered_2}            ; end  // current I value
//      20'h6C : begin sys_ack <= sys_en;          sys_rdata <= {Q_filtered_2}            ; end  // current Q value     
      
      20'h74 : begin sys_ack <= sys_en;          sys_rdata <= {pi_2_out  [48-1: 16]}    ; end  // current PI value
      20'h7C : begin sys_ack <= sys_en;          sys_rdata <= {pi_2_out_2[48-1: 16]}    ; end  // current PI value  
      
      20'h400: begin sys_ack <= sys_en;          sys_rdata <= {cnt_I_comp_1_prev}       ; end  //  
      20'h404: begin sys_ack <= sys_en;          sys_rdata <= {cnt_Q_comp_1_prev}       ; end  //  
      20'h408: begin sys_ack <= sys_en;          sys_rdata <= {cnt_I_comp_2_prev}       ; end  //  
      20'h40C: begin sys_ack <= sys_en;          sys_rdata <= {cnt_Q_comp_2_prev}       ; end  //  
      20'h418: begin sys_ack <= sys_en;          sys_rdata <= {phase_1}                 ; end  //  
      20'h41C: begin sys_ack <= sys_en;          sys_rdata <= {phase_2}                 ; end  //  
      20'h420: begin sys_ack <= sys_en;          sys_rdata <= {cnt_cycle_slip_1_prev}   ; end  //  
      20'h424: begin sys_ack <= sys_en;          sys_rdata <= {cnt_cycle_slip_2_prev}   ; end  //  
      
      20'h500: begin sys_ack <= sys_en;          sys_rdata <= {cnt_Omega_comp_1_prev_s}     ; end  //  
      20'h504: begin sys_ack <= sys_en;          sys_rdata <= {cnt_Omega_comp_2_prev_s}     ; end  //  
      20'h510: begin sys_ack <= sys_en;          sys_rdata <= {cnt_Omega_comp_1_prev_min}   ; end  //  
      20'h514: begin sys_ack <= sys_en;          sys_rdata <= {cnt_Omega_comp_2_prev_min}   ; end  //  
      20'h520: begin sys_ack <= sys_en;          sys_rdata <= {dac1_mux[4-1: 0]}            ; end  //  
      20'h524: begin sys_ack <= sys_en;          sys_rdata <= {dac2_mux[4-1: 0]}            ; end  //  
      20'h530: begin sys_ack <= sys_en;          sys_rdata <= {record1_sel[4-1: 0]}         ; end  //  
      20'h534: begin sys_ack <= sys_en;          sys_rdata <= {record2_sel[4-1: 0]}         ; end  //  
      20'h540: begin sys_ack <= sys_en;          sys_rdata <= {adc_a_input_mux[1-1: 0]}     ; end  //  
      20'h544: begin sys_ack <= sys_en;          sys_rdata <= {adc_b_input_mux[1-1: 0]}     ; end  //  
      20'h550: begin sys_ack <= sys_en;          sys_rdata <= {filter_select_a[4-1: 0]}     ; end  //  
      20'h554: begin sys_ack <= sys_en;          sys_rdata <= {filter_select_b[4-1: 0]}     ; end  //  
      20'h560: begin sys_ack <= sys_en;          sys_rdata <= {phase_thld  [16-1: 0]}       ; end  //  
      20'h564: begin sys_ack <= sys_en;          sys_rdata <= {phase_thld_2[16-1: 0]}       ; end  //   
      20'h570: begin sys_ack <= sys_en;          sys_rdata <= {ampl_thld  [32-1: 0]}        ; end  //  
      20'h574: begin sys_ack <= sys_en;          sys_rdata <= {ampl_thld_2[32-1: 0]}        ; end  //   
      20'h600: begin sys_ack <= sys_en;          sys_rdata <= {PHASE_UNWRAPPER_phase_saturated_i} ; end  //  
      20'h604: begin sys_ack <= sys_en;          sys_rdata <= {PHASE_UNWRAPPER_phase_fullscale_i} ; end  //   
      
            
     default : begin sys_ack <= sys_en;          sys_rdata <=  32'h0                              ; end
   endcase
end

endmodule
