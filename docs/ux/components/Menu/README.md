# Menu

A menu is a temporary, floating list of commands or options opened from a button, a menu bar title or a context gesture; it closes as soon as one is chosen.

## Anatomy
1. Container: `surface-container`, `radius-sm`, `elevation-2`, 8 padding top and bottom (4 on pointer hosts).
2. Item: a full-width row with a state layer; leading slot, label, trailing slot.
3. Leading slot: a 24 icon (18 on pointer hosts), or the check column for checkable items. Every item in a menu reserves the slot if any item uses it, so labels align.
4. Label: `body-large` on touch, `body-medium` on pointer; optional supporting line in `body-small`.
5. Trailing slot: the keyboard shortcut in `body-medium` `on-surface-variant`, or a `chevron-right` for a submenu.
6. Group head (optional): `label-medium` in `on-surface-variant` above a group of related or single-choice items.
7. Separator: 1px `outline-variant` with 8 (4 on pointer) above and below.
8. Submenu: a second menu aligned to its parent item's top, overlapping the parent by 4.

## Variants and when to use
| Variant | Item height | Use for |
|---|---|---|
| Touch menu | 48 (`control-lg`) | Overflow menus from an icon button, a card's "More", a field's dropdown on Android and touch Web. |
| Pointer menu | 32 (`control-sm`, density -2) | Menu bar menus, toolbar dropdowns and context menus on Windows, macOS, Linux and desktop Web. |
| Checkable items | as above | Independent on/off options (Word wrap) and single-choice groups (Theme). The check sits in the leading slot. |
| Submenu | as above | A second level of at most 8 items. Never nest deeper than two levels. |
| Destructive item | as above | Delete, Remove: `error` label and icon, last in the menu, after a separator. |

Use Select for choosing a value in a form (it shows the choice in the field), Context menu for the right-click variant of the same list, Popover for anything with a form control, and Action sheet on iOS compact.

## Specs
| Part | Touch (density 0) | Pointer (density -2) |
|---|---|---|
| Width | 112 min, 280 max; grows to the widest item | 200 min, 320 max |
| Container padding | `space-2` 8 top and bottom | `space-1` 4 top and bottom |
| Item height | 48; 56 with a supporting line | 32; 48 with a supporting line |
| Item side padding | `space-3` 12 | `space-3` 12 |
| Leading icon | `icon-md` 24 in `on-surface-variant` | `icon-sm` 18 in `on-surface-variant` |
| Icon to label | `space-3` 12 | `space-2` 8 |
| Label | `body-large` in `on-surface` | `body-medium` in `on-surface` |
| Supporting line | `body-small` in `on-surface-variant` | `body-small` in `on-surface-variant` |
| Shortcut | none on touch | `body-medium` in `on-surface-variant`, end-aligned, `space-6` min from the label |
| Check | `check` 24 in `on-surface` | `check` 18 in `on-surface` |
| Group head | `label-medium`, 8 above, 4 below | `label-medium`, 8 above, 4 below |
| Separator | `divider` in `outline-variant`, `space-2` around | `divider`, `space-1` around |
| Radius / elevation | `radius-sm` 8, `elevation-2` | `radius-sm` 8, `elevation-2` |
| Offset from anchor | 0 below a menu bar title; 4 from a button | same |

## States
- Item hover (pointer): `on-surface` layer at `state-hover`. The keyboard highlight and the hover highlight are one and the same row.
- Item focus (keyboard): `state-focus` layer plus the focus ring inset 3px inside the row (the row is edge-to-edge in the menu).
- Item pressed: `state-pressed`; a ripple on Android.
- Submenu open: the parent row keeps the hover layer while its submenu is open.
- Checked: the check shows; the row has no fill. Single-choice groups show exactly one check.
- Disabled: label, icon and shortcut at `on-surface` 38%; not focusable by arrows on Windows and Linux, focusable but inert on macOS (follow the host). Keep disabled items visible rather than removing them, so the menu does not reshape.
- Destructive: `error` label and icon at rest; the state layer stays `on-surface`.

