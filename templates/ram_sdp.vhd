{{!Simple dual-port RAM (one write port, one read port, one clock), infers block RAM}}
{{>header.vhd}}

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity {{entity|$file}} is
  generic (
    G_WIDTH      : positive := {{width|8}};
    G_ADDR_WIDTH : positive := {{addr_width|10}}
  );
  port (
    clk   : in  std_logic;
    we    : in  std_logic;
    waddr : in  unsigned(G_ADDR_WIDTH - 1 downto 0);
    wdata : in  std_logic_vector(G_WIDTH - 1 downto 0);
    raddr : in  unsigned(G_ADDR_WIDTH - 1 downto 0);
    rdata : out std_logic_vector(G_WIDTH - 1 downto 0)   -- 1 clock after raddr
  );
end entity {{entity}};

architecture rtl of {{entity}} is

  type ram_t is array (0 to 2**G_ADDR_WIDTH - 1)
    of std_logic_vector(G_WIDTH - 1 downto 0);
  signal ram : ram_t;

  -- Xilinx: "block" | "distributed" | "ultra" | "registers"
  attribute ram_style : string;
  attribute ram_style of ram : signal is "block";

  -- Intel Quartus:
  --   attribute ramstyle : string;
  --   attribute ramstyle of ram : signal is "M9K";

begin

  p_ram : process (clk)
  begin
    if rising_edge(clk) then
      if we = '1' then
        ram(to_integer(waddr)) <= wdata;
      end if;
      rdata <= ram(to_integer(raddr));   -- read-first when waddr = raddr
    end if;
  end process p_ram;
  {{_}}

end architecture rtl;
