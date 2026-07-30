# RLS GitHub publication status

- Release state: `RLS_GITHUB_SHOWCASE_COMPLETE_WITH_VIVADO_COMPARISON_PENDING`
- Repository: `Quentinzypp/RLS`
- Visibility / default branch: `PUBLIC` / `main`
- Authentication: GitHub account `Quentinzypp`; Git transport `SSH`
- Bootstrap commit: `a20e1220e36bcf6349a1c16c3155aa60661827ae`
- Showcase PR: `#1`, squash merge `38ec4c2903fdc299f182d817e418b35d583c51fd`, merged at `2026-07-30T08:08:11Z`
- Status PR: pending GitHub allocation
- Main SHA before the status PR: `38ec4c2903fdc299f182d817e418b35d583c51fd`
- Tracked files before / after this status record: 145 / 146

## Published package

- Chinese and English repository entry points: `README.md` and `README.en.md`
- Six deterministic SVG assets: overview, algorithm flow, verification flow, convergence, divider optimization, and FPGA/ASIC comparison
- Sixteen bilingual topic documents under `docs/zh-CN/` and `docs/en/`
- Synchronized `docs/rls_asic_spec.md`, `.docx`, and `.pdf`; the DOCX and PDF embed the canonical Markdown SHA-256
- Portable/divopt RTL, deterministic filelists, public vectors, implementation oracle, checkers, constraints, and sanitized evidence
- Machine-readable results in `reports/showcase/public_results.csv`; unavailable values use `NOT_AVAILABLE`

## Acceptance

- Documentation checks: 23/23 PASS
- ModelSim SE-64 10.6d fresh run: 1,000 updates, 12,000 weights, `175:998;208:1`, zero valid X/Z, and 12,000/12,000 generated-oracle weight matches
- Convergence: 43.166 dB / 43.249 dB observed power reduction; stable markers at updates 684 / 689
- Divider: 1,160/1,160 PASS, 40 accepted-edge latency, zero mismatch
- Public-scope, secret, and 10 MiB file-size audits: PASS for the current tree and all reachable Git blobs
- Document visual QA: Word COM export plus Poppler, all 4 Letter pages inspected; no clipping, overlap, broken tables, or missing glyphs
- SVG visual QA: all 6 browser renders inspected

## Reproduction

```powershell
.\scripts\simulation\Launch-ConvergenceSimulation.ps1
.\scripts\simulation\Invoke-DividerCheck.ps1
python .\scripts\documentation\gen_readme_assets.py
python .\scripts\documentation\check_showcase_docs.py
```

Commercial tools, licenses, PDKs, and macro libraries are user-supplied and are not repository payloads. Fresh runs write ignored artifacts under `build/`; preserved evidence remains under `reports/`.

## Boundaries and source integrity

- The uncommitted Vivado original/divopt comparison remains `IN PROGRESS / EXCLUDED`; only the prior accepted FPGA baseline is public.
- ASIC data is pre-layout standard-cell logic diagnosis, not signoff or complete PPA. SRAM area/power and full-IP power remain `NOT_AVAILABLE` or `NOT_EVALUABLE`.
- The protected source branch and HEAD remained `codex/modelsim-convergence-gui` and `44f433808e4c7884c3ba488c5b20d764500bd5fa` throughout publication.
- Source-side modified specification artifacts, comparison directories, and active Vivado-generated logs remain local and uncommitted; the publication flow did not reset, clean, stage, or commit them.

## Self-reference boundary

The status PR merge commit, its merge time, and the final `main` SHA are intentionally not embedded here because they do not exist until this file is merged. They are reported from the GitHub API in the final publication handoff.
