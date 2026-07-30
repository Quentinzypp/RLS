# RLS Algorithm Equations and RTL Event Contract

## Status and Scope

- Task: T1B.01 mathematical equation and event-alignment recovery
- Static source audit: **RUN / PASS**
- Fresh ModelSim equation trace: **RUN / PASS**
- Independent asymmetric alignment trace: **RUN / PASS**
- Golden-model or original-RTL functional result: **NOT YET CLAIMED**
- Portable RTL or PPA work: **NOT STARTED**

This document defines the equations that the Phase 1B models must implement. It does not treat a textbook RLS equation as evidence where the frozen RTL implements an explicit quantization, approximation or separate output path.

## Frozen Contract

| Item | Value |
|---|---|
| Order | 12 complex taps |
| External sample packing | `[47:24]=real`, `[23:0]=imaginary`, signed 24Q13 per lane |
| Legal feedback contract | `sel_fb1 == sel_fb2`; one adaptive reference |
| P initialization | `P(0)=8I`, each component signed 36Q29 |
| Encoded lambda | `33551077 / 2^25 = 0.999900013208389` |
| Encoded reciprocal | `65543 / 2^16 = 4194752 / 2^22 = 1.000106811523438` |
| Weight format | signed 36Q27 per component |
| Arithmetic policy | bit-slice truncation, lane-local addition/subtraction, two's-complement wrap, no saturation |
| Fixed-model acceptance | bit-exact versus RTL after valid-event alignment |
| Model authority | `RLS_re_cof.slx` v1.26, SHA-256 `5182AB692005F32AA1A6BE15554F976BD1814BEE4BBBFD85CEDE3BB0E0FE0812` |

The external upper-real/lower-imaginary sample is swapped at the matrix-core boundary. All equations below use mathematical complex values, while bit-level tables use the core's internal packing `[upper]=imaginary`, `[lower]=real`.

## Mathematical Source Model

For desired sample `d(n)`, reference vector `u(n)=[x(n),x(n-1),...,x(n-11)]^T`, weight vector `w(n-1)` and inverse-correlation matrix `P(n-1)`, Simulink v1.26 implements:

```text
A(n)   = P(n-1) u(n)
c(n)   = lambda + u(n)^H A(n)
K(n)   = A(n) / c(n)
y(n)   = w(n-1)^H u(n)
e(n)   = d(n) - y(n)
w(n)   = w(n-1) + K(n) conj(e(n))
P(n)   = P(n-1)/lambda - K(n) [u(n)^H P(n-1)/lambda]
```

This is equivalent to the standard complex RLS form. The conjugated error is consistent with the model's use of `w^H u` rather than `w^T u`.

Simulink evidence is the exported connectivity under `reports/phase1a/simulink_model_lines.csv`: `Delay1 * u` forms `A`; `u^H * A` is added to lambda; the reciprocal multiplies `A`; `P/lambda - K*(u^H P/lambda)` feeds the P delay; and `K*conj(d-w^H u)` feeds the weight delay.

## Implemented RTL Update Equations

The RTL implements the same high-level dependency graph but quantizes every named edge. Define `slice_s(v, hi, lo, W)` as Verilog bit selection `v[hi:lo]` interpreted as a signed `W`-bit two's-complement result. All component additions below wrap to the destination component width.

### 1. Matrix-vector product A

For each row `i`:

```text
product_ij = cmul_36x24(P_ij[36Q29], u_j[24Q13])       # 61Q42/component
A_i        = wrap40(sum_j slice_s(product_ij,52,13,40)) # 40Q29/component
```

The 12 complex multipliers are time-shared across the streamed columns. `rtl_original/handwritten/RLS12_c_matrixP_update.v:1401` selects `P*u`; lines 832-838 perform independent 40-bit lane accumulation.

### 2. Denominator C

The core first converts `A_i` from 40Q29 to 36Q25 with component slice `[39:4]`, multiplies by the conjugated reference, and reduces a balanced 12-term tree:

