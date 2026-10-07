----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 2026/08/06 10:47:34
-- Design Name: 
-- Module Name: tb_overflow_detector - tb
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
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity tb_overflow_detector is
end tb_overflow_detector;

architecture tb of tb_overflow_detector is

component overflow_detector is
    Port ( 
        a       : in std_logic;
        cin     : in std_logic;
        carry   : in std_logic;
        y       : out std_logic
      );
end component;

    signal a_tb         : std_logic := '0';
    signal cin_tb       : std_logic := '0';
    signal carry_tb     : std_logic := '0';
    signal y_tb         : std_logic;

begin

overflow_detector_i : overflow_detector
    port map(
        a           => a_tb,
        cin         => cin_tb,
        carry       => carry_tb,
        y           => y_tb
    );
    
process
begin

    wait for 10 ns;
    
    a_tb            <= '1';
    cin_tb          <= '0';
    carry_tb        <= '0';
    wait for 10 ns;
    
    a_tb            <= '1';
    cin_tb          <= '0';
    carry_tb        <= '1';
    wait for 10 ns;
    
    a_tb            <= '0';
    cin_tb          <= '1';
    carry_tb        <= '1';
    wait for 10 ns;
    
    a_tb            <= '0';
    cin_tb          <= '1';
    carry_tb        <= '0';
    wait;
end process;

end tb;
