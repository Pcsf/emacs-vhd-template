{{!BFM utilities: log, alert counters, check_value, final report (used by every bfm_*_pkg)}}
{{>header.vhd}}

-- Self-contained bus functional model support, no UVVM needed.  It follows
-- the UVVM style (config records, scope strings, log / alert / check_value,
-- final report), so testbenches move to UVVM's bitvis_vip_* with little change.
--
-- Rules shared by all BFMs in this family:
--   * Procedures are called from a process and take the clock as a signal.
--   * They drive their outputs right after a rising clock edge and sample
--     inputs at the rising edge (the values just before it).
--   * Errors are counted here, never stop the simulation, and are summed up
--     by bfm_report_final, which prints "TEST PASSED" or fails with
--     severity failure (so `ghdl -r` exits non-zero).
--   * Unconstrained arrays of vectors (t_slv_array) need VHDL-2008.

library ieee;
use ieee.std_logic_1164.all;

package bfm_util_pkg is

  constant C_BFM_SCOPE : string := "BFM";

  constant C_LOG_HDR : natural := 1;   -- test case headers
  constant C_LOG_BFM : natural := 2;   -- every BFM transaction

  type t_alert_level is (WARNING, ERROR, FAILURE);

  type t_slv_array is array (natural range <>) of std_logic_vector;

  procedure bfm_set_verbosity (constant level : in natural);

  procedure bfm_log (constant level : in natural;
                     constant msg   : in string;
                     constant scope : in string := C_BFM_SCOPE);

  procedure bfm_alert (constant level : in t_alert_level;
                       constant msg   : in string;
                       constant scope : in string := C_BFM_SCOPE);

  procedure bfm_check (constant condition : in boolean;
                       constant msg       : in string;
                       constant scope     : in string        := C_BFM_SCOPE;
                       constant level     : in t_alert_level := ERROR);

  procedure bfm_check_value (constant actual   : in std_logic_vector;
                             constant expected : in std_logic_vector;
                             constant msg      : in string;
                             constant scope    : in string        := C_BFM_SCOPE;
                             constant level    : in t_alert_level := ERROR);

  procedure bfm_check_value (constant actual   : in std_logic;
                             constant expected : in std_logic;
                             constant msg      : in string;
                             constant scope    : in string        := C_BFM_SCOPE;
                             constant level    : in t_alert_level := ERROR);

  procedure bfm_check_value (constant actual   : in integer;
                             constant expected : in integer;
                             constant msg      : in string;
                             constant scope    : in string        := C_BFM_SCOPE;
                             constant level    : in t_alert_level := ERROR);

  procedure bfm_wait_cycles (constant n   : in natural;
                             signal   clk : in std_logic);

  -- Print the totals; "TEST PASSED" when there were no errors, otherwise a
  -- failure that stops the simulation.
  procedure bfm_report_final (constant scope : in string := C_BFM_SCOPE);

end package bfm_util_pkg;

