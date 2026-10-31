////////////////////////////////////////////////////////////////////////////////
// Red Pitaya TOP module. It connects external pins and PS part with
// other application modules.
// Authors: Matej Oblak, Iztok Jeras
// (c) Red Pitaya  http://www.redpitaya.com
////////////////////////////////////////////////////////////////////////////////

module red_pitaya_top #(
  // identification
  bit [0:5*32-1] GITH = '0,
  // module numbers
  int unsigned MNA = 2,  // number of acquisition modules
  int unsigned MNG = 2   // number of generator   modules
)(
  // PS connections
  inout  logic [54-1:0] FIXED_IO_mio     ,
  inout  logic          FIXED_IO_ps_clk  ,
  inout  logic          FIXED_IO_ps_porb ,
  inout  logic          FIXED_IO_ps_srstb,
  inout  logic          FIXED_IO_ddr_vrn ,
  inout  logic          FIXED_IO_ddr_vrp ,
  // DDR
  inout  logic [15-1:0] DDR_addr   ,
  inout  logic [ 3-1:0] DDR_ba     ,
  inout  logic          DDR_cas_n  ,
  inout  logic          DDR_ck_n   ,
  inout  logic          DDR_ck_p   ,
  inout  logic          DDR_cke    ,
  inout  logic          DDR_cs_n   ,
  inout  logic [ 4-1:0] DDR_dm     ,
  inout  logic [32-1:0] DDR_dq     ,
  inout  logic [ 4-1:0] DDR_dqs_n  ,
  inout  logic [ 4-1:0] DDR_dqs_p  ,
  inout  logic          DDR_odt    ,
  inout  logic          DDR_ras_n  ,
  inout  logic          DDR_reset_n,
  inout  logic          DDR_we_n   ,

  // Red Pitaya periphery
  // ADC
  input  logic [MNA-1:0] [16-1:0] adc_dat_i,  // ADC data
  input  logic           [ 2-1:0] adc_clk_i,  // ADC clock {p,n}
  output logic           [ 2-1:0] adc_clk_o,  // optional ADC clock source (unused)
  output logic                    adc_cdcs_o, // ADC clock duty cycle stabilizer
  // DAC
  output logic [14-1:0] dac_dat_o  ,  // DAC combined data
  output logic          dac_wrt_o  ,  // DAC write
  output logic          dac_sel_o  ,  // DAC channel select
  output logic          dac_clk_o  ,  // DAC clock
  output logic          dac_rst_o  ,  // DAC reset
  // PWM DAC
  output logic [ 4-1:0] dac_pwm_o  ,  // 1-bit PWM DAC
  // XADC
  input  logic [ 5-1:0] vinp_i     ,  // voltages p
  input  logic [ 5-1:0] vinn_i     ,  // voltages n
  // Expansion connector
  inout  logic [ 8-1:0] exp_p_io   ,
  inout  logic [ 8-1:0] exp_n_io     
//  // LED
//  inout  logic [ 8-1:0] led_o
);

////////////////////////////////////////////////////////////////////////////////
// local signals
////////////////////////////////////////////////////////////////////////////////

// GPIO parameter
localparam int unsigned GDW = 8+8;

logic [4-1:0] fclk ; //[0]-125MHz, [1]-250MHz, [2]-50MHz, [3]-200MHz
logic [4-1:0] frstn;

// PLL signals
logic                 adc_clk_in;
logic                 pll_adc_clk;
logic                 pll_dac_clk_1x;
logic                 pll_dac_clk_2x;
logic                 pll_dac_clk_2p;
logic                 pll_ser_clk;
logic                 pll_pwm_clk;
logic                 pll_locked;
// fast serial signals
logic                 ser_clk ;
// PWM clock and reset
logic                 pwm_clk ;
logic                 pwm_rstn;

// ADC clock/reset
logic                 adc_clk;
logic                 adc_rstn;

// stream bus type
localparam type SBA_T = logic signed [14-1:0];  // acquire
localparam type SBG_T = logic signed [14-1:0];  // generate

SBA_T [MNA-1:0]          adc_dat;
SBA_T [  7-1:0]          dat; // added by PTB   Mattias

// DAC signals
logic                    dac_clk_1x;
logic                    dac_clk_2x;
logic                    dac_clk_2p;
logic                    dac_rst;

logic        [14-1:0] dac_dat_a, dac_dat_b;
logic        [14-1:0] dac_a    , dac_b    ;
logic signed [15-1:0] dac_a_sum, dac_b_sum;

// system bus
sys_bus_if   ps_sys      (.clk (adc_clk), .rstn (adc_rstn));
sys_bus_if   sys [8-1:0] (.clk (adc_clk), .rstn (adc_rstn));

// GPIO interface
gpio_if #(.DW (24)) gpio ();

// trigger
logic                   trigger; // TODO trigger source to be set.

////////////////////////////////////////////////////////////////////////////////
// PLL (clock and reset)
////////////////////////////////////////////////////////////////////////////////

// diferential clock input
IBUFDS i_clk (.I (adc_clk_i[1]), .IB (adc_clk_i[0]), .O (adc_clk_in));  // differential clock input

