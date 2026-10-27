{{!Test case on tb_util_pkg: drive after a rising edge, check on the falling edge (fails until written)}}
tc_start("{{tc|TC-03}}", "{{behaviour|one behaviour, one sentence}}", C_SCOPE);
wait_num_rising_edges(clk, 1);
{{_}}
wait until falling_edge(clk);
check_value({{cond|false}}, "{{msg|what was checked}}", C_SCOPE);
