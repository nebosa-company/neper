# Windows look: measured tokens

One place for every Windows token that was measured from a v3 capture, so other looks and workers
can reuse it. Append only what you verified, with the evidence file. All captures are at 150 % DPI
(logical px = physical / 1.5; the Options dialog checks out at 1.497: DFM ClientWidth 712 is 1066
physical px). Evidence paths are relative to `D:/repos/neper/docs/grid-parity/`; "scan" means a pixel
row or column through the control read with PIL.

## Colours

| Token | Value | Where | Evidence |
|---|---|---|---|
| Dialog face (`Background`) | #F0F0F0 | form background around the buttons | `tcxgrid/00-options-interface-controls-v3.png` (scan y=710, x=700) |
| Button face, rest (`SurfaceContainerLowest`) | #FDFDFD | TcxButton interior | same file, scan y=710 x=714..819 |
| Button border, rest | #D2D2D2 (logical); AA peaks: left #D7D7D7, top #D8D8D8, bottom #C3C3C3 | Cancel | same file, cols x=850 and row y=710; the bottom edge is darker than the top (not drawn: one border colour) |
| Default button border (accent) | #298DD9 centre, #7EBAE8 inner ring, #C9DCEB outer ring; bottom edge #2982C7 | OK | same file, scan y=710 x=711..714, col x=720 |
| Default button face | #FDFDFD (same as rest) | OK | same file |
| Disabled button face | #F9F9F9 | Apply | `DZ-format-report-Behaviors-v3.png` (col x=1130, y=744) |
| Disabled button border | #E9E9E9 .. #EAEAEA (AA peaks) | Apply | same file, row y=765 x=1114..1117 |
| Disabled button label | darkest pixel #898386 (ClearType fringed; used #878787) | Apply | same file, ink box 1140..1195 x 750..772 |
| Button label, rest | #000000 (darkest pixel #0E0E1C with fringing) | Title Properties | same file, box 40..190 x 750..772 |
| Icon-button face | #FDFDFD, border like a rest button | refresh button | `tcxgrid/06-main-prices-panel-v3.png` (row y=800, x=370) |

## Metrics (logical px = physical / 1.5)

| Token | Value | Evidence |
|---|---|---|
| TcxButton DFM size | 75 x 23 in 84 of 102 buttons (Height 23: 89, 25: 11, 28: 2; Width 75: 84, 31: 7, 195: 4, 150: 3, 25: 2, 131: 1, 130: 1) | scan of all `version-3/src/**/*.dfm` (`TcxButton` objects, 102) |
| Look of every TcxButton | `lfFlat` 96, `lfOffice11` 2 (the main form's Buy and Refresh), none 4; `NativeStyle = True` on 98; so one native Windows 11 look | same scan; `tcxgrid/06-main-prices-panel-v3.png` shows the Office11 pair drawn like the flat ones |
| Default / Cancel / ModalResult | `Default = True` 21, `Cancel = True` 28, ModalResult OK 17, Cancel 19 | same scan |
| Visible button box | about 73.3 x 21.3 (the DFM box less 1.67 each way; the theme draws inside the control rect) | Cancel, Options dialog: edge centres 108.5 px apart plus 1.5 stroke = 110 px wide, 30.4 + 1.5 = 31.9 px high (scans y=710, x=850) |
| Icon-only button | about 29.3 wide (DFM 31) x 23.3 high (DFM 25) | refresh button: 43.5 px wide, 34.5 px high (`06-main-prices-panel-v3.png`, rows 775..809) |
| Border width | 1 logical px (AA'd to 1.5 physical) for rest and default | scans above |
| Label ink (Segoe UI, `Cancel`) | 47 x 14 physical px | `00-options-interface-controls-v3.png` box 842..942 x 698..722, threshold L<170; ours renders 47 x 13 at 11.2 px |
| Label ink (Tahoma 8 pt, `Cancel`) | 47 x 14 physical px | `DZ-format-report-Behaviors-v3.png` |
| Picture on a caption button | 16 x 16 logical (24 physical), group (picture + caption) centred in the button, ink gap picture to caption 5 physical | Buy at $0.00, `06-main-prices-panel-v3.png`, scan columns 141..262 |
| Font | Segoe UI where the button has no explicit font (Options dialog, main form); Tahoma 8 pt where the form sets it (dxPrinting dialogs: `HF1-page-setup-header-footer-v3.png`, `DZ-*`) | crops at 3x |
| Accelerator | the mnemonic letter is underlined (`&Apply`): drawn in v3, not in Neper's Windows button | `DZ-format-report-Behaviors-v3.png` |

## Guesses (not measured; do not cite as v3)

Hover face #F6F6F6 and pressed face #F0F0F0 (Light), toggled-on face (accent at 20 %), the dotted focus
rectangle's inset (2 px inside the border), the split button's arrow part, the busy ring size (14),
every Windows Dark value (faces #2B2B2B / #202020, border #5A5A5A, accent #4CC2FF, text white,
disabled #282828 / #333333 / #757575, hover #323232, pressed #272727, selection #264F78), and every
high-contrast value (the system colours of "High contrast black" and "High contrast white").
