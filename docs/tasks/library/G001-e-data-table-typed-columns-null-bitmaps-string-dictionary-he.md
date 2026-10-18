# G001 — e.data.table: typed columns, null bitmaps, string dictionary + heap, bulk load, journal

| field | value |
|---|---|
| category | library / Library |
| score | 0.70 of 1 |
| queue position | 73 of 85 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Proposed by docs/grid.md section 9 (MTG Studio v3 migration grid, 150k records, DevExpress TcxGrid parity; measured Delphi baselines in section 6.1). Design: grid.md section 5, mapping and acceptance rows: section 7. Acceptance: 150k × 24 load fixture; typed get/set round-trip; dictionary rank/fold correct; memory ≤ budget. PART (D3905): lib/e/data/table.e: typed I32/I64/F64/Bool columns, null bitmaps, Str heap and Dict (deduplicated, fold-order ranks via e.algo.sort), bulk load, tombstones, per-column version journal; tests/selfhost/fixtures/link/data_table: 150,000 x 24 loaded, every cell read back, ranks vs compare_fold, versions, capacity errors, 41 MiB (bound 45). NOT DONE: row compaction, a boxed Value accessor, u16 dictionary ids, the e.db cursor adapter, a Linux run, and the load/rank timings against the design targets (load <= 250 ms).

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Existing fixtures

- `tests/selfhost/fixtures/link/data_table`

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
