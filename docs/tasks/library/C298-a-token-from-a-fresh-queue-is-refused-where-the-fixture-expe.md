# C298 — a token from a fresh queue is refused where the fixture expects it to name nothing done

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

> Open, and pre-existing: gpu_cpu is the fixture after net_ftp in the suite. It exits 90 at its first token check; splitting the four conditions shows done() itself answering an error. gpu.done goes through token_queue, which refuses `token_value.serial == 0u64` outright -- its comment says 'serials start at 1, so 0 or anything past the queue's latest serial names no work' -- while gpu.token on a queue that has not submitted anything returns exactly serial 0, which the fixture asserts (`before.serial != 0` is its own earlier failure at exit 13) before asking that done, wait and wait_for all answer cleanly. So the two disagree about whether the token a fresh queue hands out names anything, and neither the fixture nor the module has changed: the module's rule and its own token() are what conflict. The choice is whether token_queue accepts serial 0 when the queue's own serial is 0 (a dependency on nothing, which every wait should find already satisfied), or whether token() should hand out a serial that names the next submission, in which case the fixture's expectation needs rewriting. Acceptance: gpu_cpu exits 0 and prints gpu cpu ok.

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
