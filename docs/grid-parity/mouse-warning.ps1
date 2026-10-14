param([ValidateSet('show','hide','run')][string]$Action = 'show')
# A semi-transparent, click-through, always-on-top warning window with a warning emoji: shown while a
# script drives the mouse and keyboard, hidden when it is done.
#   mouse-warning.ps1 show   starts it in its own process (idempotent)
#   mouse-warning.ps1 hide   closes it
$pidFile = Join-Path $env:TEMP 'neper-mouse-warning.pid'
function Stop-Warning {
    if (Test-Path $pidFile) {
        $p = [int](Get-Content $pidFile -ErrorAction SilentlyContinue)
        if ($p) { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue }
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    }
}
if ($Action -eq 'hide') { Stop-Warning; return }
if ($Action -eq 'show') {
    if (Test-Path $pidFile) {
        $p = [int](Get-Content $pidFile -ErrorAction SilentlyContinue)
        if ($p -and (Get-Process -Id $p -ErrorAction SilentlyContinue)) { return }
    }
    $proc = Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile', '-STA', '-File', $MyInvocation.MyCommand.Path, 'run')
    Set-Content -Path $pidFile -Value $proc.Id
    Start-Sleep -Milliseconds 700
    return
}
# run: the window itself
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class WW { [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
[DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v); }
"@
$f = New-Object System.Windows.Forms.Form
$f.FormBorderStyle = 'None'
$f.TopMost = $true
$f.ShowInTaskbar = $false
$f.StartPosition = 'Manual'
$f.Opacity = 0.55
$f.BackColor = [System.Drawing.Color]::FromArgb(255, 200, 0)
$area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$f.Size = New-Object System.Drawing.Size(640, 90)
$f.Location = New-Object System.Drawing.Point(($area.Left + [int](($area.Width - 640) / 2)), ($area.Top + 12))
$l = New-Object System.Windows.Forms.Label
$l.Dock = 'Fill'
$l.TextAlign = 'MiddleCenter'
$l.Font = New-Object System.Drawing.Font('Segoe UI Emoji', 16)
$l.Text = ([char]0x26A0 + [char]0xFE0F + '  Claude is controlling the mouse and keyboard  ' + [char]0x26A0 + [char]0xFE0F)
$f.Controls.Add($l)
$f.Add_Shown({
    # click-through and never activated, so it cannot take a click or the keyboard focus
    $h = $f.Handle
    $style = [WW]::GetWindowLong($h, -20)
    [void][WW]::SetWindowLong($h, -20, $style -bor 0x20 -bor 0x80000 -bor 0x08000000)
})
[System.Windows.Forms.Application]::Run($f)
