# Phase 0 audit constraint derived directly from test_rls.v:
# always #32.552 clk = ~clk, so period = 65.104 ns.
create_clock -name clk -period 65.104 [get_ports clk]
