library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

-- Check that completed steps expose the spikes retained by the barrier.
entity tb_layer_step_output is
end entity;

architecture sim of tb_layer_step_output is
    signal clk          : std_logic := '0';
    signal rst_n        : std_logic := '0';
    signal start        : std_logic := '0';
    signal ready        : std_logic;
    signal out_spikes   : std_logic_vector(9 downto 0);
    signal input_accept : std_logic;
    signal step_valid   : std_logic;
    signal step_spikes  : std_logic_vector(9 downto 0);
begin
    clk <= not clk after 5 ns;
    rst_n <= '1' after 25 ns;

    dut : entity work.layer_10_neurons_784_inputs_sdsp
        port map (
            clk => clk,
            rst_n => rst_n,
            start => start,
            restart => '0',
            learn_en => '0',
            ca_leak_event => '0',
            bist_event => '0',
            exc_spikes => (others => '1'),
            inh_spikes => out_spikes,
            ready => ready,
            out_spikes => out_spikes,
            input_accept => input_accept,
            step_valid => step_valid,
            step_spikes => step_spikes
        );

    stimulus : process
        variable barrier_nonzero : natural := 0;
        variable exported_nonzero : natural := 0;
    begin
        wait until rst_n = '1';
        for step in 1 to 4 loop
            if ready /= '1' then
                wait until ready = '1';
            end if;
            wait until falling_edge(clk);
            start <= '1';
            wait until falling_edge(clk);
            start <= '0';

            wait until step_valid = '1';
            report "STEP=" & integer'image(step) &
                   " BARRIER=" & to_hstring(out_spikes) &
                   " EXPORTED=" & to_hstring(step_spikes);
            if out_spikes /= (out_spikes'range => '0') then
                barrier_nonzero := barrier_nonzero + 1;
            end if;
            if step_spikes /= (step_spikes'range => '0') then
                exported_nonzero := exported_nonzero + 1;
            end if;
            assert step_spikes = out_spikes
                report "Completed step does not match the barrier output"
                severity failure;
            wait until rising_edge(clk);
        end loop;

        assert barrier_nonzero > 0
            report "Dense input did not produce any registered output spikes"
            severity failure;
        assert exported_nonzero > 0
            report "Completed steps did not expose any output spikes"
            severity failure;
        report "RESULT layer output PASS: barrier and completed-step spikes match";
        finish;
    end process;

    timeout : process
    begin
        wait for 1 ms;
        assert false report "Layer output simulation timeout" severity failure;
    end process;
end architecture;
