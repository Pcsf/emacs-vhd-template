-------------------------------------------------------------------------------
-- File        : tb_debounce.vhd
-- Description : Test cases and tripwire monitors for the debounce ICD
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

use work.tb_util_pkg.all;

entity tb_debounce is
end entity tb_debounce;

architecture sim of tb_debounce is

  constant C_SCOPE  : string := "tb_debounce";
  constant C_PERIOD : time   := 10 ns;
  constant C_OFFSET : time   := 3 ns;      -- din moves this long after a clock edge

  -- 8 kHz and 1 ms give the same C_LIMIT as the design computes: 8 clocks.
  constant C_CLK_HZ      : positive := 8000;
  constant C_DEBOUNCE_MS : positive := 1;
  constant C_LIMIT       : positive := C_CLK_HZ / 1000 * C_DEBOUNCE_MS;

  -- ICD numbers, in clocks.
  constant C_SAMPLES  : positive := C_LIMIT + 1;   -- equal samples needed for a change
  constant C_LATENCY  : positive := C_LIMIT + 3;   -- din change to dout change, edges
  constant C_INTERVAL : positive := C_LIMIT + 1;   -- between two dout changes

  signal clk  : std_logic := '0';
  signal rst  : std_logic := '0';
  signal din  : std_logic := '0';
  signal dout : std_logic;

  -- What the monitors know: din and rst as sampled at the last rising edges,
  -- index 0 the newest.
  signal din_h : std_logic_vector(C_LIMIT + 2 downto 0) := (others => '0');
  signal rst_h : std_logic_vector(C_LIMIT + 2 downto 0) := (others => '0');

  function all_are (v : std_logic_vector; x : std_logic) return boolean is
  begin
    for i in v'range loop
      if v(i) /= x then
        return false;
      end if;
    end loop;
    return true;
  end function all_are;

