{{!Modulo-N counter with enable, synchronous reset and wrap strobe}}
{{>header.vhd}}

library ieee;
use ieee.std_logic_1164.all;

entity {{entity|$file}} is
  generic (
    G_MODULO : positive := {{modulo|10}}
  );
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;                             -- synchronous, active high
    en    : in  std_logic;
    count : out natural range 0 to G_MODULO - 1;
    tick  : out std_logic := '0'                       -- 1 clock, when count wrapped
  );
end entity {{entity}};

architecture rtl of {{entity}} is
  signal cnt : natural range 0 to G_MODULO - 1 := 0;
begin

  p_cnt : process (clk)
  begin
    if rising_edge(clk) then
      tick <= '0';
      if rst = '1' then
        cnt <= 0;
      elsif en = '1' then
        if cnt = G_MODULO - 1 then
          cnt  <= 0;
          tick <= '1';
        else
          cnt <= cnt + 1;
        end if;
      end if;
    end if;
  end process p_cnt;

  count <= cnt;
  {{_}}

end architecture rtl;
