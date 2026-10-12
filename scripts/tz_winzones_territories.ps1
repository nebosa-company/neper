# Extract the CLDR windowsZones territory rows that differ from the 001 default through .NET's
# TimeZoneInfo.TryConvertWindowsIdToIanaId (ICU's CLDR data), for scripts/gen_tz_winzones.py:
#   pwsh scripts/tz_winzones_territories.ps1 <windows ids file, one per line> > scripts/tz_winzones_territories.txt
# Every two-letter code AA..ZZ is asked for every id; the ones that answer differently from "001"
# are rows. Output lines are `Windows id|TT=iana`, sorted.
param([string]$Ids)
$names = Get-Content $Ids | Where-Object { $_.Trim() }
$letters = [char[]](65..90)
$rows = New-Object System.Collections.Generic.List[string]
foreach ($w in $names) {
    $d = $null; [void][TimeZoneInfo]::TryConvertWindowsIdToIanaId($w, "001", [ref]$d)
    foreach ($a in $letters) { foreach ($b in $letters) {
        $region = "$a$b"; $o = $null
        if ([TimeZoneInfo]::TryConvertWindowsIdToIanaId($w, $region, [ref]$o) -and $o -ne $d) { $rows.Add("$w|$region=$o") }
    } }
}
$rows | Sort-Object -CaseSensitive
