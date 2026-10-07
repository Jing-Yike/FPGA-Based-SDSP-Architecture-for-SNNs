library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

-- End-to-end AXI check: two dense frames must produce registered output spikes.
entity tb_snn_axi_wrapper_dense_two_steps is
end entity;

architecture sim of tb_snn_axi_wrapper_dense_two_steps is
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
        generic map (N_CYCLES => 2, CYCLES_CNT_BITWIDTH => 8)
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
        for beat in 0 to 49 loop
            wait until falling_edge(aclk);
            if beat mod 25 = 24 then
                s_axis_tdata <= x"0000FFFF";
            else
                s_axis_tdata <= x"FFFFFFFF";
            end if;
            if beat = 49 then
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
        wait until falling_edge(aclk);
        s_axi_awaddr <= (others => '0');
        s_axi_awvalid <= '1';
        s_axi_wdata <= x"00000011"; -- Start and enable completion IRQ.
        s_axi_wvalid <= '1';
        loop
            wait until rising_edge(aclk);
            exit when s_axi_awready = '1' and s_axi_wready = '1';
        end loop;
        wait until falling_edge(aclk);
        s_axi_awvalid <= '0';
        s_axi_wvalid <= '0';

        wait until irq = '1';
        read_register(16#04#, value);
        report "DENSE_STATUS=" & to_hstring(value);
        assert value(4 downto 2) = "001"
            report "Expected done with no stream or TLAST error"
            severity failure;
        read_register(16#50#, value);
        assert unsigned(value) = 2
            report "Expected exactly two accepted steps" severity failure;
        read_register(16#54#, value);
        assert unsigned(value(23 downto 16)) = 2
            report "Expected exactly two completed steps" severity failure;
        for neuron in 0 to 9 loop
            read_register(16#24# + 4*neuron, value);
            report "SPIKE_COUNT_" & integer'image(neuron) & "=" &
                   integer'image(to_integer(unsigned(value)));
            assert unsigned(value) = 1
                report "Expected one spike from each neuron" severity failure;
        end loop;
        assert axis_handshakes = 50
            report "Expected 50 AXI stream handshakes" severity failure;
        report "RESULT dense wrapper PASS: two frames, ten nonzero spike counts";
        finish;
    end process;

    timeout : process
    begin
        wait for 1 ms;
        assert false report "Dense wrapper simulation timeout" severity failure;
    end process;
end architecture;
