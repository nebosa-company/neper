# Native Win32 control gallery

A small x86 C program (`gallery.c`) that creates the standard Windows controls, drives each one through its states and saves it with `PrintWindow`. It is the independent Windows 11 reference for the Windows look in light and dark (v3 has no dark mode). Output: `docs/ui/looks/ref/windows-native/` (see the README there).

No screen access and no real input: states come from sent/posted window messages (`BM_SETSTATE`, `TB_SETHOTITEM`, `CB_SHOWDROPDOWN`, `WM_KEYDOWN`, ...) and "hot" looks from `scripts/v3_hook/v3hook.dll`, which gallery.exe loads **into its own process** and which fakes `GetCursorPos`, `GetMessagePos`, `WindowFromPoint`, `GetKeyState(VK_LBUTTON)` and `TrackMouseEvent`. Never `SendInput`, `mouse_event`, `keybd_event`, `SetCursorPos`, computer-use or owner drawing.

Files: `gallery.c`, `gallery.manifest` (comctl32 v6, activated with `CreateActCtx`), `build.ps1`, `run.ps1` (everything), `finish.py` (BMP to PNG, manifest.csv, controls.json). The hook gained one field, `tmeAll`, that swallows `TrackMouseEvent` for every class (v3 only needed Button classes).

```
pwsh -File scripts\winnative\run.ps1                      # build, light+dark x 100 %+150 %, convert (about 6 minutes)
pwsh -File scripts\winnative\run.ps1 -Dpis 100 -Case combo # one case, 100 % only
D:\Temp\claude\winnative\gallery.exe <out> <light|dark> <100|150> [name-substring|-] [case]
```

Build: `zig cc -target x86-windows-gnu` (zig at `D:\tools\zig`), output in `D:\Temp\claude\winnative`.

## How dark is applied

`SetPreferredAppMode(ForceDark)` (uxtheme ordinal 135), `FlushMenuThemes` (136), `RefreshImmersiveColorPolicyState` (104); every top-level window gets `DWMWA_USE_IMMERSIVE_DARK_MODE` (a CBT hook, so message boxes and task dialogs too) and `AllowDarkModeForWindow` (133); every control gets `SetWindowTheme`: `DarkMode_Explorer` (default), `DarkMode_CFD` (edit, combo), `DarkMode_ItemsView` (list view header). The dialog background and static/edit text colours come from `WM_CTLCOLOR*` (`#202020`, white): that colour is the app's choice, the system does not supply it. List view / tree view colours use `LVM_SETBKCOLOR` etc. Light mode is the default (no preferred mode set), so it does not follow the user's system theme. Light list/tree views use the `Explorer` theme like every modern app.

## Traps

- The instances share the hook's memory block `Local\v3hover`: run them one at a time.
- `PrintWindow` returns the DWM surface of the window: always `RedrawWindow(..., RDW_UPDATENOW)` and pump before it, otherwise a just-changed control is captured stale or blank. `snapx` does this.
- `PrintWindow` of a framed window includes the invisible DWM resize borders as black: `vrect` crops to `DWMWA_EXTENDED_FRAME_BOUNDS` (scaled when DPI unaware).
- A caption-button press (`WM_NCLBUTTONDOWN`) runs a tracking loop on the real mouse state and hangs: not captured.
- Menu loops ignore `MN_SELECTITEM` and posted `WM_MOUSEMOVE`; only keyboard selection works, which draws the keyboard-cue outline. Snapshots inside modal loops run from a `SetTimer(NULL)` callback.
- A heredoc through the shell mangles backslashes in C/python source; write sources with the editor.
- ListBox and the combo drop list get no dark theme: with `DarkMode_*` their selection is white on white (invisible text). Progress bar likewise (white fill). They keep the light scroll bar.
- DPI: 100 % = unaware process (same as v3). 150 % = per-monitor-v2 on the primary monitor (144 dpi on this machine); 200 % is not available natively (no monitor at 192 dpi, and changing the display scale is a system setting).
