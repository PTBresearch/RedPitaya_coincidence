// SPDX-FileCopyrightText: 2024 Physikalisch-Technische Bundesanstalt (PTB), German National Metrology Institute
// SPDX-License-Identifier: Apache-2.0

`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 				PTB 4.3
// Engineer: 
// 
// Create Date:    		11/31/2021 
// Design Name: 
// Module Name:    		lowpass 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module lowpass(
input  logic clk_i,
input  logic reset,			//reset filter on reset high.
input  logic        [ 4-1: 0] filter_select_i, 
input  logic signed [28-1: 0]	signal_i,
output logic signed [28-1: 0]	signal_o
);

logic   signed  [28-1: 0]   filtered_lowp_8_o;
lowp8   LP_8(
.signal_in      (signal_i),
.signal_out     (filtered_lowp_8_o), 
.clock_in       (clk_i),
.reset          (1'b0)
);
logic   signed  [28-1: 0]   filtered_lowp_16_o;
lowp16   LP_16(
.signal_in      (signal_i),
.signal_out     (filtered_lowp_16_o), 
.clock_in       (clk_i),
.reset          (1'b0)
);
logic   signed  [28-1: 0]   filtered_lowp_32_o;
lowp32   LP_32(
.signal_in      (signal_i),
.signal_out     (filtered_lowp_32_o), 
.clock_in       (clk_i),
.reset          (1'b0)
);
logic   signed  [28-1: 0]   filtered_lowp_64_o;
lowp64   LP_64(
.signal_in      (signal_i),
.signal_out     (filtered_lowp_64_o), 
.clock_in       (clk_i),
.reset          (1'b0)
);
logic   signed  [28-1: 0]   filtered_lowp_128_o;
lowp128  LP_128(
.signal_in      (signal_i),
.signal_out     (filtered_lowp_128_o), 
.clock_in       (clk_i),
.reset          (1'b0)
);
logic   signed  [28-1: 0]   filtered_lowp_256_o;
lowp256  LP_256(
.signal_in      (signal_i),
.signal_out     (filtered_lowp_256_o), 
.clock_in       (clk_i),
.reset          (1'b0)
);


 always@(posedge clk_i)
  case (filter_select_i)
  4'd0: begin signal_o <= $signed(signal_i); 	                end // bypass
  4'd1: begin signal_o <= $signed(filtered_lowp_256_o);		    end // 0,5 MHz 
  4'd2: begin signal_o <= $signed(filtered_lowp_128_o); 		end // 1,0 MHz 
  4'd3: begin signal_o <= $signed(filtered_lowp_64_o );  		end // 1,5 MHz 
  4'd4: begin signal_o <= $signed(filtered_lowp_32_o );  		end // 2,0 MHz 
  4'd5: begin signal_o <= $signed(filtered_lowp_16_o );  		end // 2,5 MHz 
  4'd6: begin signal_o <= $signed(filtered_lowp_8_o  );  		end // 5,0 MHz 
 endcase



endmodule
