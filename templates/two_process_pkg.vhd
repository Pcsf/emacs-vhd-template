{{!Two-process style (1/2): port records and component package}}
{{>header.vhd}}

library ieee;
use ieee.std_logic_1164.all;

package {{entity|$stem}}_pkg is

  type {{entity}}_in_type is record
    start : std_logic;
  end record {{entity}}_in_type;

  type {{entity}}_out_type is record
    busy : std_logic;
    done : std_logic;
  end record {{entity}}_out_type;

  component {{entity}} is
    port (
      clk    : in  std_logic;
      rst    : in  std_logic;
      {{iface|ctl}}i : in  {{entity}}_in_type;
      {{iface}}o : out {{entity}}_out_type
    );
  end component {{entity}};

end package {{entity}}_pkg;
