-- level_sync: both polarities at three clock ratios (source much faster,
-- source much slower, nearly equal).  Each case sends pulses from 1 to 300
-- source cycles and a burst that ignores src_busy, and checks that the
-- output follows the input and that every pulse is delivered or flagged.
-- Run by `make check'.

library ieee;
use ieee.std_logic_1164.all;

entity tb_level_sync_case is
  generic (
    G_ACTIVE_LEVEL : std_logic := '1';
    G_T_SRC_PS     : positive  := 2000;   -- src_clk period in ps
    G_T_DST_PS     : positive  := 37000   -- dst_clk period in ps
  );
  port (
    done : out boolean
  );
end entity tb_level_sync_case;

architecture sim of tb_level_sync_case is

  constant C_ACT  : std_logic := G_ACTIVE_LEVEL;
  constant C_IDLE : std_logic := not G_ACTIVE_LEVEL;
  constant T_SRC  : time := G_T_SRC_PS * 1 ps;
  constant T_DST  : time := G_T_DST_PS * 1 ps;
  -- Upper bound on the handshake round trip with 2 synchronizer stages.
  constant T_RT   : time := 5 * (T_SRC + T_DST);

  type t_ints  is array (natural range <>) of positive;
  type t_times is array (0 to 63) of time;
  -- Input pulse widths in src_clk cycles, short to far beyond T_RT.
  constant C_WIDTHS : t_ints := (1, 2, 3, 4, 6, 9, 14, 20, 35, 60, 100, 160, 300);

  signal src_clk, dst_clk : std_logic := '0';
  signal src_rst          : std_logic := '1';
  signal src_level        : std_logic := C_IDLE;
  signal busy, drop       : std_logic;
  signal dst_level        : std_logic;
  signal done_i           : boolean := false;

  signal n_dst  : natural := 0;                    -- completed output pulses
  signal out_w  : t_times := (others => 0 ns);     -- their widths
  signal n_drop : natural := 0;
  signal errors : natural := 0;

begin

  done <= done_i;

  src_clk <= not src_clk after T_SRC / 2 when not done_i else '0';
  dst_clk <= not dst_clk after T_DST / 2 when not done_i else '0';

  dut : entity work.level_sync
    generic map (G_STAGES => 2, G_ACTIVE_LEVEL => G_ACTIVE_LEVEL)
    port map (
      src_clk => src_clk, src_rst => src_rst, src_level => src_level,
      src_busy => busy, src_drop => drop,
      dst_clk => dst_clk, dst_level => dst_level);

  -- Count output pulses and record how long each one stayed active.
  p_mon_dst : process (dst_clk)
    variable run : natural := 0;
  begin
    if rising_edge(dst_clk) then
      if dst_level /= C_ACT and dst_level /= C_IDLE then
        report "dst_level not a clean level" severity error;
        errors <= errors + 1;
      end if;
      if dst_level = C_ACT then
        run := run + 1;
      elsif run > 0 then
        if n_dst <= t_times'high then
          out_w(n_dst) <= run * T_DST;
        end if;
        n_dst <= n_dst + 1;
        run   := 0;
      end if;
    end if;
  end process;

  p_mon_src : process (src_clk)
  begin
    if rising_edge(src_clk) and drop = '1' then
      n_drop <= n_drop + 1;
    end if;
  end process;

  p_stim : process
    variable n_sent : natural := 0;
    variable fails  : natural := 0;
    variable w_in   : time;

    procedure tick_src (n : positive := 1) is
    begin
      for i in 1 to n loop
        wait until rising_edge(src_clk);
      end loop;
    end procedure;

    procedure tick_dst (n : positive := 1) is
    begin
      for i in 1 to n loop
        wait until rising_edge(dst_clk);
      end loop;
    end procedure;

    -- One pulse: active for 'width' src cycles, then idle for 'gap'.
    procedure send (width : positive; gap : positive := 1) is
    begin
      src_level <= C_ACT;
      tick_src(width);
      src_level <= C_IDLE;
      tick_src(gap);
      n_sent := n_sent + 1;
    end procedure;

    -- Long enough for anything in flight to land on both sides.
    procedure settle is
    begin
      tick_src(8);
      tick_dst(8);
      tick_src;
      while busy /= '0' loop
        tick_src;
      end loop;
      tick_dst(4);
    end procedure;

    procedure check (cond : boolean; msg : string) is
    begin
      if not cond then
        report msg severity error;
        fails := fails + 1;
      end if;
    end procedure;

  begin
    tick_src(4);
    tick_dst(4);
    src_rst <= '0';

    -- 1. Idle input after reset: no output pulse.
    settle;
    check(n_dst = 0, "spurious pulse after reset");

    -- 2. Separated pulses: each arrives once; a pulse longer than the
    --    round trip keeps its width to within one dst_clk cycle; a shorter
    --    one lasts at least one dst_clk cycle and at most the round trip.
    for i in C_WIDTHS'range loop
      settle;
      send(C_WIDTHS(i));
    end loop;
    settle;
    check(n_drop = 0, "drop flagged on separated pulses");
    check(n_dst = n_sent,
          "separated pulses: sent " & integer'image(n_sent) &
          ", received " & integer'image(n_dst));
    for i in C_WIDTHS'range loop
      w_in := C_WIDTHS(i) * T_SRC;
      check(out_w(i) >= T_DST, "pulse " & integer'image(i) &
            " shorter than one dst_clk cycle");
      if w_in >= T_RT then
        check(abs (out_w(i) - w_in) <= T_DST,
              "pulse " & integer'image(i) & " in " & time'image(w_in) &
              ", out " & time'image(out_w(i)));
      else
        check(out_w(i) >= w_in - T_DST and out_w(i) <= T_RT + 2 * T_DST,
              "short pulse " & integer'image(i) & " in " & time'image(w_in) &
              ", out " & time'image(out_w(i)));
      end if;
    end loop;

    -- 3. Pulses and gaps of 1 to 3 src cycles, ignoring busy: each one is
    --    either a separate output pulse or flagged by drop.
    for i in 0 to 39 loop
      send(1 + i mod 3, 1 + (i / 3) mod 3);
    end loop;
    settle;
    check(n_dst + n_drop = n_sent,
          "burst: sent " & integer'image(n_sent) & ", received " &
          integer'image(n_dst) & ", dropped " & integer'image(n_drop));

    -- 4. Reset with the input idle: no output pulse, and the link still
    --    works afterwards.
    src_rst <= '1';
    tick_src(5);
    src_rst <= '0';
    settle;
    check(n_dst + n_drop = n_sent, "pulse from a reset");
    send(3);
    settle;
    check(n_dst + n_drop = n_sent, "link dead after reset");

    -- 5. An input already active when src_rst releases is one pulse.
    --    While src_rst is held the output stays idle.
    src_rst   <= '1';
    src_level <= C_ACT;
    tick_src(8);
    tick_dst(12);
    check(dst_level = C_IDLE, "output active while src_rst is held");
    tick_src;
    src_rst   <= '0';
    tick_src(4);
    src_level <= C_IDLE;
    n_sent := n_sent + 1;
    settle;
    check(n_dst + n_drop = n_sent, "input active across reset release lost");

    -- 6. Input held active: the output goes idle while src_rst is
    --    asserted and comes back when it releases.
    src_level <= C_ACT;
    tick_src(8);
    tick_dst(12);
    check(dst_level = C_ACT, "output not active while the input is held");
    src_rst <= '1';
    tick_src(8);
    tick_dst(12);
    check(dst_level = C_IDLE, "output active while src_rst is asserted");
    tick_src;
    src_rst <= '0';
    tick_src(8);
    tick_dst(12);
    check(dst_level = C_ACT, "output did not return after src_rst");
    tick_src;
    src_level <= C_IDLE;
    n_sent := n_sent + 2;   -- one input pulse, split in two by the reset
    settle;
    check(dst_level = C_IDLE, "output stuck active");
    check(n_dst + n_drop = n_sent, "held input: wrong pulse count");

    fails := fails + errors;
    done_i <= true;
    if fails = 0 then
      report "level_sync PASS active=" & std_logic'image(G_ACTIVE_LEVEL) &
             " Tsrc=" & integer'image(G_T_SRC_PS) & "ps Tdst=" &
             integer'image(G_T_DST_PS) & "ps sent=" & integer'image(n_sent) &
             " received=" & integer'image(n_dst) &
             " dropped=" & integer'image(n_drop) &
             " out_width(1 src cycle)=" & time'image(out_w(0)) &
             " out_width(300 src cycles)=" & time'image(out_w(C_WIDTHS'high));
    else
      report "level_sync FAIL: " & integer'image(fails) & " check(s)" severity failure;
    end if;
    wait;
  end process;

end architecture sim;

library ieee;
use ieee.std_logic_1164.all;

entity tb_level_sync is
end entity tb_level_sync;

architecture sim of tb_level_sync is

  type t_periods is array (0 to 2) of positive;
  constant C_T_SRC_PS : t_periods := (2000, 37000, 10000);
  constant C_T_DST_PS : t_periods := (37000, 2000, 10300);

  type t_done is array (0 to 5) of boolean;
  signal done : t_done;

begin

  g_case : for i in 0 to 2 generate
    u_hi : entity work.tb_level_sync_case
      generic map (G_ACTIVE_LEVEL => '1',
                   G_T_SRC_PS => C_T_SRC_PS(i), G_T_DST_PS => C_T_DST_PS(i))
      port map (done => done(2 * i));
    u_lo : entity work.tb_level_sync_case
      generic map (G_ACTIVE_LEVEL => '0',
                   G_T_SRC_PS => C_T_SRC_PS(i), G_T_DST_PS => C_T_DST_PS(i))
      port map (done => done(2 * i + 1));
  end generate g_case;

  -- A failing case stops the run with severity failure before this point.
  p_end : process
  begin
    for i in done'range loop
      if not done(i) then
        wait until done(i);
      end if;
    end loop;
    report "TEST PASSED";
    wait;
  end process p_end;

end architecture sim;
