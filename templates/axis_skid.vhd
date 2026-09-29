{{!AXI4-Stream register slice (skid buffer): registered data and ready, full throughput}}
{{>header.vhd}}

-- Breaks the combinational path from m_tready to s_tready and registers the
-- data path, without losing throughput.  Two storage words: the output
-- register and the skid register that catches a word when the sink stalls.

library ieee;
use ieee.std_logic_1164.all;

entity {{entity|$file}} is
  generic (
    G_WIDTH : positive := {{width|8}}
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;                            -- synchronous, active high
    -- slave (input) side
    s_tdata  : in  std_logic_vector(G_WIDTH - 1 downto 0);
    s_tlast  : in  std_logic;
    s_tvalid : in  std_logic;
    s_tready : out std_logic;
    -- master (output) side
    m_tdata  : out std_logic_vector(G_WIDTH - 1 downto 0);
    m_tlast  : out std_logic;
    m_tvalid : out std_logic;
    m_tready : in  std_logic
  );
end entity {{entity}};

architecture rtl of {{entity}} is
  -- tlast is stored together with tdata: (G_WIDTH) = tlast.
  signal o_word  : std_logic_vector(G_WIDTH downto 0) := (others => '0');
  signal k_word  : std_logic_vector(G_WIDTH downto 0) := (others => '0');
  signal o_valid : std_logic := '0';
  signal k_valid : std_logic := '0';
begin

  s_tready <= not k_valid;          -- registered: skid register is empty
  m_tdata  <= o_word(G_WIDTH - 1 downto 0);
  m_tlast  <= o_word(G_WIDTH);
  m_tvalid <= o_valid;

  p_skid : process (clk)
    variable o_free : boolean;
  begin
    if rising_edge(clk) then
      o_free := (o_valid = '0') or (m_tready = '1');
      if k_valid = '1' then                       -- stalled word goes first
        if o_free then
          o_word  <= k_word;
          o_valid <= '1';
          k_valid <= '0';
        end if;
      elsif s_tvalid = '1' then                   -- s_tready is high here
        if o_free then
          o_word  <= s_tlast & s_tdata;
          o_valid <= '1';
        else
          k_word  <= s_tlast & s_tdata;           -- sink stalled: park it
          k_valid <= '1';
        end if;
      elsif o_free then
        o_valid <= '0';
      end if;
      if rst = '1' then
        o_valid <= '0';
        k_valid <= '0';
      end if;
    end if;
  end process p_skid;
  {{_}}

end architecture rtl;
