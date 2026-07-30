# Public evidence index

Trusted source snapshot: commit `44f433808e4c7884c3ba488c5b20d764500bd5fa`.

| Claim | Public evidence | Trusted snapshot evidence | SHA-256 | Type | Boundary |
| --- | --- | --- | --- | --- | --- |
| 1,000-update convergence | `reports/modelsim/convergence_metrics.csv` | `reports/modelsim_convergence/convergence_metrics.csv` | `2341992b1e30949ef17cd566344b0c80cc56159ec8673f56b9f406edcfe01853` | preserved + fresh runner | implementation residual only |
| 174,918 residual / 12,000 weight zero mismatch | `reports/modelsim/preserved_summary.md` | `reports/modelsim_convergence/convergence_analysis.md` | `90d9df1df009a28fad1a774accfcc1ff13695c420f535b1bc4545efc1f53dab7` | preserved | implementation equivalence |
| Divider 1,160/1,160 | `reports/asic/divider_optimization.csv` | `reports/divider_optimization/divider_checker_summary.md` | `514358fdb7785b3ebbf4a5f13ea83134ab308cad1face65f772d97758dafdb3b` | preserved + fresh runner | RTL simulation |
| Divider area/timing | `reports/asic/divider_optimization.csv` | `reports/divider_optimization/block_synthesis/divider_candidate_comparison.csv` | `523c62a8cfb3c1bcd4accf62fbc221ce4c344e1533829c4912c18ebc5bf33e7e` | preserved | isolated standard-cell logic |
| Phase 4 boundary | `reports/asic/dc_logic_summary.md` | `reports/phase4_optimization_summary.md` | `20002b4d472a6412a6c88cf2757d198ce455d8ccda353a95de367459656fb92e` | preserved | partial with blockers |
| Top logic points | `reports/asic/top_logic_points.csv` | `reports/phase4_ppa_pareto.csv` | `7b88e3b8a1a61bc7d34c323e52ce4bceee466b860535b49e11fdc13894044716` | preserved | SRAM excluded |
| 18 SRAM / 3,257,856 bits | `reports/asic/sram_inventory.csv` | `reports/memory/sram_inventory_and_binding.md` | `992ee0d05039a1120c1279aa4c9a638b930d99dafaf249d7faf3fbb541bccf76` | preserved | no authorized macro views |
| Power blocked | `reports/asic/power_blocker.md` | `reports/power/power_analysis_status.md` | `4677708fe439e3b93e5a117a09eb1637c312e9014beba5107b1b40aeca96de1a` | preserved | not evaluable |
| Accepted FPGA baseline | `reports/fpga/baseline_summary.md` | `reports/fpga_rls_baseline_summary.md` | `c1ff8dd2b29f7da926496ca79924a8c06bc63e67cc68721ed93dc780f1fa4cb1` | preserved | old baseline only |
| Recommended top provenance | `rtl/optimized/top/RLS12_c_MW_top_divopt.v` | `rtl_asic_optimized/top/RLS12_c_MW_top_divopt.v` | `aa097b2b3d617ef20f48b9512d038d948c261c3b9cd490915955d767e02fdbeb` | byte-preserved | portable RTL |

Large raw convergence samples, WLF, commercial work databases, XCI payloads,
PDK/library files, and uncommitted Vivado comparison data are deliberately absent.
