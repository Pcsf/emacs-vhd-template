{{!BFM: Avalon-MM master (write, read, check) with waitrequest and readdatavalid handling}}
{{>header.vhd}}

-- Usage (in a testbench, needs bfm_util_pkg):
--   signal av_m2s : t_avmm_m2s := C_AVMM_M2S_INIT;   -- BFM -> DUT
--   signal av_s2m : t_avmm_s2m;                      -- DUT -> BFM
--   avmm_write(x"00", x"DEADBEEF", "write CONTROL", clk, av_m2s, av_s2m);
--   avmm_check(x"00", x"DEADBEEF", "read CONTROL",  clk, av_m2s, av_s2m);
-- One outstanding transfer at a time.  A command is accepted at the clock
-- edge where waitrequest is low; read data arrives with readdatavalid at
-- least one clock after that.  Addresses are what the slave sees (word
-- addresses for a slave with word addressing).  The DUT's address port may
-- be narrower than C_AVMM_ADDR_WIDTH: connect a slice.

library ieee;
use ieee.std_logic_1164.all;

use work.bfm_util_pkg.all;

package {{pkg|$file}} is

  constant C_AVMM_ADDR_WIDTH : positive := {{addr_width|8}};
  constant C_AVMM_DATA_WIDTH : positive := {{data_width|32}};

  subtype t_avmm_addr is std_logic_vector(C_AVMM_ADDR_WIDTH - 1 downto 0);
  subtype t_avmm_data is std_logic_vector(C_AVMM_DATA_WIDTH - 1 downto 0);
  subtype t_avmm_be   is std_logic_vector(C_AVMM_DATA_WIDTH / 8 - 1 downto 0);

  type t_avmm_m2s is record
    address    : t_avmm_addr;
    read       : std_logic;
    write      : std_logic;
    writedata  : t_avmm_data;
    byteenable : t_avmm_be;
  end record t_avmm_m2s;

  type t_avmm_s2m is record
    readdata      : t_avmm_data;
    readdatavalid : std_logic;
    waitrequest   : std_logic;
  end record t_avmm_s2m;

  constant C_AVMM_M2S_INIT : t_avmm_m2s := (
    address => (others => '0'), read => '0', write => '0',
    writedata => (others => '0'), byteenable => (others => '1'));

  type t_avmm_bfm_config is record
    max_wait_cycles : natural;   -- timeout for waitrequest and for readdatavalid
  end record t_avmm_bfm_config;

  constant C_AVMM_BFM_CONFIG_DEFAULT : t_avmm_bfm_config := (max_wait_cycles => 1000);

  procedure avmm_write (
    constant addr       : in  t_avmm_addr;
    constant data       : in  t_avmm_data;
    constant msg        : in  string;
    signal   clk        : in  std_logic;
    signal   m2s        : out t_avmm_m2s;
    signal   s2m        : in  t_avmm_s2m;
    constant byteenable : in  t_avmm_be := (others => '1');
    constant scope      : in  string    := C_BFM_SCOPE;
    constant config     : in  t_avmm_bfm_config := C_AVMM_BFM_CONFIG_DEFAULT);

  procedure avmm_read (
    constant addr   : in  t_avmm_addr;
    variable data   : out t_avmm_data;
    constant msg    : in  string;
    signal   clk    : in  std_logic;
    signal   m2s    : out t_avmm_m2s;
    signal   s2m    : in  t_avmm_s2m;
    constant scope  : in  string := C_BFM_SCOPE;
    constant config : in  t_avmm_bfm_config := C_AVMM_BFM_CONFIG_DEFAULT);

  procedure avmm_check (
    constant addr     : in  t_avmm_addr;
    constant exp_data : in  t_avmm_data;
    constant msg      : in  string;
    signal   clk      : in  std_logic;
    signal   m2s      : out t_avmm_m2s;
    signal   s2m      : in  t_avmm_s2m;
    constant scope    : in  string := C_BFM_SCOPE;
    constant config   : in  t_avmm_bfm_config := C_AVMM_BFM_CONFIG_DEFAULT);

