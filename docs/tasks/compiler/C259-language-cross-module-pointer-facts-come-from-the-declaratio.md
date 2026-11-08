# C259 — language: cross-module pointer facts come from the declaration, never from the callee's body

| field | value |
|---|---|
| category | compiler / Language design |
| score | 0.00 of 1 |
| queue position | 215 of 224 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Opened from the 2026-11-04 language design review. Problem: the lexical region subset in section 11 plus `callee_keeps` reads another module's body through any number of modules to decide whether a container retains a borrowed pointer. D1677 records the consequence as found and not fixed: a warm build writes an image the clean build refuses with E-SAFETY-0013, and the documented fix adds a body edge per foreign function, so every body edit invalidates its callers and both section 12 and section 15 pay for it. Proposal: a call that hands a region value or a view across a module boundary is legal only against a declared contract on the parameter (`@noescape`, `own`, or `@borrows` for the result direction), which is the fact the interface already serializes in artifact format 14. Nothing outside the function's own lexical scope is read; an unannotated callee gives no answer, so it cannot be inferred from. Token and cost: one attribute line per boundary function that hands region values, in exchange for a warm build that equals a clean one. A silently wrong image costs a rebuild, a bisect and a debugging turn, the most expensive repair class measured, and the checker loses the alias-chain cases that only the body walk accepted, so its own context shrinks. Guard: the single-function rules (move at most once, cleanup on every exit, a view of a mutated container) stay as they are. Not done: D1677's warm and clean builds agree by a fixture; the alias-chain fixtures the walk alone accepted are annotated or moved to @unsafe; both suites pass.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `callee_keeps`: `src/check.e`×7‡
- `@borrows`: `src/check.e`×4‡, `lib/e/sync.e`×2, `src/em.e`×2‡, `tests/conformance/accept/regions_borrow_contract_aggregate.e`×1, `tests/conformance/accept/regions_borrow_contract_artifact.e`×1, `tests/conformance/reject/regions_borrow_contract_body.e`×1, `tests/conformance/reject/regions_borrow_contract_body.expected.jsonl`×1, `tests/conformance/reject/regions_borrow_contract_call.e`×1

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
