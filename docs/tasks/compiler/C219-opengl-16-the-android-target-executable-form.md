# C219 — OpenGL 16: the Android target, executable form

| field | value |
|---|---|
| category | compiler / OpenGL |
| score | 0.90 of 1 |
| queue position | 105 of 106 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Done 2026-10-27 (D5896, D5900): emit-executable ... x64 android and aarch64 android write the Linux image typed ET_DYN for /system/bin/linker64, with Bionic library names (libc.so) plus libdl.so and liblog.so; arm64 Android images always carry a dynamic segment, and arm64 atomics are LDAXR/STLXR loops (ARMv8.0). Android is linux to every module and variant, so no os.android.e was needed (neither Bionic nor SELinux refused anything run so far). scripts/run-android.ps1 [-Arch aarch64] runs hello, advanced, gpu_cpu, gpu_fault_bounds, x_khronos_gl_load, x_khronos_gl_headless, atomic_ops, atomic_threads and channel_threads on the SDK's Android 15 x86_64 emulator for both architectures, all passing, with GLES 3.0 drawing and reading back. Remaining: e.gpu compute on a device with GLES 3.1+. The emulator stops at 3.0 on this host: SwiftShader, -gpu host on the Iris Xe (draws there too) and -feature GLESDynamicVersion all report ro.opengles.version 196608, and -feature GuestAngle does not boot, so this needs a real phone. Design docs/opengl-plan.md, D5884. Needs T047. Acceptance: --target android-x64 and android-a64 emit a PIE ELF for /system/bin/linker64 with DT_NEEDED libc.so, libdl.so and liblog.so; os.android.e is os.linux.e without what Bionic and SELinux refuse; the executable runs under adb shell on the x86_64 emulator, and T047's fixtures pass there on GLES.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Verification

- Every named fixture above must keep passing; add one fixture per checklist line (README §Fixture template).
- Both suites: `tests/selfhost/run.ps1` on Windows, `tests/selfhost/run.sh` on Linux through WSL (README §Build and verify).
- `python scripts/render_progress.py` must run clean after the queue edit.

## Session procedure

1. Read `docs/tasks/README.md` once: model limits, repository traps, the build and
   verification commands, the fixture template.
2. Pick **one** line of the remaining checklist above. Do not attempt the whole item.
3. Read the anchors listed here by line range (`git grep -n IDENT FILE`, then
   `sed -n 'A,Bp' FILE`), never a whole file over 120 KB.
4. Write the change, the fixture, and both runner entries (`tests/selfhost/run.ps1`
   and `run.sh`) in the same increment.
5. Build and run both suites (README). A green C-bootstrap build proves nothing on its
   own; the self-hosted stage must build and stage 2 must equal stage 3.
6. Append `## D<n> — <title>` to `docs/decisions.md` for any design choice.
7. Update this item's `score` and `evidence` in `docs/work-queue.json`: append the new sentence to the evidence and keep the `Not yet:` clause truthful. Run `python scripts/render_progress.py` and commit only the touched paths.
