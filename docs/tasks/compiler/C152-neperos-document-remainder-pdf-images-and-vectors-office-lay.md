# C152 — NeperOS Document remainder: PDF images and vectors, Office layout, pinch zoom, attachments

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.75 of 1 |
| queue position | 25 of 85 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Split from C123 (D2394): Document shows the text of PDF, Word and PowerPoint files, rendered Markdown and highlighted code from the disk, with paging, find and text size. Acceptance: (1) PDF pages painted, not only their text: vector paths, images (DCT through e.fmt.jpeg, Flate images), fonts with their own encodings, the outline and search with the match highlighted; (2) Word tables, images and styles and PowerPoint shapes laid out; (3) pinch zoom and a page or slide strip once the touch layer carries more than taps; (4) opening from Mail attachments and Wallet pages (C128, C121) and Share; (5) shebang detection and the TIOBE list refreshed from tiobe.com with the month recorded; (6) files over 16 KB paged from the disk, not read whole. Delivered by C123 and not to redo: D2389-D2394. PART (D3801, D3802, D3804, D3805, D3809): painted PDF pages (rects, segments, text, colours, q/Q, cm), Word tables as grids, shebang detection, 12000-byte windows for big text files; QEMU rows document_pdf_paint, document_docx_table, document_big, document_shebang pass; fmt_pdf (23) and fmt_ooxml (39) pass. Missing: PDF images/fonts/outline/search highlight, Word images/styles, PPTX shapes, pinch zoom, open from Mail/Wallet/Share. PART (D4800-D4809): PDF images (DCT, Flate), form XObjects, font widths, ToUnicode, outline, Find highlight, zoom steps and pan; Word styles and pictures, PPTX shapes; Mail attachment Open and Files Share; fmt_pdf +30 checks vs independent producers; rows document_pdf_image, document_pdf_zoom, document_word_pic, document_pptx_shapes, document_ods, document_html, mail_attach_open, files_share, document_zip_entry pass. Remaining: pinch zoom and page strip (one pointer, no two-finger gesture), opening from Wallet pages, PDF glyph outlines, clipping, Indexed images, soft masks.

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
