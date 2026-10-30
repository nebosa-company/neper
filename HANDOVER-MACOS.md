# Handover: macOS (2026-10-30)

For whoever continues the macOS work. Read `AGENTS.md`/`CLAUDE.md` first; this file is the state of the macOS stream, what is
left, and the traps, not a replacement for them. The older `docs/2026-10-20-HANDOVER-APPLE-COMPILER.md` is the compiler-side
history and is out of date on the things below.

## Where it stands

Everything the GitHub `macos-14` runners (aarch64, and x64 under Rosetta) can test is built and passing. Last full verification:
master `097158768` (2026-10-27), all three green on that one commit:

- macOS corpus: **1132 pass / 0 fail** on aarch64 and x64, plus the application-bundle step (`BUNDLE PASS`).
- Windows suite (`tests/selfhost/run.ps1`) and Linux suite (`tests/selfhost/run.sh` via `scripts/run-linux-suite.sh`): both end
  "selfhost tests passed".

Peers have pushed to master since (memory model, OpenGL, wasm, blog posts); none of it touches the macOS code, but it was not
re-verified. Re-run before relying on it (recipe at the end).

My estimate: about 91% ready. What keeps it below 100% is below.

## What is done (queue items and decisions in `docs/work-queue.json`, `docs/decisions.md`)

- **Compiler and runtime:** `aarch64-macos` / `x64-macos` Mach-O emitters, libSystem runtime, `lib/e/os.macos.e`, self-host
  (stage 2 == stage 3 on Macs). C178 closed (D5854): a C call returning a 3- or 4-double HFA (CGRect) stores v0-v3 into a
  `c-hfa-slot`; the window code reads rects by a direct `objc_msgSend` (`_stret` on x64).
- **Window system** (`lib/e/os.macos.e`): events, close veto (D5222), input methods through a run-time `NeperTextView` (D5229),
  accessibility tree as `NSAccessibilityElement`s (D5223), Retina scale (a change arrives as a `Resize` through the poll), live
  resize through `os.window_on_resize` (D5856, also Windows D5874; `Unsupported` on Linux/NeperOS/WASI).
- **Shell services** (`lib/e/os/shell.macos.e`): open/reveal, trash, startup, notices (osascript; UNUserNotificationCenter path
  written, see below), typed clipboard, file dialogs, power, screen capture, tray and menus, Dock badge/menu/overlay, lifecycle,
  hotkeys (Carbon), single instance, credentials (`security`), PDF printer, print dialogs (NSPrintPanel/NSPageLayout),
  file and URL associations (D5217), permissions (camera, microphone, location; `Permission.NotDetermined` on every host, D5901),
  biometrics (LocalAuthentication), drag out (files, images), photo picker as the open panel.
- **Metal backend** (C193, 0.95): `src/msl.e` (arch `msl`: `emit-executable k.e . msl none out.metal`), embedded as the kernel's
  `K$spirv` on a macOS target; `lib/e/gpu/metal.macos.e` (runtime; `metal.e` is the stub for other hosts); `e.gpu` `Backend.Metal`.
  Kernels run as a block state machine that reconverges by lowest block per simdgroup (D5852). Exact float divide/sqrt
  (`precise::`), loops, 32-bit relaxed atomics (D5840), subgroups (D5852), up to four 256 MiB heaps (D5878), asynchronous launches
  with up to four in flight (D5875, D5892), a failed command is `Lost` once (D5875). Goldens: `tests/conformance/msl/`.
- **Bundles** (C191): `scripts/macos-bundle.sh` makes `.app` (+ `--zip`, `--dmg`, `--icon`, `--url-scheme`, `--doc-type`,
  `--agent`, usage strings), ad-hoc signed; `--sign`, `--entitlements`, `--notarize` exist but are unrun (D5855, D5876).
