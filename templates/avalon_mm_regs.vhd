{{!Avalon-MM slave with a small register map (control, status, scratch, version), one wait state}}
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

  signal control_r : std_logic_vector(31 downto 0) := (others => '0');
  signal scratch_r : std_logic_vector(31 downto 0) := (others => '0');
  signal rdata_r   : std_logic_vector(31 downto 0) := (others => '0');
  signal rvalid_r  : std_logic := '0';
  signal phase     : std_logic := '0';   -- '0': first clock of an access (wait)

begin

  waitrequest   <= '1' when (read = '1' or write = '1') and phase = '0' else '0';
  readdata      <= rdata_r;
  readdatavalid <= rvalid_r;
  control       <= control_r;

  p_avmm : process (clk)
    variable index : natural range 0 to 3;
  begin
    if rising_edge(clk) then
      rvalid_r <= '0';
      if read = '1' or write = '1' then
        if phase = '0' then
          phase <= '1';                      -- insert the wait state
        else
          phase <= '0';                      -- access is accepted now
          index := to_integer(unsigned(address));
          if write = '1' then
            case index is
              when 0 =>
                for i in 0 to 3 loop
                  if byteenable(i) = '1' then
                    control_r(8 * i + 7 downto 8 * i) <= writedata(8 * i + 7 downto 8 * i);
                  end if;
                end loop;
              when 2 =>
                for i in 0 to 3 loop
                  if byteenable(i) = '1' then
                    scratch_r(8 * i + 7 downto 8 * i) <= writedata(8 * i + 7 downto 8 * i);
                  end if;
                end loop;
              when others =>
                null;                        -- read-only
            end case;
          else
            case index is
              when 0      => rdata_r <= control_r;
              when 1      => rdata_r <= status;
              when 2      => rdata_r <= scratch_r;
              when others => rdata_r <= G_VERSION;
            end case;
            rvalid_r <= '1';
          end if;
        end if;
      end if;
      if reset = '1' then
        control_r <= (others => '0');
        scratch_r <= (others => '0');
        rvalid_r  <= '0';
        phase     <= '0';
      end if;
    end if;
  end process p_avmm;
  {{_}}

end architecture rtl;
