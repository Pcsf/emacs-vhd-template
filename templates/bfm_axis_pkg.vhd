{{!BFM: AXI4-Stream master (transmit packets) and slave (receive, expect), with gaps and back-pressure}}
{{>header.vhd}}

-- Usage (in a testbench, needs bfm_util_pkg):
--   signal src_m2s : t_axis_m2s := C_AXIS_M2S_INIT;   -- BFM -> DUT
--   signal src_s2m : t_axis_s2m := C_AXIS_S2M_INIT;   -- DUT -> BFM
--   ...
--   axis_transmit(packet, "packet 1", clk, src_m2s, src_s2m);      -- master
--   axis_expect  (packet, "packet 1", clk, snk_m2s, snk_s2m);      -- slave
-- One packet is one t_slv_array; tlast goes with its last beat.  The transmit
-- and the expect calls block, so run them from separate processes when the
-- DUT is in between.  gap_cycles idles the source between beats,
-- ready_low_cycles holds tready low before each beat on the sink.
-- Not modelled: tkeep, tstrb, tid, tdest, tuser (add fields to the records).

library ieee;
use ieee.std_logic_1164.all;

use work.bfm_util_pkg.all;

package {{pkg|$file}} is

  constant C_AXIS_DATA_WIDTH : positive := {{data_width|32}};

  type t_axis_m2s is record
    tdata  : std_logic_vector(C_AXIS_DATA_WIDTH - 1 downto 0);
    tvalid : std_logic;
    tlast  : std_logic;
  end record t_axis_m2s;

  type t_axis_s2m is record
    tready : std_logic;
  end record t_axis_s2m;

  constant C_AXIS_M2S_INIT : t_axis_m2s :=
    (tdata => (others => '0'), tvalid => '0', tlast => '0');
  constant C_AXIS_S2M_INIT : t_axis_s2m := (tready => '0');

  type t_axis_bfm_config is record
    max_wait_cycles  : natural;   -- timeout while waiting for tready / tvalid
    gap_cycles       : natural;   -- source: idle clocks between beats
    ready_low_cycles : natural;   -- sink: tready low clocks before each beat
  end record t_axis_bfm_config;

  constant C_AXIS_BFM_CONFIG_DEFAULT : t_axis_bfm_config :=
    (max_wait_cycles => 1000, gap_cycles => 0, ready_low_cycles => 0);

  -- Master: send one packet, tlast on the last beat.
  procedure axis_transmit (
    constant data   : in  t_slv_array;
    constant msg    : in  string;
    signal   clk    : in  std_logic;
    signal   m2s    : out t_axis_m2s;
    signal   s2m    : in  t_axis_s2m;
    constant scope  : in  string            := C_BFM_SCOPE;
    constant config : in  t_axis_bfm_config := C_AXIS_BFM_CONFIG_DEFAULT);

  -- Slave: accept one beat.
  procedure axis_receive_beat (
    variable data   : out std_logic_vector(C_AXIS_DATA_WIDTH - 1 downto 0);
    variable last   : out std_logic;
    constant msg    : in  string;
    signal   clk    : in  std_logic;
    signal   m2s    : in  t_axis_m2s;
    signal   s2m    : out t_axis_s2m;
    constant scope  : in  string            := C_BFM_SCOPE;
    constant config : in  t_axis_bfm_config := C_AXIS_BFM_CONFIG_DEFAULT);

  -- Slave: accept one packet and compare data and tlast with the expected one.
  procedure axis_expect (
    constant exp_data : in  t_slv_array;
    constant msg      : in  string;
    signal   clk      : in  std_logic;
    signal   m2s      : in  t_axis_m2s;
    signal   s2m      : out t_axis_s2m;
    constant scope    : in  string            := C_BFM_SCOPE;
    constant config   : in  t_axis_bfm_config := C_AXIS_BFM_CONFIG_DEFAULT);

end package {{pkg}};

