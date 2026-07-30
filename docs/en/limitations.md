# Limitations and non-claims

This repository does not claim place-and-route completion, signoff STA, DRC/LVS, tapeout readiness, silicon proof, full RTL-to-GDS, complete PPA, 100 MHz achievement, power optimization, Formality, GLS, or online CI PASS.

Convergence uses one fixed implementation vector set and is bounded by `IMPLEMENTATION_RESIDUAL_CONVERGENCE_OBSERVED`. Bit-accurate implementation-oracle correlation does not replace an independent system algorithm model, RF channel sweep, or hardware measurement.

Eighteen SRAM wrappers lack authorized macro views. DC top results exclude SRAM area/timing/power. Power activity mapping is incomplete with PWR-415. The previous Vivado baseline is not a new divopt comparison and includes no formal Fmax sweep.
