[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Part,
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$VivadoExecutable,
    [double]$ClockPeriodNs = 65.104
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if (-not $VivadoExecutable) { $VivadoExecutable = [Environment]::GetEnvironmentVariable('RLS_VIVADO') }
if (-not $VivadoExecutable) {
    $resolved = Get-Command vivado.bat -ErrorAction SilentlyContinue
    if (-not $resolved) { $resolved = Get-Command vivado -ErrorAction SilentlyContinue }
    if ($resolved) { $VivadoExecutable = $resolved.Source }
}
if (-not $VivadoExecutable -or -not (Test-Path -LiteralPath $VivadoExecutable -PathType Leaf)) {
    throw 'Pass -VivadoExecutable, set RLS_VIVADO, or add Vivado to PATH.'
}
$build = Join-Path $RepositoryRoot 'build\vivado_portable_experiment'
New-Item -ItemType Directory -Path $build -Force | Out-Null
$env:RLS_ROOT = $RepositoryRoot.Replace('\','/')
$env:RLS_VIVADO_BUILD = $build.Replace('\','/')
$env:RLS_VIVADO_PART = $Part
$env:RLS_VIVADO_CLOCK_NS = $ClockPeriodNs.ToString([Globalization.CultureInfo]::InvariantCulture)
& $VivadoExecutable -mode batch -notrace -source (Join-Path $RepositoryRoot 'scripts\vivado\run_portable_experiment.tcl') *> (Join-Path $build 'vivado.log')
if ($LASTEXITCODE -ne 0) { throw "Vivado experiment failed with exit code $LASTEXITCODE" }
Write-Output 'VIVADO_PORTABLE_EXPERIMENT_COMPLETE_NOT_ACCEPTED_BASELINE'
