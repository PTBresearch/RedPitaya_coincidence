// SPDX-FileCopyrightText: 2024 Physikalisch-Technische Bundesanstalt (PTB), German National Metrology Institute
// SPDX-License-Identifier: Apache-2.0

`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: PTB
// Engineer: M. Misera
// 
// Create Date:    12:57:28 01/03/2022
// Design Name: 
// Module Name:    pfc
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
module pfc(
input	logic               clock_i,
input	logic               reset_i,
input   logic               int_rst_i,
input   logic     [48-1:0]  ftw_cha_i,
input   logic     [48-1:0]  ftw_chb_i,
output  logic     [14-1:0]  error_o	
);

always @(posedge clock_i) begin
	if(reset_i==1'b0)begin

	end	else begin
        pi_in <= $signed(ftw_cha_i) - $signed(ftw_chb_i);
	end
end

////////////////////////////////////////////////////////////////////////////////
// PI servo
////////////////////////////////////////////////////////////////////////////////

logic   [ 32-1: 0]  set_sp  = 32'd0     ;
logic   [ 32-1: 0]  set_kp  = 32'd2000  ;
logic   [ 32-1: 0]  set_ki  = 32'd500   ;
logic   [ 32-1: 0]  pi_in               ;
logic   [ 48-1: 0]  pi_out              ;

PI_PTB pi_servo ( 
// PL Connections
.CLK                (clock_i),
.reset              (int_rst_i),      // active high.
// Data INput
.sensor_in          ($signed(pi_in)),  // input data 32bit
// PI Controller Inputs
.set_point          (set_sp),       // set point
.P_gain             (set_kp),       // Kp 32 bit
.I_gain             (set_ki),       // Ki 32 bit
// Output
.ctrl_sig           (pi_out)        // output data 48 bit
);
assign error_o = $signed(pi_out[48-1: 34]);

endmodule