## Behaviour
- Opening: a press on the anchor opens it; on pointer hosts a press-drag-release on an item chooses it in one gesture. The anchor shows its selected or pressed state while the menu is open.
- Keyboard: Enter, Space or Down on the anchor opens with the first item highlighted; Up opens with the last. Down and Up move and wrap; Home and End jump; Right opens a submenu and highlights its first item, Left or Escape closes it; Enter or Space chooses. Typing letters jumps to the next item starting with them (typeahead, 500 ms buffer). Tab closes the menu and moves focus on.
- Submenus: open after 200 ms of hover or on Right; stay open while the pointer travels diagonally toward them (the safe triangle); on compact touch they replace the menu, with a back row at the top.
- Choosing an item closes the whole menu chain and returns focus to the anchor; a checkable item toggles and closes (hold Shift on pointer hosts to keep it open for another toggle).
- Dismissal: Escape closes one level; a press outside, window deactivation or scrolling the anchor out of view close all. The press outside is consumed, not passed through.
- Placement: below-start of the anchor, flipping above or to the start when there is no room; kept 8 inside the window. A menu taller than the window scrolls with the first and last items kept reachable by arrow keys.
- Motion: opens over `duration-medium-1` with `ease-emphasized-decelerate`, growing from the anchor edge (scale Y from 80% and fade); closes over `duration-short-3` with `ease-emphasized-accelerate` (fade). Reduced motion: fade only.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Pointer density; shortcuts spelled "Ctrl+Shift+P"; access keys underlined when Alt is held; menu bar menus attach to the in-window menu bar; the container may take Acrylic where the host allows. |
| macOS | App commands go in the system menu bar through the native menu (`NSMenu`), not an in-window menu. In-window dropdowns and context menus may use ours or native. Shortcut glyphs (⌘⇧P) right-aligned; the check goes in the leading column; disabled items remain highlightable. |
| Linux | Pointer density. GNOME: the primary menu is a popover menu from the header bar's menu button, submenus slide in place. KDE: classic cascading menus. Shortcut spelling per desktop. |
| Android | Touch density; 48 rows, ripple; submenus replace the menu with a back row; no shortcuts shown unless a hardware keyboard is attached. |
| iOS | Use the native context menu (`UIMenu`) for long press and pull-down buttons: sections instead of separators, submenus expand inline, destructive items in `error`, no shortcuts (except the iPad keyboard command overlay). |
| Web | `role="menu"` with `menuitem`, `menuitemcheckbox`, `menuitemradio`; `aria-haspopup` and `aria-expanded` on the anchor; pointer density on fine pointers, touch density on coarse. |

## Accessibility
- Role Menu, named by the anchor's label ("View"); items MenuItem, MenuItemCheckbox (Checked state) or MenuItemRadio in a group named by its head. A submenu parent reports HasPopup and Expanded.
- The anchor reports HasPopup Menu and Expanded while open, and controls the menu.
- Focus moves into the menu on open and returns to the anchor on close; while open it stays in the menu chain.
- The shortcut is exposed as the item's keyboard shortcut property, not in its name.
- Screen readers announce "View menu, 10 items" on open, then each item with its position ("Word wrap, checked, 1 of 10").
- Label contrast 4.5:1 on `surface-container` in every theme; the 38% disabled label is exempt but must still read against the container.
- Targets: 48 rows on touch; 32 rows, full width, on pointer hosts.
- Reduced motion: fade only.

## Content
- Labels are verbs or verb phrases for commands ("Duplicate", "Export build"), nouns or adjectives for options ("Minimap", "Dark"). Sentence case, no trailing period.
- End a label with "…" only when the command needs more input before it acts ("Command palette…", "New folder…").
- One to three words. Put detail in the supporting line ("Zip archive, 24 MB"), not the label.
- Order by frequency, then group; destructive last. Keep the order stable; never reorder by recent use.

## e.ui today
`overlay.menu` places the `MenuItem { label, action, enabled }` rows as Plain buttons in a bordered `surface` column below `anchor`; `overlay.menu_button` puts that menu under an Outlined button. To reach this design:
- Replace the Plain buttons with real menu rows: full-width state layers, 48 or 32 tall by density, `body-large` or `body-medium` in `on-surface` (not `primary`), and no `radius-md` per row.
- Extend `MenuItem` with an icon, a shortcut, a supporting line, `checked` (off, on, radio group), `destructive` and `submenu: []const MenuItem`; add group heads and separators as item kinds.
- Add arrow-key roving focus, Home/End, typeahead, Right/Left for submenus and the safe-triangle hover; today Tab walks the items and there is no submenu.
- Stop wrapping a Button node inside every MenuItem, and report the item role directly.
- Repaint the container as `surface-container`, `radius-sm`, `elevation-2`, no border; show the disabled item at 38%, not half opacity.
- Route macOS app menus to the native menu bar.
