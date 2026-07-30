# 定点格式与算术边界

| 对象 | 格式 | 备注 |
| --- | --- | --- |
| 输入 | signed 24Q13 / component | 外部 upper-real/lower-imag |
| P | signed 36Q29 | `P0=8I` |
| W | signed 36Q27 | 12 个复数 tap |
| prediction/residual | signed 36Q25 | `E=D-Y` |
| denominator | signed 34Q25 | 包含量化 lambda |
| gain/reciprocal | signed 24Q20 | divider Q32 后切片 |
| P update accumulator | 40 bit/component | rank-1 update 中间结果 |

RTL 使用固定 bit slice、two's-complement wrap 和 truncation，不使用饱和算术。implementation oracle 保留相同顺序、树形求和和 ties-to-negative-infinity divider 规则，用于 RTL 相关性检查；它不是独立的系统级 golden algorithm。

外部输入打包为 upper-real/lower-imag，部分内部总线采用 upper-imag/lower-real。所有跨边界交换都必须按模块端口处的显式拼接处理，不能只依据 Q 格式推断 lane order。
