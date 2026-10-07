library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity comparator is
    generic (
        CA_WIDTH       : positive := 3;
        VMEM_WIDTH     : positive := 16;
        THETA1         : natural  := 1;
        THETA2         : natural  := 3;
        THETA3         : natural  := 6;
        VMEM_THRESHOLD : integer  := 256
    );
    port (
        ca   : in  std_logic_vector(CA_WIDTH-1 downto 0);
        vmem : in  std_logic_vector(VMEM_WIDTH-1 downto 0);
        up   : out std_logic;
        down : out std_logic
    );
end entity comparator;

architecture rtl of comparator is
begin
    assert THETA1 < THETA2 and THETA2 < THETA3
        report "SDSP thresholds must satisfy THETA1 < THETA2 < THETA3"
        severity failure;

    -- Spiker stores membrane voltage as two's-complement signed fixed point.
    up <= '1' when
        unsigned(ca) >= to_unsigned(THETA1, CA_WIDTH) and
        unsigned(ca) <  to_unsigned(THETA3, CA_WIDTH) and
        signed(vmem) >= to_signed(VMEM_THRESHOLD, VMEM_WIDTH)
        else '0';

    down <= '1' when
        unsigned(ca) >= to_unsigned(THETA1, CA_WIDTH) and
        unsigned(ca) <  to_unsigned(THETA2, CA_WIDTH) and
        signed(vmem) <  to_signed(VMEM_THRESHOLD, VMEM_WIDTH)
        else '0';
end architecture rtl;
