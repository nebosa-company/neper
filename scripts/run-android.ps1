# Build link fixtures for `x64 android` or, with -Arch aarch64, `aarch64 android` (C219, D5896, D5900), push them to the
# device or emulator adb sees, and run each under `adb shell` from /data/local/tmp; an x86_64 emulator runs arm64 images
# through its translator. A fixture whose name starts with gpu_gl is built with `--gpu glsl`. Exit 1 when any fixture
# exits non-zero.
#   scripts/run-android.ps1 hello advanced gpu_cpu x_khronos_gl_headless gpu_gl
#   scripts/run-android.ps1 -Arch aarch64 hello atomic_ops
# `hello` is examples/hello.e. ADB is $env:ADB, else adb.exe under $env:ANDROID_SDK_ROOT, else on PATH.
param([string]$Arch = 'x64', [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)][string[]]$Fixtures)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$compiler = Join-Path $repo 'build\windows\neper-try.exe'
$adb = $env:ADB
if (-not $adb -and $env:ANDROID_SDK_ROOT) { $adb = Join-Path $env:ANDROID_SDK_ROOT 'platform-tools\adb.exe' }
if (-not $adb) { $adb = 'adb' }
$out = Join-Path $repo "build\android\$Arch"
New-Item -ItemType Directory -Force $out | Out-Null
$failed = 0
foreach ($fixture in $Fixtures) {
    $source = Join-Path $repo "tests\selfhost\fixtures\link\$fixture\src\main.e"
    if ($fixture -eq 'hello') { $source = Join-Path $repo 'examples\hello.e' }
    $binary = Join-Path $out $fixture
    $flags = @()
    if ($fixture.StartsWith('gpu_gl')) { $flags = @('--gpu', 'glsl') }
    $written = & $compiler emit-executable $source $repo $Arch 'android' $binary @flags
    if ($written -ne 'executable written') { Write-Output "$fixture did not build: $written"; $failed++; continue }
    & $adb push $binary "/data/local/tmp/$fixture" | Out-Null
    $output = & $adb shell "cd /data/local/tmp && chmod 755 $fixture && ./$fixture; echo exit=`$?"
    $output | Where-Object { $_ -notmatch '^exit=' } | ForEach-Object { Write-Output "  $_" }
    $code = ($output | Where-Object { $_ -match '^exit=' } | Select-Object -Last 1) -replace 'exit=', ''
    Write-Output "$fixture on $Arch android: exit $code"
    if ($code -ne '0') { $failed++ }
}
if ($failed -ne 0) { exit 1 }
