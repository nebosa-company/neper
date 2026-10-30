# Windows PowerShell 5.1: neural-ish OneCore voices via WinRT, with SSML energy.
param([string]$Voice = 'Microsoft Mark', [string]$Rate = '+12%', [string]$Pitch = '+6%', [string]$Out = "$PSScriptRoot\audio", [string]$Only = '')
Add-Type -AssemblyName System.Runtime.WindowsRuntime
[void][Windows.Media.SpeechSynthesis.SpeechSynthesizer,Windows.Media.SpeechSynthesis,ContentType=WindowsRuntime]
[void][Windows.Storage.Streams.DataReader,Windows.Storage.Streams,ContentType=WindowsRuntime]
$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | ? { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select -First 1
function Await($op, $type) { $t = $asTask.MakeGenericMethod($type).Invoke($null, @($op)); $t.Wait(); $t.Result }
$cfg = Get-Content "$PSScriptRoot\narration.json" -Raw | ConvertFrom-Json
New-Item -ItemType Directory -Force $Out | Out-Null
$s = New-Object Windows.Media.SpeechSynthesis.SpeechSynthesizer
$s.Voice = [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices | ? { $_.DisplayName -eq $Voice } | Select -First 1
foreach ($sc in $cfg.scenes) {
  if ($Only -and $sc.id -ne $Only) { continue }
  $text = [System.Security.SecurityElement]::Escape($sc.say)
  $ssml = "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'><prosody rate='$Rate' pitch='$Pitch'>$text</prosody></speak>"
  $stream = Await ($s.SynthesizeSsmlToStreamAsync($ssml)) ([Windows.Media.SpeechSynthesis.SpeechSynthesisStream])
  $reader = New-Object Windows.Storage.Streams.DataReader($stream)
  [void](Await ($reader.LoadAsync([uint32]$stream.Size)) ([uint32]))
  $bytes = New-Object byte[] $stream.Size
  $reader.ReadBytes($bytes)
  [IO.File]::WriteAllBytes("$Out\$($sc.id).wav", $bytes)
}
