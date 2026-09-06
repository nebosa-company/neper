$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'build-bootstrap.ps1') | Out-Null
$bootstrap = Join-Path $repo 'build\neper.exe'
$output = Join-Path $repo 'build\neper-self.exe'
& $bootstrap build (Join-Path $repo 'src\main.e') --arena 1g --output $output | Out-Null
if ($LASTEXITCODE -ne 0) { throw "self-hosted compiler build failed with exit code $LASTEXITCODE" }

Write-Output $output
