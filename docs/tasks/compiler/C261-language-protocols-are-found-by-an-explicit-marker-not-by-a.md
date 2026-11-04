# C261 — language: protocols are found by an explicit marker, not by a derived snake_case name

| field | value |
|---|---|
| category | compiler / Language design |
| score | 0.00 of 1 |
| queue position | 216 of 219 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Opened from the 2026-11-04 language design review. Problem: `K.hash(v)` resolves to `fn sensor_hash` by deriving the name from the type's name through a Unicode snake_case algorithm (`HTTP2Client` becomes `http2_client`), plus a separate rule for a generic type's stem, a rule for which alias spelling keeps the nominal declaration, and a recorded lookup edge when a supplied fallback is used (section 9, D48). Every implementation must reproduce the algorithm byte for byte, and a reader cannot tell from `fn sensor_hash` that it is the protocol for `Sensor` without running the algorithm in their head. Proposal: `@proto(Sensor)` on the function, and the same fact in `neper index`. Lookup matches a marker rather than a spelling. The five resolution rules, the supplied fallbacks and the call-site syntax stay. Token and cost: one attribute line per protocol function, nothing at any call site, and the spec loses the case algorithm with two name-resolution rules that an agent otherwise has to load to predict a resolution. A typo becomes a missing marker refused with one code, instead of a silent fall back to the supplied hash. Not done: the attribute in the grammar and the checker, the index edge, diagnostics for a duplicated or mismatched marker, and conformance fixtures for a generic type's protocol and the str fallback.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D48` — Type aliases (`docs/decisions.md:70`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `K.hash`: `lib/e/concurrent/map.e`×3, `lib/e/data/map.e`×2, `lib/e/data/tree.e`×1
- `HTTP2Client`: `src/check.e`×1‡
- `http2_client`: `src/check.e`×1‡
- `Sensor`: `benchmarks/llm_edit/semantic.py`×9, `lib/e/robot/map.e`×3, `benchmarks/llm_edit/README.md`×1, `benchmarks/llm_edit/neper_advantage_matrix.md`×1
- `@proto`: `lib/e/text/highlight.e`×1, `lib/e/ui/code_editor.e`×1‡, `scripts/gen_highlight.py`×1

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
