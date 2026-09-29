{{!I2C slave: 7-bit address, byte interface with read requests, runs on the system clock}}
{{>header.vhd}}

-- SCL and SDA are synchronized to `clk` and their edges detected there, so
-- there is no SCL-clocked logic: `clk` has to be at least 8 times faster than
-- SCL.  The slave never stretches the clock.
--
-- Write from the master:  addr_match pulses (is_read = '0'), then every byte
--   arrives as rx_data with a rx_valid pulse.  All bytes are acknowledged.
-- Read by the master:     addr_match pulses (is_read = '1') and tx_req pulses.
--   Put the byte to send on tx_data within one SCL high time; it is taken
--   when SCL falls after the acknowledge.  tx_req pulses again after every
--   byte the master acknowledges; a NACK ends the read.
-- start_evt / stop_evt pulse on every START (also repeated) and STOP: use
--   them to reset a register pointer or a byte counter.  A typical register
--   file takes the first byte after a write address as the pointer.
--
-- Open-drain pin: sda_oe = '1' pulls SDA low, '0' releases it (see i2c_master
-- for the pad code).  Only SDA is driven.

library ieee;
use ieee.std_logic_1164.all;

entity {{entity|$file}} is
  generic (
    G_ADDR : std_logic_vector(6 downto 0) := "{{addr|1010000}}"   -- 7-bit address
  );
  port (
    clk        : in  std_logic;
    rst        : in  std_logic;                          -- synchronous, active high
    -- bus
    scl_i      : in  std_logic;
    sda_i      : in  std_logic;
    sda_oe     : out std_logic;
    -- events
    start_evt  : out std_logic := '0';
    stop_evt   : out std_logic := '0';
    addr_match : out std_logic := '0';                   -- our address was acknowledged
    is_read    : out std_logic;                          -- direction of the current transfer
    -- master writes to us
    rx_data    : out std_logic_vector(7 downto 0) := (others => '0');
    rx_valid   : out std_logic := '0';
    -- master reads from us
    tx_data    : in  std_logic_vector(7 downto 0);
    tx_req     : out std_logic := '0'
  );
end entity {{entity}};

architecture rtl of {{entity}} is

  type state_t is (S_IDLE, S_ADDR, S_ACKA, S_RX, S_ACKD, S_TX, S_MACK, S_WAIT);
  signal state   : state_t := S_IDLE;

  -- q(1) is the synchronized value, q(2) the one before it.
  signal scl_q   : std_logic_vector(2 downto 0) := (others => '1');
  signal sda_q   : std_logic_vector(2 downto 0) := (others => '1');

  signal bit_cnt : natural range 0 to 9 := 0;      -- SCL rising edges in this byte
  signal sh      : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_sh   : std_logic_vector(7 downto 0) := (others => '0');
  signal sda_oe_r : std_logic := '0';
  signal matched : std_logic := '0';
  signal read_r  : std_logic := '0';
  signal m_ack   : std_logic := '0';

  attribute async_reg : string;
  attribute async_reg of scl_q : signal is "true";
  attribute async_reg of sda_q : signal is "true";

begin

  p_i2c : process (clk)
    variable v_scl_rise : boolean;
    variable v_scl_fall : boolean;
    variable v_start    : boolean;
    variable v_stop     : boolean;
    variable v_sh       : std_logic_vector(7 downto 0);
  begin
    if rising_edge(clk) then
      scl_q      <= scl_q(1 downto 0) & scl_i;
      sda_q      <= sda_q(1 downto 0) & sda_i;
      start_evt  <= '0';
      stop_evt   <= '0';
      addr_match <= '0';
      rx_valid   <= '0';
      tx_req     <= '0';

      v_scl_rise := scl_q(2) = '0' and scl_q(1) = '1';
      v_scl_fall := scl_q(2) = '1' and scl_q(1) = '0';
      -- START and STOP are SDA edges while SCL stays high.
      v_start := scl_q(2) = '1' and scl_q(1) = '1' and sda_q(2) = '1' and sda_q(1) = '0';
      v_stop  := scl_q(2) = '1' and scl_q(1) = '1' and sda_q(2) = '0' and sda_q(1) = '1';

      if v_start then
        state     <= S_ADDR;
        bit_cnt   <= 0;
        sda_oe_r  <= '0';
        start_evt <= '1';
      elsif v_stop then
        state    <= S_IDLE;
        sda_oe_r <= '0';
        stop_evt <= '1';

      elsif v_scl_rise then
        case state is
          when S_ADDR | S_RX =>
            if bit_cnt < 8 then
              v_sh    := sh(6 downto 0) & sda_q(1);
              sh      <= v_sh;
              bit_cnt <= bit_cnt + 1;
              if bit_cnt = 7 then                       -- eighth bit: byte complete
                if state = S_ADDR then
                  if v_sh(7 downto 1) = G_ADDR then
                    matched <= '1';
                    read_r  <= v_sh(0);
                  else
                    matched <= '0';
                  end if;
                else
                  rx_data  <= v_sh;
                  rx_valid <= '1';
                end if;
              end if;
            end if;
          when S_ACKA | S_ACKD =>                       -- ninth clock
            bit_cnt <= 9;
            if state = S_ACKA and read_r = '1' then
              tx_req <= '1';                            -- first byte of a read
            end if;
          when S_TX =>
            if bit_cnt < 8 then
              bit_cnt <= bit_cnt + 1;
            end if;
          when S_MACK =>                                -- master's acknowledge
            bit_cnt <= 9;
            if sda_q(1) = '0' then
              m_ack  <= '1';
              tx_req <= '1';                            -- it wants another byte
            else
              m_ack <= '0';
            end if;
          when others =>
            null;
        end case;

      elsif v_scl_fall then
        case state is
          when S_ADDR =>
            if bit_cnt = 8 then                         -- start of the acknowledge clock
              if matched = '1' then
                sda_oe_r   <= '1';                      -- ACK
                state      <= S_ACKA;
                addr_match <= '1';
              else
                state <= S_WAIT;                        -- not for us: stay off the bus
              end if;
            end if;
          when S_RX =>
            if bit_cnt = 8 then
              sda_oe_r <= '1';                          -- ACK
              state    <= S_ACKD;
            end if;
          when S_ACKA | S_ACKD =>
            if bit_cnt = 9 then                         -- end of the acknowledge clock
              bit_cnt  <= 0;
              sda_oe_r <= '0';
              if state = S_ACKA and read_r = '1' then
                tx_sh    <= tx_data;
                sda_oe_r <= not tx_data(7);             -- first bit is out before SCL rises
                state    <= S_TX;
              else
                state <= S_RX;
              end if;
            end if;
          when S_TX =>
            if bit_cnt < 8 then
              sda_oe_r <= not tx_sh(7 - bit_cnt);       -- next bit
            else
              sda_oe_r <= '0';                          -- release SDA for the master's ACK
              state    <= S_MACK;
            end if;
          when S_MACK =>
            if bit_cnt = 9 then
              bit_cnt <= 0;
              if m_ack = '1' then
                tx_sh    <= tx_data;
                sda_oe_r <= not tx_data(7);
                state    <= S_TX;
              else
                sda_oe_r <= '0';
                state    <= S_WAIT;                     -- NACK: the read is over
              end if;
            end if;
          when others =>
            null;
        end case;
      end if;

      if rst = '1' then
        state    <= S_IDLE;
        sda_oe_r <= '0';
        bit_cnt  <= 0;
      end if;
    end if;
  end process p_i2c;

  sda_oe  <= sda_oe_r;
  is_read <= read_r;
  {{_}}

end architecture rtl;
