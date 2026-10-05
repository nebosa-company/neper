# The aarch64 back end's differential check (D2123), Windows half: build each link fixture
# (or the programs named) for x64-linux and aarch64-linux with the given compiler into
# build/a64/out, named by fixture. scripts/a64-differential.sh runs the pairs in WSL and
# compares them. A fixture that fails to build for both targets is a rejection test and
# is listed, not counted; one that fails for aarch64 alone is printed as a failure.
#
#   pwsh scripts/a64-differential.ps1 -Compiler build\windows\neper-self.exe [-Programs a.e,b.e]
param([Parameter(Mandatory = $true)][string]$Compiler, [string[]]$Programs)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$out = Join-Path $repo 'build\a64\out'
New-Item -ItemType Directory -Force $out | Out-Null
if (-not $Programs) {
    $Programs = Get-ChildItem (Join-Path $repo 'tests\selfhost\fixtures\link') -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName 'src\main.e') } |
        ForEach-Object { "tests\selfhost\fixtures\link\$($_.Name)\src\main.e" }
}
$names = [Collections.Generic.List[string]]::new()
foreach ($program in $Programs) {
    $name = (($program -replace '^tests[\\/]selfhost[\\/]fixtures[\\/]', '') -replace '[\\/]src[\\/]main\.e$', '' -replace '\.e$', '') -replace '[\\/]', '_'
    $failed = @{}
    foreach ($arch in 'x64', 'aarch64') {
        $image = Join-Path $out "$name.$arch"
        Remove-Item $image -ErrorAction SilentlyContinue
        $message = & $Compiler build (Join-Path $repo $program) --target "$arch-linux" -o $image 2>&1
        if ($LASTEXITCODE -ne 0) {
            $failed[$arch] = (($message | Select-Object -Last 2) -join ' | ')
            Remove-Item $image -ErrorAction SilentlyContinue
        }
    }
    if ($failed.Count -eq 2) { Write-Output "REJECTED $name" }
    elseif ($failed.ContainsKey('aarch64')) { Write-Output "BUILD-FAIL $name aarch64: $($failed['aarch64'])" }
    elseif ($failed.ContainsKey('x64')) { Write-Output "BUILD-FAIL $name x64: $($failed['x64'])" }
    else { $names.Add($name) }
}
[IO.File]::WriteAllText((Join-Path $out 'names.txt'), ($names -join "`n") + "`n")
Write-Output "built $($names.Count) pairs"
