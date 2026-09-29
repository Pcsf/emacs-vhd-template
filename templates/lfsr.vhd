{{!LFSR / PRBS generator (Galois form, maximal length for the default taps)}}
{{>header.vhd}}

library ieee;
use ieee.std_logic_1164.all;

entity {{entity|$file}} is
  generic (
    G_WIDTH : positive := 8;
    -- Feedback mask.  x"B8" is maximal for 8 bits (period 255); use another
    -- mask (x"110" = 9 bits, x"500" = 11 bits, ...) if you change G_WIDTH.
    G_TAPS  : std_logic_vector(G_WIDTH - 1 downto 0) := x"B8";
    G_SEED  : std_logic_vector(G_WIDTH - 1 downto 0) := x"01"   -- never all zeros
  );
  port (
    clk : in  std_logic;
    rst : in  std_logic;                                -- synchronous, active high
    en  : in  std_logic;
    q   : out std_logic_vector(G_WIDTH - 1 downto 0)
  );
end entity {{entity}};

architecture rtl of {{entity}} is
  signal state : std_logic_vector(G_WIDTH - 1 downto 0) := G_SEED;
begin

  p_lfsr : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state <= G_SEED;
      elsif en = '1' then
        if state(0) = '1' then
          state <= ('0' & state(G_WIDTH - 1 downto 1)) xor G_TAPS;
        else
          state <= '0' & state(G_WIDTH - 1 downto 1);
        end if;
      end if;
    end if;
  end process p_lfsr;

  q <= state;
  {{_}}

end architecture rtl;
