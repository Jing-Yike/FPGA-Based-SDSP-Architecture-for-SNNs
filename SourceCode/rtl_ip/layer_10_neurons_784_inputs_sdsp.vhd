library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.full_system_pkg.all;

entity layer_10_neurons_784_inputs_sdsp is
    generic (
        n_exc_inputs          : positive := 784;
        n_inh_inputs          : positive := 10;
        exc_cnt_bitwidth      : positive := 10;
        inh_cnt_bitwidth      : positive := 4;
        neuron_bit_width      : positive := 16;
        inh_weights_bit_width : positive := 3;
        exc_weights_bit_width : positive := 3;
        shift                 : natural  := 4;
        ca_width              : positive := 3;
        theta1                : natural  := 1;
        theta2                : natural  := 3;
        theta3                : natural  := 6;
        vmem_threshold        : integer  := 256
    );
    port (
        clk           : in  std_logic;
        rst_n         : in  std_logic;
        start         : in  std_logic;
        restart       : in  std_logic;
        learn_en      : in  std_logic;
        teacher_en    : in  std_logic := '0';
        teacher_label : in  std_logic_vector(3 downto 0) := (others => '0');
        teacher_current : in signed(neuron_bit_width-1 downto 0) := (others => '0');
        ca_leak_event : in  std_logic;
        bist_event    : in  std_logic;
        exc_spikes    : in  std_logic_vector(n_exc_inputs-1 downto 0);
        inh_spikes    : in  std_logic_vector(n_inh_inputs-1 downto 0);
        ready         : out std_logic;
        out_spikes    : out std_logic_vector(N_NEURONS-1 downto 0);
        input_accept  : out std_logic;
        step_valid    : out std_logic;
        step_spikes   : out std_logic_vector(N_NEURONS-1 downto 0)
    );
end entity layer_10_neurons_784_inputs_sdsp;

architecture structural of layer_10_neurons_784_inputs_sdsp is
    type logic_array_t is array (0 to N_NEURONS-1) of std_logic;
    type ca_array_t is array (0 to N_NEURONS-1) of
        std_logic_vector(ca_width-1 downto 0);
    type vmem_array_t is array (0 to N_NEURONS-1) of
        signed(neuron_bit_width-1 downto 0);

    constant V_THRESHOLD : signed(neuron_bit_width-1 downto 0) :=
        to_signed(512, neuron_bit_width);

    signal neurons_ready      : std_logic;
    signal exc                : std_logic;
    signal inh                : std_logic;
    signal exc_spike          : std_logic;
    signal inh_spike          : std_logic;
    signal exc_cnt            : std_logic_vector(exc_cnt_bitwidth-1 downto 0);
    signal inh_cnt            : std_logic_vector(inh_cnt_bitwidth-1 downto 0);
    signal exc_addr           : std_logic_vector(exc_cnt_bitwidth-1 downto 0);
    signal inh_addr           : std_logic_vector(inh_cnt_bitwidth-1 downto 0);
    signal neuron_restart     : std_logic;
    signal barrier_ready      : std_logic;
    signal barrier_spikes     : std_logic_vector(N_NEURONS-1 downto 0);
    signal out_spikes_inst    : std_logic_vector(N_NEURONS-1 downto 0);
    signal out_sample         : std_logic;
    signal layer_ready_int    : std_logic;
    signal layer_step_complete : std_logic;
    signal step_in_progress   : std_logic := '0';
    signal step_valid_reg     : std_logic := '0';
    signal step_spikes_reg    : std_logic_vector(N_NEURONS-1 downto 0) :=
        (others => '0');
    signal neuron_ready       : logic_array_t;
    signal vmem               : vmem_array_t;
    signal ca                 : ca_array_t;
    signal up                 : logic_array_t;
    signal down               : logic_array_t;
    signal teacher_apply      : logic_array_t;

    signal exc_weight_word     : weight_word_t;
    signal inh_weight_word     : weight_word_t;
    signal updated_weight_word : weight_word_t;
    signal exc_phase_d         : std_logic := '0';
    signal current_addr_valid  : std_logic;
    signal learning_request    : std_logic;
    signal write_pending       : std_logic := '0';
    signal write_addr_reg      : std_logic_vector(9 downto 0) := (others => '0');
