// SPDX-FileCopyrightText: 2024 Physikalisch-Technische Bundesanstalt (PTB), German National Metrology Institute
// SPDX-License-Identifier: Apache-2.0

module signal_generator	(
						 clock_i,	           //100 MHz
						 ftw_i,                // frequency tuning word
						 sync_output_o,	       //logic square wave out
						 sigout_I_o,           //output both I and Q
						 sigout_Q_o
					     );		

input			    clock_i;
input   [48-1: 0]   ftw_i;
output	[10-1: 0]   sigout_I_o = 0;								
output	[10-1: 0]   sigout_Q_o = 0;	
output			    sync_output_o;							

logic	[10-1: 0]	sigout_I_o = 0;
logic	[10-1: 0]	sigout_Q_o = 0;
logic	[8-1:  0]	phase_I;
logic	[8-1:  0]	phase_Q;
logic		        sync_output;

//DDS variables
reg [48-1:0] 	phaseacc = 0;

assign	phase_I = phaseacc[48-1: 40];               // nur die obersten 8 bit wegen 8 bit LUT
assign	phase_Q = phaseacc[48-1: 40] + 10'd64; 	    // phase of Q is 90deg advanced from I

assign	sync_output_o = ~phaseacc[48-1];

sine_table SINE_TABLE_I(clock_i, phase_I, sigout_I_o);
sine_table SINE_TABLE_Q(clock_i, phase_Q, sigout_Q_o);

always @ (posedge clock_i)
begin
	phaseacc <= phaseacc + ftw_i;
end

endmodule