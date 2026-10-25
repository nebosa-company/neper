# L169 — Browser M4: JavaScript engine and DOM bindings

| field | value |
|---|---|
| category | library / Library |
| score | 0.00 of 1 |
| queue position | 89 of 101 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Plan docs/browser-progress.html, decision D5115. Needs L166; engine work (5.1 to 5.16) can start in parallel with L167. Acceptance: (1) P5 5.1 to 5.16: parser, compiler, VM, heap and GC, object model, builtins, ECMAScript RegExp, Promise and microtasks, modules, test262 runner with feature-gated pass targets, benchmarks against QuickJS; (2) P6 6.1 to 6.8 and 6.14 bindings: DOM, CSSOM, events, timers, fetch, storage, forms; (3) 6.17 iframes; (4) jQuery 3.5.1 initialises, AJAX re-renders, timers and events work, getBoundingClientRect feeds layout; (5) 9.4 test262 targets, 9.6 real-site sweep including JS-app pages

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] all of it

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
