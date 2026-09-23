# WindowSwitcher

A window switcher is the keyboard-driven overlay for jumping between an app's open windows or documents in most-recently-used order: hold the modifier, step with Tab, release to switch, so the previous document is one quick chord away.

## Anatomy
1. Scrim: `scrim` at `scrim-opacity` 32% over the window.
2. Panel: `surface-container-high`, `radius-xl`, `elevation-3`, centred in the window.
3. Tiles (grid form): a 136-wide tile per window with a live thumbnail (`radius-sm`, 1px `outline-variant`) and a caption (16 icon, name).
4. Selected tile: `secondary-container` with the focus ring; a hovered tile shows a Close button in its corner.
5. Detail line: the selected item's name (`title-small`) and its context and state (folder, "unsaved changes").
6. List form: a filter field and rows (as the CommandPalette's rows) instead of tiles.

## Variants and when to use
| Variant | Use for |
|---|---|
| Grid | Up to about 8 windows or documents where a thumbnail helps recognition (documents with different content, tool windows). |
| List | Many documents (over 8) or similar-looking ones (code files): names, folders and state, filterable by typing. |
| Compact | Phones and small tablets: a full-screen grid of open documents from the app bar's count button; tap to switch, swipe a card away to close. |

Running a command by name is the CommandPalette (its file mode, Ctrl+P, also opens documents by name, including closed ones). Switching among a window's tabs by pointer is DocumentTabs. Switching between different apps is the operating system's job: this component only lists the app's own windows and documents.

## Specs
| Part | Grid | List |
|---|---|---|
| Panel | `surface-container-high`, `radius-xl`, `elevation-3`, padding `space-4` 16, gap 12 | 480-560 wide, `radius-xl`, no padding |
| Placement | centred in the window | top-centred, 64 from the window's top |
| Tile | 136 wide, padding 8, `radius-md`, gap 8 between tiles; up to 6 per row, then wrap | |
| Thumbnail | 120 x 84, `radius-sm`, 1 `outline-variant`, `surface` | |
| Caption | `body-small` 12/16, 16 icon, one line with ellipsis | |
| Selected | `secondary-container` fill, `on-secondary-container` caption, focus ring 3px 2px outside | row `secondary-container`, `radius-sm` |
| Hover | `on-surface` at `state-hover` | same |
| Close on tile | 24 circle, `surface-container-highest`, `on-surface` 14 icon, 4 from the top-end | Delete key |
| Detail line | `title-small` name, `body-small` `on-surface-variant` context | inline `ctx` after the name |
| Filter field | | 48 tall, search icon, `body-large` |
| Rows | | 40 tall (pointer), 12 sides, 18 icon, `body-medium` |
| Scrim | 32% | none (the list is light and anchored) |

## States
- Opening: after the chord's second key; on a very quick press-and-release it never draws and simply switches to the previous item.
- Selected, hover, pressed; a tile of a window with unsaved changes says so in the detail line and its name.
- Closing an item from the switcher removes its tile and keeps the selection on the neighbour.
- Empty (only one item open): the chord does nothing; no panel appears.

## Behaviour
- Pointer hosts: Ctrl+Tab opens with the second most recent item selected; Tab (with Ctrl still held) steps forward, Shift+Tab back, arrow keys move in the grid, releasing Ctrl switches. Escape (still holding) cancels. Pressing a tile switches at once.
- Latency: draw the panel only if the modifier is still held after `duration-short-4` (200 ms), so fast switching never flashes it.
- List form: typing filters (fuzzy, on names then folders); Up/Down move; Enter switches; Escape closes. It stays open without a held modifier once the user types.
- Order is most-recently-used and updates on each switch; the app's other windows come first, then documents within the current window when both are listed.
- Dismiss: release, Enter, a tile press, Escape, a press on the scrim, or the window losing focus.
- Motion: the panel fades and scales from 0.95 with `ease-emphasized-decelerate` over `duration-short-4`; closing fades over `duration-short-2` with `ease-emphasized-accelerate`; selection moves instantly. Reduced motion: fade only.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Ctrl+Tab for documents inside the app (Alt+Tab belongs to the system); Ctrl+F6 cycles child windows in MDI-style apps. |
| macOS | ⌃Tab for documents; ⌘` cycles the app's windows natively without a panel, so the grid lists documents; honour the Window menu's list as the same model. |
| Linux | Ctrl+Tab for documents; Super-based chords belong to the desktop; the app's windows also appear in the desktop's switcher, keep names consistent with window titles. |
| Android | Compact grid from a count button; the system Recents screen handles apps. |
| iOS | Compact grid; on iPad with a keyboard, ⌃Tab where the app has tabs; the system App Switcher handles apps. |
| Web | Ctrl+Tab is the browser's: use Ctrl+Alt+Tab or a menu command, and the list form; never try to intercept browser chords. |

## Accessibility
- A Dialog (modal) named "Switch window" containing a Listbox; each tile or row is an Option named by the item and its state ("lower.e, neper/src, unsaved changes"), with Selected.
- Opening announces the dialog and the selected option; each step announces the new option.
- A keyboard-only alternative that does not require holding a modifier is always available: the list form from a Window menu command ("Switch window...").
- Contrast: captions and names 4.5:1 or better on their fills; thumbnails are decorative (hidden from the tree).
- Targets: tiles 136 x 120 and rows 40 exceed the pointer minimum; compact cards are 48 or more.
- Reduced motion: no scale.

## Content
- Names are the window's or document's title, exactly as in its tab; the context line adds the folder and state in words ("unsaved changes", "read only").
- The compact title counts: "3 open".
- No instructions in the panel; the chord is documented in menus and the CommandPalette.

## e.ui today
`navigation.window_switcher` shows the names as full-width buttons in a `surface` panel with `border-regular`, `radius-md` and `elevation-3`, centred with no scrim, the active one Filled; Up/Down move `active` (stopping at the ends), Enter or a tap picks, Escape and outside presses dismiss. To reach this design:
- Add the scrim, and draw the panel as `surface-container-high`, `radius-xl` with no border.
- Add the grid form (thumbnails supplied by the caller as textures, captions with icons) and restyle the list form's rows as the palette's rows (`secondary-container` selection, not a Filled `primary` button) with labels centred vertically: today they sit at the top-left.
- Implement hold-to-switch: open on the chord's second key after 200 ms, step with Tab and Shift+Tab, switch on the modifier's release, and wrap at the ends instead of stopping.
- Add type-to-filter in the list form, Close on hover and Delete, and the detail line.
- Report Listbox and Option semantics (today ListItems with a row index) and a Selected state that moves with `activate`.
