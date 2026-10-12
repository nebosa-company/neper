# L067 — Refresh-stable explorer tree adapter over e.ui.collection

| field | value |
|---|---|
| category | library / UI |
| score | 0.00 of 1 |
| queue position | 68 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Planning only (D1812). Reference: JustCode src/filetree.js, src/explorer.js and their unit cases. e.ui.collection already has TreeSource stable keys, expanded/selected key lists and virtual tree views; e.text.collate already offers numeric ordering. Reuse them for a generic file-tree adapter with folders-first natural ordering and expansion/selection/scroll retention across refresh, rename and removal. Preserve case-sensitive host distinctions; never copy JustCode's unconditional path lowercasing to Linux. Enumeration, path resolution, mutation authorization and recursive-copy containment belong to host filesystem services. No second tree widget or bespoke natural-sort implementation. P7-17's explorer hook consumes this adapter.

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] integrated filesystem snapshots, collision-safe stable identities, loading/error rows, explicit locale comparator and path-identity policy
- [ ] deterministic refresh/rename/delete/large-tree fixtures

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
