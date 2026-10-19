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
- Curves (measured by rendering synthetic one-contour fonts through GDI: 3780 of 3780 straight-edged glyphs are exact, so only conics
  deviate from the exact quadratic). Units are base units (bu), 1/64 sample, x26.6 * 6 in x. (a) A conic that is not monotone on an axis is
  cut at the exact turning point t*, and the turning point and the two new control points are rounded to whole bu (the control coordinate
  on the cut axis equals the turning point's): 98.9 % of 3780 domes with feet of unequal height, against 92.5 % for the exact curve. (b) A
  big conic is scanned on a coarser grid: with bits = bitlength(twice the area of the triangle of its three points) + bitlength(x3 - x1),
  both in bu, the grid is 2^level bu, level = (bits - 26) / 3 when bits is 29 or more, else none. Level 1 moves only y; level 2 and up also
  x, each along the direction the conic runs: the first point goes to the nearest multiple (a tie down), the other two to the nearest
  multiple of their distance from the first (a tie up). Fitted conics are right in 99.6 % of 485 at 29 to 31 bits, 97.7 % of 488 at 32.
  In the six by five path the same rule on y in bu of the 1/5 row grid is a net gain but not exact (see below).
- Hinting (`tthint.e`): the font's own programs run in ClearType mode with the rules of Microsoft's "Backwards compatibility of TrueType
  instructions with ClearType" note: x moves are on a 1/16 pixel grid, x `DELTAP` and `SHPIX` of a pixel or more are ignored (a delta
  function is recognised by its signature), `GETINFO` answers the ClearType and symmetric smoothing bits, the freedom vector says which
  direction is x. Storage 22 and 24 bypass the legacy Talk functions.
- Advance fit: GDI's ClearType pen advance is the `hdmx` advance A (the rounded scaled advance); the scaled advance X is rounded to 1/16.
  At `IUP[x]` (or, for a glyph whose program never reaches it, when the glyph is drawn: the tap fonts then read it unfitted) the points
  that x instructions touched move by the difference spread over the glyph:
  - a stem (a MIRP or MSIRP pair that is not a height) by round(centre * (A - X) / X), ties down, both points the same; IP by the shifts
    of its two references interpolated by the unhinted x and cut towards zero; the right phantom point never moves by x moves;
  - a point that MDRP, ALIGNRP or SHP sets against another takes that one's shift, and the first point it was set against is the one it
    keeps (a later instruction, or an IP after one of these, changes nothing);
  - a diagonal measure (an MDRP along x whose projection is not along x) leaves its point out of the following: it gets the shift of
    the nearest points on its contour that were placed by something other than IP (all the IP'd ones when there are none), interpolated by
    the unscaled x;
  - an instruction that moves, along a projection that is not y, a point that already has followers (the diagonal MIRP of `< > 4`, or an
    ALIGNRP that would make a reference follow its follower) switches the glyph to the other rule: every point that follows another moves
    by round(x * (A - X) / X) at its own x, and the points nothing was set against keep 0.
  - A composite component is fitted to the device advance of the top glyph (its offset rounds to 1/16 in x); its right phantom point
    carries round(own advance * (A - X) / X) and IP interpolates over the component's own span.
- Distances along any projection but y round, limit (cut-in) and keep their minimum on the 1/16 pixel grid, not only along x.
- The hinted points are checked against `GetGlyphOutline` in black and white (the whole-pixel machine) and against the ClearType machine
  through the tap fonts in `scripts/winnative/tap*.py`: copies of the font whose programs write the `GC` reading of every point into
  storage and show it as bits, cut after K instructions or after `IUP[x]`.
- Status (non-probe atlases, 190 ink glyphs each, `text_cleartype_oracle --report`): pixel-identical for 5105 of 5292
  glyphs (189 per atlas), 96.5 %. Per atlas: 95 % or more for 21 of 28; below 95 %: Tahoma regular 13 and 16 px 94.2 and 94.7 %, Tahoma
  Bold 14 and 21 px 94.2 %, and the large sizes, Segoe UI 24 px 82.5 % (Bold 89.4 %) and Tahoma 21 px 88.4 %. The
  ClearType points equal GDI's tap-font points for 5238 of 5285 glyphs (99.1 %); the black-and-white outline and advance match for 99 %.
- What is left: (1) 47 glyphs whose hinted points differ, in a dozen programs: `$ f x` of Tahoma (a pair taking its shift from a
  follower of an IP'd point; `f`, whose top arc is fitted by rules not found), Segoe UI Bold `A` at 14, 18 and 24 px and its accents
  (the interpolation of a diagonally measured point is off by one at those sizes), `#`, `s`, `m`. (2) About 100 hinted glyphs whose points
  are right and whose pixels differ by one sample at the extreme of a bowl: the coarse-grid rule above is a soft fit (the cross product
  alone is right for about 92 % of conics, the bit-length sum for 99.6 %), and a few conics with the same bit sum go either way
  (Tahoma regular 21 px: conic 162 is coarsened, conic 182 is not). Flattening by uniform or adaptive chords, FreeType 1's halving, t
  quantising, vertex rounding, crossing bias, row-boundary chords and global offsets each lost 300 to 3700 of 3780 synthetic glyphs.
  (3) The six by five path at Segoe UI 24 and Tahoma 21 (86 glyphs): the rule is applied with y in bu of the 1/5 row grid; it gains 33
  glyphs and loses 15 that the exact curve had right (listed as changed in exact.txt), conics running opposite in x and y at level 2 mostly.
  Offsets of 1 to 4 bits on the criterion, caps on the level, the x frame of the move and tie flips did not help; scaling the grid to
  whole 1/5 rows lost 24 more.