red_pitaya_pll pll (
  // inputs
  .clk         (adc_clk_in),  // clock
  .rstn        (frstn[0]  ),  // reset - active low
  // output clocks
  .clk_adc     (pll_adc_clk   ),  // ADC clock
  .clk_dac_1x  (pll_dac_clk_1x),  // DAC clock 125MHz
  .clk_dac_2x  (pll_dac_clk_2x),  // DAC clock 250MHz
  .clk_dac_2p  (pll_dac_clk_2p),  // DAC clock 250MHz -45DGR
  .clk_ser     (pll_ser_clk   ),  // fast serial clock
  .clk_pdm     (pll_pwm_clk   ),  // PWM clock
  // status outputs
  .pll_locked  (pll_locked)
);

BUFG bufg_adc_clk    (.O (adc_clk   ), .I (pll_adc_clk   ));
BUFG bufg_dac_clk_1x (.O (dac_clk_1x), .I (pll_dac_clk_1x));
BUFG bufg_dac_clk_2x (.O (dac_clk_2x), .I (pll_dac_clk_2x));
BUFG bufg_dac_clk_2p (.O (dac_clk_2p), .I (pll_dac_clk_2p));
BUFG bufg_ser_clk    (.O (ser_clk   ), .I (pll_ser_clk   ));
BUFG bufg_pwm_clk    (.O (pwm_clk   ), .I (pll_pwm_clk   ));

// ADC reset (active low)
always @(posedge adc_clk)
adc_rstn <=  frstn[0] &  pll_locked;

// DAC reset (active high)
always @(posedge dac_clk_1x)
dac_rst  <= ~frstn[0] | ~pll_locked;

// PWM reset (active low)
always @(posedge pwm_clk)
pwm_rstn <=  frstn[0] &  pll_locked;

////////////////////////////////////////////////////////////////////////////////
//  Connections to PS
////////////////////////////////////////////////////////////////////////////////

red_pitaya_ps ps (
  .FIXED_IO_mio       (  FIXED_IO_mio                ),
  .FIXED_IO_ps_clk    (  FIXED_IO_ps_clk             ),
  .FIXED_IO_ps_porb   (  FIXED_IO_ps_porb            ),
  .FIXED_IO_ps_srstb  (  FIXED_IO_ps_srstb           ),
  .FIXED_IO_ddr_vrn   (  FIXED_IO_ddr_vrn            ),
  .FIXED_IO_ddr_vrp   (  FIXED_IO_ddr_vrp            ),
  // DDR
  .DDR_addr      (DDR_addr    ),
  .DDR_ba        (DDR_ba      ),
  .DDR_cas_n     (DDR_cas_n   ),
  .DDR_ck_n      (DDR_ck_n    ),
  .DDR_ck_p      (DDR_ck_p    ),
  .DDR_cke       (DDR_cke     ),
  .DDR_cs_n      (DDR_cs_n    ),
  .DDR_dm        (DDR_dm      ),
  .DDR_dq        (DDR_dq      ),
  .DDR_dqs_n     (DDR_dqs_n   ),
  .DDR_dqs_p     (DDR_dqs_p   ),
  .DDR_odt       (DDR_odt     ),
  .DDR_ras_n     (DDR_ras_n   ),
  .DDR_reset_n   (DDR_reset_n ),
  .DDR_we_n      (DDR_we_n    ),
  // system signals
  .fclk_clk_o    (fclk        ),
  .fclk_rstn_o   (frstn       ),
  // ADC analog inputs
  .vinp_i        (vinp_i      ),
  .vinn_i        (vinn_i      ),
  // GPIO
  .gpio          (gpio),
  // system read/write channel
  .bus           (ps_sys      )
);

////////////////////////////////////////////////////////////////////////////////
// system bus decoder & multiplexer (it breaks memory addresses into 8 regions)
////////////////////////////////////////////////////////////////////////////////

sys_bus_interconnect #(
  .SN (8),
  .SW (20)
) sys_bus_interconnect (
  .bus_m (ps_sys),
  .bus_s (sys)
);

// silence unused busses
generate // todo anpassen auf meine anzahl von subsystemen ( = 1)
for (genvar i=7; i<8; i++) begin: for_sys     // PTB: changed i=5 to 7 to use the FREE space CS[6]
  sys_bus_stub sys_bus_stub_5_7 (sys[i]);
end: for_sys
endgenerate


////////////////////////////////////////////////////////////////////////////////
// ADC IO
////////////////////////////////////////////////////////////////////////////////
// ADC clock duty cycle stabilizer is enabled
assign adc_cdcs_o = 1'b1 ;

logic [2-1:0] [14-1:0] adc_dat_raw;

// lowest 2 bits reserved for 16bit ADC
always @(posedge adc_clk)// todo: diese Registrierung nötig?
begin
  adc_dat_raw[0] <= adc_dat_i[0][16-1:2];
  adc_dat_raw[1] <= adc_dat_i[1][16-1:2];
end
// transform into 2's complement (negative slope)
assign adc_dat[0] = {adc_dat_raw[0][14-1], ~adc_dat_raw[0][14-2:0]};
assign adc_dat[1] = {adc_dat_raw[1][14-1], ~adc_dat_raw[1][14-2:0]};

