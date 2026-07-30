# 快速复现

## 前置条件

- Windows PowerShell 5.1 或 PowerShell 7
- Python 3.10+；文档脚本只使用标准库，DOCX 生成需要 `python-docx` 和 `pypdf`
- ModelSim/Questa 的 `vsim`，由本地合法许可证提供
- DC/Vivado 仅在需要对应 frontend experiment 时提供

## ModelSim

```powershell
.\scripts\simulation\Launch-ConvergenceSimulation.ps1
.\scripts\simulation\Invoke-DividerCheck.ps1
```

如果工具不在 PATH，使用 `-ModelSimExecutable` / `-PythonExecutable` 或环境变量 `RLS_MODELSIM` / `RLS_PYTHON`。所有大结果写到 ignored `build/`。

## 文档

```powershell
python .\scripts\documentation\gen_readme_assets.py
python .\scripts\documentation\build_spec_documents.py
python .\scripts\documentation\check_showcase_docs.py
```

Fresh run 只验证公开 portable/divopt 路径；旧 generated-XCI FPGA baseline 只能作为 preserved evidence 阅读，仓库不包含重新构建它所需的 Xilinx payload。
