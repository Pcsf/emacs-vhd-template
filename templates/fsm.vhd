{{!Finite state machine: state register + next-state process, Moore outputs}}
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
  signal state, next_state : state_t := S_IDLE;

  -- Vivado: force an encoding with
  --   attribute fsm_encoding : string;
  --   attribute fsm_encoding of state : signal is "one_hot";

begin

  p_state : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state <= S_IDLE;
      else
        state <= next_state;
      end if;
    end if;
  end process p_state;

  p_next : process (all)
  begin
    next_state <= state;              -- default: stay in the current state
    case state is
      when S_IDLE =>
        if start = '1' then
          next_state <= S_BUSY;
        end if;
      when S_BUSY =>
        if finished = '1' then
          next_state <= S_DONE;
        end if;
      when S_DONE =>
        next_state <= S_IDLE;
      when others =>                  -- recover from illegal states
        next_state <= S_IDLE;
    end case;
    {{_}}
  end process p_next;

  busy <= '1' when state = S_BUSY else '0';
  done <= '1' when state = S_DONE else '0';

end architecture rtl;