package body {{pkg}} is

  procedure axis_transmit (
    constant data   : in  t_slv_array;
    constant msg    : in  string;
    signal   clk    : in  std_logic;
    signal   m2s    : out t_axis_m2s;
    signal   s2m    : in  t_axis_s2m;
    constant scope  : in  string            := C_BFM_SCOPE;
    constant config : in  t_axis_bfm_config := C_AXIS_BFM_CONFIG_DEFAULT) is
    variable v_wait : natural;
  begin
    if data'length = 0 then
      return;
    end if;
    if data(data'low)'length /= C_AXIS_DATA_WIDTH then
      bfm_alert(FAILURE, "axis_transmit: data is " & integer'image(data(data'low)'length)
                & " bits wide, C_AXIS_DATA_WIDTH is " & integer'image(C_AXIS_DATA_WIDTH), scope);
    end if;
    bfm_log(C_LOG_BFM, "axis_transmit: " & msg & " (" & integer'image(data'length)
            & " beats)", scope);
    for i in data'low to data'high loop
      if i /= data'low and config.gap_cycles > 0 then
        m2s.tvalid <= '0';
        for g in 1 to config.gap_cycles loop
          wait until rising_edge(clk);
        end loop;
      end if;
      m2s.tdata  <= data(i);
      m2s.tvalid <= '1';
      if i = data'high then
        m2s.tlast <= '1';
      else
        m2s.tlast <= '0';
      end if;
      v_wait := 0;
      loop
        wait until rising_edge(clk);
        exit when s2m.tready = '1';              -- accepted at this edge
        v_wait := v_wait + 1;
        if v_wait >= config.max_wait_cycles then
          bfm_alert(ERROR, "axis_transmit: timeout waiting for tready (" & msg & ")", scope);
          exit;
        end if;
      end loop;
    end loop;
    m2s <= C_AXIS_M2S_INIT;
  end procedure axis_transmit;

  procedure axis_receive_beat (
    variable data   : out std_logic_vector(C_AXIS_DATA_WIDTH - 1 downto 0);
    variable last   : out std_logic;
    constant msg    : in  string;
    signal   clk    : in  std_logic;
    signal   m2s    : in  t_axis_m2s;
    signal   s2m    : out t_axis_s2m;
    constant scope  : in  string            := C_BFM_SCOPE;
    constant config : in  t_axis_bfm_config := C_AXIS_BFM_CONFIG_DEFAULT) is
    variable v_wait : natural := 0;
  begin
    data := (others => 'X');
    last := 'X';
    for i in 1 to config.ready_low_cycles loop
      s2m.tready <= '0';
      wait until rising_edge(clk);
    end loop;
    s2m.tready <= '1';
    loop
      wait until rising_edge(clk);
      if m2s.tvalid = '1' then                   -- taken at this edge
        data := m2s.tdata;
        last := m2s.tlast;
        exit;
      end if;
      v_wait := v_wait + 1;
      if v_wait >= config.max_wait_cycles then
        bfm_alert(ERROR, "axis_receive: timeout waiting for tvalid (" & msg & ")", scope);
        exit;
      end if;
    end loop;
    -- Dropped again unless the next call sets it in the same delta cycle,
    -- so back-to-back calls keep tready high and lose no beat.
    s2m.tready <= '0';
  end procedure axis_receive_beat;

  procedure axis_expect (
    constant exp_data : in  t_slv_array;
    constant msg      : in  string;
    signal   clk      : in  std_logic;
    signal   m2s      : in  t_axis_m2s;
    signal   s2m      : out t_axis_s2m;
    constant scope    : in  string            := C_BFM_SCOPE;
    constant config   : in  t_axis_bfm_config := C_AXIS_BFM_CONFIG_DEFAULT) is
    variable v_data : std_logic_vector(C_AXIS_DATA_WIDTH - 1 downto 0);
    variable v_last : std_logic;
  begin
    for i in exp_data'low to exp_data'high loop
      axis_receive_beat(v_data, v_last, msg, clk, m2s, s2m, scope, config);
      bfm_check_value(v_data, exp_data(i),
                      "axis_expect " & msg & " beat " & integer'image(i - exp_data'low),
                      scope);
      if i = exp_data'high then
        bfm_check_value(v_last, '1', "axis_expect " & msg & ": tlast on the last beat", scope);
      else
        bfm_check_value(v_last, '0', "axis_expect " & msg & ": no tlast before the end", scope);
      end if;
    end loop;
  end procedure axis_expect;

end package body {{pkg}};
