# TcxGrid parity: audit status and plan

Source: `scripts/audit_tcxgrid.py` -> `tcxgrid-audit.md` (19 TcxGrid controls in 10 forms; read-only flags per column), v3 captures in `tcxgrid/`, menu tree in `v3-menu-tree.md` (`scripts/audit_v3_menus.py`).

## The 19 grids and where each stands

| # | Grid (form) | Opened from | v3 capture | Ours |
|---|---|---|---|---|
| 1 | dbgCards (main, top: card pool / collection) | main window | 03, 04, 05 | the sample's pool and collection grids; compared before (ledger) |
| 2 | dbgDeck (main, bottom: deck / collection) | main window | 03, 05 | the sample's deck grid |
| 3 | dbgPrices (main, left panel Prices tab) | panel tab | 06 | **not built** |
| 4 | dbgAbilitiesPreview (abilities) | Filter > Cards tab > abilities | **not captured** (Filter window moved; unreached) | **not built** |
| 5 | dbgEditions (filter: blocks, formats, editions) | Search > Filter Top... | 02a, 02b, 02c | **not built** (the sample has Advanced Filter only) |
| 6 | dbgPreview (import: 12 views, one per file format) | File > Import... (wizard step) | welcome page only | **not built** |
| 7 | dbgMessages | View > Messages | 01 | **not built** |
| 8 | gdShortcuts (options) | Tools > Options > Shortcuts | 08 | **not built** |
| 9 | dbgPrices (price dialog) | edit a collection Buy-at price | **not captured** | **not built** |
| 10 | dbgSelectEdition | Reports > Missing Set Cards... | 10 | **not built** |
| 11 | dbgSort | View > Sort... | 11 | built (D2432 and later), compared once |
| 12-19 | statistics: dbgEditions, dbgProbability, dbgManaSlots, dbgStartingHand, dbgDeck, dbgCardsInPlay, dbgDiscardPile, gdAdvanced | File > Statistics... (needs a deck) | 09a-09e (Editions, Probability, Mana Slots, Start Hand with three grids, Advanced) | **not built** |

Read-only columns: the audit file marks each column READ-ONLY (column `Options.Editing = False`, editor `Properties.ReadOnly = True`) or read-only through the view (`OptionsData.Editing = False`).

## What the captures show about v3's controls (measured, 1.5x screen)

- Buttons, combo boxes and text fields are 33 px = 22 layout units high; rows are 21 units; checkboxes are 13 units with a blue tick; radios 13 units.
- Buttons are flat: near-white face (#FDFDFD), 1 px #ADADAD border, radius 3, label centred, the default button has a 2 px blue border.
- Combo boxes: white face, 1 px #ABABAB border, a chevron button at the right edge.
- Section headers (Options pages) are a grey vertical gradient bar with a bold title and an icon at the right.
- Group boxes: a 1 px #DCDCDC frame with the title cut into its top edge.

## The oversized look in our dialogs, and the fix

Our grid code builds boxes by hand with `control.sized_style(w, h)` at 26 to 34 units (buttons 28, fields 26, spin boxes 34 to 58), which is the oversized look. The library has `control.button`, `checkbox`, `radio_group` and `combo_box`, but they draw the theme's Material-style look, not v3's DevExpress look. So:

1. Add one set of flat v3-look helpers in `datagrid.e` (`v3_button`, `v3_field`, `v3_combo`, `v3_check`, `v3_radio`, `v3_group`) at the measured sizes, and make every dialog call them instead of its own `sized_style` boxes (`fmt_button`, `dz_dialog_button`, `dz_field`, `setup_box`, `sort_button`, the margin spin boxes, the channel spin boxes).
2. Build the missing grids on the existing `e.ui.datagrid` with v3's column set, read-only flags, widths and fonts from `tcxgrid-audit.md`.
3. Capture each grid again from the sample next to its v3 capture and compare.

Not yet done: step 1 beyond the sizes, steps 2 and 3. Abilities and the price dialog still need capturing.
