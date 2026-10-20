# Cover

A cover is the large brand banner at the top of a landing page, a gallery or an empty product shell: an illustration in the system's own shapes on one side, the product name and one line of tagline on the other.

## Anatomy
1. Container: 960 by 288, clipped, on `surface`.
2. Art: a 480 by 288 panel on the right half, hidden from assistive technology.
3. Name: `display` face, 88 high, weight 600, `on-surface`, bottom-left, `space-6` from the edges.
4. Tagline: `body-medium` in `font-sans`, `on-surface-variant`, one line under the name.

## Art
The art is built from the system's own blocks, so it follows every theme:
- One tall `primary` slab, 168 by 232, bled off the top.
- A `primary-container` block, 144 by 152, stepping right from it.
- A `brand-ink` block, 160 by 200, bled off the right edge.
- One `tertiary` disc, 64 across, used once as the warm counter-accent.
- Pills (`radius-full`, 40 or 32 tall) cut into the slab in `on-primary` and laid on the tint in `on-primary-container`, at a `space-12` pitch.

Blocks use `radius-xl`; gutters are `space-3`; every side is a multiple of `space-2`. About 45% of the panel is covered, with the bottoms on one line `space-6` above the edge.

## Specs
| Part | Value |
|---|---|
| Size | 960 by 288 (the art keeps 480 by 288 at any width) |
| Name | 88 / 0.92 line height, weight 600, letter spacing -0.02em |
| Tagline | 14 / 20, letter spacing 0.25, 3 left offset to optically align with the name |
| Text block | at most 440 wide, `space-6` from the left and bottom |
| Background | `surface` |

## Behaviour
- Static: no hover, press or focus state. The cover is not interactive.
- Narrow widths: the art drops below the text block and keeps its aspect ratio; the name steps down through `display` sizes rather than wrapping a word.

## Accessibility
- The art is decorative and hidden from the accessibility tree.
- The name is the page's heading; the tagline is its description.
- Name and tagline meet 4.5:1 on `surface` in every theme.

## Content
Name the product in one or two words. The tagline is one sentence, no full stop needed, and says what the product does, not how good it is.
