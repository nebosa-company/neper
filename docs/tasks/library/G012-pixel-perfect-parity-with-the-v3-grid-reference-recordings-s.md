# G012 — pixel-perfect parity with the v3 grid: reference recordings, state catalogue, metric tokens, visual and behavioural diff ledger

| field | value |
|---|---|
| category | library / UI |
| score | 0.85 of 1 |
| queue position | 84 of 85 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Requirement added by the owner 2026-10-13 (docs/grid.md section 1.1): the grid UI and behaviour must be a pixel-perfect equivalent of MTG Studio v3 (many visual inconsistencies in v5/cardgrid). Record mtgstudio.exe (or owner-supplied screenshots) per state at 100/125/150% DPI; extract metrics into one token table; compare Neper offline renders region by region; replay recorded event traces for keyboard, mouse, timing and focus rules; keep a ledger. Acceptance: every catalogue state within recorded tolerance; traces replay with identical outcomes; no open ledger rows. Blocks G006-G011 from scoring 1. Progress 2026-10-13: states S01 (header+rows, v3 over v5), S02-S04 (header hover, sorted asc/desc), G3 (group rows + group box), F1 (footer), menus recorded from mtgstudio.exe at 150% DPI with docs/grid-parity/drive.ps1 and capture.ps1; metrics and colours extracted to docs/grid-parity/tokens.json; ledger docs/grid-parity.md has 20 differences (P001-P020, all open). Open: 100/125% scales, filter/preview/editors/scrollbar/no-data/drag/CF/deck/collection states, tokens read by e.ui.datagrid, comparison fixtures, behaviour traces. D3919: e.ui.gridlook Look (v3() from tokens.json) read by datagrid.set_look and collection TableLook: row 19, header 21, zebra, selected, column lines, group row, footer band; ui_datagrid s15 pixel probes (mutation caught); docs/grid-parity/S01-compare-after-look.png. P001/P002/P004/P005 closed; text face, indicator/star/ES columns, frame, navigator, group box, scrollbar still open. D3920-D3922: text size by ink width (P003 closed, P021 withdrawn), frame, indicator width, favourite star column + navigator arrows (screenshots S01-compare-after-*.png), SCENE_BYTES 1 MB. Open: ES column, scrollbar, group box, 100/125% recordings, body-string checks, behaviour traces. D3923: group box, group rows with +/- box, measured scrollbar, v3's own mana symbols and legality letters in the sample (screenshots S01-compare-group-box-rows/v3-images/scrollbar.png); widget Image source fixed (texels). Open: ES column (edition symbols), page-skip/filter buttons, 100/125% recordings, behaviour traces; sample to read the real Cards table of mtgstudio.db3 (owner request). D3925: v3 column set and widths in the sample, ES edition symbols from v3's SVG collection, navigator page buttons and funnel, keyboard-follows-focus with first traces (docs/grid-parity/traces.json). 100% and 125% recorded for both programs (S100-*, S125-*; row pitch equal at all three scales). Open: remaining behaviour traces, body-text checks on deck/collection views, per-state fixtures. D2383: sort traces recorded (S2: current card kept, minimal scroll, sort keys clicked+Edition+Name) and best-fit on a header-edge double tap (A1), both replayed in ui_datagrid sections 22-23; open: delayed filter, focus after filter/group/edit, deck and collection views. D2384: grouping/ungrouping keeps the current card current and opens its groups (G1, reveal_current, ui_datagrid section 24); filter trace F1 recorded as not applicable to the card pool (find box + dialog, no delayed filter row). Open: deck and collection views, focus after edit. D2385: row ink by the card colour from v3's own palette (set_row_ink, gridlook.card_ink / rarity_ink; P014 closed). D2386: collection and deck views in the sample with v3's own column sets and widths (code-read, tokens.json), collection footer Qty 310 / Used 19 / $0.00 as in the v3 recording (S01-compare-collection.png, S01-v5-deck-view.png). Open: v3's deck window as its own window, editing traces in these views. Editing trace E1 (collection Qty edit, Enter keeps the row, Down, Tab order) recorded and replayed (D3930, ui_datagrid section 25).

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
