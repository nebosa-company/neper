$ErrorActionPreference = 'Stop'
# The refresh mode of refresh-goldens.ps1: a snapshot-only difference is rewritten, any other is not, and without
# NEPER_REFRESH_GOLDENS a difference is just a difference.
$work = Join-Path ([IO.Path]::GetTempPath()) ("refresh-goldens-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force -Path (Join-Path $work 'tests/conformance/tools') | Out-Null
try {
    $golden = Join-Path $work 'tests/conformance/tools/t.x64-windows.expected.jsonl'
    $stale = '{"record":"subject","snapshot":"aaaa","checks":"retained"}'
    [IO.File]::WriteAllText($golden, $stale)
    [IO.File]::WriteAllText("$work/snapshot_only", '{"record":"subject","snapshot":"bbbb","checks":"retained"}')
    [IO.File]::WriteAllText("$work/other", '{"record":"subject","snapshot":"bbbb","checks":"dropped"}')
    function Same($a, $b) { (Get-FileHash -Algorithm SHA256 -LiteralPath $a).Hash -eq (Get-FileHash -Algorithm SHA256 -LiteralPath $b).Hash }

    . "$PSScriptRoot/refresh-goldens.ps1"
    if (Same "$work/snapshot_only" $golden) { throw 'a difference passed without NEPER_REFRESH_GOLDENS' }
    if ([IO.File]::ReadAllText($golden) -ne $stale) { throw 'the golden changed without NEPER_REFRESH_GOLDENS' }

    $env:NEPER_REFRESH_GOLDENS = '1'
    . "$PSScriptRoot/refresh-goldens.ps1"
    if (Same "$work/other" $golden) { throw 'a non-snapshot difference was refreshed' }
    if ([IO.File]::ReadAllText($golden) -ne $stale) { throw 'the golden changed on a non-snapshot difference' }
    if (Same "$work/snapshot_only" "$work/other") { throw 'a golden outside tests/conformance/tools was refreshed' }
    if (-not (Same "$work/snapshot_only" $golden)) { throw 'a snapshot-only difference was not refreshed' }
    if ([IO.File]::ReadAllText($golden) -ne [IO.File]::ReadAllText("$work/snapshot_only")) { throw 'the refreshed golden does not match' }
    Write-Output 'refresh goldens ok'
} finally {
    Remove-Item Env:NEPER_REFRESH_GOLDENS -ErrorAction SilentlyContinue
    Remove-Item Function:Get-FileHash -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
