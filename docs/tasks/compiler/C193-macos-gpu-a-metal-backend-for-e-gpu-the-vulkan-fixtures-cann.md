# C193 — macOS GPU: a Metal backend for e.gpu (the Vulkan fixtures cannot run on a Mac)

| field | value |
|---|---|
| category | compiler / macOS |
| score | 0.25 of 1 |
| queue position | 11 of 103 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Phase 1 done 2026-10-25 (D5231): e.gpu.metal, the runtime alone, as e.gpu.vulkan was before e.gpu used it: available, open, name, buffer (MTLResourceStorageModeShared, the mapping is the CPU's view), compile (MSL text compiled at run time with newLibraryWithSource, an entry function, a compute pipeline), dispatch (thread groups, optional threadgroup memory, the buffers kept resident, committed and waited on) and the matching free, destroy and close. macos_metal_raw (corpus 1110 on aarch64 and x64) runs saxpy over 1024 floats, a reversal through threadgroup memory and a barrier, and a kernel that does not compile (CompileFailed, the device keeps working). Findings on the macos-14 runners: Metal works on their paravirtual GPU ("Apple Paravirtual device") on both architectures, MSL compiles at run time, a kernel may cast a ulong to a device pointer in source (it compiles), but a kernel that did so read and wrote nothing (the buffer's gpuAddress is not usable on the paravirtual device even with useResource), so the launch ABI cannot hand a kernel physical addresses as the SPIR-V path does. The way through is one big shared heap buffer per device, buffers carved from it, addresses being offsets into it that the kernel adds to the heap's pointer (a plain buffer binding, which does work). Phase 2, not started: an MSL emitter in the compiler beside src/spirv.e (141 KB, 118 functions: structured control flow from the NIR graph, device loads and stores through the heap, atomics, barriers, shared memory, builtins, the checked-build fault buffer), a target the compiler can write kernels for on macOS (embedded in the program as the module text the way SPIR-V is), and e.gpu's Metal backend (devices, buffers carved from the heap, launch_device for Metal beside the Vulkan one, faults, queues). The earlier MoltenVK route stays unshippable on the runners (MoltenVK dies in the paravirtual device). The compiler's declaration capacity is not the blocker (D5230).

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
