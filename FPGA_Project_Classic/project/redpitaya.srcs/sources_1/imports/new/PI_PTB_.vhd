----------------------------------------------------------------------------------
-- Company:  PTB
-- Engineer:  Andreas Noack
-- 
-- Create Date: 18.11.2020 08:44:19
-- Design Name: PID Module for the Frequency Counter PLL
-- Module Name: PID_PTB - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- Feedback filter for a PLL in the red pitaya frequency counter.
-- Dependencies: None
-- 
-- Revision:
-- Revision 0.01 - File Created and filled with ports
-- Additional Comments:
-- data in on every clock cycle.
-- No Output Limit for Integral
-- No PID Output Limit
--  https://www.embeddedrelated.com/showarticle/121.php
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;



entity PI_PTB is
generic(
    input_len  : integer := 32;
    output_len : integer := 48;
    P_scale    : integer :=  0;
    I_scale    : integer :=  5
);
Port ( 
    -- PL Connections
    CLK   : in std_logic;
    reset : in std_logic; -- active high.
    -- Data INput
    sensor_in : in  signed(input_len  - 1 downto 0);
    -- PI Controller Inputs
    set_point : in signed(input_len  - 1 downto 0);
    P_gain    : in unsigned(16-1 downto 0);
    I_gain    : in unsigned(16-1 downto 0);
    -- Output
    ctrl_sig  : out signed(output_len - 1 downto 0)

);
end PI_PTB;

architecture Behavioral of PI_PTB is

-- Internal Gain Registers
signal P_gain_reg    :  signed(17-1 downto 0) := (OTHERS =>'0');
signal I_gain_reg    :  signed(17-1 downto 0) := (OTHERS =>'0');
signal set_point_reg :  signed(input_len-1 downto 0) := (OTHERS =>'0');

signal error : signed(input_len-1 downto 0) := (OTHERS =>'0');

-- Intermediate Registers to hold Calculations.
signal Kp_reg   : signed(P_gain_reg'LENGTH + input_len - 1 downto 0 ) := (OTHERS =>'0');
signal Isum_reg : signed(I_gain_reg'LENGTH + input_len - 1 downto 0 ) := (OTHERS =>'0');

signal PID : signed(I_gain_reg'LENGTH + input_len - 1  downto 0 ) := (OTHERS =>'0');


constant maxi : unsigned(output_len-2 downto 0) := (others =>'1');
constant mini : unsigned(output_len-2 downto 0) := (others =>'0');

constant Max_Out : signed(output_len-1 downto 0):= signed( '0' & maxi);
constant Min_Out : signed(output_len-1 downto 0):= signed( '1' & mini);


begin

----------------------------
---- INPUT REGISTER ----
----------------------------
Register_Gains: process(CLK)
begin
if rising_Edge(CLK) then
    if reset = '1' then
        set_point_reg <= (OTHERS =>'0');
    else
        P_gain_reg    <= signed('0' & P_gain);
        I_gain_reg    <= signed('0' & I_gain);
        set_point_reg <= set_point;
        
    end if;
end if;
end process;



----------------------------
---- 1st Clock Cycle ----
----------------------------

error_calc: process(CLK)
begin
if rising_Edge(CLK) then
    if reset = '1' then
        error <= (OTHERS =>'0');
    else
        error <= set_point_reg - sensor_in; -- cannot overflow as set_point should be 0...
    end if;
end if;
end process;

 
----------------------------
---- 2nd Clock Cycle ----
----------------------------
Kp_calc: process(CLK)

begin
if rising_Edge(CLK) then
    if reset = '1' then
        Kp_reg <= (OTHERS =>'0');
    else
        Kp_reg <= shift_right(error * P_gain_reg,P_scale); -- cannot overflow...
    end if;
end if;
end process;




Ki_calc: process(CLK)
begin
if rising_Edge(CLK) then
    if reset = '1' then
        Isum_reg <= (OTHERS =>'0');
    else
        Isum_reg <= Isum_reg +  shift_right(error * I_gain_reg,I_scale); -- Can this overflow?
    end if;
end if;
end process;



----------------------------
---- 3rd Clock Cycle ----
----------------------------
PIDSum: process(CLK)

begin
if rising_Edge(CLK) then
    if reset = '1' then
--      PID <= (OTHERS =>'0');
    else
--      PID <= Kp_reg + Isum_reg;
    end if;
end if;
end process;

PID <= Kp_reg + Isum_reg;
ctrl_sig <= PID(PID'LENGTH-1 downto (PID'LENGTH-output_len) );

end Behavioral;
