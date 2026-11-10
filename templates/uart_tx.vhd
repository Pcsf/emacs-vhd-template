{{!UART transmitter, 8N1, valid/ready handshake, two-process style}}
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

  type reg_type is record
    state   : state_t;
    cnt     : natural range 0 to C_DIV - 1;
    bit_idx : natural range 0 to 7;
    shreg   : std_logic_vector(7 downto 0);
    tx      : std_logic;
  end record reg_type;

  constant REG_RESET : reg_type := (
    state   => S_IDLE,
    cnt     => 0,
    bit_idx => 0,
    shreg   => (others => '0'),
    tx      => '1'
  );

  signal r, rin : reg_type := REG_RESET;

begin

  assert C_DIV >= 2 report "G_CLK_HZ must be at least 2 * G_BAUD" severity failure;

  comb : process (all)
    variable v        : reg_type;
    variable bit_done : boolean;                -- last clock of the current bit
  begin
    v        := r;
    bit_done := r.cnt = C_DIV - 1;

    -- tx follows the state one clock late, which gives every bit the same
    -- length of C_DIV clocks.
    case r.state is
      when S_IDLE =>
        v.tx  := '1';
        v.cnt := 0;
        if valid = '1' then
          v.shreg := data;
          v.state := S_START;
        end if;
      when S_START =>
        v.tx := '0';
        if bit_done then
          v.cnt     := 0;
          v.bit_idx := 0;
          v.state   := S_DATA;
        else
          v.cnt := r.cnt + 1;
        end if;
      when S_DATA =>
        v.tx := r.shreg(r.bit_idx);             -- LSB first
        if bit_done then
          v.cnt := 0;
          if r.bit_idx = 7 then
            v.state := S_STOP;
          else
            v.bit_idx := r.bit_idx + 1;
          end if;
        else
          v.cnt := r.cnt + 1;
        end if;
      when S_STOP =>
        v.tx := '1';
        if bit_done then
          v.cnt   := 0;
          v.state := S_IDLE;
        else
          v.cnt := r.cnt + 1;
        end if;
    end case;
    {{_}}

    if rst = '1' then                           -- control fields only
      v.state := S_IDLE;
      v.tx    := '1';
      v.cnt   := 0;
    end if;

    rin <= v;

    ready <= '1' when r.state = S_IDLE else '0';
    tx    <= r.tx;
  end process comb;

  regs : process (clk)
  begin
    if rising_edge(clk) then
      r <= rin;
    end if;
  end process regs;

end architecture rtl;
