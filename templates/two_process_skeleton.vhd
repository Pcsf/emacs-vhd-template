{{!Two-process skeleton with an empty comb process: the RED stub for test-first design}}
{{>header.vhd}}

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.{{entity|$file}}_pkg.all;

entity {{entity}} is
  port (
    clk    : in  std_logic;
    rst    : in  std_logic;                            -- synchronous, active high
    {{iface|ctl}}i : in  {{entity}}_in_type;
    {{iface}}o : out {{entity}}_out_type
  );
end entity {{entity}};

architecture rtl of {{entity}} is

  -- Where a signal goes:
  --   memory deeper than a few words  -> its own RAM entity (ram_sdp)
  --   from another clock or a pin     -> a synchronizer first (sync_2ff)
  --   needed after the next edge      -> a field here
  --   an output                       -> a field here, port driven from r
  --   anything else                   -> a variable in comb, with a default
  type reg_type is record
    busy : std_logic;
    done : std_logic;
  end record reg_type;

  constant REG_RESET : reg_type := (
    busy => '0',
    done => '0'
  );

  signal r, rin : reg_type := REG_RESET;

begin

  -- Empty on purpose: write a failing test case first, then the lines it needs.
  comb : process (all)
    variable v : reg_type;
  begin
    v := r;
    -- Default every helper variable here.

    {{_}}

    if rst = '1' then
      v := REG_RESET;
    end if;

    rin <= v;

    {{iface}}o.busy <= r.busy;
    {{iface}}o.done <= r.done;
  end process comb;

  regs : process (clk)
  begin
    if rising_edge(clk) then
      r <= rin;
    end if;
  end process regs;

end architecture rtl;
