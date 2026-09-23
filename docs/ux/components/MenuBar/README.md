# MenuBar

A menu bar is the row of a desktop window's top-level menus (File, Edit, View and so on), the complete, discoverable list of every command the app has, each with its shortcut; on macOS it is the system menu bar, not part of the window.

## Anatomy
1. Bar: full-bleed, square, 32 tall, `surface` (it is part of the window chrome, above any app bar or toolbar).
2. Menu title: `body-medium` text in a 24-tall item with `radius-xs` corners; one underlined access key while Alt is held.
3. Menu: a dense pointer menu (see Menu) below its title, start edges aligned.
4. Item: 18 leading slot (check, radio dot or icon), label with access key, shortcut at the end, `chevron-right` for a submenu.
5. Separator: 1px `outline-variant` with 8 above and below.
6. Submenu: a menu beside its parent item, top item aligned with the parent item.

## Variants and when to use
| Variant | Use for |
|---|---|
| In-window menu bar | Windows, Linux (KDE always; GNOME apps with many commands) and desktop Web apps that behave like desktop apps. |
| System menu bar | macOS: the app's menus go in the global menu bar; the window shows none. |
| Collapsed | A window narrower than the titles, or a custom title bar: the titles fold into one `menu` icon button (the "hamburger") opening the same menus as a cascade. |
| None | Touch hosts. Commands live in the AppBar's More menu, context menus and the CommandPalette. |

Every command in the menu bar should also be reachable from the CommandPalette; frequent ones also belong in a Toolbar. Commands on one object are a ContextMenu.

## Specs
| Part | Value |
|---|---|
| Bar height | `control-sm` 32, padding `space-1` 4 at the ends |
| Title | height `control-xs` 24, padding `space-2` 8, `radius-xs`, `body-medium` 14/20, `on-surface`; titles touch (gap 0) |
| Title open | `secondary-container`, `on-secondary-container` |
| Menu | `surface-container`, `radius-sm`, `elevation-2`, padding `space-2` 8 top and bottom, width 200-320 (fits the longest label plus shortcut); placement below |
| Item | `control-sm` 32 tall (density -2), `space-3` 12 sides, gap `space-2` 8, `body-medium` 14/20 `on-surface` |
| Leading slot | 18 (`icon-sm`), `on-surface-variant`; reserved in every item of a menu when any item has a check or icon |
| Shortcut | `body-medium` 13/20 `on-surface-variant`, end-aligned, `space-8` 32 minimum from the label |
| Submenu arrow | `chevron-right` 18, `on-surface-variant` |
| Separator | `divider` 1, `outline-variant`, `space-2` 8 margin |
| Hover / focus | state layer `on-surface` at `state-hover` / `state-focus`; focus ring inset 3px |
| Parent of an open submenu | `on-surface` at 8% held |
| Disabled | label and shortcut `on-surface` 38%, no state layer |
| Destructive | label and icon `error`, last in its group after a separator |

The open menu's top edge is 2 below the bar's title (`top = title bottom + 2`); a submenu overlaps its parent by 4 and starts 8 above the parent item so their labels line up.

## States
- Closed: titles at rest; hover shows the state layer.
- Alt held (Windows, Linux): access keys underline; releasing Alt alone focuses the first title (menu mode).
- Open: one title shows `secondary-container`; its menu is below. While any menu is open, hovering another title switches menus without a click.
- Item: hover, focus (ring), pressed, disabled, checked (check in the leading slot), radio (a 6px dot), submenu open.
- Collapsed: a single `menu` icon button in the title bar.

