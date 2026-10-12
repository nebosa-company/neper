# C114 — NeperOS shell 10: the Tasks and Settings apps; the shell milestone closes

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.70 of 1 |
| queue position | 33 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Queued by D2148. Acceptance: Tasks (lists, due dates, done state) persisted in the filesystem; Settings (wallpaper, 12/24-hour clock, about this device) in a settings store that survives a reboot; QEMU fixtures as for C113. Closing this item closes the D2148 shell milestone and queues the next D2148 phase (the Android bridge over vsock). BEGUN D2181/D2182: both C114 app FACES render through e.gfx.scene over the e.gpu CPU backend, host==neperos both QEMU -- tasks_app.e a checklist (header + 6 rows: checkbox, task number in the 3x5 bitmap font, title bar; hash 3422317813), settings_app.e a settings list (header + 5 rows: label bar + toggle switch track/knob; hash 385502117). D2190: the Tasks app now COMPUTES its done-state through a toggle engine -- starts 3-of-6 done, applies a fixed sequence of toggle inputs (check tasks 3 and 5), counts the result and renders the computed checkboxes, printing `tasks done 5`; host==neperos hash 394791925 both QEMU, and the app-face loop asserts the literal `tasks done 5`. C114 -> 0.65: the Tasks toggle logic computes from input; the Settings toggles, live tap input, and shell-hosting still wait on C112's prodshell. D2191: the Settings app now COMPUTES its on-state through a toggle engine too -- starts 3-of-5 on, flips settings 2 and 5, counts and renders the computed switches, printing `settings on 5`; host==neperos hash 3605923141 both QEMU, loop asserts the literal. C114 -> 0.7: both apps compute their state from input; live tap input and shell-hosting still wait on C112's prodshell.

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] interactive behavior (toggling, editing) and hosting the apps in the shell
- [ ] which wait on C112's unified launcher

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
