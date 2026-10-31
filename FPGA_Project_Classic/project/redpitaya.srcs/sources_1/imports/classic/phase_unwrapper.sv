// SPDX-FileCopyrightText: 2024 Physikalisch-Technische Bundesanstalt (PTB), German National Metrology Institute
// SPDX-License-Identifier: Apache-2.0


//###############################################################################################################
//###############################################################################################################


module phase_unwrapper #(
    parameter WIDTH_OF_PHASE_INPUT = 16,
    parameter WIDTH_OF_FULLSCALE_PHASE_OUTPUT = 64,
    parameter WIDTH_OF_SATURATED_PHASE_OUTPUT = 32,
    parameter POSITIVE_SATURATION_LIMIT = $signed({1'b0, {WIDTH_OF_SATURATED_PHASE_OUTPUT-1{1'b1}}}),
    parameter NEGATIVE_SATURATION_LIMIT = $signed({1'b1, {WIDTH_OF_SATURATED_PHASE_OUTPUT-1{1'b0}}})
)(
    input i_clk,
    input i_set_phase_unwrapped_zero_trigger,
    input i_phase_valid,
    input signed [16-1:0] i_phase,
    output reg signed [16-1:0] phase_difference = 0,
    output reg o_valid = 1'd0,
    output reg o_unwrapping_risk_of_overflow = 1'd0, // the internal unwrapping register is near to overflow. Unwrapping in direction of overflow is prevented. Output correctness can't be guaranteed.
    output reg signed [WIDTH_OF_SATURATED_PHASE_OUTPUT-1:0] o_phase_unwrapped_saturated = {WIDTH_OF_SATURATED_PHASE_OUTPUT{1'b0}},
    output wire signed [64-1:0] o_phase_unwrapped_fullscale
    );
    
    reg signed [16-1:0] phase_last = 0;
    reg signed [64-1:0] phase_unwrapped_internal = 0;
    reg set_phase_unwrapped_zero_last = 1'b0;
    
    localparam signed [WIDTH_OF_FULLSCALE_PHASE_OUTPUT-1:0] // max or min value of the unwrappers integrator before overflow occurs
        MAX_POSITIVE_UNWRAPPER_VALUE = $signed({1'b0,{WIDTH_OF_FULLSCALE_PHASE_OUTPUT-1{1'b1}}}),
        MAX_NEGATIVE_UNWRAPPER_VALUE = $signed({1'b1,{WIDTH_OF_FULLSCALE_PHASE_OUTPUT-1{1'b0}}});
    
    localparam signed [WIDTH_OF_PHASE_INPUT-1:0] // max or min change of phase to be expected => these values shouldn't lead to an integrator overflow.
        MAX_POSITIVE_INPUT_VALUE = $signed({1'b0,{WIDTH_OF_PHASE_INPUT-1{1'b1}}}),
        MAX_NEGATIVE_INPUT_VALUE = $signed({1'b1,{WIDTH_OF_PHASE_INPUT-1{1'b0}}});
    
    localparam signed [WIDTH_OF_FULLSCALE_PHASE_OUTPUT-1:0]
        POSITIVE_LIMIT_INTERNAL = MAX_POSITIVE_UNWRAPPER_VALUE - MAX_POSITIVE_INPUT_VALUE, // keep at least e.g. 32 bit distance to the overflow so that adding phase_difference to phase_unwrapped_internal is overflow-free always.
        NEGATIVE_LIMIT_INTERNAL = MAX_NEGATIVE_UNWRAPPER_VALUE - MAX_NEGATIVE_INPUT_VALUE;
       

    always @(posedge i_clk) begin
                
             // reset all registers
            if (i_set_phase_unwrapped_zero_trigger) begin     // wenn high -> reset...
                phase_unwrapped_internal <= {WIDTH_OF_FULLSCALE_PHASE_OUTPUT{1'b0}};            // 65 bit
                phase_last               <= {WIDTH_OF_PHASE_INPUT{1'b0}};                       // 32 bit
                phase_difference         <= {WIDTH_OF_PHASE_INPUT{1'b0}};                       // 32 bit
            end 
            else begin
                                 
                // INTERNAL SATURATION CONTROL
//                if(phase_unwrapped_internal > POSITIVE_LIMIT_INTERNAL) begin                    // POSITIVE_LIMIT_INTERNAL = 32 bit max
//                    phase_unwrapped_internal <= POSITIVE_LIMIT_INTERNAL;                        // auf 32 bit begrenzt
//                end
//                else if(phase_unwrapped_internal < NEGATIVE_LIMIT_INTERNAL) begin
//                    phase_unwrapped_internal <= NEGATIVE_LIMIT_INTERNAL;
//                end 
//                else begin
                
                // calculate the phase difference
                phase_difference <= i_phase - phase_last;       // 
                phase_last <= i_phase;
                
                // increment the phase
                phase_unwrapped_internal <= phase_unwrapped_internal + phase_difference;        // 64 bit <= 64 bit + 32 bit    
//                end
                
            end
    end
    
    assign o_phase_unwrapped_fullscale = phase_unwrapped_internal;              // beide 65 bit


endmodule

