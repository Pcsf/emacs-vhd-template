{{!BFM: UART transmit / receive / expect, 5-8 data bits, parity, 1-2 stop bits, error injection}}
{{>header.vhd}}

-- Usage (in a testbench, needs bfm_util_pkg):
--   constant C_UART : t_uart_bfm_config := (bit_period => 8680 ns, data_bits => 8,
--     parity => PARITY_NONE, stop_bits => 1, inject_parity_error => false,
--     inject_frame_error => false, timeout => 1 ms);
--   signal rxd : std_logic := '1';       -- BFM drives the DUT's RX pin
--   signal txd : std_logic;              -- DUT's TX pin
--   uart_transmit(x"A5", "send A5", rxd, config => C_UART);
--   uart_expect  (x"3C", "DUT answer", txd, config => C_UART);
-- The line idles high.  Transmit drives the data LSB first; receive waits for
-- the start bit (up to `timeout`), samples in the middle of every bit and
-- reports frame and parity errors.  inject_* on the transmit side produce a
-- bad parity bit or a low stop bit, to test a receiver's error flags.
-- The timing is in time, not clocks, since a UART has no clock.

library ieee;
use ieee.std_logic_1164.all;

use work.bfm_util_pkg.all;

package {{pkg|$file}} is

  type t_uart_parity is (PARITY_NONE, PARITY_EVEN, PARITY_ODD);

  type t_uart_bfm_config is record
    bit_period          : time;
    data_bits           : natural range 5 to 8;
    parity              : t_uart_parity;
    stop_bits           : natural range 1 to 2;
    inject_parity_error : boolean;   -- transmit: invert the parity bit
    inject_frame_error  : boolean;   -- transmit: stop bit(s) low
    timeout             : time;      -- receive: longest wait for a start bit
  end record t_uart_bfm_config;

  constant C_UART_BFM_CONFIG_DEFAULT : t_uart_bfm_config := (
    bit_period => 8680 ns,           -- 115200 baud
    data_bits => 8, parity => PARITY_NONE, stop_bits => 1,
    inject_parity_error => false, inject_frame_error => false,
    timeout => 1 ms);

  procedure uart_transmit (
    constant data   : in  std_logic_vector(7 downto 0);
    constant msg    : in  string;
    signal   tx     : out std_logic;
    constant scope  : in  string            := C_BFM_SCOPE;
    constant config : in  t_uart_bfm_config := C_UART_BFM_CONFIG_DEFAULT);

  procedure uart_receive (
    variable data       : out std_logic_vector(7 downto 0);
    variable frame_err  : out boolean;
    variable parity_err : out boolean;
    constant msg        : in  string;
    signal   rx         : in  std_logic;
    constant scope      : in  string            := C_BFM_SCOPE;
    constant config     : in  t_uart_bfm_config := C_UART_BFM_CONFIG_DEFAULT);

  procedure uart_expect (
    constant exp_data       : in  std_logic_vector(7 downto 0);
    constant msg            : in  string;
    signal   rx             : in  std_logic;
    constant exp_frame_err  : in  boolean           := false;
    constant exp_parity_err : in  boolean           := false;
    constant scope          : in  string            := C_BFM_SCOPE;
    constant config         : in  t_uart_bfm_config := C_UART_BFM_CONFIG_DEFAULT);

end package {{pkg}};

