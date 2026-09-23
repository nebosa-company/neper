# CommandPalette

A command palette runs any command, opens any file or jumps to any symbol by typing part of its name: a search field over a ranked, grouped list of matches with their shortcuts, one chord away from anywhere in the app.

## Anatomy
1. Scrim: `scrim` at `scrim-opacity` 32%.
2. Panel: `surface-container-high`, `radius-xl`, `elevation-3`, top-centred.
3. Field: 56 tall, `search` icon, the query in `body-large`, an optional mode prefix (">" commands, "@" symbols, ":" line) in `primary` 600, and an Esc key hint.
4. Busy bar (while results load): a 2px indeterminate linear progress under the field.
5. Group headings: `label-medium` `on-surface-variant` ("Recent", "Commands", "Files").
6. Row: 18 icon, the command's category in `on-surface-variant` ("Build:"), its name with the matched characters in bold `primary`, and its shortcut as key caps or a status word at the end.
7. Footer: key hints and the mode hint, `body-small`.
8. Empty state: a statement, a suggestion and one text button.

## Variants and when to use
| Variant | Use for |
|---|---|
| Commands (">") | Run any command in the app. Ctrl+Shift+P (⇧⌘P). |
| Files (no prefix) | Open a file or document by name, recent first. Ctrl+P (⌘P). |
| Symbols ("@") / Line (":") | Jump within the current document. |
| Compact | Phones: a full-screen search view with a Back arrow and 48 rows. |

The mode is a prefix in one component, not four components: typing or deleting the prefix switches mode in place. Switching among already-open documents in recency order is the WindowSwitcher. Searching the content of a list is a SearchBar in that list. A menu of commands for one object is a ContextMenu.

## Specs
| Part | Pointer | Compact |
|---|---|---|
| Panel | 560 wide (max window width - 32), `surface-container-high`, `radius-xl`, `elevation-3`; top edge 64 below the window's top (24 in short windows) | full screen, `surface` |
| Max height | 60% of the window; the results scroll, the field and footer stay | full |
| Field | `control-xl` 56, 16 sides, gap 12; `body-large` 16/24; prefix `primary` 600 | search bar 48, `radius-full`, `surface-container-high` |
| Divider | 1 `outline-variant` under the field | busy bar in its place |
| Results padding | 4 top, 8 sides, 8 bottom | 0 |
| Group heading | `label-medium` 12/16 600, `on-surface-variant`, 12 sides, 8 top, 4 bottom | same |
| Row | `control-md` 40, 12 sides, `radius-sm`, gap 12; `body-medium` 14/20 `on-surface` | 48, `body-medium` |
| Category | `on-surface-variant`, 4 before the name | same |
| Match highlight | weight 700, `primary` (`on-secondary-container` in the selected row) | same |
| Shortcut | key caps 20 tall, `nu-kbd` at 11 px, gap 4 | none |
| Selected row | `secondary-container`, content `on-secondary-container` | pressed only |
| Hover | `on-surface` at `state-hover` | |
| Unavailable row | 38% content, a trailing word saying why ("Indexing now") | same |
| Footer | 32 tall, 16 sides, 1 `outline-variant` top border, `body-small` `on-surface-variant` | none |
| Empty | 24 vertical, 16 sides, centred; `title-small` statement, `body-medium` suggestion, a text button | same |

## States
- Opening: field focused and empty (or holding the mode prefix); the list shows Recent first, then all commands alphabetically.
- Typing: results filter on each keystroke; the first result is selected after every change of the query.
- Loading: file and symbol modes may search asynchronously: the busy bar shows and results stream in without moving the selected row.
- Selected row, hover, unavailable (still listed, not runnable, reason at the end).
- No matches: the empty state names the query, suggests the other mode, and offers one action.
- Running: the palette closes before the command runs, so the command acts on the window, not on the palette.

