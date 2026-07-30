[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$ModelSimExecutable,
    [string]$PythonExecutable
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path

function Resolve-Executable([string]$Explicit, [string]$EnvironmentName, [string[]]$Commands) {
    if ($Explicit) {
        if (-not (Test-Path -LiteralPath $Explicit -PathType Leaf)) { throw "Tool not found: $Explicit" }
        return (Resolve-Path -LiteralPath $Explicit).Path
    }
    $environmentValue = [Environment]::GetEnvironmentVariable($EnvironmentName)
    if ($environmentValue) {
        if (-not (Test-Path -LiteralPath $environmentValue -PathType Leaf)) {
            throw "$EnvironmentName does not name a file: $environmentValue"
        }
        return (Resolve-Path -LiteralPath $environmentValue).Path
    }
    foreach ($name in $Commands) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }
    throw "Set $EnvironmentName or pass an explicit executable."
}

$vsim = Resolve-Executable $ModelSimExecutable 'RLS_MODELSIM' @('vsim.exe','vsim')
$python = Resolve-Executable $PythonExecutable 'RLS_PYTHON' @('python.exe','python','py.exe','py')
& (Join-Path $RepositoryRoot 'scripts\simulation\Generate-ImplementationOracle.ps1') `
    -RepositoryRoot $RepositoryRoot -PythonExecutable $python -Updates 1000
if ($LASTEXITCODE -ne 0) { throw 'Implementation-oracle generation failed.' }
$buildRoot = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'build\modelsim_convergence'))
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'build')).TrimEnd('\') + '\'
if (-not $buildRoot.StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Resolved build path is outside the repository build directory.'
}
if (Test-Path -LiteralPath $buildRoot) { Remove-Item -LiteralPath $buildRoot -Recurse -Force }
New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null

$reference = (Resolve-Path -LiteralPath (Join-Path $RepositoryRoot 'verification\vectors\convergence\uns_matlab.txt')).Path
$desired = (Resolve-Path -LiteralPath (Join-Path $RepositoryRoot 'verification\vectors\convergence\dns_matlab.txt')).Path
$env:RLS_ROOT = $RepositoryRoot.Replace('\','/')
$env:RLS_BUILD = $buildRoot.Replace('\','/')
$env:RLS_REFERENCE_VECTOR = $reference.Replace('\','/')
$env:RLS_DESIRED_VECTOR = $desired.Replace('\','/')
$doFile = (Resolve-Path -LiteralPath (Join-Path $RepositoryRoot 'scripts\simulation\run_convergence.do')).Path.Replace('\','/')

Push-Location $buildRoot
try {
    & $vsim -c -do "do $doFile" *> (Join-Path $buildRoot 'launcher.log')
    if ($LASTEXITCODE -ne 0) { throw "ModelSim convergence run failed with exit code $LASTEXITCODE" }
}
finally { Pop-Location }

& $python (Join-Path $RepositoryRoot 'verification\checkers\analyze_convergence.py') `
    --capture-dir $buildRoot --output-dir $buildRoot --expected-updates 1000
if ($LASTEXITCODE -ne 0) { throw 'Convergence analysis failed.' }
& $python (Join-Path $RepositoryRoot 'verification\checkers\compare_preserved_metrics.py') `
    --fresh (Join-Path $buildRoot 'convergence_metrics.csv') `
    --preserved (Join-Path $RepositoryRoot 'reports\modelsim\convergence_metrics.csv') `
    --summary (Join-Path $buildRoot 'fresh_acceptance.md')
if ($LASTEXITCODE -ne 0) { throw 'Fresh/preserved convergence comparison failed.' }
& $python (Join-Path $RepositoryRoot 'verification\checkers\compare_oracle_weights.py') `
    --oracle (Join-Path $RepositoryRoot 'build\oracle\fixed\artifacts\rls_fixed_weights.csv') `
    --rtl (Join-Path $buildRoot 'weights_samples_raw.csv') `
    --output (Join-Path $buildRoot 'oracle_weight_comparison.json')
if ($LASTEXITCODE -ne 0) { throw 'Generated-oracle/RTL weight comparison failed.' }

Write-Output 'MODELSIM_CONVERGENCE_FRESH_PASS updates=1000 oracle_weights=12000/12000 output=build/modelsim_convergence'
