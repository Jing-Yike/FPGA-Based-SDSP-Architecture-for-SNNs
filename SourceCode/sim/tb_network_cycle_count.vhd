library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

-- Two externally supplied spike vectors. If the network requests a third,
-- model the wrapper's stale ping-pong buffer by repeating the first vector.
entity tb_network_cycle_count is
    generic (
        DUT_N_CYCLES : positive := 2;
        EXPECTED_STEPS : positive := 3
    );
end entity;

architecture sim of tb_network_cycle_count is
    signal clk              : std_logic := '0';
    signal rst_n            : std_logic := '0';
    signal start            : std_logic := '0';
    signal ready            : std_logic;
    signal sample           : std_logic;
    signal input_accept     : std_logic;
    signal out_spikes_valid : std_logic;
    signal in_spikes        : std_logic_vector(783 downto 0) := (others => '0');
    signal out_spikes       : std_logic_vector(9 downto 0);
    signal sample_count     : natural := 0;
    signal accept_count     : natural := 0;
    signal valid_count      : natural := 0;
begin
    clk <= not clk after 5 ns;

    -- Drive two distinct input frames; there is no third frame in the source.
    process(accept_count)
        variable spikes : std_logic_vector(783 downto 0);
    begin
        spikes := (others => '0');
        if accept_count = 0 then
            spikes(0) := '1';
        elsif accept_count = 1 then
            spikes(1) := '1';
        elsif accept_count = 2 then
            spikes(0) := '1';
        end if;
        in_spikes <= spikes;
    end process;

    dut : entity work.network_sdsp
        generic map (
            n_cycles => DUT_N_CYCLES,
            cycles_cnt_bitwidth => 8
        )
        port map (
            clk => clk,
            rst_n => rst_n,
            start => start,
            sample_ready => '1',
            learn_en => '0',
            ca_leak_event => '0',
            bist_event => '0',
            ready => ready,
            sample => sample,
            input_accept => input_accept,
            out_spikes_valid => out_spikes_valid,
            in_spikes => in_spikes,
            out_spikes => out_spikes
        );

    process(clk)
    begin
        if rising_edge(clk) and rst_n = '1' then
            if sample = '1' then
                sample_count <= sample_count + 1;
                report "NETWORK_SAMPLE " & integer'image(sample_count + 1);
            end if;
            if input_accept = '1' then
                accept_count <= accept_count + 1;
                report "INPUT_ACCEPT " & integer'image(accept_count + 1);
            end if;
            if out_spikes_valid = '1' then
                valid_count <= valid_count + 1;
                report "OUTPUT_VALID " & integer'image(valid_count + 1);
            end if;
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

        wait until sample_count > 0;
        wait until ready = '1';
        wait for 30 ns;
        report "RESULT n_cycles=" & integer'image(DUT_N_CYCLES) &
               " samples=" & integer'image(sample_count) &
               " accepts=" & integer'image(accept_count) &
               " outputs=" & integer'image(valid_count);
        assert sample_count = EXPECTED_STEPS
            report "Unexpected number of network samples" severity failure;
        assert accept_count = EXPECTED_STEPS
            report "Unexpected number of input accepts" severity failure;
        assert valid_count = EXPECTED_STEPS
            report "Unexpected number of completed outputs" severity failure;
        finish;
    end process;

    process
    begin
        wait for 2 ms;
        assert false report "Timeout while waiting for the network to finish" severity failure;
    end process;
end architecture;
