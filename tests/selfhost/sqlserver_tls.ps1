# One-time, elevated: give a local SQL Server instance a TLS certificate so it accepts TDS 8.0
# strict connections, which x.microsoft.tds uses (D1643). The instance's self-generated
# certificate serves TDS 7.x only; strict connections are closed with "A valid TLS certificate
# is not configured".
#
#   Run in an elevated Windows PowerShell:  powershell -File tests\selfhost\sqlserver_tls.ps1 [-Instance CELVYX]
#
# It makes (or reuses) a self-signed RSA-2048 server certificate for localhost, 127.0.0.1 and this
# machine in LocalMachine\My, lets the instance's service account read its key, sets it as the
# instance's certificate, restarts the service, and writes the public certificate to
# <tools>\mssql\neper-tls.cer. The tests pin that file as their only trust root, so the server is
# verified, not trusted blindly. Nothing else on the instance changes; ForceEncryption stays off.
param([string]$Instance = 'CELVYX', [string]$Tools = $(if ($env:NEPER_DB_TOOLS) { $env:NEPER_DB_TOOLS } else { 'D:\tools' }))
$ErrorActionPreference = 'Stop'
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'run this in an elevated Windows PowerShell' }

$friendly = "neper SQL Server test ($Instance)"
$cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.FriendlyName -eq $friendly -and $_.NotAfter -gt (Get-Date).AddDays(30) } | Select-Object -First 1
if (-not $cert) {
    $fqdn = [System.Net.Dns]::GetHostByName($env:COMPUTERNAME).HostName
    $cert = New-SelfSignedCertificate -Subject "CN=$fqdn" -FriendlyName $friendly -CertStoreLocation Cert:\LocalMachine\My `
        -Type SSLServerAuthentication -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 -KeySpec KeyExchange `
        -Provider 'Microsoft RSA SChannel Cryptographic Provider' -KeyExportPolicy NonExportable -NotAfter (Get-Date).AddYears(5) `
        -TextExtension @("2.5.29.17={text}DNS=localhost&DNS=$fqdn&DNS=$env:COMPUTERNAME&IPAddress=127.0.0.1")
    "created certificate $($cert.Thumbprint)"
} else { "reusing certificate $($cert.Thumbprint)" }

# The service account reads the key: a legacy CSP key lives under MachineKeys by container name.
$service = "NT Service\MSSQL`$$Instance"
$container = $cert.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName
$keyFile = Join-Path $env:ProgramData "Microsoft\Crypto\RSA\MachineKeys\$container"
icacls $keyFile /grant "${service}:R" | Out-Null
"granted $service read on the key"

$root = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server' | Where-Object { $_.PSChildName -like "MSSQL*.$Instance" } | Select-Object -First 1
if (-not $root) { throw "no SQL Server instance named $Instance" }
Set-ItemProperty "$($root.PSPath)\MSSQLServer\SuperSocketNetLib" -Name Certificate -Value $cert.Thumbprint.ToLowerInvariant()
"set as the certificate of $($root.PSChildName)"

$service = "MSSQL`$$Instance"
$wasRunning = (Get-Service $service).Status -eq 'Running'
Restart-Service $service -Force
if (-not $wasRunning) { Stop-Service $service }
$out = Join-Path $Tools 'mssql\neper-tls.cer'
Export-Certificate -Cert $cert -FilePath $out -Type CERT | Out-Null
"public certificate written to $out"
