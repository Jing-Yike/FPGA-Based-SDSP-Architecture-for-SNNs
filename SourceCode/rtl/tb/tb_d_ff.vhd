----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 2026/08/06 10:45:24
-- Design Name: 
-- Module Name: tb_d_ff - tb
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

entity tb_d_ff is
end tb_d_ff;

architecture tb of tb_d_ff is

    constant w_WIDTH : integer := 8;
    constant clk_period : time := 10 ns;
    
component d_ff is
    Port (
        clk         : in std_logic;
        rst         : in std_logic;
        d           : in std_logic_vector(w_WIDTH-1 downto 0);
        q           : out std_logic_vector(w_WIDTH-1 downto 0)
      );
end component;

    signal clk_tb   : std_logic := '0';
    signal rst_tb   : std_logic := '1';
    signal d_tb     : std_logic_vector(w_WIDTH-1 downto 0) := (others=>'0');
    signal q_tb     : std_logic_vector(w_WIDTH-1 downto 0);

begin

d_ff_i : d_ff
    port map(
        clk     => clk_tb,
        rst     => rst_tb,
        d       => d_tb,
        q       => q_tb
    );

clk_process : process

   begin

    	clk_tb <= '0';

    	wait for clk_period/2; 

    	clk_tb <= '1';

    	wait for clk_period/2;

   end process;
   
stim_process : process
    begin
        
        wait for 10 ns;
        
        rst_tb      <= '0';
        d_tb        <= "11111111";
        wait for 10 ns;
        
        rst_tb      <= '0';
        d_tb        <= "11110000";
        wait for 10 ns;
        
        rst_tb      <= '0';
        d_tb        <= "11100111";
        wait for 10 ns;
        
        rst_tb      <= '1';
        d_tb        <= "11100100";
        wait for 10 ns;
        
        rst_tb      <= '0';
        d_tb        <= "11100100";
        wait;
        
    end process;

end tb;
