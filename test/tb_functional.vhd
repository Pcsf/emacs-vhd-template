-- Functional checks of the rendered templates: counter, FIFO, two-process
-- module, edge detector, synchronizers.  Run by `make check'.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.two_process_pkg.all;

entity tb_functional is
end entity tb_functional;

architecture sim of tb_functional is

  constant C_PERIOD : time := 10 ns;

  signal clk  : std_logic := '0';
  signal rst  : std_logic := '1';
  signal stop : boolean   := false;

  -- counter
  signal cnt_count : natural range 0 to 3;
  signal cnt_tick  : std_logic;

  -- fifo
  signal wr_en, rd_en, rd_valid, full, empty : std_logic := '0';
  signal wr_data, rd_data : std_logic_vector(7 downto 0) := (others => '0');

  -- two-process module
  signal tp_in  : two_process_in_type;
  signal tp_out : two_process_out_type;

  -- edge detector, synchronizers
  signal ed_in, ed_rise, ed_fall, ed_both : std_logic := '0';
  signal sync_in, sync_out : std_logic := '0';
  signal arst, srst : std_logic := '1';

  signal errors : natural := 0;

  procedure expect (signal counter : inout natural;
                    condition      : boolean;
                    message        : string) is
  begin
    if not condition then
      counter <= counter + 1;
      report "CHECK FAILED: " & message severity error;
    end if;
  end procedure expect;

begin

  clk <= not clk after C_PERIOD / 2 when not stop;

  u_counter : entity work.counter
    generic map (G_MODULO => 4)
    port map (clk => clk, rst => rst, en => '1', count => cnt_count,
              tick => cnt_tick);

  u_fifo : entity work.fifo_sync
    generic map (G_WIDTH => 8, G_DEPTH_LOG2 => 2)
    port map (clk => clk, rst => rst, wr_en => wr_en, wr_data => wr_data,
              rd_en => rd_en, rd_data => rd_data, rd_valid => rd_valid,
              full => full, empty => empty);

  u_two_process : entity work.two_process
    port map (clk => clk, rst => rst, ctli => tp_in, ctlo => tp_out);

  u_edge_rise : entity work.edge_detect
    generic map (G_EDGE => "RISING")
    port map (clk => clk, din => ed_in, pulse => ed_rise);
  u_edge_fall : entity work.edge_detect
    generic map (G_EDGE => "FALLING")
    port map (clk => clk, din => ed_in, pulse => ed_fall);
  u_edge_both : entity work.edge_detect
    generic map (G_EDGE => "BOTH")
    port map (clk => clk, din => ed_in, pulse => ed_both);

  u_sync : entity work.sync_2ff
    port map (clk => clk, d => sync_in, q => sync_out);

  u_reset_sync : entity work.reset_sync
    port map (clk => clk, arst => arst, srst => srst);

  p_test : process
    procedure tick (n : positive := 1) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk);
      end loop;
      wait for C_PERIOD / 10;
    end procedure tick;
  begin
    tp_in.start <= '0';

    -- reset synchronizer: asserted asynchronously, released after 2 clocks
    wait for 3 ns;
    expect(errors, srst = '1', "srst asserted while arst is high");
    arst <= '0';
    tick;
    expect(errors, srst = '1', "srst still asserted after 1 clock");
    tick;
    expect(errors, srst = '0', "srst released after 2 clocks");
    rst <= '0';

    -- counter: 0 1 2 3 0, tick with the wrap
    tick;
    tick(3);
    expect(errors, cnt_count = 0 and cnt_tick = '1',
           "counter wrapped and pulsed tick");
    tick;
    expect(errors, cnt_count = 1 and cnt_tick = '0', "counter counts on");

    -- edge detector: rising, then falling
    ed_in <= '1';               -- pulse is combinational: high until the edge
    wait for 1 ns;
    expect(errors, ed_rise = '1' and ed_fall = '0' and ed_both = '1',
           "rising edge detected");
    tick;
    expect(errors, ed_rise = '0' and ed_both = '0', "pulse lasts one clock");
    ed_in <= '0';
    wait for 1 ns;
    expect(errors, ed_fall = '1' and ed_rise = '0' and ed_both = '1',
           "falling edge detected");
    tick;
    expect(errors, ed_fall = '0' and ed_both = '0', "falling pulse ends");

    -- synchronizer: 2 clocks of latency
    sync_in <= '1';
    tick;
    expect(errors, sync_out = '0', "sync_2ff output delayed (1)");
    tick;
    expect(errors, sync_out = '1', "sync_2ff output after 2 clocks");

    -- FIFO: write 4 words, full, read them back in order
    for i in 1 to 4 loop
      wr_data <= std_logic_vector(to_unsigned(i * 16, 8));
      wr_en   <= '1';
      tick;
    end loop;
    wr_en <= '0';
    expect(errors, full = '1' and empty = '0', "FIFO full after 4 writes");
    wr_data <= x"FF";
    wr_en   <= '1';
    tick;                       -- write to a full FIFO must be ignored
    wr_en <= '0';
    for i in 1 to 4 loop
      rd_en <= '1';
      tick;
      rd_en <= '0';
      expect(errors, rd_valid = '1', "rd_valid follows rd_en");
      expect(errors, rd_data = std_logic_vector(to_unsigned(i * 16, 8)),
             "FIFO returns data in order");
    end loop;
    tick;
    expect(errors, empty = '1' and full = '0', "FIFO empty after 4 reads");
    expect(errors, rd_valid = '0', "rd_valid low without rd_en");

    -- two-process module: start, run 256 clocks, done, back to idle
    tp_in.start <= '1';
    tick;
    tp_in.start <= '0';
    expect(errors, tp_out.busy = '1', "busy after start");
    tick(256);
    expect(errors, tp_out.done = '1' and tp_out.busy = '0',
           "done after 256 clocks");
    tick;
    expect(errors, tp_out.done = '0' and tp_out.busy = '0', "back to idle");

    if errors = 0 then
      report "TEST PASSED";
    else
      report "TEST FAILED: " & integer'image(errors) & " error(s)"
        severity failure;
    end if;
    stop <= true;
    wait;
  end process p_test;

end architecture sim;
