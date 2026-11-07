# C273 — pole_placement solves a one-state plant: the polynomial scratch was two entries short

| field | value |
|---|---|
| category | library / Library |
| score | 1.00 of 1 |
| queue position | 224 of 224 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Landed. control_loop failed with exit 8, one of six pole_placement assertions; giving each a distinct code showed the 1x1 case, and splitting its call from its gain showed the call itself returning an error (87, not 88). pole_placement reserved scratch[5*nn+3*n .. 6*nn+4*n] for characteristic(), which needs 2*(n+1) entries: for n=1 that tail is nn+n=2 against 4 needed, so characteristic answered TooSmall and a one-state system was refused even though the controllability matrix [1.0] is invertible and the gain is 0.5. The same declared budget, 5*nn+5*n+2, was also below the nn+n tail for n >= 3 and only worked because the caller's scratch happened to be larger. Fixed with a computed requirement: poly_needed is max(nn+n, 2*(n+1)) and the guard is poly_base + poly_needed, so the polynomial is sized by what it actually slices. Verified: control_loop exits 0 and prints control ok, and the 2-pole, 3-pole and uncontrollable cases it already covered still pass. Pre-existing: the untouched Nov 6 compiler fails the same way.

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
