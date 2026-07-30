[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$TargetLibrary,
    [Parameter(Mandatory = $true)][string[]]$LinkLibraries,
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$DcShellExecutable,
    [string]$Top = 'RLS12_c_MW_top_divopt',
    [double]$ClockPeriodNs = 10.0
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if (-not (Test-Path -LiteralPath $TargetLibrary -PathType Leaf)) { throw 'Target library was not found.' }
foreach ($library in $LinkLibraries) {
    if (-not (Test-Path -LiteralPath $library -PathType Leaf)) { throw "Link library was not found: $library" }
}
if (-not $DcShellExecutable) { $DcShellExecutable = [Environment]::GetEnvironmentVariable('RLS_DC_SHELL') }
if (-not $DcShellExecutable) {
    $resolved = Get-Command dc_shell.exe -ErrorAction SilentlyContinue
    if (-not $resolved) { $resolved = Get-Command dc_shell -ErrorAction SilentlyContinue }
    if ($resolved) { $DcShellExecutable = $resolved.Source }
}
if (-not $DcShellExecutable -or -not (Test-Path -LiteralPath $DcShellExecutable -PathType Leaf)) {
    throw 'Pass -DcShellExecutable, set RLS_DC_SHELL, or add dc_shell to PATH.'
}

$buildRoot = Join-Path $RepositoryRoot 'build\dc_frontend'
New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
$env:RLS_ROOT = $RepositoryRoot.Replace('\','/')
$env:RLS_DC_BUILD = $buildRoot.Replace('\','/')
$env:RLS_DC_TARGET_LIBRARY = (Resolve-Path -LiteralPath $TargetLibrary).Path.Replace('\','/')
$env:RLS_DC_LINK_LIBRARIES = (($LinkLibraries | ForEach-Object { (Resolve-Path -LiteralPath $_).Path.Replace('\','/') }) -join ';')
$env:RLS_DC_TOP = $Top
$env:RLS_DC_CLOCK_PERIOD_NS = $ClockPeriodNs.ToString([Globalization.CultureInfo]::InvariantCulture)
Push-Location $buildRoot
try {
    & $DcShellExecutable -f (Join-Path $RepositoryRoot 'scripts\frontend\run_dc_frontend.tcl') *> (Join-Path $buildRoot 'dc_frontend.log')
    if ($LASTEXITCODE -ne 0) { throw "DC frontend failed with exit code $LASTEXITCODE" }
}
finally { Pop-Location }
Write-Output 'DC_FRONTEND_DIAGNOSTIC_COMPLETE output=build/dc_frontend'
