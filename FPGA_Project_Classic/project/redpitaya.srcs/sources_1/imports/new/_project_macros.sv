//fold Macros for Red Pitaya Bus transfer
/* 
 Define Variables for bus transfer like this:

// Available on Red Pitaya Bus and accessible via C-Code running under Linux.
logic           [ 8-1: 0] ramp_amplitude;  localparam MEMLOC_ramp_amplitude    = 20'h00;

// When to use which macro: 
// if (sys_wen) begin
    `sysbus_bus_to_var_macro(Value_a_MEMLOC, Value_a);

// casez (sys_addr[19:0])
    `sysbus_var_to_bus_macro(Value_a_MEMLOC, Value_a)


 */

//rot_enc_1_count_signed       ; localparam MEMLOC_rot_enc_1_count_signed      = 20'h00;

// TODO 


// `define sysbus_MEMLOC_variable(NAME, MEMORY_POSITION)  NAME ; localparam MEMLOC_NAME = 20'(MEMORY_POSITION*4);



`define sysbus_macro_variable(NAME, MEMORY_POSITION)  localparam MEMLOC_``NAME = MEMORY_POSITION;

`define sysbus_bus_to_var_macro(ADDRESS, DATA)  if (sys_addr[19:0]==ADDRESS)    DATA <= sys_wdata[32-1:0] ;
`define sysbus_var_to_bus_macro(ADDRESS, DATA)   ADDRESS : begin sys_ack <= sys_en;  sys_rdata <= {DATA}  ; end 

`define sysbus_macro_bus_to_var(NAME)  if (sys_addr[19:0]==MEMLOC_``NAME)    NAME <= sys_wdata[32-1:0] ;
`define sysbus_macro_var_to_bus(NAME)  MEMLOC_``NAME : begin sys_ack <= sys_en;  sys_rdata <= {NAME}  ; end 


//~fold

localparam SIGNED_MAX_14BIT = 14'sh1FFF;
localparam SIGNED_MIN_14BIT = 14'sh3000;


//



//`endif // PROJECT_MACROS__SV
