{{!Two-process style (2/2): comb + regs processes, register record (needs VHDL-2008)}}
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

  constant C_COUNT_MAX : natural := 255;

  type state_type is (S_IDLE, S_RUN, S_DONE);

  -- All flip-flops live in this record.
  type reg_type is record
    state : state_type;
    count : unsigned(7 downto 0);
  end record reg_type;

  constant REG_RESET : reg_type := (
    state => S_IDLE,
    count => (others => '0')
  );

  signal r, rin : reg_type;

begin

  -- All logic. `process (all)` needs VHDL-2008; otherwise list
  -- {{iface}}i, r and rst by hand.
  comb : process (all)
    variable v : reg_type;
  begin
    v := r;

    case r.state is
      when S_IDLE =>
        if {{iface}}i.start = '1' then
          v.count := (others => '0');
          v.state := S_RUN;
        end if;
      when S_RUN =>
        v.count := r.count + 1;
        if r.count = C_COUNT_MAX then
          v.state := S_DONE;
        end if;
      when S_DONE =>
        v.state := S_IDLE;
      when others =>
        v.state := S_IDLE;
    end case;

    {{_}}

    -- Synchronous reset: last, so it wins over everything above.
    if rst = '1' then
      v := REG_RESET;
    end if;

    rin <= v;

    if r.state = S_RUN then
      {{iface}}o.busy <= '1';
    else
      {{iface}}o.busy <= '0';
    end if;
    if r.state = S_DONE then
      {{iface}}o.done <= '1';
    else
      {{iface}}o.done <= '0';
    end if;
  end process comb;

  -- Registers only.
  regs : process (clk)
  begin
    if rising_edge(clk) then
      r <= rin;
    end if;
  end process regs;

end architecture rtl;
