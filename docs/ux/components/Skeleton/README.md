# Skeleton

A skeleton is a still or softly shimmering placeholder in the shape of content that is loading, so the layout is stable and people can see what is coming.

## Anatomy
1. Block: a filled shape in `surface-container-highest`: a line (text), a circle (avatar), a rectangle (media), a pill (button).
2. Shimmer: a soft highlight band in `surface-container-high` that sweeps across all blocks together.
3. Region: the container being loaded, marked busy.

## Variants and when to use
| Variant | Shape | Use for |
|---|---|---|
| Text line | `radius-xs`, 12 to 16 tall (the text's x-height band, not its line height) | Headlines and body lines; last line of a paragraph 60% wide. |
| Circle | 50% radius | Avatars and round icons. |
| Rectangle | the real media's radius | Thumbnails, charts, images; square inside cards that bleed. |
| Pill | `radius-full` | Buttons and chips, when their position matters. |
| Composite | rows or cards built from the above | Lists, cards and tables. |

Use a Progress indicator when the wait has no known shape or is expected to exceed 10 seconds, a Placeholder for a slot that is empty on purpose, and an Empty state once loading finishes with nothing.

## Specs
| Part | Value |
|---|---|
| Fill | `surface-container-highest` (on `surface` and `surface-container-low`); on `surface-container-highest` grounds use `surface-container-lowest` |
| Shimmer band | `surface-container-high`, 40% of the region wide, angled 10°, linear sweep start to end |
| Shimmer timing | 1.5 s per sweep with `ease-linear`, 0.5 s pause, all blocks in sync |
| Text lines | heights 14 (`body-large`/`body-medium` headline), 12 (supporting); gap `space-2` 8 |
| Line widths | first lines 55 to 100%, varied per row; last line 40 to 60% |
| Shapes | match the loaded component exactly: avatar 40, list rows 72, card media 112 to 160, buttons 40 |
| Count | enough rows to fill the visible region, no more (typically 3 to 8) |
| Delay | show only after 300 ms; once shown, keep for at least 500 ms |

## States
- Waiting (under 300 ms): nothing is drawn; most loads finish here.
- Loading: blocks with the shimmer.
- Reduced motion: blocks without the shimmer (no pulsing either).
- Partial: loaded items replace skeletons in place, one by one, cross-fading `duration-short-4`; the rest keep shimmering.
- Failed: skeletons are replaced by an inline error (Banner or Empty state with Retry), never left shimmering.

## Behaviour
- Skeletons are not interactive: no hover, focus or press; the region is skipped by Tab until content arrives.
- Keep the layout identical between skeleton and content so nothing jumps when data arrives.
- Scrolling works while skeletons show; skeleton rows at the end of a list stand for the next page.
- Content cross-fades in over `duration-short-4` with `ease-standard`; do not animate blocks growing or sliding.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Same design; in high-contrast mode draw blocks as 1px `outline` rectangles without fill. |
| macOS | Same; the shimmer is subtler (the band at 50% of its usual contrast) to match macOS restraint. |
| Linux | Same. |
| Android | Same; matches the Material shimmer rhythm. |
| iOS | Same; SwiftUI `redacted(.placeholder)` shapes are equivalent; honour Reduce Motion. |
| Web | Same; `aria-busy="true"` on the region; the shimmer is a CSS gradient animation stopped by `prefers-reduced-motion`. |

## Accessibility
- The region is marked busy with an accessible name ("Loading members"); the blocks themselves are hidden from the tree.
- Announce "Loading" once, politely, only if the wait exceeds 2 seconds; announce "Members loaded" (or the count) when done if focus was waiting on it.
- Blocks are decorative: no contrast requirement, but keep them visible against their surface (1.2:1 or more) so the layout reads.
- Reduced motion: no shimmer, no pulsing.

## Content
No text in skeletons. The region's accessible name says what is loading: "Loading members", "Loading build log".

## e.ui today
`control.skeleton` draws a `width` by `height` block in `surface-variant`, `radius-sm`, whose opacity breathes between 0.4 and 1.0 with the caller's `phase`; with reduced motion it stays at 1. It is a Group, Busy, with no name. To reach this design:
- Fill with `surface-container-highest` (today `surface-variant` on `background` is very faint, and at 0.4 opacity nearly vanishes) and drop the opacity pulse.
- Add the synchronised shimmer band driven by `animation`, stopped under reduced motion.
- Add the shape variants (line, circle, rectangle, pill) with their radii, and composite helpers for list rows and cards.
- Name the busy region, hide individual blocks from the tree, and add the 300 ms show delay and 500 ms minimum.
