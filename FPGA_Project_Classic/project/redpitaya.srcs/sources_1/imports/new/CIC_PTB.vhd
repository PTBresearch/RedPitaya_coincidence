----------------------------------------------------------------------------------
-- Company: PTB
-- Engineer:  Andreas Noack
-- 
-- Create Date: 26.11.2020 08:04:25
-- Design Name: CIC Filter for iTracker
-- Module Name: CIC_PTB - Behavioral
-- Project Name: 
-- Target Devices: Red Pitaya (for now) but device independant...
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created and Code Added

-- Additional Comments:
--  R can be chosen freely. But ideally multiple of 2, so the gain can be adjusted more easily...
-- bit growth: Number of bits in the accumulator to not loose preicsion. N*log2(R*M) , here:  N=3, M=1
-- gain_rightshift: output gain adjust (N*R)^M
--

----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity CIC_Filter is
generic(
   inout_len       : integer := 32;
   R               : integer := 4;
   CIC_bit_growth  : integer := 9;
   gain_rightshift : integer := 4
);
Port (
   CLK          : in  std_logic;
   reset        : in  std_logic; -- active high
   data_in      : in  signed(inout_len-1 downto 0);
   data_out     : out signed(inout_len-1 downto 0);
   data_out_vld : out std_logic
);
end CIC_Filter;

architecture Behavioral of CIC_Filter is

signal integrator1 : signed(inout_len + CIC_bit_growth -1 downto 0) := (others =>'0');
signal integrator2 : signed(inout_len + CIC_bit_growth -1 downto 0) := (others =>'0');

signal comb1_prev : signed(inout_len + CIC_bit_growth -1 downto 0) :=(others =>'0');
signal comb1      : signed(inout_len + CIC_bit_growth -1 downto 0) :=(others =>'0');

signal comb2_prev : signed(inout_len + CIC_bit_growth -1 downto 0) :=(others =>'0');
signal comb2      : signed(inout_len + CIC_bit_growth -1 downto 0) :=(others =>'0');

signal index_ds: integer :=0;


begin

Main: process(CLK)
begin
if rising_edge(CLK) then
    if reset= '1' then
        integrator1 <= (others =>'0');
        integrator2 <= (others =>'0');
        comb1       <= (others =>'0');
        comb2       <= (others =>'0');
        comb1_prev  <= (others =>'0');
        comb2_prev  <= (others =>'0');
        data_out    <= (others =>'0');
    else
    
        --1st Cycle
        integrator1 <= integrator1 + data_in;
        --2nd Cycle             
        integrator2 <= integrator2 + integrator1;
        
        --3rd Cycle      
        if index_ds >= R-1 then
            comb1      <= integrator2 - comb1_prev;
            comb1_prev <= integrator2;
            comb2_prev <= comb1; 
            index_ds <= 0;
        else 
            index_ds <= index_ds + 1;
        end if;
    
        --4th Cycle    Calculate    
        --comb2 <= comb1 - comb2_prev;-- 5th Clock Cycle
        data_out <= resize(shift_right(comb1 - comb2_prev,Gain_rightshift),data_out'length);
     
    end if;




end if;

end process;


end Behavioral;
