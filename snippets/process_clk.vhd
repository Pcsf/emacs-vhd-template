{{!Clocked process with synchronous reset}}
p_{{label|reg}} : process ({{clk|clk}})
begin
  if rising_edge({{clk}}) then
    if {{rst|rst}} = '1' then
      {{_}}
    else
      null;
    end if;
  end if;
end process p_{{label}};
