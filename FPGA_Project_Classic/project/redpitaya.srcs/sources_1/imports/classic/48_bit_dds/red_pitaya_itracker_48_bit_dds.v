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
   parameter DWE = 8 // data width for extension connector
)(   
   // signals
   input                 clk_i           ,  //!< processing clock
   input                 rstn_i          ,  //!< processing reset - active low
   input      [ 14-1: 0] dat_a_i         ,  //!< input data CHA
   input      [ 14-1: 0] dat_b_i         ,  //!< input data CHB
   output     [ 14-1: 0] dat_a_o         ,  //!< output data CHA        DAC 1
   output     [ 14-1: 0] dat_b_o         ,  //!< output data CHB        DAC 2
   output     [ 48-1: 0] dat_c_o         ,  //!< output data CHC
   output     [ 48-1: 0] dat_d_o         ,  //!< output data CHD
   output     [ 32-1: 0] dat_g_o         ,  //!< output data CHG
   
   // Expansion connector
   input      [DWE-1:0] exp_n_dat_i,  // exp. con. input data
   output reg [DWE-1:0] exp_n_dat_o,  // exp. con. output data
   output reg [DWE-1:0] exp_n_dir_o,  // exp. con. 1-output enable
  
   // system bus
   input      [ 32-1: 0] sys_addr        ,  //!< bus address
   input      [ 32-1: 0] sys_wdata       ,  //!< bus write data
   input                 sys_wen         ,  //!< bus write enable
   input                 sys_ren         ,  //!< bus read enable
   output reg [ 32-1: 0] sys_rdata       ,  //!< bus read data
   output reg            sys_err         ,  //!< bus error indicator
   output reg            sys_ack            //!< bus acknowledge signal
);

localparam  PSR = 32         ;
localparam  ISR = 32         ;

reg  [ 32-1: 0] dds_pinc_init       ;  // phase increment initial value
reg  [ 32-1: 0] dds_pinc_init_2     ;  // phase increment initial value
wire            dds_pinc_init_en    ;
wire            dds_pinc_init_en_2  ;
wire [ 48-1: 0] pi_1_out            ;
wire [ 48-1: 0] pi_2_out            ;
wire [ 48-1: 0] pi_1_out_2            ;
wire [ 48-1: 0] pi_2_out_2            ;

reg  [ 32-1: 0] I_thld              ;  // I_threshold 
reg  [ 32-1: 0] Q_thld              ;  // Q_threshold 
reg  [ 32-1: 0] phase_thld          ;  // phase_threshold
reg  [ 32-1: 0] ampl_thld           ;  // ampl_threshold
wire            cycle_slip_flag1    ; // flag that is set, if I or Q out of threshold bounds
wire            cycle_slip_flag2    ; // flag that is set, if phase or amplitude out of threshold bounds

reg  [ 14-1: 0] offset_cha          ; // Offset channel A 
reg  [ 14-1: 0] offset_chb          ; // Offset channel B
reg  [ 32-1: 0] cycle_slip_limit    ; // limit that cycle_slip_det is compared to
wire            cycle_slip_flag     ; // flag that is set, if phase slips a cycle
wire            cycle_slip_flag_pos ; // flag set if cycle slip occurs with f_dat_i < f_DDS
wire            cycle_slip_flag_neg ; // flag set if cycle slip occurs with f_dat_i > f_DDS
wire            omega_limit         ; // flag set if omega > limit || omega < -limit  

reg  [  3-1: 0] flag_hold           ; // saves cycle slip high status for 125 cycles 
reg             dds_dac1_en         ;
reg             dds_dac2_en         ;
reg             phase_dac1_en       ;
reg             ampl_dac2_en        ;


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
// Latency: 7

wire [32-1: 0] dds_o;       // dds output: [31 : 16] sin, [15 : 0] cos
wire [48-1: 0] dds_pinc;    // phase increment
wire           dds_tvalid;

