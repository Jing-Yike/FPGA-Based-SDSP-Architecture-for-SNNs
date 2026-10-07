library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity neuron_subtractive_sdsp is
    generic (
        neuron_bit_width      : positive := 16;
        inh_weights_bit_width : positive := 3;
        exc_weights_bit_width : positive := 3;
        shift                 : natural  := 4
    );
    port (
        v_th         : in  signed(neuron_bit_width-1 downto 0);
        inh_weight   : in  signed(inh_weights_bit_width-1 downto 0);
        exc_weight   : in  unsigned(exc_weights_bit_width-1 downto 0);
        clk          : in  std_logic;
        rst_n        : in  std_logic;
        restart      : in  std_logic;
        exc          : in  std_logic;
        inh          : in  std_logic;
        exc_spike    : in  std_logic;
        inh_spike    : in  std_logic;
        teacher_apply : in std_logic := '0';
        teacher_current : in signed(neuron_bit_width-1 downto 0) := (others => '0');
        neuron_ready : out std_logic;
        out_spike    : out std_logic;
        v_mem        : out signed(neuron_bit_width-1 downto 0)
    );
end entity neuron_subtractive_sdsp;

architecture structural of neuron_subtractive_sdsp is
    signal update_sel        : std_logic_vector(1 downto 0);
    signal add_or_sub        : std_logic;
    signal v_en              : std_logic;
    signal v_rst_n           : std_logic;
    signal exceed_v_th       : std_logic;
    signal masked_inh_weight : signed(inh_weights_bit_width-1 downto 0);
    signal masked_exc_weight : unsigned(exc_weights_bit_width-1 downto 0);
begin
    masked_exc_weight <= exc_weight when exc_spike = '1' else (others => '0');
    masked_inh_weight <= inh_weight when inh_spike = '1' else (others => '0');

    datapath : entity work.neuron_dp_subtractive_sdsp
        generic map (
            neuron_bit_width => neuron_bit_width,
            inh_weights_bit_width => inh_weights_bit_width,
            exc_weights_bit_width => exc_weights_bit_width,
            shift => shift
        )
        port map (
            v_th => v_th,
            inh_weight => masked_inh_weight,
            exc_weight => masked_exc_weight,
            clk => clk,
            update_sel => update_sel,
            add_or_sub => add_or_sub,
            v_en => v_en,
            v_rst_n => v_rst_n,
            teacher_apply => teacher_apply,
            teacher_current => teacher_current,
            exceed_v_th => exceed_v_th,
            v_mem => v_mem
        );

    control_unit : entity work.neuron_cu_subtractive
        port map (
            clk => clk,
            rst_n => rst_n,
            restart => restart,
            exc => exc,
            inh => inh,
            exceed_v_th => exceed_v_th,
            update_sel => update_sel,
            add_or_sub => add_or_sub,
            v_en => v_en,
            v_rst_n => v_rst_n,
            neuron_ready => neuron_ready,
            out_spike => out_spike
        );
end architecture structural;
