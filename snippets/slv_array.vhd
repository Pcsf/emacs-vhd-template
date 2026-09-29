{{!Unconstrained array of std_logic_vector (VHDL-2008 friendly)}}
type {{name|slv_array_t}} is array (natural range <>) of std_logic_vector({{width|7}} downto 0);
signal {{sig|table}} : {{name}}(0 to {{last|3}}) := (others => (others => '0'));
{{_}}
