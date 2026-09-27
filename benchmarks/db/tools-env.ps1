# Dot-source before building the Go and Rust benchmarks on Windows:  . benchmarks/db/tools-env.ps1
# Everything the two toolchains write goes under $env:NEPER_DB_TOOLS (default D:\tools): Go's
# toolchain, module cache, build cache, config and telemetry, and Cargo's registry, builds and
# temporary files. Rust itself comes from the rustup already installed; only CARGO_HOME moves.
$tools = if ($env:NEPER_DB_TOOLS) { $env:NEPER_DB_TOOLS } else { 'D:\tools' }
$home_ = Join-Path $tools 'toolhome'
foreach ($d in @('gopath', 'gocache', 'cargo-home', 'cargo-target', 'tmp', 'toolhome\AppData\Roaming', 'toolhome\AppData\Local')) {
    New-Item -ItemType Directory -Force (Join-Path $tools $d) | Out-Null
}
$env:GOROOT = Join-Path $tools 'go'
$env:GOPATH = Join-Path $tools 'gopath'
$env:GOMODCACHE = Join-Path $tools 'gopath\pkg\mod'
$env:GOCACHE = Join-Path $tools 'gocache\windows'
$env:GOENV = Join-Path $tools 'gopath\env'
$env:GOTOOLCHAIN = 'local'
$env:GOFLAGS = '-modcacherw'
# Go's config (telemetry included) lives in the user config directory: point it at D: too.
$env:APPDATA = Join-Path $home_ 'AppData\Roaming'
$env:LOCALAPPDATA = Join-Path $home_ 'AppData\Local'
$env:CARGO_HOME = Join-Path $tools 'cargo-home'
$env:CARGO_TARGET_DIR = Join-Path $tools 'cargo-target\windows'
$env:TEMP = Join-Path $tools 'tmp'
$env:TMP = $env:TEMP
# rusqlite links the Windows SDK's winsqlite3 -- the library the Neper and C benchmarks use --
# through an import library named as it expects.
$sqliteLib = Join-Path $tools 'sqlite-lib'
if (-not (Test-Path (Join-Path $sqliteLib 'sqlite3.lib'))) {
    New-Item -ItemType Directory -Force $sqliteLib | Out-Null
    $sdk = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\Lib\*\um\x64\winsqlite3.lib' | Sort-Object FullName | Select-Object -Last 1
    Copy-Item $sdk.FullName (Join-Path $sqliteLib 'sqlite3.lib')
}
$env:SQLITE3_LIB_DIR = $sqliteLib
$env:PATH = (Join-Path $env:GOROOT 'bin') + ';' + $env:PATH
