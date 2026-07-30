# ASIC frontend results

The aligned Radix-4 divider passed 1,160/1,160 vectors with zero mismatch and 40-edge compatibility latency. Isolated standard-cell logic area changed from 108089.645137 to 18365.116790 (-83.009%); 10 ns WNS changed from -191.04 ns to +3.13 ns.

At top level, 10 ns standard-cell logic area fell 5.586154%, but WNS remained -0.09 ns. Timing is not met. Eighteen SRAM wrappers hold 3,257,856 bits without authorized macro views, so SRAM/full-IP PPA is `NOT_AVAILABLE`. Sequential SAIF mapping is 54.64% with PWR-415; power and energy/update are `NOT_EVALUABLE`.

All DC numbers are FreePDK45/GSCL45 typical-only 1.10 V/27 C pre-layout diagnostics, not signoff.
