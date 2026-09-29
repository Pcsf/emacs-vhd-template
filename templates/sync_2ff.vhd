{{!CDC: N-flop synchronizer for a single-bit level (marked ASYNC_REG)}}
{{>header.vhd}}

-- Only for single-bit signals that change slowly compared to `clk`.  For
-- buses use a Gray-coded async FIFO or a req/ack handshake, never one
-- synchronizer per bit.  Constrain the path into `sync(0)` with
-- set_false_path or set_max_delay -datapath_only (see the XDC/SDC templates).

library ieee;
use ieee.std_logic_1164.all;

entity {{entity|$file}} is
  generic (
    G_STAGES : positive range 2 to 8 := 2;
    G_INIT   : std_logic             := '0'
  );
  port (
    clk : in  std_logic;   -- destination clock
    d   : in  std_logic;   -- asynchronous input
    q   : out std_logic    -- input, synchronous to clk
  );
end entity {{entity}};

architecture rtl of {{entity}} is

  signal sync : std_logic_vector(G_STAGES - 1 downto 0) := (others => G_INIT);

  -- Xilinx: keep the flops together and treat them as a synchronizer.
  attribute async_reg : string;
  attribute async_reg of sync : signal is "true";

  -- Intel Quartus:
  --   attribute altera_attribute : string;
  --   attribute altera_attribute of rtl : architecture is
  --     "-name SYNCHRONIZER_IDENTIFICATION ""FORCED IF ASYNCHRONOUS""";

begin

  -- No reset on purpose: it would add a second asynchronous path.
  p_sync : process (clk)
  begin
    if rising_edge(clk) then
      sync <= sync(G_STAGES - 2 downto 0) & d;
    end if;
  end process p_sync;

  q <= sync(G_STAGES - 1);

end architecture rtl;
