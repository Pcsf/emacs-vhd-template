{{!BFM: Avalon-ST source (transmit packets) and sink (receive, expect), ready latency 0}}
{{>header.vhd}}

-- Usage (in a testbench, needs bfm_util_pkg):
--   signal src_m2s : t_avst_m2s := C_AVST_M2S_INIT;   -- source -> DUT
--   signal src_s2m : t_avst_s2m := C_AVST_S2M_INIT;   -- DUT -> source
--   avst_transmit(packet, "packet 1", clk, src_m2s, src_s2m);    -- source
--   avst_expect  (packet, "packet 1", clk, snk_m2s, snk_s2m);    -- sink
-- startofpacket goes with the first beat and endofpacket with the last one.
-- Ready latency is 0 (data moves in every cycle where valid and ready are
-- both high).  Set check_sop to false for a DUT that does not carry
-- startofpacket through.  Not modelled: empty, channel, error.

library ieee;
use ieee.std_logic_1164.all;

use work.bfm_util_pkg.all;

package {{pkg|$file}} is

  constant C_AVST_DATA_WIDTH : positive := {{data_width|32}};

  type t_avst_m2s is record
    data          : std_logic_vector(C_AVST_DATA_WIDTH - 1 downto 0);
    valid         : std_logic;
    startofpacket : std_logic;
    endofpacket   : std_logic;
  end record t_avst_m2s;

  type t_avst_s2m is record
    ready : std_logic;
  end record t_avst_s2m;

  constant C_AVST_M2S_INIT : t_avst_m2s :=
    (data => (others => '0'), valid => '0', startofpacket => '0', endofpacket => '0');
  constant C_AVST_S2M_INIT : t_avst_s2m := (ready => '0');

  type t_avst_bfm_config is record
    max_wait_cycles  : natural;   -- timeout while waiting for ready / valid
    gap_cycles       : natural;   -- source: idle clocks between beats
    ready_low_cycles : natural;   -- sink: ready low clocks before each beat
    check_sop        : boolean;   -- sink: compare startofpacket too
  end record t_avst_bfm_config;

  constant C_AVST_BFM_CONFIG_DEFAULT : t_avst_bfm_config :=
    (max_wait_cycles => 1000, gap_cycles => 0, ready_low_cycles => 0, check_sop => true);

  procedure avst_transmit (
    constant data   : in  t_slv_array;
    constant msg    : in  string;
    signal   clk    : in  std_logic;
    signal   m2s    : out t_avst_m2s;
    signal   s2m    : in  t_avst_s2m;
    constant scope  : in  string            := C_BFM_SCOPE;
    constant config : in  t_avst_bfm_config := C_AVST_BFM_CONFIG_DEFAULT);

  procedure avst_receive_beat (
    variable data   : out std_logic_vector(C_AVST_DATA_WIDTH - 1 downto 0);
    variable sop    : out std_logic;
    variable eop    : out std_logic;
    constant msg    : in  string;
    signal   clk    : in  std_logic;
    signal   m2s    : in  t_avst_m2s;
    signal   s2m    : out t_avst_s2m;
    constant scope  : in  string            := C_BFM_SCOPE;
    constant config : in  t_avst_bfm_config := C_AVST_BFM_CONFIG_DEFAULT);

  procedure avst_expect (
    constant exp_data : in  t_slv_array;
    constant msg      : in  string;
    signal   clk      : in  std_logic;
    signal   m2s      : in  t_avst_m2s;
    signal   s2m      : out t_avst_s2m;
    constant scope    : in  string            := C_BFM_SCOPE;
    constant config   : in  t_avst_bfm_config := C_AVST_BFM_CONFIG_DEFAULT);

end package {{pkg}};

