-- SPDX-FileCopyrightText: 2024 Physikalisch-Technische Bundesanstalt (PTB), German National Metrology Institute
-- SPDX-License-Identifier: Apache-2.0

----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 21.10.2020 11:06:43
-- Design Name: 
-- Module Name: LAvgModule - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- The module calculates the lambda-average of the input data stream "data_in". A new sample is available at the input at the clock frequency "CLK".
-- The module averages the number of samples given by "samples_cnt". 
-- When a new value has been generated "data_out" is updated and "data_out_vld" becomes high for one clock cycle. This can be used as an interrupt
-- The output has to be scaled by the sample_cnt^2! This should be done on the CPU.


-- Advantage
-- All Averaging done on FPGA. Simpler Code Maintenance.
-- Input of this module is a complete tuning word (not the last 32 bits). No Addition etc. required.
--  More ressource efficient than previous implementation. Why? Utilisation of buffer registers, multiplier core. Not putting all in a signle process.
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity LAvgModule is

  Port (
    CLK                 : in std_logic;
    reset               : in std_logic;
    data_valid          : out std_logic;
    data_in             : in unsigned(48-1 downto 0);
    
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

architecture Behavioral of LAvgModule is

--signal data_in_Reg : unsigned(data_in'LENGTH-1 downto 0)     := (OTHERS =>'0');
signal reset_newAVGValue : std_logic := '0';
------------------------------------
---- Lambda Average Module 1 ----
------------------------------------

signal inputdata_reg1   : unsigned(data_in'LENGTH-1 downto 0)     := (OTHERS =>'0');
signal sampleToAverage1 : unsigned(27-1 downto 0) :=to_unsigned(1000,27);--(OTHERS =>'0');
signal reset_i1         : std_logic := '0';
signal LAvg_out1        : unsigned(data_in'LENGTH+27+27-1 downto 0) := (OTHERS =>'0');
signal LAvg_out_vld1    : std_logic := '0';


------------------------------------
---- Lambda Average Module 2 ----
------------------------------------

signal inputdata_reg2   : unsigned(data_in'LENGTH-1 downto 0)     := (OTHERS =>'0');
signal sampleToAverage2 : unsigned(27-1 downto 0) :=to_unsigned(1000,27);--(OTHERS =>'0');
signal reset_i2         : std_logic := '1';
signal LAvg_out2        : unsigned(data_in'LENGTH + 27 + 27-1 downto 0) := (OTHERS =>'0');
signal LAvg_out_vld2    : std_logic;

--  output register
signal data_out_reg     :  unsigned(data_in'LENGTH + 27 + 27-1 downto 0)  := (OTHERS =>'0');
signal data_out_vld_reg  : std_logic := '0';

------------------------------------------------
---- Offset for both averaging modules  ----
------------------------------------------------
signal coutner_delay_reset : unsigned(27-1 downto 0) := (OTHERS =>'0');



------------------------------------------------
---- FPGA Buffer  ----
------------------------------------------------
constant samplestoStore : integer  := 5;  -- total of 16, 2 to the power of samplestoStore.
constant AddrBits       : integer  := samplestoStore + 2; -- + 2 because we require 4x width to store 128  bits of data into 4x32 bits of word length 
constant RAM_Width      : integer  := 32;

-- Define BRAM Memory.
type BRAM is array (0 to 2**AddrBits - 1) of std_logic_vector(RAM_Width-1 downto 0);

signal mem_bram  : BRAM                            := (OTHERS => (OTHERS =>'0') );
signal addr_bram : unsigned(AddrBits-1   downto 0) := (OTHERS =>'0');


------------------------------------------------
---- System Bus Communication  ----
------------------------------------------------
signal sys_en : std_logic:='0';


------------
begin ----
------------

----------------------------------------------------------------------------------------------------
---- REGISTER INPUT ----
----------------------------------------------------------------------------------------------------

REGIN1: process(CLK)
begin
if rising_edge(CLK) then

    reset_i1         <= reset;
    inputdata_reg1   <= data_in;

end if;
end process;

REGIN2: process(CLK)
begin
if rising_edge(CLK) then

    inputdata_reg2   <= data_in;

end if;
end process;


----------------------------------------------------------------------------------------------------
---- Offset Calculation for 2nd Lambda Averaging Module  ----
----------------------------------------------------------------------------------------------------
OFFSET_2ndLAVG: process(CLK)
begin
if rising_edge(CLK) then
    if reset_i1 = '0' and reset_newAVGValue = '0' then
    
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
---- Update Output  ----
----------------------------------------------------------------------------------------------------
OutputREG: process(CLK)
begin
if rising_edge(CLK) then

    if LAvg_out_vld1 = '1' then
        data_out_reg        <= LAvg_out1;
        data_out_vld_reg    <= '1';
        data_valid          <= '1';
    elsif  LAvg_out_vld2 = '1' then
        data_out_reg        <= LAvg_out2;
        data_out_vld_reg    <= '1';
        data_valid          <= '1';
    else -- keep current data_out while no new sample has been generated.
       -- data_out     <= (OTHERS =>'0');
        data_out_vld_reg    <= '0';
        data_valid          <= '0';
    end if;
    
end if;
end process;

-----------------------------------------------------------------------------------
----  System bus Connections ----
-----------------------------------------------------------------------------------

UpdateLocalRAM: process(CLK)
begin
if rising_edge(CLK) then
if reset = '0' then 
    
    if data_out_vld_reg = '1' then
        
        mem_bram(to_integer(addr_bram+0)) <= std_logic_vector(resize(data_out_reg(102-1 downto 96),32));
        mem_bram(to_integer(addr_bram+1)) <= std_logic_vector(data_out_reg(96-1 downto 64));
        mem_bram(to_integer(addr_bram+2)) <= std_logic_vector(data_out_reg(64-1 downto 32));
        mem_bram(to_integer(addr_bram+3)) <= std_logic_vector(data_out_reg(32-1 downto  0));
        addr_bram                         <= resize(addr_bram + 4,addr_bram'LENGTH);
        
    end if;
else
    addr_bram <= (OTHERS => '0');
end if;
end if;
end process;

--------------------------------------------
---- Read Request from BUS ----
--------------------------------------------
sys_en <= sys_wen  or sys_ren;
ReadRegs: process(CLK)
begin
if rising_edge(CLK) then
    sys_ack <=  sys_en;
    sys_err <='0';
    case sys_addr(19 downto 0) is
    
       when x"02000" => sys_rdata <= std_logic_vector(resize(addr_bram,sys_rdata'LENGTH));
       when x"03000" => sys_rdata <= std_logic_vector(resize(sampleToAverage1,sys_rdata'LENGTH));
       when others   => sys_rdata <= std_logic_vector( mem_bram(to_integer( 
                                                            shift_right(
                                                                    unsigned( sys_addr(19 downto 0) ) 
                                                            ,2) 
                                                        )) 
                                                      ); 
    end case;
end if;
end process;




--------------------------------------------
---- WRITE REQUEST FROM BUS ----
--------------------------------------------
WriteToRegs: process(CLK)
begin
if rising_edge(CLK) then
--if reset = '1' then
--     sampleToAverage1 <=  (others =>'0');
--     sampleToAverage2 <=  (others =>'0');
-- else
      if sys_wen = '1' then
      
          case sys_addr(19 downto 0) is
          when  x"03000" =>
            sampleToAverage1 <= unsigned(sys_wdata(27-1 downto 0)) ;
            sampleToAverage2 <= unsigned(sys_wdata(27-1 downto 0)) ;
            reset_newAVGValue <= '1';
          when others =>
          end case;
      else 
          reset_newAVGValue <= '0';
      end if;

--end if;
end if;
end process;



end Behavioral;
