# T056 — Rename the prose name for the standard library to `e.lib` across the docs

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.00 of 1 |
| queue position | 119 of 219 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Opened 2026-11-03 from docs/roadmap.md:444 by the single-list audit; not previously a queue row. Acceptance: spec section 1 and 2, modules.md, module-apis.md, tooling.md, README.md and render_progress.py row text use `e.lib` for the lib/e modules, with a D-row recording the term. A grep for 'stdlib', 'core library' and 'standard library' in those files finds none outside quotes. Size S. Checked open: grep 'e\.lib' in src/ hits only unrelated identifiers; docs still say 'standard library'/'stdlib'.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `e.lib`: `src/wasm.e`×6, `src/nir.e`×5†, `scripts/render_progress.py`×3, `src/em.e`×3‡, `src/lower.e`×2‡, `src/em_link.e`×1†, `src/wasm_code.e`×1†

## Verification

- Every named fixture above must keep passing; add one fixture per checklist line (README §Fixture template).
- Both suites: `tests/selfhost/run.ps1` on Windows, `tests/selfhost/run.sh` on Linux through WSL (README §Build and verify).
- Every emitted record must validate: `python scripts/validate_stream.py`.
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
