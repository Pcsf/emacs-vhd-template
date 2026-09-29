{{!SPI slave (any mode, MSB or LSB first, any word width), runs on the system clock}}
{{>header.vhd}}

-- The three SPI inputs are synchronized to `clk` and their edges are detected
-- there, so no SCLK-clocked logic and no extra clock domain: `clk` has to be
-- at least 4 times faster than SCLK, and the master must hold CS low for at
-- least 3 `clk` periods before the first SCLK edge.
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

  -- q(1) is the synchronized value, q(2) the one before it.
  signal sclk_q : std_logic_vector(2 downto 0) := (others => G_CPOL);
  signal cs_q   : std_logic_vector(2 downto 0) := (others => '1');
  signal mosi_q : std_logic_vector(1 downto 0) := (others => '0');

  attribute async_reg : string;
  attribute async_reg of sclk_q : signal is "true";
  attribute async_reg of cs_q   : signal is "true";
  attribute async_reg of mosi_q : signal is "true";

  signal tx_sh   : std_logic_vector(G_WIDTH - 1 downto 0) := (others => '0');
  signal rx_sh   : std_logic_vector(G_WIDTH - 1 downto 0) := (others => '0');
  signal miso_r  : std_logic := '0';
  signal bit_cnt : natural range 0 to G_WIDTH := 0;

  function reverse (v : std_logic_vector) return std_logic_vector is
    variable r : std_logic_vector(v'range);
  begin
    for i in v'range loop
      r(v'high - (i - v'low)) := v(i);
    end loop;
    return r;
  end function reverse;

  -- The shift register is MSB first; LSB-first words are reversed on the way in and out.
  function wire_order (v : std_logic_vector; msb_first : boolean) return std_logic_vector is
  begin
    if msb_first then
      return v;
    else
      return reverse(v);
    end if;
  end function wire_order;

begin

  assert G_WIDTH >= 2 report "G_WIDTH must be at least 2" severity failure;

  p_spi : process (clk)
    variable v_edge      : boolean;
    variable v_leading   : boolean;
    variable v_load      : std_logic_vector(G_WIDTH - 1 downto 0);
    variable v_rx_next   : std_logic_vector(G_WIDTH - 1 downto 0);
  begin
    if rising_edge(clk) then
      sclk_q   <= sclk_q(1 downto 0) & sclk;
      cs_q     <= cs_q(1 downto 0) & cs_n;
      mosi_q   <= mosi_q(0) & mosi;
      rx_valid <= '0';

      v_edge    := sclk_q(1) /= sclk_q(2);
      v_leading := v_edge and sclk_q(1) /= G_CPOL;   -- left the idle level

      if cs_q(1) = '1' then
        -- Not selected.
        miso_r  <= '0';
        bit_cnt <= 0;
      elsif cs_q(2) = '1' then
        -- CS just fell: load the word.
        v_load  := wire_order(tx_data, G_MSB_FIRST);
        bit_cnt <= 0;
        if G_CPHA = '0' then
          miso_r <= v_load(G_WIDTH - 1);              -- first bit before the first edge
          tx_sh  <= v_load(G_WIDTH - 2 downto 0) & '0';
        else
          tx_sh  <= v_load;                           -- first bit on the leading edge
        end if;
      elsif v_edge then
        if v_leading = (G_CPHA = '0') then
          -- Sampling edge.
          if bit_cnt < G_WIDTH then
            v_rx_next := rx_sh(G_WIDTH - 2 downto 0) & mosi_q(1);
            rx_sh     <= v_rx_next;
            bit_cnt   <= bit_cnt + 1;
            if bit_cnt = G_WIDTH - 1 then
              rx_data  <= wire_order(v_rx_next, G_MSB_FIRST);
              rx_valid <= '1';
            end if;
          end if;
        else
          -- Shifting edge.
          miso_r <= tx_sh(G_WIDTH - 1);
          tx_sh  <= tx_sh(G_WIDTH - 2 downto 0) & '0';
        end if;
      end if;

      if rst = '1' then
        miso_r   <= '0';
        bit_cnt  <= 0;
        rx_valid <= '0';
      end if;
    end if;
  end process p_spi;

  gen_tristate : if G_MISO_TRISTATE generate
    miso <= miso_r when cs_q(1) = '0' else 'Z';
  end generate gen_tristate;

  gen_driven : if not G_MISO_TRISTATE generate
    miso <= miso_r;
  end generate gen_driven;

  active <= not cs_q(1);
  {{_}}

end architecture rtl;
