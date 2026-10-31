// SPDX-FileCopyrightText: 2024 Physikalisch-Technische Bundesanstalt (PTB), German National Metrology Institute
// SPDX-License-Identifier: Apache-2.0


`timescale 1ns/1ps

module coincidence_counter_tb ();

  logic clk_100MHz = 0;
  logic clk_200MHz = 0;

  logic resetn;
  logic ce;
  
  logic   test_sig_1 = 0;
  logic   test_sig_2 = 0;


// main clk 100MHz
initial begin
    clk_100MHz <= 1'b0;
    #5;
    forever begin
      clk_100MHz <= ~clk_100MHz;
      #5;
    end
end


// main clk 200MHz
initial begin
    clk_200MHz <= 1'b0;
    #2.5;
    forever begin
      clk_200MHz <= ~clk_200MHz;
      #2.5;
    end
end


  initial begin
    test_sig_1 <= 1'b0;
    forever begin
      test_sig_1 <= 1;
      #10;
      test_sig_1 <= 0;
      #111;
    end
  end

  initial begin
    
    test_sig_2 <= 1'b0; 
    forever begin
      test_sig_2 <= 1;
      #10;
      test_sig_2 <= 0;
      #333;
    end
  end

 

  initial begin
    resetn <= 1'b0;
    #100;
    resetn <= 1'b1;
  end

  initial begin
    ce <= 1'b0;
    #10000
    forever begin
      ce <= 1'b1;
      #10
      ce <= 1'b0;
      #(10000-10);
    end
  end
  
////////////////////////////////////////////////////////////////////////////////
// Coincidence counter
////////////////////////////////////////////////////////////////////////////////


logic   [32-1: 0]   cnt_detector_1_fly=0; 
logic   [32-1: 0]   cnt_detector_1_100ms=0;  
logic   [32-1: 0]   cnt_detector_1_1s=0;   
logic   [32-1: 0]   cnt_detector_1_2s=0;   
logic   [32-1: 0]   cnt_detector_1_5s=0;  
logic   [32-1: 0]   cnt_detector_1_10s=0; 

logic   [32-1: 0]   cnt_detector_2_fly=0;
logic   [32-1: 0]   cnt_detector_2_100ms=0;
logic   [32-1: 0]   cnt_detector_2_1s=0; 
logic   [32-1: 0]   cnt_detector_2_2s=0; 
logic   [32-1: 0]   cnt_detector_2_5s=0; 
logic   [32-1: 0]   cnt_detector_2_10s=0;

logic   [32-1: 0]   cnt_channel_1_fly=0; 
logic   [32-1: 0]   cnt_channel_1_100ms=0;
logic   [32-1: 0]   cnt_channel_1_1s=0; 
logic   [32-1: 0]   cnt_channel_1_2s=0;  
logic   [32-1: 0]   cnt_channel_1_5s=0;  
logic   [32-1: 0]   cnt_channel_1_10s=0;  
                    


coincidence_counter co_counter (
    // inputs
    .clk_200MHz                ( clk_200MHz ),  // main clk (200MHz)
    .clk_125MHz                (  ),  
    .clk_100MHz                ( clk_100MHz ),  
    
    .rstn_i               ( 1'b1),
    .detector_1_i         ( test_sig_1 ),  
    .detector_2_i         ( test_sig_2 ),
//    .detector_3_i         (  ),  
//    .detector_4_i         (  ),
    
    // outputs
    .cnt_detector_1_fly     (cnt_detector_1_fly), 
    .cnt_detector_1_100ms   (cnt_detector_1_100ms),
    .cnt_detector_1_1s      (cnt_detector_1_1s),  
    .cnt_detector_1_2s      (cnt_detector_1_2s),  
    .cnt_detector_1_5s      (cnt_detector_1_5s),  
    .cnt_detector_1_10s     (cnt_detector_1_10s), 
                        
    .cnt_detector_2_fly     (cnt_detector_2_fly), 
    .cnt_detector_2_100ms   (cnt_detector_2_100ms),
    .cnt_detector_2_1s      (cnt_detector_2_1s),  
    .cnt_detector_2_2s      (cnt_detector_2_2s),  
    .cnt_detector_2_5s      (cnt_detector_2_5s),  
    .cnt_detector_2_10s     (cnt_detector_2_10s), 
                        
    .cnt_channel_1_fly(     cnt_channel_1_fly),  
    .cnt_channel_1_100ms    (cnt_channel_1_100ms),
    .cnt_channel_1_1s       (cnt_channel_1_1s),   
    .cnt_channel_1_2s       (cnt_channel_1_2s),   
    .cnt_channel_1_5s       (cnt_channel_1_5s),   
    .cnt_channel_1_10s      (cnt_channel_1_10s)  
    
    
      // System bus
//  .sys_addr      (sys[1].addr ),
//  .sys_wdata     (sys[1].wdata),
//  .sys_wen       (sys[1].wen  ),
//  .sys_ren       (sys[1].ren  ),
//  .sys_rdata     (sys[1].rdata),
//  .sys_err       (sys[1].err  ),
//  .sys_ack       (sys[1].ack  )
);



endmodule
