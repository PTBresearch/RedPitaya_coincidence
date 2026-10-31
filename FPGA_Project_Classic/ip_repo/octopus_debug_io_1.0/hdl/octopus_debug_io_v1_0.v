// SPDX-FileCopyrightText: 2024 Physikalisch-Technische Bundesanstalt (PTB), German National Metrology Institute
// SPDX-License-Identifier: Apache-2.0


`timescale 1 ns / 1 ps

	module octopus_debug_io_v1_0 #
	(
		// Users to add parameters here

		// User parameters ends
		// Do not modify the parameters beyond this line


		// Parameters of Axi Slave Bus Interface S00_AXI
		parameter integer C_S00_AXI_DATA_WIDTH	= 32,
		parameter integer C_S00_AXI_ADDR_WIDTH	= 6
	)
	(
		// Users to add ports here
        input   [32-1: 0]   debug_0_i,
        input   [32-1: 0]   debug_1_i,
        input   [32-1: 0]   debug_2_i,
        input   [32-1: 0]   debug_3_i,
        input   [32-1: 0]   debug_4_i,
        input   [32-1: 0]   debug_5_i,
        input   [32-1: 0]   debug_6_i,
        input   [32-1: 0]   debug_7_i,
        input   [32-1: 0]   debug_8_i,
        input   [32-1: 0]   debug_9_i,
        input   [32-1: 0]   debug_10_i,
        input   [32-1: 0]   debug_11_i,
        input   [32-1: 0]   debug_12_i,
        input   [32-1: 0]   debug_13_i,
        input   [32-1: 0]   debug_14_i,
        input   [32-1: 0]   debug_15_i,
		
        output   [32-1: 0]   debug_0_o,
        output   [32-1: 0]   debug_1_o,
        output   [32-1: 0]   debug_2_o,
        output   [32-1: 0]   debug_3_o,
        output   [32-1: 0]   debug_4_o,
        output   [32-1: 0]   debug_5_o,
        output   [32-1: 0]   debug_6_o,
        output   [32-1: 0]   debug_7_o,
        output   [32-1: 0]   debug_8_o,
        output   [32-1: 0]   debug_9_o,
        output   [32-1: 0]   debug_10_o,
        output   [32-1: 0]   debug_11_o,
        output   [32-1: 0]   debug_12_o,
        output   [32-1: 0]   debug_13_o,
        output   [32-1: 0]   debug_14_o,
        output   [32-1: 0]   debug_15_o,

		// User ports ends
		// Do not modify the ports beyond this line


		// Ports of Axi Slave Bus Interface S00_AXI
		input wire  s00_axi_aclk,
		input wire  s00_axi_aresetn,
		input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_awaddr,
		input wire [2 : 0] s00_axi_awprot,
		input wire  s00_axi_awvalid,
		output wire  s00_axi_awready,
		input wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_wdata,
		input wire [(C_S00_AXI_DATA_WIDTH/8)-1 : 0] s00_axi_wstrb,
		input wire  s00_axi_wvalid,
		output wire  s00_axi_wready,
		output wire [1 : 0] s00_axi_bresp,
		output wire  s00_axi_bvalid,
		input wire  s00_axi_bready,
		input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_araddr,
		input wire [2 : 0] s00_axi_arprot,
		input wire  s00_axi_arvalid,
		output wire  s00_axi_arready,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_rdata,
		output wire [1 : 0] s00_axi_rresp,
		output wire  s00_axi_rvalid,
		input wire  s00_axi_rready
	);
// Instantiation of Axi Bus Interface S00_AXI
	octopus_debug_io_v1_0_S00_AXI # ( 
		.C_S_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
		.C_S_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH)
	) octopus_debug_io_v1_0_S00_AXI_inst (
		.S_AXI_ACLK(s00_axi_aclk),
		.S_AXI_ARESETN(s00_axi_aresetn),
		.S_AXI_AWADDR(s00_axi_awaddr),
		.S_AXI_AWPROT(s00_axi_awprot),
		.S_AXI_AWVALID(s00_axi_awvalid),
		.S_AXI_AWREADY(s00_axi_awready),
		.S_AXI_WDATA(s00_axi_wdata),
		.S_AXI_WSTRB(s00_axi_wstrb),
		.S_AXI_WVALID(s00_axi_wvalid),
		.S_AXI_WREADY(s00_axi_wready),
		.S_AXI_BRESP(s00_axi_bresp),
		.S_AXI_BVALID(s00_axi_bvalid),
		.S_AXI_BREADY(s00_axi_bready),
		.S_AXI_ARADDR(s00_axi_araddr),
		.S_AXI_ARPROT(s00_axi_arprot),
		.S_AXI_ARVALID(s00_axi_arvalid),
		.S_AXI_ARREADY(s00_axi_arready),
		.S_AXI_RDATA(s00_axi_rdata),
		.S_AXI_RRESP(s00_axi_rresp),
		.S_AXI_RVALID(s00_axi_rvalid),
		.S_AXI_RREADY(s00_axi_rready),
		
		.debug_0_i(debug_0_i),
		.debug_1_i(debug_1_i),
		.debug_2_i(debug_2_i),
		.debug_3_i(debug_3_i),
		.debug_4_i(debug_4_i),
		.debug_5_i(debug_5_i),
		.debug_6_i(debug_6_i),
		.debug_7_i(debug_7_i),
		.debug_8_i(debug_8_i),
		.debug_9_i(debug_9_i),
		.debug_10_i(debug_10_i),
		.debug_11_i(debug_11_i),
		.debug_12_i(debug_12_i),
		.debug_13_i(debug_13_i),
		.debug_14_i(debug_14_i),
		.debug_15_i(debug_15_i),
		
		.debug_0_o(debug_0_o),
		.debug_1_o(debug_1_o),
		.debug_2_o(debug_2_o),
		.debug_3_o(debug_3_o),
		.debug_4_o(debug_4_o),
		.debug_5_o(debug_5_o),
		.debug_6_o(debug_6_o),
		.debug_7_o(debug_7_o),
		.debug_8_o(debug_8_o),
		.debug_9_o(debug_9_o),
		.debug_10_o(debug_10_o),
		.debug_11_o(debug_11_o),
		.debug_12_o(debug_12_o),
		.debug_13_o(debug_13_o),
		.debug_14_o(debug_14_o),
		.debug_15_o(debug_15_o)
		
	);

	// Add user logic here

	// User logic ends

	endmodule
