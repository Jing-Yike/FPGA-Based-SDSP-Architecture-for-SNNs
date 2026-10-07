----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 2026/08/06 10:45:24
-- Design Name: 
-- Module Name: tb_nbit_adder - tb
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

entity tb_nbit_adder is
end tb_nbit_adder;

architecture tb of tb_nbit_adder is

    constant w_WIDTH : integer := 8;
    
component nbit_adder is
    Port ( 
        a           : in std_logic_vector(w_WIDTH-1 downto 0);
        b           : in std_logic_vector(w_WIDTH-1 downto 0);
        cin         : in std_logic;
        sum         : out std_logic_vector(w_WIDTH-1 downto 0);
        cout        : out std_logic
      );
end component;

    signal a_tb     : std_logic_vector(w_WIDTH-1 downto 0) := (others=>'0');
    signal b_tb     : std_logic_vector(w_WIDTH-1 downto 0) := (others=>'0');
    signal cin_tb   : std_logic := '0';
    signal sum_tb   : std_logic_vector(w_WIDTH-1 downto 0) := (others=>'0');
    signal cout_tb  : std_logic := '0';

begin

nbit_adder_i : nbit_adder
    port map(
        a       => a_tb,
        b       => b_tb,
        cin     => cin_tb,
        cout    => cout_tb,
        sum     => sum_tb
    );
    
process
begin
    
    wait for 10 ns;
    
    a_tb    <= "00000000";
    b_tb    <= "01010101";
    cin_tb  <= '1';
    wait for 10 ns;
    
    a_tb    <= "01111100";
    b_tb    <= "01010101";
    cin_tb  <= '0';
    wait for 10 ns;
    
    a_tb    <= "11111111";
    b_tb    <= "01000010";
    cin_tb  <= '1';
    wait;
end process;

end tb;
