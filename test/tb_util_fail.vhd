-- Runs that must fail, one per G_MODE: an unexpected error, the alert stop
-- limit, a FAILURE alert, an unexpected warning.  `make check' runs each
-- and requires a non-zero exit, TEST FAILED, and no line after the stop.

library ieee;
use ieee.std_logic_1164.all;

use work.tb_util_pkg.all;

entity tb_util_fail is
  generic (G_MODE : string := "mismatch");
end entity tb_util_fail;

architecture sim of tb_util_fail is
  signal clk : std_logic := '0';
begin

  p_clk : process begin clock_generator(clk, 10 ns); end process;

  p_main : process
  begin
    tc_start("TC-01", "must fail: " & G_MODE);
    if G_MODE = "mismatch" then
      check_value(clk, 'X', "planted");
    elsif G_MODE = "limit" then
      set_alert_stop_limit(ERROR, 2);
      check_value(false, "one");
      check_value(false, "two");
      report "NOT REACHED";
    elsif G_MODE = "failure" then
      alert(FAILURE, "planted failure");
      report "NOT REACHED";
    elsif G_MODE = "warning" then
      alert(WARNING, "unexpected warning");
    else
      alert(FAILURE, "unknown G_MODE " & G_MODE);
    end if;
    wait_num_rising_edges(clk, 2);
    report_final;
    report "NOT REACHED";
    std.env.stop;
  end process p_main;

end architecture sim;
