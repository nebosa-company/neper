# GDI ClearType glyph oracle

Every code 32..255 of Segoe UI and Tahoma, regular (400) and bold (700), drawn by real GDI `TextOutW` into a 32-bit DIB with the
machine's ClearType settings (`settings.txt`), at the pixel sizes the Windows looks use. Made by `scripts/winnative/glyphs.ps1`
(`glyphs.c`, `glyphs_finish.py`); no window is shown and no input is used. Re-run it on a machine with the same fonts; the files are
rewritten wholesale.

- `<face>-<weight>-<px>-q5.<fg>-<bg>.png`: a 16 x 14 atlas, code 32 at the top left, row-major. `atlases.txt` lists each atlas as
  `name w h cell_w cell_h ascent pad` (cell_w = widest advance + 2 pad, cell_h = tmHeight + 2 pad, pad = 6). A glyph is drawn with
  `TextOutW(x = col * cell_w + pad, y = row * cell_h + pad)` (top left alignment), so its pen is at x + 0 and its baseline row is
  `y + ascent`. The background is filled with `bg`, the text mode is TRANSPARENT, `fg` is `SetTextColor`. Black on white and white on
  black for every size; white on `202020`, black and `6D6D6D` on `F0F0F0`, white on `0078D7` for Segoe UI 12 and Tahoma 11 regular.
- `<face>-<weight>-<px>-q5.outline.gz`: one line per glyph, integers in 26.6 pixels, y up, x from the pen:
  `code adv a b c bbx bby orgx orgy ncont { npts { x y on } }` where `adv` is `gmCellIncX` (the hinted whole-pixel advance) and `a b c` are
  the ABC widths. These are `GetGlyphOutline(GGO_NATIVE)` outlines, which GDI hints with the **black-and-white** machine whatever the
  font's quality (the same numbers come back for quality 3, 4, 5 and 6), so they are the truth for the black-and-white interpreter and the
  advances, not for the ClearType outline. The ClearType outline is not exposed by any GDI call; its truth is the pixel atlases.
- `blend.q5.png`, `blend.q6.png`: "Wo" in Segoe UI 24 px for grey text 0, 16, ... 255 (rows) on grey backgrounds 0, 16, ... 255
  (columns), 28 x 36 cells. `blend2.q5.png`: "W" with 256 rows (the varied grey) and four 24 x 32 columns: text 0..255 on 0, text 0..255
  on 255, background 0..255 under text 0, background 0..255 under text 255. `settings.txt`: the machine's smoothing settings.
- `exact.txt`: per atlas, 224 marks (code 32 first) of the glyphs whose pixels the Neper pipeline reproduces (no channel more than 2 levels
  off), a space, and 224 marks of the glyphs whose black-and-white outline and advance match `GetGlyphOutline`. The regression test
  (`tests/selfhost/fixtures/link/text_cleartype_oracle`) fails when a marked glyph stops matching; `--write-exact` rewrites the file
  after an improvement.

Facts measured on the way (Windows 11 build 26300): lfQuality 0 (the message font's DEFAULT_QUALITY) draws the same bytes as 5
(CLEARTYPE_QUALITY); 4 (ANTIALIASED) and 6 (CLEARTYPE_NATURAL) differ. `TextOutW` of "Static text label" in Segoe UI 12 white on `202020`
matches the native dark `label-rest@1x` capture to within 1 level per channel, so the oracle is what the captures show. The ClearType
contrast is 1200 (`SPI_GETFONTSMOOTHINGCONTRAST`, registry `FontSmoothingGamma` 0 = default), orientation RGB; this is the 1.2 of the
gamma blend in `e.gfx.cleartype`.

The blend is exact (`scripts/winnative/glyphs_blend_check.py`: 0 of 35 million samples off): per channel, background and text go through
an 8-bit table (255 * (i / 255) ^ 1.2, rounded), are mixed with a = round(65536 * k / 6) / 65536 where k is the coverage in sixths
(a channel has seven levels, so black on white shows 255 219 182 144 102 58 0), rounded to a byte and sent back through the inverse
table; a pixel no channel covers is left alone, a covered pixel's uncovered channel still goes through the tables (64 comes out 65).
The odd-k ties round the way they do because of the 16.16 fraction.

Model the Neper pipeline fits to these atlases (`lib/e/text/tthint.e`, `ttglyph.e`, `lib/e/gfx/cleartype.e`):

- GDI's ClearType pen advance is the font's `hdmx` advance, and hinting runs at the fonts' own sizes with x fitting added at `IUP[x]`
  (per-point whole-pixel shifts that spread the difference between the `hdmx` advance and the rounded scaled advance over the glyph:
  IP interpolates its reference shifts, pairs take the centre rule or follow a shifted reference, `SHPIX` of a pixel or more is ignored,
  the right phantom is never moved by x moves, x `DELTAP` is ignored). `Outline.adv` is that advance.
- A glyph whose program ran is sampled on one line per pixel row (y + 0.5) with six samples per pixel; a channel's coverage level is the
  number of samples in its six-sample window. A glyph without a program (the NProbe fonts) is sampled on five weighted lines instead.
- The hinted points are checked against `GetGlyphOutline` in black and white (the whole-pixel machine) and against the ClearType machine
  through the tap fonts in `scripts/winnative/tap*.py`: copies of the font whose programs write the `GC` reading of every point into
  storage and show it as bits, cut after K instructions or after `IUP[x]`.
- Status at the end of round 22 (non-probe atlases): 4830 of 14144 ink glyphs pixel-identical, ClearType points equal to GDI's for
  7188 of 12082 glyphs; the black-and-white outline and advance already match for 99%. Open: Segoe UI 24 (the stem is not rounded), Tahoma
  (single-point y differences of 16 to 64 and x on `# f L ] r X { }`), composites (no fitting), `&PRUcm~` at Segoe UI 12.
