# v3 reference captures

`main-window@1x.png`: the real MTG Studio v3 main window (Card Pool, Collection from Pool mode), 800 x 600 at 100 %
(the v3 exe is DPI unaware, so PrintWindow paints it at 100 % even on a 150 % desktop). Taken 2026-10-15 with
`scripts/grab_v3_windows.ps1` (launches a copy of `version-3/bin/mtgstudio.exe` from `D:\Temp\claude\v3run`, saves each
visible top-level window with Win32 PrintWindow; no mouse, no keyboard, no screen access). It shows the menu bar,
two toolbars (enabled and disabled buttons), the Mode combo, the status bar, splitters, grid chrome, scroll bars and
the tab strip at rest. Dialogs need input to open and are not captured this way; the older 150 % captures in
`docs/grid-parity` remain the only references for them.
