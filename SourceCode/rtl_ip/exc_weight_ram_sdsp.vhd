library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.full_system_pkg.all;

-- 784 words x 30 bits, simple-dual-port (one synchronous read + one write).
-- Each word stores ten unsigned 3-bit weights. Neuron i occupies bits
-- (3*i)+2 downto 3*i, matching the original Spiker ROM packing.
entity exc_weight_ram_sdsp is
    port (
        clk     : in  std_logic;
        rd_addr : in  std_logic_vector(9 downto 0);
        rd_data : out weight_word_t;
        wr_en   : in  std_logic;
        wr_addr : in  std_logic_vector(9 downto 0);
        wr_data : in  weight_word_t
    );
end entity exc_weight_ram_sdsp;

architecture rtl of exc_weight_ram_sdsp is
    signal mem         : exc_weight_memory_t := EXC_WEIGHT_INIT;
    signal rd_data_reg : weight_word_t := (others => '0');

    attribute ram_style : string;
    attribute ram_style of mem : signal is "block";
begin
    process(clk)
    begin
        if rising_edge(clk) then
            -- Read-first behavior. The learning write port can update address A
            -- while the Spiker datapath prefetches address A+1.
            -- The one-address-ahead prefetch reaches 784 after the final
            -- valid weight (783). Define that unused read as zero.
            if unsigned(rd_addr) < N_INPUTS then
                rd_data_reg <= mem(to_integer(unsigned(rd_addr)));
            else
                rd_data_reg <= (others => '0');
            end if;

            if wr_en = '1' then
                mem(to_integer(unsigned(wr_addr))) <= wr_data;
            end if;
        end if;
    end process;

    rd_data <= rd_data_reg;
end architecture rtl;
