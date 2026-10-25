# C190 — macOS window system: accessibility, input methods, close veto, live resize, Retina

| field | value |
|---|---|
| category | library / macOS |
| score | 0.60 of 1 |
| queue position | 8 of 103 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Done 2026-10-25: the close button is a request answered through a window delegate (D5222, macos_window_close); the published accessibility tree is NSAccessibilityElements under the content view (D5223, macos_accessibility); input methods commit text (D5229, macos_text_input). The content view's class (NeperTextView, made at run time over the view's own class) answers the text input protocol: insertText:replacementRange: turns committed text, from an NSString or an NSAttributedString, into Text events; setMarkedText, unmarkText, hasMarkedText, markedRange and selectedRange hold a composition's state (marked text is not shown, since a window event has no preedit kind: that is an API change for every host); firstRectForCharacterRange answers a point in the window's top left for the candidate window; doCommandBySelector: is ignored; the view accepts first responder, so the window has an input context. A key with an input method selected (its source id has "inputmethod" in it) goes through interpretKeyEvents:, a plain layout's key keeps its own characters as before (a synthetic key event does not come back from the input context synchronously, so the layout path stays direct). macos_text_input calls the input method's methods by hand: an accented letter and a kana become Text events, marked text produces none, committing clears the mark; aarch64 and x64, corpus 1109. Not done: a real input method composing Japanese, Chinese or Korean and its candidate window's place (C192); preedit display; focus, set-value and selection requests, tables, relations and live regions in the accessibility elements, and a real VoiceOver reading the tree (C192); live resize while the pointer drags an edge, which the poll model cannot do (the program is inside AppKit's tracking loop and gets Resize and Paint only afterwards; a callback API would be needed); Retina scale changes between displays (windowDidChangeBackingProperties: on the window delegate) and native-resolution checks (C192).

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
