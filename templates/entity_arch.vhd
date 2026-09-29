{{!Entity + RTL architecture: generic width, clocked process, synchronous reset}}
{{>header.vhd}}

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity {{entity|$file}} is
  generic (
    G_WIDTH : positive := {{width|8}}
  );
  port (
    clk  : in  std_logic;
    rst  : in  std_logic;                              -- synchronous, active high
    din  : in  std_logic_vector(G_WIDTH - 1 downto 0);
    dout : out std_logic_vector(G_WIDTH - 1 downto 0)
  );
end entity {{entity}};

architecture rtl of {{entity}} is
  {{_}}
begin

  p_reg : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        dout <= (others => '0');
      else
        dout <= din;
      end if;
    end if;
  end process p_reg;

end architecture rtl;
