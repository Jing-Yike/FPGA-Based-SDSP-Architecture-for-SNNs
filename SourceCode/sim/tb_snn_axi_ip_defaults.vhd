library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

-- Checks build-time IP defaults, PS AXI overrides, and hardware reset.
entity tb_snn_axi_ip_defaults is
end entity;

architecture sim of tb_snn_axi_ip_defaults is
    signal aclk : std_logic := '0';
    signal aresetn : std_logic := '0';
    signal s_axi_awaddr : std_logic_vector(31 downto 0) := (others => '0');
    signal s_axi_awvalid, s_axi_awready : std_logic := '0';
    signal s_axi_wdata : std_logic_vector(31 downto 0) := (others => '0');
    signal s_axi_wvalid, s_axi_wready : std_logic := '0';
    signal s_axi_bvalid : std_logic;
    signal s_axi_araddr : std_logic_vector(31 downto 0) := (others => '0');
    signal s_axi_arvalid, s_axi_arready : std_logic := '0';
    signal s_axi_rdata : std_logic_vector(31 downto 0);
    signal s_axi_rvalid : std_logic;
begin
    aclk <= not aclk after 5 ns;

    dut : entity work.snn_axi_wrapper
        generic map (
            N_CYCLES => 2,
            CA_INTERVAL_DEFAULT => 7,
            BIST_INTERVAL_DEFAULT => 11,
            TEACHER_CURRENT_DEFAULT => 256,
            LABEL_DEFAULT => 4,
            LEARN_ENABLE_DEFAULT => 1,
            BIST_ENABLE_DEFAULT => 1,
            TEACHER_ENABLE_DEFAULT => 1
        )
        port map (
            aclk => aclk, aresetn => aresetn,
            s_axis_tdata => (others => '0'),
            s_axis_tkeep => (others => '1'),
            s_axis_tlast => '0', s_axis_tvalid => '0',
            s_axis_tready => open,
            s_axi_awaddr => s_axi_awaddr,
            s_axi_awprot => (others => '0'),
            s_axi_awvalid => s_axi_awvalid,
            s_axi_awready => s_axi_awready,
            s_axi_wdata => s_axi_wdata,
            s_axi_wstrb => (others => '1'),
            s_axi_wvalid => s_axi_wvalid,
            s_axi_wready => s_axi_wready,
            s_axi_bresp => open, s_axi_bvalid => s_axi_bvalid,
            s_axi_bready => '1',
            s_axi_araddr => s_axi_araddr,
            s_axi_arprot => (others => '0'),
            s_axi_arvalid => s_axi_arvalid,
            s_axi_arready => s_axi_arready,
            s_axi_rdata => s_axi_rdata,
            s_axi_rresp => open, s_axi_rvalid => s_axi_rvalid,
            s_axi_rready => '1', irq => open
        );

    process
        procedure read_register(
            constant address : in natural;
            constant expected : in std_logic_vector(31 downto 0)) is
            variable actual : std_logic_vector(31 downto 0);
        begin
            wait until falling_edge(aclk);
            s_axi_araddr <= std_logic_vector(to_unsigned(address, 32));
            s_axi_arvalid <= '1';
            loop
                wait until rising_edge(aclk);
                exit when s_axi_arready = '1';
            end loop;
            wait until falling_edge(aclk);
            s_axi_arvalid <= '0';
            while s_axi_rvalid /= '1' loop
                wait until falling_edge(aclk);
            end loop;
            actual := s_axi_rdata;
            assert actual = expected
                report "AXI read mismatch at offset " &
                    integer'image(address) & ": got " & to_hstring(actual) &
                    ", expected " & to_hstring(expected)
                severity failure;
            wait until rising_edge(aclk);
        end procedure;

        procedure write_register(
            constant address : in natural;
            constant value : in std_logic_vector(31 downto 0)) is
        begin
            wait until falling_edge(aclk);
            s_axi_awaddr <= std_logic_vector(to_unsigned(address, 32));
            s_axi_wdata <= value;
            s_axi_awvalid <= '1';
            s_axi_wvalid <= '1';
            loop
                wait until rising_edge(aclk);
                exit when s_axi_awready = '1' and s_axi_wready = '1';
            end loop;
            wait until falling_edge(aclk);
            s_axi_awvalid <= '0';
            s_axi_wvalid <= '0';
            while s_axi_bvalid /= '1' loop
                wait until falling_edge(aclk);
            end loop;
            wait until rising_edge(aclk);
        end procedure;
    begin
        -- The regression runner automatically runs 1 us before its own run.
        wait for 2 us;
        wait until falling_edge(aclk);
        aresetn <= '1';
        wait until falling_edge(aclk);

        read_register(16#00#, x"0000004C"); -- learn, BIST, teacher
        read_register(16#0C#, x"00000004");
        read_register(16#10#, x"00000007");
        read_register(16#14#, x"0000000B");
        read_register(16#18#, x"00000100"); -- 0.5 in Q9

        write_register(16#00#, x"00000004"); -- PS disables BIST/teacher
        write_register(16#0C#, x"00000002");
        write_register(16#10#, x"00000005");
        write_register(16#14#, x"00000000");
        write_register(16#18#, x"00000080"); -- 0.25 in Q9
        read_register(16#00#, x"00000004");
        read_register(16#0C#, x"00000002");
        read_register(16#10#, x"00000005");
        read_register(16#14#, x"00000000");
        read_register(16#18#, x"00000080");

        wait until falling_edge(aclk);
        aresetn <= '0';
        wait for 30 ns;
        wait until falling_edge(aclk);
        aresetn <= '1';
        read_register(16#00#, x"0000004C");
        read_register(16#0C#, x"00000004");
        read_register(16#10#, x"00000007");
        read_register(16#14#, x"0000000B");
        read_register(16#18#, x"00000100");

        report "RESULT IP defaults, PS overrides and reset PASS";
        finish;
    end process;

    process
    begin
        wait for 1 ms;
        assert false report "IP defaults simulation timeout" severity failure;
    end process;
end architecture;
