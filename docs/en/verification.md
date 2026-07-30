# Verification

Deterministic vectors drive the original Xilinx hierarchy and the portable/divopt implementation under a common event schedule. Preserved comparison covers 174,918 residual samples and 12,000 serialized weights with zero mismatch. The 1,000-update divopt run has zero valid X/Z.

`reports/modelsim/` contains sanitized preserved metrics and the compact 50-update moving-RMS curve. The convergence runner recreates full capture under ignored `build/` and compares fresh metrics against preserved evidence. The divider runner independently checks 1,160 vectors, reset interruption, protocol behavior, and 40-edge aligned latency.

These tests are not Formality, gate-level simulation, silicon validation, or end-to-end RF validation.
