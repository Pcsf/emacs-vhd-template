{{!ROM / lookup table filled by a function (sine table), infers block RAM}}
{{>header.vhd}}

-- Replace init_rom by your own table.  The initial value of a signal that is
-- never written is what makes Vivado and Quartus infer a ROM.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity {{entity|$file}} is
  generic (
    G_ADDR_WIDTH : positive := {{addr_width|8}};
    G_WIDTH      : positive := {{width|8}}
  );
  port (
    clk  : in  std_logic;
    addr : in  unsigned(G_ADDR_WIDTH - 1 downto 0);
    data : out std_logic_vector(G_WIDTH - 1 downto 0)    -- 1 clock after addr
  );
end entity {{entity}};

architecture rtl of {{entity}} is

  constant C_DEPTH : positive := 2**G_ADDR_WIDTH;

  type rom_t is array (0 to C_DEPTH - 1) of std_logic_vector(G_WIDTH - 1 downto 0);

  -- One sine period over the whole table, centred on mid-scale.
  function init_rom return rom_t is
    variable rom       : rom_t;
    variable amplitude : real := real(2**(G_WIDTH - 1) - 1);
    variable value     : integer;
  begin
    for i in rom'range loop
      value := 2**(G_WIDTH - 1)
               + integer(round(amplitude * sin(2.0 * MATH_PI * real(i) / real(C_DEPTH))));
      rom(i) := std_logic_vector(to_unsigned(value, G_WIDTH));
    end loop;
    return rom;
  end function init_rom;

  signal rom : rom_t := init_rom;

  attribute rom_style : string;
  attribute rom_style of rom : signal is "block";   -- Xilinx: block | distributed

begin

  p_rom : process (clk)
  begin
    if rising_edge(clk) then
      data <= rom(to_integer(addr));
    end if;
  end process p_rom;
  {{_}}

end architecture rtl;
