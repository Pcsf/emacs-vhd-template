{{!BFM: AXI4-Lite master (write, read, check) with response checking and back-pressure}}
{{>header.vhd}}

-- Usage (in a testbench, needs bfm_util_pkg):
--   signal axi_m2s : t_axilite_m2s := C_AXILITE_M2S_INIT;   -- BFM -> DUT
--   signal axi_s2m : t_axilite_s2m;                         -- DUT -> BFM
--   axilite_write(x"00000000", x"DEADBEEF", "write CONTROL", clk, axi_m2s, axi_s2m);
--   axilite_check(x"00000000", x"DEADBEEF", "read CONTROL",  clk, axi_m2s, axi_s2m);
--   axilite_write(x"00000004", x"1", "RO register", clk, axi_m2s, axi_s2m,
--                 exp_resp => C_AXI_RESP_SLVERR);
-- Every call checks bresp / rresp (default OKAY).  bready_delay and
-- rready_delay hold the master's ready low, to prove the slave keeps its
-- response valid until it is taken.  The DUT's address port may be narrower
-- than C_AXILITE_ADDR_WIDTH: connect a slice, e.g. axi_m2s.awaddr(3 downto 0).

library ieee;
use ieee.std_logic_1164.all;

use work.bfm_util_pkg.all;

package {{pkg|$file}} is

  constant C_AXILITE_ADDR_WIDTH : positive := {{addr_width|32}};
  constant C_AXILITE_DATA_WIDTH : positive := 32;   -- AXI4-Lite allows 32 or 64

  subtype t_axilite_addr is std_logic_vector(C_AXILITE_ADDR_WIDTH - 1 downto 0);
  subtype t_axilite_data is std_logic_vector(C_AXILITE_DATA_WIDTH - 1 downto 0);
  subtype t_axilite_strb is std_logic_vector(C_AXILITE_DATA_WIDTH / 8 - 1 downto 0);
  subtype t_axi_resp     is std_logic_vector(1 downto 0);

  constant C_AXI_RESP_OKAY   : t_axi_resp := "00";
  constant C_AXI_RESP_EXOKAY : t_axi_resp := "01";
  constant C_AXI_RESP_SLVERR : t_axi_resp := "10";
  constant C_AXI_RESP_DECERR : t_axi_resp := "11";

  type t_axilite_m2s is record
    awaddr  : t_axilite_addr;
    awvalid : std_logic;
    wdata   : t_axilite_data;
    wstrb   : t_axilite_strb;
    wvalid  : std_logic;
    bready  : std_logic;
    araddr  : t_axilite_addr;
    arvalid : std_logic;
    rready  : std_logic;
  end record t_axilite_m2s;

  type t_axilite_s2m is record
    awready : std_logic;
    wready  : std_logic;
    bresp   : t_axi_resp;
    bvalid  : std_logic;
    arready : std_logic;
    rdata   : t_axilite_data;
    rresp   : t_axi_resp;
    rvalid  : std_logic;
  end record t_axilite_s2m;

  constant C_AXILITE_M2S_INIT : t_axilite_m2s := (
    awaddr => (others => '0'), awvalid => '0',
    wdata  => (others => '0'), wstrb   => (others => '0'), wvalid => '0',
    bready => '0',
    araddr => (others => '0'), arvalid => '0',
    rready => '0');

  type t_axilite_bfm_config is record
    max_wait_cycles : natural;   -- timeout for every handshake
    bready_delay    : natural;   -- clocks before bready is raised
    rready_delay    : natural;   -- clocks before rready is raised
  end record t_axilite_bfm_config;

  constant C_AXILITE_BFM_CONFIG_DEFAULT : t_axilite_bfm_config :=
    (max_wait_cycles => 1000, bready_delay => 0, rready_delay => 0);

  procedure axilite_write (
    constant addr     : in  t_axilite_addr;
    constant data     : in  t_axilite_data;
    constant msg      : in  string;
    signal   clk      : in  std_logic;
    signal   m2s      : out t_axilite_m2s;
    signal   s2m      : in  t_axilite_s2m;
    constant strb     : in  t_axilite_strb := (others => '1');
    constant exp_resp : in  t_axi_resp     := C_AXI_RESP_OKAY;
    constant scope    : in  string         := C_BFM_SCOPE;
    constant config   : in  t_axilite_bfm_config := C_AXILITE_BFM_CONFIG_DEFAULT);

  procedure axilite_read (
    constant addr     : in  t_axilite_addr;
    variable data     : out t_axilite_data;
    constant msg      : in  string;
    signal   clk      : in  std_logic;
    signal   m2s      : out t_axilite_m2s;
    signal   s2m      : in  t_axilite_s2m;
    constant exp_resp : in  t_axi_resp     := C_AXI_RESP_OKAY;
    constant scope    : in  string         := C_BFM_SCOPE;
    constant config   : in  t_axilite_bfm_config := C_AXILITE_BFM_CONFIG_DEFAULT);

  procedure axilite_check (
    constant addr     : in  t_axilite_addr;
    constant exp_data : in  t_axilite_data;
    constant msg      : in  string;
    signal   clk      : in  std_logic;
    signal   m2s      : out t_axilite_m2s;
    signal   s2m      : in  t_axilite_s2m;
    constant exp_resp : in  t_axi_resp     := C_AXI_RESP_OKAY;
    constant scope    : in  string         := C_BFM_SCOPE;
    constant config   : in  t_axilite_bfm_config := C_AXILITE_BFM_CONFIG_DEFAULT);

