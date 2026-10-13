# Grid parity ledger (G012, docs/grid.md section 1.1)

Reference: `mtgstudio.exe` v3.234 (Debug build, db3 of 120,254 cards, 120,239 in the pool) recorded with
`docs/grid-parity/capture.ps1` (DPI-aware, topmost, `GetWindowRect` + `CopyFromScreen`) next to the Neper sample
`v5/cardgrid` on the same machine. This machine runs at **150 % (144 dpi)**, so every number below is in physical
pixels at 150 % with the logical (100 %) value after the slash; the 100 % and 125 % recordings are still to be
made (change the display scale, rerun the capture).

## Recorded states

| State | v3 recording | v5 recording | Comparison |
|---|---|---|---|
| S01 card pool, header + first rows, first row selected (current), nothing filtered | `S01-v3-cardpool-150pct.png` | `S01-v5-cardgrid-150pct.png` | `S01-compare-v3-over-v5.png` (v3 above, v5 below, same scale) |

Still to record (catalogue in grid.md 1.1): header hover/pressed/sorted, group rows and group footers, footer
summaries, filter row, preview row, in-place editors, scrollbars, no-data, drag, conditional formatting, and the
deck and collection views.

## Measured metrics (S01)

| Metric | v3 | v5 | Ledger |
|---|---|---|---|
| Row pitch | 28-29 px / 19 (28.5: rows alternate 28 and 29) | 42 px / 28 | P001 |
| Header cell height | 32 px / 21 (166..197, bottom line #C6C6C6) | ~42 px / 28 plus a 18 px band row | P002 |
| Selected row | fill #A6D2FF, 1 px border #83878B, light gradient on the top and bottom 2 px | secondary-container tint, no border | P006 |
| Row backgrounds | zebra: #FFFFFF / #EFEFEF, no horizontal line | all rows the same, 2 px line (#D6D8E4 / #CACDDB) | P004, P005 |
| Grid frame | 1 px #BBBDC2 around the grid | none | P011 |

## Differences (open until closed by a recording-backed fixture)

| Id | Difference | Measure | State |
|---|---|---|---|
| P001 | Row height is 1.5x v3's | 42 vs 28.5 px | open |
| P002 | Header (and band) taller than v3's | 42+18 vs 32 px | open |
| P003 | Text is larger than v3's (Segoe UI 9 pt in v3) | v5 glyphs ~1.35x taller | open, measure em height |
| P004 | v3 stripes rows (#FFFFFF / #EFEFEF); v5 does not | | open |
| P005 | v5 draws 2 px row separators; v3 has none between rows | | open |
| P006 | Selected row: v3 #A6D2FF with a dark 1 px border and gradient ends; v5 flat tint, no border | | open |
| P007 | v3 has full-height vertical column lines in header and body; v5 only short header dividers | | open |
| P008 | Header look: v3 white cell with the sort triangle right-aligned in the cell; v5 tinted header with the arrow after the text | | open |
| P009 | Left columns: v3 has the customization glyph, favourite star, "ES" icon and the row indicator arrow, each ~18-20 px / 13 logical; v5 has one 28 px indicator | | open |
| P010 | Cell text inset: v3 ~6 px / 4; v5 ~16 px | | open |
| P011 | v3 frames the grid with a 1 px border; v5 has none | | open |
| P012 | Navigator: v3 flat glyph buttons (|< << < "1 of 120239" > >> >| filter) and a grey scroll bar; v5 text buttons | | open |
| P013 | Footer: v3 shows summaries in a tinted band only when the footer is on ("Rows: 8" in the collection grid); v5 "Total" row styled differently | | open |
| P014 | Row ink by rarity: v3 orange (mythic) and red (rare) with the exact palette of the app; v5 uses theme data colours | | open, extract palette |
| P015 | Scrollbar: v3 native thin vertical bar; v5 draws none in the capture | | open |
| P016 | Legality cell: v3 paints five coloured "S M E L V" badges; v5 shows no legality column | | open (G008 painter) |

The metrics must move into the single token table the grid reads (grid.md 1.1) and every row above gets a
fixture comparing a Neper render with its recording; none is closed yet.
