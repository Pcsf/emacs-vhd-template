{{!CDC: single-pulse synchronizer between two clocks (toggle method)}}
{{>header.vhd}}

-- The source pulse is turned into a level toggle, synchronized, and turned
-- back into a pulse.  Source pulses must be at least 3 destination clock
-- periods apart, or they merge.  Constrain the path from `toggle` to
-- `sync(0)` with set_false_path or set_max_delay -datapath_only.

library ieee;
use ieee.std_logic_1164.all;

entity {{entity|$file}} is
  port (
    src_clk   : in  std_logic;
    src_pulse : in  std_logic;   -- one src_clk cycle wide
    dst_clk   : in  std_logic;
    dst_pulse : out std_logic    -- one dst_clk cycle wide
  );
end entity {{entity}};

architecture rtl of {{entity}} is

  signal toggle : std_logic := '0';                             -- src_clk domain
  signal sync   : std_logic_vector(2 downto 0) := (others => '0');  -- dst_clk

  attribute async_reg : string;
  attribute async_reg of sync : signal is "true";

begin

  p_src : process (src_clk)
  begin
    if rising_edge(src_clk) then
      if src_pulse = '1' then
        toggle <= not toggle;
      end if;
    end if;
  end process p_src;

  p_dst : process (dst_clk)
  begin
    if rising_edge(dst_clk) then
      sync <= sync(1 downto 0) & toggle;
    end if;
  end process p_dst;

  dst_pulse <= sync(2) xor sync(1);
  {{_}}

end architecture rtl;
