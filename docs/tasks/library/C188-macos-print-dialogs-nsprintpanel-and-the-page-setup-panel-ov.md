# C188 — macOS print dialogs: NSPrintPanel and the page setup panel over the PDF printer

| field | value |
|---|---|
| category | library / macOS |
| score | 0.70 of 1 |
| queue position | 6 of 103 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Built 2026-10-25 (D5219): print_dialog runs NSPrintPanel modally over a copy of the shared NSPrintInfo with the page range preset to the caller's minimum and maximum, copies and range shown, and returns a Printer (the virtual PDF printer of D5212) carrying the chosen range and copies; page_setup_dialog runs NSPageLayout and returns paper and margins in hundredths of a millimetre (points converted). tests/macos/probe/print_dialogs.e shows both on the runners and dismisses them from the run loop: both answer Cancelled on aarch64 and x64, the screenshot shows the print panel with range 1 to 9; ui_print passes and the corpus is 1105. Open: a confirmed OK (range, copies and the paper and margin values read back) needs a person (C192); a printer other than PDF picked in the panel is ignored, so real printing (NSPrintOperation drawing into a view) is still a design of its own. Done when a confirmed dialog is checked and the real-printer question is decided.

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
