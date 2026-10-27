{{!Testbench utilities in the UVVM style: log, alerts, check_value, await_*, gen_pulse, clock_generator, random, final report}}
{{>header.vhd}}

-- Self-contained testbench support, no library to build: analyse this file
-- first, then the BFMs (bfm_*_pkg) and the testbench.  VHDL-2008.
--
--   p_clk : process begin clock_generator(clk, 10 ns, 50); end process;
--   gen_pulse(rst, '1', clk, 4, "reset");          -- high for 4 clocks
--   tc_start("TC-01", "dout follows din");          -- header, tags every alert
--   check_value(dout, x"A5", "dout");               -- counted, run continues
--   await_value(done, '1', 0 ns, 1 us, "done");     -- alert on timeout
--   await_stable(dout, 100 ns, 1 us, "dout");
--   increment_expected_alerts(ERROR, 1);            -- for a negative test
--   report_final(C_SCOPE);                          -- then std.env.stop
--
-- Every line goes to the simulator's output as "<time> <scope> <message>".
-- Alerts never stop the run (set_alert_stop_limit changes that); they are
-- counted and summed up by report_final: "TEST PASSED" when every level
-- has as many alerts as were expected, otherwise a failure that stops the
-- simulation, so `ghdl -r` and `make test` fail.
-- set_log_verbosity(C_LOG_BFM) also prints every passing check.
-- The names follow uvvm_util; there check_value takes the alert level
-- before the message.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

