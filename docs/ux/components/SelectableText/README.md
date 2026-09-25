# SelectableText

Selectable text is read-only text the person can select and copy: ids, paths, hashes, error messages and log output.

## Anatomy
1. Text: any Text role, usually `code` for values and `body-medium` for messages.
2. Selection highlight: `primary-container` behind the selected glyphs, text turns `on-primary-container`.
3. Caret: 2 px `primary`, shown only while the text has keyboard focus (caret browsing).
4. Selection handles (touch): 12 px teardrops in `primary` under each end of the selection, with a 48 target.
5. Context surface: the desktop context menu (Menu, dense) or the touch floating toolbar (`surface-container`, `radius-sm`, `elevation-2`, text buttons).
6. Optional copy button: an Icon button (small, standard) after a single value.

## Variants and when to use
| Variant | Looks like | Use for |
|---|---|---|
| Inline value | Text, no frame | A single id, hash or path in a detail pane, usually with a copy button. |
| Message | Text, no frame | An error or result message the person may paste into a search or a ticket. |
| Block | `surface-container-high` block, `radius-sm`, `code` role | Logs, command output, stack traces. Scrolls; focusable. |

Use Text when nothing on screen needs copying (labels, headings, button text never select). Use Text field with read only when the value must look editable or sit in a form. Use a Code editor surface for more than a screen of output with search.

## Specs
| Part | Value |
|---|---|
| Text | Any Text role and colour role; values in `code` 13/20 |
| Selection | `primary-container` fill, `on-primary-container` text; unfocused window: `surface-container-highest` fill, text keeps its colour |
| Caret | 2 px wide, the line height tall, `primary`; blink 500 ms on, 500 ms off, stops after 10 s idle |
| Handles (touch) | 12 px, `primary`, hanging `space-1` under the line; target `target-touch` 48 |
| Floating toolbar (touch) | `surface-container`, `radius-sm`, `elevation-2`, padding `space-1`, text buttons `control-sm` 32 in `on-surface`, `space-2` above the selection (below if no room) |
| Context menu (desktop) | Menu, dense (36 rows): Copy, Select all, a separator, then app actions such as Search for selection |
| Copy button | Icon button small (`control-sm` 32), `on-surface-variant`, `space-1` after the value |
| Block | padding `space-3` by `space-4`, `radius-sm`, `surface-container-high`, `code` role, max height by the pane, scrolls vertically; long lines wrap unless the block is a log, which scrolls horizontally |

## States
- Rest: identical to Text. The pointer becomes an I-beam over it.
- Hover: I-beam cursor only; no layer, no underline.
- Focus (block, or caret browsing): the focus ring 3 px `focus-ring`, 2 px outside the block; caret visible.
- Selected: the highlight; it stays (in the unfocused colour) when focus moves elsewhere in the window, and clears on a press elsewhere in the same text.
- Copied: a snackbar "Copied to clipboard" on touch hosts; on desktop the copy button's icon swaps to `check` for 2 s. Never change the text itself.
- Disabled: not applicable; selectable text inside a disabled region stays selectable and keeps its colour at 38%.

## Behaviour
- Pointer: press and drag selects characters; double-click a word (an identifier with `_` and `.` counts as one word for `code`); triple-click a line or paragraph. Shift+click extends.
- Keyboard: Tab reaches a block and an inline value with a copy button (the button is the stop); arrows move the caret, Shift+arrows extend, Ctrl/Cmd+Shift+arrows by word, Home and End to the line, Ctrl/Cmd+A selects all of this text only, Ctrl/Cmd+C copies, Escape clears the selection.
- Touch: long press selects the word under the finger and shows handles and the toolbar; drag a handle to extend with a magnifier; a tap elsewhere dismisses. The toolbar fades in with a 4px drop over `duration-short-4`, `ease-emphasized-decelerate`.
- Selection never crosses into neighbouring controls; a view that needs cross-paragraph selection makes the whole region one selectable text.
- The context menu replaces the host's default only by adding to it: Copy and Select all always first.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Selection uses the accent-tinted `primary-container`; right-click opens the context menu; Ctrl+C, Ctrl+A; caret browsing with F7 where the app enables it. |
| macOS | Right-click or Control-click menu with Copy and Look Up; ⌘C, ⌘A; the unfocused-window selection turns grey (`surface-container-highest`) as AppKit does. |
| Linux | Selecting also fills the primary selection (middle-click paste) on X11 and Wayland; Ctrl+C for the clipboard. |
| Android | Long press, teardrop handles, the floating text toolbar with Copy, Select all, Share and any Process Text actions the system offers. |
| iOS | Long press, round-knob handles, the edit menu (Copy, Look Up, Translate, Share) above the selection; the magnifier loupe while dragging. |
| Web | Native text selection (`user-select: text`); the browser's context menu is kept, never suppressed; `::selection` uses the tokens. |

## Accessibility
- Role Text (static text) with the Selectable state and the Set selection and Copy actions; blocks are a focusable Document or Log region named by their pane ("Build output").
- The selection is exposed to screen readers (text range), so a reader can read and copy just the selection.
- Copy announces "Copied" politely; the copy button's name says what it copies ("Copy commit hash").
- Contrast: `on-primary-container` on `primary-container` meets 4.5:1 in every theme; the caret meets 3:1 against the ground.
- Handles and the copy button meet the 48 touch target.
- Reduced motion: the toolbar and snackbar appear without motion; the caret does not blink.

## Content
- Show the exact value; never shorten a hash or path the person will paste. When space forces truncation, truncate in the middle and copy the full value.
- Label the value with a Text in `label-medium`, sentence case, no colon: "Build ID", "Output path".
- Error messages lead with what failed, then the detail: "Linking failed: undefined symbol e_ui_control_card".

## e.ui today
`control.selectable_text` wraps a read-only `widget.edit` over the caller's `buffer` and `len` (D807): the editor gives caret, Shift+arrows and copy; any `wrap` but `.None` makes it multiline; `align`, `max_lines` and `ellipsis` are ignored. To reach this design:
- Fill the selection with `primary-container` and repaint the selected glyphs in `on-primary-container` instead of the single `Selection` colour behind unchanged text; add the unfocused-window colour.
- Report a Text role with Selectable and Copy, not an editable node that offers Set selection.
- Take it out of the tab order unless it is a block (a new `SelectableOptions { block }`), and draw the focus ring on a block.
- Add the context menu and the touch handles and floating toolbar, and word selection on double-click and long press.
- Honour `align`, `max_lines` and `ellipsis` so a selectable value lays out like its Text.
