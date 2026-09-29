{{!Vivado non-project batch build: synth, place, route, timing gate, bitstream}}
{{>header.hash}}

# Usage:  vivado -mode batch -source build.tcl
# Layout: rtl/*.vhd  constraints/*.xdc  ->  build/ (checkpoints, reports, .bit)

set part   "{{part|xc7a35ticsg324-1L}}"
set top    "{{top|top_level}}"
set outdir "build"
file mkdir $outdir

read_vhdl -vhdl2008 [glob rtl/*.vhd]
read_xdc [glob constraints/*.xdc]

synth_design -top $top -part $part
write_checkpoint -force $outdir/post_synth.dcp
report_utilization -file $outdir/utilization_synth.rpt

opt_design
place_design
route_design
write_checkpoint -force $outdir/post_route.dcp
report_utilization -file $outdir/utilization.rpt
report_timing_summary -file $outdir/timing.rpt
report_clock_interaction -file $outdir/clock_interaction.rpt
report_cdc -file $outdir/cdc.rpt

# Stop before the bitstream when setup timing is not met.
set wns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
if {$wns < 0} {
  puts "ERROR: setup timing not met (WNS = $wns ns), see $outdir/timing.rpt"
  exit 1
}

write_bitstream -force $outdir/$top.bit
{{_}}
