# C258 — language: a local may shadow a module-scope function and a builtin type name (reopen D66's reserved set)

| field | value |
|---|---|
| category | compiler / Language design |
| score | 0.00 of 1 |
| queue position | 214 of 224 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Opened from the 2026-11-04 language design review. Problem: E-NAME-0003 ended 35 of the 134 builds that failed on a compile code in 2026-09-20..27, more than any other code (D1678), and its largest slice is the rule that a local or parameter may not reuse a module-scope function (`text`, `row`, `cell`, `level`, `width`, `at`) or a builtin type name (`target`, `Vec`, `i8`). That makes the legality of `let width = 3` depend on declarations elsewhere in the module, which is exactly what a generated line may not depend on (spec section 1, goal 1); D1678's rename fix mitigates it but does not change the design. Proposal: reserve only `use` qualifiers and the `target` namespace. A local or parameter may shadow a module-scope fn, const, var or type name and the builtin type names, because spec section 2 already resolves types and values by position. Module scope keeps one definition per name, so `grep -n ^fn dot` still returns one line, and a call through a shadowed name is a local type error (E-NAME-0004), never an ambiguity. D1678's machine-applicable rename stays for qualifier collisions and duplicate locals. Token and cost: this deletes a repair class. No new syntax, no extra token on any line, a shorter trap section on the card, and it removes one failed build plus one repair turn per occurrence, which is the most expensive failure mode measured. Guard: the five implicit operations, the no-overloading rule and the explicit-cast rule are untouched, and the index, tokens and parse streams keep their shape. Not done: fixtures that shadow a module fn, a const, `i8`, `Vec` and `str` as a value name accept and format; a call through the shadowed name rejects E-NAME-0004; the card re-renders without those two traps; lang-stats repeat rate is re-measured on transcripts written after the change.

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
