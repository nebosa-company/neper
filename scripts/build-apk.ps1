# Pack a neper NativeActivity app into a signed APK (T044, D5909): the program, built with `emit-shared-library` for
# x86_64 and arm64-v8a, is the app's libapp.so, and android.app.NativeActivity (no Java code) loads it and calls its
# exported ANativeActivity_onCreate. The manifest is written here; aapt2 links it against the platform's android.jar,
# the libraries go in uncompressed, zipalign pages them, and apksigner (run by WSL's Java) signs with the debug key.
#   scripts/build-apk.ps1 -Source examples/android/native_activity/src/main.e -Package dev.neper.example -Out build/android/example.apk
# Then `adb install -r OUT` and `adb shell am start -n PACKAGE/android.app.NativeActivity`.
param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Package,
    [Parameter(Mandatory = $true)][string]$Out,
    [string]$Label = 'neper',
    [string]$Platform = 'android-35',
    [string]$BuildTools = '35.0.0'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$compiler = if ($env:NEPER_COMPILER) { $env:NEPER_COMPILER } else { Join-Path $repo 'build\windows\neper-try.exe' }
$sdk = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { 'D:\tools\Android\Sdk' }
$tools = Join-Path $sdk "build-tools\$BuildTools"
$stage = Join-Path $repo "build\android\apk-$Package"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force $stage | Out-Null

foreach ($abi in @(@('x64', 'x86_64'), @('aarch64', 'arm64-v8a'))) {
    $dir = Join-Path $stage "lib\$($abi[1])"
    New-Item -ItemType Directory -Force $dir | Out-Null
    $written = & $compiler emit-shared-library $Source $repo $abi[0] 'android' (Join-Path $dir 'libapp.so')
    if ($written -ne 'executable written') { throw "libapp.so for $($abi[1]) did not build: $written" }
}

$manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="$Package" android:versionCode="1" android:versionName="1.0">
  <uses-sdk android:minSdkVersion="26" android:targetSdkVersion="35" />
  <application android:label="$Label" android:hasCode="false" android:extractNativeLibs="false">
    <activity android:name="android.app.NativeActivity" android:exported="true" android:configChanges="orientation|keyboardHidden|screenSize">
      <meta-data android:name="android.app.lib_name" android:value="app" />
      <intent-filter>
        <action android:name="android.intent.action.MAIN" />
        <category android:name="android.intent.category.LAUNCHER" />
      </intent-filter>
    </activity>
  </application>
</manifest>
"@
$manifestPath = Join-Path $stage 'AndroidManifest.xml'
[System.IO.File]::WriteAllText($manifestPath, $manifest)
$linked = Join-Path $stage 'linked.apk'
& (Join-Path $tools 'aapt2.exe') link -o $linked --manifest $manifestPath -I (Join-Path $sdk "platforms\$Platform\android.jar")
if ($LASTEXITCODE -ne 0) { throw 'aapt2 link failed' }

# The libraries stored, not deflated: with extractNativeLibs false Android maps them straight from the APK.
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($linked, 'Update')
try {
    foreach ($abi in 'x86_64', 'arm64-v8a') {
        $entry = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, (Join-Path $stage "lib\$abi\libapp.so"), "lib/$abi/libapp.so", [System.IO.Compression.CompressionLevel]::NoCompression)
    }
} finally { $zip.Dispose() }

$aligned = Join-Path $stage 'aligned.apk'
& (Join-Path $tools 'zipalign.exe') -f -P 16 4 $linked $aligned
if ($LASTEXITCODE -ne 0) { throw 'zipalign failed' }

function ToWsl([string]$path) { $full = [System.IO.Path]::GetFullPath($path); '/mnt/' + $full.Substring(0, 1).ToLower() + $full.Substring(2).Replace('\', '/') }
$keystore = Join-Path $env:USERPROFILE '.android\debug.keystore'
$outFull = [System.IO.Path]::GetFullPath((Join-Path $repo $Out))
New-Item -ItemType Directory -Force (Split-Path -Parent $outFull) | Out-Null
$signer = ToWsl (Join-Path $tools 'lib\apksigner.jar')
wsl.exe -e java -jar $signer sign --ks (ToWsl $keystore) --ks-pass pass:android --key-pass pass:android --out (ToWsl $outFull) (ToWsl $aligned)
if ($LASTEXITCODE -ne 0) { throw 'apksigner failed' }
Write-Output "apk written: $Out"
