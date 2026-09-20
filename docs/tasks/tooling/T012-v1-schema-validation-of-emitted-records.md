# T012 — v1 schema validation of emitted records

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.90 of 1 |
| queue position | 44 of 51 (only position 1 is eligible for the next session; see README) |
| difficulty | low — rated for a small model; a whole checklist line per session is realistic |

## Definition of done

The contract is `docs/tooling.md`, section `## 9. Conformance and compatibility` (the closed v1 authority; `docs/tooling-v2-draft.md` is the non-normative successor draft).

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> `python scripts/validate_stream.py` validates every committed golden against docs/schemas/neper-v1.schema.json, and both suites run it (D250): the 23 `.jsonl` streams under tests/conformance -- one record per line, 895 of them -- and docs/modules.json as a whole document, so the three shapes anything currently emits are covered (`streamRecord`, `buildManifest`, `modulePlan`). The goldens are what the commands emit byte for byte, so validating them validates the emitters. A self-check rejects a header carrying an unregistered command before the corpus runs, so a validator that accepted everything could not pass; a machine without the `jsonschema` package prints a skip rather than failing the suite. The runner's source map (D264) is validated by both suites as a fourth shape; `packageManifest` is in the schema with nothing producing it yet

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

Notes:

- The remaining shape is `packageManifest`: it is in `docs/schemas/neper-v1.schema.json` with nothing producing it. It becomes producible with M6 pacman P0; until then the honest increment is a fixture document validated by `scripts/validate_stream.py` so the schema branch is exercised.

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D250` — The corpus is validated against the v1 schema, by both suites (`docs/decisions.md:4664`)
- `D264` — Source maps: the test runner writes one, and the compiler reads it back (`docs/decisions.md:5033`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `.jsonl`: `scripts/render_progress.py`×3, `scripts/validate_stream.py`×3, `benchmarks/metamorphic/reorder_parameters.py`×1, `scripts/check_stats_record.py`×1, `scripts/render_card.py`×1
- `jsonschema`: `scripts/validate_stream.py`×3

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
