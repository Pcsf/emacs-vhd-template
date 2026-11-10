{{!AXI4-Lite slave register bank: control, status, scratch, version; two-process style}}
{{>header.vhd}}

-- Register map (32-bit registers, byte addresses):
--   0x00  CONTROL  RW  drives `control`
--   0x04  STATUS   RO  reads `status`
--   0x08  SCRATCH  RW  read-back test register
--   0x0C  VERSION  RO  G_VERSION
-- Writes to a read-only register are answered with SLVERR.  Only address bits
-- 3:2 are decoded, so the block repeats every 16 bytes; the interconnect
-- normally decodes the rest.  aresetn is active low, as in AXI.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity {{entity|$file}} is
  generic (
    G_ADDR_WIDTH : positive range 4 to 32 := 4;
    G_VERSION    : std_logic_vector(31 downto 0) := x"00010000"
  );
  port (
    aclk          : in  std_logic;
    aresetn       : in  std_logic;
    -- write address channel
    s_axi_awaddr  : in  std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
    s_axi_awvalid : in  std_logic;
    s_axi_awready : out std_logic;
    -- write data channel
    s_axi_wdata   : in  std_logic_vector(31 downto 0);
    s_axi_wstrb   : in  std_logic_vector(3 downto 0);
    s_axi_wvalid  : in  std_logic;
    s_axi_wready  : out std_logic;
    -- write response channel
    s_axi_bresp   : out std_logic_vector(1 downto 0);
    s_axi_bvalid  : out std_logic;
    s_axi_bready  : in  std_logic;
    -- read address channel
    s_axi_araddr  : in  std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
    s_axi_arvalid : in  std_logic;
    s_axi_arready : out std_logic;
    -- read data channel
    s_axi_rdata   : out std_logic_vector(31 downto 0);
    s_axi_rresp   : out std_logic_vector(1 downto 0);
    s_axi_rvalid  : out std_logic;
    s_axi_rready  : in  std_logic;
    -- user logic
    control       : out std_logic_vector(31 downto 0);
    status        : in  std_logic_vector(31 downto 0)
  );
end entity {{entity}};

architecture rtl of {{entity}} is

  constant C_OKAY   : std_logic_vector(1 downto 0) := "00";
  constant C_SLVERR : std_logic_vector(1 downto 0) := "10";

  constant C_REG_CONTROL : natural := 0;
  constant C_REG_STATUS  : natural := 1;
  constant C_REG_SCRATCH : natural := 2;
  constant C_REG_VERSION : natural := 3;

  type reg_type is record
    control : std_logic_vector(31 downto 0);
    scratch : std_logic_vector(31 downto 0);
    awready : std_logic;
    wready  : std_logic;
    bvalid  : std_logic;
    bresp   : std_logic_vector(1 downto 0);
    arready : std_logic;
    rvalid  : std_logic;
    rdata   : std_logic_vector(31 downto 0);
  end record reg_type;

  constant REG_RESET : reg_type := (
    control => (others => '0'),
    scratch => (others => '0'),
    awready => '0',
    wready  => '0',
    bvalid  => '0',
    bresp   => C_OKAY,
    arready => '0',
    rvalid  => '0',
    rdata   => (others => '0')
  );

  signal r, rin : reg_type := REG_RESET;

begin

  comb : process (all)
    variable v      : reg_type;
    variable wr_go  : boolean;
    variable rd_go  : boolean;
    variable wr_reg : natural range 0 to 3;
    variable rd_reg : natural range 0 to 3;
  begin
    v      := r;
    wr_reg := to_integer(unsigned(s_axi_awaddr(3 downto 2)));
    rd_reg := to_integer(unsigned(s_axi_araddr(3 downto 2)));
    wr_go  := s_axi_awvalid = '1' and s_axi_wvalid = '1'
              and r.awready = '0' and r.bvalid = '0';
    rd_go  := s_axi_arvalid = '1' and r.arready = '0' and r.rvalid = '0';

    -- Write: take address and data together, answer one clock later.
    v.awready := '0';
    v.wready  := '0';
    if wr_go then
      v.awready := '1';
      v.wready  := '1';
      v.bvalid  := '1';
      v.bresp   := C_OKAY;
      case wr_reg is
        when C_REG_CONTROL =>
          for i in 0 to 3 loop
            if s_axi_wstrb(i) = '1' then
              v.control(8 * i + 7 downto 8 * i) := s_axi_wdata(8 * i + 7 downto 8 * i);
            end if;
          end loop;
        when C_REG_SCRATCH =>
          for i in 0 to 3 loop
            if s_axi_wstrb(i) = '1' then
              v.scratch(8 * i + 7 downto 8 * i) := s_axi_wdata(8 * i + 7 downto 8 * i);
            end if;
          end loop;
        when others =>
          v.bresp := C_SLVERR;                  -- read-only register
      end case;
    elsif s_axi_bready = '1' then
      v.bvalid := '0';
    end if;

    -- Read: latch the data, hold it until the master takes it.
    v.arready := '0';
    if rd_go then
      v.arready := '1';
      v.rvalid  := '1';
      case rd_reg is
        when C_REG_CONTROL => v.rdata := r.control;
        when C_REG_STATUS  => v.rdata := status;
        when C_REG_SCRATCH => v.rdata := r.scratch;
        when others        => v.rdata := G_VERSION;
      end case;
    elsif s_axi_rready = '1' then
      v.rvalid := '0';
    end if;
    {{_}}

    if aresetn = '0' then                       -- everything but response and read data
      v.control := (others => '0');
      v.scratch := (others => '0');
      v.awready := '0';
      v.wready  := '0';
      v.bvalid  := '0';
      v.arready := '0';
      v.rvalid  := '0';
    end if;

    rin <= v;

    s_axi_awready <= r.awready;
    s_axi_wready  <= r.wready;
    s_axi_bvalid  <= r.bvalid;
    s_axi_bresp   <= r.bresp;
    s_axi_arready <= r.arready;
    s_axi_rvalid  <= r.rvalid;
    s_axi_rdata   <= r.rdata;
    s_axi_rresp   <= C_OKAY;
    control       <= r.control;
  end process comb;

  regs : process (aclk)
  begin
    if rising_edge(aclk) then
      r <= rin;
    end if;
  end process regs;

end architecture rtl;
