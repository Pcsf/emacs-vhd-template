{{!Finite state machine, two-process style: state and registered Moore outputs in one record}}
{{>header.vhd}}

library ieee;
use ieee.std_logic_1164.all;

entity {{entity|$file}} is
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;   -- synchronous, active high
    start    : in  std_logic;
    finished : in  std_logic;
    busy     : out std_logic;
    done     : out std_logic
  );
end entity {{entity}};

architecture rtl of {{entity}} is

  type state_t is (S_IDLE, S_BUSY, S_DONE);

  type reg_type is record
    state : state_t;
    busy  : std_logic;
    done  : std_logic;
  end record reg_type;

  constant REG_RESET : reg_type := (
    state => S_IDLE,
    busy  => '0',
    done  => '0'
  );

  -- To force a state encoding use the synthesis options (Vivado
  -- -fsm_extraction, Quartus State Machine Processing): there is no separate
  -- state signal to put an attribute on.
  signal r, rin : reg_type := REG_RESET;

begin

  comb : process (all)
    variable v : reg_type;
  begin
    v := r;                           -- default: stay in the current state

    case r.state is
      when S_IDLE =>
        if start = '1' then
          v.state := S_BUSY;
        end if;
      when S_BUSY =>
        if finished = '1' then
          v.state := S_DONE;
        end if;
      when S_DONE =>
        v.state := S_IDLE;
      when others =>                  -- recover from illegal states
        v.state := S_IDLE;
    end case;
    {{_}}

    -- Moore outputs, decoded from the next state and registered: they change
    -- in the same clock as the state and come straight from a flip-flop.
    v.busy := '1' when v.state = S_BUSY else '0';
    v.done := '1' when v.state = S_DONE else '0';

    if rst = '1' then                 -- synchronous reset: last, so it wins
      v := REG_RESET;
    end if;

    rin <= v;

    busy <= r.busy;
    done <= r.done;
  end process comb;

  regs : process (clk)
  begin
    if rising_edge(clk) then
      r <= rin;
    end if;
  end process regs;

end architecture rtl;
