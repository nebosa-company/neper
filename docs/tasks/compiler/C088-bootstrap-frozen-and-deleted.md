# C088 — Bootstrap frozen and deleted

| field | value |
|---|---|
| category | compiler / Self-hosting |
| score | 0.00 of 1 |
| queue position | 29 of 48 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

From `docs/roadmap.md`, section **M2 — Self-hosting and `.em` modules**:

> Bootstrap compiler frozen, then deleted

**Done when:** `neper` compiles itself; GP-01 passes its applicable correctness,
failure-injection and deterministic-build cases; a one-function edit rebuilds in
milliseconds on Linux and Windows; clean, incremental, relocated, `-j 1`, every
supported worker count and perturbed-schedule builds produce byte-identical
deterministic artifacts; every M2 API matches source; and the language- and
tool-complete release gates below pass.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> bootstrap/neper.c still builds stage 0

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

Notes:

- Last of all: this item is score 0 by design. Freezing and deleting `bootstrap/neper.c` is only correct after every other compiler item no longer needs a stage-0 rebuild and the archived recovery revision (C087) is verified on a machine with no `neper` binary. Do not pick this item while any other compiler item is partial.

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
