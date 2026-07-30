# FPGA prototype results

The accepted Vivado 2024.2 routed baseline uses `RLS12_c_MW_top` on `xczu48dr-ffvg1517-2-e`: 21,535 LUT, 42,855 registers, 103 BRAM Tile, and 352 DSP48E2.

At the 65.104 ns clock constraint it reports +55.532 ns setup WNS, zero TNS, and +0.010 ns worst hold slack. No formal Fmax sweep was performed; the reciprocal of the 9.460 ns routed data path is not a validated Fmax.

The new original/divopt comparison is uncommitted and still in progress in the protected source workspace, so it is `IN PROGRESS / EXCLUDED`. FPGA and ASIC resource quantities are not directly convertible.
