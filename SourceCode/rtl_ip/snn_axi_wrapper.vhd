library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- AXI front end for the 784-input, 10-output SNN+SDSP network.
-- Each time step is 25 words: words 0..23 carry bits 0..767 and
-- word 24 bits 15..0 carry bits 768..783. Its upper 16 bits are padding.
-- TLAST is expected only on the last word of the N_CYCLES-step image.
entity snn_axi_wrapper is
    generic (
        N_CYCLES : positive := 100;
        CYCLES_CNT_BITWIDTH : positive := 8;
        CA_WIDTH : positive := 3;
        -- IP customization values are reset defaults for the AXI registers.
        -- Software can still overwrite every value at run time.
        CA_INTERVAL_DEFAULT : natural := 0;
        BIST_INTERVAL_DEFAULT : natural := 0;
        TEACHER_CURRENT_DEFAULT : natural := 128;
        LABEL_DEFAULT : natural := 0;
        LEARN_ENABLE_DEFAULT : natural := 0;
        BIST_ENABLE_DEFAULT : natural := 0;
        TEACHER_ENABLE_DEFAULT : natural := 0
    );
    port (
        aclk : in std_logic;
        aresetn : in std_logic;
        s_axis_tdata : in std_logic_vector(31 downto 0);
        s_axis_tkeep : in std_logic_vector(3 downto 0);
        s_axis_tlast : in std_logic;
        s_axis_tvalid : in std_logic;
        s_axis_tready : out std_logic;
        s_axi_awaddr : in std_logic_vector(31 downto 0);
        s_axi_awprot : in std_logic_vector(2 downto 0);
        s_axi_awvalid : in std_logic;
        s_axi_awready : out std_logic;
        s_axi_wdata : in std_logic_vector(31 downto 0);
        s_axi_wstrb : in std_logic_vector(3 downto 0);
        s_axi_wvalid : in std_logic;
        s_axi_wready : out std_logic;
        s_axi_bresp : out std_logic_vector(1 downto 0);
        s_axi_bvalid : out std_logic;
        s_axi_bready : in std_logic;
        s_axi_araddr : in std_logic_vector(31 downto 0);
        s_axi_arprot : in std_logic_vector(2 downto 0);
        s_axi_arvalid : in std_logic;
        s_axi_arready : out std_logic;
        s_axi_rdata : out std_logic_vector(31 downto 0);
        s_axi_rresp : out std_logic_vector(1 downto 0);
        s_axi_rvalid : out std_logic;
        s_axi_rready : in std_logic;
        irq : out std_logic
    );
end entity;

