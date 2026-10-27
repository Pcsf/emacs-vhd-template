{{!Generic scoreboard (VHDL-2008 generic package): queue of expected values, check_received against the head}}
{{>header.vhd}}

-- Needs tb_util_pkg.  One instance per stream, at file level or in an
-- architecture:
--   package sb_byte_pkg is new work.sb_pkg
--     generic map (t_element => std_logic_vector(7 downto 0));
--   use sb_byte_pkg.all;
--   shared variable sb : t_scoreboard;
--   ...
--   sb.add_expected(x"A5", "first byte");     -- the sequencer, in order
--   sb.check_received(rx_byte, "uart rx");    -- the monitor, as data arrives
--   sb.check_empty("all bytes received");     -- before report_final
-- to_string defaults to the one visible for t_element; give another one for
-- a record.  G_DEPTH is the most values waiting at once.  GHDL and Questa
-- take generic packages; check your simulator before relying on this file.

library ieee;
use ieee.std_logic_1164.all;

use work.tb_util_pkg.all;

package {{pkg|$file}} is
  generic (
    type t_element;
    function to_string (e : t_element) return string is <>;
    G_DEPTH : positive := 256
  );

  type t_scoreboard is protected
    procedure set_scope (constant scope : in string);
    procedure add_expected (constant e   : in t_element;
                            constant msg : in string := "");
    -- Compare with the oldest expected value and drop it.
    procedure check_received (constant e     : in t_element;
                              constant msg   : in string := "";
                              constant level : in t_alert_level := ERROR);
    impure function pending return natural;
    impure function received return natural;
    procedure check_empty (constant msg   : in string := "";
                           constant level : in t_alert_level := ERROR);
    procedure reset;
  end protected t_scoreboard;

end package {{pkg}};

package body {{pkg}} is

  type t_scoreboard is protected body
    type t_queue is array (0 to G_DEPTH - 1) of t_element;

    variable q         : t_queue;
    variable head      : natural := 0;
    variable count     : natural := 0;
    variable n_rx      : natural := 0;
    variable sb_scope  : string(1 to 32) := (others => ' ');
    variable scope_len : natural := 0;

    impure function get_scope return string is
    begin
      if scope_len = 0 then
        return "SB";
      end if;
      return sb_scope(1 to scope_len);
    end function get_scope;

    procedure set_scope (constant scope : in string) is
      constant C_LEN : natural := minimum(scope'length, sb_scope'length);
    begin
      sb_scope(1 to C_LEN) := scope(scope'left to scope'left + C_LEN - 1);
      scope_len := C_LEN;
    end procedure set_scope;

    procedure add_expected (constant e   : in t_element;
                            constant msg : in string := "") is
    begin
      if count = G_DEPTH then
        alert(FAILURE, "scoreboard full (" & integer'image(G_DEPTH) & "): " & msg, get_scope);
      end if;
      q((head + count) mod G_DEPTH) := e;
      count := count + 1;
      log(C_LOG_DEBUG, "add_expected " & to_string(e) & " " & msg
          & " (" & integer'image(count) & " pending)", get_scope);
    end procedure add_expected;

    procedure check_received (constant e     : in t_element;
                              constant msg   : in string := "";
                              constant level : in t_alert_level := ERROR) is
    begin
      n_rx := n_rx + 1;
      if count = 0 then
        alert(level, "received " & to_string(e) & " with nothing expected: " & msg, get_scope);
        return;
      end if;
      if e = q(head) then
        log(C_LOG_BFM, "OK: " & msg & " = " & to_string(e), get_scope);
      else
        alert(level, "CHECK FAILED: " & msg & ", expected " & to_string(q(head))
              & " got " & to_string(e), get_scope);
      end if;
      head  := (head + 1) mod G_DEPTH;
      count := count - 1;
    end procedure check_received;

    impure function pending return natural is
    begin
      return count;
    end function pending;

    impure function received return natural is
    begin
      return n_rx;
    end function received;

    procedure check_empty (constant msg   : in string := "";
                           constant level : in t_alert_level := ERROR) is
    begin
      check_value(count, 0, "scoreboard pending " & msg, get_scope, level);
    end procedure check_empty;

    procedure reset is
    begin
      head  := 0;
      count := 0;
      n_rx  := 0;
    end procedure reset;
  end protected body t_scoreboard;

end package body {{pkg}};