begin
    assert n_exc_inputs = N_INPUTS
        report "This integrated RAM image is fixed at 784 excitatory inputs"
        severity failure;
    assert n_inh_inputs = N_NEURONS
        report "This integrated layer is fixed at 10 neurons"
        severity failure;
    assert exc_weights_bit_width = WEIGHT_WIDTH
        report "The supplied COE/VHDL initialization uses 3-bit weights"
        severity failure;

    neurons_ready <= neuron_ready(0) and neuron_ready(1) and
        neuron_ready(2) and neuron_ready(3) and neuron_ready(4) and
        neuron_ready(5) and neuron_ready(6) and neuron_ready(7) and
        neuron_ready(8) and neuron_ready(9) and barrier_ready;

    -- An empty input frame can return the input scanner to idle before the
    -- neuron and spike barrier finish. Do not start/count the next step yet.
    layer_step_complete <= layer_ready_int and neurons_ready;
    ready        <= layer_step_complete;
    out_spikes   <= barrier_spikes;
    input_accept <= out_sample;
    step_valid   <= step_valid_reg;
    step_spikes  <= step_spikes_reg;

    -- Export exact input-accept and completed-step timing to the AXI wrapper.
    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                step_in_progress <= '0';
                step_valid_reg   <= '0';
                step_spikes_reg  <= (others => '0');
            else
                step_valid_reg <= '0';
                if restart = '1' then
                    step_in_progress <= '0';
                    step_spikes_reg  <= (others => '0');
                elsif out_sample = '1' then
                    step_in_progress <= '1';
                elsif step_in_progress = '1' and layer_step_complete = '1' then
                    step_in_progress <= '0';
                    step_valid_reg   <= '1';
                    -- The neuron pulse has ended by the time the layer is ready.
                    -- Use the barrier's registered output for this step.
                    step_spikes_reg  <= barrier_spikes;
                end if;
            end if;
        end if;
    end process;

    multi_input_control : entity work.multi_input_784_exc_10_inh
        generic map (
            n_exc_inputs => n_exc_inputs,
            n_inh_inputs => n_inh_inputs,
            exc_cnt_bitwidth => exc_cnt_bitwidth,
            inh_cnt_bitwidth => inh_cnt_bitwidth
        )
        port map (
            clk => clk,
            rst_n => rst_n,
            restart => restart,
            start => start,
            exc_spikes => exc_spikes,
            inh_spikes => inh_spikes,
            neurons_ready => neurons_ready,
            exc_cnt => exc_cnt,
            inh_cnt => inh_cnt,
            ready => layer_ready_int,
            neuron_restart => neuron_restart,
            exc => exc,
            inh => inh,
            out_sample => out_sample,
            exc_spike => exc_spike,
            inh_spike => inh_spike
        );

    -- The generated Spiker datapath uses addr=counter+1 to prefetch a
    -- synchronous memory one cycle before the corresponding neuron update.
    exc_addr_conv : entity work.addr_converter
        generic map (N => exc_cnt_bitwidth)
        port map (addr_in => exc_cnt, addr_out => exc_addr);

    inh_addr_conv : entity work.addr_converter
        generic map (N => inh_cnt_bitwidth)
        port map (addr_in => inh_cnt, addr_out => inh_addr);

    -- Delaying exc by one cycle aligns the learning decision with the exact
    -- weight/spike that the neuron consumes. This also includes input 783,
    -- which is consumed one cycle after the controller deasserts exc.
    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                exc_phase_d    <= '0';
                write_pending  <= '0';
                write_addr_reg <= (others => '0');
            else
                exc_phase_d   <= exc;
                write_pending <= learning_request;
                if learning_request = '1' then
                    write_addr_reg <= exc_cnt;
                end if;
            end if;
        end if;
    end process;

    current_addr_valid <= '1' when unsigned(exc_cnt) < n_exc_inputs else '0';
    learning_request <= learn_en and exc_phase_d and current_addr_valid and
        (exc_spike or bist_event);

    exc_mem : entity work.exc_weight_ram_sdsp
        port map (
            clk => clk,
            rd_addr => exc_addr,
            rd_data => exc_weight_word,
            wr_en => write_pending,
            wr_addr => write_addr_reg,
            wr_data => updated_weight_word
        );

    inh_mem : entity work.inh_weight_rom
        port map (
            clk => clk,
            rd_addr => inh_addr,
            rd_data => inh_weight_word
        );

    neurons_and_learning : for i in 0 to N_NEURONS-1 generate
        -- start is one pulse per network time step, not per presynaptic bit.
        teacher_apply(i) <= start and teacher_en and learn_en when
            unsigned(teacher_label) = to_unsigned(i, teacher_label'length)
            else '0';

        neuron_i : entity work.neuron_subtractive_sdsp
            generic map (
                neuron_bit_width => neuron_bit_width,
                inh_weights_bit_width => inh_weights_bit_width,
                exc_weights_bit_width => exc_weights_bit_width,
                shift => shift
            )
            port map (
                v_th => V_THRESHOLD,
                inh_weight => signed(inh_weight_word(
                    (i+1)*inh_weights_bit_width-1 downto i*inh_weights_bit_width)),
                exc_weight => unsigned(exc_weight_word(
                    (i+1)*exc_weights_bit_width-1 downto i*exc_weights_bit_width)),
                clk => clk,
                rst_n => rst_n,
                restart => neuron_restart,
                exc => exc,
                inh => inh,
                exc_spike => exc_spike,
                inh_spike => inh_spike,
                teacher_apply => teacher_apply(i),
                teacher_current => teacher_current,
                neuron_ready => neuron_ready(i),
                out_spike => out_spikes_inst(i),
                v_mem => vmem(i)
            );

        ca_counter_i : entity work.ca_counter
            generic map (CA_WIDTH => ca_width)
            port map (
                clk => clk,
                rst => not rst_n,
                sample_start => restart,
                spk_post => out_spikes_inst(i),
                leak_event => ca_leak_event,
                ca => ca(i)
            );

        comparator_i : entity work.comparator
            generic map (
                CA_WIDTH => ca_width,
                VMEM_WIDTH => neuron_bit_width,
                THETA1 => theta1,
                THETA2 => theta2,
                THETA3 => theta3,
                VMEM_THRESHOLD => vmem_threshold
            )
            port map (
                ca => ca(i),
                vmem => std_logic_vector(vmem(i)),
                up => up(i),
                down => down(i)
            );

        sdsp_i : entity work.sdsp_top
            generic map (w_WIDTH => exc_weights_bit_width)
            port map (
                learn_en => learning_request,
                up => up(i),
                down => down(i),
                spk_pre => exc_spike,
                bist => bist_event,
                w => exc_weight_word(
                    (i+1)*exc_weights_bit_width-1 downto i*exc_weights_bit_width),
                w_next => updated_weight_word(
                    (i+1)*exc_weights_bit_width-1 downto i*exc_weights_bit_width),
                clk => clk,
                rst => not rst_n
            );
    end generate neurons_and_learning;

    spikes_barrier : entity work.barrier
        generic map (N => N_NEURONS)
        port map (
            clk => clk,
            rst_n => rst_n,
            restart => restart,
            out_sample => out_sample,
            reg_in => out_spikes_inst,
            ready => barrier_ready,
            reg_out => barrier_spikes
        );

end architecture structural;
