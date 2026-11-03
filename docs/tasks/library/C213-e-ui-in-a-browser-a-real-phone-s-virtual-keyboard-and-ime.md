# C213 — e.ui in a browser: a real phone's virtual keyboard and IME

| field | value |
|---|---|
| category | library / WebAssembly |
| score | 0.00 of 1 |
| queue position | 102 of 106 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Android Chrome checked by hand (D5890, D5891: suggestion replacement, touch hold, drag selection, toolbar); iPhone simulator (iOS 17.5 Mobile Safari, .github/workflows/ios-sim.yml, D5900) passes typing, Backspace and the hold toolbar; a real iPhone and a composing keyboard are still unchecked. Needs a device. Prepared: `node scripts/serve-wasm.mjs --isolated --host 0.0.0.0` and open /tests/wasm/browser/phone_probe.html on the phone (a plain field that logs key, composition, paste, visualViewport and scroll events; Report copies the log) to answer checks 1-5 before touching ui_counter. D5821 lists what the mobile preset did and did not show (synthetic composition events, the textarea at 16 px not scrolling or zooming). Serve tests/wasm/browser/ui_counter.html over HTTPS or a LAN address with scripts/serve-wasm.mjs --isolated (a secure context is needed for crossOriginIsolated and the clipboard) and check on iOS Safari and Android Chrome: (1) tapping the Name field opens the keyboard and neither zooms nor scrolls the page; (2) typed letters, Backspace and Enter arrive once each; (3) composition with a CJK keyboard (pinyin or kana) delivers the committed text once, with no duplicate after compositionend and none while composing; (4) the clipboard: paste from the system menu reaches the program, and Ctrl+C in the program writes navigator.clipboard, with the permission prompt answered either way; (5) visualViewport resizes when the keyboard opens and the canvas stays usable (decide whether the window follows it); (6) a physical keyboard on a tablet still works. Fix what fails in lib/wasm/window.js; window_visible is separate.

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
