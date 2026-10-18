# C172 — NeperOS Document remainder: PDF painting, zoom, tables, HTML view, spreadsheets

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.75 of 1 |
| queue position | 67 of 85 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Split from C142 (D2431): Document reads the text of PDF, Word, PowerPoint and OpenDocument files and renders Markdown and highlighted code. Acceptance: (1) PDF pages painted, not just their text: fonts and text positioning, vector paths and images through e.gfx.scene, with the outline, search and page jump; (2) pinch zoom and pan (the touch layer needs press, move and release events); (3) CommonMark with tables in the Markdown parser and an HTML view shared with Mail (C128) and the Browser (C129); (4) Word and PowerPoint tables, images and slide shapes, and spreadsheets (.ods, .xlsx) as grids; (5) open from Mail attachments and the Browser's downloads, an open-with and share sheet, and Dynamic's source view using the code view; (6) a fixture on QEMU that opens a real PDF, DOCX and PPTX and checks what is drawn. Not queued here: editing, annotation, signing. PART (D3800-D3802, D3809): PDF painting, Markdown tables, xlsx as a grid (sheet_names/sheet_grid), Word tables; QEMU rows document_sheet, document_mdtable pass. Missing: pinch zoom/pan, HTML view, .ods grid, PPTX shapes, Word images, open from Mail/Browser, share sheet. PART (D4800-D4809): PDF painting, outline and jump, Word and PPTX layout, .ods/.xlsx grids (fmt_odf +9), html.to_markdown HTML view (fmt_html +3), opening from Mail. Remaining: pinch zoom, Browser and Mail on the shared HTML view, Browser downloads and open-with sheet, Dynamic source view, fixtures on real PDF/DOCX/PPTX from independent producers (only hand-assembled, reportlab and generated samples so far).

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
