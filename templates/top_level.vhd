{{!FPGA top level: board clock and reset button, reset synchronizer, blinking LED}}
{{>header.vhd}}

-- Needs the reset_sync and counter templates in the same project.

library ieee;
use ieee.std_logic_1164.all;

entity {{entity|$file}} is
  generic (
    G_CLK_HZ : positive := {{clk_hz|100_000_000}}
  );
  port (
    clk_in : in  std_logic;   -- board oscillator
    rst_n  : in  std_logic;   -- push button, active low, asynchronous
    led    : out std_logic
  );
end entity {{entity}};

architecture rtl of {{entity}} is

  signal rst_async : std_logic;
  signal rst       : std_logic;   -- active high, synchronous to clk_in
  signal tick      : std_logic;
  signal led_r     : std_logic := '0';

begin

  rst_async <= not rst_n;

  u_reset_sync : entity work.reset_sync
    port map (
      clk  => clk_in,
      arst => rst_async,
      srst => rst
    );

  -- Two ticks per second, so the LED blinks at 1 Hz.
  u_tick : entity work.counter
    generic map (
      G_MODULO => G_CLK_HZ / 2
    )
    port map (
      clk   => clk_in,
      rst   => rst,
      en    => '1',
      count => open,
      tick  => tick
    );

  p_led : process (clk_in)
  begin
    if rising_edge(clk_in) then
      if rst = '1' then
        led_r <= '0';
      elsif tick = '1' then
        led_r <= not led_r;
      end if;
    end if;
  end process p_led;

  led <= led_r;
  {{_}}

end architecture rtl;
