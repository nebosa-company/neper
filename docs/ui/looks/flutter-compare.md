# Flutter comparison (round 70, lane a: inputs)

References: `ref/flutter/neper` (M3, seed #1b3a6b) for the Neper looks, `ref/flutter/material` (M3, seed #6750A4) for Android, `ref/flutter/cupertino` for macOS/iOS (shapes only, its text is Roboto). Comparer: own python (numpy, scipy) scripts, not committed: components found by bounding box, size, corner radius, mode fill, edge colour, shadow ring and glyph ink box read per cell, light only for the numbers, dark checked by role. Coverage is partial: the Material rows below were measured cell by cell; the Neper and Cupertino rows of this lane were only measured for button, icon button, checkbox, radio, range slider and the text fields, and are left at their status.

## Global deviations (all controls)

- G1 Neper palette: `docs/ux/tokens.json` primary is #145db2, Flutter's fromSeed(#1b3a6b) gives #425e91. Same roles and the same state layers (hover 8, focus 10, pressed 10); Neper's own tokens win.
- G2 Neper density: pointer-host controls are 32 tall (button, icon button 32, fields 30), Flutter is 40/48/56. README: density is a setting.
- G3 Neper focus: 3 px solid ring 2 px outside; Flutter shows a state layer only. Stated design.
- G4 Android palette: the published M3 baseline (#6750A4, matched earlier against Material Web) against Flutter's fromSeed result #65558F for primary, on-primary-container and tertiary roles; surfaces, outline and containers agree within 2 levels. Not changed here: the palette is shared by every Android row, so it needs one decision for all lanes.
- G5 Flutter harness artifacts, ignored: black outline on hovered buttons, on elevated buttons at rest, on every FAB state and on snackbar/menu surfaces (refs `button-*-hover`, `button-elevated-*`, `fab-*`, switch hover/focus); pressed refs are a mid-ripple frame.

## Deviations by control

- button, Neper: 32 tall pill against 40 (G2); Cupertino: medium 34, large 50 against Flutter large 52 x r8, label font differs.
- radio, Android: ring 20 x 20 (M3 spec, Material Web) against Flutter 18 x 18.
- checkbox, Android: focused unchecked halo tinted primary, Flutter on-surface. Unfixed gap.
- checkbox, Neper: focus ring is clipped to the row height in the sheet (only the two side bars show); halo is a rounded square not a circle. Unfixed gap.
- checkbox, Cupertino: focus ring surrounds box and label (134 x 26), Flutter rings the 14 px box only (20 x 20). Unfixed gap.
- range slider, Neper: vertical-bar handles (M3 expressive), Flutter draws round thumbs. Intended per the Neper component spec.

## Fixed

- Android outlined icon button: the focused outline turned primary; Flutter and the M3 outlined icon button keep the outline colour. Only the outlined button turns primary. Fix in `material_icon_button` (control.e); changes `material/icon_button`, `material/fab` and the dark pair.
