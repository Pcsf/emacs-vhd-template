{{!Self-checking testbench: clock, reset, check procedure, ends by itself}}
{{>header.vhd}}

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity {{tb|$file}} is
end entity {{tb}};

architecture sim of {{tb}} is

  constant C_CLK_PERIOD : time     := {{period|10 ns}};
  constant C_WIDTH      : positive := 8;

  signal clk      : std_logic := '0';
  signal rst      : std_logic := '1';
  signal din      : std_logic_vector(C_WIDTH - 1 downto 0) := (others => '0');
  signal dout     : std_logic_vector(C_WIDTH - 1 downto 0);
  signal sim_done : boolean   := false;

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

  -- The clock stops when the stimulus is done, which ends the simulation.
  p_clk : process
  begin
    while not sim_done loop
      clk <= '0';
      wait for C_CLK_PERIOD / 2;
      clk <= '1';
      wait for C_CLK_PERIOD / 2;
    end loop;
    wait;
  end process p_clk;

  p_stim : process
    variable errors : natural := 0;

    procedure check (condition : boolean; message : string) is
    begin
      if not condition then
        errors := errors + 1;
        report "CHECK FAILED: " & message severity error;
      end if;
    end procedure check;

    -- Wait for N rising edges plus a little, so outputs have settled and
    -- inputs are driven away from the edge.
    procedure tick (n : positive := 1) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk);
      end loop;
      wait for C_CLK_PERIOD / 10;
    end procedure tick;

    function to_slv (value : natural) return std_logic_vector is
    begin
      return std_logic_vector(to_unsigned(value, C_WIDTH));
    end function to_slv;
  begin
    rst <= '1';
    tick(4);
    rst <= '0';
    tick;

    din <= to_slv(16#A5#);
    tick;
    check(dout = to_slv(16#A5#), "dout follows din after one clock");

    din <= to_slv(16#5A#);
    tick;
    check(dout = to_slv(16#5A#), "dout follows a new din value");

    {{_}}

    tick(2);
    if errors = 0 then
      report "TEST PASSED";
    else
      report "TEST FAILED: " & integer'image(errors) & " error(s)"
        severity failure;
    end if;
    sim_done <= true;
    wait;
  end process p_stim;

end architecture sim;
