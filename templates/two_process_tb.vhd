{{!Test-first testbench for a two-process block on tb_util_pkg: port records, numbered test cases, make test verdict}}
{{>header.vhd}}

-- Needs tb_util_pkg, analysed first.  Inputs change just after a rising
-- edge; outputs are checked on the falling edge, half a period after the
-- edge that updated them.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.tb_util_pkg.all;
use work.{{entity|$stem}}_pkg.all;

entity {{tb|$file}} is
end entity {{tb}};

architecture sim of {{tb}} is

  constant C_CLK_PERIOD : time   := {{period|10 ns}};
  constant C_SCOPE      : string := "{{tb}}";

  signal clk : std_logic := '0';
  signal rst : std_logic := '0';
  signal {{iface|ctl}}i : {{entity}}_in_type;
  signal {{iface}}o : {{entity}}_out_type;

begin

  u_dut : entity work.{{entity}}
    port map (
      clk  => clk,
      rst  => rst,
      {{iface}}i => {{iface}}i,
      {{iface}}o => {{iface}}o
    );

  p_clk : process
  begin
    clock_generator(clk, C_CLK_PERIOD);
  end process p_clk;

  p_main : process
  begin
    {{iface}}i.start <= '0';
    gen_pulse(rst, '1', clk, 2, "reset", C_SCOPE);

    -- Passes on the empty skeleton: make it fail once with a mutant.
    tc_start("TC-01", "reset leaves busy and done low", C_SCOPE);
    wait until falling_edge(clk);
    check_value({{iface}}o.busy, '0', "busy", C_SCOPE);
    check_value({{iface}}o.done, '0', "done", C_SCOPE);

    tc_start("TC-02", "start raises busy on the next clock", C_SCOPE);
    wait_num_rising_edges(clk, 1);
    {{iface}}i.start <= '1';
    wait_num_rising_edges(clk, 1);
    {{iface}}i.start <= '0';
    wait until falling_edge(clk);
    check_value({{iface}}o.busy, '1', "busy", C_SCOPE);

    {{_}}

    report_final(C_SCOPE);
    std.env.stop;
  end process p_main;

  p_watchdog : process
  begin
    wait for {{timeout|1 ms}};
    alert(FAILURE, "watchdog: the test did not finish", C_SCOPE);
  end process p_watchdog;

end architecture sim;
