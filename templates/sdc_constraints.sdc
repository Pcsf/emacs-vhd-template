{{!SDC (Intel Quartus TimeQuest and most other tools): clock, reset, I/O delays}}
{{>header.hash}}

## Clock
create_clock -name {{clk|clk_in}} -period {{period_ns|10.000}} [get_ports {{clk}}]

## Intel only: PLL outputs and clock uncertainty
# derive_pll_clocks
# derive_clock_uncertainty

## Asynchronous reset button, synchronised inside reset_sync
set_false_path -from [get_ports rst_n]

## Input / output timing
# set_input_delay  -clock {{clk}} -max 2.0 [get_ports din]
# set_input_delay  -clock {{clk}} -min 0.5 [get_ports din]
# set_output_delay -clock {{clk}} -max 2.0 [get_ports dout]

## Clock domain crossings
# set_clock_groups -asynchronous -group [get_clocks clk_a] -group [get_clocks clk_b]
{{_}}
