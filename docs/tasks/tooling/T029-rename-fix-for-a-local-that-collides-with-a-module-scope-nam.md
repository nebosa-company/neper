# T029 — Rename fix for a local that collides with a module-scope name (E-NAME-0003)

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.85 of 1 |
| queue position | 51 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> E-NAME-0003 ended 35 of the 134 builds that failed on a compile code in 2026-09-20..27, the most of any code: common nouns that large modules use as functions (`text`, `level`, `row`, `placeholder`, `at`, `cell`, `icon`), `use` qualifiers (`source`, `bytes`, `check`) and the reserved `target`, `Vec` and `i8`. D66's no-shadowing rule stays; what is missing is a fifth fix kind beside the four in src/main.e's diagnostic writer that proposes a free name for the local and every use of it in its scope, so D948's repair loop applies it without a model turn. Done when a fixture per collision kind (module function, qualifier, builtin, reserved) carries a machine-applicable rename and lang-stats.py shows E-NAME-0003 no longer the top repeated code. Fix kind 5 (D1678) does the first half: on ModuleShadow, ReservedLocal and DuplicateLocal the diagnostic carries a `maybe` fix renaming the local and every use in its scope, one edit per site under one SHA-256 precondition, to the first free `name_value`/`name_value2`..`9`. Uses are found lexically to the end of the block (`let`/`var`) or of the body a parameter, `for` name or capture heads; members, field labels, calls of the colliding function, qualified paths through the colliding qualifier and type positions of a colliding builtin are left alone. Fixtures reject/rename_function, rename_qualifier, rename_builtin and rename_duplicate, and reserved_local's golden now carries its fix: byte-equal under stage 1, stage 2 and on Linux, and each applied fix checks clean. Follow-on (D1898): same measurement must include OpenCode rows; a Claude-only reading cannot close a harness-wide top-code claim.

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] lang-stats.py over transcripts written after D1678 showing E-NAME-0003 no longer the top repeated code

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D66` — Composable names and imports (`docs/decisions.md:88`)
- `D948` — H25's context/repair workflow: what an agent is handed, and repairs by the compiler's own fixes (`docs/decisions.md:19007`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `name_value`: `lib/x/cloud/manifest.e`×6, `lib/x/cloud/rest.e`×6, `scripts/rest_fixture_template.e`×3, `scripts/manifest_fixture_template.e`×1, `scripts/manifest_vectors.mjs`×1, `scripts/rest_vectors.mjs`×1, `src/main.e`×1‡
- `name_value2`: `src/main.e`×1‡

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
