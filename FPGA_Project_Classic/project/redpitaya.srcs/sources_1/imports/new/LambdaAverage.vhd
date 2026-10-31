-- SPDX-FileCopyrightText: 2024 Physikalisch-Technische Bundesanstalt (PTB), German National Metrology Institute
-- SPDX-License-Identifier: Apache-2.0

----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 20.10.2020 14:56:21
-- Design Name: 
-- Module Name: LambdaAverage - Behavioral
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


-- EXPLAIN THIS MODULE HERE!!!
-- CLK : Clock Input
-- data_in : input data stream. A new sample is clocked in at the clock rate.
-- samples_cnt : the number of samples to average.
-- reset : resets the module.
-- data_out output data stream.
-- data_out_vld: goes high for one clock cycle when output data is valid.

----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity LambdaAverage is
Port (
-- INPUT PORTS
CLK          : in std_logic :='0';
data_in      : in unsigned(48-1 downto 0) := (OTHERS =>'0'); -- registererd
samples_cnt  : in unsigned(27-1 downto 0) := (OTHERS =>'0');  -- registered 
reset        : in std_logic := '0'; --active high reset
-- OUTPUT PORTS
data_out     : out unsigned(48+27+27 - 1 downto 0) := (OTHERS =>'0'); -- registered
data_out_vld : out std_logic :='0'

 );
end LambdaAverage;

architecture Behavioral of LambdaAverage is

---- CONSTANTS

constant dataLen  : integer := 48;
constant coeffLen : integer := 27;
constant pipe_len : integer := 8; -- Clock cycle delay until output of multiplier becomes valid.


signal sample_cnt_reg1 : unsigned(coeffLen -1 downto 0) := (OTHERS => '0');
signal sample_cnt_reg2 : unsigned(coeffLen -1 downto 0) := (OTHERS => '0');
signal reset_reg       : std_logic :='1';


signal data_out_reg     :  unsigned(48+27+27 - 1 downto 0) := (OTHERS =>'0'); -- registered
signal data_out_vld_reg :  std_logic :='0';

------------------------------------------
---- Weight Generator Components ----
------------------------------------------
type state_weight is
(
UP,
DOWN
);

signal status_weight : state_weight := UP;
signal weight  : unsigned(coeffLen-1 downto 0):= to_unsigned(1,coeffLen);


------------------------------------------
---- MULTIPLIER COMPONENT DECLARATION ----
------------------------------------------


component mult_gen_0 -- has 5 pipeline stages.
  PORT (
    CLK : IN STD_LOGIC;
    A   : IN STD_LOGIC_VECTOR(dataLen-1 DOWNTO 0);
    B   : IN STD_LOGIC_VECTOR(coeffLen-1 DOWNTO 0);
    P   : OUT STD_LOGIC_VECTOR(dataLen + coeffLen - 1 DOWNTO 0)
  );
end component;

signal multiA : std_logic_vector(dataLen-1 downto 0)            := (OTHERS =>'0');
signal multiB : std_logic_vector(coeffLen-1 downto 0)           := (OTHERS =>'0');
signal multiP : std_logic_vector(dataLen + coeffLen-1 downto 0) := (OTHERS =>'0');

-- Multiplier Status. Output becomes valid only after "pipe_len" clock cycles have passed.
type state_multi is
(
    PIPE_DELAY,
    MULTI_VALID
);

signal status_multi : state_multi := PIPE_DELAY;
-- counter to count elapsed clock cycles to change state_multi to valid.
signal counter_pipe_delay : unsigned(8-1 downto 0) := (OTHERS =>'0');


------------------------
---- SUMMING STAGE ----
------------------------
                            
signal summing   : unsigned(dataLen + coeffLen + coeffLen - 1 downto 0) := (OTHERS =>'0');
signal sum_index : unsigned(coeffLen+1 - 1 downto 0)                      := (OTHERS =>'0'); -- this has to go twice the distance of coeffLen!!


------------------------
begin
------------------------

----------------------------------------------------------------------------------------------------
---- REGISTER INPUT ----
----------------------------------------------------------------------------------------------------
inputfeed1: process(CLK)
begin
if rising_edge(CLK) then

    sample_cnt_reg1  <= samples_cnt;
    sample_cnt_reg2  <= samples_cnt;
    multiA           <= std_logic_vector(data_in);
    multiB           <= std_logic_vector(weight);
    reset_reg        <= reset;
    
end if;
end process;


------------------------------------------------------------------------------------------------------------
---- Multiplier Interface ----
------------------------------------------------------------------------------------------------------------

multiplier: mult_gen_0
port map(
    CLK => CLK,
    A   => multiA,
    B   => multiB,
    P   => multiP
);
    

-- INITIAL PIPELINE DELAY BEFORE MULTI BECOMES VALID
multiVLD : process(CLK)
begin
if rising_edge(CLK) then
   
if reset_reg = '0' then
    
    if counter_pipe_delay >= pipe_len then
        status_multi <= MULTI_VALID;
    else
        counter_pipe_delay <= counter_pipe_delay+1;
        status_multi <= PIPE_DELAY;
    end if;
  
else
    counter_pipe_delay <= (OTHERS =>'0');
    status_multi <= PIPE_DELAY;
end if; 
end if;
end process;



------------------------------------------------------------------------------------------------
---- SUMMING MODULE ----
------------------------------------------------------------------------------------------------

SUM: process(CLK)
begin
if rising_edge(CLK) then
   
if reset_reg = '0' then

   if status_multi = MULTI_VALID then -- start summing only when output of multiplier is valid.
       
       if sum_index >= 2 * sample_cnt_reg1-1 then
           sum_index <= (OTHERS => '0');
           summing   <= resize(unsigned(multiP),summing'LENGTH); 
           data_out_reg  <= summing;
           data_out_vld_reg <= '1';
       else
           sum_index <= sum_index + 1;
           summing   <= resize(summing + unsigned(multiP),summing'LENGTH);
           data_out_vld_reg <= '0';
       end if;
       
   else
       sum_index <= (OTHERS => '0');
       summing   <= resize(unsigned(multiP),summing'LENGTH); 
       data_out_vld_reg <= '0';
   end if;
   
else -- reset_reg active
   sum_index        <= (OTHERS => '0' );
   summing          <= (OTHERS => '0' );
   data_out_reg     <= (OTHERS => '0' );
   data_out_vld_reg <= '0';
end if;
   

end if;
end process;

process(CLK)
begin
if rising_edge(CLK) then
    data_out     <= data_out_reg;
    data_out_vld <= data_out_vld_reg;
end if;
end process;



------------------------------------------------------------------------------------------------
---- CREATE WEIGHTS ----
------------------------------------------------------------------------------------------------

increment:process(CLK)
begin
if rising_edge(CLK) then
if reset_reg = '0' then
    
        case status_weight is
            when  UP =>
                weight <= weight + 1;
            WHEN DOWN =>
                weight <= weight - 1;
        end case;

else
    weight <= to_unsigned(1,weight'LENGTH);
end if;

end if;
end process;

weightDirection: process(CLK)
begin

if rising_edge(CLK) then
if reset_reg = '0' then
    
    if weight >= sample_cnt_reg2-1 then
        status_weight <= DOWN;
    elsif weight = 1 and status_weight = DOWN then
        status_weight <= UP;
    end if;
 
else
    status_weight <= UP;
end if;
   
end if;
end process;





end Behavioral;
