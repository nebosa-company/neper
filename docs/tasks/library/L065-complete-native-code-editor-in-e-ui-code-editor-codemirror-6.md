# L065 — Complete native code editor in e.ui.code_editor (CodeMirror 6 / JustCode parity)

| field | value |
|---|---|
| category | library / UI |
| score | 0.30 of 1 |
| queue position | 40 of 106 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> PART (D3201): e.ui.code_editor model and engine only -- gap-buffer UTF-8 document with line index, atomic commit, multi-range selections, grapheme/word motion, undo/redo with coalescing, incremental tokenizer (neper, javascript, python, plain), indent/comment commands, literal search/replace; ui_code_editor fixture: 10 scenarios plus a 520-step generated script digest-checked against a flat-text oracle. Missing: widget, IME/accessibility, bidi/wrap layout, folds, regex search, completion, diagnostics, LSP, most language packs. PART (D3500): regex search/replace, bracket matching, folds, soft-wrap model, multi-cursor and rectangular selection, 13 language packs; ui_code_editor_ext 394 cases vs Python re and models. Missing: widget, IME/accessibility, bidi, decorations, completion, diagnostics, LSP. PART (D4401-D4403): 33 more language packs checked against Pygments (41 of 51 ids), per-view fold state through edits/undo, wrap-aware motion, completion and diagnostics models, bracket and JSON lints; ui_code_editor_svc 1,098 cases. Missing: widget, IME/accessibility, bidi, decorations, snippets, LSP, Scratch .sb3, embedded-language HTML.

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
