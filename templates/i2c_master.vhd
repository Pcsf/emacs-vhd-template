{{!I2C master: one command per byte (START, write or read, STOP), clock stretching; two-process style}}
{{+sync_2ff}}
{{>header.vhd}}

-- One command moves at most one byte:  [START] [write or read a byte] [STOP].
--   write 3 bytes to a device:  {start, write, addr&'0'}  {write, b0}  {write, b1, stop}
--   read 2 bytes from a device: {start, write, addr&'1'}  {read}       {read, nack, stop}
--   register read: ... {write, reg} {start, write, addr&'1'} {read, nack, stop}
--                                    ^ START again while the bus is open = repeated START
-- The address goes out as a normal write byte, so the first response
-- (rsp_nack) tells whether the device answered.  After a NACK, send a command
-- with only `stop` set.  A command with `read` set wins over `write`; with
-- neither set only START and / or STOP are generated.
--
-- SCL = G_SCL_HZ (each quarter period is G_CLK_HZ / (4 * G_SCL_HZ) clocks).  A
-- slave that holds SCL low stretches the clock and the master waits.  START
-- hold, repeated START setup, STOP setup and the bus free time after a STOP
-- are each half an SCL period, which meets I2C Standard-mode at 100 kHz.  Not
-- supported: multi-master arbitration, 10-bit addresses.
--
-- Open-drain pins: *_oe = '1' pulls the line low, '0' releases it.  At the top
-- level (Xilinx / Intel):   scl_pad <= '0' when scl_oe = '1' else 'Z';
--                           scl_i   <= scl_pad;   (same for SDA)
-- The lines need an external pull-up (or PULLUP in the constraints).

library ieee;
use ieee.std_logic_1164.all;

entity {{entity|$file}} is
  generic (
    G_CLK_HZ : positive := {{clk_hz|100_000_000}};
    G_SCL_HZ : positive := {{scl_hz|100_000}}
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;                            -- synchronous, active high
    -- command, taken when cmd_valid and cmd_ready
    cmd_valid : in  std_logic;
    cmd_ready : out std_logic;
    cmd_start : in  std_logic;                            -- (repeated) START first
    cmd_stop  : in  std_logic;                            -- STOP last
    cmd_read  : in  std_logic;                            -- read a byte ...
    cmd_write : in  std_logic;                            -- ... or write one
    cmd_nack  : in  std_logic;                            -- read: answer NACK (last byte)
    cmd_data  : in  std_logic_vector(7 downto 0);         -- byte to write
    -- response, one clock wide, when the command is done
    rsp_valid : out std_logic := '0';
    rsp_data  : out std_logic_vector(7 downto 0) := (others => '0');   -- byte read
    rsp_nack  : out std_logic := '0';                     -- byte written was not acknowledged
    busy      : out std_logic;
    -- bus
    scl_i     : in  std_logic;
    scl_oe    : out std_logic;
    sda_i     : in  std_logic;
    sda_oe    : out std_logic
  );
end entity {{entity}};

architecture rtl of {{entity}} is

  constant C_Q : positive := G_CLK_HZ / (4 * G_SCL_HZ);   -- clocks per quarter SCL period

  type state_t is (S_IDLE, S_START, S_BYTE, S_STOP, S_DONE);

  type reg_type is record
    state      : state_t;
    step       : natural range 0 to 6;
    bit_idx    : natural range 0 to 8;           -- 0-7 data bits, 8 acknowledge
    timer      : natural range 0 to C_Q - 1;
    bus_active : std_logic;                      -- a transaction is open
    scl_oe     : std_logic;
    sda_oe     : std_logic;
    tx_sh      : std_logic_vector(7 downto 0);
    rx_sh      : std_logic_vector(7 downto 0);
    do_start   : std_logic;
    do_stop    : std_logic;
    do_read    : std_logic;
    do_write   : std_logic;
    nack       : std_logic;
    ack_err    : std_logic;
    rsp_valid  : std_logic;
    rsp_data   : std_logic_vector(7 downto 0);
    rsp_nack   : std_logic;
  end record reg_type;

  constant REG_RESET : reg_type := (
    state      => S_IDLE,
    step       => 0,
    bit_idx    => 0,
    timer      => 0,
    bus_active => '0',
    scl_oe     => '0',
    sda_oe     => '0',
    tx_sh      => (others => '0'),
    rx_sh      => (others => '0'),
    do_start   => '0',
    do_stop    => '0',
    do_read    => '0',
    do_write   => '0',
    nack       => '0',
    ack_err    => '0',
    rsp_valid  => '0',
    rsp_data   => (others => '0'),
    rsp_nack   => '0'
  );

  signal r, rin : reg_type := REG_RESET;

  -- The bus lines, synchronous to clk.
  signal scl_s : std_logic;
  signal sda_s : std_logic;

