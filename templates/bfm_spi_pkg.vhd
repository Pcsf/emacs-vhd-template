{{!BFM: SPI master and slave, modes 0-3, MSB or LSB first, 1-32 bits per word}}
{{>header.vhd}}

-- Usage (in a testbench, needs bfm_util_pkg):
--   constant C_SPI : t_spi_bfm_config := (cpol => '0', cpha => '0',
--     sclk_period => 1 us, msb_first => true, word_width => 8,
--     cs_setup => 100 ns, cs_hold => 100 ns, timeout => 1 ms);
--   signal spi_m2s : t_spi_m2s := spi_m2s_idle(C_SPI);   -- master -> slave
--   signal spi_s2m : t_spi_s2m := C_SPI_S2M_INIT;        -- slave -> master
--   -- BFM as master, DUT is the slave:
--   spi_master_check(spi_word(16#A5#), spi_word(16#3C#), "read ID", spi_m2s, spi_s2m, config => C_SPI);
--   -- BFM as slave, DUT is the master (run from its own process):
--   spi_slave_check(spi_word(16#3C#), spi_word(16#A5#), "answer", spi_m2s, spi_s2m, config => C_SPI);
-- Words are right-aligned in a 32-bit vector; only word_width bits are used.
-- One call is one chip-select frame of one word.  While the slave is not
-- selected, MISO is driven '0' (a real slave would tri-state it).
-- Mode = (cpol, cpha): the clock idles at cpol; with cpha '0' data is
-- sampled on the first (leading) edge and changes on the second, with
-- cpha '1' it changes on the leading edge and is sampled on the second.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.bfm_util_pkg.all;

package {{pkg|$file}} is

  constant C_SPI_MAX_WIDTH : positive := 32;

  subtype t_spi_word is std_logic_vector(C_SPI_MAX_WIDTH - 1 downto 0);

  type t_spi_m2s is record
    sclk : std_logic;
    mosi : std_logic;
    cs_n : std_logic;
  end record t_spi_m2s;

  type t_spi_s2m is record
    miso : std_logic;
  end record t_spi_s2m;

  type t_spi_bfm_config is record
    cpol        : std_logic;                            -- clock level when idle
    cpha        : std_logic;                            -- '0': sample on the leading edge
    sclk_period : time;
    msb_first   : boolean;
    word_width  : natural range 1 to C_SPI_MAX_WIDTH;
    cs_setup    : time;                                 -- clock idle before CS, CS to first edge
    cs_hold     : time;                                 -- last edge to CS high
    timeout     : time;                                 -- slave: longest wait for CS
  end record t_spi_bfm_config;

  constant C_SPI_BFM_CONFIG_DEFAULT : t_spi_bfm_config := (
    cpol => '0', cpha => '0', sclk_period => 1 us, msb_first => true,
    word_width => 8, cs_setup => 100 ns, cs_hold => 100 ns, timeout => 1 ms);

  constant C_SPI_S2M_INIT : t_spi_s2m := (miso => '0');

  -- Signal initial value with the clock at its idle level.
  function spi_m2s_idle (constant config : t_spi_bfm_config) return t_spi_m2s;

  function spi_word (constant value : natural) return t_spi_word;

  -- Master: one frame, returns what the slave shifted out.
  procedure spi_master_transfer (
    constant tx_data : in  t_spi_word;
    variable rx_data : out t_spi_word;
    constant msg     : in  string;
    signal   m2s     : out t_spi_m2s;
    signal   s2m     : in  t_spi_s2m;
    constant scope   : in  string           := C_BFM_SCOPE;
    constant config  : in  t_spi_bfm_config := C_SPI_BFM_CONFIG_DEFAULT);

  procedure spi_master_check (
    constant tx_data : in  t_spi_word;
    constant exp_rx  : in  t_spi_word;
    constant msg     : in  string;
    signal   m2s     : out t_spi_m2s;
    signal   s2m     : in  t_spi_s2m;
    constant scope   : in  string           := C_BFM_SCOPE;
    constant config  : in  t_spi_bfm_config := C_SPI_BFM_CONFIG_DEFAULT);

  -- Slave: waits for CS, shifts tx_data out, returns what the master sent.
  procedure spi_slave_transfer (
    constant tx_data : in  t_spi_word;
    variable rx_data : out t_spi_word;
    constant msg     : in  string;
    signal   m2s     : in  t_spi_m2s;
    signal   s2m     : out t_spi_s2m;
    constant scope   : in  string           := C_BFM_SCOPE;
    constant config  : in  t_spi_bfm_config := C_SPI_BFM_CONFIG_DEFAULT);

  procedure spi_slave_check (
    constant tx_data : in  t_spi_word;
    constant exp_rx  : in  t_spi_word;
    constant msg     : in  string;
    signal   m2s     : in  t_spi_m2s;
    signal   s2m     : out t_spi_s2m;
    constant scope   : in  string           := C_BFM_SCOPE;
    constant config  : in  t_spi_bfm_config := C_SPI_BFM_CONFIG_DEFAULT);

end package {{pkg}};

package body {{pkg}} is

  function spi_m2s_idle (constant config : t_spi_bfm_config) return t_spi_m2s is
  begin
    return (sclk => config.cpol, mosi => '0', cs_n => '1');
  end function spi_m2s_idle;

  function spi_word (constant value : natural) return t_spi_word is
  begin
    return std_logic_vector(to_unsigned(value, C_SPI_MAX_WIDTH));
  end function spi_word;

  -- Index of the i-th bit on the wire.
  function bit_index (constant i : natural; constant config : t_spi_bfm_config)
    return natural is
  begin
    if config.msb_first then
      return config.word_width - 1 - i;
    else
      return i;
    end if;
  end function bit_index;

  -- A mask that keeps the low word_width bits.
  function width_mask (constant config : t_spi_bfm_config) return t_spi_word is
    variable v_mask : t_spi_word := (others => '0');
  begin
    v_mask(config.word_width - 1 downto 0) := (others => '1');
    return v_mask;
  end function width_mask;

  procedure spi_master_transfer (
    constant tx_data : in  t_spi_word;
    variable rx_data : out t_spi_word;
    constant msg     : in  string;
    signal   m2s     : out t_spi_m2s;
    signal   s2m     : in  t_spi_s2m;
    constant scope   : in  string           := C_BFM_SCOPE;
    constant config  : in  t_spi_bfm_config := C_SPI_BFM_CONFIG_DEFAULT) is
    constant C_HALF : time    := config.sclk_period / 2;
    constant C_W    : natural := config.word_width;
    variable v_rx   : t_spi_word := (others => '0');
  begin
    bfm_log(C_LOG_BFM, "spi_master_transfer: " & msg & " tx 0x"
            & to_hstring(tx_data and width_mask(config)), scope);
    m2s.sclk <= config.cpol;                     -- clock at idle before CS falls, so
    wait for config.cs_setup;                    -- a mode change is not seen as an edge
    m2s.cs_n <= '0';
    if config.cpha = '0' then                    -- first bit is out before the first edge
      m2s.mosi <= tx_data(bit_index(0, config));
    end if;
    wait for config.cs_setup;
    for i in 0 to C_W - 1 loop
      if config.cpha = '0' then
        wait for C_HALF;
        v_rx(bit_index(i, config)) := s2m.miso;             -- sampled on the leading edge
        m2s.sclk <= not config.cpol;
        wait for C_HALF;
        m2s.sclk <= config.cpol;
        if i < C_W - 1 then                                 -- changes on the trailing edge
          m2s.mosi <= tx_data(bit_index(i + 1, config));
        end if;
      else
        wait for C_HALF;
        m2s.sclk <= not config.cpol;
        m2s.mosi <= tx_data(bit_index(i, config));          -- changes on the leading edge
        wait for C_HALF;
        v_rx(bit_index(i, config)) := s2m.miso;             -- sampled on the trailing edge
        m2s.sclk <= config.cpol;
      end if;
    end loop;
    wait for config.cs_hold;
    m2s.cs_n <= '1';
    m2s.mosi <= '0';
    rx_data := v_rx;
  end procedure spi_master_transfer;

  procedure spi_master_check (
    constant tx_data : in  t_spi_word;
    constant exp_rx  : in  t_spi_word;
    constant msg     : in  string;
    signal   m2s     : out t_spi_m2s;
    signal   s2m     : in  t_spi_s2m;
    constant scope   : in  string           := C_BFM_SCOPE;
    constant config  : in  t_spi_bfm_config := C_SPI_BFM_CONFIG_DEFAULT) is
    variable v_rx : t_spi_word;
  begin
    spi_master_transfer(tx_data, v_rx, msg, m2s, s2m, scope, config);
    bfm_check_value(v_rx and width_mask(config), exp_rx and width_mask(config),
                    "spi_master_check " & msg, scope);
  end procedure spi_master_check;

  procedure spi_slave_transfer (
    constant tx_data : in  t_spi_word;
    variable rx_data : out t_spi_word;
    constant msg     : in  string;
    signal   m2s     : in  t_spi_m2s;
    signal   s2m     : out t_spi_s2m;
    constant scope   : in  string           := C_BFM_SCOPE;
    constant config  : in  t_spi_bfm_config := C_SPI_BFM_CONFIG_DEFAULT) is
    constant C_W  : natural := config.word_width;
    variable v_rx : t_spi_word := (others => '0');
  begin
    rx_data := (others => 'X');
    if m2s.cs_n /= '0' then
      wait until m2s.cs_n = '0' for config.timeout;
      if m2s.cs_n /= '0' then
        bfm_alert(ERROR, "spi_slave_transfer: timeout waiting for chip select (" & msg & ")", scope);
        return;
      end if;
    end if;
    if config.cpha = '0' then                    -- first bit must be there before the first edge
      s2m.miso <= tx_data(bit_index(0, config));
    end if;
    for i in 0 to C_W - 1 loop
      wait until m2s.sclk = not config.cpol;                -- leading edge
      if config.cpha = '0' then
        v_rx(bit_index(i, config)) := m2s.mosi;
      else
        s2m.miso <= tx_data(bit_index(i, config));
      end if;
      wait until m2s.sclk = config.cpol;                    -- trailing edge
      if config.cpha = '0' then
        if i < C_W - 1 then
          s2m.miso <= tx_data(bit_index(i + 1, config));
        end if;
      else
        v_rx(bit_index(i, config)) := m2s.mosi;
      end if;
    end loop;
    if m2s.cs_n /= '1' then
      wait until m2s.cs_n = '1' for config.timeout;
    end if;
    s2m.miso <= '0';
    rx_data := v_rx;
    bfm_log(C_LOG_BFM, "spi_slave_transfer: " & msg & " rx 0x"
            & to_hstring(v_rx and width_mask(config)), scope);
  end procedure spi_slave_transfer;

  procedure spi_slave_check (
    constant tx_data : in  t_spi_word;
    constant exp_rx  : in  t_spi_word;
    constant msg     : in  string;
    signal   m2s     : in  t_spi_m2s;
    signal   s2m     : out t_spi_s2m;
    constant scope   : in  string           := C_BFM_SCOPE;
    constant config  : in  t_spi_bfm_config := C_SPI_BFM_CONFIG_DEFAULT) is
    variable v_rx : t_spi_word;
  begin
    spi_slave_transfer(tx_data, v_rx, msg, m2s, s2m, scope, config);
    bfm_check_value(v_rx and width_mask(config), exp_rx and width_mask(config),
                    "spi_slave_check " & msg, scope);
  end procedure spi_slave_check;

end package body {{pkg}};
