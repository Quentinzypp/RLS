# Overview

RLS Self-Interference Cancellation Soft IP is a 12-tap complex recursive least-squares digital canceller. The repository includes a handwritten FPGA hierarchy reference, XCI-free ASIC-portable RTL, and the optimized aligned Radix-4 top.

The recommended integration module is `RLS12_c_MW_top_divopt`. Public evidence covers long ModelSim convergence, divider equivalence and isolated synthesis, DC standard-cell logic diagnosis, and the previous accepted Vivado routed baseline.

Claims are bounded by `RTL_OBSERVED_A0` and `IMPLEMENTATION_RESIDUAL_CONVERGENCE_OBSERVED`. No place-and-route, signoff, complete PPA, or tapeout readiness is claimed. See the [machine-readable results](../../reports/showcase/public_results.csv) and [evidence index](../../reports/showcase/evidence_index.md).
