-- Checks the BFM packages against designs and models they did not write:
--   AXI-Stream        BFM -> axis_skid -> BFM (gaps and back-pressure)
--   Avalon-ST         BFM -> axis_skid -> BFM, and BFM -> BFM (startofpacket)
--   AXI4-Lite         BFM master -> axi_lite_regs
--   Avalon-MM         BFM master -> avalon_mm_regs (one wait state per access)
--   UART              BFM -> uart_rx, uart_tx -> BFM, BFM <-> BFM formats and errors
--   SPI               BFM slave <-> spi_master, BFM master <-> reference slave
--                     written separately here, BFM master <-> BFM slave
-- Run by `make check'.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.bfm_util_pkg.all;
use work.bfm_axis_pkg.all;
use work.bfm_avalon_st_pkg.all;
use work.bfm_axilite_pkg.all;
use work.bfm_avalon_mm_pkg.all;
use work.bfm_uart_pkg.all;
use work.bfm_spi_pkg.all;

entity tb_bfm is
end entity tb_bfm;

architecture sim of tb_bfm is

  constant C_PERIOD : time   := 10 ns;
  constant C_SCOPE  : string := "tb_bfm";

  signal clk  : std_logic := '0';
  signal rst  : std_logic := '1';
  signal stop : boolean   := false;
  signal done : std_logic_vector(0 to 18) := (others => '0');

  ---------------------------------------------------------------------------
  -- AXI-Stream and Avalon-ST
  ---------------------------------------------------------------------------
  function axis_packet (id : natural; length : positive) return t_slv_array is
    variable p : t_slv_array(0 to length - 1)(C_AXIS_DATA_WIDTH - 1 downto 0);
  begin
    for i in p'range loop
      p(i) := std_logic_vector(to_unsigned(id * 256 + i, C_AXIS_DATA_WIDTH));
    end loop;
    return p;
  end function axis_packet;

  function avst_packet (id : natural; length : positive) return t_slv_array is
    variable p : t_slv_array(0 to length - 1)(C_AVST_DATA_WIDTH - 1 downto 0);
  begin
    for i in p'range loop
      p(i) := std_logic_vector(to_unsigned(id * 256 + i, C_AVST_DATA_WIDTH));
    end loop;
    return p;
  end function avst_packet;

  constant C_AXIS_GAP  : t_axis_bfm_config := (1000, 2, 0);   -- source gaps
  constant C_AXIS_BP   : t_axis_bfm_config := (1000, 0, 3);   -- sink back-pressure
  constant C_AXIS_SRC2 : t_axis_bfm_config := (1000, 1, 0);
  constant C_AXIS_SNK2 : t_axis_bfm_config := (1000, 0, 1);

  constant C_AVST_GAP  : t_avst_bfm_config := (1000, 2, 0, true);
  constant C_AVST_BP   : t_avst_bfm_config := (1000, 0, 3, true);
  constant C_AVST_SKID : t_avst_bfm_config := (1000, 0, 0, false);   -- skid drops sop
  constant C_AVST_SKID_BP : t_avst_bfm_config := (1000, 0, 2, false);

  signal ax_src_m2s, ax_snk_m2s : t_axis_m2s := C_AXIS_M2S_INIT;
  signal ax_src_s2m, ax_snk_s2m : t_axis_s2m := C_AXIS_S2M_INIT;

  signal st_src_m2s, st_snk_m2s : t_avst_m2s := C_AVST_M2S_INIT;
  signal st_src_s2m, st_snk_s2m : t_avst_s2m := C_AVST_S2M_INIT;

  signal sd_m2s : t_avst_m2s := C_AVST_M2S_INIT;     -- direct source -> sink
  signal sd_s2m : t_avst_s2m := C_AVST_S2M_INIT;

  ---------------------------------------------------------------------------
  -- AXI4-Lite and Avalon-MM
  ---------------------------------------------------------------------------
  signal al_m2s     : t_axilite_m2s := C_AXILITE_M2S_INIT;
  signal al_s2m     : t_axilite_s2m;
  signal al_control : std_logic_vector(31 downto 0);
  signal al_status  : std_logic_vector(31 downto 0) := (others => '0');

  signal av_m2s     : t_avmm_m2s := C_AVMM_M2S_INIT;
  signal av_s2m     : t_avmm_s2m;
  signal av_control : std_logic_vector(31 downto 0);
  signal av_status  : std_logic_vector(31 downto 0) := (others => '0');

  ---------------------------------------------------------------------------
  -- UART: 80 ns per bit = 8 clocks of the DUTs (G_CLK_HZ 800, G_BAUD 100)
  ---------------------------------------------------------------------------
  constant C_UART_DUT : t_uart_bfm_config :=
    (bit_period => 80 ns, data_bits => 8, parity => PARITY_NONE, stop_bits => 1,
     inject_parity_error => false, inject_frame_error => false, timeout => 100 us);
  constant C_UART_BADSTOP : t_uart_bfm_config :=
    (bit_period => 80 ns, data_bits => 8, parity => PARITY_NONE, stop_bits => 1,
     inject_parity_error => false, inject_frame_error => true, timeout => 100 us);

  signal u_rxd                : std_logic := '1';    -- BFM -> uart_rx
  signal u_rx_data            : std_logic_vector(7 downto 0);
  signal u_rx_valid, u_rx_err : std_logic;
  signal u_tx_data            : std_logic_vector(7 downto 0) := (others => '0');
  signal u_tx_valid           : std_logic := '0';
  signal u_tx_ready           : std_logic;
  signal u_txd                : std_logic;           -- uart_tx -> BFM

  type t_uart_case is record
    cfg       : t_uart_bfm_config;
    data      : std_logic_vector(7 downto 0);
    exp_frame : boolean;
    exp_par   : boolean;
  end record t_uart_case;
  type t_uart_cases is array (natural range <>) of t_uart_case;

  constant C_UART_1US : t_uart_bfm_config :=
    (bit_period => 1 us, data_bits => 8, parity => PARITY_NONE, stop_bits => 1,
     inject_parity_error => false, inject_frame_error => false, timeout => 100 us);

  constant C_UART_CASES : t_uart_cases := (
    (C_UART_1US, x"A6", false, false),
    (C_UART_1US, x"31", false, false),
    -- 7 data bits, even parity
    ((1 us, 7, PARITY_EVEN, 1, false, false, 100 us), x"55", false, false),
    ((1 us, 7, PARITY_EVEN, 1, false, false, 100 us), x"2A", false, false),
    -- 8 data bits, odd parity, two stop bits
    ((1 us, 8, PARITY_ODD, 2, false, false, 100 us), x"A6", false, false),
    ((1 us, 8, PARITY_ODD, 2, false, false, 100 us), x"31", false, false),
    -- 5 data bits
    ((1 us, 5, PARITY_NONE, 1, false, false, 100 us), x"15", false, false),
    ((1 us, 5, PARITY_NONE, 1, false, false, 100 us), x"0A", false, false),
    -- errors on purpose
    ((1 us, 8, PARITY_EVEN, 1, true, false, 100 us), x"5A", false, true),
    ((1 us, 8, PARITY_NONE, 1, false, true, 100 us), x"C3", true, false),
    ((1 us, 8, PARITY_ODD, 1, false, false, 100 us), x"7E", false, false));

  signal u2_line : std_logic := '1';

  ---------------------------------------------------------------------------
  -- SPI
  ---------------------------------------------------------------------------
  constant C_SPI_DUT : t_spi_bfm_config :=
    (cpol => '0', cpha => '0', sclk_period => 80 ns, msb_first => true,
     word_width => 8, cs_setup => 50 ns, cs_hold => 50 ns, timeout => 100 us);

  -- spi_master DUT with the slave BFM
  signal sp_m2s    : t_spi_m2s := spi_m2s_idle(C_SPI_DUT);
  signal sp_s2m    : t_spi_s2m := C_SPI_S2M_INIT;
  signal sp_start  : std_logic := '0';
  signal sp_tx     : std_logic_vector(7 downto 0) := (others => '0');
  signal sp_rx     : std_logic_vector(7 downto 0);
  signal sp_busy, sp_done : std_logic;

  -- master BFM with the reference slave
  signal rf_m2s  : t_spi_m2s := spi_m2s_idle(C_SPI_DUT);
  signal rf_miso : std_logic := '0';
  signal rf_s2m  : t_spi_s2m;
  signal rf_cpol, rf_cpha : std_logic := '0';
  signal rf_w    : natural range 1 to 32 := 8;
  signal rf_msb  : boolean := true;
  signal rf_tx   : std_logic_vector(31 downto 0) := (others => '0');
  signal rf_rx   : std_logic_vector(31 downto 0) := (others => '0');

  -- master BFM with slave BFM
  signal bs_m2s : t_spi_m2s := spi_m2s_idle(C_SPI_DUT);
  signal bs_s2m : t_spi_s2m := C_SPI_S2M_INIT;

  type t_spi_word_case is record
    width : natural range 1 to 32;
    msb   : boolean;
  end record t_spi_word_case;
  type t_spi_word_cases is array (natural range <>) of t_spi_word_case;
  constant C_SPI_WORD_CASES : t_spi_word_cases :=
    ((8, true), (12, false), (16, true), (5, false), (32, true));

  function make_spi_config (mode : natural; width : natural; msb : boolean)
    return t_spi_bfm_config is
    variable v_cfg : t_spi_bfm_config :=
      (cpol => '0', cpha => '0', sclk_period => 200 ns, msb_first => msb,
       word_width => width, cs_setup => 50 ns, cs_hold => 50 ns, timeout => 100 us);
  begin
    if mode >= 2 then
      v_cfg.cpol := '1';
    end if;
    if (mode mod 2) = 1 then
      v_cfg.cpha := '1';
    end if;
    return v_cfg;
  end function make_spi_config;

  function mask (width : natural) return std_logic_vector is
    variable v : std_logic_vector(31 downto 0) := (others => '0');
  begin
    v(width - 1 downto 0) := (others => '1');
    return v;
  end function mask;

  constant C_SPI_M_WORD : std_logic_vector(31 downto 0) := x"A6C35A19";
  constant C_SPI_S_WORD : std_logic_vector(31 downto 0) := x"9E4B27D1";

begin

  clk <= not clk after C_PERIOD / 2 when not stop;

  p_reset : process
  begin
    rst <= '1';
    bfm_wait_cycles(5, clk);
    rst <= '0';
    wait;
  end process p_reset;

  ---------------------------------------------------------------------------
  -- AXI-Stream: BFM -> axis_skid -> BFM
  ---------------------------------------------------------------------------
  u_skid_axis : entity work.axis_skid
    generic map (G_WIDTH => C_AXIS_DATA_WIDTH)
    port map (clk => clk, rst => rst,
              s_tdata => ax_src_m2s.tdata, s_tlast => ax_src_m2s.tlast,
              s_tvalid => ax_src_m2s.tvalid, s_tready => ax_src_s2m.tready,
              m_tdata => ax_snk_m2s.tdata, m_tlast => ax_snk_m2s.tlast,
              m_tvalid => ax_snk_m2s.tvalid, m_tready => ax_snk_s2m.tready);

  p_axis_src : process
  begin
    wait until rst = '0';
    wait until rising_edge(clk);
    axis_transmit(axis_packet(1, 4), "P1", clk, ax_src_m2s, ax_src_s2m, C_SCOPE);
    axis_transmit(axis_packet(2, 5), "P2 with gaps", clk, ax_src_m2s, ax_src_s2m, C_SCOPE, C_AXIS_GAP);
    axis_transmit(axis_packet(3, 6), "P3", clk, ax_src_m2s, ax_src_s2m, C_SCOPE);
    axis_transmit(axis_packet(4, 1), "P4 single beat", clk, ax_src_m2s, ax_src_s2m, C_SCOPE);
    axis_transmit(axis_packet(5, 7), "P5 gaps and back-pressure", clk, ax_src_m2s, ax_src_s2m, C_SCOPE, C_AXIS_SRC2);
    done(0) <= '1';
    wait;
  end process p_axis_src;

  p_axis_snk : process
  begin
    axis_expect(axis_packet(1, 4), "P1", clk, ax_snk_m2s, ax_snk_s2m, C_SCOPE);
    axis_expect(axis_packet(2, 5), "P2 with gaps", clk, ax_snk_m2s, ax_snk_s2m, C_SCOPE);
    axis_expect(axis_packet(3, 6), "P3 with back-pressure", clk, ax_snk_m2s, ax_snk_s2m, C_SCOPE, C_AXIS_BP);
    axis_expect(axis_packet(4, 1), "P4 single beat", clk, ax_snk_m2s, ax_snk_s2m, C_SCOPE);
    axis_expect(axis_packet(5, 7), "P5 gaps and back-pressure", clk, ax_snk_m2s, ax_snk_s2m, C_SCOPE, C_AXIS_SNK2);
    done(1) <= '1';
    wait;
  end process p_axis_snk;

  ---------------------------------------------------------------------------
  -- Avalon-ST: BFM -> axis_skid -> BFM, and BFM -> BFM
  ---------------------------------------------------------------------------
  u_skid_st : entity work.axis_skid
    generic map (G_WIDTH => C_AVST_DATA_WIDTH)
    port map (clk => clk, rst => rst,
              s_tdata => st_src_m2s.data, s_tlast => st_src_m2s.endofpacket,
              s_tvalid => st_src_m2s.valid, s_tready => st_src_s2m.ready,
              m_tdata => st_snk_m2s.data, m_tlast => st_snk_m2s.endofpacket,
              m_tvalid => st_snk_m2s.valid, m_tready => st_snk_s2m.ready);

  p_st_src : process
  begin
    wait until rst = '0';
    wait until rising_edge(clk);
    avst_transmit(avst_packet(1, 5), "P1", clk, st_src_m2s, st_src_s2m, C_SCOPE);
    avst_transmit(avst_packet(2, 1), "P2 single beat", clk, st_src_m2s, st_src_s2m, C_SCOPE);
    avst_transmit(avst_packet(3, 6), "P3 with gaps", clk, st_src_m2s, st_src_s2m, C_SCOPE, C_AVST_GAP);
    done(2) <= '1';
    wait;
  end process p_st_src;

  p_st_snk : process
  begin
    avst_expect(avst_packet(1, 5), "P1", clk, st_snk_m2s, st_snk_s2m, C_SCOPE, C_AVST_SKID);
    avst_expect(avst_packet(2, 1), "P2 single beat", clk, st_snk_m2s, st_snk_s2m, C_SCOPE, C_AVST_SKID);
    avst_expect(avst_packet(3, 6), "P3 with back-pressure", clk, st_snk_m2s, st_snk_s2m, C_SCOPE, C_AVST_SKID_BP);
    done(3) <= '1';
    wait;
  end process p_st_snk;

  p_sd_src : process
  begin
    wait until rst = '0';
    wait until rising_edge(clk);
    avst_transmit(avst_packet(1, 4), "P1", clk, sd_m2s, sd_s2m, C_SCOPE);
    avst_transmit(avst_packet(2, 1), "P2 single beat", clk, sd_m2s, sd_s2m, C_SCOPE);
    avst_transmit(avst_packet(3, 5), "P3 with gaps", clk, sd_m2s, sd_s2m, C_SCOPE, C_AVST_GAP);
    done(4) <= '1';
    wait;
  end process p_sd_src;

  p_sd_snk : process
  begin
    avst_expect(avst_packet(1, 4), "P1", clk, sd_m2s, sd_s2m, C_SCOPE);
    avst_expect(avst_packet(2, 1), "P2 single beat", clk, sd_m2s, sd_s2m, C_SCOPE);
    avst_expect(avst_packet(3, 5), "P3 with back-pressure", clk, sd_m2s, sd_s2m, C_SCOPE, C_AVST_BP);
    done(5) <= '1';
    wait;
  end process p_sd_snk;

  ---------------------------------------------------------------------------
  -- AXI4-Lite: BFM -> axi_lite_regs
  ---------------------------------------------------------------------------
  u_axi : entity work.axi_lite_regs
    port map (aclk => clk, aresetn => not rst,
              s_axi_awaddr => al_m2s.awaddr(3 downto 0), s_axi_awvalid => al_m2s.awvalid,
              s_axi_awready => al_s2m.awready,
              s_axi_wdata => al_m2s.wdata, s_axi_wstrb => al_m2s.wstrb,
              s_axi_wvalid => al_m2s.wvalid, s_axi_wready => al_s2m.wready,
              s_axi_bresp => al_s2m.bresp, s_axi_bvalid => al_s2m.bvalid,
              s_axi_bready => al_m2s.bready,
              s_axi_araddr => al_m2s.araddr(3 downto 0), s_axi_arvalid => al_m2s.arvalid,
              s_axi_arready => al_s2m.arready,
              s_axi_rdata => al_s2m.rdata, s_axi_rresp => al_s2m.rresp,
              s_axi_rvalid => al_s2m.rvalid, s_axi_rready => al_m2s.rready,
              control => al_control, status => al_status);

  p_axilite : process
    constant C_SLOW : t_axilite_bfm_config :=
      (max_wait_cycles => 1000, bready_delay => 3, rready_delay => 3);
  begin
    al_status <= x"12345678";
    wait until rst = '0';
    wait until rising_edge(clk);
    axilite_write(x"00000000", x"DEADBEEF", "CONTROL", clk, al_m2s, al_s2m, scope => C_SCOPE);
    bfm_check_value(al_control, x"DEADBEEF", "CONTROL drives its output", C_SCOPE);
    axilite_check(x"00000000", x"DEADBEEF", "CONTROL", clk, al_m2s, al_s2m, scope => C_SCOPE);
    axilite_write(x"00000008", x"FFFFFFFF", "SCRATCH ones", clk, al_m2s, al_s2m, scope => C_SCOPE);
    axilite_write(x"00000008", x"00000000", "SCRATCH strobes 0101", clk, al_m2s, al_s2m,
                  strb => "0101", scope => C_SCOPE);
    axilite_check(x"00000008", x"FF00FF00", "SCRATCH after strobes, slow master", clk, al_m2s, al_s2m,
                  scope => C_SCOPE, config => C_SLOW);
    axilite_check(x"00000004", x"12345678", "STATUS", clk, al_m2s, al_s2m, scope => C_SCOPE);
    axilite_write(x"00000004", x"FFFFFFFF", "STATUS is read-only", clk, al_m2s, al_s2m,
                  exp_resp => C_AXI_RESP_SLVERR, scope => C_SCOPE, config => C_SLOW);
    axilite_check(x"00000004", x"12345678", "STATUS unchanged", clk, al_m2s, al_s2m, scope => C_SCOPE);
    axilite_write(x"0000000C", x"FFFFFFFF", "VERSION is read-only", clk, al_m2s, al_s2m,
                  exp_resp => C_AXI_RESP_SLVERR, scope => C_SCOPE);
    axilite_check(x"00000000", x"DEADBEEF", "CONTROL untouched by the read-only writes",
                  clk, al_m2s, al_s2m, scope => C_SCOPE);
    axilite_write(x"00000000", x"00000000", "CONTROL strobes 1010", clk, al_m2s, al_s2m,
                  strb => "1010", scope => C_SCOPE);
    bfm_check_value(al_control, x"00AD00EF", "CONTROL output after strobed write", C_SCOPE);
    axilite_check(x"0000000C", x"00010000", "VERSION", clk, al_m2s, al_s2m, scope => C_SCOPE);
    done(6) <= '1';
    wait;
  end process p_axilite;

  ---------------------------------------------------------------------------
  -- Avalon-MM: BFM -> avalon_mm_regs
  ---------------------------------------------------------------------------
  u_avmm : entity work.avalon_mm_regs
    port map (clk => clk, reset => rst,
              address => av_m2s.address(1 downto 0),
              read => av_m2s.read, readdata => av_s2m.readdata,
              readdatavalid => av_s2m.readdatavalid,
              write => av_m2s.write, writedata => av_m2s.writedata,
              byteenable => av_m2s.byteenable, waitrequest => av_s2m.waitrequest,
              control => av_control, status => av_status);

  p_avmm : process
  begin
    av_status <= x"12345678";
    wait until rst = '0';
    wait until rising_edge(clk);
    avmm_write(x"00", x"DEADBEEF", "CONTROL", clk, av_m2s, av_s2m, scope => C_SCOPE);
    bfm_wait_cycles(1, clk);            -- the write returns on the edge the slave latches it
    bfm_check_value(av_control, x"DEADBEEF", "CONTROL drives its output", C_SCOPE);
    avmm_check(x"00", x"DEADBEEF", "CONTROL", clk, av_m2s, av_s2m, C_SCOPE);
    avmm_write(x"02", x"FFFFFFFF", "SCRATCH ones", clk, av_m2s, av_s2m, scope => C_SCOPE);
    avmm_write(x"02", x"00000000", "SCRATCH byteenable 0101", clk, av_m2s, av_s2m,
               byteenable => "0101", scope => C_SCOPE);
    avmm_check(x"02", x"FF00FF00", "SCRATCH after byteenables", clk, av_m2s, av_s2m, C_SCOPE);
    avmm_check(x"01", x"12345678", "STATUS", clk, av_m2s, av_s2m, C_SCOPE);
    avmm_write(x"01", x"FFFFFFFF", "STATUS is read-only", clk, av_m2s, av_s2m, scope => C_SCOPE);
    avmm_check(x"01", x"12345678", "STATUS unchanged", clk, av_m2s, av_s2m, C_SCOPE);
    avmm_write(x"03", x"FFFFFFFF", "VERSION is read-only", clk, av_m2s, av_s2m, scope => C_SCOPE);
    avmm_check(x"00", x"DEADBEEF", "CONTROL untouched by the read-only writes", clk, av_m2s, av_s2m, C_SCOPE);
    avmm_write(x"00", x"00000000", "CONTROL byteenable 1010", clk, av_m2s, av_s2m,
               byteenable => "1010", scope => C_SCOPE);
    bfm_wait_cycles(1, clk);
    bfm_check_value(av_control, x"00AD00EF", "CONTROL output after byteenabled write", C_SCOPE);
    avmm_check(x"03", x"00010000", "VERSION", clk, av_m2s, av_s2m, C_SCOPE);
    done(7) <= '1';
    wait;
  end process p_avmm;

  ---------------------------------------------------------------------------
  -- UART: BFM -> uart_rx
  ---------------------------------------------------------------------------
  u_uart_rx : entity work.uart_rx
    generic map (G_CLK_HZ => 800, G_BAUD => 100)
    port map (clk => clk, rst => rst, rx => u_rxd, data => u_rx_data,
              valid => u_rx_valid, frame_err => u_rx_err);

  p_uart_send : process
  begin
    wait until rst = '0';
    wait for 200 ns;
    uart_transmit(x"A6", "A6", u_rxd, C_SCOPE, C_UART_DUT);
    wait for 160 ns;
    uart_transmit(x"31", "31", u_rxd, C_SCOPE, C_UART_DUT);
    uart_transmit(x"01", "01 back to back", u_rxd, C_SCOPE, C_UART_DUT);
    uart_transmit(x"80", "80 back to back", u_rxd, C_SCOPE, C_UART_DUT);
    wait for 160 ns;
    uart_transmit(x"5A", "5A with a low stop bit", u_rxd, C_SCOPE, C_UART_BADSTOP);
    wait for 400 ns;
    done(8) <= '1';
    wait;
  end process p_uart_send;

  p_uart_mon : process
    type t_bytes is array (natural range <>) of std_logic_vector(7 downto 0);
    constant C_BYTES : t_bytes := (x"A6", x"31", x"01", x"80", x"5A");
  begin
    for i in C_BYTES'range loop
      wait until rising_edge(clk) and u_rx_valid = '1';
      bfm_check_value(u_rx_data, C_BYTES(i), "uart_rx byte " & integer'image(i), C_SCOPE);
      if i = C_BYTES'high then
        bfm_check_value(u_rx_err, '1', "uart_rx flags the low stop bit", C_SCOPE);
      else
        bfm_check_value(u_rx_err, '0', "uart_rx no framing error, byte " & integer'image(i), C_SCOPE);
      end if;
    end loop;
    done(9) <= '1';
    wait;
  end process p_uart_mon;

  ---------------------------------------------------------------------------
  -- UART: uart_tx -> BFM
  ---------------------------------------------------------------------------
  u_uart_tx : entity work.uart_tx
    generic map (G_CLK_HZ => 800, G_BAUD => 100)
    port map (clk => clk, rst => rst, data => u_tx_data, valid => u_tx_valid,
              ready => u_tx_ready, tx => u_txd);

  p_uart_tx_drive : process
    type t_bytes is array (natural range <>) of std_logic_vector(7 downto 0);
    constant C_BYTES : t_bytes := (x"A6", x"31", x"01", x"80");
  begin
    wait until rst = '0';
    wait until rising_edge(clk);
    for i in C_BYTES'range loop
      u_tx_data  <= C_BYTES(i);
      u_tx_valid <= '1';
      loop
        wait until rising_edge(clk);
        exit when u_tx_ready = '1';              -- taken at this edge
      end loop;
      u_tx_valid <= '0';
      wait until rising_edge(clk);
    end loop;
    done(10) <= '1';
    wait;
  end process p_uart_tx_drive;

  p_uart_tx_expect : process
    type t_bytes is array (natural range <>) of std_logic_vector(7 downto 0);
    constant C_BYTES : t_bytes := (x"A6", x"31", x"01", x"80");
  begin
    wait until rst = '0';
    for i in C_BYTES'range loop
      uart_expect(C_BYTES(i), "uart_tx byte " & integer'image(i), u_txd,
                  scope => C_SCOPE, config => C_UART_DUT);
    end loop;
    done(11) <= '1';
    wait;
  end process p_uart_tx_expect;

  ---------------------------------------------------------------------------
  -- UART: BFM <-> BFM, formats and injected errors
  ---------------------------------------------------------------------------
  p_uart_fmt_tx : process
  begin
    wait until rst = '0';
    wait for 1 us;
    for i in C_UART_CASES'range loop
      uart_transmit(C_UART_CASES(i).data, "case " & integer'image(i), u2_line,
                    C_SCOPE, C_UART_CASES(i).cfg);
      wait for 3 us;
    end loop;
    done(12) <= '1';
    wait;
  end process p_uart_fmt_tx;

  p_uart_fmt_rx : process
    variable v_cfg : t_uart_bfm_config;
  begin
    wait until rst = '0';
    for i in C_UART_CASES'range loop
      v_cfg := C_UART_CASES(i).cfg;
      v_cfg.inject_parity_error := false;        -- injection is a transmit-side option
      v_cfg.inject_frame_error  := false;
      uart_expect(C_UART_CASES(i).data, "case " & integer'image(i), u2_line,
                  C_UART_CASES(i).exp_frame, C_UART_CASES(i).exp_par, C_SCOPE, v_cfg);
    end loop;
    done(13) <= '1';
    wait;
  end process p_uart_fmt_rx;

  ---------------------------------------------------------------------------
  -- SPI: spi_master DUT <-> slave BFM
  ---------------------------------------------------------------------------
  u_spi : entity work.spi_master
    generic map (G_CLK_DIV => 4)
    port map (clk => clk, rst => rst, start => sp_start, tx_data => sp_tx,
              busy => sp_busy, rx_data => sp_rx, done => sp_done,
              sclk => sp_m2s.sclk, mosi => sp_m2s.mosi, miso => sp_s2m.miso,
              cs_n => sp_m2s.cs_n);

  p_spi_dut : process
    type t_words is array (natural range <>) of natural;
    constant C_TX : t_words := (16#A6#, 16#31#, 16#01#);
    constant C_RX : t_words := (16#5C#, 16#8E#, 16#80#);
  begin
    wait until rst = '0';
    wait for 100 ns;
    for i in C_TX'range loop
      sp_tx    <= std_logic_vector(to_unsigned(C_TX(i), 8));
      sp_start <= '1';
      wait until rising_edge(clk);
      sp_start <= '0';
      wait until rising_edge(clk) and sp_done = '1';
      wait for 1 ns;
      bfm_check_value(sp_rx, std_logic_vector(to_unsigned(C_RX(i), 8)),
                      "spi_master DUT receives the slave BFM word " & integer'image(i), C_SCOPE);
      bfm_wait_cycles(3, clk);
    end loop;
    done(14) <= '1';
    wait;
  end process p_spi_dut;

  p_spi_dut_slave : process
    type t_words is array (natural range <>) of natural;
    constant C_TX : t_words := (16#A6#, 16#31#, 16#01#);
    constant C_RX : t_words := (16#5C#, 16#8E#, 16#80#);
  begin
    for i in C_TX'range loop
      spi_slave_check(spi_word(C_RX(i)), spi_word(C_TX(i)),
                      "slave BFM receives the spi_master word " & integer'image(i),
                      sp_m2s, sp_s2m, C_SCOPE, C_SPI_DUT);
    end loop;
    done(15) <= '1';
    wait;
  end process p_spi_dut_slave;

  ---------------------------------------------------------------------------
  -- SPI: master BFM <-> reference slave (written independently of the BFM)
  ---------------------------------------------------------------------------
  rf_s2m.miso <= rf_miso;

  p_spi_ref_slave : process
    variable v_rx  : std_logic_vector(31 downto 0);
    variable v_cnt : natural;
    variable v_txi : natural;

    procedure drive_next is
    begin
      if v_txi < rf_w then
        if rf_msb then
          rf_miso <= rf_tx(rf_w - 1 - v_txi);
        else
          rf_miso <= rf_tx(v_txi);
        end if;
        v_txi := v_txi + 1;
      end if;
    end procedure drive_next;
  begin
    rf_miso <= '0';
    wait until rf_m2s.cs_n = '0';
    v_rx  := (others => '0');
    v_cnt := 0;
    v_txi := 0;
    if rf_cpha = '0' then
      drive_next;                                -- first bit out when CS falls
    end if;
    loop
      wait on rf_m2s.sclk, rf_m2s.cs_n;
      exit when rf_m2s.cs_n = '1';
      if rf_m2s.sclk'event then
        -- Data is sampled on the rising edge when cpol = cpha, else on the falling one.
        if (rf_m2s.sclk = '1') = (rf_cpol = rf_cpha) then
          if v_cnt < rf_w then
            if rf_msb then
              v_rx(rf_w - 1 - v_cnt) := rf_m2s.mosi;
            else
              v_rx(v_cnt) := rf_m2s.mosi;
            end if;
            v_cnt := v_cnt + 1;
          end if;
        else
          drive_next;
        end if;
      end if;
    end loop;
    rf_rx   <= v_rx;
    rf_miso <= '0';
  end process p_spi_ref_slave;

  p_spi_ref_master : process
    variable v_cfg : t_spi_bfm_config;
    variable v_rx  : t_spi_word;
  begin
    wait until rst = '0';
    wait for 100 ns;
    for mode in 0 to 3 loop
      for w in C_SPI_WORD_CASES'range loop
        v_cfg   := make_spi_config(mode, C_SPI_WORD_CASES(w).width, C_SPI_WORD_CASES(w).msb);
        rf_cpol <= v_cfg.cpol;
        rf_cpha <= v_cfg.cpha;
        rf_w    <= v_cfg.word_width;
        rf_msb  <= v_cfg.msb_first;
        rf_tx   <= C_SPI_S_WORD;
        wait for 10 ns;
        spi_master_transfer(C_SPI_M_WORD, v_rx, "mode " & integer'image(mode)
                            & " width " & integer'image(v_cfg.word_width),
                            rf_m2s, rf_s2m, C_SCOPE, v_cfg);
        wait for 1 ns;
        bfm_check_value(v_rx and mask(v_cfg.word_width), C_SPI_S_WORD and mask(v_cfg.word_width),
                        "master BFM receives the reference slave word, mode " & integer'image(mode)
                        & " width " & integer'image(v_cfg.word_width), C_SCOPE);
        bfm_check_value(rf_rx and mask(v_cfg.word_width), C_SPI_M_WORD and mask(v_cfg.word_width),
                        "reference slave receives the master BFM word, mode " & integer'image(mode)
                        & " width " & integer'image(v_cfg.word_width), C_SCOPE);
      end loop;
    end loop;
    done(16) <= '1';
    wait;
  end process p_spi_ref_master;

  ---------------------------------------------------------------------------
  -- SPI: master BFM <-> slave BFM
  ---------------------------------------------------------------------------
  p_spi_bfm_master : process
    variable v_cfg : t_spi_bfm_config;
  begin
    wait until rst = '0';
    wait for 100 ns;
    for mode in 0 to 3 loop
      for w in C_SPI_WORD_CASES'range loop
        v_cfg := make_spi_config(mode, C_SPI_WORD_CASES(w).width, C_SPI_WORD_CASES(w).msb);
        spi_master_check(C_SPI_M_WORD, C_SPI_S_WORD, "mode " & integer'image(mode)
                         & " width " & integer'image(v_cfg.word_width),
                         bs_m2s, bs_s2m, C_SCOPE, v_cfg);
        wait for 100 ns;
      end loop;
    end loop;
    done(17) <= '1';
    wait;
  end process p_spi_bfm_master;

  p_spi_bfm_slave : process
    variable v_cfg : t_spi_bfm_config;
  begin
    for mode in 0 to 3 loop
      for w in C_SPI_WORD_CASES'range loop
        v_cfg := make_spi_config(mode, C_SPI_WORD_CASES(w).width, C_SPI_WORD_CASES(w).msb);
        spi_slave_check(C_SPI_S_WORD, C_SPI_M_WORD, "mode " & integer'image(mode)
                        & " width " & integer'image(v_cfg.word_width),
                        bs_m2s, bs_s2m, C_SCOPE, v_cfg);
      end loop;
    end loop;
    done(18) <= '1';
    wait;
  end process p_spi_bfm_slave;

  ---------------------------------------------------------------------------
  -- Verdict
  ---------------------------------------------------------------------------
  p_verdict : process
  begin
    wait until done = (done'range => '1') for 2 ms;
    if done /= (done'range => '1') then
      bfm_alert(ERROR, "timeout, blocks not finished: " & to_string(done), C_SCOPE);
    end if;
    wait for 100 ns;
    bfm_report_final(C_SCOPE);
    stop <= true;
    wait;
  end process p_verdict;

end architecture sim;
