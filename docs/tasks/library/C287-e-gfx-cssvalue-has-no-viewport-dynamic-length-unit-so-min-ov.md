# C287 — e.gfx.cssvalue has no viewport-dynamic length unit, so min() over dvh does not resolve

| field | value |
|---|---|
| category | library / Library |
| score | 0.00 of 1 |
| queue position | 1 of 224 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Open. With C286 landed gfx_cssvalue emits and runs, and stops on `min(abs(360in), min(16pt, 100dvh))`. Its reference answer is {v:0, u:"px", o:0, p:null} -- a plain zero length whose to_px resolution is null -- while the fixture's check fails, and the likeliest reason is that css.parse_length answers not-good because LengthUnit is {Px, Pt, Em, Rem, Ex, Percent, Vw, Vh, Vmin, Vmax, Ch, Lh} with no viewport-dynamic unit, so `100dvh` is not a length at all. Whether the reference reaches 0 by treating an unknown basis as zero (so min(16pt, 0) is 0 and min(abs(360in), 0) is 0) or by clamping is the thing to establish from Vaper's Dart parser before choosing between adding the dvh family to the enum and matching the zero-basis reading. Everything after this case is unmeasured, since the fixture stops at the first mismatch. Acceptance: gfx_cssvalue runs to completion, and the fixture's remaining cases agree with the reference.

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
