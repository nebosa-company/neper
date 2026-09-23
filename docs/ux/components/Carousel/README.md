# Carousel

A carousel is a horizontal strip of items that scrolls to browse, sized so the next items peek in from the edge, for a short featured or recent set inside a page: builds, templates, shared files.

## Anatomy
1. Header (optional): a `title-medium` title, then previous and next outlined icon buttons at the end (pointer hosts) or a "Show all" text button (touch).
2. Strip: items side by side, `space-2` 8 apart, scrolling horizontally, `space-4` 16 inset from the page edges.
3. Items: containers `radius-md`, clipping their media; content is an icon or image at the top and a title (`title-medium`) and one line of meta (`body-small`) at the bottom.
4. Small items: the peeking items at the end, 40 to 56 wide, showing their media only.
5. State layer: the item's content colour over the item.
6. Focus ring: 3px `focus-ring`, 2px outside the item.

## Variants and when to use
| Variant | Layout | Use for |
|---|---|---|
| Multi-browse | Large, medium and small items; items grow and shrink as they pass the leading edge | Browsing a set of 5 to 20 visual items on medium and wider screens. |
| Hero | One large item plus one small peek | A featured set on compact screens: templates, onboarding offers. |
| Uncontained | Fixed-width items that clip at the edge | Dense rows of equal items: recent files, people, shared folders. |

Use Page view for one full-size page at a time. Use GridView when the person needs to compare all items at once. Do not put a carousel's items anywhere else only: the "Show all" destination must exist when there are more than the carousel shows.

## Specs
| Part | Value |
|---|---|
| Item radius | `radius-md` 12 |
| Gap | `space-2` 8 |
| Strip inset | `space-4` 16 (compact), `space-6` 24 (medium and up) |
| Item height | 200 default, 160 uncontained, 280 hero on medium and up |
| Large item | 2x the medium; fills what is left after one medium and one small item |
| Medium item | 200 (desktop), fills the remainder on compact |
| Small item | 40 min, 56 max; media only, centred |
| Uncontained item | 120 (compact) to 180 wide |
| Item padding | `space-4` 16 |
| Title / meta | `title-medium` / `body-small`, one line each, ellipsised; on the item's container colour pair |
| Item fills | an image, or a container role with its pair: `primary-container`, `secondary-container`, `tertiary-container`, `surface-container-highest` |
| Header buttons | outlined icon buttons `control-md` 40 (32 dense), `space-2` apart |

Text sits on the item's container, never on top of a photo; for photo items put the title below the media or on a `surface-container-high` strip at the bottom.

## States
- Rest: as laid out; the scroll position snaps so an item starts at the strip inset.
- Hover (pointer): `state-hover` layer on the item; header buttons show their own hover.
- Focus: `state-focus` layer and the outside ring on the focused item.
- Pressed: `state-pressed` layer; on Android a ripple.
- Resizing (multi-browse, while scrolling): items change width continuously between small, medium and large; content fades out below 80 wide.
- Start and end: at the start the previous button is disabled (38%, not focusable); at the end the next button is.
- Loading: items are `nu-skeleton` rectangles of the item size.

## Behaviour
- Touch: horizontal drag scrolls with momentum and snaps to an item edge; vertical drags pass to the page.
- Pointer: previous and next scroll by the visible width less one item; a trackpad scrolls horizontally; Shift+wheel scrolls.
- Keyboard: one tab stop into the strip, landing on the first visible item; Left and Right move focus item by item and scroll it fully into view; Home and End go to the first and last. Enter opens the item. Tab leaves the strip.
- Tapping a small (peeking) item scrolls it to the large position rather than opening it.
- No auto-advance. Carousels never move by themselves.
- Motion: snap and step with `duration-medium-4` and `ease-emphasized-decelerate`; item resizing follows scrolling 1:1. Reduced motion: steps jump without animation and items keep one width (uncontained layout).

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Header step buttons; Shift+wheel and touchpad scroll; density -1 header buttons (32). |
| macOS | Header step buttons; two-finger horizontal scroll with elastic ends. |
| Linux | Header step buttons; touchpad scroll; libadwaita apps may prefer uncontained. |
| Android | Hero or multi-browse by width; momentum with snapping; "Show all" in the header; ripple. |
| iOS | Uncontained or hero with paging-like snapping; "See all" in the header, per iOS convention; context menu on long press. |
| Web | CSS scroll-snap (`scroll-snap-type: x mandatory`), header buttons on `(hover: hover)`, a list of links inside a labelled region. |

## Accessibility
- Role region with `aria-roledescription` "carousel", named by the header title ("Recent builds"). Items are a list; each item is a list item (or group with `aria-roledescription` "item") named by its title and meta.
- All items stay in the tree, including those scrolled off; moving focus scrolls them in. Small items report their full name too.
- Header buttons: "Previous builds" and "Next builds" (name what they scroll).
- Contrast: titles and meta 4.5:1 on their container; image items carry text outside the image.
- Target: items far above 48; small items are at least 40 wide and 48 tall.
- Reduced motion: no resizing, no animated steps.

## Content
- Header: a plural noun phrase: "Recent builds", "Templates", "Shared with you".
- Item title: the thing's name, one line: "Build 4128 · main". Meta: one fact: "Passed on 3 targets · 6 min ago".
- "Show all" (Android, desktop) or "See all" (iOS), never "More".

## e.ui today
`collection.carousel` puts a `page_view` between plain "<" and ">" buttons with a `page_indicator` below: one page at a time, turning by swipe, button, dot or arrow key. To reach this design:
- Replace the page-at-a-time layout with a scrolling strip of items (multi-browse, hero, uncontained) that snaps to item edges, and move single-page behaviour to Page view.
- Move the step buttons into a header as outlined icon buttons named "Previous builds"/"Next builds"; today they are the literal glyphs "<" and ">" in the accessible tree.
- Drop the page indicator; position is shown by the peeking items.
- Give the region a label and items names; today the carousel has no node or label of its own.
- Add item states (hover, focus ring, pressed), keyboard focus movement between items, and disabled ends at 38% rather than half opacity.
