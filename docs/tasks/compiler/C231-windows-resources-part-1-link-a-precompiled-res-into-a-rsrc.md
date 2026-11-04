# C231 — Windows resources part 1: link a precompiled .res into a .rsrc section; os.resource(kind,name)

| field | value |
|---|---|
| category | compiler / Back end |
| score | 0.00 of 1 |
| queue position | 120 of 219 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Opened 2026-11-03 from docs/roadmap.md:450 by the single-list audit; not previously a queue row. Acceptance: `project.yaml` names a `.res` per Windows target and the PE carries a byte-deterministic `.rsrc` directory (type, name, language order; icon and group-icon split; manifest at id 1). `os.resource` reads a custom RCDATA entry at run time. A Linux build records the resource as not applicable. Size L. Checked open: grep -i 'rsrc' in src/ and lib/: no hits; link_pe.e emits .text and .idata only; no os.resource in lib/e/os.windows.e.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `project.yaml`: `src/main.e`×8‡, `src/assets.e`×5, `lib/e/asset.e`×1, `src/graph.e`×1†
- `.res`: `src/check.e`×549‡, `src/codegen_x64.e`×83‡, `lib/e/web/dom_js.e`×76‡, `src/glsl.e`×76†, `src/spirv.e`×72‡, `lib/e/os.windows.e`×71‡, `lib/e/os.linux.e`×65‡, `src/codegen_a64.e`×63‡

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
