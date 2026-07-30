[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$ModelSimExecutable
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if (-not $ModelSimExecutable) { $ModelSimExecutable = [Environment]::GetEnvironmentVariable('RLS_MODELSIM') }
if (-not $ModelSimExecutable) {
    $resolved = Get-Command vsim.exe -ErrorAction SilentlyContinue
    if (-not $resolved) { $resolved = Get-Command vsim -ErrorAction SilentlyContinue }
    if ($resolved) { $ModelSimExecutable = $resolved.Source }
}
if (-not $ModelSimExecutable -or -not (Test-Path -LiteralPath $ModelSimExecutable -PathType Leaf)) {
    throw 'Pass -ModelSimExecutable, set RLS_MODELSIM, or add vsim to PATH.'
}

$buildRoot = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'build\divider'))
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'build')).TrimEnd('\') + '\'
if (-not $buildRoot.StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe build path.' }
if (Test-Path -LiteralPath $buildRoot) { Remove-Item -LiteralPath $buildRoot -Recurse -Force }
New-Item -ItemType Directory -Path $buildRoot | Out-Null
foreach ($name in @('dividend.mem','divisor.mem','expected.mem','divide_by_zero.mem')) {
    Copy-Item -LiteralPath (Join-Path $RepositoryRoot "verification\vectors\divider\$name") -Destination $buildRoot
}
$env:RLS_ROOT = $RepositoryRoot.Replace('\','/')
$env:RLS_BUILD = $buildRoot.Replace('\','/')
$doFile = (Resolve-Path -LiteralPath (Join-Path $RepositoryRoot 'scripts\simulation\run_divider.do')).Path.Replace('\','/')
Push-Location $buildRoot
try {
    & $ModelSimExecutable -c -do "do $doFile" *> (Join-Path $buildRoot 'launcher.log')
    if ($LASTEXITCODE -ne 0) { throw "Divider run failed with exit code $LASTEXITCODE" }
}
finally { Pop-Location }
$text = Get-Content -LiteralPath (Join-Path $buildRoot 'divider_transcript.log') -Raw
foreach ($marker in @(
    'PHASE4_DIVIDER_CANDIDATE_VECTORS=1160',
    'PHASE4_DIVIDER_ALIGNED_OUTPUTS=1160',
    'PHASE4_DIVIDER_MISMATCHES=0',
    'PHASE4_DIVIDER_UNKNOWNS=0',
    'PHASE4_DIVIDER_LATENCY_ERRORS=0',
    'PHASE4_DIVIDER_PROTOCOL_ERRORS=0',
    'PHASE4_DIVIDER_EXACT_CANDIDATES_PASS')) {
    if (-not $text.Contains($marker)) { throw "Divider acceptance marker missing: $marker" }
}
Write-Output 'DIVIDER_FRESH_PASS checker=1160/1160 aligned_latency_edges=40 mismatches=0'
