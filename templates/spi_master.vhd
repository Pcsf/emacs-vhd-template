{{!SPI master, mode 0 (CPOL=0, CPHA=0), 8 bits MSB first, two-process style}}
{{+sync_2ff}}
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

  type reg_type is record
    state   : state_t;
    cnt     : natural range 0 to G_CLK_DIV - 1;
    bit_cnt : natural range 0 to 7;
    tx_sh   : std_logic_vector(7 downto 0);
    rx_sh   : std_logic_vector(7 downto 0);
    rx_data : std_logic_vector(7 downto 0);
    done    : std_logic;
    sclk    : std_logic;
    mosi    : std_logic;
    cs_n    : std_logic;
  end record reg_type;

  constant REG_RESET : reg_type := (
    state   => S_IDLE,
    cnt     => 0,
    bit_cnt => 0,
    tx_sh   => (others => '0'),
    rx_sh   => (others => '0'),
    rx_data => (others => '0'),
    done    => '0',
    sclk    => '0',
    mosi    => '0',
    cs_n    => '1'
  );

  signal r, rin : reg_type := REG_RESET;
  signal miso_s : std_logic;                    -- miso, synchronous to clk

begin

  -- The pin goes through the synchronizer cell before it enters the record.
  u_sync_miso : entity work.sync_2ff
    generic map (G_STAGES => 2, G_INIT => '0')
    port map (clk => clk, d => miso, q => miso_s);

  comb : process (all)
    variable v         : reg_type;
    variable half_done : boolean;               -- last clock of the half period
  begin
    v         := r;
    half_done := r.cnt = G_CLK_DIV - 1;
    v.done    := '0';

    case r.state is
      when S_IDLE =>
        v.sclk := '0';
        v.cnt  := 0;
        if start = '1' then
          v.tx_sh   := tx_data;
          v.mosi    := tx_data(7);              -- first bit set up before SCLK rises
          v.cs_n    := '0';
          v.bit_cnt := 0;
          v.state   := S_LOW;
        end if;
      when S_LOW =>                             -- SCLK low; ends with the rising edge
        if half_done then
          v.cnt   := 0;
          v.sclk  := '1';
          v.rx_sh := r.rx_sh(6 downto 0) & miso_s;   -- sample on the rising edge
          v.state := S_HIGH;
        else
          v.cnt := r.cnt + 1;
        end if;
      when S_HIGH =>                            -- SCLK high; ends with the falling edge
        if half_done then
          v.cnt  := 0;
          v.sclk := '0';
          if r.bit_cnt = 7 then
            v.state := S_END;
          else
            v.bit_cnt := r.bit_cnt + 1;
            v.tx_sh   := r.tx_sh(6 downto 0) & '0';
            v.mosi    := r.tx_sh(6);            -- shift on the falling edge
            v.state   := S_LOW;
          end if;
        else
          v.cnt := r.cnt + 1;
        end if;
      when S_END =>                             -- hold CS low one more half period
        if half_done then
          v.cnt     := 0;
          v.cs_n    := '1';
          v.rx_data := r.rx_sh;
          v.done    := '1';
          v.state   := S_IDLE;
        else
          v.cnt := r.cnt + 1;
        end if;
    end case;
    {{_}}

    if rst = '1' then                           -- control fields only
      v.state := S_IDLE;
      v.sclk  := '0';
      v.cs_n  := '1';
      v.done  := '0';
    end if;

    rin <= v;

    busy    <= '0' when r.state = S_IDLE else '1';
    rx_data <= r.rx_data;
    done    <= r.done;
    sclk    <= r.sclk;
    mosi    <= r.mosi;
    cs_n    <= r.cs_n;
  end process comb;

  regs : process (clk)
  begin
    if rising_edge(clk) then
      r <= rin;
    end if;
  end process regs;

end architecture rtl;