- **CI:** `.github/workflows/macos-corpus.yml` (25 min, builds every `tests/selfhost/fixtures/link` fixture on Ubuntu with
  `neper-self`, runs them on macos-14; results `corpus-results-<arch>` artifact) and `macos-probe.yml` (one program, ~4 min).
  `tests/macos/run-corpus.sh` holds the skip list (Windows/Linux/wasm-only fixtures: `hfa_return`, `os_window_resize`,
  `wasm_net`, `wasm_release`, ...). A bootstrap fix keeps it building on Ubuntu 26.04 (`bootstrap/runtime.c` includes
  `<stdio.h>`).

## What is left

### 1. Needs a person at a real Mac (C192, score 0.2)

Run `tests/macos/manual/main.e` (never run; compiles for both architectures):

```
neper-self emit-executable tests/macos/manual/main.e . aarch64 macos manual     # x64 on an Intel Mac
./manual
```

It walks the checks one at a time and writes `~/neper-manual-results.txt`. It covers: Retina scale, tray click and menu, global
shortcut, open/save panels, a drop from Finder, clipboard to another app, a notice banner, Dock menu, an associated file opening,
the print panel range and copies, camera permission prompt, Touch ID, screen capture size, VoiceOver reading the tree and
pressing a button, **live resize while an edge is dragged**, and three **Metal facts**:

- does the real GPU preserve subnormals (the runners' paravirtual GPU flushes them, so Metal reports no `.DenormPreserve`; if a
  real Mac preserves them the capability could be claimed);
