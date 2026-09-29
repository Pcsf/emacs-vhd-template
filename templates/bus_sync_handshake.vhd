{{!CDC: handshake bus synchronizer (2-phase req/ack), moves a multi-bit word between two clocks}}
{{>header.vhd}}

-- The word is frozen in `data_hold`, a request toggle crosses to the
-- destination through a 2-flop synchronizer, the destination copies the word
-- and answers with an acknowledge toggle that crosses back.  `src_ready` goes
-- high again only after the acknowledge has been seen, so `data_hold` never
-- changes while the destination may still read it.  One transfer takes about
-- 3-4 dst_clk plus 2-3 src_clk periods: use it for configuration words and
-- commands, and an async FIFO for streams.
--
-- Assert src_rst and dst_rst together (each synchronous to its own clock):
-- both toggles must agree on their idle value after reset.
--
-- Constraints (Vivado; u_hs is this instance):
--   set_max_delay -datapath_only -from [get_cells u_hs/data_hold_reg[*]] \
--                 -to [get_cells u_hs/dst_data_r_reg[*]] <dst_clk period>
--   set_bus_skew  -from [get_cells u_hs/data_hold_reg[*]] \
--                 -to [get_cells u_hs/dst_data_r_reg[*]] <half dst_clk period>
--   set_max_delay -datapath_only -from [get_cells u_hs/req_tgl_reg] \
--                 -to [get_cells u_hs/req_sync_reg[0]] <dst_clk period>
--   set_max_delay -datapath_only -from [get_cells u_hs/ack_tgl_reg] \
--                 -to [get_cells u_hs/ack_sync_reg[0]] <src_clk period>

library ieee;
use ieee.std_logic_1164.all;

entity {{entity|$file}} is
  generic (
    G_WIDTH : positive := {{width|16}}
  );
  port (
    -- source domain
    src_clk   : in  std_logic;
    src_rst   : in  std_logic;                            -- synchronous, active high
    src_data  : in  std_logic_vector(G_WIDTH - 1 downto 0);
    src_send  : in  std_logic;                            -- ignored unless src_ready
    src_ready : out std_logic;                            -- idle: a transfer may start
    -- destination domain
    dst_clk   : in  std_logic;
    dst_rst   : in  std_logic;                            -- synchronous, active high
    dst_data  : out std_logic_vector(G_WIDTH - 1 downto 0);   -- holds the last word
    dst_valid : out std_logic                             -- one dst_clk: new word
  );
end entity {{entity}};

architecture rtl of {{entity}} is

  -- source domain
  signal data_hold : std_logic_vector(G_WIDTH - 1 downto 0) := (others => '0');
  signal req_tgl   : std_logic := '0';
  signal ack_sync  : std_logic_vector(1 downto 0) := (others => '0');
  signal busy      : std_logic;

  -- destination domain
  signal req_sync    : std_logic_vector(1 downto 0) := (others => '0');
  signal ack_tgl     : std_logic := '0';
  signal dst_data_r  : std_logic_vector(G_WIDTH - 1 downto 0) := (others => '0');
  signal dst_valid_r : std_logic := '0';

  attribute async_reg : string;
  attribute async_reg of req_sync : signal is "true";
  attribute async_reg of ack_sync : signal is "true";

begin

  busy      <= req_tgl xor ack_sync(1);      -- request not yet acknowledged
  src_ready <= not busy;

  p_src : process (src_clk)
  begin
    if rising_edge(src_clk) then
      ack_sync <= ack_sync(0) & ack_tgl;
      if src_send = '1' and busy = '0' then
        data_hold <= src_data;               -- freeze the word ...
        req_tgl   <= not req_tgl;            -- ... and ask
      end if;
      if src_rst = '1' then
        req_tgl  <= '0';
        ack_sync <= (others => '0');
      end if;
    end if;
  end process p_src;

  p_dst : process (dst_clk)
  begin
    if rising_edge(dst_clk) then
      req_sync    <= req_sync(0) & req_tgl;
      dst_valid_r <= '0';
      if req_sync(1) /= ack_tgl then         -- new request
        dst_data_r  <= data_hold;            -- stable for >= 1 dst_clk by now
        dst_valid_r <= '1';
        ack_tgl     <= req_sync(1);          -- acknowledge
      end if;
      if dst_rst = '1' then
        req_sync    <= (others => '0');
        ack_tgl     <= '0';
        dst_valid_r <= '0';
      end if;
    end if;
  end process p_dst;

  dst_data  <= dst_data_r;
  dst_valid <= dst_valid_r;
  {{_}}

end architecture rtl;
