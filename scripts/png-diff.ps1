# Row-by-row comparison of two rendered reftest images, for the cases where the layout is measured
# correct (fragments, box heights, painted ranges) and the images still differ: prints the first
# differing pixel, the row and column ink histograms, and the rows whose ink differs.
#
#   scripts/png-diff.ps1 -A tmp/wpt/out/test.png -B tmp/wpt/out/ref.png
#
# `-WindowX/-WindowY/-WindowW/-WindowH` restrict the comparison to a window, which is how a single box of a multi-box test
# (`letter-spacing-200` has four floats) is looked at on its own.
param(
    [Parameter(Mandatory = $true)][string]$A,
    [Parameter(Mandatory = $true)][string]$B,
    [int]$MaxRows = 40,
    [int]$WindowX = 0,
    [int]$WindowY = 0,
    [int]$WindowW = 0,
    [int]$WindowH = 0
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
$ia = [System.Drawing.Bitmap]::FromFile((Resolve-Path $A))
$ib = [System.Drawing.Bitmap]::FromFile((Resolve-Path $B))
if ($ia.Width -ne $ib.Width -or $ia.Height -ne $ib.Height) {
    Write-Output "size differs: $($ia.Width)x$($ia.Height) vs $($ib.Width)x$($ib.Height)"
    exit 1
}
$w = $ia.Width
$h = $ia.Height
if ($WindowW -gt 0) { if ($WindowX + $WindowW -lt $w) { $w = $WindowX + $WindowW } }
if ($WindowH -gt 0) { if ($WindowY + $WindowH -lt $h) { $h = $WindowY + $WindowH } }
$first = $null
$rows = @()
for ($y = $WindowY; $y -lt $h; $y++) {
    $na = 0
    $nb = 0
    $diff = 0
    for ($x = $WindowX; $x -lt $w; $x++) {
        $pa = $ia.GetPixel($x, $y)
        $pb = $ib.GetPixel($x, $y)
        $wa = ($pa.R -lt 250) -or ($pa.G -lt 250) -or ($pa.B -lt 250)
        $wb = ($pb.R -lt 250) -or ($pb.G -lt 250) -or ($pb.B -lt 250)
        if ($wa) { $na++ }
        if ($wb) { $nb++ }
        if ($pa.ToArgb() -ne $pb.ToArgb()) {
            $diff++
            if ($null -eq $first) { $first = "first difference at x=$x y=$y (A=$($pa.R),$($pa.G),$($pa.B) B=$($pb.R),$($pb.G),$($pb.B))" }
        }
    }
    if ($diff -gt 0) { $rows += [pscustomobject]@{ y = $y; inkA = $na; inkB = $nb; diff = $diff } }
}
$ia.Dispose()
$ib.Dispose()
if ($null -eq $first) { Write-Output "images are identical"; exit 0 }
Write-Output $first
Write-Output ("rows with differences: {0}" -f $rows.Count)
$rows | Select-Object -First $MaxRows | Format-Table -AutoSize | Out-String -Width 80 | Write-Output
