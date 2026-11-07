$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'build-bootstrap.ps1') | Out-Null
$bootstrap = Join-Path $repo 'build\windows\neper.exe'
$output = Join-Path $repo 'build\windows\neper-self.exe'
# No `--arena`: the size is a lazily-committed ceiling, so the compiler grows into what it
# needs instead of failing against an arbitrary cap. See the note in tests/selfhost/run.ps1.
& $bootstrap build (Join-Path $repo 'src\main.e') --output $output | Out-Null
if ($LASTEXITCODE -ne 0) { throw "self-hosted compiler build failed with exit code $LASTEXITCODE" }

Write-Output $output
