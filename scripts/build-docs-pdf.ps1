#!/usr/bin/env pwsh
# Build docs/neper.pdf from the neper documentation set.
#
#   scripts\build-docs-pdf.ps1                 -> docs\neper.pdf
#   scripts\build-docs-pdf.ps1 --out other.pdf
#
# Creates .venv-docs-pdf/ beside the repository root and installs the pinned
# dependencies in scripts/docs-pdf-requirements.txt. Reinstallation happens only
# when that file changes.

$ErrorActionPreference = "Stop"

$scriptDir = $PSScriptRoot
$root = Split-Path -Parent $scriptDir
$venv = Join-Path $root ".venv-docs-pdf"
$venvPython = Join-Path $venv "Scripts\python.exe"
$requirements = Join-Path $scriptDir "docs-pdf-requirements.txt"
$stamp = Join-Path $venv "requirements.sha256"

if (-not (Test-Path $venvPython)) {
    Write-Host "creating $venv"
    $bootstrap = (Get-Command python -ErrorAction SilentlyContinue)
    if ($null -eq $bootstrap) { $bootstrap = (Get-Command py -ErrorAction Stop) }
    & $bootstrap.Source -m venv $venv
    if ($LASTEXITCODE -ne 0) { throw "failed to create virtual environment" }
}

# Lower case so the stamp matches the one scripts/build-docs-pdf.sh writes.
$wanted = (Get-FileHash $requirements -Algorithm SHA256).Hash.ToLowerInvariant()
$have = if (Test-Path $stamp) { (Get-Content $stamp -Raw).Trim() } else { "" }
if ($wanted -ne $have) {
    Write-Host "installing pinned dependencies"
    & $venvPython -m pip install --disable-pip-version-check --quiet --upgrade pip
    if ($LASTEXITCODE -ne 0) { throw "pip upgrade failed" }
    & $venvPython -m pip install --disable-pip-version-check --quiet -r $requirements
    if ($LASTEXITCODE -ne 0) { throw "dependency installation failed" }
    Set-Content -Path $stamp -Value $wanted -NoNewline
}

& $venvPython (Join-Path $scriptDir "build-docs-pdf.py") @args
exit $LASTEXITCODE
