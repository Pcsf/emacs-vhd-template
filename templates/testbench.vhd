{{!Self-checking testbench on tb_util_pkg: clock_generator, reset pulse, numbered test cases, final report}}
{{>header.vhd}}

-- Needs tb_util_pkg (C-c t n tb_util_pkg), analysed first.  Inputs are driven
-- right after a rising edge and outputs checked on the falling edge.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.tb_util_pkg.all;

entity {{tb|$file}} is
end entity {{tb}};

architecture sim of {{tb}} is

  constant C_CLK_PERIOD : time     := {{period|10 ns}};
  constant C_SCOPE      : string   := "{{tb}}";
  constant C_WIDTH      : positive := 8;

  signal clk  : std_logic := '0';
  signal rst  : std_logic := '0';
  signal din  : std_logic_vector(C_WIDTH - 1 downto 0) := (others => '0');
  signal dout : std_logic_vector(C_WIDTH - 1 downto 0);

  function to_slv (value : natural) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(value, C_WIDTH));
  end function to_slv;

begin

  u_dut : entity work.{{dut|$stem}}
    generic map (
      G_WIDTH => C_WIDTH
    )
    port map (
      clk  => clk,
      rst  => rst,
      din  => din,
      dout => dout
    );

  p_clk : process
  begin
    clock_generator(clk, C_CLK_PERIOD);
  end process p_clk;

  p_main : process
  begin
    gen_pulse(rst, '1', clk, 4, "reset", C_SCOPE);
    wait_num_rising_edges(clk, 1);

    tc_start("TC-01", "dout follows din after one clock", C_SCOPE);
    din <= to_slv(16#A5#);
    wait_num_rising_edges(clk, 1);
    wait until falling_edge(clk);
    check_value(dout, to_slv(16#A5#), "dout", C_SCOPE);

    tc_start("TC-02", "dout follows a new din value", C_SCOPE);
    din <= to_slv(16#5A#);
    wait_num_rising_edges(clk, 1);
    wait until falling_edge(clk);
    check_value(dout, to_slv(16#5A#), "dout", C_SCOPE);

    {{_}}

    wait_num_rising_edges(clk, 2);
    report_final(C_SCOPE);
    std.env.stop;
  end process p_main;

  p_watchdog : process
  begin
    wait for {{timeout|1 ms}};
    alert(FAILURE, "watchdog: the test did not finish", C_SCOPE);
  end process p_watchdog;

end architecture sim;