package {{pkg|$file}} is

  constant C_TB_SCOPE_DEFAULT : string := "TB";

  constant C_LOG_HDR   : natural := 1;   -- test case headers
  constant C_LOG_BFM   : natural := 2;   -- every transaction and passing check
  constant C_LOG_DEBUG : natural := 3;

  type t_alert_level is (WARNING, ERROR, FAILURE);

  type t_slv_array is array (natural range <>) of std_logic_vector;

  -- Log and test cases -------------------------------------------------------

  procedure set_log_verbosity (constant level : in natural);

  procedure log (constant level : in natural;
                 constant msg   : in string;
                 constant scope : in string := C_TB_SCOPE_DEFAULT);

  -- Logs a header and prefixes every alert with NAME until the next call.
  procedure tc_start (constant name  : in string;
                      constant msg   : in string := "";
                      constant scope : in string := C_TB_SCOPE_DEFAULT);

  -- Alerts ------------------------------------------------------------------

  procedure alert (constant level : in t_alert_level;
                   constant msg   : in string;
                   constant scope : in string := C_TB_SCOPE_DEFAULT);

  procedure increment_expected_alerts (constant level : in t_alert_level;
                                       constant n     : in natural := 1);

  -- 0 never stops; N stops the run at the Nth alert of that level.
  procedure set_alert_stop_limit (constant level : in t_alert_level;
                                  constant limit : in natural);

  impure function get_alert_count (constant level : in t_alert_level) return natural;

  -- Checks ------------------------------------------------------------------

  procedure check_value (constant condition : in boolean;
                         constant msg       : in string;
                         constant scope     : in string        := C_TB_SCOPE_DEFAULT;
                         constant level     : in t_alert_level := ERROR);

  procedure check_value (constant actual   : in std_logic_vector;
                         constant expected : in std_logic_vector;
                         constant msg      : in string;
                         constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                         constant level    : in t_alert_level := ERROR);

  procedure check_value (constant actual   : in unsigned;
                         constant expected : in unsigned;
                         constant msg      : in string;
                         constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                         constant level    : in t_alert_level := ERROR);

  procedure check_value (constant actual   : in signed;
                         constant expected : in signed;
                         constant msg      : in string;
                         constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                         constant level    : in t_alert_level := ERROR);

  procedure check_value (constant actual   : in std_logic;
                         constant expected : in std_logic;
                         constant msg      : in string;
                         constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                         constant level    : in t_alert_level := ERROR);

  procedure check_value (constant actual   : in integer;
                         constant expected : in integer;
                         constant msg      : in string;
                         constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                         constant level    : in t_alert_level := ERROR);

  procedure check_value (constant actual   : in boolean;
                         constant expected : in boolean;
                         constant msg      : in string;
                         constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                         constant level    : in t_alert_level := ERROR);

  procedure check_value (constant actual   : in time;
                         constant expected : in time;
                         constant msg      : in string;
                         constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                         constant level    : in t_alert_level := ERROR);

  procedure check_value (constant actual   : in string;
                         constant expected : in string;
                         constant msg      : in string;
                         constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                         constant level    : in t_alert_level := ERROR);

  procedure check_value_in_range (constant actual  : in integer;
                                  constant min_val : in integer;
                                  constant max_val : in integer;
                                  constant msg     : in string;
                                  constant scope   : in string        := C_TB_SCOPE_DEFAULT;
                                  constant level   : in t_alert_level := ERROR);

  procedure check_value_in_range (constant actual  : in unsigned;
                                  constant min_val : in unsigned;
                                  constant max_val : in unsigned;
                                  constant msg     : in string;
                                  constant scope   : in string        := C_TB_SCOPE_DEFAULT;
                                  constant level   : in t_alert_level := ERROR);

  procedure check_value_in_range (constant actual  : in time;
                                  constant min_val : in time;
                                  constant max_val : in time;
                                  constant msg     : in string;
                                  constant scope   : in string        := C_TB_SCOPE_DEFAULT;
                                  constant level   : in t_alert_level := ERROR);

  -- The signal has not changed for at least STABLE_REQ.
  procedure check_stable (signal   target     : in std_logic;
                          constant stable_req : in time;
                          constant msg        : in string;
                          constant scope      : in string        := C_TB_SCOPE_DEFAULT;
                          constant level      : in t_alert_level := ERROR);

  procedure check_stable (signal   target     : in std_logic_vector;
                          constant stable_req : in time;
                          constant msg        : in string;
                          constant scope      : in string        := C_TB_SCOPE_DEFAULT;
                          constant level      : in t_alert_level := ERROR);

  -- Waiting -----------------------------------------------------------------

  procedure wait_num_rising_edges (signal   clk : in std_logic;
                                   constant n   : in natural);

  procedure wait_num_falling_edges (signal   clk : in std_logic;
                                    constant n   : in natural);

  -- Wait until TARGET = EXPECTED.  Alert when that takes longer than MAX_TIME
  -- or happens before MIN_TIME.
  procedure await_value (signal   target   : in std_logic;
                         constant expected : in std_logic;
                         constant min_time : in time;
                         constant max_time : in time;
                         constant msg      : in string;
                         constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                         constant level    : in t_alert_level := ERROR);

  procedure await_value (signal   target   : in std_logic_vector;
                         constant expected : in std_logic_vector;
                         constant min_time : in time;
                         constant max_time : in time;
                         constant msg      : in string;
                         constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                         constant level    : in t_alert_level := ERROR);

  procedure await_value (signal   target   : in unsigned;
                         constant expected : in unsigned;
                         constant min_time : in time;
                         constant max_time : in time;
                         constant msg      : in string;
                         constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                         constant level    : in t_alert_level := ERROR);

  procedure await_value (signal   target   : in integer;
                         constant expected : in integer;
                         constant min_time : in time;
                         constant max_time : in time;
                         constant msg      : in string;
                         constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                         constant level    : in t_alert_level := ERROR);

  procedure await_value (signal   target   : in boolean;
                         constant expected : in boolean;
                         constant min_time : in time;
                         constant max_time : in time;
                         constant msg      : in string;
                         constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                         constant level    : in t_alert_level := ERROR);

  -- Wait for any change of TARGET, within MIN_TIME .. MAX_TIME.
  procedure await_change (signal   target   : in std_logic;
                          constant min_time : in time;
                          constant max_time : in time;
                          constant msg      : in string;
                          constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                          constant level    : in t_alert_level := ERROR);

  procedure await_change (signal   target   : in std_logic_vector;
                          constant min_time : in time;
                          constant max_time : in time;
                          constant msg      : in string;
                          constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                          constant level    : in t_alert_level := ERROR);

  procedure await_change (signal   target   : in integer;
                          constant min_time : in time;
                          constant max_time : in time;
                          constant msg      : in string;
                          constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                          constant level    : in t_alert_level := ERROR);

  -- Wait until TARGET has been unchanged for STABLE_REQ; alert when that
  -- does not happen within TIMEOUT.
  procedure await_stable (signal   target     : in std_logic;
                          constant stable_req : in time;
                          constant timeout    : in time;
                          constant msg        : in string;
                          constant scope      : in string        := C_TB_SCOPE_DEFAULT;
                          constant level      : in t_alert_level := ERROR);

  procedure await_stable (signal   target     : in std_logic_vector;
                          constant stable_req : in time;
                          constant timeout    : in time;
                          constant msg        : in string;
                          constant scope      : in string        := C_TB_SCOPE_DEFAULT;
                          constant level      : in t_alert_level := ERROR);

  -- Stimulus ----------------------------------------------------------------

  -- Drive PULSE_VALUE for DURATION or NUM_PERIODS rising edges, then restore
  -- the value the signal had before.
  procedure gen_pulse (signal   target      : inout std_logic;
                       constant pulse_value : in    std_logic;
                       constant duration    : in    time;
                       constant msg         : in    string;
                       constant scope       : in    string := C_TB_SCOPE_DEFAULT);

  procedure gen_pulse (signal   target      : inout std_logic;
                       constant pulse_value : in    std_logic;
                       signal   clk         : in    std_logic;
                       constant num_periods : in    positive;
                       constant msg         : in    string;
                       constant scope       : in    string := C_TB_SCOPE_DEFAULT);

  procedure gen_pulse (signal   target      : inout std_logic_vector;
                       constant pulse_value : in    std_logic_vector;
                       constant duration    : in    time;
                       constant msg         : in    string;
                       constant scope       : in    string := C_TB_SCOPE_DEFAULT);

  procedure gen_pulse (signal   target      : inout std_logic_vector;
                       constant pulse_value : in    std_logic_vector;
                       signal   clk         : in    std_logic;
                       constant num_periods : in    positive;
                       constant msg         : in    string;
                       constant scope       : in    string := C_TB_SCOPE_DEFAULT);

  -- Never returns: call it from a process of its own.
  procedure clock_generator (signal   clk            : inout std_logic;
                             constant period         : in    time;
                             constant duty_cycle_pct : in    natural range 1 to 99 := 50);

  -- Same, with the clock stopped low while ENA is false.
  procedure clock_generator (signal   clk            : inout std_logic;
                             signal   ena            : in    boolean;
                             constant period         : in    time;
                             constant duty_cycle_pct : in    natural range 1 to 99 := 50);

  -- Random ------------------------------------------------------------------

  procedure set_random_seed (constant seed : in positive);

  impure function random (constant min_val : in integer;
                          constant max_val : in integer) return integer;

  impure function random (constant length : in positive) return std_logic_vector;

  impure function random return std_logic;

  -- Final report ------------------------------------------------------------

  -- Alert totals per level against the expected ones; "TEST PASSED" when
  -- they all match, otherwise a failure that stops the simulation.
  procedure report_final (constant scope : in string := C_TB_SCOPE_DEFAULT);

