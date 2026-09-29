{{!PWM generator: free-running counter compared with a duty value}}
{{>header.vhd}}

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity {{entity|$file}} is
  generic (
    G_WIDTH : positive := {{width|8}}     -- period = 2**G_WIDTH clocks
  );
  port (
    clk     : in  std_logic;
    rst     : in  std_logic;                              -- synchronous, active high
    duty    : in  unsigned(G_WIDTH - 1 downto 0);         -- high for `duty` of 2**G_WIDTH clocks
    pwm_out : out std_logic
  );
end entity {{entity}};

architecture rtl of {{entity}} is
  signal cnt : unsigned(G_WIDTH - 1 downto 0) := (others => '0');
begin

  p_pwm : process (clk)
  begin
    if rising_edge(clk) then
      cnt <= cnt + 1;
      if cnt < duty then
        pwm_out <= '1';
      else
        pwm_out <= '0';
      end if;
      if rst = '1' then
        cnt     <= (others => '0');
        pwm_out <= '0';
      end if;
    end if;
  end process p_pwm;
  {{_}}

end architecture rtl;
