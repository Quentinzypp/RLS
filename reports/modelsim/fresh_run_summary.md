# Fresh public convergence reproduction

- Status: **PASS**
- Runner: `scripts/simulation/Launch-ConvergenceSimulation.ps1`
- Sources: public `rtl/filelists/divopt.f`
- Vectors: public convergence reference/desired vectors
- Updates / weights: 1,000 / 12,000
- Weight X/Z: 0
- Schedule: `175:998;208:1`
- Capture: 175,263 cycles / 11.410518 ms
- Fresh metrics versus preserved metrics: **MATCH**
- Generated implementation-oracle weights versus fresh RTL: 12,000 / 12,000, zero mismatch
- Implementation-oracle primitive/directed self-tests: 54 / 54 PASS
- Boundary: `IMPLEMENTATION_RESIDUAL_CONVERGENCE_OBSERVED`

The fresh raw capture is generated under ignored `build/modelsim_convergence/`.
The preserved reference-versus-divopt comparison remains separately documented in
`preserved_summary.md`.
