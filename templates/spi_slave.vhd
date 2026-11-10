{{!SPI slave on the system clock: any mode, any width, MSB or LSB first; two-process style}}
{{+sync_2ff}}
{{>header.vhd}}

-- The three SPI inputs are synchronized to `clk` and their edges are detected
-- there, so no SCLK-clocked logic and no extra clock domain.  MISO changes up
-- to 3 `clk` periods after the CS or SCLK edge that causes it, so half an SCLK
-- period, and the time from CS falling to the first SCLK edge, must both
-- exceed 3 `clk` periods plus the MISO output and board delay and the
-- master's setup time.  `clk` at least 8 times SCLK leaves one `clk` period
-- for those delays.
--
-- tx_data is taken when CS falls (it must be stable then); it is shifted out
-- on MISO.  When G_WIDTH bits have been received, rx_data holds them and
-- rx_valid pulses for one clock.  A frame that ends early (CS rises before
-- G_WIDTH bits) produces no rx_valid; clocks beyond G_WIDTH are ignored.
--
-- Mode: G_CPOL is the idle level of SCLK.  With G_CPHA '0' data is sampled on
-- the first (leading) edge and changes on the second, with '1' it changes on
-- the leading edge and is sampled on the second.
--
-- Constraints: the SPI pins are asynchronous inputs to `clk`; add
-- set_false_path (or input delays for a known SCLK) for sclk, cs_n and mosi.

library ieee;
use ieee.std_logic_1164.all;

entity {{entity|$file}} is
  generic (
    G_WIDTH         : positive  := {{width|8}};
    G_CPOL          : std_logic := '{{cpol|0}}';
    G_CPHA          : std_logic := '{{cpha|0}}';
    G_MSB_FIRST     : boolean   := true;
    G_MISO_TRISTATE : boolean   := false     -- true: MISO is 'Z' while not selected
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;                            -- synchronous, active high
    -- SPI pins
    sclk     : in  std_logic;
    cs_n     : in  std_logic;
    mosi     : in  std_logic;
    miso     : out std_logic;
    -- user side
    tx_data  : in  std_logic_vector(G_WIDTH - 1 downto 0);   -- sampled when CS falls
    rx_data  : out std_logic_vector(G_WIDTH - 1 downto 0) := (others => '0');
    rx_valid : out std_logic := '0';                     -- one clock: rx_data is new
    active   : out std_logic                             -- selected (CS low)
  );
end entity {{entity}};

architecture rtl of {{entity}} is

  type reg_type is record
    sclk_d   : std_logic;                               -- sclk_s one clock ago
    cs_d     : std_logic;                               -- cs_s one clock ago
    tx_sh    : std_logic_vector(G_WIDTH - 1 downto 0);
    rx_sh    : std_logic_vector(G_WIDTH - 1 downto 0);
    rx_data  : std_logic_vector(G_WIDTH - 1 downto 0);
    rx_valid : std_logic;
    miso     : std_logic;
    bit_cnt  : natural range 0 to G_WIDTH;
  end record reg_type;

  constant REG_RESET : reg_type := (
    sclk_d   => G_CPOL,
    cs_d     => '1',
    tx_sh    => (others => '0'),
    rx_sh    => (others => '0'),
    rx_data  => (others => '0'),
    rx_valid => '0',
    miso     => '0',
    bit_cnt  => 0
  );

  signal r, rin : reg_type := REG_RESET;

  -- The SPI pins, synchronous to clk.
  signal sclk_s : std_logic;
  signal cs_s   : std_logic;
  signal mosi_s : std_logic;

  function reverse (word : std_logic_vector) return std_logic_vector is
    variable result : std_logic_vector(word'range);
  begin
    for i in word'range loop
      result(word'high - (i - word'low)) := word(i);
    end loop;
    return result;
  end function reverse;

  -- The shift register is MSB first; LSB-first words are reversed on the way in and out.
  function wire_order (word : std_logic_vector; msb_first : boolean) return std_logic_vector is
  begin
    if msb_first then
      return word;
    else
      return reverse(word);
    end if;
  end function wire_order;

begin

  assert G_WIDTH >= 2 report "G_WIDTH must be at least 2" severity failure;

  -- The pins go through synchronizer cells before they enter the record: the
  -- chains have no reset and constraints can find them by name.
  u_sync_sclk : entity work.sync_2ff
    generic map (G_STAGES => 2, G_INIT => G_CPOL)
    port map (clk => clk, d => sclk, q => sclk_s);

  u_sync_cs : entity work.sync_2ff
    generic map (G_STAGES => 2, G_INIT => '1')
    port map (clk => clk, d => cs_n, q => cs_s);

  u_sync_mosi : entity work.sync_2ff
    generic map (G_STAGES => 2, G_INIT => '0')
    port map (clk => clk, d => mosi, q => mosi_s);

  comb : process (all)
    variable v       : reg_type;
    variable edge    : boolean;                         -- SCLK changed
    variable leading : boolean;                         -- ... away from its idle level
    variable load    : std_logic_vector(G_WIDTH - 1 downto 0);
    variable rx_next : std_logic_vector(G_WIDTH - 1 downto 0);
  begin
    v          := r;
    edge       := sclk_s /= r.sclk_d;
    leading    := edge and sclk_s /= G_CPOL;
    load       := wire_order(tx_data, G_MSB_FIRST);
    rx_next    := r.rx_sh(G_WIDTH - 2 downto 0) & mosi_s;
    v.sclk_d   := sclk_s;
    v.cs_d     := cs_s;
    v.rx_valid := '0';

    if cs_s = '1' then
      -- Not selected.
      v.miso    := '0';
      v.bit_cnt := 0;
    elsif r.cs_d = '1' then
      -- CS just fell: load the word.
      v.bit_cnt := 0;
      if G_CPHA = '0' then
        v.miso  := load(G_WIDTH - 1);                   -- first bit before the first edge
        v.tx_sh := load(G_WIDTH - 2 downto 0) & '0';
      else
        v.tx_sh := load;                                -- first bit on the leading edge
      end if;
    elsif edge then
      if leading = (G_CPHA = '0') then
        -- Sampling edge.
        if r.bit_cnt < G_WIDTH then
          v.rx_sh   := rx_next;
          v.bit_cnt := r.bit_cnt + 1;
          if r.bit_cnt = G_WIDTH - 1 then
            v.rx_data  := wire_order(rx_next, G_MSB_FIRST);
            v.rx_valid := '1';
          end if;
        end if;
      else
        -- Shifting edge.
        v.miso  := r.tx_sh(G_WIDTH - 1);
        v.tx_sh := r.tx_sh(G_WIDTH - 2 downto 0) & '0';
      end if;
    end if;
    {{_}}

    if rst = '1' then                                   -- control fields only
      v.miso     := '0';
      v.bit_cnt  := 0;
      v.rx_valid := '0';
    end if;

    rin <= v;

    if G_MISO_TRISTATE and cs_s = '1' then
      miso <= 'Z';                                      -- not selected
    else
      miso <= r.miso;
    end if;
    rx_data  <= r.rx_data;
    rx_valid <= r.rx_valid;
    active   <= not cs_s;
  end process comb;

  regs : process (clk)
  begin
    if rising_edge(clk) then
      r <= rin;
    end if;
  end process regs;

end architecture rtl;
