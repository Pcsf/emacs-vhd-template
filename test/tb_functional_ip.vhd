-- Functional checks of the interface and CDC templates: debounce,
-- pulse_sync, fifo_async, pwm, lfsr, shift_reg, rom_lut, mac_dsp, UART
-- (loopback), SPI (loopback), axis_skid, axi_lite_regs, bus_sync_handshake.
-- Run by `make check'.

-- One direction of a handshake bus synchronizer under test: the source keeps
-- offering new words (and changes src_data while a transfer is in flight),
-- the destination must receive every word once, in order, as a one-clock pulse.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_hs_bench is
  port (
    src_clk : in  std_logic;
    dst_clk : in  std_logic;
    rst     : in  std_logic;
    done    : out std_logic := '0';
    fail    : out std_logic := '0'
  );
end entity tb_hs_bench;

architecture sim of tb_hs_bench is

  constant C_WORDS : natural := 30;

  signal data_in   : std_logic_vector(15 downto 0) := (others => '0');
  signal send      : std_logic := '0';
  signal ready     : std_logic;
  signal dst_data  : std_logic_vector(15 downto 0);
  signal dst_valid : std_logic;

  function word (i : natural) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned((i * 2731 + 12345) mod 65536, 16));
  end function word;

begin

  u_hs : entity work.bus_sync_handshake
    generic map (G_WIDTH => 16)
    port map (src_clk => src_clk, src_rst => rst, src_data => data_in,
              src_send => send, src_ready => ready,
              dst_clk => dst_clk, dst_rst => rst, dst_data => dst_data,
              dst_valid => dst_valid);

  p_src : process
    variable i : natural := 1;
  begin
    wait until rst = '0';
    wait until rising_edge(src_clk);
    while i <= C_WORDS loop
      data_in <= word(i);
      send    <= '1';
      wait until rising_edge(src_clk);
      if ready = '1' then                   -- accepted at this edge
        i := i + 1;
      end if;
    end loop;
    send <= '0';
    wait;
  end process p_src;

  p_dst : process (dst_clk)
    variable expected   : natural := 1;
    variable prev_valid : std_logic := '0';
  begin
    if rising_edge(dst_clk) then
      if dst_valid = '1' then
        if prev_valid = '1' then
          fail <= '1';
          report "CHECK FAILED: dst_valid is longer than one clock" severity error;
        end if;
        if expected > C_WORDS then
          fail <= '1';
          report "CHECK FAILED: more words received than sent" severity error;
        elsif dst_data /= word(expected) then
          fail <= '1';
          report "CHECK FAILED: word " & integer'image(expected)
                 & " is wrong or out of order" severity error;
        end if;
        expected := expected + 1;
        if expected = C_WORDS + 1 then
          done <= '1';
        end if;
      end if;
      prev_valid := dst_valid;
    end if;
  end process p_dst;

end architecture sim;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_functional_ip is
end entity tb_functional_ip;

architecture sim of tb_functional_ip is

  constant C_PERIOD  : time := 10 ns;
  constant C_PERIOD2 : time := 13 ns;   -- second, unrelated clock

  signal clk  : std_logic := '0';
  signal clk2 : std_logic := '0';
  signal stop : boolean   := false;

  signal rst  : std_logic := '1';
  signal fail : std_logic_vector(0 to 14) := (others => '0');
  signal done : std_logic_vector(0 to 14) := (others => '0');

  procedure expect (signal flag : out std_logic;
                    condition   : boolean;
                    message     : string) is
  begin
    if not condition then
      flag <= '1';
      report "CHECK FAILED: " & message severity error;
    end if;
  end procedure expect;

  -- debounce
  signal db_in, db_out : std_logic := '0';

  -- pulse_sync
  signal ps_in, ps_out : std_logic := '0';
  signal ps_count      : natural := 0;

  -- fifo_async
  signal fa_wr_rst, fa_rd_rst : std_logic := '1';
  signal fa_wr_en, fa_full    : std_logic := '0';
  signal fa_wr_data           : std_logic_vector(7 downto 0) := (others => '0');
  signal fa_rd_en, fa_empty, fa_rd_valid : std_logic := '0';
  signal fa_rd_data           : std_logic_vector(7 downto 0);
  signal fa_saw_full          : std_logic := '0';

  -- pwm
  signal pwm_duty : unsigned(3 downto 0) := to_unsigned(4, 4);
  signal pwm_out  : std_logic;

  -- lfsr
  signal lfsr_en : std_logic := '0';
  signal lfsr_q  : std_logic_vector(7 downto 0);

  -- shift_reg
  signal sr_din, sr_dout : std_logic_vector(7 downto 0) := (others => '0');

  -- rom_lut
  signal rom_addr : unsigned(3 downto 0) := (others => '0');
  signal rom_data : std_logic_vector(7 downto 0);

  -- mac_dsp
  signal mac_clr : std_logic := '0';
  signal mac_a, mac_b : signed(7 downto 0) := (others => '0');
  signal mac_acc : signed(23 downto 0);

  -- uart
  signal u_data, u_rx_data : std_logic_vector(7 downto 0) := (others => '0');
  signal u_valid, u_ready, u_line, u_rx_valid, u_frame_err : std_logic := '0';

  -- uart with baud rate error
  signal sk_line : std_logic := '1';
  signal sk_rx_data : std_logic_vector(7 downto 0);
  signal sk_rx_valid, sk_rx_err : std_logic := '0';

  -- spi
  signal spi_start, spi_busy, spi_done, spi_sclk, spi_mosi, spi_cs_n : std_logic := '0';
  signal spi_tx, spi_rx : std_logic_vector(7 downto 0) := (others => '0');
  signal spi_edges : natural := 0;

  -- axis_skid
  signal sk_s_data, sk_m_data : std_logic_vector(7 downto 0) := (others => '0');
  signal sk_s_last, sk_s_valid, sk_s_ready : std_logic := '0';
  signal sk_m_last, sk_m_valid, sk_m_ready : std_logic := '0';

  -- axi_lite_regs
  signal aresetn : std_logic;
  signal awaddr, araddr : std_logic_vector(3 downto 0) := (others => '0');
  signal awvalid, awready, wvalid, wready, bvalid, bready : std_logic := '0';
  signal arvalid, arready, rvalid, rready : std_logic := '0';
  signal wdata, rdata, control, status : std_logic_vector(31 downto 0) := (others => '0');
  signal wstrb : std_logic_vector(3 downto 0) := (others => '0');
  signal bresp, rresp : std_logic_vector(1 downto 0);
  signal b_seen : natural := 0;
  signal b_resp : std_logic_vector(1 downto 0) := "00";

begin

  clk  <= not clk  after C_PERIOD  / 2 when not stop;
  clk2 <= not clk2 after C_PERIOD2 / 2 when not stop;
  aresetn <= not rst;

  u_debounce : entity work.debounce
    generic map (G_CLK_HZ => 1000, G_DEBOUNCE_MS => 4)
    port map (clk => clk, rst => rst, din => db_in, dout => db_out);

  u_pulse_sync : entity work.pulse_sync
    port map (src_clk => clk, src_pulse => ps_in, dst_clk => clk2,
              dst_pulse => ps_out);

  u_fifo_async : entity work.fifo_async
    generic map (G_WIDTH => 8, G_DEPTH_LOG2 => 2)
    port map (wr_clk => clk, wr_rst => fa_wr_rst, wr_en => fa_wr_en,
              wr_data => fa_wr_data, full => fa_full,
              rd_clk => clk2, rd_rst => fa_rd_rst, rd_en => fa_rd_en,
              rd_data => fa_rd_data, rd_valid => fa_rd_valid,
              empty => fa_empty);

  u_pwm : entity work.pwm
    generic map (G_WIDTH => 4)
    port map (clk => clk, rst => rst, duty => pwm_duty, pwm_out => pwm_out);

  u_lfsr : entity work.lfsr
    port map (clk => clk, rst => rst, en => lfsr_en, q => lfsr_q);

  u_shift_reg : entity work.shift_reg
    generic map (G_WIDTH => 8, G_DEPTH => 3)
    port map (clk => clk, en => '1', din => sr_din, dout => sr_dout);

  u_rom : entity work.rom_lut
    generic map (G_ADDR_WIDTH => 4, G_WIDTH => 8)
    port map (clk => clk, addr => rom_addr, data => rom_data);

  u_mac : entity work.mac_dsp
    generic map (G_A_WIDTH => 8, G_B_WIDTH => 8, G_ACC_WIDTH => 24)
    port map (clk => clk, clr => mac_clr, a => mac_a, b => mac_b, acc => mac_acc);

  u_uart_tx : entity work.uart_tx
    generic map (G_CLK_HZ => 800, G_BAUD => 100)
    port map (clk => clk, rst => rst, data => u_data, valid => u_valid,
              ready => u_ready, tx => u_line);

  u_uart_rx : entity work.uart_rx
    generic map (G_CLK_HZ => 800, G_BAUD => 100)
    port map (clk => clk, rst => rst, rx => u_line, data => u_rx_data,
              valid => u_rx_valid, frame_err => u_frame_err);

  u_spi : entity work.spi_master
    generic map (G_CLK_DIV => 4)
    port map (clk => clk, rst => rst, start => spi_start, tx_data => spi_tx,
              busy => spi_busy, rx_data => spi_rx, done => spi_done,
              sclk => spi_sclk, mosi => spi_mosi, miso => spi_mosi,
              cs_n => spi_cs_n);

  u_skid : entity work.axis_skid
    generic map (G_WIDTH => 8)
    port map (clk => clk, rst => rst,
              s_tdata => sk_s_data, s_tlast => sk_s_last,
              s_tvalid => sk_s_valid, s_tready => sk_s_ready,
              m_tdata => sk_m_data, m_tlast => sk_m_last,
              m_tvalid => sk_m_valid, m_tready => sk_m_ready);

  u_axi : entity work.axi_lite_regs
    port map (aclk => clk, aresetn => aresetn,
              s_axi_awaddr => awaddr, s_axi_awvalid => awvalid,
              s_axi_awready => awready,
              s_axi_wdata => wdata, s_axi_wstrb => wstrb,
              s_axi_wvalid => wvalid, s_axi_wready => wready,
              s_axi_bresp => bresp, s_axi_bvalid => bvalid,
              s_axi_bready => bready,
              s_axi_araddr => araddr, s_axi_arvalid => arvalid,
              s_axi_arready => arready,
              s_axi_rdata => rdata, s_axi_rresp => rresp,
              s_axi_rvalid => rvalid, s_axi_rready => rready,
              control => control, status => status);

  -- Reset for everybody ------------------------------------------------------
  p_reset : process
  begin
    rst <= '1';
    for i in 1 to 5 loop
      wait until rising_edge(clk);
    end loop;
    rst <= '0';
    wait;
  end process p_reset;

  -- 0: debounce --------------------------------------------------------------
  p_debounce : process
    procedure ticks (n : positive) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk);
      end loop;
      wait for 1 ns;
    end procedure ticks;

    -- Input stays as driven; the output must hold `expected` the whole time.
    procedure watch (expected : std_logic; n : positive; message : string) is
    begin
      for i in 1 to n loop
        ticks(1);
        expect(fail(0), db_out = expected, message);
      end loop;
    end procedure watch;
  begin
    wait until rst = '0';
    for phase in 0 to 7 loop              -- glitches at different counter phases
      ticks(phase + 1);
      db_in <= '1';  ticks(3);
      db_in <= '0';  watch('0', 10, "debounce ignores a short glitch");
    end loop;
    db_in <= '1';  ticks(12);
    expect(fail(0), db_out = '1', "debounce accepts a long press");
    for phase in 0 to 7 loop
      ticks(phase + 1);
      db_in <= '0';  ticks(3);
      db_in <= '1';  watch('1', 10, "debounce ignores a short release");
    end loop;
    db_in <= '0';  ticks(12);
    expect(fail(0), db_out = '0', "debounce accepts a long release");
    done(0) <= '1';
    wait;
  end process p_debounce;

  -- 1: pulse_sync ------------------------------------------------------------
  p_ps_count : process (clk2)
  begin
    if rising_edge(clk2) then
      if ps_out = '1' then
        ps_count <= ps_count + 1;
      end if;
    end if;
  end process p_ps_count;

  p_pulse_sync : process
    procedure pulse is
    begin
      wait until rising_edge(clk);
      ps_in <= '1';
      wait until rising_edge(clk);
      ps_in <= '0';
      for i in 1 to 12 loop
        wait until rising_edge(clk);
      end loop;
    end procedure pulse;
  begin
    wait until rst = '0';
    pulse;
    expect(fail(1), ps_count = 1, "pulse_sync: one pulse in, one pulse out");
    pulse;
    pulse;
    expect(fail(1), ps_count = 3, "pulse_sync: three pulses in, three out");
    done(1) <= '1';
    wait;
  end process p_pulse_sync;

  -- 2: fifo_async ------------------------------------------------------------
  p_fifo_rst : process
  begin
    fa_wr_rst <= '1';
    fa_rd_rst <= '1';
    wait for 100 ns;
    fa_wr_rst <= '0';
    fa_rd_rst <= '0';
    wait;
  end process p_fifo_rst;

  p_fifo_write : process
    variable i : natural := 1;
  begin
    wait until fa_wr_rst = '0';
    wait until rising_edge(clk);
    while i <= 40 loop
      fa_wr_data <= std_logic_vector(to_unsigned(i, 8));
      fa_wr_en   <= '1';
      wait until rising_edge(clk);
      if fa_full = '1' then
        fa_saw_full <= '1';
      else
        i := i + 1;                       -- accepted at this edge
      end if;
    end loop;
    fa_wr_en <= '0';
    wait;
  end process p_fifo_write;

  p_fifo_read : process
    variable expected : natural := 1;
    variable saw_empty : boolean := false;
  begin
    wait until fa_rd_rst = '0';
    fa_rd_en <= '1';
    while expected <= 40 loop
      wait until rising_edge(clk2);
      if fa_empty = '1' then
        saw_empty := true;
      end if;
      if fa_rd_valid = '1' then
        expect(fail(2), fa_rd_data = std_logic_vector(to_unsigned(expected, 8)),
               "fifo_async returns data in order, none lost or repeated");
        expected := expected + 1;
      end if;
    end loop;
    fa_rd_en <= '0';
    wait for 200 ns;
    expect(fail(2), fa_saw_full = '1', "fifo_async reported full");
    expect(fail(2), saw_empty, "fifo_async reported empty");
    expect(fail(2), fa_empty = '1', "fifo_async is empty at the end");
    done(2) <= '1';
    wait;
  end process p_fifo_read;

  -- 3: pwm -------------------------------------------------------------------
  p_pwm : process
    variable highs : natural := 0;
  begin
    wait until rst = '0';
    for i in 1 to 4 loop
      wait until rising_edge(clk);
    end loop;
    for i in 1 to 32 loop                 -- two periods of 16 clocks
      wait until rising_edge(clk);
      if pwm_out = '1' then
        highs := highs + 1;
      end if;
    end loop;
    expect(fail(3), highs = 8, "pwm: duty 4/16 gives 8 high clocks in 32");
    done(3) <= '1';
    wait;
  end process p_pwm;

  -- 4: lfsr ------------------------------------------------------------------
  p_lfsr : process
    variable steps : natural := 0;
    variable early : boolean := false;
  begin
    wait until rst = '0';
    wait until rising_edge(clk);
    expect(fail(4), lfsr_q = x"01", "lfsr starts at the seed");
    lfsr_en <= '1';
    loop
      wait until rising_edge(clk);
      wait for 1 ns;
      steps := steps + 1;
      exit when lfsr_q = x"01" or steps > 300;
    end loop;
    expect(fail(4), steps = 255, "lfsr: 8-bit maximal sequence has period 255");
    done(4) <= '1';
    wait;
  end process p_lfsr;

  -- 5: shift_reg -------------------------------------------------------------
  p_shift : process
    procedure ticks (n : positive) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk);
      end loop;
      wait for 1 ns;
    end procedure ticks;
  begin
    wait until rst = '0';
    ticks(1);
    sr_din <= x"11";  ticks(1);
    sr_din <= x"22";  ticks(1);
    sr_din <= x"33";  ticks(1);
    expect(fail(5), sr_dout = x"11", "shift_reg: first word after 3 clocks");
    sr_din <= x"00";  ticks(1);
    expect(fail(5), sr_dout = x"22", "shift_reg: second word one clock later");
    ticks(1);
    expect(fail(5), sr_dout = x"33", "shift_reg: third word");
    done(5) <= '1';
    wait;
  end process p_shift;

  -- 6: rom_lut ---------------------------------------------------------------
  p_rom : process
    procedure lookup (a : natural) is
    begin
      rom_addr <= to_unsigned(a, 4);
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      wait for 1 ns;
    end procedure lookup;
  begin
    wait until rst = '0';
    lookup(0);
    expect(fail(6), rom_data = x"80", "rom_lut: sin(0) is mid-scale");
    lookup(4);
    expect(fail(6), rom_data = x"FF", "rom_lut: sin(90 deg) is full scale");
    lookup(8);
    expect(fail(6), rom_data = x"80", "rom_lut: sin(180 deg) is mid-scale");
    lookup(12);
    expect(fail(6), rom_data = x"01", "rom_lut: sin(270 deg) is minimum");
    done(6) <= '1';
    wait;
  end process p_rom;

  -- 7: mac_dsp ---------------------------------------------------------------
  p_mac : process
    procedure ticks (n : positive) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk);
      end loop;
      wait for 1 ns;
    end procedure ticks;
  begin
    wait until rst = '0';
    ticks(1);
    mac_a <= to_signed(2, 8);   mac_b <= to_signed(3, 8);   ticks(1);
    mac_a <= to_signed(-4, 8);  mac_b <= to_signed(5, 8);   ticks(1);
    mac_a <= (others => '0');   mac_b <= (others => '0');   ticks(6);
    expect(fail(7), mac_acc = to_signed(6 - 20, 24), "mac_dsp: 2*3 + (-4)*5");
    mac_clr <= '1';  ticks(1);
    mac_clr <= '0';  ticks(1);
    expect(fail(7), mac_acc = to_signed(0, 24), "mac_dsp: clear");
    done(7) <= '1';
    wait;
  end process p_mac;

  -- 8: UART loopback ---------------------------------------------------------
  p_uart_send : process
    type byte_array_t is array (natural range <>) of std_logic_vector(7 downto 0);
    constant C_BYTES : byte_array_t := (x"A6", x"31", x"01", x"80");
  begin
    wait until rst = '0';
    wait until rising_edge(clk);
    for i in C_BYTES'range loop
      u_data  <= C_BYTES(i);
      u_valid <= '1';
      loop
        wait until rising_edge(clk);
        exit when u_ready = '1';          -- taken at this edge
      end loop;
      u_valid <= '0';
      wait until rising_edge(clk);
    end loop;
    wait;
  end process p_uart_send;

  p_uart_recv : process
    type byte_array_t is array (natural range <>) of std_logic_vector(7 downto 0);
    constant C_BYTES : byte_array_t := (x"A6", x"31", x"01", x"80");
    variable n : natural := 0;
  begin
    wait until rst = '0';
    while n < C_BYTES'length loop
      wait until rising_edge(clk);
      if u_rx_valid = '1' then
        expect(fail(8), u_rx_data = C_BYTES(n), "uart: byte received intact");
        expect(fail(8), u_frame_err = '0', "uart: no framing error");
        n := n + 1;
      end if;
    end loop;
    done(8) <= '1';
    wait;
  end process p_uart_recv;

  -- 12: UART receiver against a transmitter with baud rate error ------------
  u_uart_rx_skew : entity work.uart_rx
    generic map (G_CLK_HZ => 3200, G_BAUD => 100)    -- 32 clocks per bit
    port map (clk => clk, rst => rst, rx => sk_line, data => sk_rx_data,
              valid => sk_rx_valid, frame_err => sk_rx_err);

  p_uart_skew_tx : process
    procedure send (byte : std_logic_vector(7 downto 0); bit_clks : positive) is
      procedure bit_out (b : std_logic) is
      begin
        sk_line <= b;
        for i in 1 to bit_clks loop
          wait until rising_edge(clk);
        end loop;
      end procedure bit_out;
    begin
      bit_out('0');
      for i in 0 to 7 loop
        bit_out(byte(i));
      end loop;
      bit_out('1');
      for i in 1 to 40 loop
        wait until rising_edge(clk);
      end loop;
    end procedure send;
  begin
    sk_line <= '1';
    wait until rst = '0';
    for i in 1 to 4 loop
      wait until rising_edge(clk);
    end loop;
    send(x"A6", 33);                      -- 3 % slow
    send(x"31", 31);                      -- 3 % fast
    send(x"81", 33);
    send(x"7E", 31);
    wait;
  end process p_uart_skew_tx;

  p_uart_skew_rx : process
    type byte_array_t is array (natural range <>) of std_logic_vector(7 downto 0);
    constant C_BYTES : byte_array_t := (x"A6", x"31", x"81", x"7E");
    variable n : natural := 0;
  begin
    wait until rst = '0';
    while n < C_BYTES'length loop
      wait until rising_edge(clk);
      if sk_rx_valid = '1' then
        expect(fail(12), sk_rx_data = C_BYTES(n),
               "uart_rx tolerates +-3 % baud rate error");
        expect(fail(12), sk_rx_err = '0', "uart_rx: no framing error");
        n := n + 1;
      end if;
    end loop;
    done(12) <= '1';
    wait;
  end process p_uart_skew_rx;

  -- 9: SPI loopback ----------------------------------------------------------
  p_spi_edges : process (spi_sclk)
  begin
    if rising_edge(spi_sclk) then
      spi_edges <= spi_edges + 1;
    end if;
  end process p_spi_edges;

  p_spi : process
    procedure transfer (value : std_logic_vector(7 downto 0)) is
    begin
      spi_tx    <= value;
      spi_start <= '1';
      wait until rising_edge(clk);
      spi_start <= '0';
      wait until rising_edge(clk);
      expect(fail(9), spi_busy = '1' and spi_cs_n = '0', "spi: busy, CS low");
      wait until rising_edge(clk) and spi_done = '1';
      wait for 1 ns;
      expect(fail(9), spi_rx = value, "spi: loopback returns what was sent");
      expect(fail(9), spi_cs_n = '1' and spi_busy = '0', "spi: CS released");
      wait until rising_edge(clk);
    end procedure transfer;
  begin
    wait until rst = '0';
    wait until rising_edge(clk);
    transfer(x"A6");
    transfer(x"31");
    expect(fail(9), spi_edges = 16, "spi: 8 SCLK pulses per transfer");
    done(9) <= '1';
    wait;
  end process p_spi;

  -- 10: axis_skid ------------------------------------------------------------
  p_skid_src : process
    variable i : natural := 1;
  begin
    wait until rst = '0';
    wait until rising_edge(clk);
    while i <= 50 loop
      sk_s_data <= std_logic_vector(to_unsigned(i, 8));
      if i = 50 then
        sk_s_last <= '1';
      end if;
      sk_s_valid <= '1';
      wait until rising_edge(clk);
      if sk_s_ready = '1' then            -- accepted at this edge
        i := i + 1;
        if i mod 4 = 0 then               -- gaps on the source side
          sk_s_valid <= '0';
          wait until rising_edge(clk);
          wait until rising_edge(clk);
        end if;
      end if;
    end loop;
    sk_s_valid <= '0';
    wait;
  end process p_skid_src;

  p_skid_sink : process
    variable expected : natural := 1;
    variable cycle    : natural := 0;
  begin
    wait until rst = '0';
    while expected <= 50 loop
      wait until rising_edge(clk);
      if sk_m_valid = '1' and sk_m_ready = '1' then
        expect(fail(10), sk_m_data = std_logic_vector(to_unsigned(expected, 8)),
               "axis_skid: data in order, none lost or repeated");
        expect(fail(10), (sk_m_last = '1') = (expected = 50),
               "axis_skid: tlast only on the last word");
        expected := expected + 1;
      end if;
      cycle := cycle + 1;
      if cycle mod 5 < 2 then             -- sink ready 2 of 5 clocks
        sk_m_ready <= '1';
      else
        sk_m_ready <= '0';
      end if;
    end loop;
    done(10) <= '1';
    wait;
  end process p_skid_sink;

  -- 11: axi_lite_regs --------------------------------------------------------
  p_bmon : process (clk)
  begin
    if rising_edge(clk) then
      if bvalid = '1' and bready = '1' then
        b_seen <= b_seen + 1;
        b_resp <= bresp;
      end if;
    end if;
  end process p_bmon;

  p_axi : process
    variable seen : natural;
    variable got  : std_logic_vector(31 downto 0);

    procedure axi_write (addr : natural; data : std_logic_vector(31 downto 0);
                         strb : std_logic_vector(3 downto 0)) is
    begin
      seen    := b_seen;
      awaddr  <= std_logic_vector(to_unsigned(addr, 4));
      awvalid <= '1';
      wdata   <= data;
      wstrb   <= strb;
      wvalid  <= '1';
      loop
        wait until rising_edge(clk);
        exit when awready = '1' and wready = '1';
      end loop;
      awvalid <= '0';
      wvalid  <= '0';
      while b_seen = seen loop
        wait until rising_edge(clk);
      end loop;
      wait for 1 ns;
    end procedure axi_write;

    procedure axi_read (addr : natural; hold : natural;
                        data : out std_logic_vector(31 downto 0)) is
    begin
      araddr  <= std_logic_vector(to_unsigned(addr, 4));
      arvalid <= '1';
      loop
        wait until rising_edge(clk);
        exit when arready = '1';
      end loop;
      arvalid <= '0';
      for i in 1 to hold loop             -- master not ready: slave must wait
        wait until rising_edge(clk);
        expect(fail(11), rvalid = '1', "axi: rvalid held until rready");
      end loop;
      rready <= '1';
      loop
        wait until rising_edge(clk);
        exit when rvalid = '1';
      end loop;
      data   := rdata;
      rready <= '0';
      wait for 1 ns;
    end procedure axi_read;
  begin
    bready <= '1';
    status <= x"12345678";
    wait until rst = '0';
    wait until rising_edge(clk);

    axi_write(0, x"DEADBEEF", "1111");
    expect(fail(11), b_resp = "00", "axi: write to CONTROL is OKAY");
    expect(fail(11), control = x"DEADBEEF", "axi: CONTROL drives the output");
    axi_read(0, 0, got);
    expect(fail(11), got = x"DEADBEEF", "axi: CONTROL reads back");

    axi_write(8, x"FFFFFFFF", "1111");
    axi_write(8, x"00000000", "0101");
    axi_read(8, 3, got);
    expect(fail(11), got = x"FF00FF00", "axi: byte strobes and held read data");

    axi_read(4, 0, got);
    expect(fail(11), got = x"12345678", "axi: STATUS reads the input");
    axi_write(4, x"FFFFFFFF", "1111");
    expect(fail(11), b_resp = "10", "axi: write to read-only STATUS gives SLVERR");
    axi_read(4, 0, got);
    expect(fail(11), got = x"12345678", "axi: STATUS unchanged by the write");

    axi_read(12, 0, got);
    expect(fail(11), got = x"00010000", "axi: VERSION");
    done(11) <= '1';
    wait;
  end process p_axi;

  -- 13, 14: bus_sync_handshake, both directions between unrelated clocks -----
  u_hs_slow_to_fast : entity work.tb_hs_bench
    port map (src_clk => clk2, dst_clk => clk, rst => rst,
              done => done(13), fail => fail(13));

  u_hs_fast_to_slow : entity work.tb_hs_bench
    port map (src_clk => clk, dst_clk => clk2, rst => rst,
              done => done(14), fail => fail(14));

  -- Verdict ------------------------------------------------------------------
  p_verdict : process
  begin
    wait until done = (done'range => '1') for 40 us;
    wait for 100 ns;
    if done /= (done'range => '1') then
      report "TEST FAILED: timeout, blocks not finished: " & to_string(done)
        severity failure;
    elsif fail /= (fail'range => '0') then
      report "TEST FAILED: failing blocks: " & to_string(fail) severity failure;
    else
      report "TEST PASSED";
    end if;
    stop <= true;
    wait;
  end process p_verdict;

end architecture sim;
