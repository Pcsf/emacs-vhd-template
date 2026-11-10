{{!Avalon-MM slave register bank: control, status, scratch, version; two-process style}}
{{>header.vhd}}

-- Register map (32-bit registers, word addresses as Avalon-MM uses them):
--   0  CONTROL  RW  drives `control`
--   1  STATUS   RO  reads `status`
--   2  SCRATCH  RW  read-back test register
--   3  VERSION  RO  G_VERSION
-- Writes to read-only registers are ignored.  Every access takes one wait
-- state (waitrequest high for one clock); read data comes one clock after the
-- read is accepted, flagged by readdatavalid.  `reset` is active high and
-- synchronous, as Platform Designer expects.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity {{entity|$file}} is
  generic (
    G_VERSION : std_logic_vector(31 downto 0) := x"00010000"
  );
  port (
    clk           : in  std_logic;
    reset         : in  std_logic;
    address       : in  std_logic_vector(1 downto 0);
    read          : in  std_logic;
    readdata      : out std_logic_vector(31 downto 0);
    readdatavalid : out std_logic;
    write         : in  std_logic;
    writedata     : in  std_logic_vector(31 downto 0);
    byteenable    : in  std_logic_vector(3 downto 0);
    waitrequest   : out std_logic;
    -- user logic
    control       : out std_logic_vector(31 downto 0);
    status        : in  std_logic_vector(31 downto 0)
  );
end entity {{entity}};

architecture rtl of {{entity}} is

  type reg_type is record
    control : std_logic_vector(31 downto 0);
    scratch : std_logic_vector(31 downto 0);
    rdata   : std_logic_vector(31 downto 0);
    rvalid  : std_logic;
    phase   : std_logic;                         -- '0': first clock of an access (wait)
  end record reg_type;

  constant REG_RESET : reg_type := (
    control => (others => '0'),
    scratch => (others => '0'),
    rdata   => (others => '0'),
    rvalid  => '0',
    phase   => '0'
  );

  signal r, rin : reg_type := REG_RESET;

begin

  comb : process (all)
    variable v     : reg_type;
    variable index : natural range 0 to 3;
  begin
    v        := r;
    index    := to_integer(unsigned(address));
    v.rvalid := '0';

    if read = '1' or write = '1' then
      if r.phase = '0' then
        v.phase := '1';                          -- insert the wait state
      else
        v.phase := '0';                          -- access is accepted now
        if write = '1' then
          case index is
            when 0 =>
              for i in 0 to 3 loop
                if byteenable(i) = '1' then
                  v.control(8 * i + 7 downto 8 * i) := writedata(8 * i + 7 downto 8 * i);
                end if;
              end loop;
            when 2 =>
              for i in 0 to 3 loop
                if byteenable(i) = '1' then
                  v.scratch(8 * i + 7 downto 8 * i) := writedata(8 * i + 7 downto 8 * i);
                end if;
              end loop;
            when others =>
              null;                              -- read-only
          end case;
        else
          case index is
            when 0      => v.rdata := r.control;
            when 1      => v.rdata := status;
            when 2      => v.rdata := r.scratch;
            when others => v.rdata := G_VERSION;
          end case;
          v.rvalid := '1';
        end if;
      end if;
    end if;
    {{_}}

    if reset = '1' then                          -- everything but the read data
      v.control := (others => '0');
      v.scratch := (others => '0');
      v.rvalid  := '0';
      v.phase   := '0';
    end if;

    rin <= v;

    -- Same-cycle output: it must answer the read or write of this clock.
    waitrequest   <= '1' when (read = '1' or write = '1') and r.phase = '0' else '0';
    readdata      <= r.rdata;
    readdatavalid <= r.rvalid;
    control       <= r.control;
  end process comb;

  regs : process (clk)
  begin
    if rising_edge(clk) then
      r <= rin;
    end if;
  end process regs;

end architecture rtl;