begin

  assert C_Q >= 2 report "G_CLK_HZ must be at least 8 * G_SCL_HZ" severity failure;

  -- The pins go through synchronizer cells before they enter the record: the
  -- chains have no reset and constraints can find them by name.
  u_sync_scl : entity work.sync_2ff
    generic map (G_STAGES => 2, G_INIT => '1')
    port map (clk => clk, d => scl_i, q => scl_s);

  u_sync_sda : entity work.sync_2ff
    generic map (G_STAGES => 2, G_INIT => '1')
    port map (clk => clk, d => sda_i, q => sda_s);

  comb : process (all)
    variable v       : reg_type;
    variable advance : boolean;                  -- a quarter period has passed
  begin
    v           := r;
    v.rsp_valid := '0';

    -- Quarter period timer.  While SCL is released but still reads low, a
    -- slave is stretching the clock: restart the quarter until it is high.
    advance := false;
    if r.scl_oe = '0' and scl_s = '0' then
      v.timer := C_Q - 1;
    elsif r.timer /= 0 then
      v.timer := r.timer - 1;
    else
      advance := true;
    end if;

    case r.state is

      when S_IDLE =>
        if cmd_valid = '1' then
          v.do_start := cmd_start;
          v.do_stop  := cmd_stop;
          v.do_read  := cmd_read;
          v.do_write := cmd_write and not cmd_read;
          v.nack     := cmd_nack;
          v.tx_sh    := cmd_data;
          v.ack_err  := '0';
          v.bit_idx  := 0;
          v.timer    := C_Q - 1;
          if cmd_start = '1' then
            v.state := S_START;
            if r.bus_active = '1' then       -- repeated START: SCL low, SDA up, SCL up, SDA down
              v.step   := 0;
              v.scl_oe := '1';
            else                           -- idle bus: SDA down while SCL is high
              v.step   := 4;
              v.sda_oe := '1';
            end if;
          elsif cmd_read = '1' or cmd_write = '1' then
            v.state  := S_BYTE;            -- bus is open, SCL is low
            v.step   := 0;
            v.scl_oe := '1';
          elsif cmd_stop = '1' and r.bus_active = '1' then
            v.state  := S_STOP;
            v.step   := 1;
            v.sda_oe := '1';
          else
            v.state := S_DONE;
          end if;
        end if;

      when S_START =>
        if advance then
          v.timer := C_Q - 1;
          case r.step is
            when 0 =>
              v.sda_oe := '0';             -- release SDA (SCL is low)
              v.step   := 1;
            when 1 =>
              v.scl_oe := '0';             -- release SCL, wait for it to rise
              v.step   := 2;
            when 2 =>
              v.step := 3;                 -- second quarter of the setup time
            when 3 =>
              v.sda_oe := '1';             -- START: SDA falls while SCL is high
              v.step   := 4;
            when 4 =>
              v.step := 5;                 -- second quarter of the hold time
            when 5 =>
              v.scl_oe := '1';             -- SCL low
              v.step   := 6;
            when others =>
              v.bus_active := '1';
              if r.do_read = '1' or r.do_write = '1' then
                v.state := S_BYTE;
                v.step  := 0;
              else
                v.state := S_DONE;
              end if;
          end case;
        end if;

      when S_BYTE =>
        -- Every bit takes four quarters: SCL low, SDA set, SCL released
        -- (high), SCL high; the bit is sampled at the end of the last one.
        if advance then
          v.timer := C_Q - 1;
          case r.step is
            when 0 =>
              v.step := 1;
              if r.bit_idx < 8 then
                if r.do_read = '1' then
                  v.sda_oe := '0';                       -- slave drives the bit
                else
                  v.sda_oe := not r.tx_sh(7 - r.bit_idx);    -- '0' pulls SDA low
                end if;
              else
                if r.do_read = '1' then
                  v.sda_oe := not r.nack;                -- ACK = SDA low
                else
                  v.sda_oe := '0';                       -- slave drives the ACK
                end if;
              end if;
            when 1 =>
              v.scl_oe := '0';                           -- release SCL, wait for it to rise
              v.step   := 2;
            when 2 =>
              v.step := 3;
            when 3 =>
              v.scl_oe := '1';
              if r.bit_idx < 8 then
                if r.do_read = '1' then
                  v.rx_sh := r.rx_sh(6 downto 0) & sda_s;
                end if;
                v.bit_idx := r.bit_idx + 1;
                v.step    := 0;
              else
                if r.do_write = '1' then
                  v.ack_err := sda_s;                   -- '1' = NACK
                end if;
                v.step := 4;
              end if;
            when others =>
              if r.do_stop = '1' then
                v.state  := S_STOP;
                v.step   := 1;
                v.sda_oe := '1';                         -- SDA low, SCL low
              else
                v.state := S_DONE;
              end if;
          end case;
        end if;

      when S_STOP =>
        if advance then
          v.timer := C_Q - 1;
          case r.step is
            when 1 =>
              v.scl_oe := '0';             -- release SCL, wait for it to rise
              v.step   := 2;
            when 2 =>
              v.step := 3;                 -- second quarter of the setup time
            when 3 =>
              v.sda_oe := '0';             -- STOP: SDA rises while SCL is high
              v.step   := 4;
            when 4 =>
              v.step := 5;                 -- bus free time: two more quarters
            when others =>
              v.bus_active := '0';
              v.state      := S_DONE;
          end case;
        end if;

      when S_DONE =>
        v.rsp_valid := '1';
        v.rsp_data  := r.rx_sh;
        v.rsp_nack  := r.ack_err;
        v.state     := S_IDLE;

    end case;

    {{_}}

    if rst = '1' then                              -- control fields only
      v.state      := S_IDLE;
      v.scl_oe     := '0';
      v.sda_oe     := '0';
      v.bus_active := '0';
      v.rsp_valid  := '0';
    end if;

    rin <= v;

    cmd_ready <= '1' when r.state = S_IDLE else '0';
    busy      <= '0' when r.state = S_IDLE else '1';
    rsp_valid <= r.rsp_valid;
    rsp_data  <= r.rsp_data;
    rsp_nack  <= r.rsp_nack;
    scl_oe    <= r.scl_oe;
    sda_oe    <= r.sda_oe;
  end process comb;

  regs : process (clk)
  begin
    if rising_edge(clk) then
      r <= rin;
    end if;
  end process regs;

end architecture rtl;
