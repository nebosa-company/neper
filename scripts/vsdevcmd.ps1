$ErrorActionPreference = 'Stop'

# The Visual Studio developer prompt every Windows C or assembler build runs under:
# NEPER_VSDEVCMD, else the latest installation with the x64 tools, else this machine's.
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

Write-Output $vsDevCmd
