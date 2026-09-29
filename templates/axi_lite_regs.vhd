{{!AXI4-Lite slave with a small register map (control, status, scratch, version)}}
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

  signal control_r : std_logic_vector(31 downto 0) := (others => '0');
  signal scratch_r : std_logic_vector(31 downto 0) := (others => '0');

  signal awready_r : std_logic := '0';
  signal wready_r  : std_logic := '0';
  signal bvalid_r  : std_logic := '0';
  signal bresp_r   : std_logic_vector(1 downto 0) := C_OKAY;
  signal arready_r : std_logic := '0';
  signal rvalid_r  : std_logic := '0';
  signal rdata_r   : std_logic_vector(31 downto 0) := (others => '0');

begin

  s_axi_awready <= awready_r;
  s_axi_wready  <= wready_r;
  s_axi_bvalid  <= bvalid_r;
  s_axi_bresp   <= bresp_r;
  s_axi_arready <= arready_r;
  s_axi_rvalid  <= rvalid_r;
  s_axi_rdata   <= rdata_r;
  s_axi_rresp   <= C_OKAY;
  control       <= control_r;

  p_axi : process (aclk)
    variable wr_go : boolean;
    variable rd_go : boolean;
    variable index : natural range 0 to 3;
  begin
    if rising_edge(aclk) then
      -- Write: take address and data together, answer one clock later.
      awready_r <= '0';
      wready_r  <= '0';
      wr_go := s_axi_awvalid = '1' and s_axi_wvalid = '1'
               and awready_r = '0' and bvalid_r = '0';
      if wr_go then
        awready_r <= '1';
        wready_r  <= '1';
        bvalid_r  <= '1';
        bresp_r   <= C_OKAY;
        index := to_integer(unsigned(s_axi_awaddr(3 downto 2)));
        case index is
          when C_REG_CONTROL =>
            for i in 0 to 3 loop
              if s_axi_wstrb(i) = '1' then
                control_r(8 * i + 7 downto 8 * i) <= s_axi_wdata(8 * i + 7 downto 8 * i);
              end if;
            end loop;
          when C_REG_SCRATCH =>
            for i in 0 to 3 loop
              if s_axi_wstrb(i) = '1' then
                scratch_r(8 * i + 7 downto 8 * i) <= s_axi_wdata(8 * i + 7 downto 8 * i);
              end if;
            end loop;
          when others =>
            bresp_r <= C_SLVERR;                -- read-only register
        end case;
      elsif s_axi_bready = '1' then
        bvalid_r <= '0';
      end if;

      -- Read: latch the data, hold it until the master takes it.
      arready_r <= '0';
      rd_go := s_axi_arvalid = '1' and arready_r = '0' and rvalid_r = '0';
      if rd_go then
        arready_r <= '1';
        rvalid_r  <= '1';
        index := to_integer(unsigned(s_axi_araddr(3 downto 2)));
        case index is
          when C_REG_CONTROL => rdata_r <= control_r;
          when C_REG_STATUS  => rdata_r <= status;
          when C_REG_SCRATCH => rdata_r <= scratch_r;
          when others        => rdata_r <= G_VERSION;
        end case;
      elsif s_axi_rready = '1' then
        rvalid_r <= '0';
      end if;

      if aresetn = '0' then
        control_r <= (others => '0');
        scratch_r <= (others => '0');
        awready_r <= '0';
        wready_r  <= '0';
        bvalid_r  <= '0';
        arready_r <= '0';
        rvalid_r  <= '0';
      end if;
    end if;
  end process p_axi;
  {{_}}

end architecture rtl;
