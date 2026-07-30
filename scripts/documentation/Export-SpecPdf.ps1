[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$PythonExecutable,
    [switch]$SkipDocxBuild
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if (-not $PythonExecutable) { $PythonExecutable = [Environment]::GetEnvironmentVariable('RLS_PYTHON') }
if (-not $PythonExecutable) {
    $candidate = Get-Command python.exe -ErrorAction SilentlyContinue
    if (-not $candidate) { $candidate = Get-Command python -ErrorAction SilentlyContinue }
    if ($candidate) { $PythonExecutable = $candidate.Source }
}
if (-not $PythonExecutable -or -not (Test-Path -LiteralPath $PythonExecutable -PathType Leaf)) {
    throw 'Pass -PythonExecutable, set RLS_PYTHON, or add Python to PATH.'
}

if (-not $SkipDocxBuild) {
    & $PythonExecutable (Join-Path $PSScriptRoot 'build_spec_documents.py')
    if ($LASTEXITCODE -ne 0) { throw 'DOCX generation failed.' }
}

$docx = Join-Path $RepositoryRoot 'docs\rls_asic_spec.docx'
$pdf = Join-Path $RepositoryRoot 'docs\rls_asic_spec.pdf'
$build = Join-Path $RepositoryRoot 'build\documentation'
New-Item -ItemType Directory -Path $build -Force | Out-Null
$rawPdf = Join-Path $build 'rls_asic_spec_word_export.pdf'
$word = $null
$document = $null
try {
    $word = New-Object -ComObject Word.Application
    $word.Visible = $false
    $word.DisplayAlerts = 0
    $document = $word.Documents.Open($docx, $false, $true)
    $document.Fields.Update() | Out-Null
    $document.ExportAsFixedFormat($rawPdf, 17)
}
finally {
    if ($document) {
        try { $document.Close($false) } catch { Write-Warning "Word document close returned: $($_.Exception.Message)" }
    }
    if ($word) {
        try { $word.Quit() } catch { Write-Warning "Word application quit returned: $($_.Exception.Message)" }
    }
    if ($document) { try { [Runtime.InteropServices.Marshal]::ReleaseComObject($document) | Out-Null } catch {} }
    if ($word) { try { [Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null } catch {} }
}

& $PythonExecutable (Join-Path $PSScriptRoot 'finalize_spec_pdf.py') `
    --markdown (Join-Path $RepositoryRoot 'docs\rls_asic_spec.md') `
    --docx $docx --input-pdf $rawPdf --output-pdf $pdf `
    --fingerprint-csv (Join-Path $RepositoryRoot 'reports\showcase\document_fingerprints.csv')
if ($LASTEXITCODE -ne 0) { throw 'PDF finalization failed.' }
Write-Output 'SPEC_DOCUMENTS_SYNCHRONIZED'
