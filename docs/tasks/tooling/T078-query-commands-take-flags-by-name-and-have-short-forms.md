# T078 — Query commands take flags by name and have short forms

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.00 of 1 |
| queue position | 236 of 315 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Opened from the 2026-11-12 compiler review. Acceptance: a tools conformance case runs `context-file` with `--symbol` before and after `--json` and gets identical streams; an unknown flag exits 2 with E-CLI naming it; `neper context --symbol m.f` equals the long form. Card re-rendered, with `docs/llm-neper-card.src.md:189` ("past 256 locals silently") corrected to the bootstrap's reported 400. Notes: docs/compiler-hardening-plan.md.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `context-file`: `scripts/coverage-run.sh`×12, `src/tool.e`×8‡, `src/main.e`×6‡, `benchmarks/baseline/context.py`×4, `src/check.e`×4‡, `scripts/check_agent_routes.py`×3, `benchmarks/baseline/session.py`×2, `scripts/measure_tooling_latency.py`×2

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
