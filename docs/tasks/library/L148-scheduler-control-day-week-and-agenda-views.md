# L148 — Scheduler control: day, week and agenda views

| field | value |
|---|---|
| category | library / UI |
| score | 0.95 of 1 |
| queue position | 50 of 106 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Planning only (D1890). DevExpress-style scheduler parity missing (pickers exist, no appointment surface): day/week/agenda views with drag-create and recurrence display over e.time.calendar plus L103 rules. Fixtures for layout, overlap columns and accessibility roles. PART (D2882): e.ui.schedule day, week and agenda layouts with recurrence over e.time.recur, all-day band, overlap lanes, hit, slot_at, drag_range and an accessible tree (18 checks vs datetime/dateutil). NOT DONE: month view, multi-day all-day bars, zones and DST, moving appointments, locale names, painting and pointer/keyboard model. PART (D3303): e.ui.schedule month view (build_month, +N more, hit_month, month_move), all_day_bars, move_target, resize_target, focus_next, localized names; ui_schedule_month vs an independent datetime/calendar model over three months and German labels. Missing: zones and DST, painting and pointer dispatch, multi-day bars in the month view, recurring-series moves. PART (D3602): zoned and DST views, multi-day month bars with hit testing, recurring-series moves with refusals; ui_schedule_zones vs zoneinfo, dateutil and a bar model. Missing: painting and pointer dispatch, single-occurrence exceptions. PART (D4606): EXDATE exceptions, cancel_occurrence, move_occurrence, move_series shifting EXDATEs; ui_schedule_exceptions 8 views vs dateutil plus 14 op checks. Missing: painting and pointer dispatch.

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
