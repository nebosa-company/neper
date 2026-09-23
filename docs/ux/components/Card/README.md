# Card

A card is a container for one self-contained item (a project, a build, a release) that groups its title, content and actions and can open it as a whole.

## Anatomy
1. Container: `radius-md`, padding `space-4`, one of three treatments.
2. Optional media: full-bleed at the top, clipped by the container's corners, 16:9 or a fixed 96-160 height.
3. Header: optional avatar or icon (24-40), `title-medium` title, optional trailing Icon button (more).
4. Supporting text: `body-medium` `on-surface-variant`, 1-3 lines.
5. Meta: `label-small` `on-surface-variant` (time, owner, status label).
6. Actions: text and tonal buttons at the end, `space-2` apart.
7. State layer, focus ring and selection check, when the card is pressable or selectable.

## Variants and when to use
| Variant | Container | Use for |
|---|---|---|
| Elevated | `surface-container-low` + `elevation-1` | Cards on a busy or patterned ground, or where one card must lift out of a group. |
| Filled | `surface-container-highest`, no shadow | Cards in a dense grid, dashboards, the default on pointer hosts. |
| Outlined | `surface` + 1 px `outline-variant` | Cards next to other filled regions; lists of settings or options; media cards. |

For items that are rows of the same shape use List. For a labelled set of controls use Group box. For a region of a window use a Pane or Surface. Don't put a card inside a card.

## Specs
| Part | Value |
|---|---|
| Radius | `radius-md` 12 (`radius-sm` 8 for cards under 120 wide) |
| Padding | `space-4` 16; `space-3` 12 in dense grids |
| Gap between cards | `space-4` 16 in grids, `space-2` 8 in dense grids |
| Header | avatar/icon 24-40, `space-3` gap, title `title-medium` 16/24 `on-surface`, one line, ellipsis |
| Supporting | `body-medium` 14/20 `on-surface-variant`, max 3 lines, `space-1`-`space-2` below the title |
| Meta | `label-small` 11/16 `on-surface-variant`, `space-3` above |
| Media | full-bleed top, `radius-none` inside, height 96-160 or 16:9, `space-4` below |
| Actions | end-aligned, `space-2` apart, `space-2` above; text buttons, one tonal or filled at most |
| Width | 200 minimum, 360 maximum in a grid; cards stretch to fill columns |
| Elevated shadow | `elevation-1` rest, `elevation-2` hover, `elevation-4` dragged |
| Selected | 2 px `primary` outline inside the edge, 24 `primary` check disc at the top end, `space-2` in |

## States
- Hover: `on-surface` state layer at `state-hover`; elevated cards rise to `elevation-2`, filled and outlined to `elevation-1`.
- Focus: `state-focus` layer and the focus ring, 3 px `focus-ring`, 2 px outside.
- Pressed: `state-pressed` layer; ripple from the touch point on touch hosts.
- Dragged: `state-dragged` layer, `elevation-4`, tilted 1.5 degrees and scaled to 102%.
- Selected: the `primary` outline and check; the rest of the look is kept so selection reads without colour.
- Disabled: container `on-surface` 12%, content 38%, no shadow, not focusable.
- Loading: skeletons for the title (60%), one supporting line (90%) and media.

## Behaviour
- A pressable card has one primary action: the whole card opens the item. Buttons inside it are separate targets and keep their own states; the card's layer does not show while a child is hovered.
- Keyboard: Tab focuses the card, Enter opens it, Tab again reaches its buttons. In a grid of cards, arrows move between cards (roving focus), Home and End go to the first and last, and Tab leaves the grid.
- Selection mode: Space toggles the focused card; a long press on touch enters selection mode; Ctrl/Cmd+click toggles, Shift+click selects a range.
- Drag to reorder: long press (touch) or press and move 4 px (pointer) lifts the card; Escape cancels and the card returns over `duration-medium-1` with `ease-standard`.
- Opening a card may expand it into the detail view with a container transform over `duration-long-2` with `ease-emphasized-decelerate`; reduced motion cross-fades.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Filled as the default; padding `space-4`, hover elevation only on pressable cards; right-click opens the card's context menu. |
| macOS | Filled or outlined, never elevated on a plain window ground (AppKit prefers flat grouped surfaces); ⌘-click toggles selection. |
| Linux | Outlined on GNOME (Adwaita "card" style), filled on KDE; right-click opens the context menu. |
| Android | Elevated or filled; ripple; long press enters selection mode. |
| iOS | Filled with `radius-md`; no shadow; long press shows a context menu with a preview; swipe actions are for lists, not cards. |
| Web | A real `<a>` or `<button>` covers the card for the primary action; nested buttons stay reachable; `:focus-visible` ring. |

## Accessibility
- A static card is a Group named by its title.
- A pressable card is one Link or Button named by its title, with the supporting text as description; its inner buttons are siblings in reading order, never nested inside the card's control.
- Selectable cards report Selected; the check is decorative.
- Contrast: text meets 4.5:1 on each container; the outlined card's edge is decorative (`outline-variant`), so the card must not depend on it to be found.
- Target: the whole card, at least 48 tall.
- Reduced motion: no tilt, no container transform, no rise on hover.

## Content
- Title: the item's name, sentence case, no period: "Release 2.4".
- Supporting text: one or two short sentences with the fact that matters: "Tag v2.4.0 is ready to publish."
- Actions are verbs: "Publish", "View changes". No "Read more": the card itself opens.

## e.ui today
`control.card` is a `surface` at `elevation` 1 with `radius-md`, `space-md` padding and a hairline `border`, children in a column; `panel` is its flat bordered sibling on `SurfaceVariant`. To reach this design:
- Add the three variants (elevated, filled, outlined) on the `surface-container*` roles; today a card is both shadowed and bordered.
- Add a pressable card with state layers, the focus ring and one action, and a selectable card with the check and Selected state.
- Add media, header and actions slots so cards share one layout, with `space-4` padding and `space-2` action gaps.
- Add the dragged look for reordering in grids.
- Report a Group named by the title (static) or a Button/Link (pressable); today a card is an unnamed box in the tree.
