library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

-- Full-length AXI smoke test: 100 x 25 stream words, learning enabled.
entity tb_snn_axi_wrapper_100_steps is
    generic (
        DENSE_INPUT : boolean := false;
        TEACHER_TEST : boolean := false;
        ZERO_INPUT : boolean := false
    );
end entity;

architecture sim of tb_snn_axi_wrapper_100_steps is
    constant STEPS : positive := 100;
    constant WORDS_PER_STEP : positive := 25;
    signal aclk : std_logic := '0';
    signal aresetn : std_logic := '0';
    signal s_axis_tdata : std_logic_vector(31 downto 0) := (others => '0');
    signal s_axis_tkeep : std_logic_vector(3 downto 0) := "1111";
    signal s_axis_tlast : std_logic := '0';
    signal s_axis_tvalid : std_logic := '0';
    signal s_axis_tready : std_logic;
    signal s_axi_awaddr : std_logic_vector(31 downto 0) := (others => '0');
    signal s_axi_awprot : std_logic_vector(2 downto 0) := (others => '0');
    signal s_axi_awvalid : std_logic := '0';
    signal s_axi_awready : std_logic;
    signal s_axi_wdata : std_logic_vector(31 downto 0) := (others => '0');
    signal s_axi_wstrb : std_logic_vector(3 downto 0) := "1111";
    signal s_axi_wvalid : std_logic := '0';
    signal s_axi_wready : std_logic;
    signal s_axi_bresp : std_logic_vector(1 downto 0);
    signal s_axi_bvalid : std_logic;
    signal s_axi_bready : std_logic := '1';
    signal s_axi_araddr : std_logic_vector(31 downto 0) := (others => '0');
    signal s_axi_arprot : std_logic_vector(2 downto 0) := (others => '0');
    signal s_axi_arvalid : std_logic := '0';
    signal s_axi_arready : std_logic;
    signal s_axi_rdata : std_logic_vector(31 downto 0);
    signal s_axi_rresp : std_logic_vector(1 downto 0);
    signal s_axi_rvalid : std_logic;
    signal s_axi_rready : std_logic := '1';
    signal irq : std_logic;
    signal axis_handshakes : natural := 0;
