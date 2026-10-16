# Hover helpers for the COPY of v3 (see scripts\v3_hook\README.md). Dot-source after nothing else: it loads v3_states_lib.ps1 itself.
# The hook DLL (injected into mtgstudio_s only) makes GetCursorPos / GetMessagePos / WindowFromPoint / GetKeyState(VK_LBUTTON) answer from the
# shared block "Local\v3hover" that FakeAt writes. The real pointer and keyboard are never used; the pointer messages are still posted.
. (Join-Path $PSScriptRoot 'v3_states_lib.ps1')
$script:Hook = 'D:\Temp\claude\v3run\hook'
$script:Mmf = $null; $script:Acc = $null
# block layout (int32): 0 x, 1 y, 2 enabled, 3 lbutton, 4 GetCursorPos calls, 5 IAT slots patched, 6 WindowFromPoint calls, 7 GetKeyState(VK_LBUTTON) calls, 8 ready, 9 slots patched in the exe, 10 hooked GetProcAddress hits
function Hook-Get($i){ $script:Acc.ReadInt32($i*4) }
function Hook-Set($i,$v){ $script:Acc.Write($i*4,[int]$v) }
function Start-Hooked($deck=$null){
  try{ $script:p.Kill() }catch{}; if($script:Acc){ $script:Acc.Dispose(); $script:Acc=$null }; if($script:Mmf){ $script:Mmf.Dispose(); $script:Mmf=$null }; Start-Sleep -Milliseconds 800
  Start-App $deck
  & "$script:Hook\inject.exe" $script:p.Id "$script:Hook\v3hook.dll" | Out-Null
  for($i=0;$i -lt 40;$i++){ Start-Sleep -Milliseconds 250; try{ $script:Mmf=[IO.MemoryMappedFiles.MemoryMappedFile]::OpenExisting('v3hover'); break }catch{} }
  if(-not $script:Mmf){ throw 'hook mapping did not appear' }
  $script:Acc=$script:Mmf.CreateViewAccessor(0,60)
  for($i=0;$i -lt 40 -and -not (Hook-Get 8);$i++){ Start-Sleep -Milliseconds 100 }
  FakeAway
  "hook ready, slots patched: $(Hook-Get 5) (exe $(Hook-Get 9))" }
# fake pointer at SCREEN x,y (enabled); FakeAway parks it far from every window (still "enabled", so the real pointer is never read)
function FakeAt($sx,$sy){ Hook-Set 0 $sx; Hook-Set 1 $sy; Hook-Set 2 1 }
function FakeAway { Hook-Set 3 0; FakeAt -5000 -5000 }
function FakeButton($down){ Hook-Set 3 ([int]$down) }
# hover at IMAGE coords of top-level window $top: fake pointer there, then post WM_MOUSEMOVE to the deepest child (and its ancestors up to top for
# dxBar style controls that listen on the bar), wait, return the target
function HoverAt($top,$px,$py,$wait=350,[switch]$NoAway){
  $r=[W]::Rect($top); $sx=$r[0]+$px; $sy=$r[1]+$py
  if(-not $NoAway){ FakeAway; Start-Sleep -Milliseconds 80 }
  FakeAt $sx $sy
  $u=Under $top $px $py
  MoveC $u.H $u.X $u.Y; Start-Sleep -Milliseconds 60; MoveC $u.H ($u.X) ($u.Y)
  Start-Sleep -Milliseconds $wait; $u }
function Unhover($u){ FakeAway; if($u){ Msg $u.H 0x2A3 0 0 }; Start-Sleep -Milliseconds 200 } # WM_MOUSELEAVE to the control we left
# glide: move the fake pointer in steps from (px0,py0) to (px1,py1) (image coords of $top), posting a WM_MOUSEMOVE to whatever is under each step, like a real mouse path
function GlideTo($top,$px0,$py0,$px1,$py1,$steps=8,$wait=350){
  $r=[W]::Rect($top); $u=$null
  for($i=0;$i -le $steps;$i++){ $x=[int]($px0+($px1-$px0)*$i/$steps); $y=[int]($py0+($py1-$py0)*$i/$steps)
    FakeAt ($r[0]+$x) ($r[1]+$y); $u=Under $top $x $y; MoveC $u.H $u.X $u.Y; Start-Sleep -Milliseconds 30 }
  Start-Sleep -Milliseconds $wait; $u }
