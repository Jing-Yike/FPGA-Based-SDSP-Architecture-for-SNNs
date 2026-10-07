----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 2026/08/06 10:47:34
-- Design Name: 
-- Module Name: tb_delta_w_generator - tb
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

entity tb_delta_w_generator is
end tb_delta_w_generator;

architecture tb of tb_delta_w_generator is

    constant w_WIDTH : integer := 8;
    
component delta_w_generator is
    Port ( 
        up          : in std_logic;
        down        : in std_logic;
        spk_pre     : in std_logic;
        bist        : in std_logic;
        w_msb       : in std_logic;
        delta_w     : out std_logic_vector(w_WIDTH-1 downto 0);
        cin         : out std_logic
      );
end component;

    signal up_tb        : std_logic := '0';
    signal down_tb      : std_logic := '0';
    signal spk_pre_tb   : std_logic := '0';
    signal bist_tb      : std_logic := '0';
    signal w_msb_tb     : std_logic := '0';
    signal delta_w_tb   : std_logic_vector(w_WIDTH-1 downto 0) := (others=>'0');
    signal cin_tb       : std_logic := '0';

begin

delta_w_generator_i : delta_w_generator
    port map(
        up          => up_tb,
        down        => down_tb,
        spk_pre     => spk_pre_tb,
        bist        => bist_tb,
        w_msb       => w_msb_tb,
        delta_w     => delta_w_tb,
        cin         => cin_tb
    );
    
process
begin

    wait for 10 ns;
    
    -- Stop learning test case
    up_tb           <= '0';
    down_tb         <= '0';
    spk_pre_tb      <= '1';
    bist_tb         <= '0';
    w_msb_tb        <= '0';
    wait for 10 ns;
    
    -- Weight increment test case
    up_tb           <= '1';
    down_tb         <= '0';
    spk_pre_tb      <= '1';
    bist_tb         <= '0';
    w_msb_tb        <= '0';
    wait for 10 ns;
    
    -- Weight decrement test case
    up_tb           <= '0';
    down_tb         <= '1';
    spk_pre_tb      <= '1';
    bist_tb         <= '0';
    w_msb_tb        <= '0';
    wait for 10 ns;
    
    -- Bist test case 1
    up_tb           <= '0';
    down_tb         <= '0';
    spk_pre_tb      <= '0';
    bist_tb         <= '1';
    w_msb_tb        <= '0';
    wait for 10 ns;
    
    -- Bist test case 2
    up_tb           <= '0';
    down_tb         <= '0';
    spk_pre_tb      <= '0';
    bist_tb         <= '1';
    w_msb_tb        <= '1';
    wait for 10 ns;
    
    up_tb           <= '1';
    down_tb         <= '0';
    spk_pre_tb      <= '0';
    bist_tb         <= '0';
    w_msb_tb        <= '0';
    wait;
end process;

end tb;
