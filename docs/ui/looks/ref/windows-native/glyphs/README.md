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

- Rasteriser (`cleartype.e`): GDI's ClearType is the TrueType scan converter run on a grid six samples wide per pixel (the six-sample window
  of each subpixel gives its coverage, 0..6) and one sample row per pixel row, with the outline curves flattened exactly (a quadratic's x per
  scan line, rounded). Two consecutive off-curve points imply an on-curve midpoint that is rounded on the 1/64 sample grid before the
  curve is drawn (worth 42 glyphs of 756 in the probe atlases). Drop-out control follows the font's scan type (Segoe UI mode 1, Tahoma
  mode 5), a stub is dropped, the bounding box is clamped. Sizes the `gasp` table marks for symmetric smoothing (Segoe UI above 19 ppem,
  Tahoma above 17) are sampled six by five with the vertical weights 1 2 3 2 1 and level (n + 4) / 9.
- Hinting (`tthint.e`): the font's own programs run in ClearType mode with the rules of Microsoft's "Backwards compatibility of TrueType
  instructions with ClearType" note: x moves are on a 1/16 pixel grid, x `DELTAP` and `SHPIX` of a pixel or more are ignored (a delta
  function is recognised by its signature), `GETINFO` answers the ClearType and symmetric smoothing bits, the freedom vector says which
  direction is x. Storage 22 and 24 bypass the legacy Talk functions.
- Advance fit: GDI's ClearType pen advance is the `hdmx` advance A (the rounded scaled advance); the scaled advance X is rounded to 1/16.
  At `IUP[x]` the points that x instructions touched move by the difference spread over the glyph: a stem (MIRP or MSIRP pair) by
  round(centre * (A - X) / X), IP by the interpolated shifts of its two references (settled after the whole program, so a reference that a
  later MIRP pairs counts with its final shift), a point that MDRP, ALIGNRP or SHP set against another with that one's shift, the right
  phantom never moved by x moves. A composite component is fitted to the device advance of the top glyph (its offset rounds to 1/16 in x).
- The hinted points are checked against `GetGlyphOutline` in black and white (the whole-pixel machine) and against the ClearType machine
  through the tap fonts in `scripts/winnative/tap*.py`: copies of the font whose programs write the `GC` reading of every point into
  storage and show it as bits, cut after K instructions or after `IUP[x]`.
- Status at the end of round 23 (non-probe atlases, 189 ink glyphs each): pixel-identical for Segoe UI regular 11 to 18 px 91.5 to 97.9 %
  (24 px 72.5 %), Segoe UI bold 86 to 95 % (24 px 75.7 %), Tahoma regular 78 to 88 % (21 px 79.4 %), Tahoma bold 77 to 86 % (21 px
  84.7 %); 86.9 % over the 28 atlases, 4601 of 5292. ClearType points equal GDI's for 10566 of 12082 glyphs; the black-and-white outline
  and advance already match for 99 %. Fed GDI's own hinted points, the rasteriser alone reproduces 97.5 % of the glyphs at 11 to 18 px
  and 76 % at 24 and 21 px, so the first cap is the hinter.
- What blocks 95 %: (1) the x fit of single touched points. A point that MDAP rounds alone shifts by 0, but a point that ALIGNRP, SHP or
  MDRP sets against it sometimes shifts in proportion to its own position (`<`, `>`: 15 of A - X = 17 at x = 480) and sometimes with the
  group of its reference (`#`: both bars 17 and 0), and the instruction order in the programs does not tell which; the stem-centre rule
  fits `H`, `o`, `A` and most letters but not `# $ 4 6 Z z { }`. (2) The six by five path at Segoe UI 24 and Tahoma 21: a pure function of
  the five line levels leaves 0.17 % of the cells wrong, so one glyph in four has a cell off. (3) Accented composites of Segoe UI bold.
