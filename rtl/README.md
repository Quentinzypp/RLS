# RTL publication boundary

- `portable/` replaces generated FPGA memories and arithmetic IP with synthesizable
  RTL. It is the portable baseline.
- `optimized/` contains the selected aligned Radix-4 divider and the divopt top.
  `RLS12_c_MW_top_divopt` is the recommended integration top.
- `compat/` contains only the original handwritten hierarchy for design-reference
  review. It is not independently buildable because all generated Xilinx IP is
  intentionally excluded.
- `filelists/` are deterministic and use repository-relative paths.

The portable memory modules are behavioral/synthesizable wrappers. ASIC macro
binding, timing views, physical views, and MBIST are integration responsibilities.
