# ContextMenu

A context menu offers the commands for the object under the pointer or finger (a file, a row, a selection, a tab), opened by secondary click, long-press or the keyboard's menu key, and placed at the point of invocation.

## Anatomy
1. Target: the object the menu acts on; it takes (or keeps) the selection and shows its selected state while the menu is open.
2. Menu: `surface-container`, `radius-sm`, `elevation-2`, at the pointer.
3. Items: 18 leading slot (reserved when any item has an icon), label, shortcut at the end, `chevron-right` for a submenu.
4. Groups: separated by 1px `outline-variant` separators; the destructive group last.
5. Touch only: the lifted target (a copy of the item on `surface-container-lowest`, `radius-md`, `elevation-3`) above a scrim, with the menu under it.

## Variants and when to use
| Variant | Items | Use for |
|---|---|---|
| Pointer | 32 tall, shortcuts shown | Secondary click (right click, Ctrl+click on macOS) and the menu key / Shift+F10 on desktop hosts. |
| Touch | 48 tall, icons, no shortcuts | Long-press on Android, iOS and touch Web; the item lifts and the page dims. |
| Selection | as pointer | A text or multi-item selection: the commands for all selected items, with the count in the header ("3 files"). |

Commands shown by a visible button are a menu from that button (`overlay.menu_button`), not a context menu. Window-wide commands belong in the MenuBar. Never put a command only in a context menu: it must also be in the MenuBar, the CommandPalette or the AppBar's More.

## Specs
| Part | Pointer | Touch |
|---|---|---|
| Menu width | 200-320, fits the longest label and shortcut | 112-280; 184 typical on compact |
| Menu padding | `space-2` 8 top and bottom | same |
| Item height | `control-sm` 32 (density -2) | `control-lg` 48 |
| Item padding and gap | `space-3` 12 sides, `space-2` 8 gap | 12 sides, `space-3` 12 gap |
| Label | `body-medium` 14/20 `on-surface` | same |
| Leading slot | 18, `on-surface-variant` | 24, `on-surface-variant` |
| Shortcut | 13/20 `on-surface-variant` | none |
| Container | `surface-container`, `radius-sm`, `elevation-2` | same |
| Selected target | `secondary-container` row while open | lifted copy: `surface-container-lowest`, `radius-md`, `elevation-3`, 8 inset from the screen edges |
| Scrim | none | `scrim` at `scrim-opacity` 32% |
| Destructive item | `error` label and icon | same |
| Offset | top-start corner at the pointer (+2, +2) | 8 below the lifted target, start-aligned with it |

## States
- Opening: the target is selected (if it was not) so the user sees what the commands act on; right-clicking outside a multi-selection replaces it, inside keeps it.
- Items: hover, focus (inset ring), pressed, disabled (38%), checked, submenu open (8% layer held on the parent).
- Empty target (whitespace in a list): the menu offers the container's commands (New file, Paste, Sort by).
- Touch: the target lifts over `duration-medium-1`, the scrim fades in, the menu grows from the target's edge.

## Behaviour
- Open on pointer: on secondary button release (press on Windows and Linux follow the host; macOS opens on press). The menu opens at the pointer and flips to stay within the window: to the start of the pointer if it would overflow the end, above if it would overflow the bottom.
- Open by keyboard: the menu key or Shift+F10 opens at the focused item's start edge, below it.
- Open on touch: long-press after `duration-long-2` (500 ms) with a haptic tick; dragging onto an item and releasing runs it.
- Keys: Up/Down move (wrapping), Home/End jump, Right opens a submenu, Left closes it, Enter or Space run, typeahead moves to matching labels, Escape closes and returns focus to the target.
- Dismiss: press outside (the press is not passed through to what is under it), Escape, window deactivation, or scrolling the page (pointer only).
- Running an item closes the menu first, then runs; focus returns to the target unless the command moves it (Rename focuses the field).
- Motion: pointer menus fade and scale from 0.95 at the pointer corner with `ease-emphasized-decelerate` over `duration-short-4`; closing fades over `duration-short-2` with `ease-emphasized-accelerate`. Touch lift over `duration-medium-1` with `ease-emphasized-decelerate`. Reduced motion: fades only.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Pointer variant; opens on right-button release; menu key and Shift+F10; shortcuts spelled out; access keys underline when opened from the keyboard. |
| macOS | Opens on right-button press or Ctrl+click and supports press-drag-release; no access keys; shortcuts as symbols; a Services submenu may be added by the system for text. |
| Linux | Pointer variant; GTK opens on press, Qt on release: follow the toolkit's desktop. |
| Android | Touch variant with lift; on text, the floating text selection toolbar replaces the menu. |
| iOS | Touch variant as the system context menu: the target lifts with a live preview, the background blurs (use the scrim where blur is unavailable), the menu may open above the preview when there is no room below. |
| Web | Replace the browser's menu only on objects that have their own commands; leave it on text, links and images. `role="menu"`; open on `contextmenu`. |

## Accessibility
- Role Menu named by the target ("Actions for lower.e"); items are MenuItem, MenuItemCheckbox or MenuItemRadio.
- Opening moves focus to the first enabled item and announces the menu name and item count; closing returns focus to the target.
- Each target that has a context menu exposes a Show menu action, so assistive tech can open it without a secondary click.
- Shortcuts are exposed as the keyboard shortcut property, not in the name.
- Contrast: `on-surface` on `surface-container` 7:1; `error` labels 4.5:1 or better.
- Targets: 32 on pointer hosts, 48 on touch.
- Reduced motion: no scale or lift, fade only.

## Content
- Verbs first, most common first: "Open", "Open to the side", "Copy path", "Rename", then destructive last: "Delete".
- Six to ten items; move the rest into a submenu named by the group ("Open with").
- No commands that do nothing for this target; disable rather than hide items that apply to the type but not the current state, hide those that never apply.

## e.ui today
`navigation.context_menu` calls `overlay.menu` below `anchor` and adds nothing; items are Plain `primary` buttons on a `surface` sheet with `border-regular` and `elevation-2`. To reach this design:
- Take a pointer position (or the anchor's start edge for keyboard invocation) and place the menu there, flipping at the window edges; today it always sits below `anchor`.
- Draw the Menu spec: `surface-container` without a border, 32 / 48 items by input kind, leading slot, shortcuts, separators, submenus and destructive items, in `on-surface` rather than Plain `primary`.
- Add the touch variant: long-press, the lifted target copy and the scrim.
- Add typeahead and the Show menu accessibility action on targets; return focus to the target on dismiss.
- Keep `dismiss` for Escape and outside presses, and swallow the outside press.
