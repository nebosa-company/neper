# Android text: how the references draw it, and the model

2026-10-19, round 35 (`looks35-at`). Replaces the fitted curve of `c18c66b3a` (a 7 % sideways spread, a coverage power, quarter pixel pens).

## What produced the references

`scripts/material/capture.mjs` launches Chrome for Testing 149 (headless shell) **on Windows** with `--disable-lcd-text --font-render-hinting=none`.
So the text is Skia over DirectWrite, not FreeType and not Linux. Roboto is a web font read from `C:/Windows/Fonts`. Greyscale anti-aliasing,
sub-pixel positioning on, no LCD. The earlier work looked for a FreeType light auto-hinter or a Linux Skia table; there is none of either.

## The stages (measured on isolated glyphs, `scripts/material/dwprobe.py`)

1. **Outline.** The font's own TrueType instructions at the whole pixel size, run by `e.text.ttglyph` in its ClearType mode with the end-of-glyph
   fit to the advance off (that fit is GDI's habit). FreeType's v40 hinting gives the same y for all of ASCII at 11 to 57 px; the ClearType mode
   of our hinter also matches the x that DirectWrite moves (the `;` comma), FreeType does not. The x and y are kept as 26.6 pixels.
2. **Samples.** Six columns by five rows to the pixel, a sample set when its centre is inside the outline (non-zero winding). The pen's x goes to a
   quarter pixel (Skia, `floor(4x + 0.5) / 4`) and then to a sixth (DirectWrite, `floor(6f + 0.5) / 6`: 1/4 is 1/3, 3/4 is 5/6); the baseline is a whole line.
3. **Filter.** Each of three ClearType channels is a box of six sample columns, two apart (columns -2..3, 0..5, 2..7 of the pixel); a column is the sum
   of its five rows weighted 4 9 10 9 4 (out of 36). A channel byte is `round(255 * sum / 216)`.
4. **Mask.** `(r + g + b) / 3`, whole-number mean, through Skia's pre-blend table: `SkTMaskGamma_build_correcting_lut` with sRGB for both gammas and a
   contrast of 1, selected by the text colour: each sRGB byte cut to its top three bits (repeated to a byte), then `(54 r + 183 g + 19 b) >> 8`, its
   top three bits. Eight tables; black text is table 0, white 7. Each glyph is blended as its own A8 mask under the colour (alpha of the colour multiplies the mask).

Evidence: 271 000 ink pixels of every printable ASCII glyph at 11, 12, 14, 16, 22, 24, 28 and 32 px, regular and medium, two pen offsets: 98.2 % of ink
pixels within 2 levels (`dwprobe.py`, black on white); 98.4 to 98.9 % over 12 text colours and alpha texts; the table key was checked on 90
random colours with no miss. `tests/selfhost/fixtures/link/text_dwmask` holds Chromium's own bytes for H at 16 px on the four pen positions.

Line boxes: Blink rounds the OS/2 `usWinAscent` and `usWinDescent` of the pixel size to whole pixels and floors the half leading (0 misses over
64 sizes and line heights; the hhea metrics missed 11 and 28 px). Inline sizes are LayoutUnits (a 64th), text starts floor to 64ths, and a menu is as
wide as its widest row at the exact (not whole pixel) advances.

## Measured (`scripts/material/text_cmp.py`, text ink pixels exact = every channel within 2 levels)

The mask of a cell's text is the difference between the reference and the same cell with the text transparent, both taken after the transitions
settle (`capture_textonly.mjs`, `textmask.py`; icons are not in it). Share of text ink pixels exact, before (fitted curve) and after, light then dark:

| sheet | ink px | light before | light after | dark before | dark after |
|---|---|---|---|---|---|
| button | 6292 | 23.8 | 97.0 | 16.8 | 97.7 |
| button_icon | 6288 | 20.8 | 97.2 | 15.4 | 97.8 |
| fab | 1640 | 12.7 | 99.3 | 13.3 | 99.8 |
| switch | 73 | 65.8 | 65.8 | 39.4 | 39.4 |
| text_field | 20716 | 12.2 | 97.0 | 9.4 | 96.8 |
| combo_box | 7528 | 14.9 | 97.9 | 7.3 | 97.9 |
| chips | 14451 | 19.2 | 93.6 | 15.8 | 96.1 |
| progress | 188 | 75.5 | 75.5 | 81.8 | 81.8 |
| tabs | 6237 | 19.6 | 95.0 | 10.3 | 95.3 |
| menu | 1957 | 12.9 | 99.0 | 8.6 | 99.5 |
| list | 8926 | 17.4 | 98.9 | 9.0 | 99.2 |
| dialog | 7344 | 22.5 | 99.1 | 14.4 | 99.2 |
| dialog_icon | 6348 | 21.4 | 98.9 | 14.6 | 99.0 |
| snackbar | 5952 | 9.3 | 95.0 | 18.6 | 94.8 |
| navigation_bar | 4428 | 9.4 | 93.1 | 5.8 | 93.6 |
| app_bar | 3124 | 16.5 | 97.9 | 16.1 | 98.6 |
| search_bar | 3218 | 20.8 | 98.5 | 17.1 | 98.9 |
| badge | 363 | 3.6 | 100.0 | 4.8 | 100.0 |
| tooltip | 4030 | 2.9 | 5.5 | 3.5 | 5.8 |
| slider | 198 | 8.6 | 41.4 | 10.6 | 41.9 |
| date_picker | 5835 | 18.8 | 93.0 | 17.4 | 93.5 |
| all | 117093 | 16.5 | 93.4 | 12.4 | 93.9 |

`--corrected` takes each text line's background error off first (a state layer or ripple a level or two off): all 93.9 light, 93.9 dark.

## Left

Tooltips (the plain and rich tooltip sit at a fractional x under their anchor, the reference at a whole pixel; the rich title is on-surface-variant
in the reference), the slider's value label, the switch's icon label, the progress bar's buffer label, the navigation bar's badge, the snackbar
two-line cell and the date picker's weekday row (the spec-written CSS sets 400 where the look uses label-medium) are control or reference
differences, not the rasteriser. The primary-tab disabled cell: Material Web does not dim a disabled tab. Glyphs where the hinter differs from
DirectWrite by a sixth of a pixel: `a` at 14 px medium (84 %), `` ` ``, `^`, `*`.
