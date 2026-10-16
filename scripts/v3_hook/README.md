# v3 pointer hook (hover captures of the v3 COPY)

Posted window messages cannot make VCL / DevExpress draw a hover look: they decide "the mouse is over this control" from the real pointer. This folder holds a tiny 32-bit DLL that is injected into the COPY of MTG Studio v3 only (`D:\Temp\claude\v3run\mtgstudio_s.exe`) and makes those questions answer from a shared memory block that `scripts\v3_hover_lib.ps1` writes. The real cursor and keyboard are never used, and nothing under `D:\repos\mtg.studio.src\version-3`, the installed program or the maintainer's own v3 is touched.

## Files

| File | What |
|---|---|
| `v3hook.c` | the hook DLL |
| `inject.c` | `inject.exe <pid> <dll>`: `CreateRemoteThread` + `LoadLibraryW`. It must be 32-bit so that its `kernel32!LoadLibraryW` address is the 32-bit one |
| `build.ps1` | builds both with `zig cc -target x86-windows-gnu` (zig is at `D:\tools\zig`; no Visual Studio or Delphi compiler is installed) into `D:\Temp\claude\v3run\hook` |

## Rebuild and use

```
pwsh -File scripts\v3_hook\build.ps1                    # v3hook.dll + inject.exe -> D:\Temp\claude\v3run\hook
pwsh -File scripts\grab_v3_hover.ps1 -Only main         # launches the copy, injects, captures, kills the copy
```

`Start-Hooked` in `scripts\v3_hover_lib.ps1` starts the copy, runs `inject.exe`, opens the mapping `Local\v3hover` and parks the fake pointer off screen. Helpers: `FakeAt sx sy`, `FakeAway`, `FakeButton 0|1`, `HoverAt $window $px $py` (fake pointer there, then `WM_MOUSEMOVE` to the deepest child), `GlideTo`, `Unhover`.

Shared block (int32 each): `x y enabled lbutton | calls of GetCursorPos | slots patched | WindowFromPoint calls | GetKeyState(VK_LBUTTON) calls | ready | slots patched in the exe | GetProcAddress hits | last WindowFromPoint result and point | TrackMouseEvent swallowed`. The harness reads the counters to prove the hooks are hit; with `enabled = 0` every call passes through to the real function.

## What it patches

Only the import tables (IAT) of every module loaded in that one process, by matching the slot's value against the real user32 address (no name tables: Borland-style imports have none). Do not parse names or touch the delay-load tables: the exe's delay-load descriptors are not the standard layout and reading them crashed the process.

| API | Answer while `enabled` |
|---|---|
| `GetCursorPos`, `GetMessagePos` | the fake screen point |
| `WindowFromPoint` | the real answer for the fake point; if that window is not ours (another app covers the copy) it walks the copy's own top-level windows in z-order and descends with `ChildWindowFromPointEx` |
| `GetKeyState`, `GetAsyncKeyState` | only `VK_LBUTTON`: down when `lbutton` is set (pressed looks) |
| `TrackMouseEvent` | swallowed (returns TRUE) for windows of class `Button`, `TcxButton*`, `TButton*` only: with no real pointer over the window the system answers `TME_LEAVE` with `WM_MOUSELEAVE` at once and un-hots the button. Swallowing it for dxBar broke the toolbar hover, so it is limited to button classes |
| `GetProcAddress` | user32 lookups of the functions above return the hooks (catches later lookups) |

The harness posts `WM_MOUSELEAVE` itself when it moves away.

## Traps

- The Bash tool (and any background shell) kills the copy when the call ends; run launch, capture and kill in one script, as `grab_v3_hover.ps1` does.
- `Start-Sleep 1500` is 1500 seconds in PowerShell.
- A heredoc through the shell collapses `\\` in C source: write `.c` files with the editor, not `cat <<EOF`. (`L"Local\v3hover"` once turned into a vertical tab and the mapping never appeared.)
- A crashed copy is silently restarted by `Ensure-App` in the states helpers, without the hook: if every hover is pixel-identical, check that the counters in the block still move.
- The hook needs only the resolved addresses, so it survives a new v3 build unless the exe stops importing those functions from `user32.dll`.
