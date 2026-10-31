// SPDX-FileCopyrightText: 2024 Physikalisch-Technische Bundesanstalt (PTB), German National Metrology Institute
// SPDX-License-Identifier: Apache-2.0



//
module coincidence_counter #(
  parameter RSZ = 16  // RAM size 2^RSZ      
)(
    // inputs
    input logic  clk_200MHz,         // main clk (200MHz)
    input logic  clk_125MHz,         // main clk (125MHz)
    input logic  clk_100MHz,         // main clk (100MHz)
    input logic  clk_10MHz,          // main clk (10MHz)
    input logic  rstn_i,
    input logic  detector_1_i,  
    input logic  detector_2_i,
    
      // outputs     
    output logic               detector_1_toggle_o = 0,
    output logic               detector_2_toggle_o = 0,
    output logic               channel_1_toggle_o = 0,
    output logic               detector_1_pulse_o,
    output logic               detector_2_pulse_o,
    output logic               channel_1_pulse_o,
    
    output logic   [32-1: 0]   cnt_detector_1_fly,
    output logic   [32-1: 0]   cnt_detector_1_100ms,
    output logic   [32-1: 0]   cnt_detector_1_1s,
    output logic   [32-1: 0]   cnt_detector_1_2s,
    output logic   [32-1: 0]   cnt_detector_1_5s,
    output logic   [32-1: 0]   cnt_detector_1_10s,
    
    output logic   [32-1: 0]   cnt_detector_2_fly,
    output logic   [32-1: 0]   cnt_detector_2_100ms,
    output logic   [32-1: 0]   cnt_detector_2_1s,
    output logic   [32-1: 0]   cnt_detector_2_2s,
    output logic   [32-1: 0]   cnt_detector_2_5s,
    output logic   [32-1: 0]   cnt_detector_2_10s,
    
    output logic   [32-1: 0]   cnt_channel_1_fly,
    output logic   [32-1: 0]   cnt_channel_1_100ms,
    output logic   [32-1: 0]   cnt_channel_1_1s,
    output logic   [32-1: 0]   cnt_channel_1_2s,
    output logic   [32-1: 0]   cnt_channel_1_5s,
    output logic   [32-1: 0]   cnt_channel_1_10s,

    // System bus
    input      [ 32-1: 0] sys_addr      ,  // bus saddress
    input      [ 32-1: 0] sys_wdata     ,  // bus write data
    input                 sys_wen       ,  // bus write enable
    input                 sys_ren       ,  // bus read enable
    output reg [ 32-1: 0] sys_rdata     ,  // bus read data
    output reg            sys_err       ,  // bus error indicator
    output reg            sys_ack          // bus acknowledge signal
);

////////////////////////////////////////////////////////////////////////////////
// Coincidence counter input signal buffering
////////////////////////////////////////////////////////////////////////////////
logic   detector_1_i_reg;
logic   detector_2_i_reg;

always @(posedge clk_200MHz)begin
    if(detector_1_i == 1)begin
        detector_1_i_reg <= 1;
    end else begin
        detector_1_i_reg <= 0;
    end
    if(detector_2_i == 1)begin
        detector_2_i_reg <= 1;
    end else begin
        detector_2_i_reg <= 0;
    end
end



////////////////////////////////////////////////////////////////////////////////
// Coincidence counter timer registers
////////////////////////////////////////////////////////////////////////////////
logic               cnt_rst;        // reset all counters
logic   [32-1: 0]   cnt_100ms=0;
logic   [32-1: 0]   cnt_1s=0;
logic   [32-1: 0]   cnt_2s=0;
logic   [32-1: 0]   cnt_5s=0;
logic   [32-1: 0]   cnt_10s=0;

// Buffer register

logic   [32-1: 0]   index_100ms;
logic   [32-1: 0]   index_1s;
logic   [32-1: 0]   index_2s;
logic   [32-1: 0]   index_5s;
logic   [32-1: 0]   index_10s;

