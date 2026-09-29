{{!Edge detector: one-clock pulse on a rising, falling or any edge}}
{{>header.vhd}}

-- `din` must already be synchronous to `clk` (see sync_2ff).

library ieee;
use ieee.std_logic_1164.all;

entity {{entity|$file}} is
  generic (
    G_EDGE : string := "{{edge|RISING}}"   -- "RISING", "FALLING" or "BOTH"
  );
  port (
    clk   : in  std_logic;
    din   : in  std_logic;
    pulse : out std_logic
  );
end entity {{entity}};

architecture rtl of {{entity}} is
  signal din_d : std_logic := '0';
begin

  assert G_EDGE = "RISING" or G_EDGE = "FALLING" or G_EDGE = "BOTH"
    report "G_EDGE must be RISING, FALLING or BOTH" severity failure;

  p_delay : process (clk)
  begin
    if rising_edge(clk) then
      din_d <= din;
    end if;
  end process p_delay;

  gen_rising : if G_EDGE = "RISING" generate
    pulse <= din and not din_d;
  end generate gen_rising;

  gen_falling : if G_EDGE = "FALLING" generate
    pulse <= not din and din_d;
  end generate gen_falling;

  gen_both : if G_EDGE = "BOTH" generate
    pulse <= din xor din_d;
  end generate gen_both;
  {{_}}

end architecture rtl;
