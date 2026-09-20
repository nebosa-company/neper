# C093 — M3-05: device selection: devices, DeviceInfo/DeviceKind/DeviceKey, open_id, info

| field | value |
|---|---|
| category | compiler / Back end |
| score | 0.40 of 1 |
| queue position | 32 of 55 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> `devices` answers the bounded snapshot with the CPU device (`supported`, no stable key, capabilities copied into the caller's arena), `open` takes `.Cpu` index 0 and refuses other indices with `NoDevice` and other backends with `Unsupported`, `open_id` refuses a CPU key with `NoDevice` since the CPU has none, `info` copies the opening-time descriptor (D778)

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] Vulkan and CUDA enumeration, stable keys and `AmbiguousDevice`, memory capacity

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D778` — M3 opens with `e.gpu` on the CPU backend and `gpu.launch` as the third pack intrinsic (`docs/decisions.md:14678`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `devices`: `lib/e/gpu.e`×7, `scripts/check_gpu_contracts.py`×1
- `.Cpu`: `lib/e/gpu.e`×6
- `NoDevice`: `lib/e/gpu.e`×3
- `Unsupported`: `src/codegen_x64.e`×104‡, `src/check.e`×72‡, `src/lower.e`×53‡, `lib/e/crypto/x509.e`×17, `lib/e/net/tls.e`×14†, `lib/e/fmt/jpeg.e`×12†, `lib/e/os.windows.e`×10‡, `lib/e/net/http.e`×9†
- `open_id`: `lib/e/gpu.e`×1
- `AmbiguousDevice`: `lib/e/gpu.e`×1

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
