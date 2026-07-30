# RLS ASIC diagnostic baseline constraints.
# Period-dependent budgets scale with RLS_CLOCK_PERIOD_NS for the T4.04 scan.

if {[info exists ::env(RLS_CLOCK_PERIOD_NS)] && $::env(RLS_CLOCK_PERIOD_NS) ne ""} {
    set rls_clock_period_ns [expr {double($::env(RLS_CLOCK_PERIOD_NS))}]
} else {
    set rls_clock_period_ns 10.000
}
if {$rls_clock_period_ns <= 0.0} {
    error "RLS_CLOCK_PERIOD_NS must be positive"
}

set rls_setup_uncertainty_ns [expr {$rls_clock_period_ns * 0.05}]
set rls_hold_uncertainty_ns  [expr {$rls_clock_period_ns * 0.02}]
set rls_input_delay_max_ns   [expr {$rls_clock_period_ns * 0.20}]
set rls_input_delay_min_ns   [expr {$rls_clock_period_ns * 0.05}]
set rls_output_delay_max_ns  [expr {$rls_clock_period_ns * 0.20}]
set rls_output_delay_min_ns  [expr {$rls_clock_period_ns * -0.05}]
set rls_clock_transition_ns  [expr {$rls_clock_period_ns * 0.05}]
set rls_max_transition_ns    [expr {$rls_clock_period_ns * 0.10}]
set rls_output_load_pf       0.007264
set rls_max_fanout           16

set rls_clock_port [get_ports -quiet clk]
set rls_reset_port [get_ports -quiet rst_n]
if {[sizeof_collection $rls_clock_port] != 1 || [sizeof_collection $rls_reset_port] != 1} {
    error "Expected exactly one clk and one rst_n port"
}

create_clock -name rls_clk -period $rls_clock_period_ns \
    -waveform [list 0.0 [expr {$rls_clock_period_ns / 2.0}]] $rls_clock_port
set_clock_uncertainty -setup $rls_setup_uncertainty_ns [get_clocks rls_clk]
set_clock_uncertainty -hold  $rls_hold_uncertainty_ns  [get_clocks rls_clk]
set_clock_transition $rls_clock_transition_ns [get_clocks rls_clk]

set rls_timed_inputs [remove_from_collection [all_inputs] [add_to_collection $rls_clock_port $rls_reset_port]]
set rls_timed_outputs [all_outputs]
if {[sizeof_collection $rls_timed_inputs] != 195} {
    error "Expected 195 timed input bits, found [sizeof_collection $rls_timed_inputs]"
}
if {[sizeof_collection $rls_timed_outputs] != 144} {
    error "Expected 144 timed output bits, found [sizeof_collection $rls_timed_outputs]"
}

set_input_delay -clock rls_clk -max $rls_input_delay_max_ns $rls_timed_inputs
set_input_delay -clock rls_clk -min $rls_input_delay_min_ns $rls_timed_inputs
set_output_delay -clock rls_clk -max $rls_output_delay_max_ns $rls_timed_outputs
set_output_delay -clock rls_clk -min $rls_output_delay_min_ns $rls_timed_outputs
set_driving_cell -library gscl45nm -lib_cell BUFX4 -pin Y $rls_timed_inputs
set_load $rls_output_load_pf $rls_timed_outputs

set_max_transition $rls_max_transition_ns [current_design]
set_max_fanout $rls_max_fanout [current_design]

set rls_reset_sync_clear_pins [get_pins -hierarchical -quiet "*sync_*_reg/clear"]
if {[sizeof_collection $rls_reset_sync_clear_pins] != 2} {
    error "Expected exactly two reset synchronizer asynchronous clear pins"
}
set rls_reset_sync_clear_names [lsort [get_object_name $rls_reset_sync_clear_pins]]
set rls_expected_reset_sync_clear_names [lsort [list \
    u_reset_sync/sync_meta_reg/clear \
    u_reset_sync/sync_release_reg/clear]]
if {$rls_reset_sync_clear_names ne $rls_expected_reset_sync_clear_names} {
    error "Reset synchronizer clear-pin names changed: $rls_reset_sync_clear_names"
}
set_false_path -from $rls_reset_port -to $rls_reset_sync_clear_pins
