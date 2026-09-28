# The SQL Server that x.microsoft.tds's Windows fixture talks to (D1643): the CELVYX instance
# (SQL Server 2025 Developer, TCP 14330), which accepts TDS 8.0 strict connections once
# sqlserver_tls.ps1 has given it a certificate (run that once, elevated). `start` creates the
# `neper` login and database through Windows authentication when they are missing.
#
#   sqlserver.ps1 start DIR   start the instance if stopped; append tds_* lines to DIR\ports
#   sqlserver.ps1 stop DIR    stop it again if `start` started it
#
# The password is a test value for a login on a loopback-only development instance.
param(
    [Parameter(Mandatory)][ValidateSet('start', 'stop')][string]$Action,
    [Parameter(Mandatory)][string]$Dir
)
$ErrorActionPreference = 'Stop'
$service = 'MSSQL$CELVYX'
$port = 14330
$certificate = 'D:\tools\mssql\neper-tls.cer'
$password = 'Neper-test-only-1!'

# One batch as the current Windows user, through Windows PowerShell's System.Data.SqlClient
# (PowerShell 7 has none). Windows authentication sends no password; the certificate is not
# checked on this loopback administration connection.
function Invoke-Admin([string]$sql, [switch]$Quiet) {
    $env:NEPER_SQLSERVER_BATCH = $sql
    $env:NEPER_SQLSERVER_PORT = "$port"
    $script = @'
$c = New-Object System.Data.SqlClient.SqlConnection ("Server=tcp:localhost," + $env:NEPER_SQLSERVER_PORT + ";Integrated Security=true;Encrypt=true;TrustServerCertificate=true;Connect Timeout=10")
$c.Open()
$q = $c.CreateCommand()
$q.CommandText = $env:NEPER_SQLSERVER_BATCH
[void]$q.ExecuteNonQuery()
$c.Close()
'@
    if ($Quiet) {
        powershell.exe -NoProfile -NonInteractive -Command $script 2>&1 | Out-Null
    } else {
        powershell.exe -NoProfile -NonInteractive -Command $script
    }
    $answered = $LASTEXITCODE -eq 0
    Remove-Item Env:\NEPER_SQLSERVER_BATCH, Env:\NEPER_SQLSERVER_PORT
    return $answered
}

if ($Action -eq 'start') {
    if (-not (Test-Path $certificate)) {
        throw "sqlserver.ps1: $certificate is missing; run tests\selfhost\sqlserver_tls.ps1 once in an elevated Windows PowerShell"
    }
    New-Item -ItemType Directory -Force $Dir | Out-Null
    $started = 0
    if ((Get-Service $service).Status -ne 'Running') {
        Start-Service $service
        $started = 1
    }
    Set-Content (Join-Path $Dir 'sqlserver-started') $started
    $ready = $false
    for ($i = 0; $i -lt 90 -and -not $ready; $i++) {
        $ready = Invoke-Admin 'SELECT 1' -Quiet
        if (-not $ready) { Start-Sleep -Seconds 1 }
    }
    if (-not $ready) { throw "sqlserver.ps1: SQL Server did not answer on $port" }
    if (-not (Invoke-Admin "IF SUSER_ID('neper') IS NULL CREATE LOGIN neper WITH PASSWORD = '$password', CHECK_POLICY = OFF; IF DB_ID('neper') IS NULL CREATE DATABASE neper;")) { throw 'sqlserver.ps1: could not create the neper login and database' }
    if (-not (Invoke-Admin "USE neper; IF USER_ID('neper') IS NULL CREATE USER neper FOR LOGIN neper; ALTER ROLE db_owner ADD MEMBER neper;")) { throw 'sqlserver.ps1: could not make neper the database owner' }
    Add-Content (Join-Path $Dir 'ports') @("tds_port=$port", "tds_root=$certificate", 'tds_user=neper', "tds_password=$password")
} else {
    $flag = Join-Path $Dir 'sqlserver-started'
    if ((Test-Path $flag) -and (Get-Content $flag) -eq '1') { Stop-Service $service }
    Remove-Item -Force -ErrorAction SilentlyContinue $flag
}
