# FPGA 原型结果

旧正式 Vivado 2024.2 baseline 使用 `RLS12_c_MW_top` 和 `xczu48dr-ffvg1517-2-e`。routed 结果为 21,535 LUT、42,855 registers、103 BRAM Tile 和 352 DSP48E2。

在 65.104 ns clock constraint 下，setup WNS 为 +55.532 ns、TNS 为 0，worst hold slack 为 +0.010 ns。9.460 ns 是该约束运行中的 worst routed data-path delay；未执行 formal Fmax sweep，因此不能用它的倒数声称 Fmax。

新 original/divopt Vivado comparison 在源工作区仍未提交且运行中，本仓库标记为 `IN PROGRESS / EXCLUDED`。FPGA LUT/FF/BRAM/DSP 与 ASIC standard-cell area/SRAM/STA 不可直接换算。
