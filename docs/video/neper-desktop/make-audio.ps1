param([string]$Out = "$PSScriptRoot\audio")
Add-Type -AssemblyName System.Speech
$cfg = Get-Content "$PSScriptRoot\narration.json" -Raw | ConvertFrom-Json
New-Item -ItemType Directory -Force $Out | Out-Null
$s = New-Object System.Speech.Synthesis.SpeechSynthesizer
$s.SelectVoice($cfg.voice)
$s.Rate = 0
foreach ($sc in $cfg.scenes) {
  $s.SetOutputToWaveFile("$Out\$($sc.id).wav")
  $s.Speak($sc.say)
}
$s.SetOutputToNull()