- does a single 1 GiB buffer read back (the runners' did not, so heaps are 256 MiB each, D5853);
- does `memory_order_seq_cst` / `atomic_thread_fence` compile (Metal 3.1 on the runners has neither, so any atomic stronger
  than relaxed keeps its kernel on the CPU, D5840).

Also unverified for the same reason: a real input method composing Japanese/Chinese/Korean and its candidate window, a person
dragging files into Finder (C195), a confirmed (OK) print dialog and a printer other than the PDF one (C188), the location
prompt (C186), a real Touch ID sheet (C187), the UNUserNotificationCenter path (post, replace, remove, `getDelivered`; the
runner never authorizes the center, C189).

Turn the answers into queue/decision updates; the three Metal answers decide whether three limits are the runners' or Metal's.

### 2. Needs an Apple Developer ID (C191, 0.75)

`scripts/macos-bundle.sh --sign "Developer ID Application: ..." [--entitlements FILE] --notarize PROFILE` is written to the tools'
documented command lines (`codesign --options runtime --timestamp`, `xcrun notarytool submit --keychain-profile PROFILE --wait`,
`stapler staple`, `spctl -a -vv`) and has never run against Apple's service. Done when a notarized bundle has been built and
opened on a clean Mac. Not done: a `neper` command that wraps the script (the script is the interface), dSYM handling.

### 3. Not built (decisions, not blocked on hardware)

- Session restore (`restart_register`) stays `Unsupported`: a launchd job with `KeepAlive` starts at once and a Mac restores a
  program's windows through its own saved state, which is not a command line to register (C195).
- Photos-library access (PHPicker is a SwiftUI view this library cannot present) (C187).
- Notification action buttons (`UNNotificationAction` categories and a delegate for responses) (C189).
- Real printing to a printer other than PDF (`NSPrintOperation` drawing into a view) is a design of its own (C188).
- Promised files (a file made at the drop's destination) (C195).
- A Metal buffer above 256 MiB (a single buffer; the device holds about 1 GiB as four heaps).

### 4. Metal gaps (C193, 0.95)

- Atomics stronger than relaxed and all 64-bit atomics: refused in the emitter (`Unsupported`), so the kernel runs on the CPU.
- 64-bit subgroup operations; `switch` and non-inlined helper calls in kernels (the SPIR-V emitter lacks them too).
- `.DenormPreserve` is not claimed; only `ftz` kernels run on Metal, others answer `Unsupported`.
- The `Lost` path (a command the device failed) is read, not run: no runner fault can be forced.
- The GPU still runs launches one after another; only the CPU's queueing overlaps.
- Metal has no `f64`. The SPIR-V writer's `f64` divide and square root (C095) are not macOS work but are unwritten and cannot
  be checked without an `f64` GPU.

## How to verify master

```
# macOS corpus (≈25 min): reads results from the run's artifacts
gh workflow run macos-corpus.yml --ref master          # use GH_TOKEN=$(gh auth token -u nebosa-company) per command
gh run download <id> -n corpus-results-aarch64         # and -x64; expect 0 FAIL lines and "BUNDLE PASS"

# one program on a Mac (≈4 min), exit code and what it wrote are in the log
gh workflow run macos-probe.yml --ref <branch> -f source=tests/selfhost/fixtures/link/macos_gpu_metal/src/main.e
```

Windows suite (≈70 min, from a clean `git worktree`, with a seed so the 5 GB bootstrap build is skipped):

```
$env:NEPER_SEED = '<a copy of build\windows\tests\selfhost\neper-self.exe>'
$env:Path = 'D:\tools\neper-pyenv\Scripts;' + $env:Path + ';C:\Program Files (x86)\Microsoft Visual Studio\Installer'
pwsh -NoProfile -File <worktree>\tests\selfhost\run.ps1
```

Linux suite (≈70 min): from PowerShell with the worktree as the current directory, `wsl -d Ubuntu-24.04 -- bash scripts/run-linux-suite.sh`
(the working directory matters: started from the shared checkout it rsyncs everything, including untracked files, for an hour).

## Traps found

- **Any change to `lib/e/os*.e` or `lib/e/gpu*.e` churns goldens** in `tests/conformance/tools`: the `e.os interface` hash (per host),
  `snapshot` hashes (`NEPER_REFRESH_GOLDENS=1` rewrites snapshot-only diffs), `explain_inline` records, and `uses*`/`batch`
  `indirect_calls` (those goldens are per host now). Run the suite in refresh mode once, review that only hash lines changed,
  commit. A new function in a platform file also changes the inlining records.
- **The Mac corpus builds every link fixture**: a Windows-only or Linux-only fixture must be listed in `tests/macos/run-corpus.sh`.
- **The shared tree `D:\repos\neper` holds peers' uncommitted edits**: verify from a clean worktree, commit explicit paths only,
  never `git add -A`/`git add .`, never `git checkout -- <dir>`. Use `GH_TOKEN=$(gh auth token -u nebosa-company)` per command.
- **Memory contention** on the Windows machine (a peer's bootstrap build, `qemu-system`, WPT runs) shows up as `fatal: access
  violation`, `WinError 1455` or "neper: out of memory"; each passes alone. Wait for a quiet window, or `wsl --shutdown`.
- **Bootstrap rules** (the C bootstrap builds `src/`): no `else if`, no `-=`, parenthesize `x == CONST {`, no top-level `var`,
  `MAX_USES` 384. `\x00` in a string literal must be the escape, not the byte (several tools mangle it; check with `cat -A`).
- **`neper fmt`** used to fail on `@import` lines of 100+ columns; fixed (attribute arguments are never wrapped).
- Reserved names in Neper: `target`, `error`, `shared`; module-level `str`/`f32` consts give a locationless `E-TYPE-9999`.
- Runners' paravirtual Metal device: a `ulong` cast to a device pointer reads nothing (so kernels use heap offsets), no
  DenormPreserve, single buffers above 256 MiB read back wrong, Metal 3.1 only.
- The Node runner's permission bits on Windows are `0o666` for a directory (completed to include execute in
  `lib/wasm/run-wasm-host.mjs`).

## Memory notes

`C:\Users\gaddl\.claude\projects\D--repos-neper\memory\neper-macos-shell-stream.md` and `MEMORY.md` carry the same lessons for a
future session of the same user; the file you are reading is the repository's copy.