end package {{pkg}};

package body {{pkg}} is

  procedure axilite_write (
    constant addr     : in  t_axilite_addr;
    constant data     : in  t_axilite_data;
    constant msg      : in  string;
    signal   clk      : in  std_logic;
    signal   m2s      : out t_axilite_m2s;
    signal   s2m      : in  t_axilite_s2m;
    constant strb     : in  t_axilite_strb := (others => '1');
    constant exp_resp : in  t_axi_resp     := C_AXI_RESP_OKAY;
    constant scope    : in  string         := C_BFM_SCOPE;
    constant config   : in  t_axilite_bfm_config := C_AXILITE_BFM_CONFIG_DEFAULT) is
    variable v_aw   : boolean := false;
    variable v_w    : boolean := false;
    variable v_wait : natural := 0;
  begin
    bfm_log(C_LOG_BFM, "axilite_write: " & msg & " addr 0x" & to_hstring(addr)
            & " data 0x" & to_hstring(data), scope);
    m2s.awaddr  <= addr;
    m2s.awvalid <= '1';
    m2s.wdata   <= data;
    m2s.wstrb   <= strb;
    m2s.wvalid  <= '1';
    -- Address and data channels are accepted independently.
    while not (v_aw and v_w) loop
      wait until rising_edge(clk);
      if not v_aw and s2m.awready = '1' then
        v_aw := true;
        m2s.awvalid <= '0';
      end if;
      if not v_w and s2m.wready = '1' then
        v_w := true;
        m2s.wvalid <= '0';
      end if;
      v_wait := v_wait + 1;
      if v_wait >= config.max_wait_cycles and not (v_aw and v_w) then
        bfm_alert(ERROR, "axilite_write: timeout waiting for awready / wready (" & msg & ")", scope);
        m2s.awvalid <= '0';
        m2s.wvalid  <= '0';
        exit;
      end if;
    end loop;
    -- Response.
    for i in 1 to config.bready_delay loop
      wait until rising_edge(clk);
    end loop;
    m2s.bready <= '1';
    v_wait := 0;
    loop
      wait until rising_edge(clk);
      exit when s2m.bvalid = '1';                -- taken at this edge
      v_wait := v_wait + 1;
      if v_wait >= config.max_wait_cycles then
        bfm_alert(ERROR, "axilite_write: timeout waiting for bvalid (" & msg & ")", scope);
        exit;
      end if;
    end loop;
    m2s.bready <= '0';
    bfm_check_value(s2m.bresp, exp_resp, "axilite_write " & msg & ": bresp", scope);
  end procedure axilite_write;

  procedure axilite_read (
    constant addr     : in  t_axilite_addr;
    variable data     : out t_axilite_data;
    constant msg      : in  string;
    signal   clk      : in  std_logic;
    signal   m2s      : out t_axilite_m2s;
    signal   s2m      : in  t_axilite_s2m;
    constant exp_resp : in  t_axi_resp     := C_AXI_RESP_OKAY;
    constant scope    : in  string         := C_BFM_SCOPE;
    constant config   : in  t_axilite_bfm_config := C_AXILITE_BFM_CONFIG_DEFAULT) is
    variable v_wait : natural := 0;
  begin
    data := (others => 'X');
    m2s.araddr  <= addr;
    m2s.arvalid <= '1';
    loop
      wait until rising_edge(clk);
      exit when s2m.arready = '1';               -- accepted at this edge
      v_wait := v_wait + 1;
      if v_wait >= config.max_wait_cycles then
        bfm_alert(ERROR, "axilite_read: timeout waiting for arready (" & msg & ")", scope);
        exit;
      end if;
    end loop;
    m2s.arvalid <= '0';
    for i in 1 to config.rready_delay loop
      wait until rising_edge(clk);
      bfm_check(s2m.rvalid = '1', "axilite_read " & msg & ": rvalid held until rready", scope);
    end loop;
    m2s.rready <= '1';
    v_wait := 0;
    loop
      wait until rising_edge(clk);
      if s2m.rvalid = '1' then                   -- taken at this edge
        data := s2m.rdata;
        bfm_check_value(s2m.rresp, exp_resp, "axilite_read " & msg & ": rresp", scope);
        exit;
      end if;
      v_wait := v_wait + 1;
      if v_wait >= config.max_wait_cycles then
        bfm_alert(ERROR, "axilite_read: timeout waiting for rvalid (" & msg & ")", scope);
        exit;
      end if;
    end loop;
    m2s.rready <= '0';
    bfm_log(C_LOG_BFM, "axilite_read: " & msg & " addr 0x" & to_hstring(addr)
            & " data 0x" & to_hstring(data), scope);
  end procedure axilite_read;

  procedure axilite_check (
    constant addr     : in  t_axilite_addr;
    constant exp_data : in  t_axilite_data;
    constant msg      : in  string;
    signal   clk      : in  std_logic;
    signal   m2s      : out t_axilite_m2s;
    signal   s2m      : in  t_axilite_s2m;
    constant exp_resp : in  t_axi_resp     := C_AXI_RESP_OKAY;
    constant scope    : in  string         := C_BFM_SCOPE;
    constant config   : in  t_axilite_bfm_config := C_AXILITE_BFM_CONFIG_DEFAULT) is
    variable v_data : t_axilite_data;
  begin
    axilite_read(addr, v_data, msg, clk, m2s, s2m, exp_resp, scope, config);
    bfm_check_value(v_data, exp_data, "axilite_check " & msg, scope);
  end procedure axilite_check;

end package body {{pkg}};