end package {{pkg}};

package body {{pkg}} is

  function fmt (constant t : in time) return string is
  begin
    return to_string(t, ns);
  end function fmt;

  function fmt (constant level : in t_alert_level) return string is
  begin
    return t_alert_level'image(level);
  end function fmt;

  procedure put (constant scope : in string; constant msg : in string) is
    constant C_TIME  : string := fmt(now);
    constant C_WIDTH : natural := 12;
    variable v_line  : line;
  begin
    if C_TIME'length < C_WIDTH then
      write(v_line, string'(1 to C_WIDTH - C_TIME'length => ' '));
    end if;
    write(v_line, C_TIME & "  " & scope & ": " & msg);
    writeline(output, v_line);
    flush(output);
  end procedure put;

  -- All state lives in one protected variable, so several processes can
  -- log and check at the same time.
  type t_tb_state is protected
    procedure set_verbosity (level : natural);
    impure function get_verbosity return natural;
    procedure set_tc (name : string);
    impure function get_tc return string;
    procedure increment (level : t_alert_level);
    procedure increment_expected (level : t_alert_level; n : natural);
    procedure set_stop_limit (level : t_alert_level; limit : natural);
    impure function get_count (level : t_alert_level) return natural;
    impure function get_expected (level : t_alert_level) return natural;
    impure function stop_limit_reached (level : t_alert_level) return boolean;
    impure function get_failed_tcs return string;
    procedure set_seed (seed : positive);
    impure function next_random return natural;
  end protected t_tb_state;

  type t_tb_state is protected body
    type t_counts is array (t_alert_level) of natural;
    constant C_TC_MAX     : natural := 64;
    constant C_FAILED_MAX : natural := 1024;

    variable verbosity  : natural := C_LOG_HDR;
    variable counts     : t_counts := (others => 0);
    variable expected   : t_counts := (others => 0);
    variable limits     : t_counts := (others => 0);
    variable tc_name    : string(1 to C_TC_MAX);
    variable tc_len     : natural := 0;
    variable tc_failed  : boolean := false;
    variable failed     : string(1 to C_FAILED_MAX);
    variable failed_len : natural := 0;
    variable rng        : unsigned(31 downto 0) := x"2545F491";

    procedure set_verbosity (level : natural) is
    begin
      verbosity := level;
    end procedure set_verbosity;

    impure function get_verbosity return natural is
    begin
      return verbosity;
    end function get_verbosity;

    procedure set_tc (name : string) is
      constant C_LEN : natural := minimum(name'length, C_TC_MAX);
    begin
      tc_name(1 to C_LEN) := name(name'left to name'left + C_LEN - 1);
      tc_len    := C_LEN;
      tc_failed := false;
    end procedure set_tc;

    impure function get_tc return string is
    begin
      return tc_name(1 to tc_len);
    end function get_tc;

    procedure increment (level : t_alert_level) is
      constant C_ENTRY : string := get_tc & " ";
    begin
      counts(level) := counts(level) + 1;
      if level /= WARNING and tc_len > 0 and not tc_failed
         and failed_len + C_ENTRY'length <= C_FAILED_MAX then
        failed(failed_len + 1 to failed_len + C_ENTRY'length) := C_ENTRY;
        failed_len := failed_len + C_ENTRY'length;
        tc_failed  := true;
      end if;
    end procedure increment;

    procedure increment_expected (level : t_alert_level; n : natural) is
    begin
      expected(level) := expected(level) + n;
    end procedure increment_expected;

    procedure set_stop_limit (level : t_alert_level; limit : natural) is
    begin
      limits(level) := limit;
    end procedure set_stop_limit;

    impure function get_count (level : t_alert_level) return natural is
    begin
      return counts(level);
    end function get_count;

    impure function get_expected (level : t_alert_level) return natural is
    begin
      return expected(level);
    end function get_expected;

    impure function stop_limit_reached (level : t_alert_level) return boolean is
    begin
      return limits(level) > 0 and counts(level) >= limits(level);
    end function stop_limit_reached;

    impure function get_failed_tcs return string is
    begin
      return failed(1 to failed_len);
    end function get_failed_tcs;

    procedure set_seed (seed : positive) is
    begin
      rng := to_unsigned(seed, 32);
    end procedure set_seed;

    -- xorshift32
    impure function next_random return natural is
      variable v : unsigned(31 downto 0) := rng;
    begin
      v := v xor (v sll 13);
      v := v xor (v srl 17);
      v := v xor (v sll 5);
      rng := v;
      return to_integer(v(30 downto 0));
    end function next_random;
  end protected body t_tb_state;

  shared variable sv_tb : t_tb_state;

  -- Log and test cases -------------------------------------------------------

  procedure set_log_verbosity (constant level : in natural) is
  begin
    sv_tb.set_verbosity(level);
  end procedure set_log_verbosity;

  procedure log (constant level : in natural;
                 constant msg   : in string;
                 constant scope : in string := C_TB_SCOPE_DEFAULT) is
  begin
    if sv_tb.get_verbosity >= level then
      put(scope, msg);
    end if;
  end procedure log;

  procedure tc_start (constant name  : in string;
                      constant msg   : in string := "";
                      constant scope : in string := C_TB_SCOPE_DEFAULT) is
  begin
    sv_tb.set_tc(name);
    if msg = "" then
      log(C_LOG_HDR, "==== " & name, scope);
    else
      log(C_LOG_HDR, "==== " & name & ": " & msg, scope);
    end if;
  end procedure tc_start;

  -- Alerts ------------------------------------------------------------------

  procedure alert (constant level : in t_alert_level;
                   constant msg   : in string;
                   constant scope : in string := C_TB_SCOPE_DEFAULT) is
    constant C_TC : string := sv_tb.get_tc;
  begin
    sv_tb.increment(level);
    if C_TC = "" then
      put(scope, fmt(level) & ": " & msg);
    else
      put(scope, fmt(level) & ": [" & C_TC & "] " & msg);
    end if;
    if level = FAILURE then
      report_final(scope);
      report scope & ": stopped by a FAILURE alert" severity failure;
    elsif sv_tb.stop_limit_reached(level) then
      put(scope, "alert stop limit reached for " & fmt(level));
      report_final(scope);
      report scope & ": stopped at the alert stop limit" severity failure;
    end if;
  end procedure alert;

  procedure increment_expected_alerts (constant level : in t_alert_level;
                                       constant n     : in natural := 1) is
  begin
    sv_tb.increment_expected(level, n);
  end procedure increment_expected_alerts;

  procedure set_alert_stop_limit (constant level : in t_alert_level;
                                  constant limit : in natural) is
  begin
    sv_tb.set_stop_limit(level, limit);
  end procedure set_alert_stop_limit;

  impure function get_alert_count (constant level : in t_alert_level) return natural is
  begin
    return sv_tb.get_count(level);
  end function get_alert_count;

  -- Checks ------------------------------------------------------------------

  procedure check_result (constant ok       : in boolean;
                          constant msg      : in string;
                          constant detail   : in string;
                          constant scope    : in string;
                          constant level    : in t_alert_level) is
  begin
    if ok then
      log(C_LOG_BFM, "OK: " & msg & detail, scope);
    else
      alert(level, "CHECK FAILED: " & msg & detail, scope);
    end if;
  end procedure check_result;

  procedure check_value (constant condition : in boolean;
                         constant msg       : in string;
                         constant scope     : in string        := C_TB_SCOPE_DEFAULT;
                         constant level     : in t_alert_level := ERROR) is
  begin
    check_result(condition, msg, "", scope, level);
  end procedure check_value;

  procedure check_value (constant actual   : in std_logic_vector;
                         constant expected : in std_logic_vector;
                         constant msg      : in string;
                         constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                         constant level    : in t_alert_level := ERROR) is
  begin
    if actual'length /= expected'length then
      alert(level, "CHECK FAILED: " & msg & ", width " & integer'image(actual'length)
            & " against expected width " & integer'image(expected'length), scope);
    elsif actual = expected then
      check_result(true, msg, " = 0x" & to_hstring(actual), scope, level);
    else
      check_result(false, msg, ", expected 0x" & to_hstring(expected)
                   & " got 0x" & to_hstring(actual), scope, level);
    end if;
  end procedure check_value;

  procedure check_value (constant actual   : in unsigned;
                         constant expected : in unsigned;
                         constant msg      : in string;
                         constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                         constant level    : in t_alert_level := ERROR) is
  begin
    check_result(actual = expected, msg,
                 ", expected " & to_string(to_integer(expected))
                 & " got " & to_string(to_integer(actual)), scope, level);
  end procedure check_value;

  procedure check_value (constant actual   : in signed;
                         constant expected : in signed;
                         constant msg      : in string;
                         constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                         constant level    : in t_alert_level := ERROR) is
  begin
    check_result(actual = expected, msg,
                 ", expected " & to_string(to_integer(expected))
                 & " got " & to_string(to_integer(actual)), scope, level);
  end procedure check_value;

  procedure check_value (constant actual   : in std_logic;
                         constant expected : in std_logic;
                         constant msg      : in string;
                         constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                         constant level    : in t_alert_level := ERROR) is
  begin
    check_result(actual = expected, msg,
                 ", expected " & to_string(expected) & " got " & to_string(actual),
                 scope, level);
  end procedure check_value;

  procedure check_value (constant actual   : in integer;
                         constant expected : in integer;
                         constant msg      : in string;
                         constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                         constant level    : in t_alert_level := ERROR) is
  begin
    check_result(actual = expected, msg,
                 ", expected " & to_string(expected) & " got " & to_string(actual),
                 scope, level);
  end procedure check_value;

  procedure check_value (constant actual   : in boolean;
                         constant expected : in boolean;
                         constant msg      : in string;
                         constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                         constant level    : in t_alert_level := ERROR) is
  begin
    check_result(actual = expected, msg,
                 ", expected " & to_string(expected) & " got " & to_string(actual),
                 scope, level);
  end procedure check_value;

  procedure check_value (constant actual   : in time;
                         constant expected : in time;
                         constant msg      : in string;
                         constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                         constant level    : in t_alert_level := ERROR) is
  begin
    check_result(actual = expected, msg,
                 ", expected " & fmt(expected) & " got " & fmt(actual), scope, level);
  end procedure check_value;

  procedure check_value (constant actual   : in string;
                         constant expected : in string;
                         constant msg      : in string;
                         constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                         constant level    : in t_alert_level := ERROR) is
  begin
    check_result(actual = expected, msg,
                 ", expected """ & expected & """ got """ & actual & """", scope, level);
  end procedure check_value;

  procedure check_value_in_range (constant actual  : in integer;
                                  constant min_val : in integer;
                                  constant max_val : in integer;
                                  constant msg     : in string;
                                  constant scope   : in string        := C_TB_SCOPE_DEFAULT;
                                  constant level   : in t_alert_level := ERROR) is
  begin
    check_result(actual >= min_val and actual <= max_val, msg,
                 ", " & to_string(actual) & " in " & to_string(min_val)
                 & " .. " & to_string(max_val), scope, level);
  end procedure check_value_in_range;

  procedure check_value_in_range (constant actual  : in unsigned;
                                  constant min_val : in unsigned;
                                  constant max_val : in unsigned;
                                  constant msg     : in string;
                                  constant scope   : in string        := C_TB_SCOPE_DEFAULT;
                                  constant level   : in t_alert_level := ERROR) is
  begin
    check_value_in_range(to_integer(actual), to_integer(min_val), to_integer(max_val),
                         msg, scope, level);
  end procedure check_value_in_range;

  procedure check_value_in_range (constant actual  : in time;
                                  constant min_val : in time;
                                  constant max_val : in time;
                                  constant msg     : in string;
                                  constant scope   : in string        := C_TB_SCOPE_DEFAULT;
                                  constant level   : in t_alert_level := ERROR) is
  begin
    check_result(actual >= min_val and actual <= max_val, msg,
                 ", " & fmt(actual) & " in " & fmt(min_val) & " .. " & fmt(max_val),
                 scope, level);
  end procedure check_value_in_range;

  procedure check_stable (signal   target     : in std_logic;
                          constant stable_req : in time;
                          constant msg        : in string;
                          constant scope      : in string        := C_TB_SCOPE_DEFAULT;
                          constant level      : in t_alert_level := ERROR) is
  begin
    check_result(target'last_event >= stable_req, msg,
                 ", stable for " & fmt(target'last_event) & " of " & fmt(stable_req),
                 scope, level);
  end procedure check_stable;

  procedure check_stable (signal   target     : in std_logic_vector;
                          constant stable_req : in time;
                          constant msg        : in string;
                          constant scope      : in string        := C_TB_SCOPE_DEFAULT;
                          constant level      : in t_alert_level := ERROR) is
  begin
    check_result(target'last_event >= stable_req, msg,
                 ", stable for " & fmt(target'last_event) & " of " & fmt(stable_req),
                 scope, level);
  end procedure check_stable;

  -- Waiting -----------------------------------------------------------------

  procedure wait_num_rising_edges (signal   clk : in std_logic;
                                   constant n   : in natural) is
  begin
    for i in 1 to n loop
      wait until rising_edge(clk);
    end loop;
  end procedure wait_num_rising_edges;

  procedure wait_num_falling_edges (signal   clk : in std_logic;
                                    constant n   : in natural) is
  begin
    for i in 1 to n loop
      wait until falling_edge(clk);
    end loop;
  end procedure wait_num_falling_edges;

  procedure await_result (constant reached  : in boolean;
                          constant elapsed  : in time;
                          constant min_time : in time;
                          constant max_time : in time;
                          constant what     : in string;
                          constant msg      : in string;
                          constant scope    : in string;
                          constant level    : in t_alert_level) is
  begin
    if not reached then
      alert(level, what & ": " & msg & ", timeout after " & fmt(max_time), scope);
    elsif elapsed < min_time then
      alert(level, what & ": " & msg & " after " & fmt(elapsed)
            & ", before the minimum of " & fmt(min_time), scope);
    else
      log(C_LOG_BFM, what & ": " & msg & " after " & fmt(elapsed), scope);
    end if;
  end procedure await_result;

  procedure await_value (signal   target   : in std_logic;
                         constant expected : in std_logic;
                         constant min_time : in time;
                         constant max_time : in time;
                         constant msg      : in string;
                         constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                         constant level    : in t_alert_level := ERROR) is
    constant C_START : time := now;
  begin
    if target /= expected then
      wait until target = expected for max_time;
    end if;
    await_result(target = expected, now - C_START, min_time, max_time,
                 "await_value", msg & " = " & to_string(expected), scope, level);
  end procedure await_value;

  procedure await_value (signal   target   : in std_logic_vector;
                         constant expected : in std_logic_vector;
                         constant min_time : in time;
                         constant max_time : in time;
                         constant msg      : in string;
                         constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                         constant level    : in t_alert_level := ERROR) is
    constant C_START : time := now;
  begin
    if target /= expected then
      wait until target = expected for max_time;
    end if;
    await_result(target = expected, now - C_START, min_time, max_time,
                 "await_value", msg & " = 0x" & to_hstring(expected), scope, level);
  end procedure await_value;

  procedure await_value (signal   target   : in unsigned;
                         constant expected : in unsigned;
                         constant min_time : in time;
                         constant max_time : in time;
                         constant msg      : in string;
                         constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                         constant level    : in t_alert_level := ERROR) is
    constant C_START : time := now;
  begin
    if target /= expected then
      wait until target = expected for max_time;
    end if;
    await_result(target = expected, now - C_START, min_time, max_time,
                 "await_value", msg & " = " & to_string(to_integer(expected)),
                 scope, level);
  end procedure await_value;

  procedure await_value (signal   target   : in integer;
                         constant expected : in integer;
                         constant min_time : in time;
                         constant max_time : in time;
                         constant msg      : in string;
                         constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                         constant level    : in t_alert_level := ERROR) is
    constant C_START : time := now;
  begin
    if target /= expected then
      wait until target = expected for max_time;
    end if;
    await_result(target = expected, now - C_START, min_time, max_time,
                 "await_value", msg & " = " & to_string(expected), scope, level);
  end procedure await_value;

  procedure await_value (signal   target   : in boolean;
                         constant expected : in boolean;
                         constant min_time : in time;
                         constant max_time : in time;
                         constant msg      : in string;
                         constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                         constant level    : in t_alert_level := ERROR) is
    constant C_START : time := now;
  begin
    if target /= expected then
      wait until target = expected for max_time;
    end if;
    await_result(target = expected, now - C_START, min_time, max_time,
                 "await_value", msg & " = " & to_string(expected), scope, level);
  end procedure await_value;

  procedure await_change (signal   target   : in std_logic;
                          constant min_time : in time;
                          constant max_time : in time;
                          constant msg      : in string;
                          constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                          constant level    : in t_alert_level := ERROR) is
    constant C_START : time := now;
  begin
    wait on target for max_time;
    await_result(target'event, now - C_START, min_time, max_time,
                 "await_change", msg, scope, level);
  end procedure await_change;

  procedure await_change (signal   target   : in std_logic_vector;
                          constant min_time : in time;
                          constant max_time : in time;
                          constant msg      : in string;
                          constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                          constant level    : in t_alert_level := ERROR) is
    constant C_START : time := now;
  begin
    wait on target for max_time;
    await_result(target'event, now - C_START, min_time, max_time,
                 "await_change", msg, scope, level);
  end procedure await_change;

  procedure await_change (signal   target   : in integer;
                          constant min_time : in time;
                          constant max_time : in time;
                          constant msg      : in string;
                          constant scope    : in string        := C_TB_SCOPE_DEFAULT;
                          constant level    : in t_alert_level := ERROR) is
    constant C_START : time := now;
  begin
    wait on target for max_time;
    await_result(target'event, now - C_START, min_time, max_time,
                 "await_change", msg, scope, level);
  end procedure await_change;

  procedure await_stable (signal   target     : in std_logic;
                          constant stable_req : in time;
                          constant timeout    : in time;
                          constant msg        : in string;
                          constant scope      : in string        := C_TB_SCOPE_DEFAULT;
                          constant level      : in t_alert_level := ERROR) is
    constant C_START : time := now;
    variable v_stable : boolean := false;
  begin
    while not v_stable loop
      if target'last_event >= stable_req then
        v_stable := true;
      elsif now + (stable_req - target'last_event) > C_START + timeout then
        wait on target for C_START + timeout - now;
        exit;
      else
        wait on target for stable_req - target'last_event;
      end if;
    end loop;
    await_result(v_stable, now - C_START, 0 ns, timeout,
                 "await_stable", msg & " stable for " & fmt(stable_req), scope, level);
  end procedure await_stable;

  procedure await_stable (signal   target     : in std_logic_vector;
                          constant stable_req : in time;
                          constant timeout    : in time;
                          constant msg        : in string;
                          constant scope      : in string        := C_TB_SCOPE_DEFAULT;
                          constant level      : in t_alert_level := ERROR) is
    constant C_START : time := now;
    variable v_stable : boolean := false;
  begin
    while not v_stable loop
      if target'last_event >= stable_req then
        v_stable := true;
      elsif now + (stable_req - target'last_event) > C_START + timeout then
        wait on target for C_START + timeout - now;
        exit;
      else
        wait on target for stable_req - target'last_event;
      end if;
    end loop;
    await_result(v_stable, now - C_START, 0 ns, timeout,
                 "await_stable", msg & " stable for " & fmt(stable_req), scope, level);
  end procedure await_stable;

  -- Stimulus ----------------------------------------------------------------

  procedure gen_pulse (signal   target      : inout std_logic;
                       constant pulse_value : in    std_logic;
                       constant duration    : in    time;
                       constant msg         : in    string;
                       constant scope       : in    string := C_TB_SCOPE_DEFAULT) is
    constant C_INIT : std_logic := target;
  begin
    log(C_LOG_BFM, "gen_pulse: " & msg & " " & to_string(pulse_value)
        & " for " & fmt(duration), scope);
    target <= pulse_value;
    wait for duration;
    target <= C_INIT;
  end procedure gen_pulse;

  procedure gen_pulse (signal   target      : inout std_logic;
                       constant pulse_value : in    std_logic;
                       signal   clk         : in    std_logic;
                       constant num_periods : in    positive;
                       constant msg         : in    string;
                       constant scope       : in    string := C_TB_SCOPE_DEFAULT) is
    constant C_INIT : std_logic := target;
  begin
    log(C_LOG_BFM, "gen_pulse: " & msg & " " & to_string(pulse_value)
        & " for " & to_string(num_periods) & " clock(s)", scope);
    target <= pulse_value;
    wait_num_rising_edges(clk, num_periods);
    target <= C_INIT;
  end procedure gen_pulse;

  procedure gen_pulse (signal   target      : inout std_logic_vector;
                       constant pulse_value : in    std_logic_vector;
                       constant duration    : in    time;
                       constant msg         : in    string;
                       constant scope       : in    string := C_TB_SCOPE_DEFAULT) is
    constant C_INIT : std_logic_vector(target'range) := target;
  begin
    log(C_LOG_BFM, "gen_pulse: " & msg & " 0x" & to_hstring(pulse_value)
        & " for " & fmt(duration), scope);
    target <= pulse_value;
    wait for duration;
    target <= C_INIT;
  end procedure gen_pulse;

  procedure gen_pulse (signal   target      : inout std_logic_vector;
                       constant pulse_value : in    std_logic_vector;
                       signal   clk         : in    std_logic;
                       constant num_periods : in    positive;
                       constant msg         : in    string;
                       constant scope       : in    string := C_TB_SCOPE_DEFAULT) is
    constant C_INIT : std_logic_vector(target'range) := target;
  begin
    log(C_LOG_BFM, "gen_pulse: " & msg & " 0x" & to_hstring(pulse_value)
        & " for " & to_string(num_periods) & " clock(s)", scope);
    target <= pulse_value;
    wait_num_rising_edges(clk, num_periods);
    target <= C_INIT;
  end procedure gen_pulse;

  procedure clock_generator (signal   clk            : inout std_logic;
                             constant period         : in    time;
                             constant duty_cycle_pct : in    natural range 1 to 99 := 50) is
    constant C_HIGH : time := period * duty_cycle_pct / 100;
  begin
    loop
      clk <= '0';
      wait for period - C_HIGH;
      clk <= '1';
      wait for C_HIGH;
    end loop;
  end procedure clock_generator;

  procedure clock_generator (signal   clk            : inout std_logic;
                             signal   ena            : in    boolean;
                             constant period         : in    time;
                             constant duty_cycle_pct : in    natural range 1 to 99 := 50) is
    constant C_HIGH : time := period * duty_cycle_pct / 100;
  begin
    loop
      clk <= '0';
      if not ena then
        wait until ena;
      end if;
      wait for period - C_HIGH;
      clk <= '1';
      wait for C_HIGH;
    end loop;
  end procedure clock_generator;

  -- Random ------------------------------------------------------------------

  procedure set_random_seed (constant seed : in positive) is
  begin
    sv_tb.set_seed(seed);
  end procedure set_random_seed;

  impure function random (constant min_val : in integer;
                          constant max_val : in integer) return integer is
  begin
    return min_val + sv_tb.next_random mod (max_val - min_val + 1);
  end function random;

  impure function random (constant length : in positive) return std_logic_vector is
    variable v : std_logic_vector(length - 1 downto 0);
  begin
    for i in 0 to (length - 1) / 16 loop
      for b in 0 to 15 loop
        if i * 16 + b < length then
          v(i * 16 + b) := to_unsigned(sv_tb.next_random mod 65536, 16)(b);
        end if;
      end loop;
    end loop;
    return v;
  end function random;

  impure function random return std_logic is
  begin
    if sv_tb.next_random mod 2 = 1 then
      return '1';
    else
      return '0';
    end if;
  end function random;

  -- Final report ------------------------------------------------------------

  procedure report_final (constant scope : in string := C_TB_SCOPE_DEFAULT) is
    variable v_pass : boolean := true;
  begin
    put(scope, "==== final report");
    for level in t_alert_level loop
      if sv_tb.get_count(level) = sv_tb.get_expected(level) then
        put(scope, "  " & fmt(level) & ": " & to_string(sv_tb.get_count(level)));
      else
        put(scope, "  " & fmt(level) & ": " & to_string(sv_tb.get_count(level))
            & ", expected " & to_string(sv_tb.get_expected(level)));
        v_pass := false;
      end if;
    end loop;
    if sv_tb.get_failed_tcs /= "" then
      put(scope, "  test cases with alerts: " & sv_tb.get_failed_tcs);
    end if;
    if v_pass then
      put(scope, "TEST PASSED");
    else
      put(scope, "TEST FAILED");
      report scope & ": TEST FAILED" severity failure;
    end if;
  end procedure report_final;

end package body {{pkg}};
