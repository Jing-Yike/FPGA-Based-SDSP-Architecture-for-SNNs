library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.full_system_pkg.all;

-- The inhibitory path is not trained, so its original 10 x 30 ROM remains
-- read-only. Its contents are copied exactly from rom_10x10_inhlif1.coe.
entity inh_weight_rom is
    port (
        clk     : in  std_logic;
        rd_addr : in  std_logic_vector(3 downto 0);
        rd_data : out weight_word_t
    );
end entity inh_weight_rom;

architecture rtl of inh_weight_rom is
    signal mem         : inh_weight_memory_t := INH_WEIGHT_INIT;
    signal rd_data_reg : weight_word_t := (others => '0');

    attribute rom_style : string;
    attribute rom_style of mem : signal is "block";
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if unsigned(rd_addr) < N_NEURONS then
                rd_data_reg <= mem(to_integer(unsigned(rd_addr)));
            else
                rd_data_reg <= (others => '0');
            end if;
        end if;
    end process;

    rd_data <= rd_data_reg;
end architecture rtl;

