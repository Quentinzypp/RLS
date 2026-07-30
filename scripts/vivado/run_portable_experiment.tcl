foreach variable {RLS_ROOT RLS_VIVADO_BUILD RLS_VIVADO_PART RLS_VIVADO_CLOCK_NS} {
    if {![info exists ::env($variable)] || $::env($variable) eq ""} {error "$variable is missing"}
}
set root [file normalize $::env(RLS_ROOT)]
set build [file normalize $::env(RLS_VIVADO_BUILD)]
set stream [open [file join $root rtl filelists divopt.f] r]
set sources [list]
while {[gets $stream line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string index $line 0] eq "#"} {continue}
    lappend sources [file join $root $line]
}
close $stream
read_verilog -sv $sources
synth_design -top RLS12_c_MW_top_divopt -part $::env(RLS_VIVADO_PART)
create_clock -name clk -period $::env(RLS_VIVADO_CLOCK_NS) [get_ports clk]
report_utilization -file [file join $build utilization_synth.rpt]
report_timing_summary -file [file join $build timing_summary_synth.rpt]
report_methodology -file [file join $build methodology_synth.rpt]
exit
