{{!CDC: asynchronous FIFO, Gray-coded pointers, separate write and read clocks}}
{{>header.vhd}}

-- Assert wr_rst and rd_rst together and long enough for both clocks.
-- Constraints (Vivado): set_max_delay -datapath_only on the Gray pointers
-- (wr_gray -> wr_gray_r1, rd_gray -> rd_gray_w1), ideally with set_bus_skew.
-- Read data is valid one rd_clk after rd_en, flagged by rd_valid.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity {{entity|$file}} is
  generic (
    G_WIDTH      : positive := {{width|8}};
    G_DEPTH_LOG2 : positive range 2 to 16 := {{depth_log2|4}}   -- depth 2**G_DEPTH_LOG2
  );
  port (
    -- write side
    wr_clk   : in  std_logic;
    wr_rst   : in  std_logic;                          -- synchronous, active high
    wr_en    : in  std_logic;                          -- ignored when full
    wr_data  : in  std_logic_vector(G_WIDTH - 1 downto 0);
    full     : out std_logic;
    -- read side
    rd_clk   : in  std_logic;
    rd_rst   : in  std_logic;                          -- synchronous, active high
    rd_en    : in  std_logic;                          -- ignored when empty
    rd_data  : out std_logic_vector(G_WIDTH - 1 downto 0);
    rd_valid : out std_logic;
    empty    : out std_logic
  );
end entity {{entity}};

architecture rtl of {{entity}} is

  constant N : positive := G_DEPTH_LOG2;

  subtype ptr_t  is unsigned(N downto 0);            -- one extra bit: full/empty
  subtype gray_t is std_logic_vector(N downto 0);

  type ram_t is array (0 to 2**N - 1) of std_logic_vector(G_WIDTH - 1 downto 0);
  signal ram : ram_t;

  function to_gray (b : ptr_t) return gray_t is
  begin
    return std_logic_vector(b xor shift_right(b, 1));
  end function to_gray;

  -- write domain
  signal wr_bin       : ptr_t  := (others => '0');
  signal wr_gray      : gray_t := (others => '0');
  signal wr_bin_next  : ptr_t;
  signal wr_gray_next : gray_t;
  signal full_r       : std_logic := '0';
  signal do_wr        : std_logic;
  signal rd_gray_w1   : gray_t := (others => '0');   -- read pointer, seen from
  signal rd_gray_w2   : gray_t := (others => '0');   -- the write domain

  -- read domain
  signal rd_bin       : ptr_t  := (others => '0');
  signal rd_gray      : gray_t := (others => '0');
  signal rd_bin_next  : ptr_t;
  signal rd_gray_next : gray_t;
  signal empty_r      : std_logic := '1';
  signal do_rd        : std_logic;
  signal wr_gray_r1   : gray_t := (others => '0');   -- write pointer, seen from
  signal wr_gray_r2   : gray_t := (others => '0');   -- the read domain

  attribute async_reg : string;
  attribute async_reg of rd_gray_w1 : signal is "true";
  attribute async_reg of rd_gray_w2 : signal is "true";
  attribute async_reg of wr_gray_r1 : signal is "true";
  attribute async_reg of wr_gray_r2 : signal is "true";

begin

  -- Write side ---------------------------------------------------------------
  do_wr        <= wr_en and not full_r;
  wr_bin_next  <= wr_bin + 1 when do_wr = '1' else wr_bin;
  wr_gray_next <= to_gray(wr_bin_next);

  p_wr : process (wr_clk)
  begin
    if rising_edge(wr_clk) then
      rd_gray_w1 <= rd_gray;
      rd_gray_w2 <= rd_gray_w1;
      wr_bin     <= wr_bin_next;
      wr_gray    <= wr_gray_next;
      -- full: write pointer caught up with the read pointer, one lap ahead
      if wr_gray_next = (not rd_gray_w2(N downto N - 1)) & rd_gray_w2(N - 2 downto 0) then
        full_r <= '1';
      else
        full_r <= '0';
      end if;
      if wr_rst = '1' then
        wr_bin     <= (others => '0');
        wr_gray    <= (others => '0');
        full_r     <= '0';
        rd_gray_w1 <= (others => '0');
        rd_gray_w2 <= (others => '0');
      end if;
    end if;
  end process p_wr;

  p_ram_wr : process (wr_clk)
  begin
    if rising_edge(wr_clk) then
      if do_wr = '1' then
        ram(to_integer(wr_bin(N - 1 downto 0))) <= wr_data;
      end if;
    end if;
  end process p_ram_wr;

  full <= full_r;

  -- Read side ----------------------------------------------------------------
  do_rd        <= rd_en and not empty_r;
  rd_bin_next  <= rd_bin + 1 when do_rd = '1' else rd_bin;
  rd_gray_next <= to_gray(rd_bin_next);

  p_rd : process (rd_clk)
  begin
    if rising_edge(rd_clk) then
      wr_gray_r1 <= wr_gray;
      wr_gray_r2 <= wr_gray_r1;
      rd_bin     <= rd_bin_next;
      rd_gray    <= rd_gray_next;
      rd_valid   <= do_rd;
      rd_data    <= ram(to_integer(rd_bin(N - 1 downto 0)));
      -- empty: read pointer equals the (synchronized) write pointer
      if rd_gray_next = wr_gray_r2 then
        empty_r <= '1';
      else
        empty_r <= '0';
      end if;
      if rd_rst = '1' then
        rd_bin     <= (others => '0');
        rd_gray    <= (others => '0');
        empty_r    <= '1';
        rd_valid   <= '0';
        wr_gray_r1 <= (others => '0');
        wr_gray_r2 <= (others => '0');
      end if;
    end if;
  end process p_rd;

  empty <= empty_r;
  {{_}}

end architecture rtl;
