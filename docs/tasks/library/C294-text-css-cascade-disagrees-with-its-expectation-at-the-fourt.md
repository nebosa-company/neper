# C294 — text_css_cascade disagrees with its expectation at the fourth element of a table case

| field | value |
|---|---|
| category | library / Library |
| score | 0.00 of 1 |
| queue position | 1 of 225 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Open, and pre-existing: it is the fixture after gfx_cssvalue in the suite, so no run had reached it before. It answers exit 1 with 'FAIL element index 4 tag table' followed by 'FAIL case' -- the computed cascade for the fifth element of some vector (a table) does not match the case's expectation. Not caused by the selector or cssvalue work: rebuilding it against lib/e/fmt/css/selector.e from before the attribute-lowercase and leading-combinator changes, and against lib/e/gfx/cssvalue.e from before the viewport-unit, transform and colour changes, both still answer exit 1 with the same message, and reversing those changes one at a time on top of HEAD changes nothing. The fixture prints one 'rule <matched> <condition-text>' line per rule it walked, and the run reaches 'rule scoped-no cont-yes' before failing, so the case in question is among the early vectors -- vectors_0 has a body with bgcolor and color attributes and a table beneath it, which is the shape the message describes. Acceptance: text_css_cascade exits 0, and the cascade of the table case agrees with the expectation.

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
