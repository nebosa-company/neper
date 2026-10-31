# C193 — macOS GPU: a Metal backend for e.gpu (the Vulkan fixtures cannot run on a Mac)

| field | value |
|---|---|
| category | compiler / macOS |
| score | 0.95 of 1 |
| queue position | 10 of 106 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Phase 1 done 2026-10-25 (D5231): e.gpu.metal, the runtime alone. Phase 2 2026-10-26: src/msl.e, the MSL emitter (D5838; kernel as a switch state machine over heap offsets that reconverges by lowest block, precise::divide/sqrt, fast math off, D5840 32-bit relaxed atomics, D5852 subgroups) and e.gpu's Metal backend (D5839): on a macOS target a kernel's K$spirv carries MSL, Backend.Metal opens a device with a 256 MiB shared heap, buffers are heap ranges, launch_metal runs the SPIR-V launch ABI over it, faults come back through the fault block. Verified on Metal on aarch64 and x64: macos_metal_emitted, macos_metal_exact, macos_gpu_metal, macos_metal_atomics, macos_metal_subgroup (every word equal to the CPU backend's); the emitter's saxpy, loops and exact float are pinned in tests/conformance/msl; the full macOS corpus passes (1130/1130 on both). D5853: a heap larger than 256 MiB read back wrong on the runners. D5892: up to four launches in flight with their own fault blocks (the CPU queues ahead of the GPU; the GPU still runs them in order). D5878: up to four 256 MiB heaps, about 1 GiB of buffers (a single buffer still under 256 MiB). D5875: gpu.launch on Metal commits without waiting (the next call into the device finishes it and reports the fault), so the CPU can work while the GPU runs. Remaining: stronger atomic orders (Metal 3.1 has no fence), 64-bit atomics and subgroup operations on 64-bit values, switch and helper calls (SPIR-V has neither), the Windows and Linux suites for the shared compiler change.

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
