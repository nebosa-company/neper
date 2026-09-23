# PageIndicator

A page indicator shows how many pages a Page view or Carousel has and which one is showing, and lets the person step or scrub to another.

## Anatomy
1. Track: one control, `radius-full`, 32 tall on pointer hosts and 48 on touch; transparent, or a `surface-container-high` pill over media.
2. Dots: 8 circles in `outline`, `space-2` 8 apart.
3. Current: a 24 by 8 pill in `primary`, so position reads by shape as well as colour.
4. Edge dots (more than 7 pages): the two outermost visible dots shrink to 6 and 4 to show the set continues.
5. State layer: `on-surface` over the whole track.
6. Focus ring: 3px `focus-ring`, 2px outside the track.

## Variants and when to use
| Variant | Use for |
|---|---|
| Plain | Under an inset Page view or a Carousel, on a surface. |
| On media | Overlaid on a full-bleed image or page: the track takes a `surface-container-high` pill so dots hold contrast over any content. |
| Scrolling | More than 7 pages: 7 dots visible, the window slides so the current pill stays inside, edge dots shrink. |

Use Pagination when there are more than about 10 pages or people need page numbers. Use Tabs when pages have names. A page indicator is not a progress bar: use Progress bar or Stepper for a task's progress.

## Specs
| Part | Touch | Pointer |
|---|---|---|
| Track height | `target-touch` 48 | `target-pointer` 32 |
| Track padding | `space-4` 16 sides | `space-3` 12 sides |
| Dot | 8 circle, `outline` | same |
| Current | 24 by 8, `radius-full`, `primary` | same |
| Gap | `space-2` 8 | same |
| Edge dots | 6 and 4 | same |
| On-media pill | `control-sm` 32 tall, `surface-container-high`, `radius-full` | same |
| Visible dots | at most 7 | at most 7 |

## States
- Rest: as above.
- Hover: `state-hover` layer over the track (pointer hosts).
- Focus: `state-focus` layer plus the outside ring.
- Pressed: `state-pressed` layer while the finger or button is down; the current pill follows a scrub.
- Disabled (the pager cannot turn, e.g. while a page saves): dots and pill at `on-surface` 38%, not focusable.
- Changing: the pill slides and stretches between dots over `duration-medium-2` with `ease-standard`, keeping pace with the page view's settle.

## Behaviour
- The whole track is one target. A tap or click before the current pill steps back one page, after it steps forward one. It never jumps several pages on a tap: dots are too small to aim at.
- Drag along the track (touch) or press and drag (pointer) scrubs: the current page follows the pointer dot by dot, with a haptic tick per page on Android and iOS.
- Keyboard: one tab stop. Left and Right (mirrored in right-to-left) step; Home and End go to the first and last page; Page Up and Page Down also step.
- With more than 7 pages the visible window scrolls by one dot when the pill would reach the edge dots.
- Reduced motion: the pill moves without the stretch, cross-fading in `duration-short-2`.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Pointer metrics (32); shown beneath FlipView-style pagers; hover state layer. |
| macOS | Pointer metrics; trackpad horizontal scroll over the track steps pages. |
| Linux | Pointer metrics; matches libadwaita CarouselIndicatorDots (with the pill for current, where libadwaita uses opacity). |
| Android | Touch metrics (48); scrub with haptics; plain variant under pagers. |
| iOS | Touch metrics (44pt minimum); behaves as UIPageControl: tap to step, drag to scrub, the pill for current; on media, the pill background. |
| Web | Pointer metrics with a fine pointer, 48 with a coarse one; `role="slider"` with `aria-valuetext`; Left and Right keys. |

## Accessibility
- Role slider (adjustable on iOS), named "Page", with value min 1, max = count, and value text "Page 2 of 5". A page view that also has previous and next buttons keeps the indicator in the tree.
- Actions: Increment and Decrement step pages; screen reader swipe up and down on the adjustable element works on iOS and Android.
- Announces the new value politely on change.
- Contrast: dots in `outline` hold 3:1 on `surface` and on the on-media pill; the current pill in `primary` holds 3:1 too, and differs in shape.
- Target: the track, never a single dot: 48 touch, 32 pointer.
- Reduced motion: no stretch animation.

## Content
- No text in the control. The accessible value is "Page 2 of 5"; name the pages themselves on the Page view.

## e.ui today
`collection.page_indicator` draws a `space-sm` dot per page, the current in `primary` and the rest in `border`, each a separate focusable tab with a `space-lg` (24) hit area that fires `turn` on tap, Enter or Space. To reach this design:
- Make it one control: a 32 or 48 track with a single tab stop, tap-to-step on either side of the current pill, drag to scrub, and Left, Right, Home and End.
- Draw the current page as a 24 pill in `primary`, dots in `outline`, and animate the pill between dots.
- Add the state layers and the focus ring; today the dots are focusable but paint no focus.
- Replace the per-dot tabs (no labels, no arrow keys, a 24 target under the 32 minimum) with a slider role and "Page 2 of 5" value text.
- Add the scrolling window with shrinking edge dots for more than 7 pages, and the on-media pill.
