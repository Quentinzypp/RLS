# RLS 架构

数据从 desired/received 与 reference 端口进入 FIFO/pack memory。12-tap complex FIR 使用当前 W 形成预测 Y，残差为 `E=D-Y`。矩阵路径计算 P 与输入向量的乘积、denominator、reciprocal 和 gain K，再依次更新 12 个权值与 P 的 rank-1 项。

核心内部一次 RLS 更新调度为 150 cycles；输入打包与外部事件对齐后，稳态更新间隔是 175 cycles。公开 1,000-update run 还包含一次 208-cycle refill，因此直方图为 `175:998;208:1`。

## 接口模式

`sel_fb1` 和 `sel_fb2` 在内部服务于不同数据拼接路径，但当前通过验证的算法合同要求两者连接同一 reference sample。仓库中的 convergence TB 会检查该 alias 关系。`reset_ready` 明确同步复位释放，输入/监视应以它为边界。

## 存储边界

portable RTL 实例化 18 个可综合 SRAM wrapper：4 个 deep FIFO、2 个 pack RAM、12 个 P-matrix SRAM。ASIC 集成必须使用满足读延迟和 read-during-write 合同的宏替换；仓库不提供 Liberty、LEF 或 GDS。
