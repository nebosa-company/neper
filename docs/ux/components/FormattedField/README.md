# FormattedField

A formatted field is a text field that knows the shape of its value, inserting separators as people type and checking the result when they leave, for dates, codes, keys, versions and phone numbers.

## Anatomy
1. Field: the Text field (outlined or filled) with its label, value, supporting text and optional leading or trailing icon.
2. Typed text: `on-surface`.
3. Mask remainder: the rest of the pattern after the caret ("DD") in `on-surface-variant`, shown only while focused.
4. Placeholder: the whole pattern ("YYYY-MM-DD") while empty and unfocused.
5. Prefix / suffix: fixed text outside the value ("v", "ms") in `on-surface-variant`.
6. Supporting text: what the pattern means, or the error; an optional counter at the end.
7. Status icon: `error` when invalid, `check-circle` in `success` when a checked value is confirmed valid (optional).

## Variants and when to use
| Variant | Behaviour | Use for |
|---|---|---|
| Masked | Fixed-length pattern; separators inserted; remainder shown | Dates, times, licence keys, card-style groups. |
| Validated | Free typing; checked on leave | Versions, email addresses, URLs, IP addresses. |
| Normalised | Accepts loose input, rewrites it on leave | Phone numbers, keys pasted with spaces or lowercase. |

Use a Date picker or Time picker when people pick rather than type; a Spin box for quantities; a plain Text field when any text is valid. Never mask names or free-form addresses.

## Specs
| Part | Default (touch) | Dense (density -1) |
|---|---|---|
| Height | `control-xl` 56 | `control-md` 40 |
| Value | `body-large`; codes in `font-mono` 15 | `body-medium`; codes `code` 13 |
| Mask remainder | same style, `on-surface-variant` | same |
| Prefix/suffix | `body-large` `on-surface-variant`, `space-1` from the value | `body-medium` |
| Supporting text | `body-small`, `on-surface-variant` (`error` when invalid); counter end-aligned | same |
| Outline | 1px `outline`; 2px `primary` focused; 2px `error` invalid | same |
| Icons | `icon-md` 24 leading/trailing; error icon `error`; valid icon `success` | same |
| Width | sized to the pattern plus 20%, 280 max on compact | same |

## States
- Empty, unfocused: placeholder pattern, never invalid, however strict the format.
- Focused, typing: remainder of the mask shown; partial input is never flagged.
- Valid (optional confirmation): `check-circle` in `success` with a word in supporting text ("Valid key").
- Invalid: after leaving the field, or on submit: 2px `error` outline, `error` icon, label and supporting text in `error`, message that says the fix. Clears as soon as the text becomes valid again.
- Disabled and read-only: the Text field's.

## Behaviour
- Typing a character that fits the next slot inserts it and any fixed separators after it; a separator typed early is accepted and skips ahead ("2026/9" becomes "2026-09-" in a date).
- Characters that can never fit are ignored silently; for a masked field, the keyboard type follows the slot (numeric for digits).
- Backspace deletes the character before the caret and any separator it passes; the caret never lands inside a separator.
- Paste accepts loose input and normalises it (strip spaces, uppercase keys) before checking.
- Leaving the field (blur or Enter) validates and, for normalised fields, rewrites the text to canonical form. The rewrite is instant; the error appears with a `duration-short-2` fade.
- Undo restores the text as typed, before normalisation.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Dense; locale date order from the region setting; Ctrl+Z undo covers normalisation. |
| macOS | Dense; NSFormatter behaviour: validation on leave, the field does not beep for ignored characters. |
| Linux | Dense; follow the locale (`LC_TIME`, `LC_NUMERIC`) for patterns. |
| Android | Default; `inputType` per slot (number, phone, text caps characters for keys). |
| iOS | Default; `keyboardType` per slot and `textContentType` for phone and one-time codes. |
| Web | Default on touch, dense with a pointer; `inputmode` per pattern; do not use `type="date"` here (that is the Date picker). |

## Accessibility
- Role text field, name = label, description = supporting text; the pattern is announced as the description ("Year, month and day, YYYY-MM-DD").
- The mask remainder is not read as content; the value read is only what was typed.
- Invalid state is exposed and the message linked as the error message; announce it once when it appears (polite).
- Inserted separators are announced with the character typed ("9, dash").
- Contrast: remainder and placeholder are `on-surface-variant` (4.5:1).

## Content
The label names the value ("Release date"); supporting text says the shape in words ("Year, month and day"). Errors state the rule and the fix: "Month must be 01 to 12", not "Invalid format". Use the pattern letters people recognise: YYYY, MM, DD, HH.

## e.ui today
`control.formatted_field` is `text_field` with a `Format { accept, format }` adapter: invalid whenever `accept` rejects the buffer, and Enter writes the formatted text back. To reach this design:
- Do not judge an empty or untouched field (today a strict adapter marks a fresh field invalid from the first frame); validate on leave and on submit only.
- Add a mask description to the adapter so the field can insert separators, show the remainder and keep the caret out of separators.
- Normalise on blur as well as Enter, and keep an undo step before the rewrite.
- Draw the invalid look through the redesigned field (2px `error`, icon, message) with a caller-supplied fix message, and add prefix and suffix slots.
- Publish the pattern as the field's description.
