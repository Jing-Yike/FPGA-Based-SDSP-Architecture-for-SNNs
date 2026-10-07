----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 2026/08/06 20:53:19
-- Design Name: 
-- Module Name: tb_ca_counter - tb
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

entity tb_ca_counter is
end tb_ca_counter;

architecture tb of tb_ca_counter is

    constant clk_period : time := 10 ns;
    
component ca_counter is
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        spk_post   : in  std_logic;
        leak_event : in  std_logic;
        ca         : out std_logic_vector(2 downto 0)
    );
end component;

    signal clk_tb           : std_logic := '0';
    signal rst_tb           : std_logic := '1';
    signal spk_post_tb      : std_logic := '0';
    signal leak_event_tb    : std_logic := '0';
    signal ca_tb            : std_logic_vector(2 downto 0) := "000";

begin

ca_counter_i : ca_counter
    port map(
        clk         => clk_tb,
        rst         => rst_tb,
        spk_post    => spk_post_tb,
        leak_event  => leak_event_tb,
        ca          => ca_tb
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
        
        rst_tb          <= '0';
        
        -- Case "00"
        spk_post_tb     <= '0';
        leak_event_tb   <= '0';
        wait for 10 ns;
        
        -- Case "01"
        spk_post_tb     <= '0';
        leak_event_tb   <= '1';
        wait for 10 ns;
        
        -- Case "10"
        spk_post_tb     <= '1';
        leak_event_tb   <= '0';
        wait for 10 ns;
        
        -- Case "11"
        spk_post_tb     <= '1';
        leak_event_tb   <= '1';
        wait;
    end process;

end tb;
