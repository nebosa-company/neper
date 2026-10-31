# C095 — M3-07: GPU floating point: no contraction, math.fma only, denormals, ftz

| field | value |
|---|---|
| category | compiler / Back end |
| score | 0.88 of 1 |
| queue position | 17 of 106 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

>  PART (D4203): DenormPreserve/DenormFlushToZero over every reachable function, ftz kernels run under FTZ/DAZ on the CPU (stmxcsr/ldmxcsr; aarch64 FPCR hand-derived, not run), math.fma as Fma/NoContraction; gpu_float_modes passes on the CPU and the Intel Xe device. Missing: f64 in the SPIR-V writer, NVIDIA DenormPreserve, ftz+f64 on the CPU. PART (D4701): f64 in the SPIR-V writer (Float64, NoContraction FAdd/FSub/FMul, compares, conversions, fma); float64.spv hash-checked, gpu_f64 bit-exact on the CPU; no device here runs f64 (Intel Xe lacks Float64, the RTX 3080 fails the denormal gate). Missing: f64 div/sqrt, NVIDIA DenormPreserve, ftz+f64 on the CPU.

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