end package {{pkg}};

package body {{pkg}} is

  procedure avmm_write (
    constant addr       : in  t_avmm_addr;
    constant data       : in  t_avmm_data;
    constant msg        : in  string;
    signal   clk        : in  std_logic;
    signal   m2s        : out t_avmm_m2s;
    signal   s2m        : in  t_avmm_s2m;
    constant byteenable : in  t_avmm_be := (others => '1');
    constant scope      : in  string    := C_BFM_SCOPE;
    constant config     : in  t_avmm_bfm_config := C_AVMM_BFM_CONFIG_DEFAULT) is
    variable v_wait : natural := 0;
  begin
    bfm_log(C_LOG_BFM, "avmm_write: " & msg & " addr 0x" & to_hstring(addr)
            & " data 0x" & to_hstring(data), scope);
    m2s.address    <= addr;
    m2s.writedata  <= data;
    m2s.byteenable <= byteenable;
    m2s.write      <= '1';
    loop
      wait until rising_edge(clk);
      exit when s2m.waitrequest = '0';           -- accepted at this edge
      v_wait := v_wait + 1;
      if v_wait >= config.max_wait_cycles then
        bfm_alert(ERROR, "avmm_write: timeout waiting for waitrequest low (" & msg & ")", scope);
        exit;
      end if;
    end loop;
    m2s.write <= '0';
  end procedure avmm_write;

  procedure avmm_read (
    constant addr   : in  t_avmm_addr;
    variable data   : out t_avmm_data;
    constant msg    : in  string;
    signal   clk    : in  std_logic;
    signal   m2s    : out t_avmm_m2s;
    signal   s2m    : in  t_avmm_s2m;
    constant scope  : in  string := C_BFM_SCOPE;
    constant config : in  t_avmm_bfm_config := C_AVMM_BFM_CONFIG_DEFAULT) is
    variable v_wait : natural := 0;
  begin
    data := (others => 'X');
    m2s.address    <= addr;
    m2s.byteenable <= (others => '1');
    m2s.read       <= '1';
    loop
      wait until rising_edge(clk);
      exit when s2m.waitrequest = '0';           -- accepted at this edge
      v_wait := v_wait + 1;
      if v_wait >= config.max_wait_cycles then
        bfm_alert(ERROR, "avmm_read: timeout waiting for waitrequest low (" & msg & ")", scope);
        exit;
      end if;
    end loop;
    m2s.read <= '0';
    v_wait := 0;
    loop
      wait until rising_edge(clk);
      if s2m.readdatavalid = '1' then
        data := s2m.readdata;
        exit;
      end if;
      v_wait := v_wait + 1;
      if v_wait >= config.max_wait_cycles then
        bfm_alert(ERROR, "avmm_read: timeout waiting for readdatavalid (" & msg & ")", scope);
        exit;
      end if;
    end loop;
    bfm_log(C_LOG_BFM, "avmm_read: " & msg & " addr 0x" & to_hstring(addr)
            & " data 0x" & to_hstring(data), scope);
  end procedure avmm_read;

  procedure avmm_check (
    constant addr     : in  t_avmm_addr;
    constant exp_data : in  t_avmm_data;
    constant msg      : in  string;
    signal   clk      : in  std_logic;
    signal   m2s      : out t_avmm_m2s;
    signal   s2m      : in  t_avmm_s2m;
    constant scope    : in  string := C_BFM_SCOPE;
    constant config   : in  t_avmm_bfm_config := C_AVMM_BFM_CONFIG_DEFAULT) is
    variable v_data : t_avmm_data;
  begin
    avmm_read(addr, v_data, msg, clk, m2s, s2m, scope, config);
    bfm_check_value(v_data, exp_data, "avmm_check " & msg, scope);
  end procedure avmm_check;

end package body {{pkg}};
