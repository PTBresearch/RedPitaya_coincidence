----------------------------------------------------------------------------------
-- Company:  PTB in Braunschweig
-- Engineer: Andreas Noack
-- 
-- Create Date: 21.10.2020 11:06:43
-- Design Name: LAmbda Averaging Module
-- Module Name: LAvgModule - Behavioral
-- Project Name: Red Pitaya Acquisition Tool
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.1 - File Created
-- Revision 1.0 - File Tested and published
-- Revision 1.1 - Added BRAM type array of std logig vector
-- Revision 1.2 - Replaced memory array with proper memory IP block.
-- Revision 1.3 - Replaced Memory Ring Buffer with simplified FIFO. 
-- Revision 1.4 - Added Pi Averaging Module.
-- Additional Comments:
-- The module calculates the lambda-average of the input data stream "data_in". A new sample is available at the input at the clock frequency "CLK".
-- The module averages the number of samples given by "samples_cnt". 
-- When a new value has been generated "data_out" is updated and "data_out_vld" becomes high for one clock cycle. This can be used as an interrupt
-- The output has to be scaled by the sample_cnt^2! This should be done on the CPU.


-- Advantage
-- All Averaging done on FPGA. Simpler Code Maintenance.
-- Input of this module is a complete tuning word (not the last 32 bits). No Addition etc. required.
-- More ressource efficient than previous implementation. Why? Utilisation of buffer registers, multiplier core. Not putting all in a signle process.
-- FIFO: Single Register Read, no pointer handling required.

-- Limitation: 

-- Can only average 2^27 samples. At a clock rate of 100 MHz, this is equivalent to 1.3 seconds.
-- Memory Write Process takes 4 Clock Cycles for one result. In other words, the minimum number of samples which can be averaged is to average is 2.
-- Memory Read Process takes 2 Clock Cycles to read 1/4 of complete number. So a total of 4 Request each at 2 CLock cycles are required to read a complete word (plus processing delay). 
-- Based on Memory Read delay, the minimum samples which can be averaged is 10ish? Let's probably say 20... Which is an output rate of 100 MHz/50 = 2 MHz... which is a lot I guess?
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity LAvgModule is

  Port (
    CLK          : in std_logic;
    reset        : in std_logic;
    data_in      : in unsigned(48-1 downto 0);
    
    ---- Connect Registers to PS ----
    sys_addr  : in std_logic_vector (32-1 downto 0);
    sys_wdata : in std_logic_vector (32-1 downto 0);
    sys_wen   : in std_logic;
    sys_ren   : in std_logic;
    sys_rdata : out std_logic_vector (32-1 downto 0);
    sys_err   : out std_logic;
    sys_ack   : out std_logic   
   );
end LAvgModule;

architecture Behavioral2 of LAvgModule is

