# RLS ASIC/FPGA Portable RTL Specification

**Document class:** Public compact reference guide\
**Implementation boundary:** `RTL_OBSERVED_A0`\
**Convergence boundary:** `IMPLEMENTATION_RESIDUAL_CONVERGENCE_OBSERVED`\
**Source snapshot:** `44f433808e4c7884c3ba488c5b20d764500bd5fa`

## 1. Scope

This specification describes the public integration, data-path, fixed-point, verification, FPGA-prototype, and ASIC-frontend boundaries of a 12-tap complex RLS self-interference cancellation Soft IP. It is synchronized into Markdown, DOCX, and PDF for review.

The recommended top is `RLS12_c_MW_top_divopt`. The package includes portable synthesizable RTL, an aligned Radix-4 divider, deterministic test vectors, implementation-oracle code, ModelSim runners, public constraints, sanitized evidence, and documentation generators.

## 2. Non-scope

The package does not include or claim generated Xilinx IP, PDK/library payloads, SRAM macros, backend implementation, signoff, full PPA, tapeout readiness, silicon proof, Formality, GLS, or an authoritative independent system-algorithm golden pass.

## 3. Integration interface

| Port group | Width | Direction | Contract |
| --- | ---: | --- | --- |
| `clk`, `rst_n` | 1 | input | Single clock; asynchronous assertion and synchronized internal release |
| `BUF_len` | 14 | input | Buffer length; public convergence run uses 1000 |
| `sel_en` | 1 | input | Input sample valid |
| `sel_rx` | 48 | input | Desired/received complex sample, upper-real/lower-imag |
| `sel_fb1`, `sel_fb2` | 48 each | input | Reference samples; accepted mode requires equality |
| `in_var_p` | 36 | input | P initialization parameter, signed 36Q29 |
| `RLS_out_rdy`, `RLS_out` | 1, 48 | output | Residual-valid and packed residual |
| `coef_update_plus`, `coef_update_en`, `coef_update_data` | 1, 1, 72 | output | Update event and serialized signed 36Q27 complex weights |
| `update_cnt` | 20 | output | Observed RLS update counter |
| `reset_ready` | 1 | output | Synchronized reset-release boundary |

### 3.1 Alias mode

The current verified mode is single-reference alias mode: `sel_fb1 == sel_fb2`. The two physical ports feed different internal splice paths, but independent dual-reference behavior is not specified or verified.

## 4. Algorithm data flow

The datapath is: input FIFO/pack memory; 12-tap complex prediction; residual `E=D-Y`; P-vector product and denominator; reciprocal through the aligned Radix-4 iterative divider; gain K; W update; P rank-1 update; residual, weights, and status outputs.

P initializes to `8I`. The matrix core schedule is 150 cycles. External packing yields a 175-cycle steady update interval, plus one accepted 208-cycle refill in the 1,000-update vector run.

## 5. Fixed-point formats

| Quantity | Signed format | Arithmetic note |
| --- | --- | --- |
| Input components | 24Q13 | External upper-real/lower-imag packing |
| P matrix components | 36Q29 | Initial diagonal raw value 4294967296 |
| Weight components | 36Q27 | Twelve complex taps |
| Y and E components | 36Q25 | Residual is desired minus prediction |
| Denominator components | 34Q25 | Quantized forgetting-factor contribution |
| K/reciprocal components | 24Q20 | Divider computes an intermediate signed Q32 quotient |
| P-update accumulator | 40 bits | Per real/imag component |

RTL-defined two's-complement wrap, bit slicing, and truncation are part of the implementation contract. Saturation is not implied. Internal lane ordering can differ from the external port ordering and is defined by explicit concatenations at each boundary.

## 6. Divider architecture

The baseline expanded 40-bit quotient pipeline is replaced by `DIV_ITERATIVE_RADIX4_ALIGNED`. The selected implementation retains 40 accepted-edge latency and uses a 37-cycle initiation interval within the 175-cycle RLS schedule.

The exact checker covers 1,160 vectors and reports zero mismatches, unknowns, latency errors, and protocol errors. Divider block standard-cell logic area changes from 108089.645137 to 18365.116790 (-83.009%), and 10 ns WNS changes from -191.04 ns to +3.13 ns. These are isolated pre-layout diagnostic results.

## 7. Memory architecture

| Wrapper class | Instances | Geometry | Total bits | Read-during-write |
| --- | ---: | --- | ---: | --- |
| Deep FIFO SRAM | 4 | 48 x 16384 | 3145728 | old data |
| Pack RAM SRAM | 2 | 48 x 16 | 1536 | new data |
| P-matrix SRAM | 12 | 72 x 128 | 110592 | old data |

The 18 wrappers total 3,257,856 bits. They define the macro-binding boundary; no authorized SRAM timing, area, power, LEF, GDS, or MBIST payload is included.

## 8. ModelSim verification

The preserved ModelSim SE-64 10.6d run uses top `test_rls_convergence` and DUT `RLS12_c_MW_top_divopt`. It completes 1,000 updates and 12,000 serialized weights with schedule `175:998;208:1` and zero valid X/Z.

Channel 1 moving analysis observes RMS `2784.158 -> 19.338`, 43.166 dB power reduction, and a stable marker at update 684. Channel 2 observes RMS `2778.053 -> 19.112`, 43.249 dB, and update 689. Original implementation versus divopt comparison covers 174,918 residual samples and 12,000 weights with zero mismatch.

The observed convergence boundary is implementation residual behavior only. It does not establish RF cancellation over arbitrary channels or authoritative independent algorithm correctness.

## 9. ASIC frontend diagnosis

Phase 4 status is `PHASE4_OPTIMIZATION_PARTIAL_WITH_EXPLICIT_BLOCKERS`. At the 10 ns top point, standard-cell logic area falls 5.586154%, but WNS remains -0.09 ns and timing is not met.

Results use FreePDK45/GSCL45 typical-only at 1.10 V and 27 C with medium mapping effort. SRAM area/power, SRAM-crossing timing, full-IP PPA, power, and energy/update are unavailable or not evaluable. Sequential SAIF mapping is 54.64% and DC reports PWR-415.

## 10. FPGA prototype baseline

The accepted Vivado 2024.2 routed baseline for `RLS12_c_MW_top` reports 21,535 LUT, 42,855 registers, 103 BRAM Tile, and 352 DSP48E2. At a 65.104 ns clock constraint, setup WNS is +55.532 ns, TNS is zero, and worst hold slack is +0.010 ns.

No formal Fmax sweep exists. The reciprocal of the 9.460 ns worst routed data path is not a validated Fmax. FPGA resource classes are not directly convertible to ASIC standard-cell area, SRAM area, or STA.

## 11. Reproduction

Run `scripts/simulation/Launch-ConvergenceSimulation.ps1` for the public 1,000-update divopt simulation and `scripts/simulation/Invoke-DividerCheck.ps1` for the 1,160-vector divider check. Generated large artifacts remain under ignored `build/`.

Commercial EDA tools, licenses, PDKs, and macro libraries are supplied legally by the user and are not repository payloads. The DC frontend accepts explicit target/link library paths. The Vivado directory documents only a portable experimental path because the generated-XCI baseline is not redistributable here.

## 12. Limitations

The implementation is not presented as tapeout-ready, silicon-proven, full RTL-to-GDS, complete PPA, 100 MHz achieved, power optimized, or signoff complete. The new Vivado original/divopt comparison remains uncommitted and excluded. Only the previous accepted FPGA baseline is public.