## Behaviour
- Open: Ctrl+Shift+P for commands, Ctrl+P for files (⇧⌘P, ⌘P on macOS), or from the Help or View menu. The same chord while open closes it.
- Matching: fuzzy on the category plus name ("rb" finds "Rebuild"), ranking exact prefix, then word-start matches, then subsequences; recent items rank higher. The palette owns filtering; the caller supplies the full command list and a recency score.
- Keys: Up/Down move (wrapping), Page Up/Page Down move by a page, Home/End move the cursor in the field (Ctrl+Home/End move to the first and last result), Enter runs, Ctrl+Enter (files) opens to the side, Escape closes and returns focus where it was; Tab does not leave the palette.
- Pointer: hover selects, press runs; a press on the scrim closes.
- Commands that need an argument open a second step in the same panel (the field's placeholder asks for it, "Branch name"), with Back on Backspace in an empty field.
- The query is kept when the palette is reopened within the same session, selected so typing replaces it.
- Motion: the panel fades and moves down 8 px into place with `ease-emphasized-decelerate` over `duration-short-4`; closing fades over `duration-short-2` with `ease-emphasized-accelerate`; results update without animation. Reduced motion: fade only.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Ctrl+Shift+P / Ctrl+P; shortcuts spelled "Ctrl+Shift+B"; the palette lists menu bar commands with their menu path as the category. |
| macOS | ⇧⌘P / ⌘P; shortcuts as symbols (⇧⌘B); the Help menu's system search also finds menu items: keep command names identical to menu item names so both agree. |
| Linux | Ctrl+Shift+P / Ctrl+P; on GNOME, where there is no menu bar, the palette is the main keyboard route to commands, so every primary-menu command must be listed. |
| Android | Compact full-screen search view from an app bar search action; no key hints; 48 rows; the system back closes. |
| iOS | Compact full-screen search view; on iPad with a keyboard the pointer layout, opened with ⇧⌘P and listed in the Command-key overlay. |
| Web | Pointer layout; Ctrl+K is a common, browser-safe alternative chord (Ctrl+P prints); `role="combobox"` with a `listbox` popup and `aria-activedescendant`. |

## Accessibility
- A Dialog (modal) named "Command palette" containing a Combobox (the field, Expanded, controls the list) and a Listbox of Options; group headings are Groups with names.
- Focus stays in the field; the selected option is conveyed with the active-descendant relation, so each arrow press announces "Build: Rebuild project, Ctrl+Shift+B, 1 of 4".
- The result count is announced politely after typing pauses ("4 commands"); no matches announces the empty statement.
- Unavailable options report Disabled and include their reason in the description.
- Matches are marked by weight as well as colour.
- Contrast: rows `on-surface` on `surface-container-high`, highlights `primary` 4.5:1 or better; key caps `on-surface-variant` on `surface-container-lowest`.
- Targets: 40 rows on pointer, 48 on compact.
- Reduced motion: fade only.

## Content
- Command names: a category and a verb phrase, sentence case: "Build: Rebuild project", "View: Toggle word wrap". The same words as the menu item.
- Empty state: `No commands match "deplyo"`, then one suggestion and one action ("Search files for "deplyo"").
- Unavailable reasons in two or three words: "Indexing now", "No project open".
- Placeholder by mode: "Type a command", "Search files by name", "Go to symbol", "Go to line".

## e.ui today
`navigation.command_palette` puts a `control.search_field` (placeholder "Type a command") over the caller-filtered `commands` as full-width buttons in a `surface` panel with `border-regular`, `radius-md` and `elevation-3`, centred, no scrim; Up/Down change `active`, Enter or a tap runs. To reach this design:
- Fix the key collision: the field's Clear button (`key + 2 + 1`) and the first row (`key + 3 + 0`) share `key + 3` whenever text is typed; give rows their own base.
- Wire Clear (it is passed a zero `Submit` and does nothing), and stop it being pushed past the clipped edge: the field is already the panel's full inner width, so reserve its space inside the field.
- Reset `active` to 0 on every query change (today the caller must clamp it to the new `commands.len`), and wrap at the ends.
- Add the scrim, top-centred placement, `surface-container-high` with `radius-xl` and no border, the 56 field with mode prefixes, grouped rows with categories, match highlighting and shortcuts, the footer, the empty and loading states.
- Move fuzzy matching and recency ranking into the component (the caller passes all commands), and report Combobox/Listbox semantics with an active descendant instead of ListItems.
- Add the compact full-screen variant.
