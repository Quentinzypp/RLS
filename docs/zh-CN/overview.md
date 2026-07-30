# 项目概览

RLS Self-Interference Cancellation Soft IP 是 12 阶复数递归最小二乘数字自干扰对消实现。仓库同时保留 FPGA 原型的 handwritten hierarchy 参考、无 Xilinx 生成 IP 的 ASIC-portable RTL，以及使用 aligned Radix-4 divider 的优化顶层。

推荐集成模块是 `RLS12_c_MW_top_divopt`。公开证据覆盖 ModelSim 长时间收敛、divider 等价与隔离块综合、DC 顶层标准单元逻辑诊断和旧 Vivado routed baseline。

## 证据边界

- 收敛结论为 `IMPLEMENTATION_RESIDUAL_CONVERGENCE_OBSERVED`。
- 算法/拼接边界为 `RTL_OBSERVED_A0`，当前只验证 single-reference alias mode。
- DC 结果是 pre-layout、typical-only、SRAM excluded 的逻辑诊断。
- 未完成布局布线、signoff、完整 PPA 或 tapeout readiness。

量化入口见 [`public_results.csv`](../../reports/showcase/public_results.csv)，声明与来源映射见 [`evidence_index.md`](../../reports/showcase/evidence_index.md)。
