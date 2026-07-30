# 限制与非声明

本仓库没有完成或声称以下内容：布局布线、signoff STA、DRC/LVS、tapeout readiness、silicon proof、完整 RTL-to-GDS、完整 PPA、100 MHz achieved、power optimized、Formality、GLS 或在线 CI PASS。

收敛数据基于一组固定实现向量，边界是 `IMPLEMENTATION_RESIDUAL_CONVERGENCE_OBSERVED`。implementation oracle 与 RTL 的 bit-accurate 关系不能替代独立系统算法 golden model、RF channel sweep 或硬件测量。

18 个 SRAM wrapper 缺少授权宏视图。DC 顶层结果排除 SRAM area/timing/power；功耗活动映射不足并有 PWR-415。旧 Vivado baseline 不是新 divopt 比较，且没有正式 Fmax sweep。

未提交的 Vivado comparison、原始 WLF/VCD、大型逐周期数据、XCI、PDK、许可证和商业工具 payload 均被排除。
