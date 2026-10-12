# C142 — NeperOS Document: real PDF, Office and Markdown readers; highlighting for the 30 leading languages

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.00 of 1 |
| queue position | 24 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Queued (2026-10-08). The Document app (D2237) shows sample files: a Markdown renderer for headings, bullets and code, a code view with a one-rule-set highlighter and keyword lists for eight languages, and hand-drawn PDF, Word and PowerPoint pages. This is C123's remainder. Acceptance: (1) a PDF reader in the library (objects, streams with Flate, fonts and text positioning, images, vector paths) painting through e.gfx.scene, with the outline, search, page jump and zoom by pinch (the touch layer needs it); (2) a Word (.docx) and PowerPoint (.pptx) reader over the Open Packaging zip and XML in the library (paragraph and run styles, lists, tables, images, slide shapes and text), and OpenDocument next; (3) a Markdown parser (CommonMark with tables) and an HTML view shared with Mail (C128) and the Browser (C129); (4) highlighting from table-driven rule sets in the library (token rules per language, picked by extension and shebang) for the 30 languages that lead the TIOBE index in the month the item is built, plus Neper reusing its own tokenizer, with a fixture of snippets and the expected token classes for each; (5) open files from Files (C125), Mail attachments and the Browser's downloads, with large files paged; (6) a share and open-with sheet, and Dynamic's source view (C124) uses the code view; (7) a fixture on QEMU that opens a real Markdown, PDF, DOCX and PPTX file from a test image and checks the text drawn. Not queued here: editing, annotation, signing.

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