architecture rtl of snn_axi_wrapper is
    constant WORDS_PER_STEP : positive := 25;
    type spike_count_array_t is array (0 to 9) of unsigned(31 downto 0);

    function apply_wstrb(
        old_value, new_value : std_logic_vector(31 downto 0);
        strb : std_logic_vector(3 downto 0)) return std_logic_vector is
        variable result : std_logic_vector(31 downto 0) := old_value;
    begin
        for i in 0 to 3 loop
            if strb(i) = '1' then
                result(i*8+7 downto i*8) := new_value(i*8+7 downto i*8);
            end if;
        end loop;
        return result;
    end;

    function enabled_default(value : natural) return std_logic is
    begin
        if value = 0 then
            return '0';
        end if;
        return '1';
    end;

    signal buffer_0, buffer_1 : std_logic_vector(783 downto 0) :=
        (others => '0');
    signal buffer_0_valid, buffer_1_valid : std_logic := '0';
    signal write_select, read_select : std_logic := '0';
    signal word_count : integer range 0 to WORDS_PER_STEP-1 := 0;
    signal received_step_count : integer range 0 to N_CYCLES := 0;
    signal accepted_step_count : integer range 0 to N_CYCLES := 0;
    signal completed_step_count : integer range 0 to N_CYCLES := 0;
    signal axis_ready_i, stream_error, tlast_error : std_logic := '0';

    signal start_pulse, soft_reset_pulse, clear_done_pulse : std_logic := '0';
    signal learn_enable_reg : std_logic :=
        enabled_default(LEARN_ENABLE_DEFAULT);
    signal bist_enable_reg : std_logic :=
        enabled_default(BIST_ENABLE_DEFAULT);
    signal irq_enable_reg : std_logic := '0';
    signal teacher_enable_reg : std_logic :=
        enabled_default(TEACHER_ENABLE_DEFAULT);
    signal teacher_enable_active : std_logic := '0';
    signal label_reg : std_logic_vector(3 downto 0) :=
        std_logic_vector(to_unsigned(LABEL_DEFAULT, 4));
    signal teacher_label_active : std_logic_vector(3 downto 0) :=
        (others => '0');
    signal ca_interval_reg : unsigned(15 downto 0) :=
        to_unsigned(CA_INTERVAL_DEFAULT, 16);
    signal bist_interval_reg : unsigned(15 downto 0) :=
        to_unsigned(BIST_INTERVAL_DEFAULT, 16);
    signal teacher_current_reg : std_logic_vector(31 downto 0) :=
        std_logic_vector(to_unsigned(TEACHER_CURRENT_DEFAULT, 32));
    signal teacher_current_active : signed(15 downto 0) := (others => '0');
    signal start_pending, accelerator_active, done_sticky : std_logic := '0';
    signal result_class : unsigned(3 downto 0) := (others => '0');
    signal spike_counts : spike_count_array_t := (others => (others => '0'));
    signal ca_leak_pulse, bist_active : std_logic := '0';
    signal ca_countdown, bist_countdown : unsigned(15 downto 0) :=
        (others => '0');
    signal argmax_active : std_logic := '0';
    signal argmax_scan_index : integer range 1 to 9 := 1;
    signal argmax_value : unsigned(31 downto 0) := (others => '0');

    signal net_rst_n, net_start, net_sample_ready, net_ready : std_logic;
    signal net_sample, net_input_accept, net_output_valid : std_logic;
    signal net_in_spikes : std_logic_vector(783 downto 0);
    signal net_out_spikes : std_logic_vector(9 downto 0);
    signal awready_i, wready_i, bvalid_i, arready_i, rvalid_i : std_logic :=
        '0';
    signal bresp_i, rresp_i : std_logic_vector(1 downto 0) := (others => '0');
    signal rdata_i : std_logic_vector(31 downto 0) := (others => '0');
    signal busy_status : std_logic;
