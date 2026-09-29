{{!I2C master: byte commands (START, write or read a byte, STOP), clock stretching, single master}}
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
-- slave that holds SCL low stretches the clock and the master waits.  Not
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
  signal state      : state_t := S_IDLE;
  signal step       : natural range 0 to 4 := 0;
  signal bit_idx    : natural range 0 to 8 := 0;           -- 0-7 data bits, 8 acknowledge
  signal timer      : natural range 0 to C_Q - 1 := 0;
  signal bus_active : std_logic := '0';                    -- a transaction is open

  signal scl_oe_r : std_logic := '0';
  signal sda_oe_r : std_logic := '0';
  signal scl_q    : std_logic_vector(1 downto 0) := (others => '1');
  signal sda_q    : std_logic_vector(1 downto 0) := (others => '1');

  signal tx_sh    : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_sh    : std_logic_vector(7 downto 0) := (others => '0');
  signal do_start : std_logic := '0';
  signal do_stop  : std_logic := '0';
  signal do_read  : std_logic := '0';
  signal do_write : std_logic := '0';
  signal nack_r   : std_logic := '0';
  signal ack_err  : std_logic := '0';

  attribute async_reg : string;
  attribute async_reg of scl_q : signal is "true";
  attribute async_reg of sda_q : signal is "true";

begin

  assert C_Q >= 2 report "G_CLK_HZ must be at least 8 * G_SCL_HZ" severity failure;

  p_i2c : process (clk)
    variable v_advance : boolean;
  begin
    if rising_edge(clk) then
      scl_q     <= scl_q(0) & scl_i;
      sda_q     <= sda_q(0) & sda_i;
      rsp_valid <= '0';

      -- Quarter period timer.  While SCL is released but still reads low, a
      -- slave is stretching the clock: restart the quarter until it is high.
      v_advance := false;
      if scl_oe_r = '0' and scl_q(1) = '0' then
        timer <= C_Q - 1;
      elsif timer /= 0 then
        timer <= timer - 1;
      else
        v_advance := true;
      end if;

      case state is

        when S_IDLE =>
          if cmd_valid = '1' then
            do_start <= cmd_start;
            do_stop  <= cmd_stop;
            do_read  <= cmd_read;
            do_write <= cmd_write and not cmd_read;
            nack_r   <= cmd_nack;
            tx_sh    <= cmd_data;
            ack_err  <= '0';
            bit_idx  <= 0;
            timer    <= C_Q - 1;
            if cmd_start = '1' then
              state <= S_START;
              if bus_active = '1' then       -- repeated START: SCL low, SDA up, SCL up, SDA down
                step     <= 0;
                scl_oe_r <= '1';
              else                           -- idle bus: SDA down while SCL is high
                step     <= 3;
                sda_oe_r <= '1';
              end if;
            elsif cmd_read = '1' or cmd_write = '1' then
              state    <= S_BYTE;            -- bus is open, SCL is low
              step     <= 0;
              scl_oe_r <= '1';
            elsif cmd_stop = '1' and bus_active = '1' then
              state    <= S_STOP;
              step     <= 1;
              sda_oe_r <= '1';
            else
              state <= S_DONE;
            end if;
          end if;

        when S_START =>
          if v_advance then
            timer <= C_Q - 1;
            case step is
              when 0 =>
                sda_oe_r <= '0';             -- release SDA (SCL is low)
                step     <= 1;
              when 1 =>
                scl_oe_r <= '0';             -- release SCL, wait for it to rise
                step     <= 2;
              when 2 =>
                sda_oe_r <= '1';             -- START: SDA falls while SCL is high
                step     <= 3;
              when 3 =>
                scl_oe_r <= '1';             -- SCL low
                step     <= 4;
              when others =>
                bus_active <= '1';
                if do_read = '1' or do_write = '1' then
                  state <= S_BYTE;
                  step  <= 0;
                else
                  state <= S_DONE;
                end if;
            end case;
          end if;

        when S_BYTE =>
          -- Every bit takes four quarters: SCL low, SDA set, SCL released
          -- (high), SCL high; the bit is sampled at the end of the last one.
          if v_advance then
            timer <= C_Q - 1;
            case step is
              when 0 =>
                step <= 1;
                if bit_idx < 8 then
                  if do_read = '1' then
                    sda_oe_r <= '0';                       -- slave drives the bit
                  else
                    sda_oe_r <= not tx_sh(7 - bit_idx);    -- '0' pulls SDA low
                  end if;
                else
                  if do_read = '1' then
                    sda_oe_r <= not nack_r;                -- ACK = SDA low
                  else
                    sda_oe_r <= '0';                       -- slave drives the ACK
                  end if;
                end if;
              when 1 =>
                scl_oe_r <= '0';                           -- release SCL, wait for it to rise
                step     <= 2;
              when 2 =>
                step <= 3;
              when 3 =>
                scl_oe_r <= '1';
                if bit_idx < 8 then
                  if do_read = '1' then
                    rx_sh <= rx_sh(6 downto 0) & sda_q(1);
                  end if;
                  bit_idx <= bit_idx + 1;
                  step    <= 0;
                else
                  if do_write = '1' then
                    ack_err <= sda_q(1);                   -- '1' = NACK
                  end if;
                  step <= 4;
                end if;
              when others =>
                if do_stop = '1' then
                  state    <= S_STOP;
                  step     <= 1;
                  sda_oe_r <= '1';                         -- SDA low, SCL low
                else
                  state <= S_DONE;
                end if;
            end case;
          end if;

        when S_STOP =>
          if v_advance then
            timer <= C_Q - 1;
            case step is
              when 1 =>
                scl_oe_r <= '0';             -- release SCL, wait for it to rise
                step     <= 2;
              when 2 =>
                sda_oe_r <= '0';             -- STOP: SDA rises while SCL is high
                step     <= 3;
              when others =>
                bus_active <= '0';
                state      <= S_DONE;
            end case;
          end if;

        when S_DONE =>
          rsp_valid <= '1';
          rsp_data  <= rx_sh;
          rsp_nack  <= ack_err;
          state     <= S_IDLE;

      end case;

      if rst = '1' then
        state      <= S_IDLE;
        scl_oe_r   <= '0';
        sda_oe_r   <= '0';
        bus_active <= '0';
        rsp_valid  <= '0';
      end if;
    end if;
  end process p_i2c;

  cmd_ready <= '1' when state = S_IDLE else '0';
  busy      <= '0' when state = S_IDLE else '1';
  scl_oe    <= scl_oe_r;
  sda_oe    <= sda_oe_r;
  {{_}}

end architecture rtl;
