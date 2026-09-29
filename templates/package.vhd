{{!Package + body: constants, types, functions}}
{{>header.vhd}}

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package {{pkg|$file}} is

  constant C_DATA_WIDTH : positive := 8;

  subtype data_t is std_logic_vector(C_DATA_WIDTH - 1 downto 0);

  type state_t is (S_IDLE, S_ACTIVE);

  -- Number of bits needed to address N items (clog2(1) = 0, clog2(5) = 3).
  function clog2 (n : positive) return natural;

  {{_}}

end package {{pkg}};

package body {{pkg}} is

  function clog2 (n : positive) return natural is
    variable bits  : natural  := 0;
    variable value : positive := 1;
  begin
    while value < n loop
      value := value * 2;
      bits  := bits + 1;
    end loop;
    return bits;
  end function clog2;

end package body {{pkg}};
