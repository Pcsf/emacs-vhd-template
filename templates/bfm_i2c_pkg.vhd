{{!BFM: I2C master and slave (transmit, receive, check), clock stretching, address NACK, repeated START}}
{{>header.vhd}}

-- Usage (in a testbench, needs bfm_util_pkg).  The bus is two std_logic
-- signals with a weak pull-up; every device drives '0' or 'Z':
--   signal scl, sda : std_logic := 'Z';
--   scl <= 'H';   sda <= 'H';                       -- the pull-ups
--   constant C_ADDR : t_i2c_addr := "1010000";      -- 0x50
--   -- BFM as master, DUT is the slave:
--   i2c_master_transmit(C_ADDR, (x"10", x"A1", x"B2"), "write", scl, sda);
--   i2c_master_transmit(C_ADDR, (0 => x"10"), "set pointer", scl, sda, send_stop => false);
--   i2c_master_check   (C_ADDR, (x"A1", x"B2"), "read back", scl, sda);   -- repeated START
--   -- BFM as slave, DUT is the master (run from its own process):
--   i2c_slave_check   (C_ADDR, (x"12", x"34"), "master writes", scl, sda);
--   i2c_slave_transmit(C_ADDR, (0 => x"9A"),   "master reads",  scl, sda);
-- A DUT's *_i input must see the resolved bus, converted with to_x01(scl)
-- ('H' becomes '1').  The master BFM sends START, address, bytes and STOP; with
-- send_stop => false it keeps SCL low, and the next call with send_start =>
-- true then makes a repeated START.  It reads back and checks every ACK.  The
-- slave BFM waits for a (repeated) START, checks the address and direction,
-- and returns after its last byte, without waiting for the STOP.
-- config.stretch holds SCL low after every byte to test clock stretching;
-- config.addr_ack = false makes the slave BFM leave its address unacknowledged.
-- Timing is in time, not clocks.  Not modelled: 10-bit addresses, arbitration.

library ieee;
use ieee.std_logic_1164.all;

use work.bfm_util_pkg.all;

