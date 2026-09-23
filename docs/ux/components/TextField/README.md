# TextField

A text field takes typed input: one line, a secret, or several lines. Filled and outlined variants carry a floating label, optional icons and affixes, supporting text, a counter and an error.

## Anatomy
1. Container: filled (`surface-container-highest`, top corners `radius-xs`) or outlined (1px `outline`, `radius-xs` all round).
2. Active indicator (filled only): a 1px line along the bottom edge, 2px while focused or invalid.
3. Label: rests inside the box in `body-large`. It floats to the top in `body-small` when the field is focused or holds a value. On an outlined field it sits in a notch in the outline.
4. Input text: `body-large`, one line, or wrapping in a text area. The caret is 2px `primary`.
5. Optional leading icon: 24px, 12px before the text.
6. Optional prefix or suffix: fixed text such as `https://` or `ms`, in `on-surface-variant`.
7. Optional trailing icon or icon button: an error icon, clear, or password reveal.
8. Supporting text: `body-small`, 4px below the box and inset 16px. It holds help or the error message.
9. Optional character counter: `body-small`, at the end of the supporting line.

## Variants and when to use
| Variant | Container | Use for |
|---|---|---|
| Filled | `surface-container-highest`, bottom indicator | Short forms on touch hosts, fields in sheets and dialogs, and single fields that need emphasis, such as sign-in. The default on Android, iOS and touch Web. |
| Outlined | 1px `outline` | Long forms and dense settings, and anywhere a column of fields would look heavy when filled. The default on Windows, macOS, Linux and desktop Web. |
| Dense (outlined, 40) | 1px `outline` | Tool windows, inspectors and table filters. The label moves outside the box as a Field label. |
| Password | either | Secrets. It masks the value with bullets and adds a reveal button. |
| Text area (multiline) | either | Free text of more than one sentence, such as release notes or descriptions. It grows from 3 rows to its maximum, then scrolls. |

Use one variant throughout a form. For a query use Search bar. For one of a fixed set of values use Select. For numbers with steps use Spin box. For a list of tokens use Token field. For a label, help and error on a control that is not a text field, wrap it in Form field.

## Specs
| Part | Touch (default) | Pointer (density -1) | Dense (density -2) |
|---|---|---|---|
| Container height | `control-xl` 56 | `control-lg` 48 | `control-md` 40 |
| Side padding | `space-4` 16 | `space-4` 16 | `space-3` 12 |
| Icon to text gap | `space-3` 12 | `space-3` 12 | `space-2` 8 |
| Label | `body-large` resting, `body-small` floated | same | outside, `title-small` (Field label) |
| Input text | `body-large`, `on-surface` | `body-large` | `body-medium` |
| Radius | `radius-xs` 4 (filled: top corners only) | same | same |
| Supporting text | `body-small`, `space-1` 4 below, 16 inset | same | same, 0 inset |
| Leading and trailing icons | `icon-md` 24, `on-surface-variant` | same | `icon-sm` 18 |
| Trailing icon button | `control-md` 40 circle, 48 target | 40, 32 target | `control-sm` 32 |
| Text area | min 112 (3 rows), grows to `maxRows` (default 8) | same | min 88 |

| Part | Colour role |
|---|---|
| Filled container | `surface-container-highest`; hover adds `on-surface` at `state-hover` |
| Filled indicator | `on-surface-variant` 1px; focused `primary` 2px (`outline-focused`); invalid `error` 2px |
| Outline | `outline` 1px; hover `on-surface` 1px; focused `primary` 2px; invalid `error` 2px |
| Label | `on-surface-variant`; focused `primary`; invalid `error` |
| Input text | `on-surface`; placeholder `on-surface-variant` |
| Prefix, suffix, icons | `on-surface-variant`; trailing error icon `error` |
| Caret | `primary`; selection `primary-container` behind `on-primary-container` text |
| Supporting text, counter | `on-surface-variant`; invalid `error` |
| Read-only outline | `outline-variant`, no fill; the text stays `on-surface` |

A field fills its column. Its minimum width is 120. In a multi-column form it spans the column. Never size a field to its content.

## States
- Enabled: the label rests inside the box and the placeholder is hidden.
- Hover: filled adds the `state-hover` layer. Outlined darkens the outline to `on-surface`.
- Focused: the label floats and turns `primary`. The indicator or outline goes 2px `primary` and the caret blinks. The 2px focused outline is the field's focus indicator, so no separate ring is drawn. The placeholder, if any, shows only now.
- Filled with a value: the label stays floated in `on-surface-variant`.
- Invalid: label, indicator or outline, and supporting text turn `error`. A trailing error icon appears, and the supporting text is replaced with the reason. The word and the icon carry the state, not the colour.
- Disabled: container `on-surface` at 4%, indicator, label, text and icons `on-surface` at 38%. Not focusable. The value can't be copied.
- Read-only: no fill, `outline-variant` outline, text at full `on-surface`. Focusable and selectable, so the value can be copied. It never shows a caret.
- Password revealed: the reveal button shows as selected (`primary` icon) and the value is shown in plain text.

