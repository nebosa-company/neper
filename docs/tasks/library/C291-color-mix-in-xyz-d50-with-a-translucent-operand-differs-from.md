# C291 — color-mix in xyz-d50 with a translucent operand differs from the reference

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

> Open. With C288-C290 landed gfx_cssvalue runs to its twenty-fifth vector chunk and stops on `color-mix(in xyz-d50, #80808080 100%, black 30%)`, whose reference answer is 2641457521 -- ARGB 9D 71 71 71, a neutral grey. The alpha agrees with what the shared formula gives: 0.502*0.769 + 1*0.231 = 0.617, which is 0x9D, and the weights are the percentages normalised over their 130 total. So the difference is in the colour channels, and the places to look are to_space_coords/from_space_coords for xyz-d50 (whether the conversion and its white point match the reference's) and the premultiplied blend in mix_in_space, which divides by the summed alpha and is otherwise the textbook formula. Everything after this chunk is unmeasured, since the fixture stops at the first mismatch. Acceptance: gfx_cssvalue runs to completion and its remaining cases agree with the reference.

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
