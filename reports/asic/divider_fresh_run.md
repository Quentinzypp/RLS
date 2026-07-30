# Fresh public divider reproduction

- Status: **PASS**
- Runner: `scripts/simulation/Invoke-DividerCheck.ps1`
- Vectors: 1,160
- Radix-2 / Radix-4 / aligned outputs: 1,160 / 1,160 / 1,160
- Mismatches / unknowns / latency errors / protocol errors: 0 / 0 / 0 / 0
- Aligned Radix-4 accepted-edge latency: 40
- Marker: `PHASE4_DIVIDER_EXACT_CANDIDATES_PASS`

This fresh result is RTL simulation evidence. Area and timing remain preserved DC
frontend diagnostic evidence in `divider_optimization.csv`.