```text
q_i      = cmul_36x24(A_i[39:4], conj(u_i))             # 61Q38/component
s        = wrap40_tree(sum_i slice_s(q_i,48,9,40))      # 40Q29/component
C_imag   = slice_s(s_imag,37,4,34)
C_real   = wrap34(slice_s(s_real,37,4,34) + 33551077)
C        = C_real + j*C_imag                             # 34Q25/component
```

Unlike the ideal real-positive denominator, the RTL retains a quantized imaginary component and sends both components to a complex divider.

### 3. Custom complex reciprocal D

The reciprocal block calculates `(1+j0)/C`, but it first truncates each 34Q25 operand to signed 25Q16 using `[33:9]`. Six signed 25x25 multipliers form `ac`, `bd`, `ad`, `bc`, `cc` and `dd`; each 50-bit product is sliced `[48:9]` to signed 40Q23. The two signed Divider Generator instances use a 40-bit dividend/divisor and 32 fractional quotient bits.

```text
num_real = wrap40(ac + bd)
num_imag = wrap40(bc - ad)
den      = wrap40(cc + dd)
q_real   = signed_div_fractional(num_real, den, 32)
q_imag   = signed_div_fractional(num_imag, den, 32)
D        = {slice_s(q_imag,30,7,24), slice_s(q_real,30,7,24)} # 24Q20
```

The divider arithmetic and latency come from `float_complex_div.v` plus `mult_div.xci` and `div.xci`; the latter is signed, high-radix, 40-bit, 32-fractional-bit, latency 41.

### 4. Gain K

Each accumulated `A_i` is converted from 40Q29 to 36Q28 using `[36:1]` per component and multiplied by `D`:

```text
K_i = slice_s(cmul_36x24(A_i[36:1], D),51,28,24) # 24Q20/component
```

The packed result is `A1I00..A1I11`, internal upper-imaginary/lower-real.

### 5. Prediction and error

The core prediction uses the newest reference with weight 0 and explicitly conjugates every weight:

```text
y_terms_i = cmul_36x24(conj(w_i[36Q27]), u_i[24Q13])
y         = slice_s(wrap40_tree(sum_i slice_s(y_terms_i,51,12,40)),38,3,36)
e         = wrap36_lane(d[36Q25] - y[36Q25])
```

The result is signed 36Q25 per component. `R0_2I11` is the newest tap and multiplies `w0`; `R0_2I00` is the oldest tap and multiplies `w11`.

### 6. Weight update

```text
g_i  = slice_s(cmul_36x24(conj(e)[36Q25], K_i[24Q20]),53,18,36) # 36Q27
w_i' = wrap36_lane(w_i + g_i)
```

There is no saturation or overflow flag. The core serializer emits `w11,w10,...,w0`; the FIR reload wrapper reverses the sequence according to the generated FIR reload-order file.

### 7. P update

The reciprocal of lambda is applied through two separately encoded but numerically equal constants:

```text
u_lambda_H = slice_s(cmul_24x18(conj(u), 65543),39,16,24)   # 24Q13
B_j        = wrap40(sum_i slice_s(cmul_36x24(P_ij, u_lambda_H_i),51,12,40))
B_j_36     = slice_s(B_j,37,2,36)                            # 36Q28
Pprime_ij  = slice_s(cmul_36x24(P_ij, 4194752),57,22,36)     # 36Q29
KB_ij      = slice_s(cmul_36x24(B_j_36, K_i),54,19,36)       # 36Q29
P_ij'      = wrap36_lane(Pprime_ij - KB_ij)
```

The implemented scalar is `1.000106811523438`, whereas the exact reciprocal of encoded lambda is `1.000099996789970`. This 6.814 ppm relative bias is an intentional frozen-baseline behavior, not a model correction opportunity.

## External Residual Path

`RLS_out` does not expose the matrix core's internal `e(n)`. A separate full-rate dual-FIR path consumes unmodified external `sel_fb2`, reloads the serialized weights, reconstructs a complex sample, aligns `sel_rx` through a FIFO, and subtracts in 24Q13.

