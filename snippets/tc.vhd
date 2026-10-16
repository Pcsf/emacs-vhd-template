{{!Test case: drive after a rising edge, check on the falling edge (fails until written)}}
-- {{tc|TC-03}}: {{behaviour|one behaviour, one sentence}}
clocks;
{{_}}
wait until falling_edge(clk);
check({{cond|false}}, "{{tc}} {{behaviour}}");
