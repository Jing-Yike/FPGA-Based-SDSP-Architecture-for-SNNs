library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ca_counter is
    generic (
        CA_WIDTH : positive := 3
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        sample_start : in  std_logic;
        spk_post     : in  std_logic;
        leak_event   : in  std_logic;
        ca           : out std_logic_vector(CA_WIDTH-1 downto 0)
    );
end entity ca_counter;

architecture rtl of ca_counter is
    signal ca_reg : unsigned(CA_WIDTH-1 downto 0) := (others => '0');
    constant CA_MIN : unsigned(CA_WIDTH-1 downto 0) := (others => '0');
    constant CA_MAX : unsigned(CA_WIDTH-1 downto 0) := (others => '1');
begin
    process(clk, rst)
    begin
        if rst = '1' then
            ca_reg <= CA_MIN;
        elsif rising_edge(clk) then
            if sample_start = '1' then
                ca_reg <= CA_MIN;
            elsif spk_post = '1' and leak_event = '0' then
                if ca_reg < CA_MAX then
                    ca_reg <= ca_reg + 1;
                end if;
            elsif spk_post = '0' and leak_event = '1' then
                if ca_reg > CA_MIN then
                    ca_reg <= ca_reg - 1;
                end if;
            end if;
        end if;
    end process;

    ca <= std_logic_vector(ca_reg);
end architecture rtl;

