# Preserved ModelSim convergence evidence

- Tool: ModelSim SE-64 10.6d
- Top / DUT: `test_rls_convergence` / `RLS12_c_MW_top_divopt`
- Observed duration: approximately 11.410517665 ms
- Updates / weights: 1,000 / 12,000
- Schedule: `175:998;208:1`
- Valid X/Z: 0
- Channel 1 RMS: `2784.158 -> 19.338`; power reduction 43.166 dB; stable marker update 684
- Channel 2 RMS: `2778.053 -> 19.112`; power reduction 43.249 dB; stable marker update 689
- Reference/divopt residual comparison: 174,918 samples, zero mismatch
- Reference/divopt weight comparison: 12,000 words, zero mismatch
- Status: `MODELSIM_CONVERGENCE_SIMULATION_PASS`
- Boundary: `IMPLEMENTATION_RESIDUAL_CONVERGENCE_OBSERVED`

The raw WLF, 33 MB combined sample table, per-cycle capture, and large oracle are
not published. `convergence_curve.csv` is a deterministic 50-update moving-RMS
reduction of the trusted per-cycle capture. A fresh run recreates full raw output
under ignored `build/modelsim_convergence/`.
