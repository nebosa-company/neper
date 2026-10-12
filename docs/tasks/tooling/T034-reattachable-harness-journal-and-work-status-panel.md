# T034 — Reattachable harness journal and work-status panel

| field | value |
|---|---|
| category | tooling / Project tools |
| score | 0.00 of 1 |
| queue position | 70 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Planning only (D1812). Reference: JustCode src/perp.js. Work lifecycle stays in the harness, so closing the panel cannot stop work and reopening cannot lose it. Validate truncated/partial records, journal rotation, stale refresh replies and bounded large-journal reads. Harness discovery, binding validation and typed run/pause/message actions stay outside e.ui; the panel must not invent a second task scheduler. Follow-on (D1898): parallel harnesses also need a claim protocol â€” queue-item checkout plus D-number reservation â€” after two live collisions between sessions sharing one JSON queue. Use generic library view primitives without baking Perpetum or .harness schemas into the standard library.

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] a tooling panel composed from existing collection/overlay controls and L066's safe viewer, reading persistent journal/status through a supplied adapter
- [ ] timeline/detail/filter views, follow-tail, path-specific watcher refresh with bounded fallback, absent-harness handling and close/reopen reattachment

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
