-- I2C: every design and BFM against something it did not write.
--   bus A   i2c_master  <->  slave BFM   (write, read, repeated START, address NACK, clock stretching)
--   bus B   master BFM  <->  i2c_slave   (register file: pointer byte, write, read back, wrong address)
--   bus C   i2c_master  <->  i2c_slave   (both RTL)
--   bus D   master BFM  <->  slave BFM   (incl. stretching and address NACK)
-- Run by `make check'.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.bfm_util_pkg.all;

-- A small driver for the i2c_master command interface: whole transactions
-- (START, address, bytes, STOP) built from single-byte commands.
package tb_i2c_pkg is

  type t_mcmd is record
    valid : std_logic;
    start : std_logic;
    stop  : std_logic;
    read  : std_logic;
    write : std_logic;
    nack  : std_logic;
    data  : std_logic_vector(7 downto 0);
  end record t_mcmd;

  constant C_MCMD_INIT : t_mcmd := ('0', '0', '0', '0', '0', '0', (others => '0'));

  type t_mrsp is record
    ready : std_logic;
    valid : std_logic;
    nack  : std_logic;
    busy  : std_logic;
    data  : std_logic_vector(7 downto 0);
  end record t_mrsp;

  procedure i2c_dut_byte (
    signal   clk     : in  std_logic;
    signal   cmd     : out t_mcmd;
    signal   rsp     : in  t_mrsp;
    constant start   : in  std_logic;
    constant stop    : in  std_logic;
    constant read    : in  std_logic;
    constant write   : in  std_logic;
    constant nack    : in  std_logic;
    constant data    : in  std_logic_vector(7 downto 0);
    variable rd      : out std_logic_vector(7 downto 0);
    variable nacked  : out std_logic);

  procedure i2c_dut_write (
    constant addr       : in  std_logic_vector(6 downto 0);
    constant data       : in  t_slv_array;
    constant stop       : in  boolean;
    signal   clk        : in  std_logic;
    signal   cmd        : out t_mcmd;
    signal   rsp        : in  t_mrsp;
    variable addr_nack  : out boolean;
    variable data_nack  : out boolean);

  procedure i2c_dut_read (
    constant addr       : in  std_logic_vector(6 downto 0);
    variable data       : out t_slv_array;
    constant stop       : in  boolean;
    signal   clk        : in  std_logic;
    signal   cmd        : out t_mcmd;
    signal   rsp        : in  t_mrsp;
    variable addr_nack  : out boolean);

end package tb_i2c_pkg;

package body tb_i2c_pkg is

  function to_sl (b : boolean) return std_logic is
  begin
    if b then
      return '1';
    else
      return '0';
    end if;
  end function to_sl;

  procedure i2c_dut_byte (
    signal   clk     : in  std_logic;
    signal   cmd     : out t_mcmd;
    signal   rsp     : in  t_mrsp;
    constant start   : in  std_logic;
    constant stop    : in  std_logic;
    constant read    : in  std_logic;
    constant write   : in  std_logic;
    constant nack    : in  std_logic;
    constant data    : in  std_logic_vector(7 downto 0);
    variable rd      : out std_logic_vector(7 downto 0);
    variable nacked  : out std_logic) is
  begin
    cmd <= ('1', start, stop, read, write, nack, data);
    loop
      wait until rising_edge(clk);
      exit when rsp.ready = '1';                 -- taken at this edge
    end loop;
    cmd.valid <= '0';
    loop
      wait until rising_edge(clk);
      exit when rsp.valid = '1';
    end loop;
    rd     := rsp.data;
    nacked := rsp.nack;
  end procedure i2c_dut_byte;

  procedure i2c_dut_write (
    constant addr       : in  std_logic_vector(6 downto 0);
    constant data       : in  t_slv_array;
    constant stop       : in  boolean;
    signal   clk        : in  std_logic;
    signal   cmd        : out t_mcmd;
    signal   rsp        : in  t_mrsp;
    variable addr_nack  : out boolean;
    variable data_nack  : out boolean) is
    variable v_rd   : std_logic_vector(7 downto 0);
    variable v_nack : std_logic;
    variable v_byte : std_logic_vector(7 downto 0);
  begin
    addr_nack := false;
    data_nack := false;
    i2c_dut_byte(clk, cmd, rsp, '1', '0', '0', '1', '0', addr & '0', v_rd, v_nack);
    if v_nack = '1' then
      addr_nack := true;
      i2c_dut_byte(clk, cmd, rsp, '0', '1', '0', '0', '0', x"00", v_rd, v_nack);   -- STOP only
      return;
    end if;
    for n in data'low to data'high loop
      v_byte := data(n);
      i2c_dut_byte(clk, cmd, rsp, '0', to_sl(stop and n = data'high), '0', '1', '0',
                   v_byte, v_rd, v_nack);
      if v_nack = '1' then
        data_nack := true;
      end if;
    end loop;
  end procedure i2c_dut_write;

  procedure i2c_dut_read (
    constant addr       : in  std_logic_vector(6 downto 0);
    variable data       : out t_slv_array;
    constant stop       : in  boolean;
    signal   clk        : in  std_logic;
    signal   cmd        : out t_mcmd;
    signal   rsp        : in  t_mrsp;
    variable addr_nack  : out boolean) is
    variable v_rd   : std_logic_vector(7 downto 0);
    variable v_nack : std_logic;
  begin
    addr_nack := false;
    for n in data'low to data'high loop
      data(n) := (data(n)'range => 'X');
    end loop;
    i2c_dut_byte(clk, cmd, rsp, '1', '0', '0', '1', '0', addr & '1', v_rd, v_nack);
    if v_nack = '1' then
      addr_nack := true;
      i2c_dut_byte(clk, cmd, rsp, '0', '1', '0', '0', '0', x"00", v_rd, v_nack);   -- STOP only
      return;
    end if;
    for n in data'low to data'high loop
      i2c_dut_byte(clk, cmd, rsp, '0', to_sl(stop and n = data'high), '1', '0',
                   to_sl(n = data'high), x"00", v_rd, v_nack);   -- NACK the last byte
      data(n) := v_rd;
    end loop;
  end procedure i2c_dut_read;

end package body tb_i2c_pkg;

---------------------------------------------------------------------------
-- i2c_slave with a 256-byte register file: the first byte after a write
-- address is the pointer, further bytes are stored (pointer increments),
-- reads return memory from the pointer on.
---------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_i2c_mem_slave is
  generic (
    G_ADDR : std_logic_vector(6 downto 0) := "1010000"
  );
  port (
    clk : in    std_logic;
    rst : in    std_logic;
    scl : in    std_logic;                       -- the slave only reads SCL
    sda : inout std_logic;
    starts : out natural := 0;                   -- START and repeated START seen
    stops  : out natural := 0                    -- STOP seen
  );
end entity tb_i2c_mem_slave;

architecture sim of tb_i2c_mem_slave is

  signal sda_oe     : std_logic;
  signal start_evt  : std_logic;
  signal stop_evt   : std_logic;
  signal addr_match : std_logic;
  signal is_read    : std_logic;
  signal rx_data    : std_logic_vector(7 downto 0);
  signal rx_valid   : std_logic;
  signal tx_data    : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_req     : std_logic;

  type t_mem is array (0 to 255) of std_logic_vector(7 downto 0);

begin

  sda <= '0' when sda_oe = '1' else 'Z';

  u_slave : entity work.i2c_slave
    generic map (G_ADDR => G_ADDR)
    port map (clk => clk, rst => rst, scl_i => to_x01(scl), sda_i => to_x01(sda),
              sda_oe => sda_oe, start_evt => start_evt, stop_evt => stop_evt,
              addr_match => addr_match, is_read => is_read, rx_data => rx_data,
              rx_valid => rx_valid, tx_data => tx_data, tx_req => tx_req);

  p_user : process (clk)
    variable mem   : t_mem := (others => (others => '0'));
    variable ptr   : natural range 0 to 255 := 0;
    variable first : boolean := true;
    variable n_start : natural := 0;
    variable n_stop  : natural := 0;
  begin
    if rising_edge(clk) then
      if start_evt = '1' then
        n_start := n_start + 1;
        starts  <= n_start;
      end if;
      if stop_evt = '1' then
        n_stop := n_stop + 1;
        stops  <= n_stop;
      end if;
      if addr_match = '1' and is_read = '0' then
        first := true;                           -- the next byte is the pointer
      end if;
      if rx_valid = '1' then
        if first then
          ptr   := to_integer(unsigned(rx_data));
          first := false;
        else
          mem(ptr) := rx_data;
          ptr      := (ptr + 1) mod 256;
        end if;
      end if;
      if tx_req = '1' then
        tx_data <= mem(ptr);
        ptr     := (ptr + 1) mod 256;
      end if;
    end if;
  end process p_user;

end architecture sim;

---------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.bfm_util_pkg.all;
use work.bfm_i2c_pkg.all;
use work.tb_i2c_pkg.all;

entity tb_i2c is
end entity tb_i2c;

architecture sim of tb_i2c is

  constant C_PERIOD : time   := 10 ns;
  constant C_SCOPE  : string := "tb_i2c";
  constant C_ADDR   : t_i2c_addr := "1010000";        -- 0x50

  -- 3200 / 100 = 32 clocks per SCL period, 8 per quarter: 320 ns
  constant C_GEN_CLK_HZ : positive := 3200;
  constant C_GEN_SCL_HZ : positive := 100;

  constant C_CFG : t_i2c_bfm_config :=
    (scl_period => 320 ns, stretch => 0 ns, addr_ack => true, timeout => 100 us);
  constant C_CFG_STRETCH : t_i2c_bfm_config :=
    (scl_period => 320 ns, stretch => 1 us, addr_ack => true, timeout => 100 us);
  constant C_CFG_NACK : t_i2c_bfm_config :=
    (scl_period => 320 ns, stretch => 0 ns, addr_ack => false, timeout => 100 us);

  signal clk  : std_logic := '0';
  signal rst  : std_logic := '1';
  signal stop : boolean   := false;
  signal done : std_logic_vector(0 to 5) := (others => '0');

  -- the four buses, each with a weak pull-up
  signal a_scl, a_sda : std_logic := 'Z';
  signal b_scl, b_sda : std_logic := 'Z';
  signal c_scl, c_sda : std_logic := 'Z';
  signal d_scl, d_sda : std_logic := 'Z';

  -- i2c_master on bus A and C
  signal a_cmd : t_mcmd := C_MCMD_INIT;
  signal a_rsp : t_mrsp;
  signal a_scl_oe, a_sda_oe : std_logic;
  signal c_cmd : t_mcmd := C_MCMD_INIT;
  signal c_rsp : t_mrsp;
  signal c_scl_oe, c_sda_oe : std_logic;

  signal b_starts, b_stops, c_starts, c_stops : natural;

  -- longest time SCL was held low on the buses with a stretching slave
  signal a_max_low, d_max_low : time := 0 ns;

begin

  clk <= not clk after C_PERIOD / 2 when not stop;

  a_scl <= 'H';  a_sda <= 'H';
  b_scl <= 'H';  b_sda <= 'H';
  c_scl <= 'H';  c_sda <= 'H';
  d_scl <= 'H';  d_sda <= 'H';

  p_reset : process
  begin
    rst <= '1';
    bfm_wait_cycles(5, clk);
    rst <= '0';
    wait;
  end process p_reset;

  ---------------------------------------------------------------------------
  -- Bus A: i2c_master <-> slave BFM
  ---------------------------------------------------------------------------
  u_master_a : entity work.i2c_master
    generic map (G_CLK_HZ => C_GEN_CLK_HZ, G_SCL_HZ => C_GEN_SCL_HZ)
    port map (clk => clk, rst => rst,
              cmd_valid => a_cmd.valid, cmd_ready => a_rsp.ready,
              cmd_start => a_cmd.start, cmd_stop => a_cmd.stop,
              cmd_read => a_cmd.read, cmd_write => a_cmd.write,
              cmd_nack => a_cmd.nack, cmd_data => a_cmd.data,
              rsp_valid => a_rsp.valid, rsp_data => a_rsp.data,
              rsp_nack => a_rsp.nack, busy => a_rsp.busy,
              scl_i => to_x01(a_scl), scl_oe => a_scl_oe,
              sda_i => to_x01(a_sda), sda_oe => a_sda_oe);

  a_scl <= '0' when a_scl_oe = '1' else 'Z';
  a_sda <= '0' when a_sda_oe = '1' else 'Z';

  p_a_master : process
    variable v_rd2      : t_slv_array(0 to 1)(7 downto 0);
    variable v_rd1      : t_slv_array(0 to 0)(7 downto 0);
    variable v_addr_nack : boolean;
    variable v_data_nack : boolean;
  begin
    wait until rst = '0';
    wait for 200 ns;

    i2c_dut_write(C_ADDR, (x"12", x"34"), true, clk, a_cmd, a_rsp, v_addr_nack, v_data_nack);
    bfm_check(not v_addr_nack and not v_data_nack, "A T1: write acknowledged", C_SCOPE);

    i2c_dut_read(C_ADDR, v_rd2, true, clk, a_cmd, a_rsp, v_addr_nack);
    bfm_check(not v_addr_nack, "A T2: read address acknowledged", C_SCOPE);
    bfm_check_value(v_rd2(0), x"9A", "A T2: first byte read", C_SCOPE);
    bfm_check_value(v_rd2(1), x"C3", "A T2: second byte read", C_SCOPE);

    -- pointer write, repeated START, read
    i2c_dut_write(C_ADDR, (0 => x"07"), false, clk, a_cmd, a_rsp, v_addr_nack, v_data_nack);
    i2c_dut_read(C_ADDR, v_rd1, true, clk, a_cmd, a_rsp, v_addr_nack);
    bfm_check_value(v_rd1(0), x"5E", "A T3: byte read after a repeated START", C_SCOPE);

    -- nobody answers: the master must see the NACK and release the bus
    i2c_dut_write(C_ADDR, (0 => x"55"), true, clk, a_cmd, a_rsp, v_addr_nack, v_data_nack);
    bfm_check(v_addr_nack, "A T4: NACKed address is reported", C_SCOPE);
    bfm_check(a_rsp.busy = '0', "A T4: master idle again", C_SCOPE);

    -- slave stretches the clock after every byte
    i2c_dut_write(C_ADDR, (x"A5", x"5A", x"C3"), true, clk, a_cmd, a_rsp, v_addr_nack, v_data_nack);
    bfm_check(not v_addr_nack and not v_data_nack, "A T5: write with clock stretching", C_SCOPE);
    i2c_dut_read(C_ADDR, v_rd2, true, clk, a_cmd, a_rsp, v_addr_nack);
    bfm_check_value(v_rd2(0), x"3C", "A T5: first byte read with clock stretching", C_SCOPE);
    bfm_check_value(v_rd2(1), x"81", "A T5: second byte read with clock stretching", C_SCOPE);

    done(0) <= '1';
    wait;
  end process p_a_master;

  p_a_slave : process
    variable v_rx : t_slv_array(0 to 0)(7 downto 0);
  begin
    i2c_slave_check(C_ADDR, (x"12", x"34"), "A T1", a_scl, a_sda, C_SCOPE, C_CFG);
    i2c_slave_transmit(C_ADDR, (x"9A", x"C3"), "A T2", a_scl, a_sda, C_SCOPE, C_CFG);
    i2c_slave_check(C_ADDR, (0 => x"07"), "A T3 pointer", a_scl, a_sda, C_SCOPE, C_CFG);
    i2c_slave_transmit(C_ADDR, (0 => x"5E"), "A T3 data", a_scl, a_sda, C_SCOPE, C_CFG);
    i2c_slave_receive(C_ADDR, v_rx, "A T4", a_scl, a_sda, C_SCOPE, C_CFG_NACK);
    i2c_slave_check(C_ADDR, (x"A5", x"5A", x"C3"), "A T5 write", a_scl, a_sda, C_SCOPE, C_CFG_STRETCH);
    i2c_slave_transmit(C_ADDR, (x"3C", x"81"), "A T5 read", a_scl, a_sda, C_SCOPE, C_CFG_STRETCH);
    done(1) <= '1';
    wait;
  end process p_a_slave;

  ---------------------------------------------------------------------------
  -- Bus B: master BFM <-> i2c_slave with a register file
  ---------------------------------------------------------------------------
  u_slave_b : entity work.tb_i2c_mem_slave
    port map (clk => clk, rst => rst, scl => b_scl, sda => b_sda,
              starts => b_starts, stops => b_stops);

  p_b_master : process
  begin
    wait until rst = '0';
    wait for 500 ns;

    i2c_master_transmit(C_ADDR, (x"10", x"A1", x"B2", x"C3"), "B write 3 bytes at 0x10",
                        b_scl, b_sda, scope => C_SCOPE, config => C_CFG);
    -- pointer, then a repeated START and a read
    i2c_master_transmit(C_ADDR, (0 => x"10"), "B set pointer 0x10", b_scl, b_sda,
                        send_stop => false, scope => C_SCOPE, config => C_CFG);
    i2c_master_check(C_ADDR, (x"A1", x"B2", x"C3"), "B read back 3 bytes", b_scl, b_sda,
                     scope => C_SCOPE, config => C_CFG);

    -- nobody at this address
    i2c_master_transmit("1010001", (0 => x"00"), "B wrong address", b_scl, b_sda,
                        addr_ack_expected => false, scope => C_SCOPE, config => C_CFG);

    -- a NACKed address ends with a STOP even when the caller asked for none
    i2c_master_transmit("1010001", (0 => x"00"), "B wrong address, no STOP requested", b_scl, b_sda,
                        addr_ack_expected => false, send_stop => false,
                        scope => C_SCOPE, config => C_CFG);

    -- another region, then the first one again
    i2c_master_transmit(C_ADDR, (x"F0", x"01", x"02"), "B write 2 bytes at 0xF0",
                        b_scl, b_sda, scope => C_SCOPE, config => C_CFG);
    i2c_master_transmit(C_ADDR, (0 => x"F0"), "B set pointer 0xF0", b_scl, b_sda,
                        send_stop => false, scope => C_SCOPE, config => C_CFG);
    i2c_master_check(C_ADDR, (x"01", x"02"), "B read back at 0xF0", b_scl, b_sda,
                     scope => C_SCOPE, config => C_CFG);
    i2c_master_transmit(C_ADDR, (0 => x"11"), "B set pointer 0x11", b_scl, b_sda,
                        send_stop => false, scope => C_SCOPE, config => C_CFG);
    i2c_master_check(C_ADDR, (x"B2", x"C3"), "B 0x10 region unchanged", b_scl, b_sda,
                     scope => C_SCOPE, config => C_CFG);
    wait for 1 us;
    bfm_check(b_starts = 10, "B: slave saw 10 START conditions, got " & integer'image(b_starts), C_SCOPE);
    bfm_check(b_stops = 7, "B: slave saw 7 STOP conditions, got " & integer'image(b_stops), C_SCOPE);
    done(2) <= '1';
    wait;
  end process p_b_master;

  ---------------------------------------------------------------------------
  -- Bus C: i2c_master <-> i2c_slave, both RTL
  ---------------------------------------------------------------------------
  u_master_c : entity work.i2c_master
    generic map (G_CLK_HZ => C_GEN_CLK_HZ, G_SCL_HZ => C_GEN_SCL_HZ)
    port map (clk => clk, rst => rst,
              cmd_valid => c_cmd.valid, cmd_ready => c_rsp.ready,
              cmd_start => c_cmd.start, cmd_stop => c_cmd.stop,
              cmd_read => c_cmd.read, cmd_write => c_cmd.write,
              cmd_nack => c_cmd.nack, cmd_data => c_cmd.data,
              rsp_valid => c_rsp.valid, rsp_data => c_rsp.data,
              rsp_nack => c_rsp.nack, busy => c_rsp.busy,
              scl_i => to_x01(c_scl), scl_oe => c_scl_oe,
              sda_i => to_x01(c_sda), sda_oe => c_sda_oe);

  c_scl <= '0' when c_scl_oe = '1' else 'Z';
  c_sda <= '0' when c_sda_oe = '1' else 'Z';

  u_slave_c : entity work.tb_i2c_mem_slave
    port map (clk => clk, rst => rst, scl => c_scl, sda => c_sda,
              starts => c_starts, stops => c_stops);

  p_c_master : process
    variable v_rd        : t_slv_array(0 to 3)(7 downto 0);
    variable v_addr_nack : boolean;
    variable v_data_nack : boolean;
    variable v_byte      : std_logic_vector(7 downto 0);
    variable v_nack      : std_logic;
  begin
    wait until rst = '0';
    wait for 300 ns;

    i2c_dut_write(C_ADDR, (x"20", x"11", x"22", x"33", x"44"), true, clk, c_cmd, c_rsp,
                  v_addr_nack, v_data_nack);
    bfm_check(not v_addr_nack and not v_data_nack, "C: write acknowledged", C_SCOPE);

    i2c_dut_write(C_ADDR, (0 => x"20"), false, clk, c_cmd, c_rsp, v_addr_nack, v_data_nack);
    i2c_dut_read(C_ADDR, v_rd, true, clk, c_cmd, c_rsp, v_addr_nack);
    bfm_check(not v_addr_nack, "C: read address acknowledged", C_SCOPE);
    bfm_check_value(v_rd(0), x"11", "C: byte 0 read back", C_SCOPE);
    bfm_check_value(v_rd(1), x"22", "C: byte 1 read back", C_SCOPE);
    bfm_check_value(v_rd(2), x"33", "C: byte 2 read back", C_SCOPE);
    bfm_check_value(v_rd(3), x"44", "C: byte 3 read back", C_SCOPE);

    i2c_dut_write("1010001", (0 => x"00"), true, clk, c_cmd, c_rsp, v_addr_nack, v_data_nack);
    bfm_check(v_addr_nack, "C: wrong address is NACKed", C_SCOPE);

    -- the bus works again after the NACK
    i2c_dut_write(C_ADDR, (0 => x"22"), false, clk, c_cmd, c_rsp, v_addr_nack, v_data_nack);
    i2c_dut_read(C_ADDR, v_rd, true, clk, c_cmd, c_rsp, v_addr_nack);
    bfm_check_value(v_rd(0), x"33", "C: read after the NACK", C_SCOPE);

    -- a command with both read and write set is a read, and it must not
    -- report a NACK of the master's own acknowledge bit
    i2c_dut_write(C_ADDR, (0 => x"22"), false, clk, c_cmd, c_rsp, v_addr_nack, v_data_nack);
    i2c_dut_byte(clk, c_cmd, c_rsp, '1', '0', '0', '1', '0', C_ADDR & '1', v_byte, v_nack);
    i2c_dut_byte(clk, c_cmd, c_rsp, '0', '1', '1', '1', '1', x"00", v_byte, v_nack);
    bfm_check_value(v_byte, x"33", "C: read wins over write", C_SCOPE);
    bfm_check_value(v_nack, '0', "C: no NACK reported for a read", C_SCOPE);

    wait for 1 us;
    bfm_check(c_starts = 8, "C: slave saw 8 START conditions, got " & integer'image(c_starts), C_SCOPE);
    bfm_check(c_stops = 5, "C: slave saw 5 STOP conditions, got " & integer'image(c_stops), C_SCOPE);
    done(3) <= '1';
    wait;
  end process p_c_master;

  ---------------------------------------------------------------------------
  -- Bus D: master BFM <-> slave BFM
  ---------------------------------------------------------------------------
  p_d_master : process
  begin
    wait until rst = '0';
    wait for 200 ns;
    i2c_master_transmit(C_ADDR, (x"12", x"34", x"56"), "D T1", d_scl, d_sda,
                        scope => C_SCOPE, config => C_CFG);
    i2c_master_check(C_ADDR, (x"9A", x"C3"), "D T2", d_scl, d_sda,
                     scope => C_SCOPE, config => C_CFG);
    i2c_master_transmit(C_ADDR, (0 => x"07"), "D T3 pointer", d_scl, d_sda,
                        send_stop => false, scope => C_SCOPE, config => C_CFG);
    i2c_master_check(C_ADDR, (0 => x"5E"), "D T3 data", d_scl, d_sda,
                     scope => C_SCOPE, config => C_CFG);
    i2c_master_transmit(C_ADDR, (0 => x"00"), "D T4 unanswered address", d_scl, d_sda,
                        addr_ack_expected => false, scope => C_SCOPE, config => C_CFG);
    i2c_master_transmit(C_ADDR, (x"A5", x"5A"), "D T5 stretched", d_scl, d_sda,
                        scope => C_SCOPE, config => C_CFG);
    i2c_master_check(C_ADDR, (x"3C", x"81", x"E7"), "D T5 stretched read", d_scl, d_sda,
                     scope => C_SCOPE, config => C_CFG);
    done(4) <= '1';
    wait;
  end process p_d_master;

  p_d_slave : process
    variable v_rx : t_slv_array(0 to 0)(7 downto 0);
  begin
    i2c_slave_check(C_ADDR, (x"12", x"34", x"56"), "D T1", d_scl, d_sda, C_SCOPE, C_CFG);
    i2c_slave_transmit(C_ADDR, (x"9A", x"C3"), "D T2", d_scl, d_sda, C_SCOPE, C_CFG);
    i2c_slave_check(C_ADDR, (0 => x"07"), "D T3 pointer", d_scl, d_sda, C_SCOPE, C_CFG);
    i2c_slave_transmit(C_ADDR, (0 => x"5E"), "D T3 data", d_scl, d_sda, C_SCOPE, C_CFG);
    i2c_slave_receive(C_ADDR, v_rx, "D T4", d_scl, d_sda, C_SCOPE, C_CFG_NACK);
    i2c_slave_check(C_ADDR, (x"A5", x"5A"), "D T5 write", d_scl, d_sda, C_SCOPE, C_CFG_STRETCH);
    i2c_slave_transmit(C_ADDR, (x"3C", x"81", x"E7"), "D T5 read", d_scl, d_sda, C_SCOPE, C_CFG_STRETCH);
    done(5) <= '1';
    wait;
  end process p_d_slave;

  ---------------------------------------------------------------------------
  -- SCL low time: the stretching slave must really have held the clock
  ---------------------------------------------------------------------------
  p_a_scl_low : process
    variable v_fall : time := 0 ns;
  begin
    wait on a_scl;
    if to_x01(a_scl) = '0' then
      v_fall := now;
    elsif to_x01(a_scl) = '1' and to_x01(a_scl'last_value) = '0' and now - v_fall > a_max_low then
      a_max_low <= now - v_fall;
    end if;
  end process p_a_scl_low;

  p_d_scl_low : process
    variable v_fall : time := 0 ns;
  begin
    wait on d_scl;
    if to_x01(d_scl) = '0' then
      v_fall := now;
    elsif to_x01(d_scl) = '1' and to_x01(d_scl'last_value) = '0' and now - v_fall > d_max_low then
      d_max_low <= now - v_fall;
    end if;
  end process p_d_scl_low;

  ---------------------------------------------------------------------------
  -- Verdict
  ---------------------------------------------------------------------------
  p_verdict : process
  begin
    wait until done = (done'range => '1') for 3 ms;
    if done /= (done'range => '1') then
      bfm_alert(ERROR, "timeout, blocks not finished: " & to_string(done), C_SCOPE);
    end if;
    wait for 500 ns;
    bfm_check(a_max_low >= C_CFG_STRETCH.stretch, "A: SCL was held low at least " & time'image(C_CFG_STRETCH.stretch)
              & ", longest " & time'image(a_max_low), C_SCOPE);
    bfm_check(d_max_low >= C_CFG_STRETCH.stretch, "D: SCL was held low at least " & time'image(C_CFG_STRETCH.stretch)
              & ", longest " & time'image(d_max_low), C_SCOPE);
    bfm_report_final(C_SCOPE);
    stop <= true;
    wait;
  end process p_verdict;

end architecture sim;