////////////////////////////////////////////////////////////////////////////////
// DAC IO
////////////////////////////////////////////////////////////////////////////////
// output registers + signed to unsigned (also to negative slope)
always @(posedge dac_clk_1x) // todo: hier könnte man einen clk cycle sparen, wenn man ohne Zwischenregister arbeitet.
begin
  dac_dat_a <= {dac_a[14-1], ~dac_a[14-2:0]};
  dac_dat_b <= {dac_b[14-1], ~dac_b[14-2:0]};
end

// DDR outputs
ODDR oddr_dac_clk          (.Q(dac_clk_o), .D1(1'b0     ), .D2(1'b1     ), .C(dac_clk_2p), .CE(1'b1), .R(1'b0   ), .S(1'b0));
ODDR oddr_dac_wrt          (.Q(dac_wrt_o), .D1(1'b0     ), .D2(1'b1     ), .C(dac_clk_2x), .CE(1'b1), .R(1'b0   ), .S(1'b0));
ODDR oddr_dac_sel          (.Q(dac_sel_o), .D1(1'b1     ), .D2(1'b0     ), .C(dac_clk_1x), .CE(1'b1), .R(dac_rst), .S(1'b0));
ODDR oddr_dac_rst          (.Q(dac_rst_o), .D1(dac_rst  ), .D2(dac_rst  ), .C(dac_clk_1x), .CE(1'b1), .R(1'b0   ), .S(1'b0));
ODDR oddr_dac_dat [14-1:0] (.Q(dac_dat_o), .D1(dac_dat_b), .D2(dac_dat_a), .C(dac_clk_1x), .CE(1'b1), .R(dac_rst), .S(1'b0));


////////////////////////////////////////////////////////////////////////////////
/***
 *      _  _     _  _     _   _   _  __            ___     ___    __    ___      _         ____     _____   _____    _____     ____    ______   _         ____   __          __
 *     | || |   | || |   | \ | | | |/ /           / _ \   / _ \  /_ |  / _ \    | |       / __ \   / ____| |_   _|  / ____|   |  _ \  |  ____| | |       / __ \  \ \        / /
 *     | || |_  | || |_  |  \| | | ' /           | | | | | | | |  | | | (_) |   | |      | |  | | | |  __    | |   | |        | |_) | | |__    | |      | |  | |  \ \  /\  / / 
 *     |__   _| |__   _| | . ` | |  <            | | | | | | | |  | |  > _ <    | |      | |  | | | | |_ |   | |   | |        |  _ <  |  __|   | |      | |  | |   \ \/  \/ /  
 *        | |      | |   | |\  | | . \           | |_| | | |_| |  | | | (_) |   | |____  | |__| | | |__| |  _| |_  | |____    | |_) | | |____  | |____  | |__| |    \  /\  /   
 *        |_|      |_|   |_| \_| |_|\_\           \___/   \___/   |_|  \___/    |______|  \____/   \_____| |_____|  \_____|   |____/  |______| |______|  \____/      \/  \/    
 *                                       ______                                                                                                                                
 *                                      |______|                                                                                                                               
 */
////////////////////////////////////////////////////////////////////////////////

/***
 *      _____               _____               __  __   ______   _______   ______   _____     _____ 
 *     |  __ \      /\     |  __ \      /\     |  \/  | |  ____| |__   __| |  ____| |  __ \   / ____|
 *     | |__) |    /  \    | |__) |    /  \    | \  / | | |__       | |    | |__    | |__) | | (___  
 *     |  ___/    / /\ \   |  _  /    / /\ \   | |\/| | |  __|      | |    |  __|   |  _  /   \___ \ 
 *     | |       / ____ \  | | \ \   / ____ \  | |  | | | |____     | |    | |____  | | \ \   ____) |
 *     |_|      /_/    \_\ |_|  \_\ /_/    \_\ |_|  |_| |______|    |_|    |______| |_|  \_\ |_____/ 
 *                                                                                                   
 *                                                                                                   
 */
 
 localparam PHASE_RESOLUTION_360 = 16; // xx Bit represent 360 Degree ATTENTION: when you change this value adapt dsp_phase_measure.sv correspondingly 
 localparam MAGNITUDE_RESOLUTION = PHASE_RESOLUTION_360; // equivalent to phase resolution because of the common cordic
 localparam PHASE_RESOLUTION_UNWRAPPED = 32; // Resolution of the phase after unwrapping (fullscale)
 localparam PHASE_RESOLUTION_UNWRAPPED_SATURATED = 19; // Resolution of the phase after unwrapping and saturation (for limited phase resolution for the controller calculations)
 localparam DDS_FREQUENCY_WORD_WIDTH = 32;
 localparam DDS_PHASE_WORD_WIDTH = 14; // equals 360°
 localparam CONTROLLER_COEFFICIENT_WIDTH = 16; // (signed) 2 integer digits + 14 fractional digits => coefficient interval [-2 … +2[  
 localparam CONTROLLER_COEFFICIENT_FRACTIONAL_DIGITS = 14;
 
 
 
/***
 *      _____                   _         _                     _____           _                    __                       
 *     |  __ \                 (_)       | |                   |_   _|         | |                  / _|                      
 *     | |__) |   ___    __ _   _   ___  | |_    ___   _ __      | |    _ __   | |_    ___   _ __  | |_    __ _    ___    ___ 
 *     |  _  /   / _ \  / _` | | | / __| | __|  / _ \ | '__|     | |   | '_ \  | __|  / _ \ | '__| |  _|  / _` |  / __|  / _ \
 *     | | \ \  |  __/ | (_| | | | \__ \ | |_  |  __/ | |       _| |_  | | | | | |_  |  __/ | |    | |   | (_| | | (__  |  __/
 *     |_|  \_\  \___|  \__, | |_| |___/  \__|  \___| |_|      |_____| |_| |_|  \__|  \___| |_|    |_|    \__,_|  \___|  \___|
 *                       __/ |                                                                                                
 *                      |___/                                                                                                 
 * Font Generator: http://patorjk.com/software/taag/#p=display&h=0&v=0&c=c&f=Big&t=Dig.%20Attenuator
 */
wire signed [16-1:0]    CPU_controller_0_b0;
wire signed [16-1:0]    CPU_controller_0_b1;
wire signed [32-1:0]    CPU_phase_controller_setpoint;
wire [32-1:0]           CPU_aom_0_frequency_offset;
wire [32-1:0]           CPU_aom_0_frequency_debug;
wire [32-1:0]           CPU_aom_1_frequency_debug;
wire [14-1:0]           CPU_aom_0_phase_debug;
wire [14-1:0]           CPU_aom_1_phase_debug;
wire [10-1:0]           CPU_aom_0_amplitude;
wire [10-1:0]           CPU_aom_1_amplitude;
wire [10-1:0]           CPU_mixer_0_amplitude;
wire [10-1:0]           CPU_mixer_1_amplitude;
wire [5-1:0]            CPU_dat_0_attenuation;
wire [5-1:0]            CPU_dat_1_attenuation;
wire                    CPU_set_phase_0_unwrapped_zero_trigger;
wire                    CPU_controller_0_phase_out_zero;
wire                    CPU_fpga_enable;
wire                    CPU_controller_coefficient_updating;
wire                    CPU_acquisition_trigger;
wire                    CPU_reset_request;

wire [32-1:0] CPU_mixer_0_local_oscillator_frequency; // todo integrate these wires into the wire structure above and remove unused wires.
wire [32-1:0] CPU_mixer_1_local_oscillator_frequency;
wire [48-1:0] CPU_fpga_mixer_0_local_oscillator_frequency;

wire                    PHASE_UNWRAPPER_valid;
wire signed [PHASE_RESOLUTION_UNWRAPPED-1:0]    PHASE_UNWRAPPER_phase_fullscale;
wire signed [PHASE_RESOLUTION_UNWRAPPED_SATURATED-1:0]    PHASE_UNWRAPPER_phase_saturated;
wire signed [65-1:0]    AVERAGER_phase_fullscale_125kHz;
wire                    AVERAGER_valid;
reg signed [32-1:0]     LPF_magnitude_0_always_valid;
wire [PHASE_RESOLUTION_360-1:0] DSP_PHASE_MEASURE_phase;
wire [32-1:0]           DDS_error_read_write_mismatch;

register_interface register_interface_0 (
  .clk_i           (adc_clk),
  .rstn_i          (adc_rstn),
  .fpga_startup_enable(CPU_fpga_enable),
  .controller_coefficient_updating(CPU_controller_coefficient_updating),
  .dat_0_attenuation(CPU_dat_0_attenuation),
  .dat_1_attenuation(CPU_dat_1_attenuation),
  .mixer_0_local_oscillator_frequency(CPU_mixer_0_local_oscillator_frequency),
  .fpga_mixer_0_local_oscillator_frequency(CPU_fpga_mixer_0_local_oscillator_frequency),
  .controller_0_phase_setpoint(CPU_phase_controller_setpoint),
  .controller_0_b0(CPU_controller_0_b0),
  .controller_0_b1(CPU_controller_0_b1),
  .aom_0_frequency_offset(CPU_aom_0_frequency_offset),
  .aom_0_frequency_debug(CPU_aom_0_frequency_debug),
  .aom_0_phase_debug(CPU_aom_0_phase_debug),
  .aom_0_amplitude(CPU_aom_0_amplitude),
  .mixer_0_amplitude(CPU_mixer_0_amplitude),
  .set_phase_0_unwrapped_zero_trigger(CPU_set_phase_0_unwrapped_zero_trigger),
  .controller_0_phase_out_zero(CPU_controller_0_phase_out_zero),
  .magnitude_0(LPF_magnitude_0_always_valid),
  .mixer_1_local_oscillator_frequency(CPU_mixer_1_local_oscillator_frequency),
  .aom_1_frequency_debug(CPU_aom_1_frequency_debug),
  .aom_1_phase_debug(CPU_aom_1_phase_debug),
  .aom_1_amplitude(CPU_aom_1_amplitude),
  .mixer_1_amplitude(CPU_mixer_1_amplitude),
  .DDS_error_read_write_mismatch(DDS_error_read_write_mismatch),
  // Ringbuffer
  .i_ringbuffer_data_to_be_stored(AVERAGER_phase_fullscale_125kHz),
  .i_ringbuffer_data_valid(AVERAGER_valid),
  // System bus
  .sys_addr        (sys[6].addr ),
  .sys_wdata       (sys[6].wdata),
  .sys_wen         (sys[6].wen  ),
  .sys_ren         (sys[6].ren  ),
  .sys_rdata       (sys[6].rdata),
  .sys_err         (sys[6].err  ),
  .sys_ack         (sys[6].ack  )
);







/***
 *       _____                 _                           _____                   _                    _   _               
 *      / ____|               | |                         / ____|                 | |                  | | | |              
 *     | (___    _   _   ___  | |_    ___   _ __ ___     | |        ___    _ __   | |_   _ __    ___   | | | |   ___   _ __ 
 *      \___ \  | | | | / __| | __|  / _ \ | '_ ` _ \    | |       / _ \  | '_ \  | __| | '__|  / _ \  | | | |  / _ \ | '__|
 *      ____) | | |_| | \__ \ | |_  |  __/ | | | | | |   | |____  | (_) | | | | | | |_  | |    | (_) | | | | | |  __/ | |   
 *     |_____/   \__, | |___/  \__|  \___| |_| |_| |_|    \_____|  \___/  |_| |_|  \__| |_|     \___/  |_| |_|  \___| |_|   
 *                __/ |                                                                                                     
 *               |___/                                                                                                      
 */
wire SC_dds_enable;
wire SC_dat_enable;
wire SC_phase_controller_enable;
wire SC_phase_measurement_enable;
wire DDS_is_armed;
wire PHASE_CONTROLLER_is_armed;
system_controller system_controller0(
    .i_clk(adc_clk),
    .i_fpga_enable(CPU_fpga_enable),
    .o_dds_enable(SC_dds_enable),
    .o_dat_enable(SC_dat_enable),
    .o_phase_controller_enable(SC_phase_controller_enable),
    .o_phase_measurement_enable(SC_phase_measurement_enable),
    .i_dds_is_armed(DDS_is_armed),
    .i_phase_controller_is_armed(PHASE_CONTROLLER_is_armed)
    );


/***
 *      _____     _____   _____      _____    _                              __  __                                            
 *     |  __ \   / ____| |  __ \    |  __ \  | |                            |  \/  |                                           
 *     | |  | | | (___   | |__) |   | |__) | | |__     __ _   ___    ___    | \  / |   ___    __ _   ___   _   _   _ __    ___ 
 *     | |  | |  \___ \  |  ___/    |  ___/  | '_ \   / _` | / __|  / _ \   | |\/| |  / _ \  / _` | / __| | | | | | '__|  / _ \
 *     | |__| |  ____) | | |        | |      | | | | | (_| | \__ \ |  __/   | |  | | |  __/ | (_| | \__ \ | |_| | | |    |  __/
 *     |_____/  |_____/  |_|        |_|      |_| |_|  \__,_| |___/  \___|   |_|  |_|  \___|  \__,_| |___/  \__,_| |_|     \___|
 *                                                                                                                             
 *                                                                                                                             
 */
wire            DSP_PHASE_MEASURE_valid;
wire [MAGNITUDE_RESOLUTION-1:0]   DSP_PHASE_MEASURE_magnitude;
wire            DSP_PHASE_MEASURE_cic_valid_i;
wire signed [14-1:0] DSP_PHASE_MEASURE_sine_monitor;
dsp_phase_measure 
    #(
    .PHASE_WIDTH (PHASE_RESOLUTION_360), // ATTENTION: Cordic and the following processing need to be adapted manually when changing the phase or magnitude width!
    .MAGNITUDE_WIDTH (MAGNITUDE_RESOLUTION)
    ) 
    dsp_phase_measure_0 
    (
    .i_clk(adc_clk),
    .i_reset(SC_reset_dsp), // todo undriven
    .i_valid(1),
    .i_adc(adc_dat[0]),
    .i_enable (SC_phase_measurement_enable),
    .i_dds_frequency_word (CPU_fpga_mixer_0_local_oscillator_frequency),
    .o_valid(DSP_PHASE_MEASURE_valid),
    .o_phase (DSP_PHASE_MEASURE_phase),
    .o_magnitude (DSP_PHASE_MEASURE_magnitude),
    .o_sine_monitor (DSP_PHASE_MEASURE_sine_monitor),
    .o_cic_valid_i (DSP_PHASE_MEASURE_cic_valid_i)
    );
 
 /***
 *      _____    _                              _    _                                                                       __   _____           _                            _                  
 *     |  __ \  | |                            | |  | |                                                                     / /  / ____|         | |                          | |                 
 *     | |__) | | |__     __ _   ___    ___    | |  | |  _ __   __      __  _ __    __ _   _ __    _ __     ___   _ __     / /  | (___     __ _  | |_   _   _   _ __    __ _  | |_    ___    _ __ 
 *     |  ___/  | '_ \   / _` | / __|  / _ \   | |  | | | '_ \  \ \ /\ / / | '__|  / _` | | '_ \  | '_ \   / _ \ | '__|   / /    \___ \   / _` | | __| | | | | | '__|  / _` | | __|  / _ \  | '__|
 *     | |      | | | | | (_| | \__ \ |  __/   | |__| | | | | |  \ V  V /  | |    | (_| | | |_) | | |_) | |  __/ | |     / /     ____) | | (_| | | |_  | |_| | | |    | (_| | | |_  | (_) | | |   
 *     |_|      |_| |_|  \__,_| |___/  \___|    \____/  |_| |_|   \_/\_/   |_|     \__,_| | .__/  | .__/   \___| |_|    /_/     |_____/   \__,_|  \__|  \__,_| |_|     \__,_|  \__|  \___/  |_|   
 *                                                                                        | |     | |                                                                                             
 *                                                                                        |_|     |_|                                                                                             
 */


phase_unwrapper_saturator 
    #(
    .WIDTH_OF_PHASE_INPUT (PHASE_RESOLUTION_360),
    .WIDTH_OF_FULLSCALE_PHASE_OUTPUT (PHASE_RESOLUTION_UNWRAPPED),
    .WIDTH_OF_SATURATED_PHASE_OUTPUT (PHASE_RESOLUTION_UNWRAPPED_SATURATED)
    ) 
    phase_unwrapper_saturator_0(
    .i_clk(adc_clk),
    .i_set_phase_unwrapped_zero_trigger(CPU_set_phase_0_unwrapped_zero_trigger),
    .i_phase_valid(DSP_PHASE_MEASURE_valid),
    .i_phase(DSP_PHASE_MEASURE_phase),
    .o_valid(PHASE_UNWRAPPER_valid),
    .o_unwrapping_risk_of_overflow(/*todo handle this?*/),
    .o_phase_unwrapped_saturated(PHASE_UNWRAPPER_phase_saturated),
    .o_phase_unwrapped_fullscale(PHASE_UNWRAPPER_phase_fullscale)
    );

/***
 *      _        _____    ______      __                     _____   _                                       _                 
 *     | |      |  __ \  |  ____|    / _|                   / ____| | |                                     (_)                
 *     | |      | |__) | | |__      | |_    ___    _ __    | (___   | |_   _ __    ___    __ _   _ __ ___    _   _ __     __ _ 
 *     | |      |  ___/  |  __|     |  _|  / _ \  | '__|    \___ \  | __| | '__|  / _ \  / _` | | '_ ` _ \  | | | '_ \   / _` |
 *     | |____  | |      | |        | |   | (_) | | |       ____) | | |_  | |    |  __/ | (_| | | | | | | | | | | | | | | (_| |
 *     |______| |_|      |_|        |_|    \___/  |_|      |_____/   \__| |_|     \___|  \__,_| |_| |_| |_| |_| |_| |_|  \__, |
 *                                                                                                                        __/ |
 *                                                                                                                       |___/ 
 */
 averager averager_phase_0(
    .i_clk(adc_clk),
    .i_data(PHASE_UNWRAPPER_phase_fullscale),
    .i_data_valid(PHASE_UNWRAPPER_valid),
    .o_data(AVERAGER_phase_fullscale_125kHz),
    .o_data_valid(AVERAGER_valid)
);

wire LPF_magnitude_0_valid;
wire signed [32-1:0]    LPF_magnitude_0;
cic_amplitude_streaming cic_amplitude_0 (
  .aclk(adc_clk),
  .s_axis_data_tdata(DSP_PHASE_MEASURE_magnitude),
  .s_axis_data_tvalid(DSP_PHASE_MEASURE_valid),
  .s_axis_data_tready(),
  .m_axis_data_tdata(LPF_magnitude_0),
  .m_axis_data_tvalid(LPF_magnitude_0_valid)
);
always @(posedge adc_clk) begin
    if(LPF_magnitude_0_valid) begin
        LPF_magnitude_0_always_valid <= LPF_magnitude_0;
    end
end

/***
 *      _____    _                               _____                   _                    _   _               
 *     |  __ \  | |                             / ____|                 | |                  | | | |              
 *     | |__) | | |__     __ _   ___    ___    | |        ___    _ __   | |_   _ __    ___   | | | |   ___   _ __ 
 *     |  ___/  | '_ \   / _` | / __|  / _ \   | |       / _ \  | '_ \  | __| | '__|  / _ \  | | | |  / _ \ | '__|
 *     | |      | | | | | (_| | \__ \ |  __/   | |____  | (_) | | | | | | |_  | |    | (_) | | | | | |  __/ | |   
 *     |_|      |_| |_|  \__,_| |___/  \___|    \_____|  \___/  |_| |_|  \__| |_|     \___/  |_| |_|  \___| |_|   
 *                                                                                                                
 *                                                                                                                
 */
wire signed [PHASE_RESOLUTION_UNWRAPPED_SATURATED+1-1:0] phase_error_signal;
wire signed [DDS_PHASE_WORD_WIDTH-1:0]    PHASE_CONTROLLER_phase;
wire                    PHASE_CONTROLLER_valid;
wire signed [46-1:0]    y0_debug; // todo: magic number
phase_controllerV2 #(
    .COEFF_WIDTH(CONTROLLER_COEFFICIENT_WIDTH),
    .COEFF_SCALE(CONTROLLER_COEFFICIENT_FRACTIONAL_DIGITS + (PHASE_RESOLUTION_360-DDS_PHASE_WORD_WIDTH)), // scale by the coefficients fractional digits AND convert 360°-unit of phase measurement to 360°-unit of DDS-chip
    .PHASE_ERROR_INPUT_WIDTH(PHASE_RESOLUTION_UNWRAPPED_SATURATED + 1) // +1 because error signal is (setpoint - measured value) => 1 additional bit needed
) phase_controllerV2_0(
    .i_clk(adc_clk),
    .i_enable(SC_phase_controller_enable),
    .i_valid(PHASE_UNWRAPPER_valid),
    .i_phase_error(phase_error_signal),
    .o_is_armed(PHASE_CONTROLLER_is_armed),
    .o_valid(PHASE_CONTROLLER_valid),
    .o_phase(PHASE_CONTROLLER_phase),
    .i_coefficient_updating(CPU_controller_coefficient_updating),
    .i_b0(CPU_controller_0_b0),
    .i_b1(CPU_controller_0_b1),
    .i_controller_phase_out_zero(CPU_controller_0_phase_out_zero),
    .o_y0_debug(y0_debug)
);
assign phase_error_signal = CPU_phase_controller_setpoint - PHASE_UNWRAPPER_phase_saturated;

ila_phase_controllerV2 ila_phase_controllerV2_0 ( // todo: ILA anpassen
	.clk(adc_clk),
	.probe0(PHASE_UNWRAPPER_phase_fullscale),
	.probe1(y0_debug),
	.probe2(PHASE_CONTROLLER_valid)
);



/***
 *      _____    _____     _____                _____     ___     ___    _____    ___  
 *     |  __ \  |  __ \   / ____|       /\     |  __ \   / _ \   / _ \  | ____|  / _ \ 
 *     | |  | | | |  | | | (___        /  \    | |  | | | (_) | | (_) | | |__   | (_) |
 *     | |  | | | |  | |  \___ \      / /\ \   | |  | |  \__, |  \__, | |___ \   \__, |
 *     | |__| | | |__| |  ____) |    / ____ \  | |__| |    / /     / /   ___) |    / / 
 *     |_____/  |_____/  |_____/    /_/    \_\ |_____/    /_/     /_/   |____/    /_/  
 *                                                                                     
 *                                                                                     
 */
wire [31:0] DDS_data_received;
wire [3:0]  DDS_sdio;
wire        DDS_scl;
wire        DDS_masterreset;
wire        DDS_ioupdate;

wire [DDS_FREQUENCY_WORD_WIDTH-1:0] aom_0_frequency;
wire [DDS_FREQUENCY_WORD_WIDTH-1:0] aom_1_frequency;
wire [DDS_PHASE_WORD_WIDTH-1:0] aom_0_phase;
wire [DDS_PHASE_WORD_WIDTH-1:0] aom_1_phase;

dds_AD9959 dds_AD9959_0(
  .i_clk(/*adc_clk*/dac_clk_2x), // todo: remove if 200 MHz doesn't work
  .i_enable (SC_dds_enable),
  .o_is_armed (DDS_is_armed),
  .o_data_received(DDS_data_received),
  .i_mixer_0_frequency_desired(CPU_mixer_0_local_oscillator_frequency),
  .i_mixer_1_frequency_desired(CPU_mixer_1_local_oscillator_frequency),
  .i_aom_0_frequency_desired(aom_0_frequency),
  .i_aom_1_frequency_desired(aom_1_frequency),
  .i_aom_0_phase_desired(aom_0_phase),
  .i_aom_1_phase_desired(aom_1_phase),
  .i_mixer_0_amplitude_desired(CPU_mixer_0_amplitude),
  .i_mixer_1_amplitude_desired(CPU_mixer_1_amplitude),
  .i_aom_0_amplitude_desired(CPU_aom_0_amplitude),
  .i_aom_1_amplitude_desired(CPU_aom_1_amplitude), 
  .o_error_read_write_mismatch(DDS_error_read_write_mismatch), 
  // AD9959 ports
  .io_sdio(DDS_sdio),
  .o_sclk(DDS_scl),
  .o_master_reset(DDS_masterreset),
  .o_ioupdate(DDS_ioupdate)
  );
  reg [14-1:0] aom_1_phase_stepped = 14'd0;
  reg phase_controller_valid_last;
  assign aom_0_frequency = (CPU_aom_0_frequency_debug != 32'd0) ? CPU_aom_0_frequency_debug : CPU_aom_0_frequency_offset;
  assign aom_1_frequency = (CPU_aom_1_frequency_debug != 32'd0) ? CPU_aom_1_frequency_debug : 32'd0 /*todo add phase controller output*/;
  assign aom_0_phase = (CPU_aom_0_phase_debug != 14'd0) ? CPU_aom_0_phase_debug : PHASE_CONTROLLER_phase;
  assign aom_1_phase = (CPU_aom_1_phase_debug != 14'd0) ? /*CPU_aom_1_phase_debug todo comment in*/aom_1_phase_stepped : 14'd0 /*todo add phase controller output*/;
  
  always @(posedge adc_clk) begin
    phase_controller_valid_last <= PHASE_CONTROLLER_valid;
    if(PHASE_CONTROLLER_valid && (phase_controller_valid_last == 1'b0)) begin
        aom_1_phase_stepped <= aom_1_phase_stepped + CPU_aom_1_phase_debug;
    end
  end

/***
 *      _____    _                            _     _                                    _                  
 *     |  __ \  (_)                   /\     | |   | |                                  | |                 
 *     | |  | |  _    __ _           /  \    | |_  | |_    ___   _ __    _   _    __ _  | |_    ___    _ __ 
 *     | |  | | | |  / _` |         / /\ \   | __| | __|  / _ \ | '_ \  | | | |  / _` | | __|  / _ \  | '__|
 *     | |__| | | | | (_| |  _     / ____ \  | |_  | |_  |  __/ | | | | | |_| | | (_| | | |_  | (_) | | |   
 *     |_____/  |_|  \__, | (_)   /_/    \_\  \__|  \__|  \___| |_| |_|  \__,_|  \__,_|  \__|  \___/  |_|   
 *                    __/ |                                                                                 
 *                   |___/                                                                                  
 */
wire DAT_latch_enable_0; //todo wohin mit diesen leitungen?
wire DAT_latch_enable_1;
wire DAT_scl;
wire DAT_data;

dat_DAT31A_SP dat_DAT31A_SP_0(
    .i_clk(adc_clk),
    .i_enable(SC_dat_enable),
    .i_attenuation_0(CPU_dat_0_attenuation),
    .i_attenuation_1(CPU_dat_1_attenuation),
    // DAT31A-SN+ ports
    .io_sdio(DAT_data), // todo rename if this works..o_sclk(),
    .o_sclk(DAT_scl), // todo mapping auf die extension connectors.
    .o_le0(DAT_latch_enable_0),
    .o_le1(DAT_latch_enable_1)
    );
    
    
/***
 *       _____                                _        
 *      / ____|                              (_)       
 *     | |  __    ___   _ __     ___   _ __   _    ___ 
 *     | | |_ |  / _ \ | '_ \   / _ \ | '__| | |  / __|
 *     | |__| | |  __/ | | | | |  __/ | |    | | | (__ 
 *      \_____|  \___| |_| |_|  \___| |_|    |_|  \___|
 *                                                     
 *                                                     
 */

reg PCB_led = 1'b0;
always @(posedge adc_clk) begin
//    if(aom_0_phase > 14'd100) begin
//        PCB_led <= 1'b1;
//    end
//    else begin 
//        PCB_led <= 1'b0;
//    end
    if(PHASE_UNWRAPPER_phase_saturated > 19'sd16384) begin
        PCB_led <= 1'b1;
    end
    else begin 
        PCB_led <= 1'b0;
    end
end


/***
 *      _____    _                                    _                                              _         
 *     |  __ \  (_)               /\                 (_)                                            | |        
 *     | |__) |  _   _ __        /  \     ___   ___   _    __ _   _ __    _ __ ___     ___   _ __   | |_   ___ 
 *     |  ___/  | | | '_ \      / /\ \   / __| / __| | |  / _` | | '_ \  | '_ ` _ \   / _ \ | '_ \  | __| / __|
 *     | |      | | | | | |    / ____ \  \__ \ \__ \ | | | (_| | | | | | | | | | | | |  __/ | | | | | |_  \__ \
 *     |_|      |_| |_| |_|   /_/    \_\ |___/ |___/ |_|  \__, | |_| |_| |_| |_| |_|  \___| |_| |_|  \__| |___/
 *                                                         __/ |                                               
 *                                                        |___/                                                
 */

/* // Pin mapping for prototyping layout with 44MK_0057a PCB and modified QuadDDS PCB.
//assign exp_p_io[0] = ;
//assign exp_n_io[0] = ;
//assign exp_p_io[1] = ;
//assign exp_n_io[1] = ;
//assign exp_p_io[2] = ;
//assign exp_n_io[2] = ;
//assign exp_p_io[3] = ;
//assign exp_n_io[3] = ; 
assign exp_p_io[4] = DDS_sdio[0];
assign exp_n_io[4] = DDS_sdio[1];
assign exp_p_io[5] = DDS_sdio[2];
assign exp_n_io[5] = DDS_sdio[3];
assign exp_p_io[6] = DDS_masterreset;
assign exp_n_io[6] = DDS_scl;
assign exp_p_io[7] = DDS_ioupdate;
*/
// Pin mapping for 44NK_0017_01A PCB
assign exp_p_io[0] = DAT_scl;
assign exp_n_io[0] = DAT_data;
assign exp_p_io[1] = DAT_latch_enable_0;
assign exp_n_io[1] = DAT_latch_enable_1;
assign exp_p_io[2] = PCB_led;
//assign exp_n_io[2] = ; unused
assign exp_p_io[3] = DDS_ioupdate;
assign exp_n_io[3] = DDS_scl; 
assign exp_p_io[4] = DDS_sdio[0];
assign exp_n_io[4] = DDS_sdio[1];
assign exp_p_io[5] = DDS_sdio[2];
assign exp_n_io[5] = DDS_sdio[3];
assign exp_p_io[6] = DDS_masterreset;
//assign exp_n_io[6] = DIO_a;
//assign exp_p_io[7] = DIO_b;
//assign exp_n_io[7] = DIO_c;

assign adc_clk_o = 2'b10;

assign dac_a = PHASE_UNWRAPPER_phase_saturated[PHASE_RESOLUTION_UNWRAPPED_SATURATED-1:PHASE_RESOLUTION_UNWRAPPED_SATURATED-14];
assign dac_b = {pll_locked, {13{1'b0}}};

endmodule: red_pitaya_top
