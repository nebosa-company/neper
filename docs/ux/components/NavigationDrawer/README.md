# NavigationDrawer

A navigation drawer is a side sheet of destinations: modal, sliding over a scrim from the start edge when the window cannot spare the width, or standard, sitting permanently beside the content (and collapsible) when it can.

## Anatomy
1. Container: `surface-container-low`; modal has `radius-lg` on its open (end) corners and `elevation-1`; standard is square with no shadow.
2. Header (optional): the app or workspace name in `title-small` `on-surface-variant`, or an account switcher.
3. Destination: a 56-tall row (40 at pointer density) with a 24 icon, a `label-large` label and an optional trailing count.
4. Active indicator: the whole row in `secondary-container`, `radius-full`.
5. Section heading and divider: group secondary destinations ("Teams").
6. Scrim (modal only): `scrim` at `scrim-opacity` 32% over the content.

## Variants and when to use
| Variant | Use for |
|---|---|
| Modal | Compact and medium windows: opened from the app bar's `menu` button or the rail's; also for secondary destinations that do not fit a navigation bar. Closes after a pick. |
| Standard | Expanded and large windows: permanently beside the content; the user can hide it (it collapses to nothing or to the rail). This is DestinationBar's sidebar form with sections. |

Three to five top-level places on compact windows belong in a navigation bar (DestinationBar) rather than a drawer: a drawer hides them. A panel of settings or details is a Sheet, not a drawer. Tool windows are DockPanels.

## Specs
| Part | Modal | Standard (pointer) | Standard (touch) |
|---|---|---|---|
| Width | 256-360 (`nav-drawer`), at most window width - 56 | 200-280, user-resizable | 256-360 |
| Container | `surface-container-low`, end corners `radius-lg`, `elevation-1` | `surface-container-low`, square, no shadow | same |
| Padding | `space-3` 12 | `space-2` 8 | 12 |
| Header | `title-small` 14/20 600, `on-surface-variant`, 16 sides, 16 top, 12 bottom | 12 top, 8 bottom | as modal |
| Row | `control-xl` 56, 16 start, 24 end, `radius-full`, gap 12 | `control-md` 40, 12 sides | 56 |
| Icon | 24, `on-surface-variant`; active `on-secondary-container` | same | same |
| Label | `label-large` 14/20 600, `on-surface-variant`; active `on-secondary-container` | same | same |
| Count | `label-large`, end-aligned, same colour as the label | same | same |
| Section heading | `label-medium` 12/16 600, `on-surface-variant`, 16 sides, 16 top, 8 bottom | same | same |
| Divider | 1 `outline-variant`, 16 sides, 8 vertical | same | same |
| Scrim | `scrim` 32% | none | none |
| Hover / pressed | state layer on the row | same | pressed only |
| Focus | ring inset 3px on the row | same | same |

## States
- Modal: closed (off-screen), opening, open, closing; dragging (follows the finger, scrim opacity tracks the position).
- Standard: shown, hidden (collapsed to zero or to the rail), resizing (a sash on its end edge).
- Row: rest, hover, focus, pressed, active, disabled (38%, rare: prefer hiding a destination the user can never reach).

## Behaviour
- Modal opens from the `menu` button, a swipe from the start edge (touch; not where it conflicts with the system back gesture), or Ctrl+Shift+E on pointer hosts. It closes on a pick, a press on the scrim, Escape, the back gesture, or a swipe toward the start edge.
- On open, focus moves to the active destination; on close, it returns to the `menu` button. Focus is trapped inside the modal drawer.
- Keyboard: Up/Down move between rows (skipping headings and dividers), Home/End jump, Enter or Space activate, typeahead moves to labels.
- Standard: toggled by a `dock-left` button in the content's app bar (or ⌃⌘S on macOS); its width and shown/hidden state persist.
- A long list scrolls inside the drawer; the header scrolls with it.
- Motion: modal enters with `ease-emphasized-decelerate` over `duration-medium-2` (translate plus the scrim fading in), leaves with `ease-emphasized-accelerate` over `duration-short-4`; standard hides by animating its width over `duration-medium-1` with `ease-standard`. Reduced motion: fade the drawer and scrim, no slide.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Standard at pointer density (40 rows) as the NavigationView pane; modal ("minimal" mode) in narrow windows, opened from a `menu` button at the top-start; no edge swipe with a mouse. |
| macOS | Standard only, as the window's sidebar (source list, 28-32 rows); hidden with ⌃⌘S or the sidebar toolbar button; no modal drawer: narrow windows collapse the sidebar entirely. |
| Linux | Standard as the sidebar of `AdwOverlaySplitView`; in narrow windows it becomes the modal overlay form, opened by the header bar's sidebar button. |
| Android | Modal on compact and medium with edge swipe (except where gesture navigation claims the edge: then only the button); standard at expanded and up. |
| iOS | No drawer convention: use a tab bar on iPhone and the sidebar on iPad. If one is required, present it as a sheet from the leading edge. |
| Web | Modal below `window-expanded` 840, standard above; `nav` landmark inside a `dialog` (modal) or in the page (standard). |

## Accessibility
- Modal: a Dialog (modal) named "Navigation" containing a Navigation landmark; everything behind is inert. Standard: a Navigation landmark named "Main".
- Destinations are Links with Current = page on the active one; counts are part of the name ("Projects, 12").
- The `menu` button is named "Open navigation", reports Expanded and controls the drawer.
- Opening announces "Navigation"; closing needs no announcement (focus returns to the button).
- Contrast: `on-surface-variant` on `surface-container-low` and `on-secondary-container` on `secondary-container` are 4.5:1 or better.
- Targets: 56 rows on touch, 40 on pointer.
- Reduced motion: no slide.

## Content
- Destination labels: short nouns, sentence case, 1-3 words, the same as in the DestinationBar.
- Section headings: nouns without a colon ("Teams", "Shared with me").
- Counts are numbers only; words go in the page.

## e.ui today
`navigation.navigation_drawer` shows a `.Sidebar` destination bar on a `surface` sheet with `elevation-3` in a modal overlay at the window's left edge while `open`, with no scrim; Escape and outside presses fire `dismiss`. To reach this design:
- Paint the scrim at 32% behind the modal drawer: today nothing shows that the page behind is blocked.
- Use `surface-container-low`, `radius-lg` end corners and `elevation-1`; drop the nested `surface-variant` destination-bar sheet and its padding-inside-padding.
- Draw rows per spec (56 / 40, full-width `secondary-container` pill, icons, trailing counts) instead of Filled and Plain tabs, and add headers, section headings and dividers.
- Add the standard variant (in-layout, square, collapsible and resizable), the edge swipe, focus return to the opener, and open/close motion.
- Mirror to the right edge in right-to-left layouts, and cap the width at window width - 56.
