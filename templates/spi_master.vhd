{{!SPI master, mode 0 (CPOL=0, CPHA=0), 8 bits MSB first, start/busy/done handshake}}
{{>header.vhd}}

-- SCLK = clk / (2 * G_CLK_DIV).  MISO goes through a 2-flop synchronizer, so
-- keep G_CLK_DIV >= 4.  For other modes change the edge on which `rx_sh`
-- samples and `mosi_r` shifts; for wider words change the 7s.

library ieee;
use ieee.std_logic_1164.all;

entity {{entity|$file}} is
  generic (
    G_CLK_DIV : positive range 4 to 65535 := {{clk_div|50}}
  );
  port (
    clk     : in  std_logic;
    rst     : in  std_logic;                        -- synchronous, active high
    start   : in  std_logic;                        -- one clock, ignored while busy
    tx_data : in  std_logic_vector(7 downto 0);
    busy    : out std_logic;
    rx_data : out std_logic_vector(7 downto 0);     -- valid when done pulses
    done    : out std_logic;                        -- one clock
    sclk    : out std_logic;
    mosi    : out std_logic;
    miso    : in  std_logic;
    cs_n    : out std_logic
  );
end entity {{entity}};

architecture rtl of {{entity}} is

  type state_t is (S_IDLE, S_LOW, S_HIGH, S_END);
  signal state     : state_t := S_IDLE;
  signal cnt       : natural range 0 to G_CLK_DIV - 1 := 0;
  signal bit_cnt   : natural range 0 to 7 := 0;
  signal tx_sh     : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_sh     : std_logic_vector(7 downto 0) := (others => '0');
  signal miso_sync : std_logic_vector(1 downto 0) := (others => '0');
  signal sclk_r    : std_logic := '0';
  signal mosi_r    : std_logic := '0';
  signal cs_n_r    : std_logic := '1';

  attribute async_reg : string;
  attribute async_reg of miso_sync : signal is "true";

begin

  p_spi : process (clk)
  begin
    if rising_edge(clk) then
      miso_sync <= miso_sync(0) & miso;
      done      <= '0';
      case state is
        when S_IDLE =>
          sclk_r <= '0';
          cnt    <= 0;
          if start = '1' then
            tx_sh   <= tx_data;
            mosi_r  <= tx_data(7);              -- first bit set up before SCLK rises
            cs_n_r  <= '0';
            bit_cnt <= 0;
            state   <= S_LOW;
          end if;
        when S_LOW =>                           -- SCLK low; ends with the rising edge
          if cnt = G_CLK_DIV - 1 then
            cnt    <= 0;
            sclk_r <= '1';
            rx_sh  <= rx_sh(6 downto 0) & miso_sync(1);   -- sample on the rising edge
            state  <= S_HIGH;
          else
            cnt <= cnt + 1;
          end if;
        when S_HIGH =>                          -- SCLK high; ends with the falling edge
          if cnt = G_CLK_DIV - 1 then
            cnt    <= 0;
            sclk_r <= '0';
            if bit_cnt = 7 then
              state <= S_END;
            else
              bit_cnt <= bit_cnt + 1;
              tx_sh   <= tx_sh(6 downto 0) & '0';
              mosi_r  <= tx_sh(6);              -- shift on the falling edge
              state   <= S_LOW;
            end if;
          else
            cnt <= cnt + 1;
          end if;
        when S_END =>                           -- hold CS low one more half period
          if cnt = G_CLK_DIV - 1 then
            cnt     <= 0;
            cs_n_r  <= '1';
            rx_data <= rx_sh;
            done    <= '1';
            state   <= S_IDLE;
          else
            cnt <= cnt + 1;
          end if;
      end case;
      if rst = '1' then
        state  <= S_IDLE;
        sclk_r <= '0';
        cs_n_r <= '1';
        done   <= '0';
      end if;
    end if;
  end process p_spi;

  busy <= '0' when state = S_IDLE else '1';
  sclk <= sclk_r;
  mosi <= mosi_r;
  cs_n <= cs_n_r;
  {{_}}

end architecture rtl;
