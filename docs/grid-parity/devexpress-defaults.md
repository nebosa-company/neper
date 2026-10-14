# DevExpress-side comparison (G012)

Source: `D:\tools\DevExpress VCL 23.2.6\VCL` (ExpressQuantumGrid, ExpressLibrary). The grid of v3 is a
TcxGrid of this library, so its defaults are what v3 shows unless MTG Studio overrides them
(`main.vcl.form.dfm`, `docs/grid.md` section 2). Compared 2026-10-14; values are in 96 dpi logical
pixels and scale with the display (the measurement machine runs at 150 percent).

| Item | DevExpress source | v3 measured | neper | Status |
|---|---|---|---|---|
| Row indicator width | `cxGridDefaultIndicatorWidth = 12` (`cxLookAndFeelPainters.pas:65`, used at `cxGridTableView.pas:16124` with `ScaleFactor.Apply`) | 17 px at 150 percent (about 11.3) | `ColumnSpec.width 11.3` for the indicator | matches within a pixel |
| Expand button indent in a group row | `DefaultGridExpandButtonIndent = 3` (`cxLookAndFeelPainters.pas:8383`) | box 3 px from the cell edge | box drawn at the cell's left edge (0 padding) | differs by 3 px, not changed |
| Preview left indent | `cxGridPreviewDefaultLeftIndent = 20` (`cxGridTableView.pas:78`) | text under the Name column, left of it by the indicator | detail text padded 35 logical from the row start | measured value kept |
| Preview max lines | `cxGridPreviewDefaultMaxLineCount = 3`, right indent 5 | one line (MaxLineCount set by MTG) | one line, no wrap | matches v3 measurement |
| Group row colour, Office 11 style | `dxOffice11GroupIndentColor = $C9EEFD` (BGR, `dxOffice11.pas:446`), `GridGroupRowStyleOffice11ContentColor = clWindow` when the row has data | v3 shows grey `#E4E4E4` group rows (not the Office 11 style) | `group_row` token from `tokens.json` | v3 uses another group style; neper follows v3 |
| Grid line colour | `DefaultGridLineColor` of the painter (`cxLookAndFeelPainters.pas:366`) | `#DEDEDE` measured | `line` token `#DEDEDE` | measured, source default not read |

## What this does and does not cover

* Only the defaults above were read from the DevExpress sources. The measured v3 values are the
  authority wherever MTG Studio or the skin overrides a default.
* Not compared against the sources: header height (computed from the font and the painter),
  the footer and group footer metrics, the navigator buttons (`cxNavigator`), the filter row, the
  customization form, the quick customization list and every popup menu (all taken from the
  recordings only).
