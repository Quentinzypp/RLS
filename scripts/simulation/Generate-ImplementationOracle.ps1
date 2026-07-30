[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$PythonExecutable,
    [ValidateRange(1, 1000)][int]$Updates = 1000
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if (-not $PythonExecutable) { $PythonExecutable = [Environment]::GetEnvironmentVariable('RLS_PYTHON') }
if (-not $PythonExecutable) {
    $resolved = Get-Command python.exe -ErrorAction SilentlyContinue
    if (-not $resolved) { $resolved = Get-Command python -ErrorAction SilentlyContinue }
    if ($resolved) { $PythonExecutable = $resolved.Source }
}
if (-not $PythonExecutable -or -not (Test-Path -LiteralPath $PythonExecutable -PathType Leaf)) {
    throw 'Pass -PythonExecutable, set RLS_PYTHON, or add Python to PATH.'
}
$artifactDir = Join-Path $RepositoryRoot 'build\oracle\fixed\artifacts'
$reportDir = Join-Path $RepositoryRoot 'build\oracle\fixed\reports'
New-Item -ItemType Directory -Path $artifactDir,$reportDir -Force | Out-Null
& $PythonExecutable (Join-Path $RepositoryRoot 'verification\oracle\test_rls_fixed_reference.py') `
    --output (Join-Path $RepositoryRoot 'build\oracle\fixed_self_tests.csv')
if ($LASTEXITCODE -ne 0) { throw 'Implementation-oracle self-tests failed.' }
& $PythonExecutable (Join-Path $RepositoryRoot 'verification\oracle\rls_fixed_reference.py') `
    --repo-root $RepositoryRoot --updates $Updates --artifact-dir $artifactDir --report-dir $reportDir
if ($LASTEXITCODE -ne 0) { throw 'Implementation-oracle generation failed.' }
Write-Output "IMPLEMENTATION_ORACLE_GENERATED updates=$Updates output=build/oracle/fixed"