## Behaviour
- Pointer: press a title to open; press again or press outside to close. Release on an item after pressing a title runs it (press-drag-release). Hovering a submenu item opens it after `duration-medium-4`; moving toward the submenu along a diagonal does not close it.
- Keyboard: Alt or F10 enters menu mode on the first title. Left/Right move between titles (and open the neighbour if a menu is open); Down, Enter or Space open. In a menu, Up/Down move (wrapping), Home/End jump, Right opens a submenu, Left or Escape closes one level, Escape on a top menu returns to the title and a second Escape leaves menu mode. Typing a letter moves to the next item starting with it; an access key runs its item.
- Running a command closes all menus and returns focus to where it was before menu mode.
- Shortcuts work whether or not the menu is open; the menu only shows them.
- Items never disappear because they are unavailable: disable them, so the menu's shape stays learnable.
- Motion: menus appear with a fade and 4px slide down, `ease-emphasized-decelerate` over `duration-short-4`; switching between titles is instant; closing fades over `duration-short-2` with `ease-emphasized-accelerate`. Reduced motion: fade only.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | In-window bar, 32 tall; access keys underline on Alt; F10 enters menu mode; shortcuts spelled "Ctrl+Shift+F"; menus follow the Windows 11 look (this spec already matches: `radius-sm`, 32 items). |
| macOS | System menu bar. The app menu (named by the app) comes first with About, Settings (⌘,), Hide and Quit; then File, Edit, View, the app's own menus, Window, Help. Shortcuts as symbols (⇧⌘F); no access keys; Help includes the system search field. |
| Linux | KDE: in-window bar, or the global menu when the desktop uses one (export over DBus). GNOME: no menu bar; a primary menu (`menu` icon button at the end of the header bar) holds the app-level commands. |
| Android | None. |
| iOS | None on iPhone; on iPad with a hardware keyboard, the menus appear in the system's Command-key overlay and the iPadOS menu bar, from the same model. |
| Web | In-window bar for desktop-class apps; `role="menubar"` with the full keyboard model; do not capture browser shortcuts (Ctrl+W, Ctrl+T). |

## Accessibility
- Role MenuBar with Menu, MenuItem, MenuItemCheckbox and MenuItemRadio children; titles report Has popup = menu and Expanded.
- Each item's name is its label; its shortcut is exposed as the keyboard shortcut property, not in the name.
- Disabled items report Disabled and remain reachable by arrow keys.
- Opening a menu moves focus to its first enabled item and announces the menu's name and item count.
- Contrast: `on-surface` on `surface-container` 7:1 in light and dark; disabled items are exempt but must stay legible (38%).
- Targets: 24-tall titles and 32-tall items meet the pointer minimum in the bar's width only for titles; this is a pointer-only component, and every command is also in the CommandPalette.
- Reduced motion: fade only, no slide.

## Content
- Titles: one word, standard names in standard order: File, Edit, View, then app-specific (Build, Run), Window, Help.
- Items: verbs or verb phrases in sentence case: "Find in files", "Close window". End with an ellipsis only on hosts that require it for commands that open a dialog (macOS, Windows): "Export...".
- Check items: name the state that is on when checked: "Word wrap", not "Toggle word wrap".
- Access keys: the first letter unless taken; never on a letter with a descender if avoidable.

## e.ui today
`navigation.menu_bar` lays out each menu's title as an Outlined `overlay.menu_button` on `surface-variant`, titles touching, and shows the menu at `open` `space-xs` below its title; the caller flips `open` in `toggles`. To reach this design:
- Draw titles as 24-tall flat items (state layer, `secondary-container` when open), not Outlined buttons whose borders touch.
- Draw menus per the Menu spec: `surface-container`, `radius-sm`, 32 items with leading slot, shortcuts and separators; add check, radio and submenu items to `overlay.MenuItem`.
- Implement menu mode: Alt/F10, Left/Right between titles with the open menu following, hover-switching while open, typeahead and access keys.
- Stop the key collision: keys are 16 apart, so a 15th item collides with the next title; derive item keys from a per-menu base with no fixed stride, or reject menus over 14 items with `TooLarge`.
- Add a macOS path that exports the same `MenuBarItem` model to the system menu bar instead of drawing it, and a collapsed single-button form.
