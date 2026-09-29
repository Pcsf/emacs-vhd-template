{{!Multiply-accumulate with input, multiplier and accumulator registers (DSP block inference)}}
{{>header.vhd}}

-- Fully pipelined so the tools can pack it into one DSP block:
-- a, b -> a_r, b_r -> prod (M register) -> acc (P register).  Latency 3 clocks.
-- Xilinx: attribute use_dsp of rtl : architecture is "yes";  forces DSP use.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity {{entity|$file}} is
  generic (
    G_A_WIDTH   : positive := {{a_width|18}};
    G_B_WIDTH   : positive := {{b_width|18}};
    G_ACC_WIDTH : positive := {{acc_width|48}}
  );
  port (
    clk : in  std_logic;
    clr : in  std_logic;                                -- clear accumulator, sync
    a   : in  signed(G_A_WIDTH - 1 downto 0);
    b   : in  signed(G_B_WIDTH - 1 downto 0);
    acc : out signed(G_ACC_WIDTH - 1 downto 0)
  );
end entity {{entity}};

architecture rtl of {{entity}} is
  signal a_r  : signed(G_A_WIDTH - 1 downto 0)              := (others => '0');
  signal b_r  : signed(G_B_WIDTH - 1 downto 0)              := (others => '0');
  signal prod : signed(G_A_WIDTH + G_B_WIDTH - 1 downto 0)  := (others => '0');
  signal sum  : signed(G_ACC_WIDTH - 1 downto 0)            := (others => '0');
begin

  p_mac : process (clk)
  begin
    if rising_edge(clk) then
      a_r  <= a;
      b_r  <= b;
      prod <= a_r * b_r;
      if clr = '1' then
        sum <= (others => '0');
      else
        sum <= sum + resize(prod, G_ACC_WIDTH);
      end if;
    end if;
  end process p_mac;

  acc <= sum;
  {{_}}

end architecture rtl;
