{{!CDC: single-bit level follower between two clocks, any clock ratio, active high or low}}
{{+sync_2ff}}
{{>header.vhd}}

-- dst_level follows src_level: it stays at G_ACTIVE_LEVEL for as long as the
-- input does and idles at the opposite level.  No input pulse is lost,
-- however short it is against dst_clk.
--
-- The input is copied into `hold`, which crosses into dst_clk and comes back
-- to src_clk as the acknowledge.  `hold` may rise only while the acknowledge
-- is '0' and fall only while it is '1', so the destination has seen each
-- level before the next change.  One round trip is about
--   (G_STAGES + 2) dst_clk + (G_STAGES + 1) src_clk cycles.
--   * A pulse longer than the round trip keeps its width to within one
--     dst_clk cycle.
--   * A shorter pulse is stretched to about the round trip.
--   * An idle gap shorter than the round trip is widened: the next pulse
--     starts late.  One such pulse is remembered.  A further pulse arriving
--     before the remembered one has started merges into it, and src_drop
--     goes high for one src_clk cycle.
--
-- src_rst makes the input read as idle, which keeps the output idle while
-- the logic driving an active-low input is still in reset.  There is no
-- destination reset: the crossing starts from its power-up values and
-- recovers by itself from any state (FPGA targets, not ASIC).
--
-- Constraints (Vivado; u_ls is this instance):
--   set_max_delay -datapath_only -from [get_cells u_ls/hold_reg] \
--                 -to [get_cells u_ls/u_hold_sync/sync_reg[0]] <dst_clk period>
--   set_max_delay -datapath_only -from [get_cells u_ls/hold_q_reg] \
--                 -to [get_cells u_ls/u_ack_sync/sync_reg[0]] <src_clk period>

library ieee;
use ieee.std_logic_1164.all;

entity {{entity|$file}} is
  generic (
    G_STAGES       : positive range 2 to 8 := 2;
    G_ACTIVE_LEVEL : std_logic             := '{{active_level|1}}'   -- '1' active high, '0' active low
  );
  port (
    -- source domain
    src_clk   : in  std_logic;
    src_rst   : in  std_logic;   -- synchronous, active high
    src_level : in  std_logic;   -- any width >= 1 src_clk cycle
    src_busy  : out std_logic;   -- a level change is in flight
    src_drop  : out std_logic;   -- one src_clk: a pulse merged into the next
    -- destination domain
    dst_clk   : in  std_logic;
    dst_level : out std_logic
  );
end entity {{entity}};

architecture rtl of {{entity}} is

  constant C_IDLE : std_logic := not G_ACTIVE_LEVEL;

  -- source domain, all active high
  signal act    : std_logic;          -- input is at the active level
  signal act_q  : std_logic := '0';
  signal hold   : std_logic := '0';   -- level sent to the destination
  signal pend   : std_logic := '0';   -- a pulse is waiting to start
  signal ack_s  : std_logic;
  signal drop_r : std_logic := '0';

  -- destination domain
  signal hold_s  : std_logic;
  signal hold_q  : std_logic := '0';
  signal level_r : std_logic := C_IDLE;

begin

  act <= '1' when src_level = G_ACTIVE_LEVEL and src_rst = '0' else '0';

  p_src : process (src_clk)
    variable new_pulse : boolean;
  begin
    if rising_edge(src_clk) then
      new_pulse := act = '1' and act_q = '0';
      act_q     <= act;
      drop_r    <= '0';

      if hold = '0' and ack_s = '0' and (act = '1' or pend = '1') then
        hold <= '1';
        pend <= '0';
        if new_pulse and pend = '1' then
          drop_r <= '1';
        end if;
      else
        if hold = '1' and ack_s = '1' and (act = '0' or pend = '1') then
          hold <= '0';
        end if;
        if new_pulse then
          if pend = '1' then
            drop_r <= '1';
          else
            pend <= '1';
          end if;
        end if;
      end if;

      if src_rst = '1' then
        pend <= '0';
      end if;
    end if;
  end process p_src;

  u_hold_sync : entity work.sync_2ff
    generic map (G_STAGES => G_STAGES, G_INIT => '0')
    port map (clk => dst_clk, d => hold, q => hold_s);

  p_dst : process (dst_clk)
  begin
    if rising_edge(dst_clk) then
      hold_q <= hold_s;
      if hold_s = '1' then
        level_r <= G_ACTIVE_LEVEL;
      else
        level_r <= C_IDLE;
      end if;
    end if;
  end process p_dst;

  u_ack_sync : entity work.sync_2ff
    generic map (G_STAGES => G_STAGES, G_INIT => '0')
    port map (clk => src_clk, d => hold_q, q => ack_s);

  src_busy  <= hold xor ack_s;
  src_drop  <= drop_r;
  dst_level <= level_r;
  {{_}}

end architecture rtl;
