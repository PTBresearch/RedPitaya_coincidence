// SPDX-FileCopyrightText: 2024 Physikalisch-Technische Bundesanstalt (PTB), German National Metrology Institute
// SPDX-License-Identifier: Apache-2.0

`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 14.08.2022 18:48:46
// Design Name: 
// Module Name: simu
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module unwrapper_TB(
    
    );
logic   adc_clk                         = 0;
logic   [16-1: 0]   cordic_output       = 0;
logic   [16-1: 0]   phase_difference    = 0;
    
always adc_clk = #4 ~adc_clk;  // 100 MHz

//always @(posedge adc_clk) begin
//    cordic_output <= cordic_output + 1;
//end


    
 localparam PHASE_RESOLUTION_360 = 16; // xx Bit represent 360 Degree ATTENTION: when you change this value adapt dsp_phase_measure.sv correspondingly 
 localparam MAGNITUDE_RESOLUTION = PHASE_RESOLUTION_360; // equivalent to phase resolution because of the common cordic
 localparam PHASE_RESOLUTION_UNWRAPPED = 32; // Resolution of the phase after unwrapping (fullscale)
 localparam PHASE_RESOLUTION_UNWRAPPED_SATURATED = 19; // Resolution of the phase after unwrapping and saturation (for limited phase resolution for the controller calculations)
 
 
logic signed    [PHASE_RESOLUTION_360-1:0] DSP_PHASE_MEASURE_phase = 0;
logic signed    [PHASE_RESOLUTION_UNWRAPPED-1:0]            PHASE_UNWRAPPER_phase_fullscale;
logic signed    [PHASE_RESOLUTION_UNWRAPPED_SATURATED-1:0]  PHASE_UNWRAPPER_phase_saturated;
logic           set_phase_unwrapped_zero_trigger;


logic   [32-1: 0]   cnt = 0;

always @(posedge adc_clk) begin
    cnt <= cnt + 1;
    if(cnt < 32'h22222) begin
        DSP_PHASE_MEASURE_phase <= (DSP_PHASE_MEASURE_phase) + (1);
    end
    else begin
        DSP_PHASE_MEASURE_phase <= (DSP_PHASE_MEASURE_phase) - (1);
    end
end


phase_unwrapper_saturator 
    #(
    .WIDTH_OF_PHASE_INPUT (PHASE_RESOLUTION_360),
    .WIDTH_OF_FULLSCALE_PHASE_OUTPUT (PHASE_RESOLUTION_UNWRAPPED),
    .WIDTH_OF_SATURATED_PHASE_OUTPUT (PHASE_RESOLUTION_UNWRAPPED_SATURATED)
    ) 
    phase_unwrapper_saturator_0(
    .i_clk(adc_clk),
    .i_set_phase_unwrapped_zero_trigger(set_phase_unwrapped_zero_trigger),
    .i_phase_valid(1'b1),
    .i_phase(DSP_PHASE_MEASURE_phase),                                  // input from cordic 16 bit signed!
    .phase_difference(phase_difference),
    .o_valid(/*todo handle this?*/),
    .o_unwrapping_risk_of_overflow(/*todo handle this?*/),
    .o_phase_unwrapped_saturated(PHASE_UNWRAPPER_phase_saturated),      // phase error signal 19 bit
    .o_phase_unwrapped_fullscale(PHASE_UNWRAPPER_phase_fullscale)       // phase error signal 32 bit
    );
endmodule
