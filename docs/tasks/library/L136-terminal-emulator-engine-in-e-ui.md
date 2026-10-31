# L136 — Terminal emulator engine in e.ui

| field | value |
|---|---|
| category | library / UI |
| score | 0.80 of 1 |
| queue position | 49 of 106 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> PART (D3200): e.ui.terminal, a superset of e.text.terminal (C120) -- wide cells, DSR/DA replies, OSC titles, origin/insert/tab-stop modes, wrapped flags, DEC line drawing, 1049/47/1047 alt screen, snapshot viewport; ui_terminal fixture: 12 scenarios plus a 4 KB generated stream whose buffer hash, cursor and line count equal an independent Python model fed whole and in 7-byte pieces. Missing: PTY ownership, reflow on resize, mouse and key encoding, selection, the widget over e.ui.collection. PART (D3501): reflow on resize, xterm key/mouse/focus/paste encoding, selection model; ui_terminal_ext 1000 cases vs an independent model. Missing: widget over e.ui.collection, PTY ownership, keypad application mode, mouse 1005/1015, kitty/modifyOtherKeys. PART (D4500-D4502): keypad application mode, modifyOtherKeys, kitty keyboard protocol, mouse 1005/1015, selection edge cases, e.ui.terminal_view scrollback adapter over e.ui.collection; ui_terminal_proto 6,964 cases (model is the lane's reading of the protocol texts; no xterm/kitty on this host), ui_terminal_view. Missing: PTY ownership, per-cell colour drawing in the view.

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
