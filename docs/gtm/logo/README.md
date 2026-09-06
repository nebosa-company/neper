# neper logo

The mark is a lowercase italic **e**: Euler's number, which John Napier — *Neper*
in the Latin his contemporaries used — made reachable through logarithms, and the
extension every neper source file already carries.

The bowl does not close. Its terminal keeps going as a long rising tail — the
exponential curve that is its own derivative — and that tail is the mark's signature.
Both e's in the wordmark carry it too.

It is drawn, not set in a typeface. `build-logo.py` models a broad-nib pen
travelling along a skeleton of lines and arcs, so the mark and the `neper` wordmark
come from one pen: the same weight, the same inclined contrast axis (thin at about
10:30 and 4:30, as an oldstyle italic), the same 12° slant. Nothing depends on a
font being installed, and no font licence is involved.

## Files

| File | Use |
|---|---|
| `neper-lockup.svg` | Primary logo: icon tile plus wordmark. Default choice for a README header, site nav or slide. |
| `neper-mark.svg` | The `e` alone, deep blue on a transparent ground. |
| `neper-mark-mono.svg` | The `e` with `fill="currentColor"` — inline it in HTML/SVG and it takes the surrounding text colour. As an `<img>` it renders black. |
| `neper-mark-small.svg` | The `e` at the icon cut — opened-up hairlines, shorter tail — with no tile. Use it below roughly 48 px: page headers, inline rules, favicons on a light ground. |
| `neper-wordmark.svg` | `neper` alone, without the tile. |
| `neper-icon.svg` | Rounded-square app icon / favicon: the mark reversed out of the ink tile, drawn with a lower-contrast pen and a shorter, blunter tail so both survive at icon sizes. |
| `*.png` | Raster copies of the mark, icon and lockup for contexts that reject SVG. |

## Palette

| Role | Value |
|---|---|
| Ink | `#1B3A6B` |
| Paper | `#FFFFFF` |

The ink is the same blue the generated documentation uses for headings, so
`docs/neper.pdf` and the logo sit in one family. One colour is deliberate: the mark
has to survive a favicon, an embroidered patch and a single-colour print.

## Using it

- **Clear space:** keep a margin of at least half the mark's height on every side.
- **Minimum size:** the mark reads down to about 24 px. Below roughly 48 px use
  `neper-mark-small.svg`, or `neper-icon.svg` where a tile suits — the display cut's
  hairlines disappear at those sizes.
- **Dark backgrounds:** inline `neper-mark-mono.svg` and set `color`, or use the
  icon tile, which carries its own ground.
- **Don't** re-slant, outline, add a gradient or a shadow, recolour the tile and
  glyph independently, or set the wordmark in a substitute italic font. Regenerate
  from the script instead.

## Regenerating

```bash
python docs/gtm/logo/build-logo.py
```

Standard library only — no virtual environment needed, including for the PNGs,
which come from a small scanline rasteriser in the same script. Proportions live in
named constants at the top of the file: `PEN` and `PEN_SMALL` (weight, contrast, nib
angle, slant), `SWASH` and `SWASH_SMALL` (the tail's reach, rise and end width), the
`XTOP`/`BASE`/`DESC` writing grid, and `gap` for letter spacing. Change one and
every asset stays consistent.

The wordmark is spaced on one constant gap between the letters' ink, measured with
each tail excluded, so the rhythm stays even. Each tail then overlaps the letter
after it, and its reach is solved so the tip lands halfway into that letter's stem —
an italic join. Retune `SWASH` and the joins re-solve; the spacing does not move.
