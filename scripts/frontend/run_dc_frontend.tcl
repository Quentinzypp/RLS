foreach variable {RLS_ROOT RLS_DC_BUILD RLS_DC_TARGET_LIBRARY RLS_DC_LINK_LIBRARIES RLS_DC_TOP RLS_DC_CLOCK_PERIOD_NS} {
    if {![info exists ::env($variable)] || $::env($variable) eq ""} {error "$variable is missing"}
}
set root [file normalize $::env(RLS_ROOT)]
set build [file normalize $::env(RLS_DC_BUILD)]
set target_library [list [file normalize $::env(RLS_DC_TARGET_LIBRARY)]]
set link_library [concat "*" [split $::env(RLS_DC_LINK_LIBRARIES) ";"]]
set search_path [concat $search_path [list $root]]

set sources [list]
set stream [open [file join $root rtl filelists divopt.f] r]
while {[gets $stream line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string index $line 0] eq "#"} {continue}
    lappend sources [file join $root $line]
}
close $stream
analyze -format verilog $sources
elaborate $::env(RLS_DC_TOP)
current_design $::env(RLS_DC_TOP)
link
create_clock -name clk -period $::env(RLS_DC_CLOCK_PERIOD_NS) [get_ports clk]
compile -map_effort medium
redirect [file join $build area.rpt] {report_area -hierarchy}
redirect [file join $build timing.rpt] {report_timing -max_paths 20 -delay_type max}
redirect [file join $build check_design.rpt] {check_design}
write -format verilog -hierarchy -output [file join $build mapped.v]
quit
