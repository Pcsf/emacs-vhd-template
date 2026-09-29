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

## I2C (i2c_master / i2c_slave): open-drain pads need a pull-up, internal or external
# set_property -dict { PACKAGE_PIN <pin> IOSTANDARD LVCMOS33 PULLUP true } [get_ports i2c_scl]
# set_property -dict { PACKAGE_PIN <pin> IOSTANDARD LVCMOS33 PULLUP true } [get_ports i2c_sda]
# set_false_path -from [get_ports {i2c_scl i2c_sda}]

## Configuration
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## Input / output timing (relative to sys_clk)
# set_input_delay  -clock sys_clk -max 2.0 [get_ports din]
# set_input_delay  -clock sys_clk -min 0.5 [get_ports din]
# set_output_delay -clock sys_clk -max 2.0 [get_ports dout]

## Clock domain crossings: one constraint per crossing structure.  A blanket
## set_clock_groups hides forgotten crossings, so prefer the targeted ones and
## run report_cdc.  Replace u_* by your instance paths and <T> by the period
## of the destination clock in ns.
# set_clock_groups -asynchronous -group [get_clocks clk_a] -group [get_clocks clk_b]

## sync_2ff: bound the net into the first synchronizer flop
# set_max_delay -datapath_only -from [get_cells u_src/sig_reg] -to [get_cells u_sync/sync_reg[0]] <T>

## pulse_sync: toggle into the destination synchronizer
# set_max_delay -datapath_only -from [get_cells u_ps/toggle_reg] -to [get_cells u_ps/sync_reg[0]] <T>

## reset_sync: asynchronous assertion reaches the preset pins
# set_false_path -to [get_pins u_reset_sync/sync_reg[*]/PRE]

## bus_sync_handshake: word (bounded latency and skew) and both toggles
# set_max_delay -datapath_only -from [get_cells u_hs/data_hold_reg[*]] -to [get_cells u_hs/dst_data_r_reg[*]] <T>
# set_bus_skew  -from [get_cells u_hs/data_hold_reg[*]] -to [get_cells u_hs/dst_data_r_reg[*]] <T/2>
# set_max_delay -datapath_only -from [get_cells u_hs/req_tgl_reg] -to [get_cells u_hs/req_sync_reg[0]] <T>
# set_max_delay -datapath_only -from [get_cells u_hs/ack_tgl_reg] -to [get_cells u_hs/ack_sync_reg[0]] <T_src>

## fifo_async: Gray pointers in both directions
# set_max_delay -datapath_only -from [get_cells u_fifo/wr_gray_reg[*]] -to [get_cells u_fifo/wr_gray_r1_reg[*]] <T_rd>
# set_bus_skew  -from [get_cells u_fifo/wr_gray_reg[*]] -to [get_cells u_fifo/wr_gray_r1_reg[*]] <T_rd/2>
# set_max_delay -datapath_only -from [get_cells u_fifo/rd_gray_reg[*]] -to [get_cells u_fifo/rd_gray_w1_reg[*]] <T_wr>
# set_bus_skew  -from [get_cells u_fifo/rd_gray_reg[*]] -to [get_cells u_fifo/rd_gray_w1_reg[*]] <T_wr/2>
{{_}}
