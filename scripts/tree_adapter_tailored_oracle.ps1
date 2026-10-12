# The order .NET's ICU-backed CompareInfo (CLDR collation) gives each language's name list, for
# scripts/gen_tree_adapter_tailored_test.py: reads a JSON object {culture: [names]} and writes the same shape
# sorted by that culture's culture-sensitive comparison (CompareOptions.None).
#   pwsh scripts/tree_adapter_tailored_oracle.ps1 scripts/tree_adapter_tailored_names.json scripts/tree_adapter_tailored_order.json
param([string]$Names, [string]$OutFile)
$spec = Get-Content -Raw -Encoding utf8 $Names | ConvertFrom-Json
$out = [ordered]@{}
foreach ($p in $spec.PSObject.Properties) {
    $ci = [System.Globalization.CultureInfo]::GetCultureInfo($p.Name).CompareInfo
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($n in $p.Value) { $list.Add([string]$n) }
    $list.Sort([System.Comparison[string]]{ param($a, $b) $ci.Compare($a, $b, [System.Globalization.CompareOptions]::None) })
    $out[$p.Name] = @($list)
}
$out | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 $OutFile
