library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity tb_multi_cycle_count is
end entity;

architecture sim of tb_multi_cycle_count is
    signal clk         : std_logic := '0';
    signal rst_n       : std_logic := '0';
    signal start       : std_logic := '0';
    signal ready       : std_logic;
    signal restart     : std_logic;
    signal start_all   : std_logic;
    signal start_count : natural := 0;
begin
    clk <= not clk after 5 ns;

    dut : entity work.multi_cycle
        generic map (cycles_cnt_bitwidth => 8, n_cycles => 2)
        port map (
            clk => clk,
            rst_n => rst_n,
            start => start,
            all_ready => '1',
            ready => ready,
            restart => restart,
            start_all => start_all
        );

    process(clk)
    begin
        if rising_edge(clk) and rst_n = '1' and start_all = '1' then
            start_count <= start_count + 1;
            report "START_ALL " & integer'image(start_count + 1);
        end if;
    end process;

    process
    begin
        wait for 25 ns;
        rst_n <= '1';
        wait until ready = '1';
        wait until falling_edge(clk);
        start <= '1';
        wait until falling_edge(clk);
        start <= '0';
        wait until start_count > 0;
        wait until ready = '1';
        wait for 20 ns;
        report "RESULT n_cycles=2 start_all=" & integer'image(start_count);
        assert start_count = 3
            report "Expected n_cycles + 1 start_all pulses" severity failure;
        finish;
    end process;

    process
    begin
        wait for 10 us;
        assert false report "Timeout" severity failure;
    end process;
end architecture;
