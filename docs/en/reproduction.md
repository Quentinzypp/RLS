# Reproduction

Use Windows PowerShell, Python 3.10+, and a legally installed ModelSim/Questa `vsim`. Tool paths come from explicit parameters, `RLS_MODELSIM` / `RLS_PYTHON`, or PATH.

```powershell
.\scripts\simulation\Launch-ConvergenceSimulation.ps1
.\scripts\simulation\Invoke-DividerCheck.ps1
python .\scripts\documentation\gen_readme_assets.py
python .\scripts\documentation\check_showcase_docs.py
```

Large generated outputs stay under ignored `build/`. Commercial tools, licenses, PDKs, and memory libraries are user-supplied. The old generated-XCI FPGA baseline is preserved evidence only because redistributable Xilinx payload is intentionally absent.