begin
    aclk <= not aclk after 5 ns;
    aresetn <= '1' after 25 ns;

    dut : entity work.snn_axi_wrapper
        generic map (N_CYCLES => STEPS, CYCLES_CNT_BITWIDTH => 8)
        port map (
            aclk => aclk, aresetn => aresetn,
            s_axis_tdata => s_axis_tdata, s_axis_tkeep => s_axis_tkeep,
            s_axis_tlast => s_axis_tlast, s_axis_tvalid => s_axis_tvalid,
            s_axis_tready => s_axis_tready,
            s_axi_awaddr => s_axi_awaddr, s_axi_awprot => s_axi_awprot,
            s_axi_awvalid => s_axi_awvalid, s_axi_awready => s_axi_awready,
            s_axi_wdata => s_axi_wdata, s_axi_wstrb => s_axi_wstrb,
            s_axi_wvalid => s_axi_wvalid, s_axi_wready => s_axi_wready,
            s_axi_bresp => s_axi_bresp, s_axi_bvalid => s_axi_bvalid,
            s_axi_bready => s_axi_bready,
            s_axi_araddr => s_axi_araddr, s_axi_arprot => s_axi_arprot,
            s_axi_arvalid => s_axi_arvalid, s_axi_arready => s_axi_arready,
            s_axi_rdata => s_axi_rdata, s_axi_rresp => s_axi_rresp,
            s_axi_rvalid => s_axi_rvalid, s_axi_rready => s_axi_rready,
            irq => irq
        );

    process(aclk)
    begin
        if rising_edge(aclk) and s_axis_tvalid = '1' and s_axis_tready = '1' then
            axis_handshakes <= axis_handshakes + 1;
        end if;
    end process;

    stream_source : process
    begin
        wait until aresetn = '1';
        for beat in 0 to STEPS*WORDS_PER_STEP-1 loop
            wait until falling_edge(aclk);
            s_axis_tdata <= (others => '0');
            if DENSE_INPUT and beat mod WORDS_PER_STEP = WORDS_PER_STEP-1 then
                s_axis_tdata <= x"0000FFFF";
            elsif DENSE_INPUT then
                s_axis_tdata <= x"FFFFFFFF";
            elsif not TEACHER_TEST and not ZERO_INPUT and
                  beat mod WORDS_PER_STEP = 0 then
                s_axis_tdata(0) <= '1';
            end if;
            if beat = STEPS*WORDS_PER_STEP-1 then
                s_axis_tlast <= '1';
            else
                s_axis_tlast <= '0';
            end if;
            s_axis_tvalid <= '1';
            loop
                wait until rising_edge(aclk);
                exit when s_axis_tready = '1';
            end loop;
        end loop;
        wait until falling_edge(aclk);
        s_axis_tvalid <= '0';
        s_axis_tlast <= '0';
        wait;
    end process;

    control_and_check : process
        procedure write_register(
            constant address : in natural;
            constant value : in std_logic_vector(31 downto 0)) is
        begin
            wait until falling_edge(aclk);
            s_axi_awaddr <= std_logic_vector(to_unsigned(address, 32));
            s_axi_awvalid <= '1';
            s_axi_wdata <= value;
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
        procedure read_register(
            constant address : in natural;
            variable value : out std_logic_vector(31 downto 0)) is
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
            value := s_axi_rdata;
            wait until rising_edge(aclk);
        end procedure;
        variable value : std_logic_vector(31 downto 0);
    begin
        wait until aresetn = '1';
        if TEACHER_TEST then
            write_register(16#0C#, x"00000002"); -- target neuron 2
            write_register(16#18#, x"00000080"); -- 0.25 in Q9
            write_register(16#00#, x"00000055"); -- start+learn+IRQ+teacher
            read_register(16#00#, value);
            assert value(6) = '1'
                report "Teacher-enable control readback failed"
                severity failure;
        elsif DENSE_INPUT then
            write_register(16#00#, x"00000011");
        else
            write_register(16#00#, x"00000015");
        end if;

        wait until irq = '1';
        read_register(16#04#, value);
        report "STATUS_100=" & to_hstring(value);
        assert value(4 downto 2) = "001"
            report "Expected done=1 and no stream/TLAST error" severity failure;
        read_register(16#50#, value);
        report "ACCEPTED_100=" & integer'image(to_integer(unsigned(value)));
        assert unsigned(value) = STEPS
            report "Expected 100 accepted steps" severity failure;
        read_register(16#54#, value);
        report "COUNTS_100=" & to_hstring(value);
        assert unsigned(value(23 downto 16)) = STEPS
            report "Expected 100 completed steps" severity failure;
        assert axis_handshakes = STEPS*WORDS_PER_STEP
            report "Expected 2500 AXI stream handshakes" severity failure;
        if DENSE_INPUT then
            for neuron in 0 to 9 loop
                read_register(16#24# + 4*neuron, value);
                report "DENSE_SPIKE_COUNT_" & integer'image(neuron) & "=" &
                       integer'image(to_integer(unsigned(value)));
                assert unsigned(value) > 0
                    report "Expected nonzero spikes for dense input"
                    severity failure;
            end loop;
        elsif TEACHER_TEST or ZERO_INPUT then
            for neuron in 0 to 9 loop
                read_register(16#24# + 4*neuron, value);
                report "TEACHER_SPIKE_COUNT_" & integer'image(neuron) & "=" &
                       integer'image(to_integer(unsigned(value)));
                if TEACHER_TEST and neuron = 2 then
                    assert unsigned(value) > 0
                        report "The labelled neuron did not spike with teacher current"
                        severity failure;
                else
                    assert unsigned(value) = 0
                        report "An unlabelled neuron spiked with zero input"
                        severity failure;
                end if;
            end loop;
        end if;
        report "RESULT wrapper 100-step PASS: 2500 words, 100 accepted/completed, no stream/TLAST error";
        finish;
    end process;

    process
    begin
        wait for 2 ms;
        assert false report "100-step wrapper simulation timeout" severity failure;
    end process;
end architecture;