With authoritative external packing `x={R,I}` and serialized coefficient `w={WR,WI}`, the two FIR paths and explicit recombination implement, per tap:

```text
reconstructed_real = trunc_Q13(R*WR - I*WI)
reconstructed_imag = trunc_Q13(I*WR + R*WI)
external_residual  = wrap24_lane(desired - reconstructed)
```

Thus the FIR path applies `x*w`, while the matrix prediction applies `w^H*u`. This orientation difference, the coefficient reload latency and the independent full-rate FIFO alignment are mandatory Phase 1B correlation checks. They must not be hidden by comparing only the internal error.

FIR products are 64Q40 per path and are truncated with `{sign, bits[49:27]}` to 24Q13. Phase 1A isolated tests proved input packing `{path1,path0}`, output packing `{path1,path0}`, 29-clock accepted-data latency, signed 36Q27 coefficients and reverse reload ordering.

## Dynamic Event and Sample Alignment

The fresh ModelSim trace uses the unmodified `test_rls` and frozen generated IP. A second testbench drives unique asymmetric sample IDs through the same top and reproduces the original two-cycle rx delay.

| Property | Actual result |
|---|---:|
| First `cal_en` edge after the trace origin | 210 |
| Subsequent `cal_en` interval | 175 clocks |
| Core schedule length | 150 counted clocks |
| `cal_en` to internal `wt_pulse` | 133 clocks |
| Serialized weight words per update | 12 |
| First reference source index, zero-based | 13 |
| First desired source index, zero-based | 11 |
| Reference/desired source-index relationship | desired = reference - 2 |
| Newest tap location after each fill burst | `R0_2I11` |

The first five observed update events are recorded in `reports/phase1b/phase1b_event_alignment.csv`. The script asserts reference indices `13..17`, desired indices `11..15`, 175-clock update spacing, 133-clock weight-pulse latency and 60 total serialized weight words.

The source-index offset is not a mathematical RLS requirement. It is the actual frozen-testbench behavior caused by startup FIFO/reset-busy interaction plus the explicit two-cycle receive delay. A future integration interface may change it only after a correlated portable baseline exists.

## Known RTL Deviations and Risks

| Item | Classification | Required Phase 1B handling |
|---|---|---|
| Quantized `1/lambda` differs from exact reciprocal | confirmed implementation approximation | preserve in fixed model; quantify against float model |
| Denominator is processed as complex | confirmed implementation behavior | emulate the custom divider exactly |
| Divider truncates 34Q25 to 25Q16 before squaring | confirmed precision loss | preserve and count overflow/wrap |
| P, K, W and accumulators wrap without status | confirmed implementation behavior | implement wrap counters in model |
| Initial pack/P/FIFO same-address collisions | confirmed simulation risk | retain warnings; correlation decides whether a deterministic oracle exists |
| FIFO reset-busy startup drops/shifts source alignment | dynamically confirmed for current testbench | freeze index mapping in oracle provenance |
| External residual uses independent FIR path | confirmed architectural split | check residual separately from internal error |
| FIR complex orientation differs from matrix prediction form | confirmed equation-level difference | report correlation outcome; do not normalize silently |
| External `RLS_out_rdy` can remain asserted after first assertion | confirmed top-level register behavior | checker must use actual event/data contract and detect gaps explicitly |

## Reproduction and Evidence

```powershell
& .\scripts\phase1b\Invoke-Phase1BEquationTrace.ps1
```

Evidence:

- `reports/phase1b/phase1b_equation_compile.log`
- `reports/phase1b/phase1b_equation_trace.log`
- `reports/phase1b/phase1b_equation_event_trace.csv`
- `reports/phase1b/phase1b_alignment_trace.log`
- `reports/phase1b/phase1b_alignment_event_trace.csv`
- `reports/phase1b/phase1b_event_alignment.csv`
- `reports/phase1b/phase1b_equation_source_hashes.csv`

Completion marker: `PHASE1B_T1B01_EQUATION_RECOVERY_PASS`.
