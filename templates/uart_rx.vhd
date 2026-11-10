{{!UART receiver, 8N1, mid-bit sampling, framing error flag, two-process style}}
{{+sync_2ff}}
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

  type reg_type is record
    state     : state_t;
    cnt       : natural range 0 to C_DIV - 1;
    bit_idx   : natural range 0 to 7;
    shreg     : std_logic_vector(7 downto 0);
    data      : std_logic_vector(7 downto 0);
    valid     : std_logic;
    frame_err : std_logic;
  end record reg_type;

  constant REG_RESET : reg_type := (
    state     => S_IDLE,
    cnt       => 0,
    bit_idx   => 0,
    shreg     => (others => '0'),
    data      => (others => '0'),
    valid     => '0',
    frame_err => '0'
  );

  signal r, rin : reg_type := REG_RESET;
  signal rx_s   : std_logic;                    -- rx, synchronous to clk

begin

  assert C_DIV >= 4 report "G_CLK_HZ must be at least 4 * G_BAUD" severity failure;

  -- The asynchronous pin goes through the synchronizer cell before it enters
  -- the record: the chain has no reset and constraints can find it by name.
  u_sync_rx : entity work.sync_2ff
    generic map (G_STAGES => 2, G_INIT => '1')
    port map (clk => clk, d => rx, q => rx_s);

  comb : process (all)
    variable v : reg_type;
  begin
    v       := r;
    v.valid := '0';

    case r.state is
      when S_IDLE =>
        v.cnt := 0;
        if rx_s = '0' then                      -- falling edge: start bit
          v.state := S_START;
        end if;
      when S_START =>                           -- middle of the start bit
        if r.cnt = C_DIV / 2 - 1 then
          v.cnt := 0;
          if rx_s = '0' then
            v.bit_idx := 0;
            v.state   := S_DATA;
          else
            v.state := S_IDLE;                  -- glitch, not a start bit
          end if;
        else
          v.cnt := r.cnt + 1;
        end if;
      when S_DATA =>                            -- middle of each data bit
        if r.cnt = C_DIV - 1 then
          v.cnt   := 0;
          v.shreg := rx_s & r.shreg(7 downto 1);   -- LSB first
          if r.bit_idx = 7 then
            v.state := S_STOP;
          else
            v.bit_idx := r.bit_idx + 1;
          end if;
        else
          v.cnt := r.cnt + 1;
        end if;
      when S_STOP =>                            -- middle of the stop bit
        if r.cnt = C_DIV - 1 then
          v.cnt       := 0;
          v.state     := S_IDLE;
          v.data      := r.shreg;
          v.valid     := '1';
          v.frame_err := not rx_s;
        else
          v.cnt := r.cnt + 1;
        end if;
    end case;
    {{_}}

    if rst = '1' then                           -- control fields only
      v.state     := S_IDLE;
      v.cnt       := 0;
      v.valid     := '0';
      v.frame_err := '0';
    end if;

    rin <= v;

    data      <= r.data;
    valid     <= r.valid;
    frame_err <= r.frame_err;
  end process comb;

  regs : process (clk)
  begin
    if rising_edge(clk) then
      r <= rin;
    end if;
  end process regs;

end architecture rtl;
