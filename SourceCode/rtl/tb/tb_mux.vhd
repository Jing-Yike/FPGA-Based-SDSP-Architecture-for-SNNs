----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 2026/08/06 10:45:24
-- Design Name: 
-- Module Name: tb_mux - tb
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

entity tb_mux is
end tb_mux;

architecture tb of tb_mux is

    constant w_WIDTH : integer := 8;
    
component mux is
    Port ( 
    a       : in std_logic_vector(w_WIDTH-1 downto 0);
    b       : in std_logic_vector(w_WIDTH-1 downto 0);
    sel     : in std_logic;
    o       : out std_logic_vector(w_WIDTH-1 downto 0)
  );
end component;
  
    signal a_tb   : std_logic_vector(w_WIDTH-1 downto 0) := (others=>'0');
    signal b_tb   : std_logic_vector(w_WIDTH-1 downto 0) := (others=>'0');
    signal sel_tb : std_logic := '0';
    signal o_tb   : std_logic_vector(w_WIDTH-1 downto 0) := (others=>'0');

begin

mux_i : mux
    port map(
        a       => a_tb,
        b       => b_tb,
        sel     => sel_tb,
        o       => o_tb  
    );
    
process
begin

    wait for 10 ns;
    
    a_tb    <= "11111111";
    b_tb    <= "00000011";
    sel_tb  <= '0';
    wait for 10 ns;
    
    a_tb    <= "11111111";
    b_tb    <= "00000011";
    sel_tb  <= '1';
    wait for 10 ns;
    
    a_tb    <= "11110000";
    b_tb    <= "01110011";
    sel_tb  <= '0';
    wait for 10 ns;
    
    a_tb    <= "11111111";
    b_tb    <= "00000011";
    sel_tb  <= '0';
    wait;
    end process;

end tb;
