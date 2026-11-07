# C265 — a syntax error exits with its diagnostic: the error path must not consume the machine

| field | value |
|---|---|
| category | compiler / Hardening |
| score | 0.00 of 1 |
| queue position | 220 of 224 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Found while porting x.duckdb.duckdb to DuckDB v2 and trying to build the Linux self-hosted compiler: a parse failure in lib/e/str.e (mem.bitcast[f32], syntax the September bootstrap does not know) did not report and exit. Measured in a freshly restarted 5GB WSL instance with nothing else running, RSS went 3148 kB at t=3s to 4352956 kB at t=6s, then 4550256 kB at t=9s, with MemAvailable down to 15MB, the process in D state, and exit code 1 only after the allocator had exhausted the VM. The diagnostic printed correctly (E-SYNTAX-9999 at four sites); the defect is that emitting it retained 4.5GB and stalled on swap for minutes instead of returning. Acceptance: a program with a syntax error reports every diagnostic it currently reports and exits 1 with peak RSS within a small fixed multiple of the source size (measured, and stated in the fixture); the same failure on Windows and Linux; a fixture that parses a file with many errors and asserts the exit code and a bounded peak; and no error path allocates per-diagnostic state that is never released.

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
