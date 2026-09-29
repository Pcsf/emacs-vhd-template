{{!Delay line: fixed number of stages, enable, no reset (maps to SRL / shift-register RAM)}}
{{>header.vhd}}

library ieee;
use ieee.std_logic_1164.all;

entity {{entity|$file}} is
  generic (
    G_WIDTH : positive := {{width|8}};
    G_DEPTH : positive := {{depth|4}}      -- delay in enabled clock cycles
  );
  port (
    clk  : in  std_logic;
    en   : in  std_logic;
    din  : in  std_logic_vector(G_WIDTH - 1 downto 0);
    dout : out std_logic_vector(G_WIDTH - 1 downto 0)
  );
end entity {{entity}};

architecture rtl of {{entity}} is

  type sr_t is array (0 to G_DEPTH - 1) of std_logic_vector(G_WIDTH - 1 downto 0);
  signal sr : sr_t := (others => (others => '0'));

  -- A reset would prevent the SRL mapping: leave it out.
  -- Xilinx: attribute shreg_extract of sr : signal is "no";  keeps it in flops.

begin

  p_shift : process (clk)
  begin
    if rising_edge(clk) then
      if en = '1' then
        sr <= din & sr(0 to G_DEPTH - 2);
      end if;
    end if;
  end process p_shift;

  dout <= sr(G_DEPTH - 1);
  {{_}}

end architecture rtl;
