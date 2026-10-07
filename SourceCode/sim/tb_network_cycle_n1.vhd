library ieee;
use ieee.std_logic_1164.all;

-- Run the same two-vector stimulus with the integrated network n_cycles=1.
entity tb_network_cycle_n1 is
end entity;

architecture sim of tb_network_cycle_n1 is
begin
    tb : entity work.tb_network_cycle_count
        generic map (DUT_N_CYCLES => 1, EXPECTED_STEPS => 2);
end architecture;
