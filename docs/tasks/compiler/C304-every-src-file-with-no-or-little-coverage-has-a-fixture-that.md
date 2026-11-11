# C304 — every src file with no or little coverage has a fixture that reaches it

| field | value |
|---|---|
| category | compiler / Hardening |
| score | 0.00 of 1 |
| queue position | 225 of 226 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Open. In the C303 baseline (2026-11-11, 3,702 runs, 65.5%) glsl.e, disasm_x64.e, object_elf.e, wasm_map.e and link_image_a64.e are 0%, wasm_threads.e 10%, tool.e 12.9%, emit_a64.e 25%, main.e 32%, platform.e 33%, binary.e 48%, msl.e 54%, emit_x64.e 56%. The --gpu glsl fixtures sampled never reached glsl.e, so find the entry point for each (a command, a flag, a target such as aarch64 none or neperos) and add a fixture or conformance case that fails if it breaks. Cover the neper test, run, eval, index and fmt commands and the CLI error paths in main.e and tool.e.

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