--signal data_in_Reg : unsigned(data_in'LENGTH-1 downto 0)     := (OTHERS =>'0');
signal reset_newAVGValue : std_logic := '0';


---- PI Averaging ----

signal lambdaOrPi         : std_logic :='0';

signal PI_input_data_reg   : unsigned(data_in'LENGTH-1 downto 0)       := (OTHERS =>'0');
signal PI_sampletoAverage  : unsigned(27-1 downto 0)                   := to_unsigned(100,27); -- Init Values for 1s averaging.
signal PI_reset            : std_logic                                 := '0';
signal PI_out              : unsigned(data_in'LENGTH+27-1 downto 0) := (OTHERS =>'0');
signal PI_out_vld          : std_logic := '0';



------------------------------------
---- Lambda Average Module 1 ----
------------------------------------

signal inputdata_reg1   : unsigned(data_in'LENGTH-1 downto 0)       := (OTHERS =>'0');
signal sampleToAverage1 : unsigned(27-1 downto 0)                   := to_unsigned(100,27); -- Init Values for 1s averaging.
signal reset_i1         : std_logic                                 := '0';
signal LAvg_out1        : unsigned(data_in'LENGTH+27+27-1 downto 0) := (OTHERS =>'0');
signal LAvg_out_vld1    : std_logic := '0';


------------------------------------
---- Lambda Average Module 2 ----
------------------------------------

signal inputdata_reg2   : unsigned(data_in'LENGTH-1 downto 0)           := (OTHERS =>'0');
signal sampleToAverage2 : unsigned(27-1 downto 0)                       := to_unsigned(100,27);--(OTHERS =>'0');
signal reset_i2         : std_logic := '1';
signal LAvg_out2        : unsigned(data_in'LENGTH + 27 + 27-1 downto 0) := (OTHERS =>'0');
signal LAvg_out_vld2    : std_logic;

--  output register
signal data_out_reg     :  unsigned(data_in'LENGTH + 27 + 27-1 downto 0) := (OTHERS =>'0');
signal data_out_vld_reg  : std_logic := '0';

------------------------------------------------
---- Offset for both averaging modules  ----
------------------------------------------------
signal coutner_delay_reset : unsigned(27-1 downto 0) := (OTHERS =>'0');



------------------------------------------------
---- Sample Memory ----
------------------------------------------------

component  Buffer_FIFO 
  PORT (
    clk        : IN STD_LOGIC;
    srst       : IN STD_LOGIC;
    din        : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
    wr_en      : IN STD_LOGIC;
    rd_en      : IN STD_LOGIC;
    dout       : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    full       : OUT STD_LOGIC;
    empty      : OUT STD_LOGIC;
    data_count : OUT STD_LOGIC_VECTOR(14-1 DOWNTO 0)
  );
END component;

-- Memory Signals.
signal wr_en      : std_logic := '0'; -- write enable
signal din        : STD_LOGIC_VECTOR(31 DOWNTO 0) := (OTHERS =>'0'); -- data in
signal rd_en      : std_logic := '0'; -- read enable
signal dout       : STD_LOGIC_VECTOR(31 DOWNTO 0) := (OTHERS =>'0'); -- read out 1 clock latency
signal data_count : std_logic_Vector(14-1 downto 0)  := (OTHERS =>'0'); -- amount of data in FIFO
signal FIFO_reset : std_logic :='0';

-- State of sequential writes to memory 
type SM_UpdateMemory is (
IDLE,
UPDATE0,
UPDATE1,
UPDATE2,
UPDATE3
);

signal state_FIFO_Write : SM_UpdateMemory := IDLE;

-- State of FIFO read process
type SM_ReadFifp is (
SM_IDLE,
SM_DELAY,
SM_OUTPUT
);

signal state_FIFO_Read : SM_ReadFifp := SM_IDLE;


------------------------------------------------
---- System Bus Communication  ----
------------------------------------------------

signal sys_addr_reg  : std_logic_vector (20-1 downto 0) :=(OTHERS => '0');
signal sys_read_reg  : std_logic_vector (32-1 downto 0) :=(OTHERS => '0');


------------
begin ----
------------

----------------------------------------------------------------------------------------------------
---- REGISTER INPUT Signals. ----
----------------------------------------------------------------------------------------------------
-- (not time critical)
REGIN1: process(CLK)
begin
if rising_edge(CLK) then

    if reset_newAVGValue = '1' then
       FIFO_reset <= '1';
       reset_i1         <= '1';
       PI_reset         <= '1';
    else 
       reset_i1         <= reset;
       PI_reset         <= reset;
       FIFO_reset       <= reset;  -- CHANGE HERE!!!!
    end if;

   -- Register Data Input.
    inputdata_reg1   <= data_in;

end if;
end process;

REGIN2: process(CLK)
begin
if rising_edge(CLK) then
    inputdata_reg2   <= data_in;
end if;
end process;


InputPiReg: process(CLK)
begin
if rising_edge(CLK) then
    PI_input_data_reg   <= data_in;
end if;
end process;


----------------------------------------------------------------------------------------------------
---- Offset Calculation for 2nd Lambda Averaging Module Starting Point  ----
----------------------------------------------------------------------------------------------------
OFFSET_2ndLAVG: process(CLK)
begin
if rising_edge(CLK) then
    if reset_i1 = '0' then
    
        if coutner_delay_reset >= sampleToAverage2 -1 then
            reset_i2 <= '0';
        else
            reset_i2            <= '1';
            coutner_delay_reset <= coutner_delay_reset+1;
        end if;

    else
        reset_i2            <= '1';
        coutner_delay_reset <= (OTHERS =>'0');
    end if;
end if;
end process;


----------------------------------------------------------------------------------------------------
---- Lambda Averaging Module 1 ----
----------------------------------------------------------------------------------------------------
lambdaAVGFirst: entity work.LambdaAverage(Behavioral)
port map(
CLK          => CLK,
data_in      => inputdata_reg1,
samples_cnt  => sampleToAverage1,
reset        => reset_i1,
-- OUTPUT PORTS
data_out     => LAvg_out1,
data_out_vld => LAvg_out_vld1
);



----------------------------------------------------------------------------------------------------
---- Lambda Averaging Module 2 ----
----------------------------------------------------------------------------------------------------
lambdaAVGSecond: entity work.LambdaAverage(Behavioral)
port map(
CLK          => CLK,
data_in      => inputdata_reg2,
samples_cnt  => sampleToAverage2,
reset        => reset_i2,
-- OUTPUT PORTS
data_out     => LAvg_out2,
data_out_vld => LAvg_out_vld2
);


----------------------------------------------------------------------------------------------------
---- Pi Averaging Module ----
----------------------------------------------------------------------------------------------------

PIAverage: entity work.PI_Averaging(Behavioral)
generic map(
 in_len => data_in'LENGTH,
 avg_count_bitLen => 27
)
port map(
 CLK          => CLK,
 reset        => PI_reset,
 data_in      => PI_input_data_reg,
 avg_count    => PI_sampletoAverage,
 data_out     => PI_out,
 data_out_vld => PI_out_vld
);



----------------------------------------------------------------------------------------------------
---- Register and Combine Output ----
----------------------------------------------------------------------------------------------------

-- ADD PI OUTPUR REGISTER HERE!!!...
OutputREG: process(CLK)
begin
if rising_edge(CLK) then
    if lambdaOrPi = '0' then  -- PI Enabled
        if PI_out_vld = '1' then
            data_out_reg <= resize(PI_out,data_out_reg'LENGTH);
            data_out_vld_reg <= '1';
        else
             data_out_vld_reg <= '0';
        end if;
  
    else -- Lambda Averaging Enabled
        if LAvg_out_vld1 = '1' then
            data_out_reg <= LAvg_out1;
            data_out_vld_reg <= '1';
        elsif  LAvg_out_vld2 = '1' then
            data_out_reg <= LAvg_out2;
            data_out_vld_reg <= '1';
        else -- keep current data_out while no new sample has been generated.
           -- data_out     <= (OTHERS =>'0');
            data_out_vld_reg <= '0';
        end if;
    end if; 
end if;
end process;

-------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------
----  Memory Interface .----
-----------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------------------------

---- Memory Instantiation ----
Memory: Buffer_FIFO 
port map(
     clk       => CLK,
    srst       => FIFO_reset,
    din        => din,
    wr_en      => wr_en,
    rd_en      => rd_en,
    dout       => dout,
    data_count => data_count
  );


-----------------------------------------------------------------------------------
----  Memory Write ----
-----------------------------------------------------------------------------------
-- Sequential Write to memory. Started when new data has been calculated.
UpdateLocalRAM: process(CLK)
begin
if rising_edge(CLK) then
if reset = '0' then 
    
    case state_FIFO_Write is
    when IDLE => -- Write MSBs
        if data_out_vld_reg = '1' then
            state_FIFO_Write <= UPDATE0;
            wr_en       <= '1';
            din      <= std_logic_vector(resize(data_out_reg(102-1 downto 96),din'LENGTH)); 
        else
            wr_en       <=  '0';
            din      <= (OTHERS =>'0');
        end if;
    
    when UPDATE0 =>  -- Write MSBs - 1 
        state_FIFO_Write <= UPDATE1;
        wr_en       <= '1';
        din      <= std_logic_vector(data_out_reg(96-1 downto 64));
      
    when UPDATE1 => -- Write MSBs - 2
        state_FIFO_Write <= UPDATE2;
        wr_en       <= '1';
        din      <= std_logic_vector(data_out_reg(64-1 downto 32));
    
    when UPDATE2 => -- Write LSBs 
        state_FIFO_Write <= IDLE;
        wr_en       <= '1';
        din      <= std_logic_vector(data_out_reg(32-1 downto 0));
        
    when OTHERS =>
        state_FIFO_Write <= IDLE;
        wr_en       <= '0';
    end case;

else
    state_FIFO_Write   <= IDLE;
    wr_en       <= '0';
end if;
end if;
end process;

------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------
---- System Bus Communication. ----
--------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------



--------------------------------------------
---- READ REQUEST FROM BUS ----
--------------------------------------------
--sys_en <= sys_wen  or sys_ren;
-- Convert Read address into memory address...
ReadRequest: process(CLK)
begin
if rising_edge(CLK) then
 
        case state_FIFO_Read is
        when SM_IDLE => 
            sys_ack   <=  '0';
            sys_rdata <= (others =>'0');
            if sys_ren = '1' then -- only do when read request.
                state_FIFO_Read <= SM_DELAY;
                sys_addr_reg <= sys_addr(20-1 downto 0);  
                
                if sys_addr(20-1 downto 0)  =  x"02000" then -- only FIFO enable when someone wants to read from data from FIFO.
                    rd_en      <= '1'; -- enables read process from FIFO.
                else
                    rd_en      <= '0';  -- Default: Disable read process from FIFO.
                end if;
            end if;
         when SM_DELAY =>
            rd_en      <= '0';  -- Default: Disable read process from FIFO.
            state_FIFO_Read <= SM_OUTPUT;
         
        when SM_OUTPUT =>
            -- Decode Request.
            case sys_addr_reg(19 downto 0) is
              when x"01000" => 
                  sys_rdata <= std_logic_vector(resize(shift_right(unsigned(data_count),0),sys_rdata'LENGTH)); -- returns real Number of Samples in Buffer (1 = 4 bytes)
               when x"02000" =>  
                  sys_rdata <= std_logic_vector(resize(unsigned(dout),sys_rdata'LENGTH));
               when x"03000" => 
                  sys_rdata <= std_logic_vector(resize(unsigned(sampleToAverage1),sys_rdata'LENGTH));
               when x"04000" =>
                  sys_rdata(0)<= lambdaOrPi;
               when others  => 
                  sys_rdata <= x"12345678";
               
            end case;
            sys_ack   <=  '1'; -- output valid...
            -- Reset and Return to previous stage accepting a new read process...
            rd_en      <= '0'; 
            sys_addr_reg <= (OTHERS =>'0'); 
            state_FIFO_Read <= SM_IDLE;
        
        when OTHERS =>
            state_FIFO_Read <= SM_IDLE;
            rd_en      <= '0'; 
            sys_addr_reg <= (OTHERS =>'0'); 
            sys_ack   <=  '0'; -- output valid...
        end case;
       
end if;
end process;


--------------------------------------------
---- WRITE REQUEST FROM BUS ----
--------------------------------------------
WriteRequest: process(CLK)
begin
if rising_edge(CLK) then

      if sys_wen = '1' then
      
         case sys_addr(19 downto 0) is
         when  x"03000" =>
            sampleToAverage1 <= unsigned(sys_wdata(27-1 downto 0)) ;
            sampleToAverage2 <= unsigned(sys_wdata(27-1 downto 0)) ;
            PI_sampletoAverage <= unsigned(sys_wdata(27-1 downto 0)) ;
            sys_err <= '0';
            reset_newAVGValue <= '1';
         when x"04000" =>
            lambdaOrPi <= sys_wdata(0);
            reset_newAVGValue <= '1';
            sys_err <= '0';
         when others =>
            sys_err <= '1';
         end case;
      else 
         reset_newAVGValue <= '0';
      end if;
end if;
end process;


end Behavioral2;
