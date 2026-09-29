# The e.db benchmark on Windows against C, Go and Rust: builds the C, Go and Rust programs, starts
# throwaway servers on free ports and the CELVYX SQL Server, registers a per-user DSN for
# psqlODBC, runs run.py over all five drivers, then removes the DSN and stops the servers.
#
#   pwsh benchmarks/db/run-windows-all.ps1 <neper-prefix> <results.json> [runs] [drivers]
#
# <neper-prefix>-<driver>.exe are the Neper benchmarks, built beforehand; [drivers] is a
# comma-separated subset of sqlite,postgresql,mysql,odbc,sqlserver (all by default). The client
# libraries and psqlODBC are unpacked under $env:NEPER_DB_TOOLS (default D:\tools); the Windows
# driver manager reaches an ODBC driver only through a DSN, so the run names the unpacked
# driver's DLL in HKCU\Software\ODBC\ODBC.INI\neper_psqlodbc for its duration. SQL Server needs
# tests/selfhost/sqlserver_tls.ps1 run once, elevated; C reaches it through Microsoft's ODBC
# Driver 18.
param(
    [Parameter(Mandatory = $true)][string]$NeperPrefix,
    [Parameter(Mandatory = $true)][string]$Out,
    [int]$Runs = 9,
    [string]$Drivers = 'sqlite,postgresql,mysql,odbc,sqlserver',
    # Adds Neper with <tools>\openssl's libcrypto sealing its SQL Server TLS records (D1646).
    [switch]$Openssl
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repo = Split-Path -Parent (Split-Path -Parent $here)
. (Join-Path $here 'tools-env.ps1')
$tools = if ($env:NEPER_DB_TOOLS) { $env:NEPER_DB_TOOLS } else { 'D:\tools' }
$work = Join-Path $repo 'build\db-bench-all'
New-Item -ItemType Directory -Force $work | Out-Null
$list = $Drivers -split ','
foreach ($driver in $list) { Copy-Item -Force "$NeperPrefix-$driver.exe" (Join-Path $work "bench-$driver.exe") }
cmd /c "`"$(Join-Path $here 'c\build.cmd')`" `"$(Join-Path $work 'bench-c.exe')`""
if ($LASTEXITCODE -ne 0) { throw 'the C benchmark did not build' }
Push-Location (Join-Path $here 'go')
try { go build -o (Join-Path $work 'bench-go.exe') .; if ($LASTEXITCODE -ne 0) { throw 'the Go benchmark did not build' } } finally { Pop-Location }
cargo +stable-x86_64-pc-windows-msvc build --release --quiet --manifest-path (Join-Path $here 'rust\Cargo.toml')
if ($LASTEXITCODE -ne 0) { throw 'the Rust benchmark did not build' }
Copy-Item -Force (Join-Path $env:CARGO_TARGET_DIR 'release\bench-rust.exe') (Join-Path $work 'bench-rust.exe')

$servers = Join-Path $work 'servers'
$sqlServer = Join-Path $work 'sqlserver'
$dsn = 'HKCU:\Software\ODBC\ODBC.INI\neper_psqlodbc'
$savedPath = $env:PATH
$status = 0
try {
    & (Join-Path $repo 'tests\selfhost\db_servers.ps1') start $servers | Out-Null
    $ports = @{}
    foreach ($line in Get-Content (Join-Path $servers 'ports')) { $key, $value = $line -split '=', 2; $ports[$key] = $value }
    $tds = @()
    if ($list -contains 'sqlserver') {
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $sqlServer
        & (Join-Path $repo 'tests\selfhost\sqlserver.ps1') start $sqlServer
        $tds = @('--tds', (Join-Path $sqlServer 'ports'))
        if ($Openssl) { $tds += '--openssl' }
    }
    New-Item -Force $dsn | Out-Null
    New-ItemProperty -Force $dsn -Name Driver -Value (Join-Path $tools 'psqlodbc\podbc35w.dll') | Out-Null
    $env:PATH = @((Join-Path $tools 'openssl'), (Join-Path $tools 'postgresql\bin'), (Join-Path $tools 'mysql\lib'), (Join-Path $tools 'mysql\bin'), (Join-Path $tools 'psqlodbc'), $savedPath) -join ';'
    python (Join-Path $here 'run.py') --neper (Join-Path $work 'bench') --c (Join-Path $work 'bench-c.exe') --go (Join-Path $work 'bench-go.exe') --rust (Join-Path $work 'bench-rust.exe') --runs $Runs --scratch $work --pg-port $ports['pg_port'] --mysql-port $ports['mysql_port'] --drivers $Drivers @tds --out $Out
    $status = $LASTEXITCODE
} finally {
    Remove-Item -Force -ErrorAction SilentlyContinue $dsn
    $env:PATH = $savedPath
    if (Test-Path $sqlServer) { & (Join-Path $repo 'tests\selfhost\sqlserver.ps1') stop $sqlServer }
    & (Join-Path $repo 'tests\selfhost\db_servers.ps1') stop $servers | Out-Null
}
exit $status