package {{pkg|$file}} is

  subtype t_i2c_addr is std_logic_vector(6 downto 0);

  type t_i2c_bfm_config is record
    scl_period : time;      -- master: SCL period
    stretch    : time;      -- slave: hold SCL low this long after every byte (0 ns: never)
    addr_ack   : boolean;   -- slave: acknowledge its address (false: leave it NACKed)
    timeout    : time;      -- longest wait for a bus event
  end record t_i2c_bfm_config;

  constant C_I2C_BFM_CONFIG_DEFAULT : t_i2c_bfm_config :=
    (scl_period => 10 us, stretch => 0 ns, addr_ack => true, timeout => 1 ms);   -- 100 kHz

  -- Master: START, address + write, bytes, STOP.  Every byte must be ACKed;
  -- addr_ack_expected => false expects the address to be NACKed (a STOP follows).
  procedure i2c_master_transmit (
    constant addr                : in    t_i2c_addr;
    constant data                : in    t_slv_array;
    constant msg                 : in    string;
    signal   scl                 : inout std_logic;
    signal   sda                 : inout std_logic;
    constant addr_ack_expected   : in    boolean := true;
    constant send_start          : in    boolean := true;
    constant send_stop           : in    boolean := true;
    constant scope               : in    string  := C_BFM_SCOPE;
    constant config              : in    t_i2c_bfm_config := C_I2C_BFM_CONFIG_DEFAULT);

  -- Master: START, address + read, reads data'length bytes (NACK on the last), STOP.
  procedure i2c_master_receive (
    constant addr       : in    t_i2c_addr;
    variable data       : out   t_slv_array;
    constant msg        : in    string;
    signal   scl        : inout std_logic;
    signal   sda        : inout std_logic;
    constant send_start : in    boolean := true;
    constant send_stop  : in    boolean := true;
    constant scope      : in    string  := C_BFM_SCOPE;
    constant config     : in    t_i2c_bfm_config := C_I2C_BFM_CONFIG_DEFAULT);

  procedure i2c_master_check (
    constant addr       : in    t_i2c_addr;
    constant exp_data   : in    t_slv_array;
    constant msg        : in    string;
    signal   scl        : inout std_logic;
    signal   sda        : inout std_logic;
    constant send_start : in    boolean := true;
    constant send_stop  : in    boolean := true;
    constant scope      : in    string  := C_BFM_SCOPE;
    constant config     : in    t_i2c_bfm_config := C_I2C_BFM_CONFIG_DEFAULT);

  -- Slave: waits for START, address with write, receives data'length bytes.
  procedure i2c_slave_receive (
    constant addr   : in    t_i2c_addr;
    variable data   : out   t_slv_array;
    constant msg    : in    string;
    signal   scl    : inout std_logic;
    signal   sda    : inout std_logic;
    constant scope  : in    string  := C_BFM_SCOPE;
    constant config : in    t_i2c_bfm_config := C_I2C_BFM_CONFIG_DEFAULT);

  procedure i2c_slave_check (
    constant addr     : in    t_i2c_addr;
    constant exp_data : in    t_slv_array;
    constant msg      : in    string;
    signal   scl      : inout std_logic;
    signal   sda      : inout std_logic;
    constant scope    : in    string  := C_BFM_SCOPE;
    constant config   : in    t_i2c_bfm_config := C_I2C_BFM_CONFIG_DEFAULT);

  -- Slave: waits for START, address with read, sends the bytes; returns
  -- after the master's NACK, or after the last byte if the master ACKs it.
  procedure i2c_slave_transmit (
    constant addr   : in    t_i2c_addr;
    constant data   : in    t_slv_array;
    constant msg    : in    string;
    signal   scl    : inout std_logic;
    signal   sda    : inout std_logic;
    constant scope  : in    string  := C_BFM_SCOPE;
    constant config : in    t_i2c_bfm_config := C_I2C_BFM_CONFIG_DEFAULT);

end package {{pkg}};

