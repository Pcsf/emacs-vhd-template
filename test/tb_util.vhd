-- Checks tb_util_pkg and sb_pkg: clocks (duty cycle, enable), gen_pulse,
-- await_value / await_change / await_stable, check_stable, expected alerts,
-- random, the scoreboard.  Two errors and two warnings are planted and
-- expected, so the run must end with TEST PASSED.  Run by `make check'.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package sb_byte_pkg is new work.sb_pkg
  generic map (t_element => std_logic_vector(7 downto 0), G_DEPTH => 4);

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.tb_util_pkg.all;
use work.sb_byte_pkg.all;

entity tb_util is
end entity tb_util;

architecture sim of tb_util is

  constant C_SCOPE : string := "tb_util";

  signal clk  : std_logic := '0';
  signal clk2 : std_logic := '0';
  signal ena  : boolean   := true;
  signal rst  : std_logic := '0';
  signal pv   : std_logic_vector(7 downto 0) := x"5A";
  signal v    : std_logic_vector(7 downto 0) := x"00";
  signal u    : unsigned(3 downto 0) := x"0";
  signal n    : integer := 0;
  signal b    : boolean := false;

  shared variable sb : t_scoreboard;

begin

  p_clk  : process begin clock_generator(clk, 10 ns, 25); end process;
  p_clk2 : process begin clock_generator(clk2, ena, 8 ns); end process;

  p_side : process
  begin
    wait for 100 ns;
    v <= x"A5";
    wait for 50 ns;
    u <= x"7";
    n <= 42;
    b <= true;
    wait for 20 ns;
    v <= x"5A";
    wait;
  end process p_side;

  p_main : process
    variable r    : integer;
    variable seen : std_logic_vector(7 downto 0);
  begin
    set_log_verbosity(C_LOG_BFM);
    sb.set_scope("sb");

    tc_start("TC-01", "clock with 25% duty cycle, reset pulse", C_SCOPE);
    gen_pulse(rst, '1', clk, 4, "reset", C_SCOPE);
    wait for 0 ns;
    check_value(rst, '0', "rst back low", C_SCOPE);
    check_value(now, 37500 ps, "4th rising edge: 7.5 ns + 3 x 10 ns", C_SCOPE);
    wait until falling_edge(clk);
    check_value(now, 40 ns, "falling edge 2.5 ns after the rising edge", C_SCOPE);

    tc_start("TC-02", "await_value, await_change, await_stable", C_SCOPE);
    await_value(v, x"A5", 0 ns, 200 ns, "v", C_SCOPE);
    check_value(now, 100 ns, "v arrived at 100 ns", C_SCOPE);
    await_value(u, x"7", 10 ns, 100 ns, "u", C_SCOPE);
    check_value(now, 150 ns, "u arrived at 150 ns", C_SCOPE);
    await_value(n, 42, 0 ns, 1 ns, "n already there", C_SCOPE);
    await_value(b, true, 0 ns, 1 ns, "b already there", C_SCOPE);
    await_change(v, 0 ns, 100 ns, "v changes again", C_SCOPE);
    check_value(v, x"5A", "v after the change", C_SCOPE);
    check_stable(v, 0 ns, "v just changed", C_SCOPE);
    await_stable(v, 30 ns, 1 us, "v", C_SCOPE);
    check_value(now, 200 ns, "stable 30 ns after the change at 170 ns", C_SCOPE);
    check_stable(v, 30 ns, "v stable", C_SCOPE);

    tc_start("TC-03", "planted alerts are expected", C_SCOPE);
    increment_expected_alerts(ERROR, 2);
    check_value(v, x"00", "planted mismatch", C_SCOPE);
    await_value(n, 7, 0 ns, 20 ns, "planted timeout", C_SCOPE);
    increment_expected_alerts(WARNING, 2);
    alert(WARNING, "planted warning", C_SCOPE);
    check_value_in_range(50 ns, 1 ns, 10 ns, "planted out of range", C_SCOPE, WARNING);
    check_value_in_range(5, 1, 10, "in range", C_SCOPE);
    check_value(get_alert_count(ERROR), 2, "error count so far", C_SCOPE);

    tc_start("TC-04", "random, clock enable", C_SCOPE);
    set_random_seed(7);
    for i in 1 to 200 loop
      r := random(-3, 3);
      check_value_in_range(r, -3, 3, "random in range", C_SCOPE);
    end loop;
    pv <= random(8);
    wait for 0 ns;
    seen := pv;
    pv <= random(8);
    wait for 0 ns;
    check_value(pv /= seen, "two random bytes differ", C_SCOPE);
    ena <= false;
    wait for 50 ns;
    check_stable(clk2, 40 ns, "clk2 stopped", C_SCOPE);
    check_value(clk2, '0', "clk2 low while disabled", C_SCOPE);
    ena <= true;
    await_change(clk2, 0 ns, 10 ns, "clk2 runs again", C_SCOPE);

    tc_start("TC-05", "gen_pulse on a vector, strings, time", C_SCOPE);
    seen := pv;
    gen_pulse(pv, x"FF", 15 ns, "vector pulse", C_SCOPE);
    wait for 0 ns;
    check_value(pv, seen, "vector restored", C_SCOPE);
    check_value(string'("abc"), "abc", "string", C_SCOPE);
    check_value(10 ns, 10000 ps, "time", C_SCOPE);
    check_value(to_unsigned(5, 4), x"5", "unsigned", C_SCOPE);
    check_value(to_signed(-2, 4), "1110", "signed", C_SCOPE);

    tc_start("TC-06", "scoreboard", C_SCOPE);
    sb.add_expected(x"01", "first");
    sb.add_expected(x"02", "second");
    check_value(sb.pending, 2, "two pending", C_SCOPE);
    sb.check_received(x"01", "first");
    sb.check_received(x"02", "second");
    sb.check_empty("after two");
    check_value(sb.received, 2, "two received", C_SCOPE);
    increment_expected_alerts(ERROR, 2);
    sb.add_expected(x"03", "third");
    sb.check_received(x"04", "planted mismatch");
    sb.check_received(x"05", "planted unexpected");
    sb.reset;
    sb.check_empty("after reset");

    report_final(C_SCOPE);
    std.env.stop;
  end process p_main;

end architecture sim;
