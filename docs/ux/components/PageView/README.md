# PageView

A page view shows one full-size page at a time from an ordered set and moves between them by swipe, key or button, for onboarding, step-by-step intros and one-at-a-time media.

## Anatomy
1. Viewport: fills its region, clips, `radius-md` when inset in a page (square when full screen).
2. Pages: the app's content, each exactly the viewport's size, laid side by side on a strip.
3. Previous and next buttons (pointer hosts): tonal icon buttons, 40, `space-3` 12 from the edges, vertically centred; shown on hover and focus.
4. Page indicator: a PageIndicator below or overlaid at the bottom, `space-3` 12 away.
5. Focus ring: 3px `focus-ring`, 2px outside the viewport (inset when full bleed).

## Variants and when to use
| Variant | Use for |
|---|---|
| Inset pager | Onboarding or feature intros inside a page: `radius-md`, indicator below. |
| Full-screen pager | Media viewers and first-run flows on compact screens: square, indicator overlaid on a `surface-container-high` pill. |
| Stepped pager | A short linear flow where the last page ends in its action ("Create project") and the next control disappears. |

Use Carousel to browse several items at once with parts of the neighbours visible. Use Tabs when pages have names the person picks from. Use Stepper or Wizard when steps collect input that must be valid before moving on.

## Specs
| Part | Value |
|---|---|
| Viewport | fills its region; `radius-md` 12 inset, `radius-none` full bleed; fill `surface-container-low` or the page's own |
| Page padding | `space-6` 24 (content is the app's; the preview centres an `icon-lg` well, `title-medium` title and `body-medium` text) |
| Previous / next | tonal icon button `control-md` 40 (`secondary-container` / `on-secondary-container`), `icon-md` chevrons, `space-3` from the edges |
| Indicator gap | `space-3` 12 below the viewport, or overlaid `space-4` 16 above the bottom edge |
| Swipe threshold | 50% of the width, or a fling faster than 1000 px/s in the page's direction |
| Settle | `duration-medium-4` with `ease-emphasized-decelerate` after release; back to rest with `ease-standard` |

## States
- At rest: one page; neighbours are laid out off-screen and prebuilt for instant swipes.
- Dragging: the strip follows the finger 1:1; at the first and last page the drag resists (a 30% rubber band) and springs back.
- Settling: the page snaps to the nearest page from the release position and velocity.
- Hover (pointer): previous and next fade in over `duration-short-2`; the next button's state layer shows when hovered.
- Focus: ring round the viewport; the arrow keys turn pages.
- First and last page: the previous (or next) button is hidden, not disabled, so there is nothing dead to press.
- Loading page: the page shows its own skeleton; the pager never blocks a swipe on a slow page.

## Behaviour
- Touch: horizontal drag turns; a vertical drag passes to the page's own scrolling. The gesture locks to one axis after 8 px.
- Pointer: previous and next buttons; trackpad horizontal scroll turns one page per gesture; click-drag with a mouse does not turn (so text on a page stays selectable).
- Keyboard: Left and Right (mirrored in right-to-left) turn one page; Home and End go to the first and last page; Page Up and Page Down also turn. Tab moves into the page's content.
- The page view reports every turn, whatever caused it, once; it never reports a turn to the current page.
- Auto-advance is not part of the page view. If the app adds it, it pauses on hover, on focus and while a screen reader is on, and stops for good after the first manual turn.
- Motion: the strip slides with `duration-medium-4` / `ease-emphasized-decelerate`. Reduced motion: the pages cross-fade in `duration-short-2` with no slide.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Hover arrows as in WinUI FlipView; Left and Right turn; trackpad two-finger swipe turns. |
| macOS | Hover arrows; two-finger swipe on the trackpad turns with the page following the fingers; ⌘Left and ⌘Right go to first and last. |
| Linux | As libadwaita Carousel: swipe on touchscreens and touchpads, arrow buttons on hover. |
| Android | Swipe with ViewPager physics; predictive back leaves the pager, not the previous page; no arrows. |
| iOS | Swipe with paging physics and the rubber band at the ends; the page control below is tappable; no arrows. |
| Web | Scroll-snap strip (`scroll-snap-type: x mandatory`) so native scrolling works; arrows on `(hover: hover)`; `aria-roledescription="carousel"`. |

## Accessibility
- Role region with `aria-roledescription` "carousel" (or group), named by the app ("Welcome"). Each page is a group with `aria-roledescription` "page" and the name "2 of 4" plus its title.
- Turning announces the new page's title politely ("Hear about failures first, 2 of 4").
- Hidden pages are out of the tree and the tab order; only the current page's content is reachable.
- Previous and next buttons are named "Previous page" and "Next page".
- Everything a swipe does, a key and a visible control do too; the indicator is the touch alternative.
- Contrast: arrows are tonal buttons at 4.5:1 on their container; an overlaid indicator sits on its own pill so it holds 3:1 over any page.
- Target: arrows 40 visual in a 48 target (touch hosts that show them), 32 minimum on pointer.
- Reduced motion: cross-fade instead of slide; no auto-advance.

## Content
- One idea per page: a short title (three to five words, sentence case) and one sentence of support.
- The last page's action is a verb for what happens next: "Create project", not "Done" or "Finish".
- Never put essential information only on a later page: a person may skip.

## e.ui today
`collection.page_view` shows the page at `current` alone in a clipped box; a horizontal drag past a quarter of the width, or Left and Right on the focused view, fires `turn`; nothing animates. To reach this design:
- Lay out the neighbours on a strip that follows the drag, and settle with velocity and the 50% threshold instead of jumping on the next frame.
- Add the pointer previous and next buttons (hidden at the ends) and Home, End, Page Up and Page Down.
- Create the swipe state on the first frame; today a drag in the view's first frame turns nothing.
- Stop reporting a turn to `current` itself at the first and last page.
- Name the region and each page ("2 of 4"), and announce turns; today the group has no name.
- Draw the focus ring on the focused view, and cross-fade under reduced motion.
