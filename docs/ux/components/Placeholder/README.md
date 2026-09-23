# Placeholder

A placeholder is a neutral shape that stands in for a piece of content that is still loading: a line of text, an image or an avatar. It has the content's exact size, so the layout does not move when the content arrives.

## Anatomy
1. Shape: a text line (12 tall, fully rounded), a block (the content's own radius), or a circle.
2. Fill: `surface-container-highest`.
3. Sweep: a soft band of `surface-container-high` that passes across all the placeholders of a region together.
4. Region: the container being loaded (list, card, pane). It owns the Busy state and the name, and the shapes carry none.

## Variants and when to use
| Variant | Size | Use for |
|---|---|---|
| Text line | the line's cap height to x-height: 12 for `body-medium` and `body-large`, 16 for titles, 10 for `body-small`; width 40% to 100%, varied | Lines of text. The last line of a paragraph is shorter. |
| Block | the image, chart or media's exact size and radius | Thumbnails, charts, card media. |
| Circle | the avatar or icon's size | Avatars (40), leading icons (24). |
| Composed | a row or card built from the above | Whole list rows and cards. The layout is the real component's, with shapes in its slots. |

Use placeholders for loads expected to take 300 ms to about 5 s where the layout is known. Use a Progress ring or bar when the layout is not known, when the load is longer, or when progress can be measured. Never use them for content that failed (show an error) or that is empty (show an Empty state). For the full-screen pattern of composed placeholders, see Skeleton.

## Specs
| Part | Value |
|---|---|
| Fill | `surface-container-highest` |
| Sweep | a 45% wide gradient band to `surface-container-high`, moving start to end |
| Text line | height 12 (body), 16 (title), 10 (small); `radius-full`; lines 8 apart for `body-medium` (20 line height minus 12) |
| Block radius | the content's own: `radius-md` for cards and thumbnails, `radius-xs` for inline media, 0 for full-bleed media |
| Circle | `radius-full`, the avatar or icon size |
| Count | as many rows as fill the viewport, up to 8. Never an infinite list. |
| Region | no extra padding. The placeholders sit in the real component's padding and slots. |

## States
Loading is the only state. When content arrives, the placeholders cross-fade to it. When the load fails, they are replaced by the region's error. When it succeeds with nothing, they are replaced by the Empty state.

## Behaviour
- Show placeholders only after 300 ms, so fast loads show no flash. Once shown, keep them at least 500 ms.
- The sweep crosses the region every 1.5 s with `ease-standard`, all shapes in step (one band over the region, not one per shape). With reduced motion there is no sweep: the fill pulses between 100% and 60% opacity every 2 s, or stays still.
- Content replaces the placeholders with a `duration-short-4` cross-fade (`ease-standard`). Rows that arrive in order fill in top to bottom.
- Placeholders are not interactive: no hover, no focus, no press. The region's real controls (a toolbar, a search) stay usable.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | The same shapes and sweep (Fluent's shimmer). |
| macOS | The same shapes. Prefer a static pulse, since macOS apps rarely shimmer, and use a ring for loads over 2 s. |
| Linux | The same. GNOME apps often show a spinner instead: use placeholders only where the layout is known. |
| Android | The same, matching Material's loading placeholders. |
| iOS | The same shapes. SwiftUI's redacted look, a static fill, is the native equivalent, so pulse rather than sweep. |
| Web | `aria-busy="true"` on the region, shapes `aria-hidden`, and the sweep as a CSS animation behind `prefers-reduced-motion`. |

## Accessibility
- The region is Busy and named for what is loading ("Loading recent builds"). The shapes are hidden from assistive technology, because a screen reader should not hear 24 empty items.
- When the content arrives, Busy clears and the region's content is read normally. Announce the arrival only if the reader asked for it (a search or refresh), politely ("12 builds").
- Shapes are decorative, so no contrast minimum applies. The fill must still be visible against the surface in high contrast themes, which it is at `surface-container-highest`.
- Reduced motion: no sweep.

## Content
Placeholders carry no text. The region's accessible name says what is loading, in the words the finished content will use: "Loading recent builds", "Loading project". Vary line widths the way real text varies. Don't draw ten identical full-width bars.

## e.ui today
`control.placeholder` is a `width` by `height` block in `surface-variant` with `radius-sm` corners, in a node with the Busy state and no role or label. It does not animate. To reach this design:
- Fill with `surface-container-highest`, and add the text-line (12 and round), circle, and content-radius shapes.
- Add the region-wide sweep, with a pulse or a still fill under reduced motion.
- Move Busy and a name to a region wrapper (`placeholder_region(label, children)`), and hide the individual shapes from the tree. Today each block is an unnamed busy node, so a reader hears only "busy" once per block.
- Add the 300 ms show delay, the 500 ms minimum and the cross-fade to content.
- Document composing placeholders in the real component's slots, which is what Skeleton builds on.
