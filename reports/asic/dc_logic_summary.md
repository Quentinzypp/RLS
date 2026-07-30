# DC standard-cell logic diagnosis

- Status: `PHASE4_OPTIMIZATION_PARTIAL_WITH_EXPLICIT_BLOCKERS`
- Selected divider: `DIV_ITERATIVE_RADIX4_ALIGNED`
- Divider exact checker: 1,160/1,160, zero mismatch, 40-edge compatibility latency
- Divider block area: 108089.645137 -> 18365.116790 (-83.009%)
- Divider 10 ns WNS: -191.04 ns -> +3.13 ns
- Top standard-cell logic area: 2403588.477132 -> 2269320.333519 (-5.586154%)
- Divopt top 10 ns WNS: -0.09 ns; this is **not** timing PASS
- Library/PVT: FreePDK45/GSCL45 typical-only, 1.10 V, 27 C
- Method: `compile -map_effort medium`, pre-layout frontend diagnosis

The top excludes SRAM macro area and timing arcs. The results are neither signoff
STA nor full-IP PPA and do not demonstrate layout completion or tapeout readiness.