package body {{pkg}} is

  procedure uart_transmit (
    constant data   : in  std_logic_vector(7 downto 0);
    constant msg    : in  string;
    signal   tx     : out std_logic;
    constant scope  : in  string            := C_BFM_SCOPE;
    constant config : in  t_uart_bfm_config := C_UART_BFM_CONFIG_DEFAULT) is
    variable v_par : std_logic;
  begin
    bfm_log(C_LOG_BFM, "uart_transmit: " & msg & " 0x" & to_hstring(data), scope);
    tx <= '0';                                   -- start bit
    wait for config.bit_period;
    for i in 0 to config.data_bits - 1 loop      -- LSB first
      tx <= data(i);
      wait for config.bit_period;
    end loop;
    if config.parity /= PARITY_NONE then
      v_par := xor data(config.data_bits - 1 downto 0);   -- '1' for an odd number of ones
      if config.parity = PARITY_ODD then
        v_par := not v_par;
      end if;
      if config.inject_parity_error then
        v_par := not v_par;
      end if;
      tx <= v_par;
      wait for config.bit_period;
    end if;
    for s in 1 to config.stop_bits loop
      if config.inject_frame_error then
        tx <= '0';
      else
        tx <= '1';
      end if;
      wait for config.bit_period;
    end loop;
    tx <= '1';
  end procedure uart_transmit;

  procedure uart_receive (
    variable data       : out std_logic_vector(7 downto 0);
    variable frame_err  : out boolean;
    variable parity_err : out boolean;
    constant msg        : in  string;
    signal   rx         : in  std_logic;
    constant scope      : in  string            := C_BFM_SCOPE;
    constant config     : in  t_uart_bfm_config := C_UART_BFM_CONFIG_DEFAULT) is
    variable v_data : std_logic_vector(7 downto 0) := (others => '0');
    variable v_par  : std_logic;
  begin
    data       := (others => 'X');
    frame_err  := false;
    parity_err := false;
    if rx /= '0' then
      wait until rx = '0' for config.timeout;
      if rx /= '0' then
        bfm_alert(ERROR, "uart_receive: timeout waiting for a start bit (" & msg & ")", scope);
        return;
      end if;
    end if;
    wait for config.bit_period / 2;              -- middle of the start bit
    if rx /= '0' then
      bfm_alert(ERROR, "uart_receive: start bit glitch (" & msg & ")", scope);
      return;
    end if;
    for i in 0 to config.data_bits - 1 loop
      wait for config.bit_period;
      v_data(i) := rx;
    end loop;
    if config.parity /= PARITY_NONE then
      wait for config.bit_period;
      v_par := xor v_data(config.data_bits - 1 downto 0);
      if config.parity = PARITY_ODD then
        v_par := not v_par;
      end if;
      parity_err := rx /= v_par;
    end if;
    for s in 1 to config.stop_bits loop
      wait for config.bit_period;
      if rx /= '1' then
        frame_err := true;
      end if;
    end loop;
    if frame_err then                            -- let the line return to idle
      wait until rx = '1' for config.bit_period * 12;
    end if;
    data := v_data;
    bfm_log(C_LOG_BFM, "uart_receive: " & msg & " 0x" & to_hstring(v_data), scope);
  end procedure uart_receive;

  procedure uart_expect (
    constant exp_data       : in  std_logic_vector(7 downto 0);
    constant msg            : in  string;
    signal   rx             : in  std_logic;
    constant exp_frame_err  : in  boolean           := false;
    constant exp_parity_err : in  boolean           := false;
    constant scope          : in  string            := C_BFM_SCOPE;
    constant config         : in  t_uart_bfm_config := C_UART_BFM_CONFIG_DEFAULT) is
    variable v_data : std_logic_vector(7 downto 0);
    variable v_frm  : boolean;
    variable v_par  : boolean;
    variable v_mask : std_logic_vector(7 downto 0) := (others => '0');
  begin
    uart_receive(v_data, v_frm, v_par, msg, rx, scope, config);
    -- Only the configured number of data bits is compared.
    v_mask(config.data_bits - 1 downto 0) := (others => '1');
    bfm_check_value(v_data and v_mask, exp_data and v_mask, "uart_expect " & msg, scope);
    bfm_check(v_frm = exp_frame_err, "uart_expect " & msg & ": framing error flag", scope);
    bfm_check(v_par = exp_parity_err, "uart_expect " & msg & ": parity error flag", scope);
  end procedure uart_expect;

end package body {{pkg}};
