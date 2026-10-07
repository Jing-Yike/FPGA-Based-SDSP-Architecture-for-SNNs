library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_comparator_theta_m is
end entity;

architecture sim of tb_comparator_theta_m is
    signal ca : std_logic_vector(2 downto 0) := "001";
    signal vmem : std_logic_vector(15 downto 0) := (others => '0');
    signal up, down : std_logic;
begin
    dut : entity work.comparator
        port map (ca => ca, vmem => vmem, up => up, down => down);

    process
    begin
        -- Vivado launch_simulation auto-runs 1 us before the regression Tcl
        -- issues its explicit run command. Finish only during that second run.
        wait for 2 us;
        vmem <= std_logic_vector(to_signed(255, 16));
        wait for 1 ns;
        assert up = '0' and down = '1'
            report "Q9 membrane 255 must be below theta_m=0.5"
            severity failure;

        vmem <= std_logic_vector(to_signed(256, 16));
        wait for 1 ns;
        assert up = '1' and down = '0'
            report "Q9 membrane 256 must meet theta_m=0.5"
            severity failure;

        ca <= "000";
        wait for 1 ns;
        assert up = '0' and down = '0'
            report "Calcium below theta1 must disable both directions"
            severity failure;

        report "RESULT comparator theta_m Q9 PASS";
        finish;
    end process;
end architecture;
