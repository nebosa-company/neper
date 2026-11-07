# C260 — language: make the zero value total - every enum and union enum declares a member at 0

| field | value |
|---|---|
| category | compiler / Language design |
| score | 0.00 of 1 |
| queue position | 215 of 222 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Opened from the 2026-11-04 language design review. Problem: section 7 carries a carve-out. A type that holds, at any depth, an enum with no member at 0 has no zero value, so `= zero`, a module-scope `var` without an initialiser and `try` in a function returning it are compile errors naming the outermost type and the offending field. A generator must therefore read the whole type graph before it knows whether a line is legal, the same unseen-context dependency as C258. Proposal: an `enum` or `union enum` declaration must name a member whose backing value is 0, the mirror of the existing rule that renames an error whose FNV-1a hash is 0. Then every type has a zero value, and the carve-out, its three error sites and the exceptions in the zero table go. `err` = ok, a slice = nil and the null resource already fit. Token and cost: one member on an enum that starts at 1 (`None = 0`), against a rule and three diagnostics that leave every future context, and generated code writes `= zero` and `try` without first resolving the type. Guard: `= undef` and E-SAFETY-0017, the refusal of a value that can only be invalid, are unchanged. Not done: the section 7 table and rule rewrite, the declaration-time diagnostic naming the enum and the member it needs, accept fixtures for `= zero` and `try` over such an enum, a reject fixture for the declaration without a 0 member, and the card's zero section re-rendered.

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
