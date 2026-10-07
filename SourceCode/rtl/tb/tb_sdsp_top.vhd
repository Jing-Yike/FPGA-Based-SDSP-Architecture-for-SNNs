----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 2026/08/06 11:53:54
-- Design Name: 
-- Module Name: tb_sdsp_top - tb
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

entity tb_sdsp_top is
end tb_sdsp_top;

architecture tb of tb_sdsp_top is

    constant w_WIDTH : integer := 8;
    constant clk_period : time := 10 ns;

component sdsp_top is
    Port ( 
        -- Input ports
        up          : in std_logic;
        down        : in std_logic;
        spk_pre     : in std_logic;
        bist        : in std_logic;
        w           : in std_logic_vector(w_WIDTH-1 downto 0);
        -- Output ports
        w_next      : out std_logic_vector(w_WIDTH-1 downto 0);
        -- Clk and rst
        clk         : in std_logic;
        rst         : in std_logic
      );
end component;

    signal up_tb        : std_logic := '0';
    signal down_tb      : std_logic := '0';
    signal spk_pre_tb   : std_logic := '0';
    signal bist_tb      : std_logic := '0';
    signal w_tb         : std_logic_vector(w_WIDTH-1 downto 0) := (others=>'0');
    signal w_next_tb    : std_logic_vector(w_WIDTH-1 downto 0);
    signal clk_tb       : std_logic := '0';
    signal rst_tb       : std_logic := '1';

begin

sdsp_top_i : sdsp_top
    port map(
        up          => up_tb,
        down        => down_tb,
        spk_pre     => spk_pre_tb,
        bist        => bist_tb,
        w           => w_tb,
        w_next      => w_next_tb,
        clk         => clk_tb,
        rst         => rst_tb
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
        
        -- weight increment test case
        rst_tb          <= '0';
        up_tb           <= '1';
        down_tb         <= '0';
        spk_pre_tb      <= '1';
        bist_tb         <= '0';
        w_tb            <= "00001111";
        wait for 10 ns;
        
        -- weight decrement test case
        rst_tb          <= '0';
        up_tb           <= '0';
        down_tb         <= '1';
        spk_pre_tb      <= '1';
        bist_tb         <= '0';
        w_tb            <= "00001111";
        wait for 10 ns;
        
        -- no event test case
        rst_tb          <= '0';
        up_tb           <= '1';
        down_tb         <= '0';
        spk_pre_tb      <= '0';
        bist_tb         <= '0';
        w_tb            <= "00001111";
        wait for 10 ns;
        
        -- stop learning test case
        rst_tb          <= '0';
        up_tb           <= '0';
        down_tb         <= '0';
        spk_pre_tb      <= '1';
        bist_tb         <= '0';
        w_tb            <= "00001111";
        wait for 10 ns;
        
        -- bist increment test case
        rst_tb          <= '0';
        up_tb           <= '1';
        down_tb         <= '0';
        spk_pre_tb      <= '0';
        bist_tb         <= '1';
        w_tb            <= "10001111";
        wait for 10 ns;
        
        -- bist decrement test case
        rst_tb          <= '0';
        up_tb           <= '0';
        down_tb         <= '0';
        spk_pre_tb      <= '0';
        bist_tb         <= '1';
        w_tb            <= "00001111";
        wait for 10 ns;
        
        -- underflow test case
        rst_tb          <= '0';
        up_tb           <= '1';
        down_tb         <= '0';
        spk_pre_tb      <= '0';
        bist_tb         <= '1';
        w_tb            <= "00000000";
        wait for 10 ns;
        
        -- overflow test case
        rst_tb          <= '0';
        up_tb           <= '1';
        down_tb         <= '0';
        spk_pre_tb      <= '1';
        bist_tb         <= '0';
        w_tb            <= "11111111";
        wait for 10 ns;
        
        -- reset test case
        rst_tb          <= '1';
        wait;
    
    end process;

end tb;