begin

  p_clk : process
  begin
    clock_generator(clk, C_PERIOD, 50);
  end process p_clk;

  u_dut : entity work.debounce
    generic map (G_CLK_HZ => C_CLK_HZ, G_DEBOUNCE_MS => C_DEBOUNCE_MS)
    port map (clk => clk, rst => rst, din => din, dout => dout);

  p_history : process (clk)
  begin
    if rising_edge(clk) then
      din_h <= din_h(din_h'high - 1 downto 0) & din;
      rst_h <= rst_h(rst_h'high - 1 downto 0) & rst;
    end if;
  end process p_history;

  -----------------------------------------------------------------------------
  -- Tripwire monitors: one per ICD clause, they drive nothing.
  -----------------------------------------------------------------------------

  -- dout takes a value only after din showed it at C_SAMPLES consecutive
  -- clock edges; the two newest samples are still inside the synchronizer.
  p_tw_filter : process
    variable prev : std_logic := '0';
  begin
    wait until falling_edge(clk);
    if dout /= prev and rst_h(0) = '0' then
      if not all_are(din_h(C_LIMIT + 2 downto 2), dout) then
        alert(ERROR, "[icd#filter] dout changed without " &
              integer'image(C_SAMPLES) & " equal samples of din", C_SCOPE);
      end if;
    end if;
    prev := dout;
  end process p_tw_filter;

  -- din held for C_SAMPLES samples is passed on, two clocks after the last one.
  p_tw_latency : process
  begin
    wait until falling_edge(clk);
    if all_are(rst_h, '0') then
      for x in std_logic range '0' to '1' loop
        if all_are(din_h(C_LIMIT + 2 downto 2), x) and dout /= x then
          alert(ERROR, "[icd#latency] din was stable but dout did not follow", C_SCOPE);
        end if;
      end loop;
    end if;
  end process p_tw_latency;

  -- Two changes of dout are never closer than C_INTERVAL clocks.
  p_tw_min_interval : process
    variable prev  : std_logic := '0';
    variable since : natural   := C_INTERVAL;
  begin
    wait until falling_edge(clk);
    if dout /= prev then
      if since < C_INTERVAL and rst_h(0) = '0' then
        alert(ERROR, "[icd#min-interval] dout changed again after " &
              integer'image(since) & " clocks", C_SCOPE);
      end if;
      since := 0;
    end if;
    if since < C_INTERVAL then
      since := since + 1;
    end if;
    prev := dout;
  end process p_tw_min_interval;

  -- dout is low from the clock after rst is sampled high.
  p_tw_reset : process
  begin
    wait until falling_edge(clk);
    if rst_h(0) = '1' and dout /= '0' then
      alert(ERROR, "[icd#reset] dout is not low under reset", C_SCOPE);
    end if;
  end process p_tw_reset;

  -----------------------------------------------------------------------------
  -- Test cases
  -----------------------------------------------------------------------------
  p_main : process

    -- Hold din at `value` for exactly `samples` clock edges.  Called and left
    -- C_OFFSET after a rising edge.
    procedure din_for (constant value : in std_logic; constant samples : in positive) is
    begin
      din <= value;
      wait_num_rising_edges(clk, samples);
      wait for C_OFFSET;
    end procedure din_for;

    procedure idle (constant clocks : in positive) is
    begin
      wait_num_rising_edges(clk, clocks);
      wait for C_OFFSET;
    end procedure idle;

  begin
    wait until rising_edge(clk);
    wait for C_OFFSET;

    tc_start("TC-01", "reset leaves dout low", C_SCOPE);
    rst <= '1';
    idle(3);
    check_value(dout, '0', "dout under reset", C_SCOPE);
    rst <= '0';
    idle(C_LATENCY + 2);
    check_value(dout, '0', "dout stays low while din is low", C_SCOPE);

    tc_start("TC-02", "a rising din is passed on after the stated latency", C_SCOPE);
    din <= '1';
    idle(C_LATENCY - 1);
    check_value(dout, '0', "one clock before the latency has passed", C_SCOPE);
    idle(1);
    check_value(dout, '1', "after C_LATENCY clock edges", C_SCOPE);

    tc_start("TC-03", "a falling din is passed on after the same latency", C_SCOPE);
    din <= '0';
    idle(C_LATENCY - 1);
    check_value(dout, '1', "one clock before the latency has passed", C_SCOPE);
    idle(1);
    check_value(dout, '0', "after C_LATENCY clock edges", C_SCOPE);

    tc_start("TC-04", "the longest pulse that is ignored: one sample short", C_SCOPE);
    din_for('1', C_SAMPLES - 1);
    din <= '0';
    idle(C_LATENCY + 2);
    check_stable(dout, (C_LATENCY + C_SAMPLES) * C_PERIOD, "dout did not move", C_SCOPE);
    check_value(dout, '0', "dout still low", C_SCOPE);

    tc_start("TC-05", "the shortest pulse that is passed on", C_SCOPE);
    din_for('1', C_SAMPLES);
    din <= '0';
    idle(2);
    check_value(dout, '1', "pulse accepted", C_SCOPE);
    idle(C_SAMPLES + 2);
    check_value(dout, '0', "and released again", C_SCOPE);

    tc_start("TC-10", "a bouncing contact gives exactly one change", C_SCOPE);
    for i in 1 to 6 loop                       -- each rest is shorter than C_SAMPLES
      din_for('1', 1 + (i mod (C_SAMPLES - 1)));
      din_for('0', 1 + ((i * 3) mod (C_SAMPLES - 1)));
    end loop;
    check_value(dout, '0', "nothing passed while it bounced", C_SCOPE);
    din <= '1';
    idle(C_LATENCY);
    check_value(dout, '1', "the settled level is passed on", C_SCOPE);
    din <= '0';
    idle(C_LATENCY);

    tc_start("TC-11", "glitches at every phase of the clock are ignored", C_SCOPE);
    for phase in 1 to 9 loop
      wait until rising_edge(clk);
      wait for phase * C_PERIOD / 10;
      din <= '1';
      wait for (C_SAMPLES - 1) * C_PERIOD - 1 ns;
      din <= '0';
      wait_num_rising_edges(clk, C_LATENCY + 1);
      check_value(dout, '0', "glitch at phase " & integer'image(phase) & "/10", C_SCOPE);
    end loop;
    wait for C_OFFSET;

    tc_start("TC-12", "an input that never rests is never passed on", C_SCOPE);
    for i in 1 to 20 loop
      din_for('1', C_SAMPLES - 1);
      din_for('0', C_SAMPLES - 1);
    end loop;
    check_stable(dout, 40 * (C_SAMPLES - 1) * C_PERIOD, "dout did not move", C_SCOPE);

    tc_start("TC-13", "reset restarts the count and forces dout low while din is high", C_SCOPE);
    din <= '1';
    idle(C_LATENCY - 2);                       -- two clocks before it would be passed on
    rst <= '1';
    idle(2);
    rst <= '0';
    check_value(dout, '0', "count was restarted", C_SCOPE);
    idle(C_SAMPLES - 1);
    check_value(dout, '0', "one clock before the full time after reset", C_SCOPE);
    idle(1);
    check_value(dout, '1', "full time after reset", C_SCOPE);
    rst <= '1';
    idle(1);
    check_value(dout, '0', "reset wins over a high din", C_SCOPE);
    rst <= '0';
    idle(C_SAMPLES);
    check_value(dout, '1', "and din is passed on again", C_SCOPE);
    din <= '0';
    idle(C_LATENCY);

    tc_start("TC-14", "a change taken back right after it was passed on is ignored", C_SCOPE);
    din_for('1', C_SAMPLES);
    din_for('0', 1);                           -- one sample, as dout rises
    din <= '1';
    idle(C_LATENCY + 2);
    check_value(dout, '1', "dout stayed high", C_SCOPE);
    check_stable(dout, C_LATENCY * C_PERIOD, "and did not move", C_SCOPE);
    din <= '0';
    idle(C_LATENCY);

    report_final(C_SCOPE);
    std.env.stop;
  end process p_main;

end architecture sim;
