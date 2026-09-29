{{!Testbench with BFMs for an AXI-Stream DUT: TC-numbered sequencer, sink checker, final report}}
{{>header.vhd}}

-- Needs bfm_util_pkg and bfm_axis_pkg, and a DUT with this port list (the
-- axis_skid template has it).  The sequencer drives, a separate process
-- checks: the source BFM sends packets, the sink BFM expects the same ones.
-- Add one TC block to both processes per behaviour.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.bfm_util_pkg.all;
use work.bfm_axis_pkg.all;

entity {{tb|$file}} is
end entity {{tb}};

architecture sim of {{tb}} is

  constant C_CLK_PERIOD : time   := {{period|10 ns}};
  constant C_SCOPE      : string := "{{tb}}";

  signal clk       : std_logic := '0';
  signal rst       : std_logic := '1';
  signal stop      : boolean   := false;
  signal sink_done : boolean   := false;

  signal src_m2s : t_axis_m2s := C_AXIS_M2S_INIT;   -- source BFM -> DUT
  signal src_s2m : t_axis_s2m := C_AXIS_S2M_INIT;   -- DUT -> source BFM
  signal snk_m2s : t_axis_m2s := C_AXIS_M2S_INIT;   -- DUT -> sink BFM
  signal snk_s2m : t_axis_s2m := C_AXIS_S2M_INIT;   -- sink BFM -> DUT

  -- Packet `id` of `length` beats; the sequencer and the checker both use it.
  function packet (id : natural; length : positive) return t_slv_array is
    variable p : t_slv_array(0 to length - 1)(C_AXIS_DATA_WIDTH - 1 downto 0);
  begin
    for i in p'range loop
      p(i) := std_logic_vector(to_unsigned(id * 256 + i, C_AXIS_DATA_WIDTH));
    end loop;
    return p;
  end function packet;

  -- Source with idle clocks between beats, sink with back-pressure.
  constant C_SLOW_SOURCE : t_axis_bfm_config := (max_wait_cycles => 1000, gap_cycles => 2, ready_low_cycles => 0);
  constant C_SLOW_SINK   : t_axis_bfm_config := (max_wait_cycles => 1000, gap_cycles => 0, ready_low_cycles => 3);

begin

  u_dut : entity work.{{dut|$stem}}
    generic map (
      G_WIDTH => C_AXIS_DATA_WIDTH
    )
    port map (
      clk      => clk,
      rst      => rst,
      s_tdata  => src_m2s.tdata,
      s_tlast  => src_m2s.tlast,
      s_tvalid => src_m2s.tvalid,
      s_tready => src_s2m.tready,
      m_tdata  => snk_m2s.tdata,
      m_tlast  => snk_m2s.tlast,
      m_tvalid => snk_m2s.tvalid,
      m_tready => snk_s2m.tready
    );

  p_clk : process
  begin
    while not stop loop
      clk <= '0';
      wait for C_CLK_PERIOD / 2;
      clk <= '1';
      wait for C_CLK_PERIOD / 2;
    end loop;
    wait;
  end process p_clk;

  -- Sequencer: stimulus only.
  p_sequencer : process
  begin
    bfm_log(C_LOG_HDR, "Applying reset", C_SCOPE);
    rst <= '1';
    bfm_wait_cycles(4, clk);
    rst <= '0';
    bfm_wait_cycles(1, clk);

    bfm_log(C_LOG_HDR, "TC-01: a single-beat packet passes", C_SCOPE);
    axis_transmit(packet(1, 1), "TC-01", clk, src_m2s, src_s2m, C_SCOPE);

    bfm_log(C_LOG_HDR, "TC-02: an 8-beat packet passes back to back", C_SCOPE);
    axis_transmit(packet(2, 8), "TC-02", clk, src_m2s, src_s2m, C_SCOPE);

    bfm_log(C_LOG_HDR, "TC-03: a packet with gaps on the source and back-pressure on the sink", C_SCOPE);
    axis_transmit(packet(3, 6), "TC-03", clk, src_m2s, src_s2m, C_SCOPE, C_SLOW_SOURCE);

    {{_}}

    wait until sink_done;
    bfm_wait_cycles(4, clk);
    bfm_report_final(C_SCOPE);
    stop <= true;
    wait;
  end process p_sequencer;

  -- Checker: the sink BFM compares every packet with the expected one.
  p_checker : process
  begin
    axis_expect(packet(1, 1), "TC-01", clk, snk_m2s, snk_s2m, C_SCOPE);
    axis_expect(packet(2, 8), "TC-02", clk, snk_m2s, snk_s2m, C_SCOPE);
    axis_expect(packet(3, 6), "TC-03", clk, snk_m2s, snk_s2m, C_SCOPE, C_SLOW_SINK);
    sink_done <= true;
    wait;
  end process p_checker;

  p_watchdog : process
  begin
    wait until stop for 1 ms;
    if not stop then
      bfm_alert(FAILURE, "watchdog: the test did not finish", C_SCOPE);
    end if;
    wait;
  end process p_watchdog;

end architecture sim;