logic   [32-1: 0]   cnt_detector_1_100ms_t0=0;
logic   [32-1: 0]   cnt_detector_1_1s_t0=0;
logic   [32-1: 0]   cnt_detector_1_2s_t0=0;
logic   [32-1: 0]   cnt_detector_1_5s_t0=0;
logic   [32-1: 0]   cnt_detector_1_10s_t0=0;

logic   [32-1: 0]   cnt_detector_2_100ms_t0=0;
logic   [32-1: 0]   cnt_detector_2_1s_t0=0;
logic   [32-1: 0]   cnt_detector_2_2s_t0=0;
logic   [32-1: 0]   cnt_detector_2_5s_t0=0;
logic   [32-1: 0]   cnt_detector_2_10s_t0=0;

logic   [32-1: 0]   cnt_channel_1_100ms_t0=0;
logic   [32-1: 0]   cnt_channel_1_1s_t0=0;
logic   [32-1: 0]   cnt_channel_1_2s_t0=0;
logic   [32-1: 0]   cnt_channel_1_5s_t0=0;
logic   [32-1: 0]   cnt_channel_1_10s_t0=0;



////////////////////////////////////////////////////////////////////////////////
// Coincidence counter management
////////////////////////////////////////////////////////////////////////////////

always @(posedge clk_200MHz)begin
        if(cnt_100ms < 32'd20000000)begin         // 100ms
            cnt_100ms   <= cnt_100ms + 1;
        end else begin
            cnt_100ms <= 0;
            index_100ms             <= index_100ms + 1; 
            cnt_detector_1_100ms_t0 <= cnt_detector_1_fly;
            cnt_detector_1_100ms    <= cnt_detector_1_fly - cnt_detector_1_100ms_t0;
            cnt_detector_2_100ms_t0 <= cnt_detector_2_fly;
            cnt_detector_2_100ms    <= cnt_detector_2_fly - cnt_detector_2_100ms_t0;
            cnt_channel_1_100ms_t0  <= cnt_channel_1_fly;
            cnt_channel_1_100ms     <= cnt_channel_1_fly  - cnt_channel_1_100ms_t0;
        end
end

always @(posedge clk_200MHz)begin
        if(cnt_1s   < 32'd200000000)begin        // 1s
            cnt_1s      <= cnt_1s + 1;
        end else begin
            cnt_1s      <= 0;
            index_1s                <= index_1s + 1;
            cnt_detector_1_1s_t0    <= cnt_detector_1_fly;
            cnt_detector_1_1s       <= cnt_detector_1_fly - cnt_detector_1_1s_t0;
            cnt_detector_2_1s_t0    <= cnt_detector_2_fly;
            cnt_detector_2_1s       <= cnt_detector_2_fly - cnt_detector_2_1s_t0;
            cnt_channel_1_1s_t0     <= cnt_channel_1_fly;
            cnt_channel_1_1s        <= cnt_channel_1_fly  - cnt_channel_1_1s_t0;
        end       
end        

always @(posedge clk_200MHz)begin
        if(cnt_2s   < 32'd400000000)begin        // 2s
            cnt_2s      <= cnt_2s + 1;
        end else begin
            cnt_2s      <= 0;
            index_2s                <= index_2s + 1;
            cnt_detector_1_2s_t0    <= cnt_detector_1_fly;
            cnt_detector_1_2s       <= cnt_detector_1_fly - cnt_detector_1_2s_t0;
            cnt_detector_2_2s_t0    <= cnt_detector_2_fly;
            cnt_detector_2_2s       <= cnt_detector_2_fly - cnt_detector_2_2s_t0;
            cnt_channel_1_2s_t0     <= cnt_channel_1_fly;
            cnt_channel_1_2s        <= cnt_channel_1_fly  - cnt_channel_1_2s_t0;
        end       
end        

always @(posedge clk_200MHz)begin
        if(cnt_5s   < 32'd1000000000)begin        // 5s
            cnt_5s      <= cnt_5s + 1;
        end else begin
            cnt_5s      <= 0;
            index_5s                <= index_5s + 1;
            cnt_detector_1_5s_t0    <= cnt_detector_1_fly;
            cnt_detector_1_5s       <= cnt_detector_1_fly - cnt_detector_1_5s_t0;
            cnt_detector_2_5s_t0    <= cnt_detector_2_fly;
            cnt_detector_2_5s       <= cnt_detector_2_fly - cnt_detector_2_5s_t0;
            cnt_channel_1_5s_t0     <= cnt_channel_1_fly;
            cnt_channel_1_5s        <= cnt_channel_1_fly  - cnt_channel_1_5s_t0;
        end       
end        
        
always @(posedge clk_200MHz)begin
        if(cnt_10s   < 32'd2000000000)begin        // 10s
            cnt_10s      <= cnt_10s + 1;
        end else begin
            cnt_10s      <= 0;
            index_10s                <= index_10s + 1;
            cnt_detector_1_10s_t0    <= cnt_detector_1_fly;
            cnt_detector_1_10s       <= cnt_detector_1_fly - cnt_detector_1_10s_t0;
            cnt_detector_2_10s_t0    <= cnt_detector_2_fly;
            cnt_detector_2_10s       <= cnt_detector_2_fly - cnt_detector_2_10s_t0;
            cnt_channel_1_10s_t0     <= cnt_channel_1_fly;
            cnt_channel_1_10s        <= cnt_channel_1_fly  - cnt_channel_1_10s_t0;
        end       
end        
       
        
////////////////////////////////////////////////////////////////////////////////
// Coincidence counter logic
////////////////////////////////////////////////////////////////////////////////
logic   [8-1: 0]    detector_1_event = 0;
logic   [8-1: 0]    detector_2_event = 0;
logic   [8-1: 0]    channel_1_event  = 0;


//########################################################################################
// only for testing....
//########################################################################################
//logic   [32-1: 0]   cnt_detector_1_fly_test = 0 ;
//logic   [32-1: 0]   counter = 0;

////slow clock
//always @(posedge clk_200MHz)begin
//    counter <= counter + 1;
//end

//always @(posedge counter[11])begin  // (/4096 ~48 kHz)
//    cnt_detector_1_fly_test <= cnt_detector_1_fly_test + 1;
//end
//########################################################################################

always @(posedge clk_200MHz)begin
//    if(cnt_rst)begin
//        cnt_detector_1_fly <= 0;
//    end else begin
        if(detector_1_event == 0)begin
            if(detector_1_i_reg == 1'b1)begin
                cnt_detector_1_fly  <= cnt_detector_1_fly + 1;
                detector_1_pulse_o  <= 1;
                detector_1_event    <= 5;                  
            end else begin             
                detector_1_pulse_o  <= 0;            
            end           
        end else begin
            detector_1_pulse_o      <= 0; 
            detector_1_event        <= detector_1_event -1;
        end
//    end
end

always @(posedge clk_200MHz)begin
//    if(cnt_rst)begin
//        cnt_detector_2_fly <= 0;
//    end else begin
        if(detector_2_event == 0)begin
            if(detector_2_i_reg == 1)begin
                cnt_detector_2_fly  <= cnt_detector_2_fly + 1;
                detector_2_pulse_o  <= 1;
                detector_2_event    <= 5;                  
            end else begin             
                detector_2_pulse_o  <= 0;            
            end           
        end else begin
            detector_2_pulse_o      <= 0;
            detector_2_event        <= detector_2_event -1;
        end
//    end
end

always @(posedge clk_200MHz)begin
//    if(cnt_rst)begin
//        cnt_channel_1_fly <= 0;
//    end else begin        
        if(channel_1_event == 0)begin
            if(detector_1_i_reg & detector_2_i_reg)begin
                cnt_channel_1_fly  <= cnt_channel_1_fly + 1;
                channel_1_pulse_o  <= 1;
                channel_1_event    <= 5;                  
            end else begin             
                channel_1_pulse_o  <= 0;            
            end           
        end else begin
            channel_1_pulse_o       <= 0;
            channel_1_event         <= channel_1_event -1;
        end
//    end
end


////////////////////////////////////////////////////////////////////////////////
//  System bus connection
////////////////////////////////////////////////////////////////////////////////

always @(posedge clk_125MHz)
if (rstn_i == 1'b0) begin

end else begin
   if (sys_wen) begin
      if (sys_addr[19:0]==20'h00)    cnt_rst              <= sys_wdata[1-1: 0] ;

            
   end
end



wire sys_en;
assign sys_en = sys_wen | sys_ren;

always @(posedge clk_125MHz)
if (rstn_i == 1'b0) begin
   sys_err <= 1'b0 ;
   sys_ack <= 1'b0 ;
end else begin
   sys_err <= 1'b0 ;

   casez (sys_addr[19:0])
//   20'h00000 : begin sys_ack <= sys_en;          sys_rdata <=   cnt_rst                          ; end 
     20'h00100 : begin sys_ack <= sys_en;          sys_rdata <=   cnt_detector_1_fly               ; end
     20'h00104 : begin sys_ack <= sys_en;          sys_rdata <=   cnt_detector_1_100ms             ; end
     20'h00108 : begin sys_ack <= sys_en;          sys_rdata <=   cnt_detector_1_1s                ; end
     20'h0010C : begin sys_ack <= sys_en;          sys_rdata <=   cnt_detector_1_2s                ; end
     20'h00110 : begin sys_ack <= sys_en;          sys_rdata <=   cnt_detector_1_5s                ; end
     20'h00114 : begin sys_ack <= sys_en;          sys_rdata <=   cnt_detector_1_10s               ; end
                                                                                                        
     20'h00200 : begin sys_ack <= sys_en;          sys_rdata <=   cnt_detector_2_fly               ; end
     20'h00204 : begin sys_ack <= sys_en;          sys_rdata <=   cnt_detector_2_100ms             ; end
     20'h00208 : begin sys_ack <= sys_en;          sys_rdata <=   cnt_detector_2_1s                ; end
     20'h0020C : begin sys_ack <= sys_en;          sys_rdata <=   cnt_detector_2_2s                ; end
     20'h00210 : begin sys_ack <= sys_en;          sys_rdata <=   cnt_detector_2_5s                ; end
     20'h00214 : begin sys_ack <= sys_en;          sys_rdata <=   cnt_detector_2_10s               ; end
                                                                                                 
     20'h00300 : begin sys_ack <= sys_en;          sys_rdata <=   cnt_channel_1_fly                ; end
     20'h00304 : begin sys_ack <= sys_en;          sys_rdata <=   cnt_channel_1_100ms              ; end
     20'h00308 : begin sys_ack <= sys_en;          sys_rdata <=   cnt_channel_1_1s                 ; end
     20'h0030C : begin sys_ack <= sys_en;          sys_rdata <=   cnt_channel_1_2s                 ; end
     20'h00310 : begin sys_ack <= sys_en;          sys_rdata <=   cnt_channel_1_5s                 ; end
     20'h00314 : begin sys_ack <= sys_en;          sys_rdata <=   cnt_channel_1_10s                ; end

     20'h00400 : begin sys_ack <= sys_en;          sys_rdata <=   index_100ms                      ; end
     20'h00404 : begin sys_ack <= sys_en;          sys_rdata <=   index_1s                         ; end
     20'h00408 : begin sys_ack <= sys_en;          sys_rdata <=   index_2s                         ; end
     20'h0040C : begin sys_ack <= sys_en;          sys_rdata <=   index_5s                         ; end
     20'h00410 : begin sys_ack <= sys_en;          sys_rdata <=   index_10s                        ; end
            
     default : begin sys_ack <= sys_en;            sys_rdata <=  32'h12345678                      ; end
   endcase
end

endmodule
