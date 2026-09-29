{{!CDC: reset synchronizer, asserts asynchronously, releases synchronously}}
{{>header.vhd}}

library ieee;
use ieee.std_logic_1164.all;

entity {{entity|$file}} is
  generic (
    G_STAGES : positive range 2 to 8 := 2
  );
  port (
    clk  : in  std_logic;
    arst : in  std_logic;   -- asynchronous reset in, active high
    srst : out std_logic    -- reset synchronous to clk, active high
  );
end entity {{entity}};

architecture rtl of {{entity}} is

  signal sync : std_logic_vector(G_STAGES - 1 downto 0) := (others => '1');

  attribute async_reg : string;
  attribute async_reg of sync : signal is "true";

begin

  p_sync : process (clk, arst)
  begin
    if arst = '1' then
      sync <= (others => '1');
    elsif rising_edge(clk) then
      sync <= sync(G_STAGES - 2 downto 0) & '0';
    end if;
  end process p_sync;

  srst <= sync(G_STAGES - 1);

end architecture rtl;
