# OpenGL group: handover

Written 2026-10-30. The design is `docs/opengl-plan.md`; the decisions are D5940–D5911 and D5914 in `docs/decisions.md` (D5913 is the f16 session's CPU work). The queue is `docs/work-queue.json`, group "OpenGL". This file holds only what neither of those says.

## What is left

Three items, none of which can be finished on the machine they were worked on.

| Item | Score | What it needs |
|---|---|---|
| C219 Android executable form | 0.9 | GPU compute (`e.gpu` on `.Gl`) on a device with GLES 3.1 or newer. The x86_64 Android 15 emulator stops at 3.0 whatever the GPU mode (`swiftshader_indirect`, `host`, `-feature GLESDynamicVersion`), and `-feature GuestAngle` does not boot. A real phone over `adb` is the way. Everything else in C219 passes, on x64 and arm64. |
| L176 CGL on macOS | 0 | A Mac. GL 4.1 core through CGL, presentation only (no compute). Nothing is written. `x.khronos.context` has `.linux.e` and `.windows.e` variants; this is a `.macos.e`. |
| T048 full suites | 0 | Verify only: run both full suites for the shared compiler change and report the tails. Neither suite had finished on the Windows/WSL machine, because of the Windows `run.ps1` stderr trip and WSL running short of memory. The user's memory index says both have finished since; check `neper-macos-shell-stream.md` and `neper-linux-suite-on-github.md` for how (a branch pushed to GitHub, `linux-suite.yml`). |

When T048 runs, it also covers the changes of this group that no single fixture owns: `src/glsl.e`, `src/link_elf*.e`, `src/main.e` (`emit-shared-library`), `lib/e/os*.e`, `lib/e/gpu.e`, `lib/e/ui/{window,app}.e`, `lib/e/gfx/scene.e`.

## Verified this stretch, and how far

- **On Windows (Intel Iris Xe) and Linux (WSL, Mesa llvmpipe):** every GL fixture, the 22 Vulkan gpu fixtures rerun on `.Gl` (`scripts/run-gl-fixtures.py`), the six window-opening `ui_*` fixtures through GL and GLES (`--ui`), the GLSL goldens, and the self-host fixed point (stage 2 equals stage 3 at each commit).
- **On the Android emulator:** `scripts/run-android.ps1` (x64 and aarch64) and the counter app (`scripts/build-apk.ps1`).
- **Not exercised:** a window really moving between monitors of different scales (L175 sends `WM_DPICHANGED` to itself); real phones; macOS; ES 3.1 on real hardware (only Mesa forced to 3.1 with `MESA_GLES_VERSION_OVERRIDE=3.1`).
- **The C bootstrap build** was not run for the f16 session's commit (D5913). `scripts/check-fixture.sh` builds with it, so anything it builds is covered; the full run is T048.

## Limits written into the code, in case they bite

- GLSL f64 `fma` is exact only while no intermediate step overflows or underflows (`dfma_source` in `src/glsl.e`); outside that it is plain `a * b + c`.
- f64 arithmetic on GL is the driver's (`+ - * /`, `sqrt`), checked on llvmpipe only. Intel cannot run an f64 kernel at all, because it flushes denormals and an `ftz` kernel holds no f64.
- Not written in GLSL: 64-bit integer to f16/bf16, a subgroup add/min/max of narrow floats, 64-bit atomics, a signed atomic min/max.
- `f32_fma` no longer flushes under `ftz` (D5914), matching the CPU's software `fma`. Division, square root and the hardware operations still flush.
- A workgroup smaller than one subgroup reads `gpu.subgroup_width` as its own size rounded up, not the hardware's.
- ANGLE on Windows (D3D11, ES 3.1) is still refused: it has neither `GL_EXT_gpu_shader5` nor `GL_OES_gpu_shader5`, so an f32 multiply-add could fuse.
- The Android counter app draws edge to edge, so the status bar overlaps its top. Insets are not applied.
- The Android emulator offers GLES 3.0 only, so `e.gpu` compute there reports no device and the fixtures print "nothing checked".

## Environment traps (this machine)

- **Do not use `build/windows/neper-try.exe`.** Other sessions' test runs (`slust_work`, `neper-w`) hold it open. Build your own: `build/windows/neper.exe build src/main.e --arena 1g --output build/windows/neper-gl.exe`, then `export NEPER_COMPILER=D:/repos/neper/build/windows/neper-gl.exe` (absolute, or the Python harness cannot find it) for `scripts/check-fixture.sh` and `scripts/run-gl-fixtures.py`.
- **Memory pressure** shows as "out of memory", "arena exhausted", or `E-LINK-9999 assembler or system linker failed`. Check the free commit (`Win32_OperatingSystem.FreeVirtualMemory`), close the Android emulator when idle, and retry.
- **`git checkout -- <file>` discards uncommitted edits to that file.** I lost an uncommitted `compute.e` change this way once. Use it only on `docs/tasks`.
- **Stale `.git/index.lock`:** wait; remove it only when it is more than a minute old and no git process is running.
- **Bootstrap rules in `src/`:** no top-level `var`, no `-=`, `x == CONST {` needs parentheses (`T_*` names count as constants), no `mem.eq[u8](...)` generic call in `src/`. `u32(x)` traps when `x` is out of range: mask first.
- **GLSL reserved words** that bit: `half`. Others to avoid in emitted code: `sample`, `input`, `output`, `fixed`.
- **A string literal with `\n` written through a heredoc** can end up with a real newline. Check with `grep -n '^")$'` after generating source that way.
- **`docs/tasks` churn:** after `render_tasks.py`, `git checkout -- docs/tasks` and delete new untracked files there.
- **Python** is `D:\tools\neper-pyenv\Scripts\python.exe`; Git Bash has none. Under Git Bash, `bash scripts/...` resolves to WSL's bash from PowerShell, so run the fixture scripts from the Bash tool.
- WSL has gcc, aarch64-linux-gnu-gcc, qemu-aarch64, and OpenJDK 17 (installed for `apksigner`). Windows has no Java. Android SDK and NDK are under `D:\tools\Android\Sdk` (AVD `mtg_studio_test`).

## Sessions

- **This session** (`local_c8376423-7034-4522-b4cf-903acb38a2e6`) did everything above except D5913. It is the one a Stop hook kept asking to finish "the whole group", which cannot happen until the three items above can be run.
- **[f16 and bf16 arithmetic in the CPU backend](#local_bc17c0e2-0a47-4815-a616-88956019c6f1)** (`local_bc17c0e2-0a47-4815-a616-88956019c6f1`, branch `ai/sharp-kalam-d399bd`, worktree `.claude/worktrees/neper-promo-video-e47c1a`) is finished. Its one commit (D5913) was merged here by fast-forward and C216 was built on it. It can be archived. It never ran the C bootstrap build or the full suites; both are part of T048.

## Git state when this was written

The work is committed on local `master`; the last OpenGL commits are `6cb1a7230` (C216), `749656c29`, `a56dd01fd`, `5046a3ce6`, `d19380e8e`, `964f1f1a1` and earlier. Peers have committed on top since. `master` is far ahead of `origin/master` and none of the group's commits is pushed. Follow the push rule in the memory index (`git log origin/master..HEAD` first: peers' unpushed commits wait for their own suites). The uncommitted changes in the working tree at the time (`docs/decisions.md`, `docs/library-fixtures.json`, `docs/tasks`, `lib/wasm/*`, `tests/wasm/*`) belong to other sessions, except that `docs/progress.html` and `docs/digest/*` are regenerated by whoever commits next.

One open numbering clash: another session's uncommitted `lib/wasm/window.js` cited `D5942`, which is this group's decision for GLES 3.2 devices. They should renumber.

## If a Mac is available (L176)

Read `neper-macos-shell-stream.md` (how to run both suites there, `NEPER_SEED`, the Metal backend in `src/msl.e`). Start from `lib/x/khronos/context.windows.e` for the shape of a context variant and from D5880 for what the Windows one does. Presentation only is the acceptance: GL 4.1 core through CGL, the same `x.khronos.present` path (`install()` in D5907), checked bit for bit by `x_khronos_gl_present`. Compute on macOS is Metal's (D5838), not GL's.

## If a phone is available (C219)

Install a GLES 3.1+ device on `adb`, then `scripts/run-android.ps1 -Arch aarch64 gpu_gl gpu_gl_exact gpu_gl_narrow` and `gpu_gl_subgroup` and read the tails. The x64 emulator-only fixtures print "nothing checked" without a compute device; on a phone they should run for real. `x.khronos.compute.install_es()` is what selects ES (GLES 3.2, or 3.1 with `GL_EXT_gpu_shader5` or `GL_OES_gpu_shader5`). Fold the result into C213, which the queue names for the real-phone check.
