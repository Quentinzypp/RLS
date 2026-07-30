# ASIC 前端结果

选中的 `DIV_ITERATIVE_RADIX4_ALIGNED` 在 1,160/1,160 checker 中零 mismatch，保持 40-edge compatibility latency。隔离 divider 的标准单元逻辑面积从 108089.645137 降到 18365.116790，减少 83.009%；10 ns WNS 从 -191.04 ns 变为 +3.13 ns。

顶层 10 ns 点的标准单元逻辑面积从 2403588.477132 降到 2269320.333519，减少 5.586154%，但 WNS 仍为 -0.09 ns，因此不是 timing PASS。

## Blockers

- 18 个 SRAM wrapper / 3,257,856 bits 没有授权宏时序、面积和功耗视图。
- SRAM-crossing STA、SRAM area/power 和 full-IP PPA 为 `NOT_AVAILABLE`。
- SAIF sequential mapping 为 54.64%，DC 报告 PWR-415；power 和 energy/update 为 `NOT_EVALUABLE`。
- FreePDK45/GSCL45 typical-only 1.10 V/27 C 只用于前端诊断，不是 signoff corner set。
