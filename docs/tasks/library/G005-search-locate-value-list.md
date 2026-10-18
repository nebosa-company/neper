# G005 — search / locate / value list

| field | value |
|---|---|
| category | library / Library |
| score | 0.70 of 1 |
| queue position | 77 of 85 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Proposed by docs/grid.md section 9 (MTG Studio v3 migration grid, 150k records, DevExpress TcxGrid parity; measured Delphi baselines in section 6.1). Design: grid.md section 5, mapping and acceptance rows: section 7. Acceptance: begins-with and within; next/prev with wrap; value list = dictionary. PART (D3909): lib/e/data/tablesearch.e: find (begins/within, fold or exact, forward/backward, wrap) over any display order with a per-entry verdict on dictionary columns, value_list (dictionary counts in fold order, merged case variants, nulls, filtered rows only); tests/selfhost/fixtures/link/data_tablesearch against brute force, four mutations caught; measured full-scan miss 2.3 ms (dictionary) / 8.4 ms (heap string), value list 1.4 ms at 150,000 rows. NOT DONE: search on numeric display text, binary search of a sorted dictionary, match highlighting, find-panel syntax, a Linux run.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Existing fixtures

- `tests/selfhost/fixtures/link/data_tablesearch`

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
