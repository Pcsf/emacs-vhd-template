{{!Vivado XDC: clock, reset, pins, false paths (example pins: Digilent Arty A7)}}
{{>header.hash}}

## Clock
set_property -dict { PACKAGE_PIN {{clk_pin|E3}} IOSTANDARD {{iostd|LVCMOS33}} } [get_ports clk_in]
create_clock -name sys_clk -period {{period_ns|10.000}} [get_ports clk_in]

## Reset button: asynchronous, synchronised inside reset_sync
set_property -dict { PACKAGE_PIN {{rst_pin|C2}} IOSTANDARD {{iostd}} } [get_ports rst_n]
set_false_path -from [get_ports rst_n]

## Outputs
set_property -dict { PACKAGE_PIN {{led_pin|H5}} IOSTANDARD {{iostd}} } [get_ports led]

## Configuration
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## Input / output timing (relative to sys_clk)
# set_input_delay  -clock sys_clk -max 2.0 [get_ports din]
# set_input_delay  -clock sys_clk -min 0.5 [get_ports din]
# set_output_delay -clock sys_clk -max 2.0 [get_ports dout]

## Clock domain crossings
# set_clock_groups -asynchronous -group [get_clocks clk_a] -group [get_clocks clk_b]
# set_max_delay -datapath_only -from [get_cells src_reg*] -to [get_cells sync_reg[0]*] 4.0
{{_}}
