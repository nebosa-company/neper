$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$build = Join-Path $repo 'build'
$source = Join-Path $repo 'bootstrap\neper.c'
$vsDevCmd = $env:NEPER_VSDEVCMD

if (-not $vsDevCmd) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere) {
        $installation = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($installation) {
            $vsDevCmd = Join-Path $installation 'Common7\Tools\VsDevCmd.bat'
        }
    }
}

if (-not $vsDevCmd -and (Test-Path -LiteralPath 'D:\VS\Community\Common7\Tools\VsDevCmd.bat')) {
    $vsDevCmd = 'D:\VS\Community\Common7\Tools\VsDevCmd.bat'
}

if (-not $vsDevCmd -or -not (Test-Path -LiteralPath $vsDevCmd)) {
    throw "Visual Studio C++ tools were not found. Set NEPER_VSDEVCMD to VsDevCmd.bat."
}

New-Item -ItemType Directory -Force -Path $build | Out-Null
$command = 'call "{0}" -arch=x64 -host_arch=x64 >nul && cl /nologo /std:c11 /W4 /O2 /Fo:"{1}" /Fe:"{2}" "{3}"' -f $vsDevCmd, (Join-Path $build 'neper.obj'), (Join-Path $build 'neper.exe'), $source
cmd.exe /d /s /c $command
if ($LASTEXITCODE -ne 0) { throw "bootstrap compilation failed with exit code $LASTEXITCODE" }

$libraryTarget = Join-Path $build 'lib\e'
New-Item -ItemType Directory -Force -Path $libraryTarget | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'lib\e\mem.e') -Destination $libraryTarget -Force
Copy-Item -LiteralPath (Join-Path $repo 'lib\e\io.e') -Destination $libraryTarget -Force

Write-Output (Join-Path $build 'neper.exe')
