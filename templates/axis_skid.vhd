{{!AXI4-Stream register slice (skid buffer): registered data and ready, two-process style}}
{{>header.vhd}}

-- Breaks the combinational path from m_tready to s_tready and registers the
-- data path, without losing throughput.  Two storage words: the output
-- register and the skid register that catches a word when the sink stalls.

library ieee;
use ieee.std_logic_1164.all;

entity {{entity|$file}} is
  generic (
    G_WIDTH : positive := {{width|8}}
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;                            -- synchronous, active high
    -- slave (input) side
    s_tdata  : in  std_logic_vector(G_WIDTH - 1 downto 0);
    s_tlast  : in  std_logic;
    s_tvalid : in  std_logic;
    s_tready : out std_logic;
    -- master (output) side
    m_tdata  : out std_logic_vector(G_WIDTH - 1 downto 0);
    m_tlast  : out std_logic;
    m_tvalid : out std_logic;
    m_tready : in  std_logic
  );
end entity {{entity}};

architecture rtl of {{entity}} is

  -- tlast is stored together with tdata: (G_WIDTH) = tlast.
  type reg_type is record
    o_word  : std_logic_vector(G_WIDTH downto 0);   -- output register
    k_word  : std_logic_vector(G_WIDTH downto 0);   -- skid register
    o_valid : std_logic;
    k_valid : std_logic;
  end record reg_type;

  constant REG_RESET : reg_type := (
    o_word  => (others => '0'),
    k_word  => (others => '0'),
    o_valid => '0',
    k_valid => '0'
  );

  signal r, rin : reg_type := REG_RESET;

begin

  comb : process (all)
    variable v      : reg_type;
    variable o_free : boolean;                    -- output register can take a word
  begin
    v      := r;
    o_free := (r.o_valid = '0') or (m_tready = '1');

    if r.k_valid = '1' then                       -- stalled word goes first
      if o_free then
        v.o_word  := r.k_word;
        v.o_valid := '1';
        v.k_valid := '0';
      end if;
    elsif s_tvalid = '1' then                     -- s_tready is high here
      if o_free then
        v.o_word  := s_tlast & s_tdata;
        v.o_valid := '1';
      else
        v.k_word  := s_tlast & s_tdata;           -- sink stalled: park it
        v.k_valid := '1';
      end if;
    elsif o_free then
      v.o_valid := '0';
    end if;
    {{_}}

    if rst = '1' then                             -- the valid flags only
      v.o_valid := '0';
      v.k_valid := '0';
    end if;

    rin <= v;

    s_tready <= not r.k_valid;                    -- registered: skid register is empty
    m_tdata  <= r.o_word(G_WIDTH - 1 downto 0);
    m_tlast  <= r.o_word(G_WIDTH);
    m_tvalid <= r.o_valid;
  end process comb;

  regs : process (clk)
  begin
    if rising_edge(clk) then
      r <= rin;
    end if;
  end process regs;

end architecture rtl;
