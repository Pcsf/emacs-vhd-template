{{!Synchronous FIFO, single clock, block-RAM friendly (read data valid one clock after rd_en)}}
{{>header.vhd}}

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity {{entity|$file}} is
  generic (
    G_WIDTH      : positive := {{width|8}};
    G_DEPTH_LOG2 : positive := {{depth_log2|4}}          -- depth = 2**G_DEPTH_LOG2
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;                            -- synchronous, active high
    wr_en    : in  std_logic;                            -- ignored when full
    wr_data  : in  std_logic_vector(G_WIDTH - 1 downto 0);
    rd_en    : in  std_logic;                            -- ignored when empty
    rd_data  : out std_logic_vector(G_WIDTH - 1 downto 0);
    rd_valid : out std_logic := '0';                     -- rd_data is valid
    full     : out std_logic;
    empty    : out std_logic
  );
end entity {{entity}};

architecture rtl of {{entity}} is

  type ram_t is array (0 to 2**G_DEPTH_LOG2 - 1)
    of std_logic_vector(G_WIDTH - 1 downto 0);
  signal ram : ram_t;

  -- One extra pointer bit tells "full" from "empty".
  signal wr_ptr : unsigned(G_DEPTH_LOG2 downto 0) := (others => '0');
  signal rd_ptr : unsigned(G_DEPTH_LOG2 downto 0) := (others => '0');

  signal full_i  : std_logic;
  signal empty_i : std_logic;
  signal do_wr   : std_logic;
  signal do_rd   : std_logic;

begin

  empty_i <= '1' when wr_ptr = rd_ptr else '0';
  full_i  <= '1' when wr_ptr(G_DEPTH_LOG2) /= rd_ptr(G_DEPTH_LOG2)
                  and wr_ptr(G_DEPTH_LOG2 - 1 downto 0)
                      = rd_ptr(G_DEPTH_LOG2 - 1 downto 0) else '0';
  do_wr   <= wr_en and not full_i;
  do_rd   <= rd_en and not empty_i;
  full    <= full_i;
  empty   <= empty_i;

  p_ptr : process (clk)
  begin
    if rising_edge(clk) then
      rd_valid <= do_rd;
      if do_wr = '1' then
        wr_ptr <= wr_ptr + 1;
      end if;
      if do_rd = '1' then
        rd_ptr <= rd_ptr + 1;
      end if;
      if rst = '1' then
        wr_ptr   <= (others => '0');
        rd_ptr   <= (others => '0');
        rd_valid <= '0';
      end if;
    end if;
  end process p_ptr;

  -- No reset here, so the tools can infer a block RAM.
  p_ram : process (clk)
  begin
    if rising_edge(clk) then
      if do_wr = '1' then
        ram(to_integer(wr_ptr(G_DEPTH_LOG2 - 1 downto 0))) <= wr_data;
      end if;
      rd_data <= ram(to_integer(rd_ptr(G_DEPTH_LOG2 - 1 downto 0)));
    end if;
  end process p_ram;
  {{_}}

end architecture rtl;
