library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity network_sdsp is
    generic (
        n_cycles           : positive := 100;
        cycles_cnt_bitwidth : positive := 8;
        ca_width            : positive := 3;
        theta1              : natural  := 1;
        theta2              : natural  := 3;
        theta3              : natural  := 6;
        vmem_threshold       : integer  := 256
    );
    port (
        clk           : in  std_logic;
        rst_n         : in  std_logic;
        start         : in  std_logic;
        sample_ready  : in  std_logic;
        learn_en      : in  std_logic;
        teacher_en    : in  std_logic := '0';
        teacher_label : in  std_logic_vector(3 downto 0) := (others => '0');
        teacher_current : in signed(15 downto 0) := (others => '0');
        ca_leak_event : in  std_logic;
        bist_event    : in  std_logic;
        ready         : out std_logic;
        sample        : out std_logic;
        input_accept  : out std_logic;
        out_spikes_valid : out std_logic;
        in_spikes     : in  std_logic_vector(783 downto 0);
        out_spikes    : out std_logic_vector(9 downto 0)
    );
end entity network_sdsp;

architecture structural of network_sdsp is
    signal start_all        : std_logic;
    signal all_ready        : std_logic;
    signal restart          : std_logic;
    signal layer_0_ready    : std_logic;
    signal layer_0_feedback : std_logic_vector(9 downto 0);
    signal layer_0_accept   : std_logic;
    signal layer_0_valid    : std_logic;
    signal layer_0_result   : std_logic_vector(9 downto 0);
begin
    sample     <= start_all;
    all_ready  <= sample_ready and layer_0_ready;
    input_accept     <= layer_0_accept;
    out_spikes_valid <= layer_0_valid;
    out_spikes       <= layer_0_result;

    multi_cycle_control : entity work.multi_cycle
        generic map (
            cycles_cnt_bitwidth => cycles_cnt_bitwidth,
            n_cycles => n_cycles
        )
        port map (
            clk => clk,
            rst_n => rst_n,
            start => start,
            all_ready => all_ready,
            ready => ready,
            restart => restart,
            start_all => start_all
        );

    layer_0 : entity work.layer_10_neurons_784_inputs_sdsp
        generic map (
            n_exc_inputs => 784,
            n_inh_inputs => 10,
            exc_cnt_bitwidth => 10,
            inh_cnt_bitwidth => 4,
            neuron_bit_width => 16,
            inh_weights_bit_width => 3,
            exc_weights_bit_width => 3,
            shift => 4,
            ca_width => ca_width,
            theta1 => theta1,
            theta2 => theta2,
            theta3 => theta3,
            vmem_threshold => vmem_threshold
        )
        port map (
            clk => clk,
            rst_n => rst_n,
            start => start_all,
            restart => restart,
            learn_en => learn_en,
            teacher_en => teacher_en,
            teacher_label => teacher_label,
            teacher_current => teacher_current,
            ca_leak_event => ca_leak_event,
            bist_event => bist_event,
            exc_spikes => in_spikes,
            inh_spikes => layer_0_feedback,
            ready => layer_0_ready,
            out_spikes => layer_0_feedback,
            input_accept => layer_0_accept,
            step_valid => layer_0_valid,
            step_spikes => layer_0_result
        );
end architecture structural;