dds_compiler_0 i_dds(
  .aclk(clk_i),                                    // input wire aclk
  .s_axis_phase_tvalid(rstn_i),                    // input wire s_axis_phase_tvalid
  .s_axis_phase_tdata(dds_pinc),                   // input wire [31 : 0] s_axis_phase_tdata
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
// Latency: 7

wire [32-1: 0] dds_o_2;       // dds output: [31 : 16] sin, [15 : 0] cos
wire [48-1: 0] dds_pinc_2;    // phase increment
wire           dds_tvalid_2;

dds_compiler_0 i_dds_2(
  .aclk(clk_i),                                    // input wire aclk
  .s_axis_phase_tvalid(rstn_i),                    // input wire s_axis_phase_tvalid
  .s_axis_phase_tdata(dds_pinc_2),                   // input wire [31 : 0] s_axis_phase_tdata
  .m_axis_data_tvalid(dds_tvalid_2),                 // output wire m_axis_data_tvalid
  .m_axis_data_tdata(dds_o_2)                        // output wire [31 : 0] m_axis_data_tdata
);





////////////////////////////////////////////////////////////////////////////////
// Inphase component (cos)
////////////////////////////////////////////////////////////////////////////////
// A operand width: 14 bit
// B operand width: 16 bit
// Output width: 30 bit 

wire [30-1: 0]  I_unfiltered;   
assign I_unfiltered = ( $signed(dat_a_i) + $signed(offset_cha)) * $signed(dds_o[15: 0]);

////////////////////////////////////////////////////////////////////////////////
// Quadrature component (sin)
////////////////////////////////////////////////////////////////////////////////

wire [30-1: 0]  Q_unfiltered;   
assign Q_unfiltered = ( $signed(dat_a_i) + $signed(offset_cha)) * $signed(dds_o[31: 16]);


////////////////////////////////////////////////////////////////////////////////
// Inphase component (cos) 2
////////////////////////////////////////////////////////////////////////////////
// A operand width: 14 bit
// B operand width: 16 bit
// Output width: 30 bit 

wire [30-1: 0]  I_unfiltered_2;   
assign I_unfiltered_2 = ( $signed(dat_b_i) + $signed(offset_chb)) * $signed(dds_o_2[15: 0]);

////////////////////////////////////////////////////////////////////////////////
// Quadrature component (sin) 2
////////////////////////////////////////////////////////////////////////////////

wire [30-1: 0]  Q_unfiltered_2;   
assign Q_unfiltered_2 = ( $signed(dat_b_i) + $signed(offset_chb)) * $signed(dds_o_2[31: 16]);



////////////////////////////////////////////////////////////////////////////////
// CIC filter (IP core): Inphase component (cos)
////////////////////////////////////////////////////////////////////////////////
// 5 MHz LPF - Decimate 8 CIC
// Clock frequency = Input Sampling Frequency: 125 MHz
// Input data width: 30 bit
// Output width: 32 bit 
// DSP48 Slices: 4
// Cycle Latency: 15

wire [32-1: 0]  I_filtered;                             // fir_I output
wire            I_filtered_tvalid;

cic_compiler_0 i_cic_I (
  .aclk(clk_i),                                         // input wire aclk
  .s_axis_data_tvalid(dds_tvalid),                      // input wire s_axis_data_tvalid
  .s_axis_data_tdata($signed(I_unfiltered)),            // input wire [31 : 0] s_axis_data_tdata
  .m_axis_data_tvalid(I_filtered_tvalid),               // output wire m_axis_data_tvalid
  .m_axis_data_tdata(I_filtered)                        // output wire [31 : 0] m_axis_data_tdata
);

////////////////////////////////////////////////////////////////////////////////
// CIC filter (IP core): Quadrature component (sin)
////////////////////////////////////////////////////////////////////////////////

wire [32-1: 0]  Q_filtered;                             // fir_Q output
wire            Q_filtered_tvalid;

cic_compiler_0 i_cic_Q (
  .aclk(clk_i),                                         // input wire aclk
  .s_axis_data_tvalid(dds_tvalid),                      // input wire s_axis_data_tvalid
  .s_axis_data_tdata($signed(Q_unfiltered)),            // input wire [31 : 0] s_axis_data_tdata
  .m_axis_data_tvalid(Q_filtered_tvalid),               // output wire m_axis_data_tvalid
  .m_axis_data_tdata(Q_filtered)                        // output wire [31 : 0] m_axis_data_tdata
);


////////////////////////////////////////////////////////////////////////////////
// CIC filter (IP core): Inphase component (cos) 2
////////////////////////////////////////////////////////////////////////////////
// 5 MHz LPF - Decimate 8 CIC
// Clock frequency = Input Sampling Frequency: 125 MHz
// Input data width: 30 bit
// Output width: 32 bit 
// DSP48 Slices: 4
// Cycle Latency: 15

wire [32-1: 0]  I_filtered_2;                             // fir_I output
wire            I_filtered_tvalid_2;
/*
cic_compiler_0 i_cic_I_2 (
  .aclk(clk_i),                                         // input wire aclk
  .s_axis_data_tvalid(dds_tvalid),                      // input wire s_axis_data_tvalid
  //.s_axis_data_tready(s_axis_data_tready),            // output wire s_axis_data_tready
  .s_axis_data_tdata($signed(I_unfiltered_2)),            // input wire [31 : 0] s_axis_data_tdata
  .m_axis_data_tvalid(I_filtered_tvalid_2),               // output wire m_axis_data_tvalid
  .m_axis_data_tdata(I_filtered_2)                        // output wire [31 : 0] m_axis_data_tdata
);
*/
////////////////////////////////////////////////////////////////////////////////
// CIC filter (IP core): Quadrature component (sin) 2
////////////////////////////////////////////////////////////////////////////////

wire [32-1: 0]  Q_filtered_2;                             // fir_Q output
wire            Q_filtered_tvalid_2;
/*
cic_compiler_0 i_cic_Q_2 (
  .aclk(clk_i),                                         // input wire aclk
  .s_axis_data_tvalid(dds_tvalid),                      // input wire s_axis_data_tvalid
  //.s_axis_data_tready(s_axis_data_tready),            // output wire s_axis_data_tready
  .s_axis_data_tdata($signed(Q_unfiltered_2)),            // input wire [31 : 0] s_axis_data_tdata
  .m_axis_data_tvalid(Q_filtered_tvalid_2),               // output wire m_axis_data_tvalid
  .m_axis_data_tdata(Q_filtered_2)                        // output wire [31 : 0] m_axis_data_tdata
);
*/

////////////////////////////////////////////////////////////////////////////////
// CORDIC_0 (IP-core): arc tan (Q/I) = phase 1
////////////////////////////////////////////////////////////////////////////////
// Functional Selection: Arc Tan
//      When the ArcTan functional configuration is selected, the input vector (X_IN,Y_IN) is rotated
//      (using the CORDIC algorithm) until the Y component is zero. This generates the output
//      angle, Atan(Y_IN/X_IN).
//    Signal      Range                   Description
//      X_IN        -1 <= X_IN <=1          Input X Coordinate
//      Y_IN        -1 <= Y_IN <=1          Input Y Coordinate
//      PHASE_OUT   -Pi <= PHASE_OUT <= Pi  Output Angle
// Data Format: SignedFraction
//      The input vector (X_IN, Y_IN) is expressed as a pair of fixed-point twos complement
//      numbers with an integer width of 2 bits (1QN format). The output angle, Pout radians, is
//      expressed as a fixed-point twos complement number with an integer width of 3 bits (2QN
//      format).
// Phase Format: Radians
// Input/Output width: 32 bit
// Latency: 36


wire [32-1: 0]  phase;                                                  // Cordic arctan output
wire            phase_tvalid;

cordic_0 i_cordic_arctan (
  .aclk(clk_i),                                                         // input wire aclk
//.s_axis_cartesian_tvalid(I_filtered_tvalid && Q_filtered_tvalid),     // input wire s_axis_cartesian_tvalid           // Julia
  .s_axis_cartesian_tvalid(1'b1),     // input wire s_axis_cartesian_tvalid                                             // Mattias  
  .s_axis_cartesian_tdata({$signed(Q_filtered),$signed(I_filtered)}),   // input wire [63 : 0] s_axis_cartesian_tdata: IMAG(63:32), REAL(31:0)
  .m_axis_dout_tvalid(phase_tvalid),                                    // output wire m_axis_dout_tvalid
  .m_axis_dout_tdata(phase)                                             // output wire [31 : 0] m_axis_dout_tdata: PHASE(32:0)
);


////////////////////////////////////////////////////////////////////////////////
// CORDIC_0 (IP-core): arc tan (Q/I) = phase 2
////////////////////////////////////////////////////////////////////////////////
// Functional Selection: Arc Tan
//      When the ArcTan functional configuration is selected, the input vector (X_IN,Y_IN) is rotated
//      (using the CORDIC algorithm) until the Y component is zero. This generates the output
//      angle, Atan(Y_IN/X_IN).
//    Signal      Range                   Description
//      X_IN        -1 <= X_IN <=1          Input X Coordinate
//      Y_IN        -1 <= Y_IN <=1          Input Y Coordinate
//      PHASE_OUT   -Pi <= PHASE_OUT <= Pi  Output Angle
// Data Format: SignedFraction
//      The input vector (X_IN, Y_IN) is expressed as a pair of fixed-point twos complement
//      numbers with an integer width of 2 bits (1QN format). The output angle, Pout radians, is
//      expressed as a fixed-point twos complement number with an integer width of 3 bits (2QN
//      format).
// Phase Format: Radians
// Input/Output width: 32 bit
// Latency: 36


wire [32-1: 0]  phase_2;                                                  // Cordic arctan output
wire            phase_tvalid_2;

cordic_0 i_cordic_arctan_2 (
  .aclk(clk_i),                                                         // input wire aclk
  .s_axis_cartesian_tvalid(I_filtered_tvalid_2 && Q_filtered_tvalid_2),     // input wire s_axis_cartesian_tvalid
  .s_axis_cartesian_tdata({$signed(Q_filtered_2),$signed(I_filtered_2)}),   // input wire [63 : 0] s_axis_cartesian_tdata: IMAG(63:32), REAL(31:0)
  .m_axis_dout_tvalid(phase_tvalid_2),                                    // output wire m_axis_dout_tvalid
  .m_axis_dout_tdata(phase_2)                                             // output wire [31 : 0] m_axis_dout_tdata: PHASE(32:0)
);



////////////////////////////////////////////////////////////////////////////////
// Inphase^2
////////////////////////////////////////////////////////////////////////////////
// use mult-IP-core here to save DSP slices (necessary because of operand size)
wire [64-1: 0]  I_2; 

mult_gen_1 mult_I_2 (
  .CLK(clk_i),                  // input wire CLK
  .A($signed(I_filtered)),      // input wire [31 : 0] A
  .B($signed(I_filtered)),      // input wire [31 : 0] B
  .P(I_2)                       // output wire [63 : 0] P
);

////////////////////////////////////////////////////////////////////////////////
// Quadrature^2
////////////////////////////////////////////////////////////////////////////////

wire [64-1: 0]  Q_2;        
                   
mult_gen_1 mult_Q_2 (
  .CLK(clk_i),                  // input wire CLK
  .A($signed(Q_filtered)),      // input wire [31 : 0] A
  .B($signed(Q_filtered)),      // input wire [31 : 0] B
  .P(Q_2)                       // output wire [63 : 0] P
);


////////////////////////////////////////////////////////////////////////////////
// CORDIC_1 (IP-core): square root (I² + Q²) = amplitude
////////////////////////////////////////////////////////////////////////////////
// Functional Selection: Square Root
//      When the square root functional configuration is selected, a simplified CORDIC algorithm is
//      used to calculate the positive square root of the input. The input, X_IN, and the output,
//      X_OUT, are always positive and are both expressed as either unsigned fractions or unsigned
//      integers.
//    Signal      Range (UnsignedInteger)                 Description
//      X_IN        0 <= X_IN < 2^(input_width)             Input X Value
//      X_OUT       0 <= X_OUT < 2^(int(input_width/2)+1)   Output Square Root
// Data Format: UnsignedInteger
//      The input, X_IN, is expressed as an unsigned integer. The output, X_OUT, is expressed as an
//      unsigned integer. 
// Phase Format: Radians
// Input width: 48 bit (= max.)
// Output width: 25 bit
// Latency: 25

wire [65-1: 0]  ampl_2;                         
assign ampl_2 = $signed(I_2) + $signed(Q_2);

wire [32-1: 0]  ampl;                                               // Cordic sqrt output (amplitude)
wire            ampl_tvalid;

cordic_1 i_cordic_sqrt (
  .aclk(clk_i),                                                     // input wire aclk
  .s_axis_cartesian_tvalid(I_filtered_tvalid && Q_filtered_tvalid), // input wire s_axis_cartesian_tvalid
  .s_axis_cartesian_tdata($signed(ampl_2[65-1:16])),                // input wire [47 : 0] s_axis_cartesian_tdata
  .m_axis_dout_tvalid(ampl_tvalid),                                 // output wire m_axis_dout_tvalid
  .m_axis_dout_tdata(ampl)                                          // output wire [31 : 0] m_axis_dout_tdata
);


////////////////////////////////////////////////////////////////////////////////
//  Calc differential phase = phase d/dt = angular velocity -> omega
////////////////////////////////////////////////////////////////////////////////
reg  [32-1: 0]  limit;
reg  [32-1: 0]  phase_old;
reg  [32-1: 0]  omega_old;
wire [32-1: 0]  omega_test;
reg  [32-1: 0]  omega;
wire            cycle_slip;
wire [33-1: 0]  omega2;
wire [33-1: 0]  cycle_slip2;
   
always @(posedge clk_i) begin
   if (rstn_i == 1'b0) begin
      phase_old  <= 32'h0;
      omega_old  <= 32'h0;
      omega      <= 32'h0;
      limit      <= 32'h3FFFFFFF; // <= 32'd1073741824;
   end
   else begin 
      if ( cycle_slip ) begin 
         omega      <= $signed(omega_old);  // skipp new value if phase changes from -pi to +pi (unwrap)
      end 
      else begin
         omega      <= $signed(omega_test);
         omega_old  <= $signed(omega);
      end
      phase_old  <= $signed(phase);
   end
end
      
assign omega_test = ( $signed(phase) - $signed(phase_old) ); 
assign cycle_slip = ( (phase[32-1] != phase_old[32-1]) && ( ($signed(phase) < $signed(-limit)) || ($signed(phase) > $signed(limit)) ) );


////////////////////////////////////////////////////////////////////////////////
//  Calc differential phase = phase d/dt = angular velocity -> omega 2
////////////////////////////////////////////////////////////////////////////////
reg  [32-1: 0]  limit_2;
reg  [32-1: 0]  phase_old_2;
reg  [32-1: 0]  omega_old_2;
wire [32-1: 0]  omega_test_2;
reg  [32-1: 0]  omega_2;
wire            cycle_slip_2;
wire [33-1: 0]  omega2_2;
wire [33-1: 0]  cycle_slip2_2;
   
always @(posedge clk_i) begin
   if (rstn_i == 1'b0) begin
      phase_old_2  <= 32'h0;
      omega_old_2  <= 32'h0;
      omega_2      <= 32'h0;
      limit_2      <= 32'h3FFFFFFF; // <= 32'd1073741824;
   end
   else begin 
      if ( cycle_slip_2 ) begin 
         omega_2      <= $signed(omega_old_2);  // skipp new value if phase changes from -pi to +pi (unwrap)
      end 
      else begin
         omega_2      <= $signed(omega_test_2);
         omega_old_2  <= $signed(omega_2);
      end
      phase_old_2  <= $signed(phase_2);
   end
end
      
assign omega_test_2 = ( $signed(phase_2) - $signed(phase_old_2) ); 
assign cycle_slip_2 = ( (phase_2[32-1] != phase_old_2[32-1]) && ( ($signed(phase_2) < $signed(-limit_2)) || ($signed(phase_2) > $signed(limit_2)) ) );



////////////////////////////////////////////////////////////////////////////////
// Cycle-slip detection 
////////////////////////////////////////////////////////////////////////////////
wire  [32-1: 0] omega_avg;
reg   [32-1: 0] omega_avg_old;
      
always @(posedge clk_i) begin
   if (rstn_i == 1'b0) begin 
      omega_avg_old   <= 32'h0;
   end
   else begin
      omega_avg_old <= $signed(omega_avg);
   end   
end

// calculate the adaptive estimation (IIR-filter) of the average value of omega and compare it to the limit value  
// omega_avg(k) = 0.25*omega(k) + 0.75*omega_avg(k-1)
assign omega_avg  = ($signed(omega[32-1: 2])) + ($signed(omega_avg_old[32-1: 1])) + ($signed(omega_avg_old[32-1: 2]));
assign omega_limit = ($signed(omega_avg) > $signed(cycle_slip_limit)) || ($signed(omega_avg) < $signed(-cycle_slip_limit));

assign omega2 = ( $signed(phase) - $signed(phase_old) );
assign cycle_slip2 = $signed(omega2) - $signed(omega_avg);
assign cycle_slip_flag_pos = ($signed(cycle_slip2) > $signed(limit)) ;  // flag set if cycle slip occurs with f_dat_i < f_DDS
assign cycle_slip_flag_neg = ($signed(cycle_slip2) < $signed(-limit)) ; // flag set if cycle slip occurs with f_dat_i > f_DDS
assign cycle_slip_flag = cycle_slip_flag_pos || cycle_slip_flag_neg ;


////////////////////////////////////////////////////////////////////////////////
// Cycle-slip detection alternative (window discriminator)
////////////////////////////////////////////////////////////////////////////////
wire  Q_comp;
wire  I_comp;
wire  phase_comp;
wire  ampl_comp;

assign Q_comp = ( ($signed(Q_filtered) > $signed(Q_thld)) || ($signed(Q_filtered) < $signed(-Q_thld)) ); // if Q is sym. around 0
assign I_comp = ( ($signed(I_2[64-1 :32-1]) < $signed(I_thld)) ); // if I is about 1 (or -1), thats why you have to take the absolute value of I

assign cycle_slip_flag1 = Q_comp || I_comp;

assign phase_comp = ( ($signed(phase) > $signed(phase_thld)) || ($signed(phase) < $signed(-phase_thld)) ); // if phase is sym. around 0
assign ampl_comp = ( ($signed(ampl) < $signed(ampl_thld)) ); // if ampl is about 1  
assign cycle_slip_flag2 = phase_comp || ampl_comp; 


////////////////////////////////////////////////////////////////////////////////
// Calc phase increment: pinc = old value + PI1 + PI2
////////////////////////////////////////////////////////////////////////////////

reg   [48-1: 0] dds_pinc_old;
reg   [48-1: 0] dds_pinc_i_old;  
   
always @(posedge clk_i) begin
   if (rstn_i == 1'b0) begin
      dds_pinc_old      <= 48'h0;
      dds_pinc_i_old    <= 48'h0;
   end
   else if (dds_pinc_init_en == 1'b1) begin // only use the dds_pinc_input value once if it changed  
      dds_pinc_old      <= (dds_pinc_init << 16);
      dds_pinc_i_old    <= (dds_pinc_init << 16);
   end
   else
      dds_pinc_old  <= $signed(dds_pinc); // feedback of output signal to DDS phase increment  Julia
//      dds_pinc_old  <= (dds_pinc);          // feedback of output signal to DDS phase increment  Mattias
end
   
assign dds_pinc = $signed(dds_pinc_old) + ( ($signed(pi_2_out) + $signed(pi_1_out)) * (!dds_pinc_init_en) );          // Julia
//assign dds_pinc = (dds_pinc_old) + ( (($signed(pi_2_out)) + ($signed(pi_1_out))) * (!dds_pinc_init_en) );           // Mattias  
assign dds_pinc_init_en = (!(dds_pinc_init << 16  == (dds_pinc_i_old)));


////////////////////////////////////////////////////////////////////////////////
// Calc phase increment: pinc = old value 2 + PI1 2 + PI2 2
////////////////////////////////////////////////////////////////////////////////

reg   [48-1: 0] dds_pinc_old_2;
reg   [48-1: 0] dds_pinc_i_old_2;  
   
always @(posedge clk_i) begin
   if (rstn_i == 1'b0) begin
      dds_pinc_old_2      <= 48'h0;
      dds_pinc_i_old_2    <= 48'h0;
   end
   else if (dds_pinc_init_en_2 == 1'b1) begin // only use the dds_pinc_input value once if it changed  
      dds_pinc_old_2      <= dds_pinc_init_2 << 16;
      dds_pinc_i_old_2    <= dds_pinc_init_2 << 16;
   end
   else
      dds_pinc_old_2  <= $signed(dds_pinc_2); // feedback of output signal to DDS phase increment
end
   
assign dds_pinc_2 = $signed(dds_pinc_old_2) + ( ($signed(pi_2_out_2) + $signed(pi_1_out_2)) * (!dds_pinc_init_en_2) );  
assign dds_pinc_init_en_2 = (!(dds_pinc_init_2 << 16 == dds_pinc_i_old_2));
    
////////////////////////////////////////////////////////////////////////////////
// PI 1
////////////////////////////////////////////////////////////////////////////////

reg  [ 32-1: 0] set_1_sp    ;
reg  [ 32-1: 0] set_1_kp    ;
reg  [ 32-1: 0] set_1_ki    ;
reg             set_1_irst  ;
wire            int_rst_1_total;

red_pitaya_pi_block #(
  .PSR (  PSR   ),
  .ISR (  ISR   )     
) i_pi1 (
   // data
  .clk_i        (  clk_i           ),  // clock
  .rstn_i       (  rstn_i          ),  // reset - active low
  .dat_i        (  $signed(omega)  ),  // input data            // omega_avg
  .dat_o        (  pi_1_out        ),  // output data

   // settings
  .set_sp_i     (  set_1_sp       ),  // set point
  .set_kp_i     (  set_1_kp       ),  // Kp
  .set_ki_i     (  set_1_ki       ),  // Ki
  .int_rst_i    (  int_rst_1_total   )   // integrator reset
);   

assign int_rst_1_total = (set_1_irst || dds_pinc_init_en); // reset integrator if the dds_init value changed

////////////////////////////////////////////////////////////////////////////////
// PI 2
////////////////////////////////////////////////////////////////////////////////

reg  [ 32-1: 0] set_2_sp    ;
reg  [ 32-1: 0] set_2_kp    ;
reg  [ 32-1: 0] set_2_ki    ;
reg             set_2_irst  ;
wire            int_rst_2_total;

red_pitaya_pi_block #(
  .PSR (  PSR   ),
  .ISR (  ISR   )     
) i_pi2 (
   // data
  .clk_i        (  clk_i           ),  // clock
  .rstn_i       (  rstn_i          ),  // reset - active low
  .dat_i        (  $signed(Q_filtered)  ),  // input data
  .dat_o        (  pi_2_out        ),  // output data

   // settings
  .set_sp_i     (  set_2_sp       ),  // set point
  .set_kp_i     (  set_2_kp       ),  // Kp
  .set_ki_i     (  set_2_ki       ),  // Ki
  .int_rst_i    (  int_rst_2_total   )   // integrator reset
);   

assign int_rst_2_total = (set_2_irst || dds_pinc_init_en); // reset integrator if the dds_init value changed


////////////////////////////////////////////////////////////////////////////////
// PI 1 2
////////////////////////////////////////////////////////////////////////////////

reg  [ 32-1: 0] set_1_sp_2    ;
reg  [ 32-1: 0] set_1_kp_2    ;
reg  [ 32-1: 0] set_1_ki_2    ;
reg             set_1_irst_2  ;
wire            int_rst_1_total_2;

red_pitaya_pi_block #(
  .PSR (  PSR   ),
  .ISR (  ISR   )     
) i_pi1_2 (
   // data
  .clk_i        (  clk_i           ),  // clock
  .rstn_i       (  rstn_i          ),  // reset - active low
  .dat_i        (  $signed(omega_2)  ),  // input data            // omega_avg
  .dat_o        (  pi_1_out_2        ),  // output data

   // settings
  .set_sp_i     (  set_1_sp_2       ),  // set point
  .set_kp_i     (  set_1_kp_2       ),  // Kp
  .set_ki_i     (  set_1_ki_2       ),  // Ki
  .int_rst_i    (  int_rst_1_total_2   )   // integrator reset
);   

assign int_rst_1_total_2 = (set_1_irst_2 || dds_pinc_init_en); // reset integrator if the dds_init value changed

////////////////////////////////////////////////////////////////////////////////
// PI 2 2
////////////////////////////////////////////////////////////////////////////////

reg  [ 32-1: 0] set_2_sp_2    ;
reg  [ 32-1: 0] set_2_kp_2    ;
reg  [ 32-1: 0] set_2_ki_2    ;
reg             set_2_irst_2  ;
wire            int_rst_2_total_2;

red_pitaya_pi_block #(
  .PSR (  PSR   ),
  .ISR (  ISR   )     
) i_pi2_2 (
   // data
  .clk_i        (  clk_i           ),  // clock
  .rstn_i       (  rstn_i          ),  // reset - active low
  .dat_i        (  $signed(Q_filtered_2)  ),  // input data
  .dat_o        (  pi_2_out_2        ),  // output data

   // settings
  .set_sp_i     (  set_2_sp_2       ),  // set point
  .set_kp_i     (  set_2_kp_2       ),  // Kp
  .set_ki_i     (  set_2_ki_2       ),  // Ki
  .int_rst_i    (  int_rst_2_total_2   )   // integrator reset
);   

assign int_rst_2_total_2 = (set_2_irst_2 || dds_pinc_init_en_2); // reset integrator if the dds_init value changed


   ////////////////////////////////////////////////////////////////////////////////
   // Expansion connector
   ////////////////////////////////////////////////////////////////////////////////
   reg   [    14-1: 0] count      ;
   reg   [    14-1: 0] count0     ;
   reg   [    14-1: 0] count1     ;
   reg   [    14-1: 0] count2     ;
   reg   [    14-1: 0] hold_time  ;
   
   always @(posedge clk_i) begin
      if (rstn_i == 1'b0) begin
         exp_n_dat_o  <= {DWE{1'b0}};
         exp_n_dir_o  <= {DWE{1'b1}}; // output
         count        <= {14{1'b0}};
         count0       <= {14{1'b0}};
         count1       <= {14{1'b0}};
         count2       <= {14{1'b0}};
         hold_time    <= 125;
      end
      else begin
         if (cycle_slip) begin
            exp_n_dat_o[0]  <= cycle_slip; 
            count           <= hold_time; 
         end 
         else if ($signed(count) > 0) 
            count <= $signed(count) - 1; 
         else if (($signed(count) == 0) && (!cycle_slip))
            exp_n_dat_o[0]  <= {1'b0};
                   
         if (cycle_slip_flag) begin
            exp_n_dat_o[1]  <= cycle_slip_flag; 
            count0          <= hold_time; 
         end 
         else if ($signed(count0) > 0) 
             count <= $signed(count0) - 1; 
         else if (($signed(count0) == 0) && (!cycle_slip_flag))
             exp_n_dat_o[1]  <= {1'b0};  
                  
         if (cycle_slip_flag1) begin
            exp_n_dat_o[2]  <= cycle_slip_flag1;   
            count1          <= hold_time;
         end
         else if ($signed(count1) > 0) 
            count1 <= $signed(count1) - 1; 
         else if (($signed(count1) == 0) && (!cycle_slip_flag1)) 
            exp_n_dat_o[2]  <= {1'b0}; 
         
         if (cycle_slip_flag2) begin
            exp_n_dat_o[3]  <= cycle_slip_flag2; 
            count2          <= hold_time; 
         end   
         else if ($signed(count2) > 0) 
            count2 <= $signed(count2) - 1;    
         else if (($signed(count2) == 0) && (!cycle_slip_flag2))
            exp_n_dat_o[3]  <= {1'b0};                        
      end
   end


////////////////////////////////////////////////////////////////////////////////
// MUX output signal
////////////////////////////////////////////////////////////////////////////////
 reg [ 14-1: 0] dac1_out;
 reg [ 14-1: 0] dac2_out;

 always@(posedge clk_i)
  case ({phase_dac1_en,dds_dac1_en})
    2'b00: dac1_out = $signed(I_filtered[32-1-3: 18-3]); //[32-1-4: 18-1-4]
    2'b01: dac1_out = $signed(dds_o[16-1: 2]);
    2'b10: dac1_out = $signed(phase[32-1: 18]);
    2'b11: dac1_out = $signed(omega[32-1: 18]);
  endcase
 
 always@(posedge clk_i)
  case ({ampl_dac2_en,dds_dac2_en})
    2'b00: dac2_out = $signed(Q_filtered[32-1-3: 18-3]); //[32-1-8: 18-1-8]
    2'b01: dac2_out = $signed(dds_o_2[16-1: 2]);
    2'b10: dac2_out = $signed(ampl[32-1: 18]);        
    2'b11: dac2_out = $signed(dds_pinc[32-1: 18]);
  endcase
   
//---------------------------------------------------------------------------------
//  Sum and saturation

wire [ 15-1: 0] out_1_sum   ;
reg  [ 14-1: 0] out_1_sat   ;
wire [ 15-1: 0] out_2_sum   ;
reg  [ 14-1: 0] out_2_sat   ;

assign out_1_sum = $signed(dac1_out);
assign out_2_sum = $signed(dac2_out);  

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
         out_1_sat <= out_1_sum[14-1:0] ;

      if (out_2_sum[15-1:15-2]==2'b01) // postitive sat
         out_2_sat <= 14'h1FFF ;
      else if (out_2_sum[15-1:15-2]==2'b10) // negative sat
         out_2_sat <= 14'h2000 ;
      else
         out_2_sat <= out_2_sum[14-1:0] ;
   end
end

assign dat_a_o = out_1_sat ;
assign dat_b_o = out_2_sat ;
assign dat_c_o = dds_pinc;      //I_filtered ;       geändert Mattias
assign dat_d_o = dds_pinc_2;    //Q_filtered ;
//assign dat_g_o = exp_n_dat_o;

//---------------------------------------------------------------------------------
//
//  System bus connection

always @(posedge clk_i) begin
   if (rstn_i == 1'b0) begin
      set_1_irst    <=  1'b1 ;
      set_1_irst_2  <=  1'b1 ;
      set_1_sp      <= 32'd0 ;
      set_1_kp      <= 32'd0 ;
      set_1_ki      <= 32'd0 ;
      set_2_irst    <=  1'b1 ;
      set_2_irst_2  <=  1'b1 ;
      set_2_sp      <= 32'd0 ;
      set_2_kp      <= 32'd0 ;
      set_2_ki      <= 32'd0 ;
      dds_dac1_en   <=  1'b0 ;
      dds_dac2_en   <=  1'b0 ;
      phase_dac1_en <=  1'b0 ;
      ampl_dac2_en  <=  1'b0 ;
      dds_pinc_init <= 32'd0 ;      //32'd343597383; // = 10 MHz  // 
      dds_pinc_init_2 <= 32'd0 ;    //32'd343597383; // = 10 MHz  //
      offset_cha    <= 32'd0 ;
      offset_chb    <= 32'd0 ;
      I_thld        <= 32'd0 ;
      Q_thld        <= 32'd0 ;
      phase_thld    <= 32'd0 ;
      ampl_thld     <= 32'd0 ;
      cycle_slip_limit <= 32'd0 ;
   end
   else begin
      if (sys_wen) begin
         if (sys_addr[19:0]==16'h0)    {ampl_dac2_en, phase_dac1_en, dds_dac2_en, dds_dac1_en, set_2_irst, set_1_irst} <= sys_wdata[ 6-1:0] ; 

         if (sys_addr[19:0]==16'h10)    set_1_sp        <= sys_wdata[32-1:0] ;
         if (sys_addr[19:0]==16'h14)    set_1_kp        <= sys_wdata[32-1:0] ;
         if (sys_addr[19:0]==16'h18)    set_1_ki        <= sys_wdata[32-1:0] ;
         if (sys_addr[19:0]==16'h1C)    dds_pinc_init   <= sys_wdata[32-1:0] ;
         
         if (sys_addr[19:0]==16'h20)    set_2_sp        <= sys_wdata[32-1:0] ;
         if (sys_addr[19:0]==16'h24)    set_2_kp        <= sys_wdata[32-1:0] ;
         if (sys_addr[19:0]==16'h28)    set_2_ki        <= sys_wdata[32-1:0] ;
         //if (sys_addr[19:0]==16'h2C)    cycle_slip     <= sys_wdata[32-1:0] ;
         
         if (sys_addr[19:0]==16'h210)    set_1_sp_2        <= sys_wdata[32-1:0] ;
         if (sys_addr[19:0]==16'h214)    set_1_kp_2        <= sys_wdata[32-1:0] ;
         if (sys_addr[19:0]==16'h218)    set_1_ki_2        <= sys_wdata[32-1:0] ;
         if (sys_addr[19:0]==16'h21C)    dds_pinc_init_2   <= sys_wdata[32-1:0] ;
         
         if (sys_addr[19:0]==16'h220)    set_2_sp_2        <= sys_wdata[32-1:0] ;
         if (sys_addr[19:0]==16'h224)    set_2_kp_2        <= sys_wdata[32-1:0] ;
         if (sys_addr[19:0]==16'h228)    set_2_ki_2        <= sys_wdata[32-1:0] ;
         //if (sys_addr[19:0]==16'h2C)    cycle_slip     <= sys_wdata[32-1:0] ;
         
         if (sys_addr[19:0]==16'h30)    I_thld           <= sys_wdata[32-1:0] ;
         if (sys_addr[19:0]==16'h34)    Q_thld           <= sys_wdata[32-1:0] ;
         if (sys_addr[19:0]==16'h38)    phase_thld       <= sys_wdata[32-1:0] ;
         if (sys_addr[19:0]==16'h3C)    ampl_thld        <= sys_wdata[32-1:0] ;
         
         if (sys_addr[19:0]==16'h48)    cycle_slip_limit <= sys_wdata[32-1:0] ;
         if (sys_addr[19:0]==16'h40)    offset_cha       <= sys_wdata[32-1:0] ;
         if (sys_addr[19:0]==16'h44)    offset_chb       <= sys_wdata[32-1:0] ;
         //if (sys_addr[19:0]==16'h4C)    exp_n_dat_o      <= sys_wdata[32-1:0] ;

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
      20'h00 : begin sys_ack <= sys_en;          sys_rdata <= {{32- 6{1'b0}}, ampl_dac2_en, phase_dac1_en, dds_dac2_en, dds_dac1_en, set_2_irst, set_1_irst}       ; end 
      20'h10 : begin sys_ack <= sys_en;          sys_rdata <= {set_1_sp}           ; end 
      20'h14 : begin sys_ack <= sys_en;          sys_rdata <= {set_1_kp}           ; end 
      20'h18 : begin sys_ack <= sys_en;          sys_rdata <= {set_1_ki}           ; end 
      20'h1C : begin sys_ack <= sys_en;          sys_rdata <= {dds_pinc_init}      ; end
      
      20'h20 : begin sys_ack <= sys_en;          sys_rdata <= {set_2_sp}           ; end 
      20'h24 : begin sys_ack <= sys_en;          sys_rdata <= {set_2_kp}           ; end 
      20'h28 : begin sys_ack <= sys_en;          sys_rdata <= {set_2_ki}           ; end 
      20'h2C : begin sys_ack <= sys_en;          sys_rdata <= {dds_pinc_init_2}    ; end
      
      20'h30 : begin sys_ack <= sys_en;          sys_rdata <= {I_thld   }          ; end 
      20'h34 : begin sys_ack <= sys_en;          sys_rdata <= {Q_thld   }          ; end 
      20'h38 : begin sys_ack <= sys_en;          sys_rdata <= {phase_thld}         ; end 
      20'h3C : begin sys_ack <= sys_en;          sys_rdata <= {ampl_thld}          ; end
             
      20'h40 : begin sys_ack <= sys_en;          sys_rdata <= {cycle_slip_limit}   ; end 
      20'h44 : begin sys_ack <= sys_en;          sys_rdata <= {offset_cha}         ; end 
      20'h48 : begin sys_ack <= sys_en;          sys_rdata <= {offset_chb}         ; end
      20'h4C : begin sys_ack <= sys_en;          sys_rdata <= {exp_n_dat_o}        ; end  // cycle_slip_flags
      
      20'h50 : begin sys_ack <= sys_en;          sys_rdata <= {dds_pinc}           ; end  // current pinc value
      20'h54 : begin sys_ack <= sys_en;          sys_rdata <= {dds_pinc_2}         ; end  // current pinc 2 value
      
     default : begin sys_ack <= sys_en;          sys_rdata <=  32'h0                              ; end
   endcase
end

endmodule
