# The e.db benchmark on Windows against C, Go and Rust: builds the C, Go and Rust programs, starts
# throwaway servers on free ports, registers a per-user DSN for psqlODBC, runs run.py over all
# four, then removes the DSN and stops the servers.
#
#   pwsh benchmarks/db/run-windows-all.ps1 <neper-prefix> <results.json> [runs]
#
# <neper-prefix>-{sqlite,postgresql,mysql,odbc}.exe are the Neper benchmarks, built beforehand.
# The client libraries and psqlODBC are unpacked under $env:NEPER_DB_TOOLS (default D:\tools);
# the Windows driver manager reaches an ODBC driver only through a DSN, so the run names the
# unpacked driver's DLL in HKCU\Software\ODBC\ODBC.INI\neper_psqlodbc for its duration.
param(
    [Parameter(Mandatory = $true)][string]$NeperPrefix,
    [Parameter(Mandatory = $true)][string]$Out,
    [int]$Runs = 9
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repo = Split-Path -Parent (Split-Path -Parent $here)
. (Join-Path $here 'tools-env.ps1')
$tools = if ($env:NEPER_DB_TOOLS) { $env:NEPER_DB_TOOLS } else { 'D:\tools' }
$work = Join-Path $repo 'build\db-bench-all'
New-Item -ItemType Directory -Force $work | Out-Null
foreach ($driver in 'sqlite', 'postgresql', 'mysql', 'odbc') { Copy-Item -Force "$NeperPrefix-$driver.exe" (Join-Path $work "bench-$driver.exe") }
cmd /c "`"$(Join-Path $here 'c\build.cmd')`" `"$(Join-Path $work 'bench-c.exe')`""
if ($LASTEXITCODE -ne 0) { throw 'the C benchmark did not build' }
Push-Location (Join-Path $here 'go')
try { go build -o (Join-Path $work 'bench-go.exe') .; if ($LASTEXITCODE -ne 0) { throw 'the Go benchmark did not build' } } finally { Pop-Location }
cargo +stable-x86_64-pc-windows-msvc build --release --quiet --manifest-path (Join-Path $here 'rust\Cargo.toml')
if ($LASTEXITCODE -ne 0) { throw 'the Rust benchmark did not build' }
Copy-Item -Force (Join-Path $env:CARGO_TARGET_DIR 'release\bench-rust.exe') (Join-Path $work 'bench-rust.exe')

$servers = Join-Path $work 'servers'
$dsn = 'HKCU:\Software\ODBC\ODBC.INI\neper_psqlodbc'
$savedPath = $env:PATH
$status = 0
try {
    & (Join-Path $repo 'tests\selfhost\db_servers.ps1') start $servers | Out-Null
    $ports = @{}
    foreach ($line in Get-Content (Join-Path $servers 'ports')) { $key, $value = $line -split '=', 2; $ports[$key] = $value }
    New-Item -Force $dsn | Out-Null
    New-ItemProperty -Force $dsn -Name Driver -Value (Join-Path $tools 'psqlodbc\podbc35w.dll') | Out-Null
    $env:PATH = @((Join-Path $tools 'postgresql\bin'), (Join-Path $tools 'mysql\lib'), (Join-Path $tools 'mysql\bin'), (Join-Path $tools 'psqlodbc'), $savedPath) -join ';'
    python (Join-Path $here 'run.py') --neper (Join-Path $work 'bench') --c (Join-Path $work 'bench-c.exe') --go (Join-Path $work 'bench-go.exe') --rust (Join-Path $work 'bench-rust.exe') --runs $Runs --scratch $work --pg-port $ports['pg_port'] --mysql-port $ports['mysql_port'] --out $Out
    $status = $LASTEXITCODE
} finally {
    Remove-Item -Force -ErrorAction SilentlyContinue $dsn
    $env:PATH = $savedPath
    & (Join-Path $repo 'tests\selfhost\db_servers.ps1') stop $servers | Out-Null
}
exit $status
