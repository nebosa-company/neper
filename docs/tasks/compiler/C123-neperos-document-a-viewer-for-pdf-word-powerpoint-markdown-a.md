# C123 — NeperOS Document: a viewer for PDF, Word, PowerPoint, Markdown and text, with syntax highlighting

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.00 of 1 |
| queue position | 4 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Queued by the user (2026-10-08). The Document icon (home index 25, a page with angle brackets) has no app yet. Acceptance: (1) a viewer for PDF (text, images and vector graphics, outline, page jump, search), Word (.docx), PowerPoint (.pptx, one slide per screen), Markdown (rendered: headings, lists, tables, code, links) and plain text, built on library parsers (the e.fmt family; a PDF and an Office Open XML reader are new library modules), with zoom, a page or slide strip and find; (2) a code view with syntax highlighting for the 30 languages that lead the current TIOBE index at the time of building (the list changes, so the item records the index month it used) plus Neper: highlighters are table-driven token rules in the library (reusing the Neper tokenizer for Neper), one rule table per language, picked by file extension and shebang, with a fixture of snippets per language; (3) opened from Files and from other apps (Mail attachments, Wallet document pages), read only; (4) large files paged, not loaded whole; (5) a fixture on QEMU that opens a Markdown file and a Neper source file and checks the highlighted token classes. Not queued here: editing, annotation, signing, printing, DRM.

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
