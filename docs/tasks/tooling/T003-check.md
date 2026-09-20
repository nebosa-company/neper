# T003 — check

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.87 of 1 |
| queue position | 37 of 53 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

The contract is `docs/tooling.md`, section `## 7. Test, build and command results` (the closed v1 authority; `docs/tooling-v2-draft.md` is the non-normative successor draft).

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> `check-file PATH ROOT ARCH OS --json` (D228): the header, a `diagnostic` record for every error the front end reports -- lexical, syntax, module, resolution and checking, each with its registered code, message and span -- an unreadable operand as a location-free E-CLI-9999 with exit 2, the `result` with the exit status, and nothing on stderr; every diagnostic printer goes through one emitter that writes the human line or the record. tests/conformance/accept and reject pin five streams byte for byte on both platforms. `check-project DIR ROOT ARCH OS WORKDIR --json` checks every module under DIR/src (D262): the tree walked in byte order so the stream is the same on every filesystem, each module checked in its own `check-file --json --path REL` process so its identity is its path under src -- `nested/deep.e`, not a basename -- and the children's records merged into one stream with one header and one result carrying the diagnostic and module counts; tests/conformance/tools/check_project pins three modules, two with an error. `neper check FILE` is the short spelling (D276) and `neper check` with no operand checks the project the current directory is in as `check-project`, working under its `.neper/debug/check/` (D294), as does `neper test` as `test-project`; both suites run each from inside a corpus project and require the project form's golden. `check-file - ... --json --path REL` reads the module from stdin under the `--path` identity (D490), the reject corpus's golden byte for byte on both hosts

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] notes
- [ ] a `project-src` root in the identity
- [ ] a module outside src

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D228` — `check-file --json`, through one diagnostic emitter (`docs/decisions.md:4141`)
- `D262` — `check-project` checks every module under a project, one stream (`docs/decisions.md:4971`)
- `D276` — Spec section 2's spellings, as a front door onto the positional forms (`docs/decisions.md:5412`)
- `D294` — `neper check` and `neper test` with no operand are the project (`docs/decisions.md:5774`)
- `D490` — `-` on `check-file` (`docs/decisions.md:10542`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `nested/deep.e`: `src/main.e`×1‡, `tests/conformance/tools/check_project.expected.jsonl`×1, `tests/conformance/tools/check_project/src/nested/deep.e`×1, `tests/conformance/tools/impact.expected.jsonl`×1, `tests/conformance/tools/impact_local.expected.jsonl`×1, `tests/conformance/tools/test_project.expected.jsonl`×1, `tests/conformance/tools/test_project/src/nested/deep.e`×1
- `check-project`: `src/main.e`×7‡, `tests/conformance/tools/check_project/src/main.e`×1
- `test-project`: `src/main.e`×9‡, `tests/conformance/tools/test_project/src/main.e`×1
- `project-src`: `tests/conformance/tools/plan_rename_type.x64-linux.expected.jsonl`×13, `tests/conformance/tools/plan_rename_type.x64-windows.expected.jsonl`×13, `tests/conformance/tools/uses_type.expected.jsonl`×9, `src/main.e`×8‡, `tests/conformance/tools/plan_rename_error.x64-linux.expected.jsonl`×6, `tests/conformance/tools/plan_rename_error.x64-windows.expected.jsonl`×6, `tests/conformance/tools/catalog_verified.x64-linux.expected.jsonl`×5, `tests/conformance/tools/catalog_verified.x64-windows.expected.jsonl`×5

## Existing fixtures

- `tests/conformance/tools/check_project`

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
