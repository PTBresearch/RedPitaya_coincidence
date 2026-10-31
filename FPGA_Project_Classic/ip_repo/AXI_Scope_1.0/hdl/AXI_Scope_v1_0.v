// SPDX-FileCopyrightText: 2024 Physikalisch-Technische Bundesanstalt (PTB), German National Metrology Institute
// SPDX-License-Identifier: Apache-2.0


`timescale 1 ns / 1 ps

	module AXI_Scope_v1_0 #
	(
		// Users to add parameters here

		// User parameters ends
		// Do not modify the parameters beyond this line


		// Parameters of Axi Slave Bus Interface S00_AXI
		parameter integer C_S00_AXI_DATA_WIDTH	= 32,
		parameter integer C_S00_AXI_ADDR_WIDTH	= 7
	)
	(
		// Users to add ports here

       input wire                      PL_CLOCK,    // clock            
       input wire                      PL_RESET_N,  // reset            
       input wire           [ 3-1:  0] CH_SELECT,   // Channel select   
                                                                        
       input wire   signed  [ 14-1: 0] adc_1_i,     // ADC data         
       input wire   signed  [ 14-1: 0] adc_2_i,     // ADC data         
       input wire   signed  [ 14-1: 0] adc_3_i,     // ADC data         
       input wire   signed  [ 14-1: 0] adc_4_i,     // ADC data         
       input wire   signed  [ 14-1: 0] adc_5_i,     // ADC data         
       input wire   signed  [ 14-1: 0] adc_6_i,     // ADC data         
       input wire   signed  [ 14-1: 0] adc_7_i,     // ADC data         
       input wire   signed  [ 14-1: 0] adc_8_i,     // ADC data         
                                                                        
       input wire   signed  [ 14-1: 0] nco_1_i,     // NCO data         
       input wire   signed  [ 14-1: 0] nco_2_i,     // NCO data         
       input wire   signed  [ 14-1: 0] nco_3_i,     // NCO data         
       input wire   signed  [ 14-1: 0] nco_4_i,     // NCO data         
       input wire   signed  [ 14-1: 0] nco_5_i,     // NCO data         
       input wire   signed  [ 14-1: 0] nco_6_i,     // NCO data         
       input wire   signed  [ 14-1: 0] nco_7_i,     // NCO data         
       input wire   signed  [ 14-1: 0] nco_8_i,     // NCO data         

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
	AXI_Scope_v1_0_S00_AXI # ( 
		.C_S_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
		.C_S_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH)
	) AXI_Scope_v1_0_S00_AXI_inst (
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
		
        .PL_CLOCK(PL_CLOCK),     // clock
        .PL_RESET_N(PL_RESET_N), // reset
        .CH_SELECT(CH_SELECT),   // Channel select
        
        .adc_1_i(adc_1_i),     // ADC data
        .adc_2_i(adc_2_i),     // ADC data
        .adc_3_i(adc_3_i),     // ADC data
        .adc_4_i(adc_4_i),     // ADC data
        .adc_5_i(adc_5_i),     // ADC data
        .adc_6_i(adc_6_i),     // ADC data
        .adc_7_i(adc_7_i),     // ADC data
        .adc_8_i(adc_8_i),     // ADC data
       
        .nco_1_i(nco_1_i),     // NCO data
        .nco_2_i(nco_2_i),     // NCO data
        .nco_3_i(nco_3_i),     // NCO data
        .nco_4_i(nco_4_i),     // NCO data
        .nco_5_i(nco_5_i),     // NCO data
        .nco_6_i(nco_6_i),     // NCO data
        .nco_7_i(nco_7_i),     // NCO data
        .nco_8_i(nco_8_i)     // NCO data		
	);

	// Add user logic here

	// User logic ends

	endmodule
