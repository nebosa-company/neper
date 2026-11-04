# C262 — docs: one normative home per fact (section 13 versus tooling.md, section 11 versus the H-track files)

| field | value |
|---|---|
| category | compiler / Language design |
| score | 0.00 of 1 |
| queue position | 217 of 219 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Opened from the 2026-11-04 language design review. Problem: the same fact is written twice, so a tooling change is read and edited in two places. Section 13 Toolchain is 603 of the spec's 5149 lines and restates docs/tooling.md; section 11's region and concurrency rules restate docs/m25-h02-regions.md and docs/m25-h04-concurrency.md. Three smaller self-contradictions sit on top: `unreachable` is a keyword although section 14 calls it the one builtin that is a keyword rather than a core function; `usize` and `isize` are keywords although they are only type names; section 8 allows copying an `Arena` to transfer it while section 11 makes it affine. Proposal: each fact lives in exactly one document and every other mention links to it. The spec keeps semantics, tooling.md keeps the command and stream contracts, and the H-track files keep their measurements as evidence rather than as normative text. Token and cost: this is the largest context win in the list. An agent landing a tooling change pays for both copies today, and the card, the digest and the tasks page inherit the duplication. Guard: no semantic change; a moved fact gains a link where it was; the card stays generated, never hand-edited. Not done: the split, the three contradictions resolved, and a link check so a moved fact cannot be silently unlinked.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `Arena`: `lib/e/ui/control.e`×460‡, `lib/e/ui/datagrid.e`×197‡, `src/main.e`×184‡, `lib/e/ui/overlay.e`×168‡, `lib/e/ui/navigation.e`×158‡, `lib/e/ui/collection.e`×113‡, `lib/e/os/shell.windows.e`×83‡, `lib/e/os/shell.macos.e`×76‡

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
