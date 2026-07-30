# 验证方法

验证流程从确定性二进制向量开始。原始 Xilinx hierarchy 先形成 implementation oracle，portable/divopt RTL 再在相同调度下比较 residual、12-tap serialized weights 和 update intervals。

保存的正式结果覆盖 174,918 个 residual samples、12,000 个 weights，均为零 mismatch；1,000-update divopt run 的 valid X/Z 为 0。两路 50-update moving RMS 分析分别在 update 684/689 首次进入最终功率 110% 阈值并连续保持。

## Fresh 与 preserved

- `reports/modelsim/` 保存净化后的正式指标和压缩曲线。
- `Launch-ConvergenceSimulation.ps1` 在 `build/` 重新生成逐周期 capture，再与 preserved metrics 比较。
- `Invoke-DividerCheck.ps1` 独立验证 1,160 个 divider vector、protocol、reset interruption 和 40-edge aligned latency。

两类证据都不等同于 Formality、GLS、silicon validation 或 RF 端到端验证。
