# T041 — T2.2 edit and test evidence: plans, contracts, structured tests

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.15 of 1 |
| queue position | 139 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Planning only (D1954). T2.2 slice missing: transactional semantic plans, structured tests, change contracts, flaky-test semantics, runtime failures and compatibility diffs. Terminal state without T2.3 trust evidence is incomplete, never verified. Pickup immediately after the chart cluster. FIRST SLICE (D2320): `test-file`/`test-project ... --json --compact` leaves passing `test` records out of the v1 stream, summary unchanged; conformance row in both suites. NOT DONE: test plans with identities and selection reasons, executed/cached/not-run evidence, structured expected/actual, setup/cancellation outcomes, output artifacts, change contract, flaky semantics, runtime failures, compatibility diff. SECOND SLICE (D2321): `test-impact-file ... --why` adds `via`, the reason a test was selected; goldens impact_why and impact_local_why in both suites. THIRD SLICE (D2322): `--retries N` re-runs a non-passing test and reports `test_retry` for every test that ran more than once (H39); flaky fixture flaky_test.e, both suites. Still open: executed/cached/not-run evidence, structured expected/actual values, setup/cancellation outcomes, output artifacts, change contract (H35), runtime failures (H41), compatibility diff (H42). SUITE (run 18, seeded Windows, static gate and live-API assertion excluded): the --compact, --why and --retries rows, the flaky fixture and the capabilities golden all pass.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `test-file`: `src/main.e`×13‡, `scripts/render_card.py`×1, `src/tool.e`×1‡, `tests/conformance/tools/capabilities.expected.jsonl`×1
- `test_retry`: `src/main.e`×1‡, `src/tool.e`×1‡

## Verification

- Every named fixture above must keep passing; add one fixture per checklist line (README §Fixture template).
- Both suites: `tests/selfhost/run.ps1` on Windows, `tests/selfhost/run.sh` on Linux through WSL (README §Build and verify).
- Every emitted record must validate: `python scripts/validate_stream.py`.
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