package body {{pkg}} is

  ---------------------------------------------------------------------------
  -- Master primitives.  SCL and SDA are only ever driven '0' or released ('Z').
  ---------------------------------------------------------------------------

  -- Release SCL and wait until it is high (a slave may stretch it).
  procedure release_scl (
    signal   scl     : inout std_logic;
    constant timeout : in    time;
    constant scope   : in    string) is
  begin
    scl <= 'Z';
    if to_x01(scl) /= '1' then
      wait until to_x01(scl) = '1' for timeout;
      if to_x01(scl) /= '1' then
        bfm_alert(ERROR, "i2c: SCL stuck low", scope);
      end if;
    end if;
  end procedure release_scl;

  procedure start_condition (
    signal   scl     : inout std_logic;
    signal   sda     : inout std_logic;
    constant q       : in    time;
    constant timeout : in    time;
    constant scope   : in    string) is
  begin
    if to_x01(scl) = '0' then          -- bus is open: repeated START
      sda <= 'Z';
      wait for q;
      release_scl(scl, timeout, scope);
      wait for q;
    end if;
    sda <= '0';                        -- SDA falls while SCL is high
    wait for q;
    scl <= '0';
    wait for q;
  end procedure start_condition;

  procedure stop_condition (
    signal   scl     : inout std_logic;
    signal   sda     : inout std_logic;
    constant q       : in    time;
    constant timeout : in    time;
    constant scope   : in    string) is
  begin
    sda <= '0';                        -- SCL is low here
    wait for q;
    release_scl(scl, timeout, scope);
    wait for q;
    sda <= 'Z';                        -- SDA rises while SCL is high
    wait for q;
  end procedure stop_condition;

  -- One clock with SDA driven to b ('0' pulls low, '1' releases).
  procedure put_bit (
    constant b       : in    std_logic;
    signal   scl     : inout std_logic;
    signal   sda     : inout std_logic;
    constant q       : in    time;
    constant timeout : in    time;
    constant scope   : in    string) is
  begin
    if b = '0' then
      sda <= '0';
    else
      sda <= 'Z';
    end if;
    wait for q;
    release_scl(scl, timeout, scope);
    wait for 2 * q;
    scl <= '0';
    wait for q;
  end procedure put_bit;

  -- One clock with SDA released; returns what the slave drove.
  procedure get_bit (
    variable b       : out   std_logic;
    signal   scl     : inout std_logic;
    signal   sda     : inout std_logic;
    constant q       : in    time;
    constant timeout : in    time;
    constant scope   : in    string) is
  begin
    sda <= 'Z';
    wait for q;
    release_scl(scl, timeout, scope);
    wait for 2 * q;
    b := to_x01(sda);
    scl <= '0';
    wait for q;
  end procedure get_bit;

  procedure put_byte (
    constant v       : in    std_logic_vector(7 downto 0);
    signal   scl     : inout std_logic;
    signal   sda     : inout std_logic;
    constant q       : in    time;
    constant timeout : in    time;
    constant scope   : in    string) is
  begin
    for i in 7 downto 0 loop
      put_bit(v(i), scl, sda, q, timeout, scope);
    end loop;
  end procedure put_byte;

  procedure get_byte (
    variable v       : out   std_logic_vector(7 downto 0);
    signal   scl     : inout std_logic;
    signal   sda     : inout std_logic;
    constant q       : in    time;
    constant timeout : in    time;
    constant scope   : in    string) is
    variable v_bit : std_logic;
  begin
    for i in 7 downto 0 loop
      get_bit(v_bit, scl, sda, q, timeout, scope);
      v(i) := v_bit;
    end loop;
  end procedure get_byte;

  ---------------------------------------------------------------------------
  -- Master
  ---------------------------------------------------------------------------
  procedure i2c_master_transmit (
    constant addr                : in    t_i2c_addr;
    constant data                : in    t_slv_array;
    constant msg                 : in    string;
    signal   scl                 : inout std_logic;
    signal   sda                 : inout std_logic;
    constant addr_ack_expected   : in    boolean := true;
    constant send_start          : in    boolean := true;
    constant send_stop           : in    boolean := true;
    constant scope               : in    string  := C_BFM_SCOPE;
    constant config              : in    t_i2c_bfm_config := C_I2C_BFM_CONFIG_DEFAULT) is
    constant q      : time := config.scl_period / 4;
    variable v_ack  : std_logic;
    variable v_byte : std_logic_vector(7 downto 0);
  begin
    if data'length > 0 and data(data'low)'length /= 8 then
      bfm_alert(FAILURE, "i2c_master_transmit: data must be bytes", scope);
    end if;
    bfm_log(C_LOG_BFM, "i2c_master_transmit: " & msg & " addr 0x" & to_hstring('0' & addr)
            & " (" & integer'image(data'length) & " bytes)", scope);
    if send_start then
      start_condition(scl, sda, q, config.timeout, scope);
    end if;
    put_byte(addr & '0', scl, sda, q, config.timeout, scope);       -- address, write
    get_bit(v_ack, scl, sda, q, config.timeout, scope);
    bfm_check((v_ack = '0') = addr_ack_expected,
              "i2c_master_transmit " & msg & ": address is " &
              boolean'image(addr_ack_expected) & " acknowledged", scope);
    if v_ack = '0' then
      for n in data'low to data'high loop
        v_byte := data(n);                       -- position-based copy, whatever the bounds
        put_byte(v_byte, scl, sda, q, config.timeout, scope);
        get_bit(v_ack, scl, sda, q, config.timeout, scope);
        bfm_check(v_ack = '0', "i2c_master_transmit " & msg & ": byte "
                  & integer'image(n - data'low) & " acknowledged", scope);
      end loop;
    end if;
    if send_stop or v_ack /= '0' then            -- a NACKed address always ends with a STOP
      stop_condition(scl, sda, q, config.timeout, scope);
    end if;
  end procedure i2c_master_transmit;

  procedure i2c_master_receive (
    constant addr       : in    t_i2c_addr;
    variable data       : out   t_slv_array;
    constant msg        : in    string;
    signal   scl        : inout std_logic;
    signal   sda        : inout std_logic;
    constant send_start : in    boolean := true;
    constant send_stop  : in    boolean := true;
    constant scope      : in    string  := C_BFM_SCOPE;
    constant config     : in    t_i2c_bfm_config := C_I2C_BFM_CONFIG_DEFAULT) is
    constant q      : time := config.scl_period / 4;
    variable v_ack  : std_logic;
    variable v_byte : std_logic_vector(7 downto 0);
  begin
    for n in data'low to data'high loop
      data(n) := (data(n)'range => 'X');
    end loop;
    bfm_log(C_LOG_BFM, "i2c_master_receive: " & msg & " addr 0x" & to_hstring('0' & addr)
            & " (" & integer'image(data'length) & " bytes)", scope);
    if send_start then
      start_condition(scl, sda, q, config.timeout, scope);
    end if;
    put_byte(addr & '1', scl, sda, q, config.timeout, scope);       -- address, read
    get_bit(v_ack, scl, sda, q, config.timeout, scope);
    bfm_check(v_ack = '0', "i2c_master_receive " & msg & ": address acknowledged", scope);
    if v_ack = '0' then
      for n in data'low to data'high loop
        get_byte(v_byte, scl, sda, q, config.timeout, scope);
        data(n) := v_byte;
        if n = data'high then
          put_bit('1', scl, sda, q, config.timeout, scope);         -- NACK the last byte
        else
          put_bit('0', scl, sda, q, config.timeout, scope);         -- ACK
        end if;
      end loop;
    end if;
    if send_stop or v_ack /= '0' then
      stop_condition(scl, sda, q, config.timeout, scope);
    end if;
  end procedure i2c_master_receive;

  procedure i2c_master_check (
    constant addr       : in    t_i2c_addr;
    constant exp_data   : in    t_slv_array;
    constant msg        : in    string;
    signal   scl        : inout std_logic;
    signal   sda        : inout std_logic;
    constant send_start : in    boolean := true;
    constant send_stop  : in    boolean := true;
    constant scope      : in    string  := C_BFM_SCOPE;
    constant config     : in    t_i2c_bfm_config := C_I2C_BFM_CONFIG_DEFAULT) is
    variable v_data : t_slv_array(exp_data'range)(7 downto 0);
    variable v_exp  : std_logic_vector(7 downto 0);
  begin
    i2c_master_receive(addr, v_data, msg, scl, sda, send_start, send_stop, scope, config);
    for n in exp_data'low to exp_data'high loop
      v_exp := exp_data(n);
      bfm_check_value(v_data(n), v_exp, "i2c_master_check " & msg & " byte "
                      & integer'image(n - exp_data'low), scope);
    end loop;
  end procedure i2c_master_check;

  ---------------------------------------------------------------------------
  -- Slave primitives
  ---------------------------------------------------------------------------

  -- Wait for START: SDA falls while SCL is high.
  procedure wait_start (
    signal   scl     : inout std_logic;
    signal   sda     : inout std_logic;
    variable found   : out   boolean;
    constant timeout : in    time) is
  begin
    found := false;
    loop
      wait on sda for timeout;
      if not sda'event then
        return;                                  -- timed out
      end if;
      if to_x01(sda) = '0' and to_x01(sda'last_value) = '1' and to_x01(scl) = '1' then
        found := true;
        return;
      end if;
    end loop;
  end procedure wait_start;

  -- Wait for the next rising / falling edge of SCL.
  procedure wait_scl_rise (
    signal   scl     : inout std_logic;
    constant timeout : in    time;
    constant scope   : in    string) is
  begin
    wait until rising_edge(scl) for timeout;
    if to_x01(scl) /= '1' then
      bfm_alert(ERROR, "i2c: timeout waiting for SCL to rise", scope);
    end if;
  end procedure wait_scl_rise;

  procedure wait_scl_fall (
    signal   scl     : inout std_logic;
    constant timeout : in    time;
    constant scope   : in    string) is
  begin
    wait until falling_edge(scl) for timeout;
    if to_x01(scl) /= '0' then
      bfm_alert(ERROR, "i2c: timeout waiting for SCL to fall", scope);
    end if;
  end procedure wait_scl_fall;

  -- Hold SCL low for config.stretch after a byte.
  procedure stretch_clock (
    signal   scl    : inout std_logic;
    constant config : in    t_i2c_bfm_config) is
  begin
    if config.stretch > 0 ns then
      scl <= '0';
      wait for config.stretch;
      scl <= 'Z';
    end if;
  end procedure stretch_clock;

  -- Receive 8 bits, sampled on the rising edges of SCL.
  procedure slave_get_byte (
    variable v       : out   std_logic_vector(7 downto 0);
    signal   scl     : inout std_logic;
    signal   sda     : inout std_logic;
    constant timeout : in    time;
    constant scope   : in    string) is
  begin
    for i in 7 downto 0 loop
      wait_scl_rise(scl, timeout, scope);
      v(i) := to_x01(sda);
    end loop;
  end procedure slave_get_byte;

  -- The address phase shared by receive and transmit.  ok is false when the
  -- transfer is not for this BFM (bad START, other address, address NACKed).
  procedure slave_address (
    constant addr     : in    t_i2c_addr;
    constant want_read : in   boolean;
    constant msg      : in    string;
    variable ok       : out   boolean;
    signal   scl      : inout std_logic;
    signal   sda      : inout std_logic;
    constant scope    : in    string;
    constant config   : in    t_i2c_bfm_config) is
    variable v_found : boolean;
    variable v_byte  : std_logic_vector(7 downto 0);
  begin
    ok := false;
    wait_start(scl, sda, v_found, config.timeout);
    if not v_found then
      bfm_alert(ERROR, "i2c slave " & msg & ": timeout waiting for START", scope);
      return;
    end if;
    slave_get_byte(v_byte, scl, sda, config.timeout, scope);
    wait_scl_fall(scl, config.timeout, scope);
    if v_byte(7 downto 1) /= addr then
      bfm_alert(ERROR, "i2c slave " & msg & ": addressed 0x" & to_hstring('0' & v_byte(7 downto 1))
                & ", expected 0x" & to_hstring('0' & addr), scope);
      return;
    end if;
    bfm_check((v_byte(0) = '1') = want_read, "i2c slave " & msg & ": direction bit", scope);
    if config.addr_ack then
      sda <= '0';                                -- ACK
      wait_scl_rise(scl, config.timeout, scope);
      wait_scl_fall(scl, config.timeout, scope);
      sda <= 'Z';
      ok := true;
    else
      sda <= 'Z';                                -- deliberately not acknowledged
      wait_scl_rise(scl, config.timeout, scope);
      wait_scl_fall(scl, config.timeout, scope);
    end if;
  end procedure slave_address;

  ---------------------------------------------------------------------------
  -- Slave
  ---------------------------------------------------------------------------
  procedure i2c_slave_receive (
    constant addr   : in    t_i2c_addr;
    variable data   : out   t_slv_array;
    constant msg    : in    string;
    signal   scl    : inout std_logic;
    signal   sda    : inout std_logic;
    constant scope  : in    string  := C_BFM_SCOPE;
    constant config : in    t_i2c_bfm_config := C_I2C_BFM_CONFIG_DEFAULT) is
    variable v_ok   : boolean;
    variable v_byte : std_logic_vector(7 downto 0);
  begin
    for n in data'low to data'high loop
      data(n) := (data(n)'range => 'X');
    end loop;
    slave_address(addr, false, msg, v_ok, scl, sda, scope, config);
    if not v_ok then
      return;
    end if;
    stretch_clock(scl, config);
    for n in data'low to data'high loop
      slave_get_byte(v_byte, scl, sda, config.timeout, scope);
      data(n) := v_byte;
      wait_scl_fall(scl, config.timeout, scope);
      sda <= '0';                                -- ACK
      wait_scl_rise(scl, config.timeout, scope);
      wait_scl_fall(scl, config.timeout, scope);
      sda <= 'Z';
      stretch_clock(scl, config);
    end loop;
    bfm_log(C_LOG_BFM, "i2c_slave_receive: " & msg & " (" & integer'image(data'length)
            & " bytes)", scope);
  end procedure i2c_slave_receive;

  procedure i2c_slave_check (
    constant addr     : in    t_i2c_addr;
    constant exp_data : in    t_slv_array;
    constant msg      : in    string;
    signal   scl      : inout std_logic;
    signal   sda      : inout std_logic;
    constant scope    : in    string  := C_BFM_SCOPE;
    constant config   : in    t_i2c_bfm_config := C_I2C_BFM_CONFIG_DEFAULT) is
    variable v_data : t_slv_array(exp_data'range)(7 downto 0);
    variable v_exp  : std_logic_vector(7 downto 0);
  begin
    i2c_slave_receive(addr, v_data, msg, scl, sda, scope, config);
    for n in exp_data'low to exp_data'high loop
      v_exp := exp_data(n);
      bfm_check_value(v_data(n), v_exp, "i2c_slave_check " & msg & " byte "
                      & integer'image(n - exp_data'low), scope);
    end loop;
  end procedure i2c_slave_check;

  procedure i2c_slave_transmit (
    constant addr   : in    t_i2c_addr;
    constant data   : in    t_slv_array;
    constant msg    : in    string;
    signal   scl    : inout std_logic;
    signal   sda    : inout std_logic;
    constant scope  : in    string  := C_BFM_SCOPE;
    constant config : in    t_i2c_bfm_config := C_I2C_BFM_CONFIG_DEFAULT) is
    variable v_ok   : boolean;
    variable v_byte : std_logic_vector(7 downto 0);
    variable v_ack  : std_logic;
  begin
    slave_address(addr, true, msg, v_ok, scl, sda, scope, config);
    if not v_ok then
      return;
    end if;
    for n in data'low to data'high loop
      v_byte := data(n);
      -- The first bit is out before SCL rises; then every falling edge shifts.
      for i in 7 downto 0 loop
        if v_byte(i) = '0' then
          sda <= '0';
        else
          sda <= 'Z';
        end if;
        if i = 7 then
          stretch_clock(scl, config);
        end if;
        wait_scl_rise(scl, config.timeout, scope);
        wait_scl_fall(scl, config.timeout, scope);
      end loop;
      sda <= 'Z';                                -- master's acknowledge
      wait_scl_rise(scl, config.timeout, scope);
      v_ack := to_x01(sda);
      wait_scl_fall(scl, config.timeout, scope);
      if n = data'high then
        bfm_log(C_LOG_BFM, "i2c_slave_transmit: " & msg & " (" & integer'image(data'length)
                & " bytes)", scope);
      elsif v_ack /= '0' then
        bfm_alert(ERROR, "i2c_slave_transmit " & msg & ": master NACKed byte "
                  & integer'image(n - data'low) & " of " & integer'image(data'length), scope);
        return;
      end if;
    end loop;
  end procedure i2c_slave_transmit;

end package body {{pkg}};
