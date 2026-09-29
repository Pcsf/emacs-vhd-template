{{!UART transmitter, 8N1, valid/ready handshake}}
{{>header.vhd}}

library ieee;
use ieee.std_logic_1164.all;

entity {{entity|$file}} is
  generic (
    G_CLK_HZ : positive := {{clk_hz|100_000_000}};
    G_BAUD   : positive := {{baud|115_200}}
  );
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;                      -- synchronous, active high
    data  : in  std_logic_vector(7 downto 0);
    valid : in  std_logic;                      -- data is taken when valid and ready
    ready : out std_logic;                      -- idle, can accept a byte
    tx    : out std_logic
  );
end entity {{entity}};

architecture rtl of {{entity}} is

  constant C_DIV : positive := G_CLK_HZ / G_BAUD;   -- clocks per bit

  type state_t is (S_IDLE, S_START, S_DATA, S_STOP);
  signal state   : state_t := S_IDLE;
  signal cnt     : natural range 0 to C_DIV - 1 := 0;
  signal bit_idx : natural range 0 to 7 := 0;
  signal shreg   : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_r    : std_logic := '1';

begin

  assert C_DIV >= 2 report "G_CLK_HZ must be at least 2 * G_BAUD" severity failure;

  p_tx : process (clk)
  begin
    if rising_edge(clk) then
      -- tx_r follows the state one clock late, which gives every bit the
      -- same length of C_DIV clocks.
      case state is
        when S_IDLE =>
          tx_r <= '1';
          cnt  <= 0;
          if valid = '1' then
            shreg <= data;
            state <= S_START;
          end if;
        when S_START =>
          tx_r <= '0';
          if cnt = C_DIV - 1 then
            cnt     <= 0;
            bit_idx <= 0;
            state   <= S_DATA;
          else
            cnt <= cnt + 1;
          end if;
        when S_DATA =>
          tx_r <= shreg(bit_idx);               -- LSB first
          if cnt = C_DIV - 1 then
            cnt <= 0;
            if bit_idx = 7 then
              state <= S_STOP;
            else
              bit_idx <= bit_idx + 1;
            end if;
          else
            cnt <= cnt + 1;
          end if;
        when S_STOP =>
          tx_r <= '1';
          if cnt = C_DIV - 1 then
            cnt   <= 0;
            state <= S_IDLE;
          else
            cnt <= cnt + 1;
          end if;
      end case;
      if rst = '1' then
        state <= S_IDLE;
        tx_r  <= '1';
        cnt   <= 0;
      end if;
    end if;
  end process p_tx;

  ready <= '1' when state = S_IDLE else '0';
  tx    <= tx_r;
  {{_}}

end architecture rtl;
