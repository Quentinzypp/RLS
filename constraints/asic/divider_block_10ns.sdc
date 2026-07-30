# Common Phase 4 divider block comparison constraints.
create_clock -name divider_clk -period 10.000 -waveform {0.000 5.000} [get_ports clk]
set_clock_uncertainty -setup 0.500 [get_clocks divider_clk]
set_clock_uncertainty -hold 0.200 [get_clocks divider_clk]
set_clock_transition 0.500 [get_clocks divider_clk]

set divider_reset [get_ports rst_n]
set divider_inputs [remove_from_collection [all_inputs] [add_to_collection [get_ports clk] $divider_reset]]
set_input_delay -clock divider_clk -max 2.000 $divider_inputs
set_input_delay -clock divider_clk -min 0.500 $divider_inputs
set_output_delay -clock divider_clk -max 2.000 [all_outputs]
set_output_delay -clock divider_clk -min -0.500 [all_outputs]
set_driving_cell -library gscl45nm -lib_cell BUFX4 -pin Y $divider_inputs
set_load 0.007264 [all_outputs]
set_max_transition 1.000 [current_design]
set_max_fanout 16 [current_design]

# rst_n is an asynchronous control input, not a functional data path.
set_false_path -from $divider_reset
