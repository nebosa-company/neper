# ShortcutRecorder

A shortcut recorder shows a keyboard shortcut as key caps and, when pressed, records the next key combination as the new binding, for keyboard settings pages.

## Anatomy
1. Field: a 40 tall outlined box, `radius-xs`, 1px `outline`, 220 wide.
2. Key caps: one Kbd per key in the host's order and names ("Ctrl", "Shift", "P"; on macOS the glyphs ⌃ ⌥ ⇧ ⌘).
3. Hint: "Not set", or "Press a key" while recording, in `body-medium` `on-surface-variant`.
4. Recording dot: an 8 `primary` circle at the start while recording.
5. Trailing button: clear (`close`) on hover and focus when set; the `keyboard` glyph when not set; `error` when in conflict.
6. Supporting line: "Escape to cancel" while recording, or the conflict message.

## Variants and when to use
| Variant | Use for |
|---|---|
| Row recorder (label left, recorder right) | A keyboard settings list. Default. |
| Inline recorder | A single binding in a dialog (a "global hotkey" setting). |
| Read-only key caps | Showing, not editing, a shortcut: use Kbd alone. |

Use a Text field for typed text; a recorder never inserts characters. Use a Menu's trailing shortcut text to display bindings in menus.

## Specs
| Part | Value |
|---|---|
| Height | `control-md` 40 (`control-sm` 32 at density -2) |
| Width | 220 (180 min); key caps never wrap |
| Padding | `space-3` 12 start, `space-1` 4 end |
| Outline | 1px `outline`; hover 1px `on-surface`; recording 2px `primary` over `primary` 8%; conflict 2px `error` |
| Shape | `radius-xs` 4 (the field shape) |
| Key caps | `nu-kbd`: 24 tall, `radius-xs`, 1px `outline-variant` (2px bottom), `font-mono` 12, `on-surface-variant` on `surface-container-lowest`; `space-1` 4 apart |
| Hint | `body-medium`, `on-surface-variant` (`on-surface` while recording) |
| Trailing button | `control-sm` 32 icon button, `icon-sm` 18 |
| Supporting line | `body-small`, `on-surface-variant`, or `error`; `space-1` below |
| Row | 48 min (`control-lg`), label `body-medium` start, recorder end |

## States
- Rest: key caps, or "Not set".
- Hover: outline `on-surface`; the clear button appears.
- Focus: the ring 2px outside the field; the clear button appears.
- Recording: 2px `primary` outline, 8% `primary` fill, the dot, held modifiers shown as caps, "Press a key".
- Conflict: 2px `error` outline, `error` icon, message naming the other command and the fix. Status is also in words, never colour alone.
- Disabled (system or policy binding): outline 12%, caps 38%, a supporting line saying who set it.

## Behaviour
- Press, Enter or Space starts recording. While recording, every key goes to the recorder, including Tab: Tab and shortcuts are not delivered to the app.
- Modifiers alone are shown but do not commit. The first non-modifier key commits the combination with the held modifiers.
- Escape cancels and keeps the old binding. Backspace or Delete, with no modifier, clears the binding. Recording also cancels on blur or after 10 seconds without a key.
- Refuse, with a message, combinations the host reserves (Alt+F4, ⌘Q, Ctrl+Alt+Del, Super on Linux) and plain letters without a modifier (unless the setting allows single keys, as in a game or a vim-style app).
- On conflict, keep the new value pending: Enter reassigns (removing it from the other command), Escape cancels.
- The clear button clears without recording. Entering recording has no motion; the outline change is instant.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Names "Ctrl", "Alt", "Shift", "Win", joined visually as caps; order Ctrl, Alt, Shift, Win, key. |
| macOS | Glyphs ⌃ ⌥ ⇧ ⌘ in that order, then the key; ⌘ is the primary modifier; follows the System Settings > Keyboard Shortcuts recorder. |
| Linux | "Ctrl", "Alt", "Shift", "Super"; GNOME order Super, Ctrl, Alt, Shift; respect keys grabbed by the compositor. |
| Android | Only with a hardware keyboard attached; otherwise hide the setting. |
| iOS | Only on iPad with a hardware keyboard; ⌘-based glyphs as macOS. |
| Web | Browser-reserved combinations (Ctrl+W, Ctrl+T, Ctrl+N) cannot be captured: refuse them with a message. |

## Accessibility
- Role button with a value: name = the command ("Build project shortcut"), value = the binding spoken in words ("Control B"), or "Not set". While recording, state pressed and a live announcement "Recording. Press a shortcut, or Escape to cancel".
- Announce the result ("Control Shift P") or the conflict message (assertive).
- Screen-reader users need their reader's pass-through key: document that the recorder captures all keys only while recording.
- Key caps are decorative; the value carries the binding. Target 40, padded to 48 on touch.

## Content
Command names are the menu names ("Build project"). Key names follow the host ("Ctrl", not "Control" or "CTRL"). Conflicts name the other command and the fix: "Used by Open file. Enter to reassign". Not set reads "Not set".

## e.ui today
`control.shortcut_recorder` draws an Outlined pressable (`radius-md`) with the chord as `Ctrl+Shift+...` text in the Body role and `primary`, and "Press keys" with the selected tint while recording; the chord is set as the Group's value, not the Button's, and `label` is not drawn. To reach this design:
- Draw key caps (Kbd) per key in host order and names (glyphs on macOS) instead of `+`-joined English text.
- Draw the recording look (2px `primary`, 8% fill, dot, live modifiers) and the conflict state with a message; add the clear button.
- Put the binding as the Button's value and give it a name from the command.
- Refuse reserved combinations per host; cancel on blur and timeout; Backspace clears.
- Localise "Press a key", "Not set" and key names.