package body {{pkg}} is

  procedure avst_transmit (
    constant data   : in  t_slv_array;
    constant msg    : in  string;
    signal   clk    : in  std_logic;
    signal   m2s    : out t_avst_m2s;
    signal   s2m    : in  t_avst_s2m;
    constant scope  : in  string            := C_BFM_SCOPE;
    constant config : in  t_avst_bfm_config := C_AVST_BFM_CONFIG_DEFAULT) is
    variable v_wait : natural;
  begin
    if data'length = 0 then
      return;
    end if;
    if data(data'low)'length /= C_AVST_DATA_WIDTH then
      bfm_alert(FAILURE, "avst_transmit: data is " & integer'image(data(data'low)'length)
                & " bits wide, C_AVST_DATA_WIDTH is " & integer'image(C_AVST_DATA_WIDTH), scope);
    end if;
    bfm_log(C_LOG_BFM, "avst_transmit: " & msg & " (" & integer'image(data'length)
            & " beats)", scope);
    for i in data'low to data'high loop
      if i /= data'low and config.gap_cycles > 0 then
        m2s.valid <= '0';
        for g in 1 to config.gap_cycles loop
          wait until rising_edge(clk);
        end loop;
      end if;
      m2s.data  <= data(i);
      m2s.valid <= '1';
      if i = data'low then
        m2s.startofpacket <= '1';
      else
        m2s.startofpacket <= '0';
      end if;
      if i = data'high then
        m2s.endofpacket <= '1';
      else
        m2s.endofpacket <= '0';
      end if;
      v_wait := 0;
      loop
        wait until rising_edge(clk);
        exit when s2m.ready = '1';               -- accepted at this edge
        v_wait := v_wait + 1;
        if v_wait >= config.max_wait_cycles then
          bfm_alert(ERROR, "avst_transmit: timeout waiting for ready (" & msg & ")", scope);
          exit;
        end if;
      end loop;
    end loop;
    m2s <= C_AVST_M2S_INIT;
  end procedure avst_transmit;

  procedure avst_receive_beat (
    variable data   : out std_logic_vector(C_AVST_DATA_WIDTH - 1 downto 0);
    variable sop    : out std_logic;
    variable eop    : out std_logic;
    constant msg    : in  string;
    signal   clk    : in  std_logic;
    signal   m2s    : in  t_avst_m2s;
    signal   s2m    : out t_avst_s2m;
    constant scope  : in  string            := C_BFM_SCOPE;
    constant config : in  t_avst_bfm_config := C_AVST_BFM_CONFIG_DEFAULT) is
    variable v_wait : natural := 0;
  begin
    data := (others => 'X');
    sop  := 'X';
    eop  := 'X';
    for i in 1 to config.ready_low_cycles loop
      s2m.ready <= '0';
      wait until rising_edge(clk);
    end loop;
    s2m.ready <= '1';
    loop
      wait until rising_edge(clk);
      if m2s.valid = '1' then                    -- taken at this edge
        data := m2s.data;
        sop  := m2s.startofpacket;
        eop  := m2s.endofpacket;
        exit;
      end if;
      v_wait := v_wait + 1;
      if v_wait >= config.max_wait_cycles then
        bfm_alert(ERROR, "avst_receive: timeout waiting for valid (" & msg & ")", scope);
        exit;
      end if;
    end loop;
    -- See axis_receive_beat: back-to-back calls keep ready high.
    s2m.ready <= '0';
  end procedure avst_receive_beat;

  procedure avst_expect (
    constant exp_data : in  t_slv_array;
    constant msg      : in  string;
    signal   clk      : in  std_logic;
    signal   m2s      : in  t_avst_m2s;
    signal   s2m      : out t_avst_s2m;
    constant scope    : in  string            := C_BFM_SCOPE;
    constant config   : in  t_avst_bfm_config := C_AVST_BFM_CONFIG_DEFAULT) is
    variable v_data : std_logic_vector(C_AVST_DATA_WIDTH - 1 downto 0);
    variable v_sop  : std_logic;
    variable v_eop  : std_logic;
  begin
    for i in exp_data'low to exp_data'high loop
      avst_receive_beat(v_data, v_sop, v_eop, msg, clk, m2s, s2m, scope, config);
      bfm_check_value(v_data, exp_data(i),
                      "avst_expect " & msg & " beat " & integer'image(i - exp_data'low),
                      scope);
      if config.check_sop then
        if i = exp_data'low then
          bfm_check_value(v_sop, '1', "avst_expect " & msg & ": startofpacket on the first beat", scope);
        else
          bfm_check_value(v_sop, '0', "avst_expect " & msg & ": no startofpacket after the first beat", scope);
        end if;
      end if;
      if i = exp_data'high then
        bfm_check_value(v_eop, '1', "avst_expect " & msg & ": endofpacket on the last beat", scope);
      else
        bfm_check_value(v_eop, '0', "avst_expect " & msg & ": no endofpacket before the end", scope);
      end if;
    end loop;
  end procedure avst_expect;

end package body {{pkg}};
