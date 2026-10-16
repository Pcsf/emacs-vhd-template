{{!Test-first testbench for a two-process block: port records, numbered test cases, make test verdict}}
{{>header.vhd}}

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.{{entity|$stem}}_pkg.all;

entity {{tb|$file}} is
end entity {{tb}};

architecture sim of {{tb}} is

  constant C_CLK_PERIOD : time := {{period|10 ns}};

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal {{iface|ctl}}i : {{entity}}_in_type;
  signal {{iface}}o : {{entity}}_out_type;

begin

  clk <= not clk after C_CLK_PERIOD / 2;

  u_dut : entity work.{{entity}}
    port map (
      clk  => clk,
      rst  => rst,
      {{iface}}i => {{iface}}i,
      {{iface}}o => {{iface}}o
    );

  -- Inputs change just after a rising edge; outputs are checked on the
  -- falling edge, half a period after the edge that updated them.
  p_stim : process
    variable errors : natural := 0;

    procedure check (condition : boolean; tc : string) is
    begin
      if not condition then
        errors := errors + 1;
        report tc & " FAILED" severity error;
      end if;
    end procedure check;

    procedure clocks (n : positive := 1) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk);
      end loop;
    end procedure clocks;
  begin
    {{iface}}i.start <= '0';
    clocks(2);
    rst <= '0';

    -- Passes on the empty skeleton: make it fail once with a mutant.
    wait until falling_edge(clk);
    check({{iface}}o.busy = '0' and {{iface}}o.done = '0',
          "TC-01 reset leaves busy and done low");

    clocks;
    {{iface}}i.start <= '1';
    clocks;
    {{iface}}i.start <= '0';
    wait until falling_edge(clk);
    check({{iface}}o.busy = '1', "TC-02 start raises busy on the next clock");

    {{_}}

    if errors = 0 then
      report "TEST PASSED";
    else
      report "TEST FAILED: " & integer'image(errors) & " check(s)" severity error;
    end if;
    std.env.stop;
    wait;
  end process p_stim;

end architecture sim;
