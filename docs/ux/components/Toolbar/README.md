# Toolbar

A toolbar is a strip of frequent commands and toggles that act on the view or selection it belongs to (an editor, a file list, a canvas), grouped, keyboard-navigable as one stop, and collapsing into More when narrow.

## Anatomy
1. Container: docked (full-bleed, square) on `surface-container`, or floating (a `radius-full` pill, `surface-container-high`, `elevation-2`).
2. Items: icon buttons, toggle icon buttons, text buttons with an icon, menu buttons (label plus `chevron-down`) and, rarely, a compact field (search, zoom).
3. Group separators: 1 x 20 `outline-variant` lines between related sets.
4. Spacer (optional): pushes the trailing group (search, More) to the end.
5. More: `more-horiz` icon button that opens a menu of the items that did not fit.
6. Tooltip: every icon-only item has one, with its shortcut.

## Variants and when to use
| Variant | Use for |
|---|---|
| Docked | Commands for a pane or window on pointer hosts: an editor's run and view toggles, a file browser's New / Upload / Download. Sits under the app bar or at the top of a pane. |
| Docked with labels | Touch hosts or a page with 2-4 actions that need words ("Filter", "Sort by date"). |
| Floating | Touch and tablet editing surfaces: formatting or drawing tools over the content, beside a FAB. Hides on scroll down. |
| Vertical | Tool palettes at a canvas's edge (select, text, image). Floating style, 40 wide. |

Screen-level actions and the title belong in the AppBar. Menus of every command belong in the MenuBar. A footer of buttons that ends a task is an ActionRow. A choice of one mode among few is a SegmentedButton, unless it is part of a larger tool set.

## Specs
| Part | Docked, pointer | Docked, touch | Floating | Vertical |
|---|---|---|---|---|
| Height (width for vertical) | `control-md` 40 | `control-lg` 48 | `control-xl` 56 | `control-md` 40 |
| Padding | `space-1` 4 sides | `space-2` 8 sides | `space-2` 8 | `space-1` 4 top and bottom |
| Items | icon buttons `control-sm` 32, icons 18 | icon buttons 40 (48 target), text buttons 40 | icon buttons 40, icons 24 | icon buttons 32 |
| Item gap | `space-1` 4 | `space-2` 8 | `space-1` 4 | `space-1` 4 |
| Separator | 1 x 20 `outline-variant`, `space-1` each side | same | same | 20 x 1 |
| Container | `surface-container`, square | same | `surface-container-high`, `radius-full`, `elevation-2` | same, `radius-md` |
| Icons | `on-surface-variant` | same | same | same |
| Toggle on | `secondary-container` fill, `on-secondary-container` icon | same | same | same |
| Menu button | text button `control-sm` in `on-surface`, `chevron-down` 18 trailing | 40 | | |
| Tooltip | plain tooltip, `space-1` 4 below the item (above for a bottom toolbar) | long-press | long-press | to the side |

## States
- Item states: hover, focus (the ring on the item), pressed; toggles also on and off; disabled is `on-surface` at 38% and stays in place (items never shift).
- Menu button open: pressed layer held, `chevron-down` flips to `chevron-up`, menu below.
- Overflowed: More appears; hidden items keep their order in its menu, toggles shown as check items.
- Floating on scroll: slides out down on scroll down, back on scroll up.

## Behaviour
- One Tab stop for the whole toolbar; arrow keys move between items (Left/Right for horizontal, Up/Down for vertical), Home and End jump to the ends, and focus skips separators but lands on disabled items so they can be read. Focus is remembered when Tab leaves and comes back.
- Enter or Space presses; a toggle flips; Down or Alt+Down on a menu button opens its menu.
- Tooltips: on hover after `duration-long-2` (500 ms), on keyboard focus immediately; they hide on press or Escape.
- Overflow collapses from the end, keeping the trailing group (search, More) last. Separators that would start or end a run are dropped.
- The docked toolbar never scrolls with the content; the floating one hides on scroll with `ease-emphasized-accelerate` over `duration-short-4` and returns with `ease-emphasized-decelerate` over `duration-medium-2`. Reduced motion: fade.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Docked pointer density; tooltips include the shortcut in parentheses ("Rebuild (Ctrl+Shift+B)"); a WinUI command bar convention: primary commands visible, secondary in More. |
| macOS | The window toolbar holds these items in the unified title bar; items can be customised by the user (Customize Toolbar in the View menu); shortcuts in tooltips use symbols (⇧⌘B). Toggles are bezel-less with a filled state. |
| Linux | Docked pointer density. GNOME puts view actions in the header bar and rarely uses a separate toolbar; KDE toolbars show text beside icons by default (follow the desktop's toolbar style). |
| Android | Docked with labels or floating; 48 targets; long-press shows the tooltip. |
| iOS | Bottom toolbar (44pt) with up to five items, text or icons, evenly spaced; the floating variant becomes the keyboard accessory bar when a field is focused. |
| Web | Docked pointer density at `window-expanded`, labelled or floating on touch; `role="toolbar"` with roving tabindex. |

## Accessibility
- Role Toolbar, named by its purpose ("Editor tools"), with an orientation.
- Each item is a Button named by its label; toggles report Pressed; menu buttons report Has popup = menu and Expanded.
- Disabled items stay focusable by arrow keys and report Disabled.
- Contrast: `on-surface-variant` icons on `surface-container` are 4.5:1 or better; the toggle's `on-secondary-container` on `secondary-container` likewise.
- Targets: 32 on pointer hosts, 48 on touch (the floating toolbar's 40 buttons pad to 48 across the 56 bar).
- Every icon-only item has a visible tooltip with the same text as its name.

## Content
- Tooltips name the command and its shortcut: "Rebuild (Ctrl+Shift+B)". Sentence case, no trailing period.
- Labelled items: one or two words, verb first where it is a command ("Sort by date"), a noun where it is a mode ("Terminal").
- A menu button shows its current value ("Release build"), not "Configuration".

## e.ui today
`navigation.toolbar` wraps an `action_row` of `.Plain` buttons in a `surface-variant` sheet with `space-xs` padding and names it as a Group. To reach this design:
- Use `surface-container` (docked) and the floating pill; set the height by density (40 / 48 / 56) instead of padding round the buttons.
- Make it one Tab stop with roving focus and arrow keys, Home and End, and the Toolbar role with an orientation.
- Add toggle items (Pressed state, `secondary-container` when on), menu-button items, separators and a spacer to the `Action` model.
- Add overflow into More and tooltips with shortcuts for icon-only items.
- Tint icons `on-surface-variant` (`action_button` icons are untinted today) and draw the focus ring (`pressable_states` drops it).
- Replace the Plain `primary` labels with `on-surface` for menu buttons and `primary` only for text buttons.
