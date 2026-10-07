library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.full_system_pkg.all;
use std.env.all;

entity tb_exc_weight_ram_bounds is
end entity;

architecture sim of tb_exc_weight_ram_bounds is
    signal clk : std_logic := '0';
    signal rd_addr : std_logic_vector(9 downto 0) := (others => '0');
    signal rd_data : weight_word_t;
    signal wr_en : std_logic := '0';
    signal wr_addr : std_logic_vector(9 downto 0) := (others => '0');
    signal wr_data : weight_word_t := (others => '1');
begin
    clk <= not clk after 5 ns;

    dut : entity work.exc_weight_ram_sdsp
        port map (
            clk => clk, rd_addr => rd_addr, rd_data => rd_data,
            wr_en => wr_en, wr_addr => wr_addr, wr_data => wr_data
        );

    process
    begin
        rd_addr <= std_logic_vector(to_unsigned(0, 10));
        wait until rising_edge(clk);
        wait for 1 ns;
        assert rd_data = EXC_WEIGHT_INIT(0)
            report "Address 0 initial weight mismatch" severity failure;

        rd_addr <= std_logic_vector(to_unsigned(783, 10));
        wait until rising_edge(clk);
        wait for 1 ns;
        assert rd_data = EXC_WEIGHT_INIT(783)
            report "Last valid weight mismatch" severity failure;

        rd_addr <= std_logic_vector(to_unsigned(784, 10));
        wait until rising_edge(clk);
        wait for 1 ns;
        assert rd_data = (rd_data'range => '0')
            report "Out-of-range prefetch did not return zero" severity failure;

        rd_addr <= std_logic_vector(to_unsigned(0, 10));
        wr_addr <= std_logic_vector(to_unsigned(0, 10));
        wr_data <= (others => '1');
        wr_en <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        assert rd_data = EXC_WEIGHT_INIT(0)
            report "Read-first behavior changed" severity failure;

        wr_en <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;
        assert rd_data = (rd_data'range => '1')
            report "Valid weight write/read failed" severity failure;
        report "RESULT RAM bounds/read-first/write PASS";
        finish;
    end process;
end architecture;
