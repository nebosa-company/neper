# Fab

A floating action button (FAB) is the one prominent button for a screen's main creation action (New build, Compose); it floats above the content and can open a short menu of related actions.

## Anatomy
1. Container: `primary-container`, `radius-lg` 16 (small `radius-md` 12, large `radius-xl` 28), `elevation-3`.
2. Icon: `icon-md` 24 (`icon-lg` 36 on the large FAB), `on-primary-container`.
3. Label (extended only): `label-large`, after the icon.
4. State layer and focus ring.
5. Menu (optional): 2-6 pill items stacked above the FAB, end-aligned; the FAB morphs into a round close button.
6. Scrim (menu open, compact touch only): `scrim` at `scrim-opacity`.

## Variants and when to use
| Variant | Size | Use for |
|---|---|---|
| Default | 56, `radius-lg` | The main action on compact and medium windows. |
| Small | 40, `radius-md` | Pointer hosts, at the top of a navigation rail; secondary floating actions next to a default FAB (a map's "my location"). |
| Large | 96, `radius-xl`, 36 icon | A screen whose whole purpose is creating (an empty project list on an expanded window). |
| Extended | 56 tall, icon + label | When the action needs a word; it collapses to the default FAB when the content scrolls down and expands when it scrolls up. |
| Menu | FAB + 2-6 items | A small set of related creation actions: Rebuild, Upload, From folder. |

Colours: `primary-container` (default), `secondary-container`, `tertiary-container`, `primary` (highest emphasis), `surface-container-high` with a `primary` icon (low emphasis on busy screens).

One FAB per screen. Use Button (filled) when the action belongs to a form or a dialog. Use Split button when one of several actions leads and they are not creation. Use Overlay menu button for longer or plain lists. Don't use a FAB for destructive or minor actions.

## Specs
| Part | Small | Default | Large | Extended |
|---|---|---|---|---|
| Size | `control-md` 40 | `control-xl` 56 | 96 | 56 tall, min 80 wide |
| Radius | `radius-md` 12 | `radius-lg` 16 | `radius-xl` 28 | `radius-lg` 16 |
| Icon | 24 | 24 | `icon-lg` 36 | 24 |
| Padding | centred | centred | centred | `space-4` 16 start, `space-5` 20 end, `space-3` 12 icon to label |
| Label | none | none | none | `label-large` 14/20 600 |
| Target | 40 (pads to 48 on touch) | 56 | 96 | 56 |

| Part | Value |
|---|---|
| Position (compact) | bottom end, `space-4` 16 from the edges, above the navigation bar |
| Position (medium, expanded) | top of the navigation rail, or bottom end `space-6` 24 in |
| Elevation | `elevation-3` rest, `elevation-4` hover, `elevation-3` pressed, `elevation-1` lowered (docked into a bottom app bar) |
| Menu items | 56 tall pills, `radius-full`, `primary-container` / `on-primary-container`, `elevation-3`, padding `space-4` 16 start / `space-6` 24 end, 24 icon, `space-2` gap, 16/24 600 label; `space-1` 4 apart; `space-2` 8 above the FAB; end-aligned |
| Menu, desktop | Menu, dense (36 rows) beside the rail FAB, `space-1` 4 away |
| Open FAB | 56 circle, `radius-full`, `primary` / `on-primary`, `close` icon |

## States
- Hover: `state-hover` layer, `elevation-4`.
- Focus: `state-focus` layer and the focus ring 3 px `focus-ring`, 2 px outside.
- Pressed: `state-pressed` layer, `elevation-3`; ripple on touch.
- Lowered: `elevation-1` when docked in a bottom app bar.
- Open (menu): the FAB morphs to a `primary` circle with `close`; items enter bottom-up, staggered 30 ms, over `duration-medium-1` with `ease-emphasized-decelerate`; they leave top-down with `ease-emphasized-accelerate` over `duration-short-4`.
- Extended collapse: the label fades and the width shrinks to 56 over `duration-medium-1` with `ease-emphasized-decelerate` when scrolling down 1 screen; expands on scroll up.
- Disabled: not used. If the action is unavailable, hide the FAB (scale out over `duration-short-4`) and explain in the content.
- Hidden: scales out to 0 over `duration-short-4` while a snackbar, sheet or keyboard would cover it; comes back with `ease-emphasized-decelerate`.

## Behaviour
- Pressing a plain FAB runs its action at once, usually opening a new item's view with a container transform from the FAB over `duration-long-2`.
- Menu FAB: press toggles the menu. While open on touch, the scrim covers the content, focus moves to the first item, and a tap on the scrim, the close FAB, Back or Escape closes it and returns focus to the FAB. On desktop the menu is a regular dense Menu: arrows, Home, End, typeahead and Enter; Escape closes.
- The FAB stays above scrolling content and never scrolls away; snackbars push it up by their height.
- A keyboard shortcut (Ctrl/Cmd+N for "new") triggers the FAB's action wherever it is shown.
- Reduced motion: the menu and the FAB morph cross-fade; no container transform.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | No floating FAB in document windows: the action goes first in the command bar or top of the navigation rail as a small FAB; its menu is a dense Menu. |
| macOS | No FAB: the action is the toolbar's "+" button and File > New in the menu bar; a menu FAB becomes a pull-down toolbar button. |
| Linux | GNOME: a "+" button at the start of the header bar; KDE: first toolbar action. Small FAB only in touch-first layouts. |
| Android | Default or extended FAB at bottom end on compact, top of the rail on medium and expanded; the menu with scrim; ripple; Back closes the menu. |
| iOS | No Material FAB by default: the action is a navigation bar button (top trailing) or a bottom toolbar item; apps that keep a FAB use the default size without ripple, and the menu becomes a UIMenu from that button. |
| Web | Default at compact widths (bottom end, fixed to the viewport), small at the top of the rail at wider widths; a `<button>` with `aria-haspopup="menu"` when it opens a menu. |

## Accessibility
- Role Button named by the action ("New build"), even when extended shows the label; Press action.
- Menu FAB: Button with Has popup (menu), Expanded while open, and controls the menu; the open close button is named "Close menu". The menu is a Menu of Menu items.
- Focus order: the FAB comes after the main content of the screen, before the navigation bar, not first.
- Contrast: icon 3:1 and label 4.5:1 on the container; the container is identifiable by its shadow and shape, not colour alone.
- Target: 56 (the small FAB pads to 48 on touch hosts).
- Reduced motion: no morph, no stagger, no container transform; hide and show by fading.

## Content
- Label the action with a verb and object: "New build", "Compose", "Invite people". Two words, sentence case.
- Menu items: verb or source, 1-2 words: "Rebuild", "Upload", "From folder".
- The icon is `add` for creation, `edit` for compose; never a brand logo.

## e.ui today
`control.speed_dial` is today's FAB: a Filled pressable head with radius half of `hit-target` (a pill) and a Label-role label, firing `toggle`; while `open`, a modal overlay above it (keyed `key + 1`) holds the actions as full Filled buttons in a column, gap `space-xs`, end-aligned. To reach this design:
- Add `control.fab` for the plain FAB (icon, optional label, the four sizes and five colours) instead of reusing the Filled button look; round it with `radius-lg`, 56 square, `primary-container`, `elevation-3`.
- Rebuild `speed_dial` on it: the head morphs to a `primary` close circle when open, and the items become 56 pill menu items in `primary-container` with icons, not Filled buttons.
- Report Collapse (not Expand) while open; the head offers Expand even when open today.
- Add the scrim on compact touch, focus into the menu on open and back to the head on close, and the dense Menu form for pointer hosts.
- Add extended collapse on scroll, hide-under-snackbar, and the motion tokens for the menu's stagger.
