# T023 — Generated-code benchmark corpus

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.50 of 1 |
| queue position | 49 of 49 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

A committed corpus of generated-code benchmarks (`benchmarks/llm_edit`, spec §1 NFRs, roadmap 'Cross-milestone verification': GP-09 and the LLM thresholds — 95% parse first pass, 90% type-check first pass, zero unrelated formatted diff, 95% one-turn repairs) with a runner and a report section that `tooling.md` §9 asks for.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> benchmarks/llm_edit

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

Notes:

- Score 0.5 with only a path as evidence. Read `benchmarks/llm_edit` and `tests/test_llm_edit_benchmark.py` first; the missing half is the report `tooling.md` §9 names and its runner entry in both suites.

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
