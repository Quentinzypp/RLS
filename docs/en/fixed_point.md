# Fixed-point contract

| Object | Format | Note |
| --- | --- | --- |
| Input | signed 24Q13/component | external upper-real/lower-imag |
| P | signed 36Q29 | `P0=8I` |
| W | signed 36Q27 | 12 complex taps |
| prediction/residual | signed 36Q25 | `E=D-Y` |
| denominator | signed 34Q25 | includes quantized lambda |
| gain/reciprocal | signed 24Q20 | sliced from divider Q32 |
| P update accumulator | 40 bits/component | rank-1 update intermediate |

RTL-prescribed slicing, truncation, and two's-complement wrap are retained; arithmetic is not saturating. The implementation oracle reproduces these choices for correlation but is not presented as an independent system-level golden algorithm.
