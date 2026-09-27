# Throwaway PostgreSQL and MySQL servers for the x.postgresql.libpq and x.oracle.mysql fixtures.
#
#   db_servers.ps1 start <dir>   initialise fresh data directories under <dir> and start both
#   db_servers.ps1 stop <dir>    stop both (safe to run when they are not running)
#
# Both listen on 127.0.0.1 only: PostgreSQL on 55432 (user `neper`, trust auth, database
# `postgres`), MySQL on 53306 (user `root`, no password, database `neper`). The binaries come
# from $env:NEPER_DB_TOOLS (default D:\tools): <tools>\postgresql\bin and <tools>\mysql\bin, as
# the EDB and Oracle Windows archives unpack.
param(
    [Parameter(Mandatory = $true)][ValidateSet('start', 'stop')][string]$Action,
    [Parameter(Mandatory = $true)][string]$Dir
)
$ErrorActionPreference = 'Stop'
$tools = if ($env:NEPER_DB_TOOLS) { $env:NEPER_DB_TOOLS } else { 'D:\tools' }
$pgBin = Join-Path $tools 'postgresql\bin'
$myBase = Join-Path $tools 'mysql'
$myBin = Join-Path $myBase 'bin'
$pgData = Join-Path $Dir 'pg'
$myData = Join-Path $Dir 'my'
$pgPort = 55432
$myPort = 53306

function Stop-Servers {
    if (Test-Path (Join-Path $pgData 'postmaster.pid')) {
        & (Join-Path $pgBin 'pg_ctl.exe') -D $pgData -m fast -w stop *> $null
    }
    & (Join-Path $myBin 'mysqladmin.exe') --user=root --host=127.0.0.1 "--port=$myPort" --connect-timeout=2 shutdown *> $null
    # mysqladmin returns before the server has let go of its files.
    for ($i = 0; $i -lt 50; $i++) {
        $held = Get-Process mysqld -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq (Join-Path $myBin 'mysqld.exe') }
        if (-not $held) { break }
        Start-Sleep -Milliseconds 200
    }
}

if ($Action -eq 'stop') { Stop-Servers; return }

foreach ($binary in @((Join-Path $pgBin 'initdb.exe'), (Join-Path $myBin 'mysqld.exe'))) {
    if (-not (Test-Path $binary)) { throw "db_servers: $binary is missing; unpack PostgreSQL and MySQL under $tools" }
}
Stop-Servers
if (Test-Path $Dir) { Remove-Item -Recurse -Force $Dir }
New-Item -ItemType Directory -Force $Dir | Out-Null

& (Join-Path $pgBin 'initdb.exe') -D $pgData -U neper -A trust -E UTF8 --no-locale -N *> (Join-Path $Dir 'pg-init.log')
if ($LASTEXITCODE -ne 0) { throw "db_servers: initdb failed; see $Dir\pg-init.log" }
# The server pg_ctl leaves running would inherit a redirected output pipe and hold it open, and
# PowerShell would wait on it forever; so pg_ctl gets no pipe, and only pg_ctl is waited for.
$pgStart = Start-Process -FilePath (Join-Path $pgBin 'pg_ctl.exe') -ArgumentList @('-D', $pgData, '-l', (Join-Path $Dir 'pg.log'), '-o', "`"-p $pgPort -c listen_addresses=127.0.0.1 -c fsync=off`"", '-w', 'start') -WindowStyle Hidden -PassThru
$pgStart.WaitForExit()
if ($pgStart.ExitCode -ne 0) { throw "db_servers: PostgreSQL did not start; see $Dir\pg.log" }

& (Join-Path $myBin 'mysqld.exe') --no-defaults --initialize-insecure "--basedir=$myBase" "--datadir=$myData" *> (Join-Path $Dir 'my-init.log')
if ($LASTEXITCODE -ne 0) { throw "db_servers: mysqld --initialize-insecure failed; see $Dir\my-init.log" }
$arguments = @('--no-defaults', "--basedir=$myBase", "--datadir=$myData", "--port=$myPort", '--bind-address=127.0.0.1', '--mysqlx=OFF', '--skip-log-bin', "--log-error=$(Join-Path $Dir 'my.log')")
Start-Process -FilePath (Join-Path $myBin 'mysqld.exe') -ArgumentList $arguments -WindowStyle Hidden | Out-Null
$up = $false
for ($i = 0; $i -lt 150; $i++) {
    & (Join-Path $myBin 'mysqladmin.exe') --user=root --host=127.0.0.1 "--port=$myPort" --connect-timeout=2 ping *> $null
    if ($LASTEXITCODE -eq 0) { $up = $true; break }
    Start-Sleep -Milliseconds 200
}
if (-not $up) { throw "db_servers: MySQL did not start; see $Dir\my.log" }
& (Join-Path $myBin 'mysql.exe') --user=root --host=127.0.0.1 "--port=$myPort" -e 'CREATE DATABASE neper' *> (Join-Path $Dir 'my-create.log')
if ($LASTEXITCODE -ne 0) { throw "db_servers: could not create the MySQL database; see $Dir\my-create.log" }
