# Dot-sourced by run.ps1. With NEPER_REFRESH_GOLDENS=1, an x64 tool golden that differs from the actual output only
# in its "snapshot" hashes is overwritten instead of failing the comparison. Each hash folds the text of every module
# the subject reaches, so any library edit moves it; any other difference still fails.
# The comparisons are `Get-FileHash actual` then `Get-FileHash golden`, so the call before a golden is its actual.
if ($env:NEPER_REFRESH_GOLDENS -eq '1') {
    $script:goldenActual = $null
    function Get-FileHash {
        param([string]$Algorithm, [string]$LiteralPath)
        if ($LiteralPath -match '[\\/]tests[\\/]conformance[\\/]tools[\\/][^\\/]+\.expected\.jsonl$' -and $script:goldenActual) {
            $actualText = [IO.File]::ReadAllText($script:goldenActual)
            $goldenText = [IO.File]::ReadAllText($LiteralPath)
            $mask = '"snapshot":"[0-9a-f]*"'
            if ($actualText -ne $goldenText -and ($actualText -replace $mask, '') -eq ($goldenText -replace $mask, '')) {
                [IO.File]::WriteAllText($LiteralPath, $actualText)
                Write-Host "refreshed $LiteralPath"
            }
        } else {
            $script:goldenActual = $LiteralPath
        }
        Microsoft.PowerShell.Utility\Get-FileHash -Algorithm $Algorithm -LiteralPath $LiteralPath
    }
}
