-------------------------------------------------------------------------------
-- File        : tb_i2c_master.vhd
-- Description : Self-checking testbench of i2c_master: test cases and the
--               tripwire monitors of the ICD (doc/i2c_master_icd.org)
-- Author      : Pcsf
-- Created     : 2026-11-10
-------------------------------------------------------------------------------

-- Needs tb_util_pkg and bfm_i2c_pkg.  The bus is open drain with a weak
-- pull-up; the slave is the BFM, started by p_main through slv_req.
-- Every p_tw_* process watches one ICD clause, drives nothing, and tags its
-- alert with the CUSTOM_ID of the clause: [icd#<id>].
-- All monitors sample at the rising edge of clk, so a value they read is the
-- one the design saw at that edge, and an output change they see was caused
-- by the edge before.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.tb_util_pkg.all;
use work.bfm_i2c_pkg.all;

entity tb_i2c_master is
end entity tb_i2c_master;

architecture sim of tb_i2c_master is

  constant C_SCOPE  : string := "tb_i2c_master";
  constant C_PERIOD : time   := 10 ns;

  constant C_CLK_HZ : positive := 3200;
  constant C_SCL_HZ : positive := 100;

  -- The numbers of the ICD, in clocks.
  constant C_Q        : positive := C_CLK_HZ / (4 * C_SCL_HZ);   -- quarter of an SCL period
  constant C_SYNC     : positive := 2;                           -- stages of the SCL synchronizer
  constant C_SCL_LOW  : positive := 2 * C_Q;
  constant C_SCL_HIGH : positive := 2 * C_Q + C_SYNC;
  constant C_BIT      : positive := C_SCL_LOW + C_SCL_HIGH;
  -- START setup and hold, STOP setup, bus free time
  constant C_START_STOP : positive := 2 * C_Q;

  constant C_RSP_TIMEOUT : positive := 5000;                     -- clocks
  constant C_SLV_TIMEOUT : time     := 300 us;
  constant C_WATCHDOG    : time     := 30 ms;

  constant C_ADDR   : t_i2c_addr := "1010000";
  constant C_ADDR_W : std_logic_vector(7 downto 0) := C_ADDR & '0';
  constant C_ADDR_R : std_logic_vector(7 downto 0) := C_ADDR & '1';

  constant C_CFG : t_i2c_bfm_config :=
    (scl_period => C_BIT * C_PERIOD, stretch => 0 ns, addr_ack => true, timeout => 100 us);
  constant C_CFG_STRETCH : t_i2c_bfm_config :=
    (scl_period => C_BIT * C_PERIOD, stretch => 1 us, addr_ack => true, timeout => 100 us);
  constant C_CFG_NACK : t_i2c_bfm_config :=
    (scl_period => C_BIT * C_PERIOD, stretch => 0 ns, addr_ack => false, timeout => 100 us);

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  signal cmd_valid : std_logic := '0';
  signal cmd_ready : std_logic;
  signal cmd_start : std_logic := '0';
  signal cmd_stop  : std_logic := '0';
  signal cmd_read  : std_logic := '0';
  signal cmd_write : std_logic := '0';
  signal cmd_nack  : std_logic := '0';
  signal cmd_data  : std_logic_vector(7 downto 0) := (others => '0');
  signal rsp_valid : std_logic;
  signal rsp_data  : std_logic_vector(7 downto 0);
  signal rsp_nack  : std_logic;
  signal busy      : std_logic;
  signal scl_oe    : std_logic;
  signal sda_oe    : std_logic;

  signal scl, sda     : std_logic := 'Z';
  signal scl_x, sda_x : std_logic;               -- the bus as the design reads it

  signal hold_scl : boolean := false;            -- a slave that keeps SCL low

  -- Shared by the monitors: a command is taken at this edge, and whether a
  -- transaction was open before it.
  signal taken    : std_logic;
  signal bus_open : boolean := false;

  signal slv_req : natural := 0;
  signal slv_ack : natural := 0;

  -- Bus observer
  signal n_start    : natural := 0;              -- SDA fell while SCL was high
  signal n_stop     : natural := 0;              -- SDA rose while SCL was high
  signal n_both     : natural := 0;              -- SCL and SDA changed in the same instant
  signal n_scl_rise : natural := 0;
  signal n_rsp      : natural := 0;
  signal obs_bits   : std_logic_vector(26 downto 0) := (others => '0');   -- SDA at SCL rises
  signal meas_clr   : boolean := false;
  signal m_low_min, m_low_max       : natural := 0;                       -- clocks
  signal m_high_min, m_high_max     : natural := 0;
  signal m_period_min, m_period_max : natural := 0;
  signal m_start_setup, m_start_hold, m_stop_setup, m_bus_free : natural := 0;

  function to_sl (b : boolean) return std_logic is
  begin
    if b then
      return '1';
    else
      return '0';
    end if;
  end function to_sl;

  -- Clocks from the edge that takes a command to the edge that samples
  -- rsp_valid high, when nothing holds SCL low.
  function latency (start, stop, byte, is_open : boolean) return natural is
    variable v_n : natural := 2;
  begin
    if start then
      if is_open then
        v_n := v_n + 7 * C_Q + C_SYNC;
      else
        v_n := v_n + 3 * C_Q;
      end if;
    end if;
    if byte then
      v_n := v_n + 9 * C_BIT + C_Q;
    end if;
    if stop and (byte or (is_open and not start)) then
      v_n := v_n + 5 * C_Q + C_SYNC;
    end if;
    return v_n;
  end function latency;

begin

  p_clk : process
  begin
    clock_generator(clk, C_PERIOD);
  end process p_clk;

  u_dut : entity work.i2c_master
    generic map (G_CLK_HZ => C_CLK_HZ, G_SCL_HZ => C_SCL_HZ)
    port map (clk => clk, rst => rst,
              cmd_valid => cmd_valid, cmd_ready => cmd_ready,
              cmd_start => cmd_start, cmd_stop => cmd_stop,
              cmd_read => cmd_read, cmd_write => cmd_write,
              cmd_nack => cmd_nack, cmd_data => cmd_data,
              rsp_valid => rsp_valid, rsp_data => rsp_data,
              rsp_nack => rsp_nack, busy => busy,
              scl_i => scl_x, scl_oe => scl_oe,
              sda_i => sda_x, sda_oe => sda_oe);

  scl <= 'H';
  sda <= 'H';
  scl <= '0' when scl_oe = '1' else 'Z';
  sda <= '0' when sda_oe = '1' else 'Z';
  scl <= '0' when hold_scl else 'Z';

  scl_x <= to_x01(scl);
  sda_x <= to_x01(sda);

  taken <= cmd_valid and cmd_ready and not rst;

  p_watchdog : process
  begin
    wait for C_WATCHDOG;
    alert(FAILURE, "watchdog: the test did not finish", C_SCOPE);
    wait;
  end process p_watchdog;

  ---------------------------------------------------------------------------
  -- Slave: one BFM script per request from p_main
  ---------------------------------------------------------------------------
  p_slave : process
    variable v_rx : t_slv_array(0 to 0)(7 downto 0);
  begin
    wait on slv_req;
    case slv_req is
      when 20 => i2c_slave_check(C_ADDR, (0 => x"A5"), "TC-02", scl, sda, C_SCOPE, C_CFG);
      when 30 => i2c_slave_receive(C_ADDR, v_rx, "TC-03", scl, sda, C_SCOPE, C_CFG_NACK);
      when 40 => i2c_slave_transmit(C_ADDR, (x"9A", x"C3"), "TC-04", scl, sda, C_SCOPE, C_CFG);
      when 50 =>
        i2c_slave_check(C_ADDR, (0 => x"07"), "TC-05 pointer", scl, sda, C_SCOPE, C_CFG);
        i2c_slave_transmit(C_ADDR, (0 => x"5E"), "TC-05 data", scl, sda, C_SCOPE, C_CFG);
      when 60 => i2c_slave_check(C_ADDR, (0 => x"3C"), "TC-06", scl, sda, C_SCOPE, C_CFG);
      when 70 =>
        i2c_slave_check(C_ADDR, (x"A5", x"5A"), "TC-07 write", scl, sda, C_SCOPE, C_CFG_STRETCH);
        i2c_slave_transmit(C_ADDR, (x"3C", x"81"), "TC-07 read", scl, sda, C_SCOPE,
                           C_CFG_STRETCH);
      when 80  => i2c_slave_check(C_ADDR, (x"11", x"22", x"33"), "TC-08", scl, sda, C_SCOPE, C_CFG);
      when 90  => i2c_slave_check(C_ADDR, (0 => x"55"), "TC-09", scl, sda, C_SCOPE, C_CFG);
      when 91  => i2c_slave_transmit(C_ADDR, (0 => x"0F"), "TC-09 read", scl, sda, C_SCOPE, C_CFG);
      when 100 => i2c_slave_check(C_ADDR, (0 => x"22"), "TC-10", scl, sda, C_SCOPE, C_CFG);
      when 110 => i2c_slave_transmit(C_ADDR, (0 => x"C3"), "TC-11", scl, sda, C_SCOPE, C_CFG);
      when 160 => i2c_slave_check(C_ADDR, (0 => x"5A"), "TC-16", scl, sda, C_SCOPE, C_CFG);
      when 180 => i2c_slave_transmit(C_ADDR, (0 => x"00"), "TC-18", scl, sda, C_SCOPE, C_CFG);
      when 181 => i2c_slave_check(C_ADDR, (0 => x"77"), "TC-18 after", scl, sda, C_SCOPE, C_CFG);
      when 190 => i2c_slave_transmit(C_ADDR, (0 => x"00"), "TC-19", scl, sda, C_SCOPE, C_CFG);
      when 191 => i2c_slave_check(C_ADDR, (0 => x"88"), "TC-19 after", scl, sda, C_SCOPE, C_CFG);
      when others => null;
    end case;
    slv_ack <= slv_req;
  end process p_slave;

  ---------------------------------------------------------------------------
  -- Bus observer: counts and measures, for the test cases
  ---------------------------------------------------------------------------
  p_bus_obs : process
    variable v_rise, v_fall, v_start, v_stop : time := 0 ns;
    variable v_rise_ok, v_fall_ok            : boolean := false;
    variable v_start_open, v_stop_seen       : boolean := false;
    variable v_first                         : boolean := true;
    variable v_n                             : natural;

    procedure min_max (signal lo, hi : inout natural; constant n : in natural;
                       constant first : in boolean) is
    begin
      if first or n < lo then
        lo <= n;
      end if;
      if first or n > hi then
        hi <= n;
      end if;
    end procedure min_max;
  begin
    wait on scl_x, sda_x, meas_clr;
    if meas_clr'event then
      v_rise_ok := false;
      v_fall_ok := false;
      v_first   := true;
      m_low_min <= 0;  m_low_max <= 0;  m_high_min <= 0;  m_high_max <= 0;
      m_period_min <= 0;  m_period_max <= 0;
    end if;
    if scl_x'event and sda_x'event and now > 0 ns then
      n_both <= n_both + 1;
    elsif sda_x'event and scl_x = '1' and sda_x'last_value = not sda_x then
      if sda_x = '0' then
        n_start       <= n_start + 1;
        m_start_setup <= (now - v_rise) / C_PERIOD;
        if v_stop_seen then
          m_bus_free <= (now - v_stop) / C_PERIOD;
        end if;
        v_start      := now;
        v_start_open := true;
        v_stop_seen  := false;
      else
        n_stop       <= n_stop + 1;
        m_stop_setup <= (now - v_rise) / C_PERIOD;
        v_stop       := now;
        v_stop_seen  := true;
      end if;
    end if;
    if scl_x'event and scl_x = '1' and scl_x'last_value = '0' then
      n_scl_rise <= n_scl_rise + 1;
      obs_bits   <= obs_bits(25 downto 0) & sda_x;
      if v_fall_ok then
        v_n := (now - v_fall) / C_PERIOD;
        min_max(m_low_min, m_low_max, v_n, m_low_max = 0);
      end if;
      if v_rise_ok then
        v_n := (now - v_rise) / C_PERIOD;
        min_max(m_period_min, m_period_max, v_n, m_period_max = 0);
      end if;
      v_rise    := now;
      v_rise_ok := true;
    elsif scl_x'event and scl_x = '0' and scl_x'last_value = '1' then
      if v_rise_ok then
        v_n := (now - v_rise) / C_PERIOD;
        min_max(m_high_min, m_high_max, v_n, m_high_max = 0);
      end if;
      if v_start_open then
        m_start_hold <= (now - v_start) / C_PERIOD;
        v_start_open := false;
      end if;
      v_fall    := now;
      v_fall_ok := true;
    end if;
  end process p_bus_obs;

  p_rsp_count : process
  begin
    wait until rising_edge(clk);
    if rsp_valid = '1' then
      n_rsp <= n_rsp + 1;
    end if;
  end process p_rsp_count;

  -- Mirror of the transaction state, from the commands taken.
  p_bus_open : process
    variable v_byte : boolean;
  begin
    wait until rising_edge(clk);
    if rst = '1' then
      bus_open <= false;
    elsif taken = '1' then
      v_byte := cmd_read = '1' or cmd_write = '1';
      if cmd_stop = '1' and (v_byte or cmd_start = '0') then
        bus_open <= false;
      elsif cmd_start = '1' then
        bus_open <= true;
      end if;
    end if;
  end process p_bus_open;

  ---------------------------------------------------------------------------
  -- Tripwire monitors: what the hardware promises on the bus
  ---------------------------------------------------------------------------
  p_tw_sda_change : process
    variable v_sda_oe, v_scl : std_logic := '0';
    variable v_rst           : std_logic := '1';
    variable v_start_ok      : boolean := false;
    variable v_stop_ok       : boolean := false;
  begin
    wait until rising_edge(clk);
    if sda_oe /= v_sda_oe and v_rst = '0' and (v_scl = '1' or scl_x = '1') then
      if sda_oe = '1' and v_start_ok and v_scl = '1' and scl_x = '1' then
        v_start_ok := false;
      elsif sda_oe = '0' and v_stop_ok and v_scl = '1' and scl_x = '1' then
        v_stop_ok := false;
      else
        alert(ERROR, "[icd#sda-change] sda_oe changed to " & to_string(sda_oe)
              & " while SCL was high, without a START or STOP asked for", C_SCOPE);
      end if;
    end if;
    if rst = '1' then
      v_start_ok := false;
      v_stop_ok  := false;
    elsif taken = '1' then
      v_start_ok := cmd_start = '1';
      v_stop_ok  := cmd_stop = '1';
    end if;
    v_sda_oe := sda_oe;
    v_scl    := scl_x;
    v_rst    := rst;
  end process p_tw_sda_change;

  p_tw_scl_low : process
    variable v_scl_oe : std_logic := '0';
    variable v_rst    : std_logic := '1';
    variable v_low    : natural := 0;
  begin
    wait until rising_edge(clk);
    if scl_oe = '0' and v_scl_oe = '1' and v_rst = '0' and v_low < C_SCL_LOW then
      alert(ERROR, "[icd#scl-low] SCL held low for " & to_string(v_low)
            & " clocks, at least " & to_string(C_SCL_LOW) & " promised", C_SCOPE);
    end if;
    if scl_oe = '1' then
      v_low := v_low + 1;
    else
      v_low := 0;
    end if;
    v_scl_oe := scl_oe;
    v_rst    := rst;
  end process p_tw_scl_low;

  p_tw_scl_high : process
    variable v_scl_oe : std_logic := '0';
    variable v_high   : natural := C_SCL_LOW;
  begin
    wait until rising_edge(clk);
    if scl_oe = '1' and v_scl_oe = '0' and v_high < 2 * C_Q then
      alert(ERROR, "[icd#scl-high] SCL pulled low after " & to_string(v_high)
            & " clocks high, at least " & to_string(2 * C_Q) & " promised", C_SCOPE);
    end if;
    if scl_x = '1' then
      v_high := v_high + 1;
    else
      v_high := 0;
    end if;
    v_scl_oe := scl_oe;
  end process p_tw_scl_high;

  p_tw_start_setup : process
    variable v_sda_oe, v_scl : std_logic := '0';
    variable v_rst           : std_logic := '1';
    variable v_high          : natural := C_START_STOP;   -- clocks SCL has been high
    variable v_released      : natural := C_START_STOP;   -- clocks sda_oe has been '0'
  begin
    wait until rising_edge(clk);
    if sda_oe = '1' and v_sda_oe = '0' and v_scl = '1' and scl_x = '1' and v_rst = '0'
      and (v_high < C_START_STOP or v_released < C_START_STOP) then
      alert(ERROR, "[icd#start-setup] START after SCL was high for " & to_string(v_high)
            & " and SDA released for " & to_string(v_released) & " clocks, at least "
            & to_string(C_START_STOP) & " promised", C_SCOPE);
    end if;
    if scl_x = '1' then
      v_high := v_high + 1;
    else
      v_high := 0;
    end if;
    if sda_oe = '0' then
      v_released := v_released + 1;
    else
      v_released := 0;
    end if;
    v_sda_oe := sda_oe;
    v_scl    := scl_x;
    v_rst    := rst;
  end process p_tw_start_setup;

  p_tw_start_hold : process
    variable v_sda_oe, v_scl : std_logic := '0';
    variable v_rst           : std_logic := '1';
    variable v_hold          : natural := 0;
    variable v_in_hold       : boolean := false;
  begin
    wait until rising_edge(clk);
    if rst = '1' then
      v_in_hold := false;
    elsif v_in_hold then
      if scl_oe = '1' then
        if v_hold < C_START_STOP then
          alert(ERROR, "[icd#start-hold] SCL pulled low " & to_string(v_hold)
                & " clocks after the START, at least " & to_string(C_START_STOP) & " promised",
                C_SCOPE);
        end if;
        v_in_hold := false;
      else
        v_hold := v_hold + 1;
      end if;
    end if;
    if sda_oe = '1' and v_sda_oe = '0' and v_scl = '1' and scl_x = '1' and v_rst = '0' then
      v_in_hold := true;
      v_hold    := 1;
    end if;
    v_sda_oe := sda_oe;
    v_scl    := scl_x;
    v_rst    := rst;
  end process p_tw_start_hold;

  p_tw_stop_setup : process
    variable v_sda_oe, v_scl : std_logic := '0';
    variable v_rst           : std_logic := '1';
    variable v_high          : natural := 0;
  begin
    wait until rising_edge(clk);
    if sda_oe = '0' and v_sda_oe = '1' and v_rst = '0' and scl_oe = '0' and scl_x = '1'
      and (v_scl /= '1' or v_high < C_START_STOP) then
      alert(ERROR, "[icd#stop-setup] STOP after SCL was high for " & to_string(v_high)
            & " clocks, at least " & to_string(C_START_STOP) & " promised", C_SCOPE);
    end if;
    if scl_x = '1' then
      v_high := v_high + 1;
    else
      v_high := 0;
    end if;
    v_sda_oe := sda_oe;
    v_scl    := scl_x;
    v_rst    := rst;
  end process p_tw_stop_setup;

  p_tw_bus_free : process
    variable v_sda_oe  : std_logic := '0';
    variable v_rst     : std_logic := '1';
    variable v_free    : natural := 0;
    variable v_in_free : boolean := false;
  begin
    wait until rising_edge(clk);
    if rst = '1' then
      v_in_free := false;
    elsif v_in_free then
      if scl_oe = '1' or sda_oe = '1' then
        if v_free < C_START_STOP then
          alert(ERROR, "[icd#bus-free] bus driven again " & to_string(v_free)
                & " clocks after the STOP, at least " & to_string(C_START_STOP) & " promised",
                C_SCOPE);
        end if;
        v_in_free := false;
      else
        v_free := v_free + 1;
      end if;
    end if;
    if sda_oe = '0' and v_sda_oe = '1' and v_rst = '0' and scl_oe = '0' and scl_x = '1' then
      v_in_free := true;
      v_free    := 1;
    end if;
    v_sda_oe := sda_oe;
    v_rst    := rst;
  end process p_tw_bus_free;

  p_tw_sda_setup : process
    variable v_sda_oe, v_scl_oe : std_logic := '0';
    variable v_rst              : std_logic := '1';
    variable v_stable           : natural := C_Q;
  begin
    wait until rising_edge(clk);
    if sda_oe /= v_sda_oe then
      v_stable := 0;
    else
      v_stable := v_stable + 1;
    end if;
    if scl_oe = '0' and v_scl_oe = '1' and v_rst = '0' and v_stable < C_Q then
      alert(ERROR, "[icd#sda-setup] SCL released " & to_string(v_stable)
            & " clocks after sda_oe changed, at least " & to_string(C_Q) & " promised", C_SCOPE);
    end if;
    v_sda_oe := sda_oe;
    v_scl_oe := scl_oe;
    v_rst    := rst;
  end process p_tw_sda_setup;

  p_tw_sda_hold : process
    variable v_sda_oe : std_logic := '0';
    variable v_rst    : std_logic := '1';
    variable v_low    : natural := 0;            -- clocks scl_oe has been '1'
  begin
    wait until rising_edge(clk);
    if sda_oe /= v_sda_oe and scl_oe = '1' and v_rst = '0' and v_low < C_Q then
      alert(ERROR, "[icd#sda-hold] sda_oe changed " & to_string(v_low)
            & " clocks after SCL was pulled low, at least " & to_string(C_Q) & " promised",
            C_SCOPE);
    end if;
    if scl_oe = '1' then
      v_low := v_low + 1;
    else
      v_low := 0;
    end if;
    v_sda_oe := sda_oe;
    v_rst    := rst;
  end process p_tw_sda_hold;

  p_tw_stretch_wait : process
    variable v_sda_oe, v_scl_oe, v_scl : std_logic := '0';
    variable v_rst                     : std_logic := '1';
  begin
    wait until rising_edge(clk);
    if (sda_oe /= v_sda_oe or scl_oe /= v_scl_oe) and v_rst = '0'
      and v_scl_oe = '0' and v_scl = '0' then
      alert(ERROR, "[icd#stretch-wait] the master went on while SCL was held low", C_SCOPE);
    end if;
    v_sda_oe := sda_oe;
    v_scl_oe := scl_oe;
    v_scl    := scl_x;
    v_rst    := rst;
  end process p_tw_stretch_wait;

  p_tw_rst_release : process
    variable v_rst : std_logic := '0';
    variable v_bad : boolean := false;
  begin
    wait until rising_edge(clk);
    if v_rst = '1' and (scl_oe = '1' or sda_oe = '1' or busy = '1' or cmd_ready = '0'
                        or rsp_valid = '1') then
      if not v_bad then
        alert(ERROR, "[icd#rst-release] one clock after rst: scl_oe=" & to_string(scl_oe)
              & " sda_oe=" & to_string(sda_oe) & " busy=" & to_string(busy)
              & " cmd_ready=" & to_string(cmd_ready) & " rsp_valid=" & to_string(rsp_valid),
              C_SCOPE);
      end if;
      v_bad := true;
    else
      v_bad := false;
    end if;
    v_rst := rst;
  end process p_tw_rst_release;

  ---------------------------------------------------------------------------
  -- Tripwire monitors: what the hardware promises to the user logic
  ---------------------------------------------------------------------------
  p_tw_rsp_pulse : process
    variable v_valid : std_logic := '0';
    variable v_bad   : boolean := false;
  begin
    wait until rising_edge(clk);
    if rsp_valid = '1' and v_valid = '1' then
      if not v_bad then
        alert(ERROR, "[icd#rsp-pulse] rsp_valid is high for more than one clock", C_SCOPE);
      end if;
      v_bad := true;
    else
      v_bad := false;
    end if;
    v_valid := rsp_valid;
  end process p_tw_rsp_pulse;

  p_tw_rsp_per_cmd : process
    variable v_valid   : std_logic := '0';
    variable v_pending : boolean := false;
  begin
    wait until rising_edge(clk);
    if rsp_valid = '1' and v_valid = '0' then
      if not v_pending then
        alert(ERROR, "[icd#rsp-per-cmd] response without a command", C_SCOPE);
      end if;
      v_pending := false;
    end if;
    if rst = '1' then
      v_pending := false;
    elsif taken = '1' then
      if v_pending then
        alert(ERROR, "[icd#rsp-per-cmd] command taken before the response to the one before",
              C_SCOPE);
      end if;
      v_pending := true;
    end if;
    v_valid := rsp_valid;
  end process p_tw_rsp_per_cmd;

  p_tw_ready_busy : process
    variable v_busy, v_taken : std_logic := '0';
    variable v_rst           : std_logic := '1';
    variable v_ok            : boolean;
    variable v_bad           : boolean := false;
  begin
    wait until rising_edge(clk);
    v_ok := cmd_ready = not busy;
    if v_rst = '0' then
      v_ok := v_ok and (busy = '1') = (v_taken = '1' or (v_busy = '1' and rsp_valid = '0'));
    end if;
    if not v_ok and not v_bad then
      alert(ERROR, "[icd#ready-busy] cmd_ready=" & to_string(cmd_ready) & " busy="
            & to_string(busy) & " rsp_valid=" & to_string(rsp_valid)
            & ", command taken at the edge before: " & to_string(v_taken), C_SCOPE);
    end if;
    v_bad   := not v_ok;
    v_busy  := busy;
    v_taken := taken;
    v_rst   := rst;
  end process p_tw_ready_busy;

  p_tw_rsp_stable : process
    variable v_data : std_logic_vector(7 downto 0) := (others => '0');
    variable v_nack : std_logic := '0';
  begin
    wait until rising_edge(clk);
    if (rsp_data /= v_data or rsp_nack /= v_nack) and rsp_valid = '0' then
      alert(ERROR, "[icd#rsp-stable] rsp_data or rsp_nack changed without rsp_valid", C_SCOPE);
    end if;
    v_data := rsp_data;
    v_nack := rsp_nack;
  end process p_tw_rsp_stable;

  p_tw_cmd_latency : process
    variable v_active  : boolean := false;
    variable v_clocks  : natural := 0;
    variable v_stretch : natural := 0;           -- clocks with SCL released but low
    variable v_expect  : natural := 0;
  begin
    wait until rising_edge(clk);
    if v_active then
      v_clocks := v_clocks + 1;
      if scl_oe = '0' and scl_x = '0' then
        v_stretch := v_stretch + 1;
      end if;
      if rsp_valid = '1' then
        if v_clocks - v_stretch /= v_expect then
          alert(ERROR, "[icd#cmd-latency] response after " & to_string(v_clocks) & " clocks, "
                & to_string(v_stretch) & " of them with SCL held low; expected "
                & to_string(v_expect) & " plus the held ones", C_SCOPE);
        end if;
        v_active := false;
      end if;
    end if;
    if rst = '1' then
      v_active := false;
    elsif taken = '1' then
      v_active  := true;
      v_clocks  := 0;
      v_stretch := 0;
      v_expect  := latency(cmd_start = '1', cmd_stop = '1',
                           cmd_read = '1' or cmd_write = '1', bus_open);
    end if;
  end process p_tw_cmd_latency;

  ---------------------------------------------------------------------------
  -- Tripwire monitors: what software owes, and the hardware tolerates
  ---------------------------------------------------------------------------
  p_tw_cmd_stable : process
    variable v_valid, v_ready : std_logic := '0';
    variable v_rst            : std_logic := '1';
    variable v_fields         : std_logic_vector(12 downto 0) := (others => '0');
    variable v_now            : std_logic_vector(12 downto 0);
  begin
    wait until rising_edge(clk);
    v_now := cmd_start & cmd_stop & cmd_read & cmd_write & cmd_nack & cmd_data;
    if v_valid = '1' and v_ready = '0' and v_rst = '0' and rst = '0'
      and (cmd_valid = '0' or v_now /= v_fields) then
      alert(ERROR, "[icd#cmd-stable] command changed or withdrawn before it was taken", C_SCOPE);
    end if;
    v_valid  := cmd_valid;
    v_ready  := cmd_ready;
    v_rst    := rst;
    v_fields := v_now;
  end process p_tw_cmd_stable;

  p_tw_cmd_rd_wr : process
  begin
    wait until rising_edge(clk);
    if taken = '1' and cmd_read = '1' and cmd_write = '1' then
      alert(ERROR, "[icd#cmd-rd-wr] command with cmd_read and cmd_write both set", C_SCOPE);
    end if;
  end process p_tw_cmd_rd_wr;

  p_tw_cmd_empty : process
  begin
    wait until rising_edge(clk);
    if taken = '1' and (cmd_start or cmd_stop or cmd_read or cmd_write) = '0' then
      alert(ERROR, "[icd#cmd-empty] command with nothing to do", C_SCOPE);
    end if;
  end process p_tw_cmd_empty;

  p_tw_stop_idle : process
  begin
    wait until rising_edge(clk);
    if taken = '1' and cmd_stop = '1' and (cmd_start or cmd_read or cmd_write) = '0'
      and not bus_open then
      alert(ERROR, "[icd#stop-idle] STOP asked for with no transaction open", C_SCOPE);
    end if;
  end process p_tw_stop_idle;

  p_tw_start_stop_empty : process
  begin
    wait until rising_edge(clk);
    if taken = '1' and cmd_start = '1' and cmd_stop = '1' and (cmd_read or cmd_write) = '0' then
      alert(ERROR, "[icd#start-stop-empty] START and STOP in one command without a byte",
            C_SCOPE);
    end if;
  end process p_tw_start_stop_empty;

  p_tw_byte_no_start : process
  begin
    wait until rising_edge(clk);
    if taken = '1' and (cmd_read or cmd_write) = '1' and cmd_start = '0' and not bus_open
      and not (cmd_read = '1' and cmd_nack = '1' and cmd_stop = '1') then
      alert(ERROR, "[icd#byte-no-start] byte asked for with no transaction open", C_SCOPE);
    end if;
  end process p_tw_byte_no_start;

  p_tw_cmd_in_reset : process
    variable v_bad : boolean := false;
  begin
    wait until rising_edge(clk);
    if rst = '1' and cmd_valid = '1' then
      if not v_bad then
        alert(ERROR, "[icd#cmd-in-reset] cmd_valid high while rst is high", C_SCOPE);
      end if;
      v_bad := true;
    else
      v_bad := false;
    end if;
  end process p_tw_cmd_in_reset;

  p_tw_rst_while_busy : process
    variable v_rst : std_logic := '1';
  begin
    wait until rising_edge(clk);
    if rst = '1' and v_rst = '0' and busy = '1' then
      alert(ERROR, "[icd#rst-while-busy] rst in the middle of a command", C_SCOPE);
    end if;
    v_rst := rst;
  end process p_tw_rst_while_busy;

  ---------------------------------------------------------------------------
  -- Test cases
  ---------------------------------------------------------------------------
  p_main : process
    variable v_rd, v_rd2      : std_logic_vector(7 downto 0);
    variable v_nack           : std_logic;
    variable v_lat            : natural;
    variable v_low, v_high    : natural;
    variable v_period, v_setup : natural;
    variable b_start, b_stop  : natural;
    variable b_both, b_rise   : natural;
    variable b_rsp            : natural;

    procedure put (constant start, stop, read, write, nack : in std_logic;
                   constant data : in std_logic_vector(7 downto 0)) is
      variable v_n : natural := 0;
    begin
      cmd_start <= start;
      cmd_stop  <= stop;
      cmd_read  <= read;
      cmd_write <= write;
      cmd_nack  <= nack;
      cmd_data  <= data;
      cmd_valid <= '1';
      loop
        wait until rising_edge(clk);
        exit when cmd_ready = '1' and rst = '0';
        v_n := v_n + 1;
        if v_n = C_RSP_TIMEOUT then
          alert(ERROR, "command not taken within " & to_string(C_RSP_TIMEOUT) & " clocks",
                C_SCOPE);
          exit;
        end if;
      end loop;
    end procedure put;

    procedure idle is
    begin
      cmd_valid <= '0';
      cmd_start <= '0';
      cmd_stop  <= '0';
      cmd_read  <= '0';
      cmd_write <= '0';
      cmd_nack  <= '0';
      cmd_data  <= (others => '0');
    end procedure idle;

    -- Returns at the edge that samples rsp_valid high; clocks counts the
    -- edges waited.
    procedure get (variable rd     : out std_logic_vector(7 downto 0);
                   variable nacked : out std_logic;
                   variable clocks : out natural) is
      variable v_n : natural := 0;
    begin
      loop
        wait until rising_edge(clk);
        v_n := v_n + 1;
        exit when rsp_valid = '1';
        if v_n = C_RSP_TIMEOUT then
          alert(ERROR, "no response within " & to_string(C_RSP_TIMEOUT) & " clocks", C_SCOPE);
          exit;
        end if;
      end loop;
      rd     := rsp_data;
      nacked := rsp_nack;
      clocks := v_n;
    end procedure get;

    procedure cmd (constant start, stop, read, write, nack : in std_logic;
                   constant data : in std_logic_vector(7 downto 0)) is
    begin
      put(start, stop, read, write, nack, data);
      idle;
      get(v_rd, v_nack, v_lat);
    end procedure cmd;

    procedure slave_arm (constant script : in natural) is
    begin
      slv_req <= script;
      wait_num_rising_edges(clk, 2);
    end procedure slave_arm;

    procedure slave_done (constant script : in natural) is
    begin
      if slv_ack /= script then
        wait until slv_ack = script for C_SLV_TIMEOUT;
      end if;
      check_value(slv_ack = script, "slave script " & to_string(script) & " finished", C_SCOPE);
    end procedure slave_done;

    procedure snap is
    begin
      b_start := n_start;
      b_stop  := n_stop;
      b_both  := n_both;
      b_rise  := n_scl_rise;
      b_rsp   := n_rsp;
    end procedure snap;

    -- Bus events since snap.
    procedure check_bus (constant starts, stops, rises : in natural; constant msg : in string) is
    begin
      check_value(n_start - b_start, starts, msg & ": START conditions on the bus", C_SCOPE);
      check_value(n_stop - b_stop, stops, msg & ": STOP conditions on the bus", C_SCOPE);
      check_value(n_scl_rise - b_rise, rises, msg & ": SCL pulses", C_SCOPE);
    end procedure check_bus;

    procedure check_idle (constant msg : in string) is
    begin
      wait until falling_edge(clk);
      check_value(scl_x = '1' and sda_x = '1', msg & ": SCL and SDA are high", C_SCOPE);
      check_value(busy = '0' and cmd_ready = '1', msg & ": block is ready", C_SCOPE);
    end procedure check_idle;

    procedure wait_clocks_until (constant what : in string; constant n : in natural) is
      variable v_n : natural := 0;
    begin
      loop
        wait until rising_edge(clk);
        if what = "scl_rise" then
          exit when n_scl_rise = n;
        elsif what = "scl_low_sda_low" then
          exit when scl_oe = '1' and sda_oe = '1';
        elsif what = "scl_high_sda_low" then
          exit when scl_oe = '0' and scl_x = '1' and sda_oe = '1';
        elsif what = "scl_high" then
          exit when scl_oe = '0' and scl_x = '1';
        elsif what = "scl_pulled_low" then
          exit when scl_oe = '1';
        end if;
        v_n := v_n + 1;
        if v_n = C_RSP_TIMEOUT then
          alert(ERROR, "timeout waiting for " & what, C_SCOPE);
          exit;
        end if;
      end loop;
    end procedure wait_clocks_until;

    -- rst for two clocks; checks the outputs at the second edge, which is one
    -- clock after rst was first sampled high.
    procedure reset_pulse (constant msg : in string) is
    begin
      rst <= '1';
      wait_num_rising_edges(clk, 2);
      check_value(scl_oe = '0' and sda_oe = '0', msg & ": both lines released one clock after rst",
                  C_SCOPE);
      check_value(cmd_ready = '1' and busy = '0', msg & ": ready one clock after rst", C_SCOPE);
      rst <= '0';
    end procedure reset_pulse;

  begin
    set_log_verbosity(C_LOG_HDR);

    -------------------------------------------------------------------------
    tc_start("TC-01", "after rst the block is ready and both bus lines are released", C_SCOPE);
    rst <= '1';
    wait_num_rising_edges(clk, 4);
    rst <= '0';
    wait until falling_edge(clk);
    check_value(cmd_ready, '1', "cmd_ready after reset", C_SCOPE);
    check_value(busy, '0', "busy after reset", C_SCOPE);
    check_value(rsp_valid, '0', "rsp_valid after reset", C_SCOPE);
    check_value(scl_oe, '0', "scl_oe after reset", C_SCOPE);
    check_value(sda_oe, '0', "sda_oe after reset", C_SCOPE);
    wait_num_rising_edges(clk, 4 * C_BIT);
    check_idle("idle with no command");
    check_value(n_start + n_stop + n_both, 0, "no bus activity without a command", C_SCOPE);
    check_value(n_rsp, 0, "no response without a command", C_SCOPE);

    -------------------------------------------------------------------------
    tc_start("TC-02", "a byte written to a slave that acknowledges reports rsp_nack = 0", C_SCOPE);
    snap;
    slave_arm(20);
    cmd('1', '0', '0', '1', '0', C_ADDR_W);
    check_value(v_nack, '0', "address acknowledged", C_SCOPE);
    cmd('0', '1', '0', '1', '0', x"A5");
    check_value(v_nack, '0', "data byte acknowledged", C_SCOPE);
    slave_done(20);
    check_bus(1, 1, 19, "write");
    check_idle("after the STOP");

    -------------------------------------------------------------------------
    tc_start("TC-03", "a byte that no slave acknowledges reports rsp_nack = 1", C_SCOPE);
    snap;
    slave_arm(30);
    cmd('1', '0', '0', '1', '0', C_ADDR_W);
    check_value(v_nack, '1', "address not acknowledged", C_SCOPE);
    wait until falling_edge(clk);
    check_value(scl_x = '0' and busy = '0', "transaction left open, block ready", C_SCOPE);
    cmd('0', '1', '0', '0', '0', x"00");
    slave_done(30);
    check_bus(1, 1, 10, "NACKed address");
    check_idle("after the STOP");

    -------------------------------------------------------------------------
    tc_start("TC-04", "bytes are read with ACK, and with NACK when cmd_nack is set", C_SCOPE);
    snap;
    slave_arm(40);
    cmd('1', '0', '0', '1', '0', C_ADDR_R);
    check_value(v_nack, '0', "address acknowledged", C_SCOPE);
    cmd('0', '0', '1', '0', '0', x"00");
    check_value(v_rd, x"9A", "first byte read", C_SCOPE);
    check_value(v_nack, '0', "rsp_nack is 0 for a read", C_SCOPE);
    cmd('0', '1', '1', '0', '1', x"00");
    check_value(v_rd, x"C3", "second byte read", C_SCOPE);
    check_value(v_nack, '0', "rsp_nack is 0 for a read answered with NACK", C_SCOPE);
    slave_done(40);
    check_bus(1, 1, 28, "read");
    -- obs_bits(0) is the SCL rise of the STOP.
    check_value(obs_bits(10), '0', "first byte answered with ACK", C_SCOPE);
    check_value(obs_bits(1), '1', "last byte answered with NACK", C_SCOPE);
    check_idle("after the STOP");

    -------------------------------------------------------------------------
    tc_start("TC-05", "cmd_start in an open transaction makes a repeated START", C_SCOPE);
    snap;
    slave_arm(50);
    cmd('1', '0', '0', '1', '0', C_ADDR_W);
    cmd('0', '0', '0', '1', '0', x"07");
    check_value(v_nack, '0', "pointer byte acknowledged", C_SCOPE);
    check_bus(1, 0, 18, "before the repeated START");
    cmd('1', '0', '0', '1', '0', C_ADDR_R);
    check_value(v_nack, '0', "address acknowledged after the repeated START", C_SCOPE);
    check_bus(2, 0, 28, "after the repeated START");
    cmd('0', '1', '1', '0', '1', x"00");
    check_value(v_rd, x"5E", "byte read after the repeated START", C_SCOPE);
    slave_done(50);
    check_bus(2, 1, 38, "whole transfer");
    check_idle("after the STOP");

    -------------------------------------------------------------------------
    tc_start("TC-06", "START, byte and STOP each work as a command of their own", C_SCOPE);
    snap;
    slave_arm(60);
    cmd('1', '0', '0', '0', '0', x"00");
    check_value(v_lat, 3 * C_Q + 2, "latency of a START alone", C_SCOPE);
    check_bus(1, 0, 0, "START alone");
    wait until falling_edge(clk);
    check_value(scl_x = '0' and sda_x = '0', "SCL and SDA low after the START", C_SCOPE);
    check_value(busy, '0', "block ready with the transaction open", C_SCOPE);
    cmd('0', '0', '0', '1', '0', C_ADDR_W);
    check_value(v_nack, '0', "address acknowledged", C_SCOPE);
    check_value(v_lat, 9 * C_BIT + C_Q + 2, "latency of a byte alone", C_SCOPE);
    cmd('0', '0', '0', '1', '0', x"3C");
    check_bus(1, 0, 18, "two bytes");
    cmd('0', '1', '0', '0', '0', x"00");
    check_value(v_lat, 5 * C_Q + C_SYNC + 2, "latency of a STOP alone", C_SCOPE);
    slave_done(60);
    check_bus(1, 1, 19, "STOP alone");
    check_idle("after the STOP");

    -------------------------------------------------------------------------
    tc_start("TC-07", "the master waits while a slave holds SCL low", C_SCOPE);
    snap;
    meas_clr <= not meas_clr;
    slave_arm(70);
    cmd('1', '0', '0', '1', '0', C_ADDR_W);
    cmd('0', '0', '0', '1', '0', x"A5");
    cmd('0', '1', '0', '1', '0', x"5A");
    check_value(v_nack, '0', "stretched write acknowledged", C_SCOPE);
    cmd('1', '0', '0', '1', '0', C_ADDR_R);
    cmd('0', '0', '1', '0', '0', x"00");
    check_value(v_rd, x"3C", "first byte read with stretching", C_SCOPE);
    cmd('0', '1', '1', '0', '1', x"00");
    check_value(v_rd, x"81", "second byte read with stretching", C_SCOPE);
    slave_done(70);
    check_bus(2, 2, 56, "stretched transfers");
    check_value(m_low_max * C_PERIOD >= C_CFG_STRETCH.stretch,
                "SCL was low for at least the stretch, longest " & to_string(m_low_max)
                & " clocks", C_SCOPE);
    check_idle("after the STOP");

    -------------------------------------------------------------------------
    tc_start("TC-08", "a waiting command is taken in the clock of rsp_valid", C_SCOPE);
    snap;
    meas_clr <= not meas_clr;
    slave_arm(80);
    put('1', '0', '0', '1', '0', C_ADDR_W);
    put('0', '0', '0', '1', '0', x"11");
    check_value(rsp_valid, '1', "second command taken in the clock of the first response",
                C_SCOPE);
    check_value(rsp_nack, '0', "address acknowledged", C_SCOPE);
    put('0', '0', '0', '1', '0', x"22");
    check_value(rsp_valid, '1', "third command taken in the clock of the second response",
                C_SCOPE);
    put('0', '1', '0', '1', '0', x"33");
    check_value(rsp_valid, '1', "fourth command taken in the clock of the third response",
                C_SCOPE);
    idle;
    get(v_rd, v_nack, v_lat);
    check_value(v_nack, '0', "last byte acknowledged", C_SCOPE);
    slave_done(80);
    check_bus(1, 1, 37, "back-to-back write");
    check_idle("after the STOP");
    check_value(n_rsp - b_rsp, 4, "four responses for four commands", C_SCOPE);
    check_value(m_low_max, 3 * C_Q + 2, "SCL low between two bytes sent back to back", C_SCOPE);

    -------------------------------------------------------------------------
    tc_start("TC-09", "SCL and the START and STOP timing have the derived numbers", C_SCOPE);
    slave_arm(90);
    cmd('1', '0', '0', '1', '0', C_ADDR_W);
    meas_clr <= not meas_clr;
    cmd('0', '0', '0', '1', '0', x"55");
    check_value(m_low_min = C_SCL_LOW and m_low_max = C_SCL_LOW,
                "SCL low within a byte is 2 * C_Q clocks, measured " & to_string(m_low_min)
                & " to " & to_string(m_low_max), C_SCOPE);
    check_value(m_period_min = C_BIT and m_period_max = C_BIT,
                "SCL period within a byte is 4 * C_Q + 2 clocks, measured "
                & to_string(m_period_min) & " to " & to_string(m_period_max), C_SCOPE);
    check_value(m_high_min = C_SCL_HIGH and m_high_max = C_SCL_HIGH,
                "SCL high within a byte is 2 * C_Q + 2 clocks, measured " & to_string(m_high_min)
                & " to " & to_string(m_high_max), C_SCOPE);
    v_low    := m_low_min;
    v_high   := m_high_min;
    v_period := m_period_min;
    slave_done(90);
    slave_arm(91);
    cmd('1', '0', '0', '1', '0', C_ADDR_R);
    check_value(m_start_setup, C_START_STOP + C_SYNC,
                "repeated START: SCL high before SDA falls", C_SCOPE);
    check_value(m_start_hold, C_START_STOP, "START: SDA low before SCL falls", C_SCOPE);
    v_setup := m_start_setup;
    put('0', '1', '1', '0', '1', x"00");
    put('1', '0', '0', '0', '0', x"00");
    idle;
    get(v_rd, v_nack, v_lat);
    check_value(m_stop_setup, C_START_STOP + C_SYNC, "STOP: SCL high before SDA rises", C_SCOPE);
    check_value(m_bus_free, C_START_STOP + 2, "STOP to START with the next command waiting",
                C_SCOPE);
    slave_done(91);
    cmd('0', '1', '0', '0', '0', x"00");
    check_idle("after the STOP");
    log(C_LOG_HDR, "measured, in clocks (C_Q = " & to_string(C_Q) & "): SCL low "
        & to_string(v_low) & ", SCL high " & to_string(v_high) & ", SCL period "
        & to_string(v_period) & ", START hold " & to_string(m_start_hold)
        & ", repeated START setup " & to_string(v_setup) & ", STOP setup "
        & to_string(m_stop_setup) & ", bus free " & to_string(m_bus_free), C_SCOPE);

    -------------------------------------------------------------------------
    tc_start("TC-10", "a command changed while it waits is taken with its last values", C_SCOPE);
    increment_expected_alerts(ERROR, 1);
    snap;
    slave_arm(100);
    put('1', '0', '0', '1', '0', C_ADDR_W);
    cmd_start <= '0';
    cmd_data  <= x"11";
    wait_num_rising_edges(clk, 20);
    cmd_data <= x"22";
    put('0', '1', '0', '1', '0', x"22");
    idle;
    get(v_rd, v_nack, v_lat);
    check_value(v_nack, '0', "byte acknowledged", C_SCOPE);
    slave_done(100);
    check_bus(1, 1, 19, "write with a changed command");
    check_idle("after the STOP");

    -------------------------------------------------------------------------
    tc_start("TC-11", "cmd_read and cmd_write together read a byte", C_SCOPE);
    increment_expected_alerts(ERROR, 1);
    snap;
    slave_arm(110);
    cmd('1', '0', '0', '1', '0', C_ADDR_R);
    cmd('0', '1', '1', '1', '1', x"00");
    check_value(v_rd, x"C3", "byte read", C_SCOPE);
    check_value(v_nack, '0', "rsp_nack is 0, as for a read", C_SCOPE);
    slave_done(110);
    check_bus(1, 1, 19, "read");
    check_idle("after the STOP");

    -------------------------------------------------------------------------
    tc_start("TC-12", "a command with nothing set is answered and leaves the bus alone",
             C_SCOPE);
    increment_expected_alerts(ERROR, 1);
    snap;
    cmd('0', '0', '0', '0', '0', x"FF");
    check_value(v_lat, 2, "latency", C_SCOPE);
    check_value(v_nack, '0', "rsp_nack", C_SCOPE);
    check_value(v_rd, x"C3", "rsp_data repeats the byte read last", C_SCOPE);
    wait_num_rising_edges(clk, 2 * C_BIT);
    check_bus(0, 0, 0, "empty command");
    check_value(n_rsp - b_rsp, 1, "one response", C_SCOPE);
    check_idle("after the empty command");

    -------------------------------------------------------------------------
    tc_start("TC-13", "STOP with no transaction open is answered and leaves the bus alone",
             C_SCOPE);
    increment_expected_alerts(ERROR, 1);
    snap;
    cmd('0', '1', '0', '0', '0', x"00");
    check_value(v_lat, 2, "latency", C_SCOPE);
    check_value(v_nack, '0', "rsp_nack", C_SCOPE);
    wait_num_rising_edges(clk, 2 * C_BIT);
    check_bus(0, 0, 0, "STOP on an idle bus");
    check_value(n_rsp - b_rsp, 1, "one response", C_SCOPE);
    check_idle("after the STOP command");

    -------------------------------------------------------------------------
    tc_start("TC-14", "START and STOP in one command without a byte make the START only",
             C_SCOPE);
    increment_expected_alerts(ERROR, 1);
    snap;
    cmd('1', '1', '0', '0', '0', x"00");
    check_value(v_lat, 3 * C_Q + 2, "latency is that of a START alone", C_SCOPE);
    wait_num_rising_edges(clk, 2 * C_BIT);
    check_bus(1, 0, 0, "START with STOP");
    wait until falling_edge(clk);
    check_value(scl_x = '0' and sda_x = '0', "transaction left open: SCL and SDA low", C_SCOPE);
    check_value(busy, '0', "block ready", C_SCOPE);
    cmd('0', '1', '0', '0', '0', x"00");
    check_bus(1, 1, 1, "STOP command after it");
    check_idle("after the STOP");

    -------------------------------------------------------------------------
    tc_start("TC-15", "a byte without START on an idle bus is clocked out with no START",
             C_SCOPE);
    increment_expected_alerts(ERROR, 2);
    snap;
    cmd('0', '0', '0', '1', '0', C_ADDR_W);
    check_value(v_nack, '1', "nobody acknowledges", C_SCOPE);
    check_bus(0, 0, 9, "byte without START");
    wait until falling_edge(clk);
    check_value(scl_oe = '1' and sda_oe = '0', "SCL left low by the master, SDA released",
                C_SCOPE);
    check_value(busy, '0', "block ready", C_SCOPE);
    -- The block does not count this as an open transaction: STOP does nothing.
    cmd('0', '1', '0', '0', '0', x"00");
    check_value(v_lat, 2, "STOP command is answered at once", C_SCOPE);
    wait_num_rising_edges(clk, 2 * C_BIT);
    check_bus(0, 0, 9, "STOP command after it");
    check_value(scl_x, '0', "SCL still low", C_SCOPE);
    -- The bus clear command of the ICD frees it.
    cmd('0', '1', '1', '0', '1', x"00");
    check_value(v_rd, x"FF", "bus clear reads an idle bus as FF", C_SCOPE);
    check_bus(0, 1, 19, "bus clear");
    check_idle("after the bus clear");
    snap;
    cmd('0', '1', '1', '0', '1', x"00");
    check_bus(0, 1, 10, "bus clear on an idle bus");
    check_idle("after a bus clear on an idle bus");

    -------------------------------------------------------------------------
    tc_start("TC-16", "rst in a written byte releases the bus at once, the next transfer works",
             C_SCOPE);
    increment_expected_alerts(ERROR, 2);
    snap;
    put('1', '0', '0', '1', '0', C_ADDR_W);
    idle;
    wait_clocks_until("scl_rise", b_rise + 5);
    wait_clocks_until("scl_low_sda_low", 0);
    wait_num_rising_edges(clk, 1);
    reset_pulse("rst with SCL and SDA low");
    wait_num_rising_edges(clk, 12 * C_BIT);
    check_value(n_rsp - b_rsp, 0, "no response to the aborted command", C_SCOPE);
    check_value(n_both - b_both, 1, "SCL and SDA rose in the same clock", C_SCOPE);
    check_bus(1, 0, 6, "aborted byte");
    check_idle("after rst with SCL and SDA low");

    snap;
    put('1', '0', '0', '1', '0', C_ADDR_W);
    idle;
    wait_clocks_until("scl_rise", b_rise + 5);
    wait_clocks_until("scl_high_sda_low", 0);
    wait_num_rising_edges(clk, 1);
    reset_pulse("rst with SCL high and SDA low");
    wait_num_rising_edges(clk, 12 * C_BIT);
    check_value(n_rsp - b_rsp, 0, "no response to the aborted command", C_SCOPE);
    check_bus(1, 1, 5, "aborted byte: SDA rose with SCL high, a STOP on the bus");
    check_idle("after rst with SCL high and SDA low");

    snap;
    slave_arm(160);
    cmd('1', '0', '0', '1', '0', C_ADDR_W);
    check_value(v_nack, '0', "address acknowledged after the resets", C_SCOPE);
    cmd('0', '1', '0', '1', '0', x"5A");
    check_value(v_nack, '0', "data byte acknowledged after the resets", C_SCOPE);
    slave_done(160);
    check_bus(1, 1, 19, "write after the resets");
    check_idle("after the STOP");

    -------------------------------------------------------------------------
    tc_start("TC-17", "a command offered while rst is high is lost without a response", C_SCOPE);
    increment_expected_alerts(ERROR, 1);
    snap;
    rst <= '1';
    wait_num_rising_edges(clk, 2);
    cmd_start <= '1';
    cmd_write <= '1';
    cmd_data  <= C_ADDR_W;
    cmd_valid <= '1';
    wait_num_rising_edges(clk, 2);
    check_value(cmd_ready, '1', "cmd_ready is high in reset", C_SCOPE);
    wait_num_rising_edges(clk, 2);
    idle;
    rst <= '0';
    wait_num_rising_edges(clk, 12 * C_BIT);
    check_value(n_rsp - b_rsp, 0, "no response", C_SCOPE);
    check_bus(0, 0, 0, "command in reset");
    check_idle("after the reset");

    -------------------------------------------------------------------------
    tc_start("TC-18", "SDA left low by a slave after rst is freed by the bus clear command",
             C_SCOPE);
    increment_expected_alerts(ERROR, 1);
    snap;
    slave_arm(180);
    cmd('1', '0', '0', '1', '0', C_ADDR_R);
    put('0', '1', '1', '0', '1', x"00");
    idle;
    wait_clocks_until("scl_rise", b_rise + 12);
    wait_clocks_until("scl_high", 0);
    wait_num_rising_edges(clk, 1);
    reset_pulse("rst in a byte read");
    wait_num_rising_edges(clk, 12 * C_BIT);
    wait until falling_edge(clk);
    check_value(scl_x, '1', "SCL high after rst", C_SCOPE);
    check_value(sda_x, '0', "SDA held low by the slave after rst", C_SCOPE);
    check_value(cmd_ready, '1', "block ready although the bus is not free", C_SCOPE);
    check_bus(1, 0, 12, "aborted read");
    snap;
    cmd('0', '1', '1', '0', '1', x"00");
    log(C_LOG_HDR, "bus clear read " & to_hstring(v_rd), C_SCOPE);
    check_bus(0, 1, 10, "bus clear");
    slave_done(180);
    check_idle("after the bus clear");
    snap;
    slave_arm(181);
    cmd('1', '0', '0', '1', '0', C_ADDR_W);
    check_value(v_nack, '0', "address acknowledged after the bus clear", C_SCOPE);
    cmd('0', '1', '0', '1', '0', x"77");
    slave_done(181);
    check_bus(1, 1, 19, "write after the bus clear");
    check_idle("after the STOP");

    -------------------------------------------------------------------------
    tc_start("TC-19", "with SDA held low a START is not seen and the transfer is lost", C_SCOPE);
    increment_expected_alerts(ERROR, 1);
    snap;
    slave_arm(190);
    cmd('1', '0', '0', '1', '0', C_ADDR_R);
    put('0', '1', '1', '0', '1', x"00");
    idle;
    wait_clocks_until("scl_rise", b_rise + 12);
    wait_clocks_until("scl_high", 0);
    wait_num_rising_edges(clk, 1);
    reset_pulse("rst in a byte read");
    wait_num_rising_edges(clk, 12 * C_BIT);
    wait until falling_edge(clk);
    check_value(sda_x, '0', "SDA held low by the slave after rst", C_SCOPE);
    snap;
    cmd('1', '0', '0', '1', '0', C_ADDR_W);
    check_bus(0, 0, 9, "address byte with SDA held low: no START on the bus");
    check_value(v_nack, '1', "the address is reported as not acknowledged", C_SCOPE);
    cmd('0', '1', '0', '0', '0', x"00");
    check_bus(0, 1, 10, "STOP after it");
    slave_done(190);
    check_idle("after the STOP");
    snap;
    slave_arm(191);
    cmd('1', '0', '0', '1', '0', C_ADDR_W);
    check_value(v_nack, '0', "address acknowledged in the second attempt", C_SCOPE);
    cmd('0', '1', '0', '1', '0', x"88");
    slave_done(191);
    check_bus(1, 1, 19, "write in the second attempt");
    check_idle("after the STOP");

    -------------------------------------------------------------------------
    tc_start("TC-20", "SCL held low without end keeps the block busy until rst", C_SCOPE);
    increment_expected_alerts(ERROR, 1);
    snap;
    put('1', '0', '0', '1', '0', C_ADDR_W);
    idle;
    wait_clocks_until("scl_rise", b_rise + 4);
    wait_clocks_until("scl_pulled_low", 0);
    hold_scl <= true;
    wait_num_rising_edges(clk, 60 * C_BIT);
    check_value(busy, '1', "busy while SCL is held low", C_SCOPE);
    check_value(scl_oe, '0', "the master has released SCL and waits", C_SCOPE);
    check_value(n_rsp - b_rsp, 0, "no response while SCL is held low", C_SCOPE);
    check_bus(1, 0, 4, "held byte");
    hold_scl <= false;
    get(v_rd, v_nack, v_lat);
    check_value(v_nack, '1', "the byte is finished after the release", C_SCOPE);
    check_bus(1, 0, 9, "byte after the release");
    cmd('0', '1', '0', '0', '0', x"00");
    check_idle("after the STOP");

    snap;
    put('1', '0', '0', '1', '0', C_ADDR_W);
    idle;
    wait_clocks_until("scl_rise", b_rise + 4);
    wait_clocks_until("scl_pulled_low", 0);
    hold_scl <= true;
    wait_num_rising_edges(clk, 20 * C_BIT);
    check_value(busy, '1', "busy while SCL is held low", C_SCOPE);
    reset_pulse("rst while SCL is held low");
    wait_num_rising_edges(clk, 4 * C_BIT);
    wait until falling_edge(clk);
    check_value(scl_x, '0', "SCL still low: held by the slave", C_SCOPE);
    check_value(cmd_ready, '1', "block ready although the bus is not free", C_SCOPE);
    check_value(n_rsp - b_rsp, 0, "no response to the aborted command", C_SCOPE);
    hold_scl <= false;
    wait_num_rising_edges(clk, 4 * C_BIT);
    check_idle("after the slave released SCL");
    snap;
    cmd('1', '0', '0', '1', '0', C_ADDR_W);
    check_value(v_nack, '1', "address byte to an absent slave", C_SCOPE);
    cmd('0', '1', '0', '0', '0', x"00");
    check_bus(1, 1, 10, "transfer after the reset");
    check_idle("after the STOP");

    wait_num_rising_edges(clk, 4 * C_BIT);
    report_final(C_SCOPE);
    std.env.stop;
    wait;
  end process p_main;

end architecture sim;
