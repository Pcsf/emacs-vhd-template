{{!UART receiver, 8N1, mid-bit sampling, framing error flag}}
{{>header.vhd}}

library ieee;
use ieee.std_logic_1164.all;

entity {{entity|$file}} is
  generic (
    G_CLK_HZ : positive := {{clk_hz|100_000_000}};
    G_BAUD   : positive := {{baud|115_200}}
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;                        -- synchronous, active high
    rx        : in  std_logic;                        -- asynchronous serial input
    data      : out std_logic_vector(7 downto 0);
    valid     : out std_logic;                        -- one clock: data is new
    frame_err : out std_logic                         -- stop bit was not '1'
  );
end entity {{entity}};

architecture rtl of {{entity}} is

  constant C_DIV : positive := G_CLK_HZ / G_BAUD;   -- clocks per bit

  type state_t is (S_IDLE, S_START, S_DATA, S_STOP);
  signal state   : state_t := S_IDLE;
  signal cnt     : natural range 0 to C_DIV - 1 := 0;
  signal bit_idx : natural range 0 to 7 := 0;
  signal shreg   : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_sync : std_logic_vector(1 downto 0) := (others => '1');

  attribute async_reg : string;
  attribute async_reg of rx_sync : signal is "true";

begin

  assert C_DIV >= 4 report "G_CLK_HZ must be at least 4 * G_BAUD" severity failure;

  p_rx : process (clk)
  begin
    if rising_edge(clk) then
      rx_sync <= rx_sync(0) & rx;
      valid   <= '0';
      case state is
        when S_IDLE =>
          cnt <= 0;
          if rx_sync(1) = '0' then              -- falling edge: start bit
            state <= S_START;
          end if;
        when S_START =>                         -- middle of the start bit
          if cnt = C_DIV / 2 - 1 then
            cnt <= 0;
            if rx_sync(1) = '0' then
              bit_idx <= 0;
              state   <= S_DATA;
            else
              state <= S_IDLE;                  -- glitch, not a start bit
            end if;
          else
            cnt <= cnt + 1;
          end if;
        when S_DATA =>                          -- middle of each data bit
          if cnt = C_DIV - 1 then
            cnt   <= 0;
            shreg <= rx_sync(1) & shreg(7 downto 1);   -- LSB first
            if bit_idx = 7 then
              state <= S_STOP;
            else
              bit_idx <= bit_idx + 1;
            end if;
          else
            cnt <= cnt + 1;
          end if;
        when S_STOP =>                          -- middle of the stop bit
          if cnt = C_DIV - 1 then
            cnt       <= 0;
            state     <= S_IDLE;
            data      <= shreg;
            valid     <= '1';
            frame_err <= not rx_sync(1);
          else
            cnt <= cnt + 1;
          end if;
      end case;
      if rst = '1' then
        state     <= S_IDLE;
        cnt       <= 0;
        valid     <= '0';
        frame_err <= '0';
      end if;
    end if;
  end process p_rx;
  {{_}}

end architecture rtl;