package body bfm_util_pkg is

  -- Verbosity and the alert counters.  A protected type, so that several
  -- processes can use the BFMs at the same time.
  type t_bfm_state is protected
    procedure set_verbosity (level : natural);
    impure function get_verbosity return natural;
    procedure increment (level : t_alert_level);
    impure function get_count (level : t_alert_level) return natural;
  end protected t_bfm_state;

  type t_bfm_state is protected body
    variable verbosity : natural := C_LOG_HDR;
    variable warnings  : natural := 0;
    variable errors    : natural := 0;

    procedure set_verbosity (level : natural) is
    begin
      verbosity := level;
    end procedure set_verbosity;

    impure function get_verbosity return natural is
    begin
      return verbosity;
    end function get_verbosity;

    procedure increment (level : t_alert_level) is
    begin
      case level is
        when WARNING         => warnings := warnings + 1;
        when ERROR | FAILURE => errors   := errors + 1;
      end case;
    end procedure increment;

    impure function get_count (level : t_alert_level) return natural is
    begin
      case level is
        when WARNING => return warnings;
        when others  => return errors;
      end case;
    end function get_count;
  end protected body t_bfm_state;

  shared variable sv_bfm : t_bfm_state;

  procedure bfm_set_verbosity (constant level : in natural) is
  begin
    sv_bfm.set_verbosity(level);
  end procedure bfm_set_verbosity;

  procedure bfm_log (constant level : in natural;
                     constant msg   : in string;
                     constant scope : in string := C_BFM_SCOPE) is
  begin
    if sv_bfm.get_verbosity >= level then
      report scope & ": " & msg;
    end if;
  end procedure bfm_log;

  procedure bfm_alert (constant level : in t_alert_level;
                       constant msg   : in string;
                       constant scope : in string := C_BFM_SCOPE) is
  begin
    sv_bfm.increment(level);
    case level is
      when WARNING => report scope & ": " & msg severity warning;
      when ERROR   => report scope & ": " & msg severity error;
      when FAILURE => report scope & ": " & msg severity failure;
    end case;
  end procedure bfm_alert;

  procedure bfm_check (constant condition : in boolean;
                       constant msg       : in string;
                       constant scope     : in string        := C_BFM_SCOPE;
                       constant level     : in t_alert_level := ERROR) is
  begin
    if condition then
      bfm_log(C_LOG_BFM, "OK: " & msg, scope);
    else
      bfm_alert(level, "CHECK FAILED: " & msg, scope);
    end if;
  end procedure bfm_check;

  procedure bfm_check_value (constant actual   : in std_logic_vector;
                             constant expected : in std_logic_vector;
                             constant msg      : in string;
                             constant scope    : in string        := C_BFM_SCOPE;
                             constant level    : in t_alert_level := ERROR) is
  begin
    if actual = expected then
      bfm_log(C_LOG_BFM, "OK: " & msg & " = 0x" & to_hstring(actual), scope);
    else
      bfm_alert(level, "CHECK FAILED: " & msg & ", expected 0x" & to_hstring(expected)
                       & " got 0x" & to_hstring(actual), scope);
    end if;
  end procedure bfm_check_value;

  procedure bfm_check_value (constant actual   : in std_logic;
                             constant expected : in std_logic;
                             constant msg      : in string;
                             constant scope    : in string        := C_BFM_SCOPE;
                             constant level    : in t_alert_level := ERROR) is
  begin
    if actual = expected then
      bfm_log(C_LOG_BFM, "OK: " & msg & " = " & to_string(actual), scope);
    else
      bfm_alert(level, "CHECK FAILED: " & msg & ", expected " & to_string(expected)
                       & " got " & to_string(actual), scope);
    end if;
  end procedure bfm_check_value;

  procedure bfm_check_value (constant actual   : in integer;
                             constant expected : in integer;
                             constant msg      : in string;
                             constant scope    : in string        := C_BFM_SCOPE;
                             constant level    : in t_alert_level := ERROR) is
  begin
    if actual = expected then
      bfm_log(C_LOG_BFM, "OK: " & msg & " = " & integer'image(actual), scope);
    else
      bfm_alert(level, "CHECK FAILED: " & msg & ", expected " & integer'image(expected)
                       & " got " & integer'image(actual), scope);
    end if;
  end procedure bfm_check_value;

  procedure bfm_wait_cycles (constant n   : in natural;
                             signal   clk : in std_logic) is
  begin
    for i in 1 to n loop
      wait until rising_edge(clk);
    end loop;
  end procedure bfm_wait_cycles;

  procedure bfm_report_final (constant scope : in string := C_BFM_SCOPE) is
    variable v_errors   : natural := sv_bfm.get_count(ERROR);
    variable v_warnings : natural := sv_bfm.get_count(WARNING);
  begin
    if v_errors = 0 then
      report scope & ": TEST PASSED (" & integer'image(v_warnings) & " warning(s))";
    else
      report scope & ": TEST FAILED: " & integer'image(v_errors) & " error(s), "
             & integer'image(v_warnings) & " warning(s)" severity failure;
    end if;
  end procedure bfm_report_final;

end package body bfm_util_pkg;