begin
    assert N_CYCLES >= 2
        report "N_CYCLES must be at least 2 for the Spiker cycle controller"
        severity failure;
    assert CA_INTERVAL_DEFAULT <= 65535 and BIST_INTERVAL_DEFAULT <= 65535
        report "CA/BIST interval defaults must fit their 16-bit AXI registers"
        severity failure;
    assert TEACHER_CURRENT_DEFAULT <= 32767
        report "Teacher current default must fit the positive signed Q9 input"
        severity failure;
    assert LABEL_DEFAULT < 10
        report "Teacher label default must select one of the 10 neurons"
        severity failure;
    assert LEARN_ENABLE_DEFAULT <= 1 and BIST_ENABLE_DEFAULT <= 1 and
           TEACHER_ENABLE_DEFAULT <= 1
        report "Enable defaults must be 0 or 1"
        severity failure;

    busy_status <= start_pending or accelerator_active;
    irq <= done_sticky and irq_enable_reg;

    s_axis_tready <= axis_ready_i;
    axis_ready_i <= '1' when
        aresetn = '1' and soft_reset_pulse = '0' and
        received_step_count < N_CYCLES and
        ((write_select = '0' and buffer_0_valid = '0') or
         (write_select = '1' and buffer_1_valid = '0')) else '0';

    net_in_spikes <= buffer_0 when read_select = '0' else buffer_1;
    -- Keep sample_ready high after the final sample so the generated controller
    -- can leave its final update_wait state without requesting another input.
    net_sample_ready <= '1' when
        (read_select = '0' and buffer_0_valid = '1') or
        (read_select = '1' and buffer_1_valid = '1') or
        (accelerator_active = '1' and accepted_step_count = N_CYCLES)
        else '0';
    net_rst_n <= aresetn and not soft_reset_pulse;

    network_i : entity work.network_sdsp
        generic map (
            -- Spiker stops after n_cycles + 1 network_update pulses.
            -- N_CYCLES is the number of externally supplied spike frames.
            n_cycles => N_CYCLES - 1,
            cycles_cnt_bitwidth => CYCLES_CNT_BITWIDTH,
            ca_width => CA_WIDTH
        )
        port map (
            clk => aclk, rst_n => net_rst_n, start => net_start,
            sample_ready => net_sample_ready, learn_en => learn_enable_reg,
            teacher_en => teacher_enable_active,
            teacher_label => teacher_label_active,
            teacher_current => teacher_current_active,
            ca_leak_event => ca_leak_pulse, bist_event => bist_active,
            ready => net_ready, sample => net_sample,
            input_accept => net_input_accept,
            out_spikes_valid => net_output_valid,
            in_spikes => net_in_spikes, out_spikes => net_out_spikes
        );

    -- Simple compliant AXI4-Lite write channel. VALID is held by the master
    -- until READY, therefore AW and W may initially arrive in different cycles.
    awready_i <= '1' when aresetn = '1' and bvalid_i = '0' and
        s_axi_awvalid = '1' and s_axi_wvalid = '1' else '0';
    wready_i <= awready_i;
    s_axi_awready <= awready_i;
    s_axi_wready <= wready_i;
    s_axi_bvalid <= bvalid_i;
    s_axi_bresp <= bresp_i;

    process(aclk)
        variable merged : std_logic_vector(31 downto 0);
        variable address_word : integer range 0 to 63;
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                bvalid_i <= '0';
                bresp_i <= "00";
                start_pulse <= '0';
                soft_reset_pulse <= '0';
                clear_done_pulse <= '0';
                learn_enable_reg <= enabled_default(LEARN_ENABLE_DEFAULT);
                bist_enable_reg <= enabled_default(BIST_ENABLE_DEFAULT);
                irq_enable_reg <= '0';
                teacher_enable_reg <= enabled_default(TEACHER_ENABLE_DEFAULT);
                label_reg <= std_logic_vector(to_unsigned(LABEL_DEFAULT, 4));
                ca_interval_reg <= to_unsigned(CA_INTERVAL_DEFAULT, 16);
                bist_interval_reg <= to_unsigned(BIST_INTERVAL_DEFAULT, 16);
                teacher_current_reg <=
                    std_logic_vector(to_unsigned(TEACHER_CURRENT_DEFAULT, 32));
            else
                start_pulse <= '0';
                soft_reset_pulse <= '0';
                clear_done_pulse <= '0';
                if bvalid_i = '1' and s_axi_bready = '1' then
                    bvalid_i <= '0';
                end if;
                if awready_i = '1' then
                    bvalid_i <= '1';
                    bresp_i <= "00";
                    address_word := to_integer(unsigned(s_axi_awaddr(7 downto 2)));
                    case address_word is
                        when 0 =>
                            if s_axi_wstrb(0) = '1' then
                                start_pulse <= s_axi_wdata(0);
                                soft_reset_pulse <= s_axi_wdata(1);
                                learn_enable_reg <= s_axi_wdata(2);
                                bist_enable_reg <= s_axi_wdata(3);
                                irq_enable_reg <= s_axi_wdata(4);
                                clear_done_pulse <= s_axi_wdata(5);
                                teacher_enable_reg <= s_axi_wdata(6);
                            end if;
                        when 3 =>
                            if s_axi_wstrb(0) = '1' then
                                label_reg <= s_axi_wdata(3 downto 0);
                            end if;
                        when 4 =>
                            merged := (others => '0');
                            merged(15 downto 0) := std_logic_vector(ca_interval_reg);
                            merged := apply_wstrb(merged, s_axi_wdata, s_axi_wstrb);
                            ca_interval_reg <= unsigned(merged(15 downto 0));
                        when 5 =>
                            merged := (others => '0');
                            merged(15 downto 0) := std_logic_vector(bist_interval_reg);
                            merged := apply_wstrb(merged, s_axi_wdata, s_axi_wstrb);
                            bist_interval_reg <= unsigned(merged(15 downto 0));
                        when 6 =>
                            teacher_current_reg <= apply_wstrb(
                                teacher_current_reg, s_axi_wdata, s_axi_wstrb);
                        when others => null;
                    end case;
                end if;
            end if;
        end if;
    end process;

    arready_i <= '1' when aresetn = '1' and rvalid_i = '0' else '0';
    s_axi_arready <= arready_i;
    s_axi_rvalid <= rvalid_i;
    s_axi_rdata <= rdata_i;
    s_axi_rresp <= rresp_i;

    process(aclk)
        variable d : std_logic_vector(31 downto 0);
        variable address_word : integer range 0 to 63;
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                rvalid_i <= '0';
                rdata_i <= (others => '0');
                rresp_i <= "00";
            else
                if rvalid_i = '1' and s_axi_rready = '1' then
                    rvalid_i <= '0';
                end if;
                if arready_i = '1' and s_axi_arvalid = '1' then
                    d := (others => '0');
                    address_word := to_integer(unsigned(s_axi_araddr(7 downto 2)));
                    case address_word is
                        when 0 =>
                            d(2) := learn_enable_reg;
                            d(3) := bist_enable_reg;
                            d(4) := irq_enable_reg;
                            d(6) := teacher_enable_reg;
                        when 1 =>
                            d(0) := not busy_status;
                            d(1) := busy_status;
                            d(2) := done_sticky;
                            d(3) := stream_error;
                            d(4) := tlast_error;
                            d(5) := accelerator_active;
                            d(6) := buffer_0_valid;
                            d(7) := buffer_1_valid;
                        when 2 =>
                            d := std_logic_vector(to_unsigned(N_CYCLES, 32));
                        when 3 => d(3 downto 0) := label_reg;
                        when 4 =>
                            d(15 downto 0) := std_logic_vector(ca_interval_reg);
                        when 5 =>
                            d(15 downto 0) := std_logic_vector(bist_interval_reg);
                        when 6 => d := teacher_current_reg;
                        when 8 =>
                            d(3 downto 0) := std_logic_vector(result_class);
                        when 9 to 18 =>
                            d := std_logic_vector(spike_counts(address_word-9));
                        when 20 =>
                            d := std_logic_vector(
                                to_unsigned(accepted_step_count, 32));
                        when 21 =>
                            d(4 downto 0) :=
                                std_logic_vector(to_unsigned(word_count, 5));
                            d(15 downto 8) := std_logic_vector(to_unsigned(
                                received_step_count mod 256, 8));
                            d(23 downto 16) := std_logic_vector(to_unsigned(
                                completed_step_count mod 256, 8));
                            d(24) := write_select;
                            d(25) := read_select;
                        when others => null;
                    end case;
                    rdata_i <= d;
                    rresp_i <= "00";
                    rvalid_i <= '1';
                end if;
            end if;
        end if;
    end process;

    process(aclk)
        variable lower_bit : integer range 0 to 767;
        variable next_step : integer range 1 to N_CYCLES;
    begin
        if rising_edge(aclk) then
            if aresetn = '0' or soft_reset_pulse = '1' then
                buffer_0 <= (others => '0');
                buffer_1 <= (others => '0');
                buffer_0_valid <= '0';
                buffer_1_valid <= '0';
                write_select <= '0';
                read_select <= '0';
                word_count <= 0;
                received_step_count <= 0;
                accepted_step_count <= 0;
                completed_step_count <= 0;
                stream_error <= '0';
                tlast_error <= '0';
                start_pending <= '0';
                accelerator_active <= '0';
                done_sticky <= '0';
                result_class <= (others => '0');
                spike_counts <= (others => (others => '0'));
                ca_leak_pulse <= '0';
                bist_active <= '0';
                ca_countdown <= (others => '0');
                bist_countdown <= (others => '0');
                argmax_active <= '0';
                argmax_scan_index <= 1;
                argmax_value <= (others => '0');
                net_start <= '0';
                teacher_enable_active <= '0';
                teacher_label_active <= (others => '0');
                teacher_current_active <= (others => '0');
            else
                ca_leak_pulse <= '0';
                net_start <= '0';

                if clear_done_pulse = '1' then
                    done_sticky <= '0';
                end if;

                if start_pulse = '1' and accelerator_active = '0' then
                    -- Snapshot the training target and Q9 current for this
                    -- image. 0.25 * 2**9 = 128, the reset default above.
                    teacher_enable_active <= teacher_enable_reg and
                        learn_enable_reg;
                    teacher_label_active <= label_reg;
                    if unsigned(teacher_current_reg) >
                       to_unsigned(32767, teacher_current_reg'length) then
                        teacher_current_active <= to_signed(32767, 16);
                    else
                        teacher_current_active <=
                            signed(teacher_current_reg(15 downto 0));
                    end if;
                    start_pending <= '1';
                    done_sticky <= '0';
                    accepted_step_count <= 0;
                    completed_step_count <= 0;
                    stream_error <= '0';
                    tlast_error <= '0';
                    result_class <= (others => '0');
                    spike_counts <= (others => (others => '0'));
                    bist_active <= '0';
                    ca_countdown <= ca_interval_reg;
                    bist_countdown <= bist_interval_reg;
                    argmax_active <= '0';
                    argmax_scan_index <= 1;
                    argmax_value <= (others => '0');
                end if;

                if start_pending = '1' and net_ready = '1' and
                   ((read_select = '0' and buffer_0_valid = '1') or
                    (read_select = '1' and buffer_1_valid = '1')) then
                    net_start <= '1';
                    start_pending <= '0';
                    accelerator_active <= '1';
                end if;

                if s_axis_tvalid = '1' and axis_ready_i = '1' then
                    if s_axis_tkeep /= "1111" then
                        stream_error <= '1';
                    end if;
                    if word_count < WORDS_PER_STEP-1 then
                        lower_bit := word_count * 32;
                        if write_select = '0' then
                            buffer_0(lower_bit+31 downto lower_bit) <=
                                s_axis_tdata;
                        else
                            buffer_1(lower_bit+31 downto lower_bit) <=
                                s_axis_tdata;
                        end if;
                    else
                        if write_select = '0' then
                            buffer_0(783 downto 768) <=
                                s_axis_tdata(15 downto 0);
                        else
                            buffer_1(783 downto 768) <=
                                s_axis_tdata(15 downto 0);
                        end if;
                    end if;

                    if s_axis_tlast = '1' then
                        if not (word_count = WORDS_PER_STEP-1 and
                                received_step_count = N_CYCLES-1) then
                            tlast_error <= '1';
                        end if;
                    elsif word_count = WORDS_PER_STEP-1 and
                          received_step_count = N_CYCLES-1 then
                        tlast_error <= '1';
                    end if;

                    if word_count = WORDS_PER_STEP-1 then
                        if write_select = '0' then
                            buffer_0_valid <= '1';
                        else
                            buffer_1_valid <= '1';
                        end if;
                        write_select <= not write_select;
                        word_count <= 0;
                        received_step_count <= received_step_count + 1;
                    else
                        word_count <= word_count + 1;
                    end if;
                end if;

                if net_input_accept = '1' then
                    if accepted_step_count < N_CYCLES then
                        next_step := accepted_step_count + 1;
                        accepted_step_count <= next_step;
                        if read_select = '0' then
                            if buffer_0_valid = '1' then
                                buffer_0_valid <= '0';
                            else
                                stream_error <= '1';
                            end if;
                        else
                            if buffer_1_valid = '1' then
                                buffer_1_valid <= '0';
                            else
                                stream_error <= '1';
                            end if;
                        end if;
                        read_select <= not read_select;

                        -- Runtime division/modulo creates a long timing path.
                        -- Countdown registers generate the same event on
                        -- interval, 2*interval, ... accepted time steps.
                        if ca_interval_reg /= 0 then
                            if ca_countdown <= 1 then
                                ca_leak_pulse <= '1';
                                ca_countdown <= ca_interval_reg;
                            else
                                ca_countdown <= ca_countdown - 1;
                            end if;
                        else
                            ca_countdown <= (others => '0');
                        end if;
                        if bist_enable_reg = '1' and bist_interval_reg /= 0 then
                            if bist_countdown <= 1 then
                                -- Held for the complete synapse scan.
                                bist_active <= '1';
                                bist_countdown <= bist_interval_reg;
                            else
                                bist_countdown <= bist_countdown - 1;
                            end if;
                        elsif bist_interval_reg = 0 then
                            bist_countdown <= (others => '0');
                        end if;
                    else
                        stream_error <= '1';
                    end if;
                end if;

                if net_output_valid = '1' then
                    if completed_step_count < N_CYCLES then
                        completed_step_count <= completed_step_count + 1;
                    end if;
                    for i in 0 to 9 loop
                        if net_out_spikes(i) = '1' then
                            spike_counts(i) <= spike_counts(i) + 1;
                        end if;
                    end loop;
                    bist_active <= '0';
                end if;

                -- Start a sequential argmax scan after the final network
                -- output.  One 32-bit comparison per cycle replaces the old
                -- chain of nine comparisons in a single 10 ns cycle.
                if accelerator_active = '1' and argmax_active = '0' and
                   net_ready = '1' and
                   accepted_step_count = N_CYCLES and
                   completed_step_count = N_CYCLES then
                    argmax_active <= '1';
                    argmax_scan_index <= 1;
                    argmax_value <= spike_counts(0);
                    result_class <= (others => '0');
                end if;

                if argmax_active = '1' then
                    if spike_counts(argmax_scan_index) > argmax_value then
                        argmax_value <= spike_counts(argmax_scan_index);
                        result_class <= to_unsigned(argmax_scan_index, 4);
                    end if;

                    if argmax_scan_index = 9 then
                        argmax_active <= '0';
                        accelerator_active <= '0';
                        done_sticky <= '1';
                        received_step_count <= 0;
                        word_count <= 0;
                    else
                        argmax_scan_index <= argmax_scan_index + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture;
