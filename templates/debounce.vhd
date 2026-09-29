{{!Button / switch debouncer: input synchronizer + stability counter}}
{{>header.vhd}}

library ieee;
use ieee.std_logic_1164.all;

entity {{entity|$file}} is
  generic (
    G_CLK_HZ      : positive := {{clk_hz|100_000_000}};
    G_DEBOUNCE_MS : positive := {{debounce_ms|10}}   -- input must be stable this long
  );
  port (
    clk  : in  std_logic;
    rst  : in  std_logic;   -- synchronous, active high
    din  : in  std_logic;   -- raw and asynchronous (button, switch)
    dout : out std_logic    -- debounced, synchronous to clk
  );
end entity {{entity}};

architecture rtl of {{entity}} is

  constant C_LIMIT : positive := G_CLK_HZ / 1000 * G_DEBOUNCE_MS;

  signal sync   : std_logic_vector(1 downto 0) := (others => '0');
  signal stable : std_logic := '0';
  signal cnt    : natural range 0 to C_LIMIT := 0;

  attribute async_reg : string;
  attribute async_reg of sync : signal is "true";

begin

  p_debounce : process (clk)
  begin
    if rising_edge(clk) then
      sync <= sync(0) & din;
      if sync(1) = stable then
        cnt <= 0;                       -- no change requested
      elsif cnt = C_LIMIT then
        stable <= sync(1);              -- new value held long enough
        cnt    <= 0;
      else
        cnt <= cnt + 1;
      end if;
      if rst = '1' then
        stable <= '0';
        cnt    <= 0;
      end if;
    end if;
  end process p_debounce;

  dout <= stable;
  {{_}}

end architecture rtl;