## Behaviour
- Pointer: a press anywhere in the container focuses the field and places the caret. A press on the label or the prefix does the same. A drag selects text and a double press selects a word.
- Touch: a tap focuses and raises the keyboard. The keyboard type follows the field's kind (email, URL, number, phone). The IME action key follows `submit`: Next when another field follows, Done or Go on the last.
- Keyboard: Tab moves between fields. Enter fires `submit` on a single line. In a text area Enter inserts a newline and Ctrl+Enter (⌘Return on macOS) submits. Home and End go to the start and end of the line, Ctrl+Home and Ctrl+End to the start and end of the text. Arrow keys move the caret, Shift extends the selection, and Ctrl+Z undoes. Escape leaves the text alone and bubbles to the enclosing dialog or view.
- Label motion: the label floats and sinks over `duration-short-4` with `ease-standard`. With reduced motion it cross-fades between the two positions.
- Counter: shown when a maximum is set. Past the limit, input is not blocked. The counter and field turn invalid and the message says by how much: "6 characters over the limit".
- Validation: validate on blur the first time, then on each change until the field is valid again. Never mark an empty required field invalid before the first submit or blur.
- Password: the reveal button toggles masking and keeps focus in the field. The field masks again on blur and on submit. Copy and cut are disabled while the value is masked. When Caps Lock is on, the supporting text says "Caps Lock is on".
- Text area: grows row by row up to `maxRows`, then scrolls inside. The container never scrolls the page.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Outlined, 48 in content and 40 dense with the label above in tool windows and settings. While focused and not empty, a clear button appears (Fluent convention). IME composition text is underlined in `primary`. The reveal button shows only while the password field has focus. |
| macOS | Outlined, 48, or 40 dense in inspectors. Forms may put labels leading and right-aligned (see Form). ⌘A, ⌘Z and ⇧⌘Z work, and the system spell-check underline appears in text areas. A password field uses secure text entry (it blocks other processes from reading keystrokes) and shows the Caps Lock glyph. |
| Linux | Outlined, 48, or 40 dense. A middle click pastes the primary selection, and selecting text sets it. On GNOME, Ctrl+Backspace deletes a word. Follow the desktop's input method (IBus, Fcitx) for preedit. |
| Android | Filled, 56. The IME action key comes from `submit`. Autofill hints come from the field's kind. The keyboard pans the view so that the field and its supporting text stay visible. |
| iOS | Filled, 56, with a 44pt minimum target. The return key type comes from `submit`. `textContentType` enables password and one-time-code autofill from the keychain. The clear button appears while editing. Text follows Dynamic Type. |
| Web | A real `<input>` or `<textarea>` with a `<label>`. Set `autocomplete`, `inputmode` and `enterkeyhint` from the field's kind. 48 with a fine pointer, 56 on touch. |

## Accessibility
- Role: text field (multi-line for a text area, protected for a password). Name: the label, never the placeholder. Description: the supporting text. States: Required, Invalid, Read-only, Disabled. The value is exposed except while masked.
- Invalid ties the field to its message as its error message. Screen readers announce the message when focus enters the field. When validation fails live, the message is announced once, politely.
- The counter is announced politely when 10 characters remain and when the limit is passed, not on every keystroke.
- Contrast: input text and label 4.5:1 or better. The outline and indicator are 3:1 against the surface (non-text contrast). High contrast themes thicken the resting outline to 2px.
- Target: the whole container is the target, at 48 or more on touch. A trailing icon button has its own 48 target on touch and 32 with a pointer.
- The reveal button is a toggle button named "Show password" and reports Pressed while revealed.
- Reduced motion: the label cross-fades instead of moving, and the caret does not blink.

## Content
- Label: a noun or short noun phrase naming the value: "Project name", "Build timeout". One to three words, sentence case, no colon, no trailing period.
- Placeholder: an example of the format only, such as "build-4128". Never the label, and never instructions a reader must remember after typing.
- Supporting text: one short sentence on what is expected or why: "Shown in the sidebar".
- Error: say how to fix it, not what went wrong in the abstract. "Enter a port from 1 to 65535", not "Invalid input".
- Units go in the suffix ("ms"), not in the label.

## e.ui today
`control.field` puts a Label-role label above an outlined frame. The frame uses `surface` and `border-regular`, `radius-sm` 8 corners, is 160 wide and `control-height` tall, and shows the placeholder in `text-muted`. `text_field`, `password_field` (an asterisk per byte), `text_area` (two rows at least, no scrolling) and `search_field` wrap it. To reach this design:
- Add the Filled variant and make it the default on touch hosts. Move the label inside the box and float it, and keep the outside label only for the dense variant.
- Size the box 56, 48 or 40 by density with `radius-xs` corners. Make it fill its column instead of defaulting to 160.
- Paint the input text in `on-surface`: today it takes the outlined foreground, `primary`.
- Replace the focus border (a `focus-ring`-wide border in `focus`) with the 2px `primary` outline or indicator, and add the hover look.
- Add `FieldOptions` slots for supporting text, `max_length` with a counter, leading and trailing icons, prefix and suffix, and `max_rows`.
- `password_field`: draw bullets, add the reveal toggle, and block copy while masked.
- `text_area`: scroll the overflow (its `ponytail:` note) and grow from 3 rows to `max_rows`.
- Read-only: stop filling it with `surface-variant` and muting the text. Use an `outline-variant` outline and `on-surface` text.
