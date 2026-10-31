-- SPDX-FileCopyrightText: 2024 Physikalisch-Technische Bundesanstalt (PTB), German National Metrology Institute
-- SPDX-License-Identifier: Apache-2.0

----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 08.12.2020 13:21:45
-- Design Name: 
-- Module Name: PI_Averaging - Behavioral
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
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity PI_Averaging is
generic(
 in_len : integer :=32;
 avg_count_bitLen : integer :=27
);
 Port ( 
 CLK          : in std_logic;
 reset : in std_logic;
 data_in      : in unsigned(in_len-1 downto 0);
 avg_count    : in unsigned(avg_count_bitLen-1 downto 0);
 data_out     :  out unsigned(in_len + avg_count_bitLen -1 downto 0);
 data_out_vld : out std_logic 
 );
end PI_Averaging;

architecture Behavioral of PI_Averaging is

signal  avg_count_reg : unsigned(avg_count_bitLen-1 downto 0):= (OTHERS =>'0');
signal  data_in_reg   : unsigned(in_len-1 downto 0)          := (OTHERS =>'0');

signal accumulator    : unsigned(in_len + avg_count_bitLen -1 downto 0) := (OTHERS =>'0');
signal index          : unsigned(avg_count_bitLen-1 downto 0)           := (OTHERS =>'0');


begin

------------------------
---- INPUT REGISTER ----
------------------------
process(CLK) 
begin
if rising_edge(CLK) then
    if reset = '1' then
        avg_count_reg <= avg_count;
        data_in_reg   <= (OTHERS =>'0');
    else
        avg_count_reg <= avg_count;    
        data_in_reg   <= data_in;
    end if;

end if;
end process;

-----------------------------
---- Accumulator Summing ----
-----------------------------

main: process(CLK) 
begin
if rising_edge(CLK) then
if reset = '1' then
    accumulator <= (OTHERS =>'0');
else

    if index >=avg_count_reg - 1 then 
        accumulator <= resize(data_in_reg,accumulator'LENGTH);
        data_out     <= accumulator;
        data_out_vld <='1'; 
        
    else
        accumulator <= accumulator + data_in_reg;
        data_out_vld <='0';
    end if;
    
end if;
end if;
end process;

------------------------------------
---- Counter (Index) Generator -----
------------------------------------
Counter: process(CLK) 
begin
if rising_edge(CLK) then
if reset = '1' then
    index <= (OTHERS =>'0');
else
    if index >=avg_count_reg - 1 then 
        index <= (OTHERS =>'0');
    else
        index <= index + 1;
    end if;
    
end if;
end if;
end process;

end Behavioral;
