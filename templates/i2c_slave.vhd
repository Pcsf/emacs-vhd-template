{{!I2C slave: 7-bit address, byte interface with events, no clock stretching; two-process style}}
{{+sync_2ff}}
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

  type reg_type is record
    state      : state_t;
    scl_d      : std_logic;                      -- scl_s one clock ago
    sda_d      : std_logic;                      -- sda_s one clock ago
    bit_cnt    : natural range 0 to 9;           -- SCL rising edges in this byte
    sh         : std_logic_vector(7 downto 0);
    tx_sh      : std_logic_vector(7 downto 0);
    sda_oe     : std_logic;
    matched    : std_logic;
    is_read    : std_logic;
    m_ack      : std_logic;
    start_evt  : std_logic;
    stop_evt   : std_logic;
    addr_match : std_logic;
    rx_data    : std_logic_vector(7 downto 0);
    rx_valid   : std_logic;
    tx_req     : std_logic;
  end record reg_type;

  constant REG_RESET : reg_type := (
    state      => S_IDLE,
    scl_d      => '1',
    sda_d      => '1',
    bit_cnt    => 0,
    sh         => (others => '0'),
    tx_sh      => (others => '0'),
    sda_oe     => '0',
    matched    => '0',
    is_read    => '0',
    m_ack      => '0',
    start_evt  => '0',
    stop_evt   => '0',
    addr_match => '0',
    rx_data    => (others => '0'),
    rx_valid   => '0',
    tx_req     => '0'
  );

  signal r, rin : reg_type := REG_RESET;

  -- The bus lines, synchronous to clk.
  signal scl_s : std_logic;
  signal sda_s : std_logic;

begin

  -- The pins go through synchronizer cells before they enter the record: the
  -- chains have no reset and constraints can find them by name.
  u_sync_scl : entity work.sync_2ff
    generic map (G_STAGES => 2, G_INIT => '1')
    port map (clk => clk, d => scl_i, q => scl_s);

  u_sync_sda : entity work.sync_2ff
    generic map (G_STAGES => 2, G_INIT => '1')
    port map (clk => clk, d => sda_i, q => sda_s);

  comb : process (all)
    variable v        : reg_type;
    variable scl_rise : boolean;
    variable scl_fall : boolean;
    variable start    : boolean;
    variable stop     : boolean;
    variable sh_next  : std_logic_vector(7 downto 0);   -- the byte with this bit shifted in
  begin
    v       := r;
    sh_next := r.sh(6 downto 0) & sda_s;

    v.scl_d      := scl_s;
    v.sda_d      := sda_s;
    v.start_evt  := '0';
    v.stop_evt   := '0';
    v.addr_match := '0';
    v.rx_valid   := '0';
    v.tx_req     := '0';

    scl_rise := r.scl_d = '0' and scl_s = '1';
    scl_fall := r.scl_d = '1' and scl_s = '0';
    -- START and STOP are SDA edges while SCL stays high.
    start := r.scl_d = '1' and scl_s = '1' and r.sda_d = '1' and sda_s = '0';
    stop  := r.scl_d = '1' and scl_s = '1' and r.sda_d = '0' and sda_s = '1';

    if start then
      v.state     := S_ADDR;
      v.bit_cnt   := 0;
      v.sda_oe    := '0';
      v.start_evt := '1';
    elsif stop then
      v.state    := S_IDLE;
      v.sda_oe   := '0';
      v.stop_evt := '1';

    elsif scl_rise then
      case r.state is
        when S_ADDR | S_RX =>
          if r.bit_cnt < 8 then
            v.sh      := sh_next;
            v.bit_cnt := r.bit_cnt + 1;
            if r.bit_cnt = 7 then                       -- eighth bit: byte complete
              if r.state = S_ADDR then
                if sh_next(7 downto 1) = G_ADDR then
                  v.matched := '1';
                  v.is_read := sh_next(0);
                else
                  v.matched := '0';
                end if;
              else
                v.rx_data  := sh_next;
                v.rx_valid := '1';
              end if;
            end if;
          end if;
        when S_ACKA | S_ACKD =>                       -- ninth clock
          v.bit_cnt := 9;
          if r.state = S_ACKA and r.is_read = '1' then
            v.tx_req := '1';                            -- first byte of a read
          end if;
        when S_TX =>
          if r.bit_cnt < 8 then
            v.bit_cnt := r.bit_cnt + 1;
          end if;
        when S_MACK =>                                -- master's acknowledge
          v.bit_cnt := 9;
          if sda_s = '0' then
            v.m_ack  := '1';
            v.tx_req := '1';                            -- it wants another byte
          else
            v.m_ack := '0';
          end if;
        when others =>
          null;
      end case;

    elsif scl_fall then
      case r.state is
        when S_ADDR =>
          if r.bit_cnt = 8 then                         -- start of the acknowledge clock
            if r.matched = '1' then
              v.sda_oe     := '1';                      -- ACK
              v.state      := S_ACKA;
              v.addr_match := '1';
            else
              v.state := S_WAIT;                        -- not for us: stay off the bus
            end if;
          end if;
        when S_RX =>
          if r.bit_cnt = 8 then
            v.sda_oe := '1';                          -- ACK
            v.state  := S_ACKD;
          end if;
        when S_ACKA | S_ACKD =>
          if r.bit_cnt = 9 then                         -- end of the acknowledge clock
            v.bit_cnt := 0;
            v.sda_oe  := '0';
            if r.state = S_ACKA and r.is_read = '1' then
              v.tx_sh  := tx_data;
              v.sda_oe := not tx_data(7);             -- first bit is out before SCL rises
              v.state  := S_TX;
            else
              v.state := S_RX;
            end if;
          end if;
        when S_TX =>
          if r.bit_cnt < 8 then
            v.sda_oe := not r.tx_sh(7 - r.bit_cnt);       -- next bit
          else
            v.sda_oe := '0';                          -- release SDA for the master's ACK
            v.state  := S_MACK;
          end if;
        when S_MACK =>
          if r.bit_cnt = 9 then
            v.bit_cnt := 0;
            if r.m_ack = '1' then
              v.tx_sh  := tx_data;
              v.sda_oe := not tx_data(7);
              v.state  := S_TX;
            else
              v.sda_oe := '0';
              v.state  := S_WAIT;                     -- NACK: the read is over
            end if;
          end if;
        when others =>
          null;
      end case;
    end if;

    {{_}}

    if rst = '1' then                                -- control fields only
      v.state   := S_IDLE;
      v.sda_oe  := '0';
      v.bit_cnt := 0;
    end if;

    rin <= v;

    sda_oe     <= r.sda_oe;
    start_evt  <= r.start_evt;
    stop_evt   <= r.stop_evt;
    addr_match <= r.addr_match;
    is_read    <= r.is_read;
    rx_data    <= r.rx_data;
    rx_valid   <= r.rx_valid;
    tx_req     <= r.tx_req;
  end process comb;

  regs : process (clk)
  begin
    if rising_edge(clk) then
      r <= rin;
    end if;
  end process regs;

end architecture rtl;
