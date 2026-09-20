# T016 — Conformance corpus accept/reject/format/tokens/parse/tools

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.90 of 1 |
| queue position | 44 of 47 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

The contract is `docs/tooling.md`, section `## 9. Conformance and compatibility` (the closed v1 authority; `docs/tooling-v2-draft.md` is the non-normative successor draft).

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> All six corpus roots of tooling.md section 9 exist with byte-exact expected output the suites compare on both platforms: tokens/ and parse/ (D227), accept/ and reject/ (D228), tools/ -- one `info` stream per host (D229), a build and a rejected build (D230), a program run (D231) and a trapping one (D253), a symbol index (D232, D251), a disassembly per host (D233), a canonical format and a `--check` rejection (D234, D244), a build manifest per host (D238), a test run and a timed-out one (D240, D246) -- and format/ (D255): a non-canonical source beside what `fmt` makes of it, the canonical side also passing `--check`. Every `.jsonl` golden validates against the v1 schema (D250). Every root has at least two fixtures (D284: accept/aggregate -- structs, an enum, a generic and a switch -- and format/types, whose first draft found `fmt` writing `case.Red` and mis-indenting `case` labels). Every registered code the compiler can raise today has a reject fixture pinning its stream (D297): ten more -- E-MODULE-0001/0002/9999 (the last two as two-module projects under reject/), E-NAME-0002/0003, E-ERROR-9999, E-MEM-9999, E-TYPE-0001/0003/9999 -- beside the six already pinned, leaving E-LINK-9999 (an error-hash collision no small fixture produces) and the codes whose subjects do not yet diagnose (E-GPU, E-SAFETY, E-TOOL-9999). reject/nesting pins section 3's 128-level nesting bound (D341), which a mutation-and-depth fuzzer (benchmarks/fuzz) guards beside the artifact readers

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] the generated-code benchmark report section 9 asks for

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D227` — `tokens --json` and `parse --json`, and the first of the conformance corpus (`docs/decisions.md:4120`)
- `D228` — `check-file --json`, through one diagnostic emitter (`docs/decisions.md:4141`)
- `D229` — `info --json` is the capability query, pinned per host (`docs/decisions.md:4158`)
- `D230` — `emit-executable --json` is the build stream (`docs/decisions.md:4173`)
- `D231` — `run --json` builds then launches, capturing the whole output (`docs/decisions.md:4189`)
- `D232` — `index --json` names the module and its declarations (`docs/decisions.md:4203`)
- `D233` — `dis --json` lists each function's bytes (`docs/decisions.md:4216`)
- `D234` — `fmt --json` emits the canonical layout (`docs/decisions.md:4228`)
- `D238` — `build-manifest --json` and a SHA-256 in the compiler (`docs/decisions.md:4320`)
- `D240` — `test --json` runs each @test in its own process (`docs/decisions.md:4372`)
- `D244` — `fmt --check` reports E-FORMAT-0001 (`docs/decisions.md:4492`)
- `D246` — A test that outruns its deadline is ended from inside (`docs/decisions.md:4525`)
- `D250` — The corpus is validated against the v1 schema, by both suites (`docs/decisions.md:4664`)
- `D251` — A symbol carries its signature, its attributes and its `///` documentation (`docs/decisions.md:4729`)
- `D253` — A trap's record is read back as the `trap` payload, under `run` and `test` (`docs/decisions.md:4761`)
- `D255` — The format corpus, and a space inside a brace pair (`docs/decisions.md:4841`)
- `D284` — A second fixture per corpus root, and what writing them found (`docs/decisions.md:5600`)
- `D297` — A reject fixture for every code the compiler raises (`docs/decisions.md:5852`)
- `D341` — Bounded malformed input: the fuzzer, the nesting bound, and the link's hash scratch (`docs/decisions.md:7301`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `.jsonl`: `scripts/render_progress.py`×3, `scripts/validate_stream.py`×3, `benchmarks/metamorphic/reorder_parameters.py`×1, `scripts/check_stats_record.py`×1, `scripts/render_card.py`×1

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
