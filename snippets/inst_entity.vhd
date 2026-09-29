{{!Direct entity instantiation with generic map and port map}}
u_{{inst|inst}} : entity work.{{ent|entity_name}}
  generic map (
    G_WIDTH => 8
  )
  port map (
    clk => clk,
    rst => rst{{_}}
  );
