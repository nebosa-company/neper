# KeyValueEditor

A key-value editor lets the person build and edit a list of named values, such as environment variables, HTTP headers or labels, as rows of a name field and a value field.

## Anatomy
1. Title (from the surrounding form or section): `title-medium`.
2. Column labels: "Name" and "Value" once, above the columns, in `label-medium` `on-surface-variant`.
3. Pair row: a name field, a value field and a Remove icon button, `space-2` 8 apart.
4. Fields: outlined dense fields, 40 tall (32 in dense tools), names in `code` when names are identifiers.
5. Secret value (optional): masked with bullets, with a Show value icon button inside the field's end.
6. Validation message: under the row, `body-small` `error` with the `error` icon (duplicate names, invalid characters, empty names with a value).
7. Empty row: a last row with placeholders "Add a name" and "Value"; typing in it creates a pair and a new empty row below.
8. Actions: an "Add variable" text button, and a Table / Text segmented button to switch to text mode.

## Variants and when to use
| Variant | Use for |
|---|---|
| Table mode | The default: pair rows, one at a time. |
| Text mode | Pasting or bulk editing: one `NAME=value` per line in a mono text area, parsed back into pairs when switching. |
| Ordered | Where order matters (HTTP headers, PATH entries): rows get drag handles and move like Reorderable list. |

Use Property grid when the names are fixed and only values change. Use a Token field for a set of plain tags without values. Use Data grid for more than two columns.

## Specs
| Part | Pointer (density -1) | Dense (density -2) | Touch |
|---|---|---|---|
| Columns | name 2fr, value 3fr, remove 40 | same, remove 32 | a List of two-line rows (name headline, value supporting) |
| Row gap | `space-2` 8 between rows and between fields | `space-1` 4 | List |
| Field | outlined, `control-md` 40, `radius-xs`, 1px `outline` (2px `primary` focused, 2px `error` invalid), `space-2` 8 padding | `control-sm` 32 | edit sheet with full Text fields |
| Name text | `code` 13/20 for identifiers, else `body-medium` | same | `code` headline |
| Column labels | `label-medium`, `on-surface-variant`, `space-2` inset | same | none |
| Remove | icon button 40 (`close`), `on-surface-variant` | 32 | in the edit sheet as a Delete text button in `error` |
| Show value | icon button 32 inside the field (`visibility`) | 24 | in the sheet |
| Message | `body-small` `error`, 16 icon, `space-1` gap, spans the two field columns | same | field supporting text |
| Actions row | `space-2` above; Add variable (text button with `add`) at the start, the mode switch (small segmented, 32) at the end | same | tonal Add variable button under the list |
| Text mode | mono `code` text area, 2px `primary` focused outline, `radius-xs`, a `body-small` hint below | same | same |

## States
- Field states: rest, hover (outline `on-surface`), focus, invalid, disabled; as Text field.
- Remove button: hover and pressed layers; focus ring outside.
- Empty row: placeholders only, no Remove; it becomes a pair on the first character typed.
- Duplicate name: both rows with the name show the `error` outline and the message on the later row: "API_URL is already set on row 2".
- Secret: masked; Show value reveals for as long as the field has focus or 30 s.
- Removed: the row collapses (`duration-short-4`, `ease-emphasized-accelerate`) and a snackbar offers Undo.
- Read-only pairs (inherited, managed): plain text with a lock description, no Remove.
- Empty list: only the empty row and the Add button, with a hint "Add variables your build can read".

## Behaviour
- Tab moves name, value, Remove, then the next row's name; typing in the empty row adds a pair and keeps focus in place.
- Enter in a value field moves to the next row's name (creating the empty row's pair if needed); Shift+Enter moves up.
- Ctrl+Backspace (⌘⌫) in an empty name field removes the row and moves focus to the previous one; Delete on a focused Remove button removes.
- Pasting several `NAME=value` lines into a name field splits them into pairs.
- Add variable focuses the empty row's name field.
- Mode switch: Table to Text serialises in order; Text to Table parses, keeping comments as they were; lines that do not parse keep the editor in Text mode with a message naming the line.
- Validation runs on blur and before save; the form's Save stays enabled and moves focus to the first error.
- Reduced motion: no collapse animation on remove.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Density -1 in settings, -2 in tool panes; Ctrl shortcuts as above. |
| macOS | Density -1; ⌘⌫ removes; the editor matches Xcode's scheme environment editor with name and value columns. |
| Linux | Density -1; GNOME places it in a boxed list with an add row at the end. |
| Android | Touch: a List of pairs; tapping opens a bottom sheet with Name and Value fields, Save and Delete; Add variable opens an empty sheet. |
| iOS | Touch: an inset grouped list; tapping pushes an edit form; swipe to delete. |
| Web | Density by pointer; real `<input>`s with visible column labels referenced by `aria-labelledby` plus the row's name; text mode is a `<textarea>`. |

## Accessibility
- Role table named by the section ("Environment variables"), with column headers Name and Value; each pair is a row whose cells are the two fields and the Remove button.
- Field names include the pair: the name field is "Name, row 2"; the value field is "Value of API_URL"; Remove is "Remove API_URL".
- Errors: fields report invalid and are described by the message; the message is announced when it appears.
- Adding and removing announce "Variable added" and "API_URL removed. Undo available".
- Secret values are password fields; Show value is a toggle button with Pressed state.
- Contrast: field outlines `outline` 3:1; text 4.5:1; errors use icon and text.
- Target: 40 fields and 40 Remove buttons (48 on touch in the sheet).
- Reduced motion as in Behaviour.

## Content
- Column labels: "Name" and "Value" (or the domain's words: "Header", "Value").
- Add button: "Add variable", "Add header": the noun of the thing.
- Messages: what is wrong and where: "API_URL is already set on row 2", "Names can use letters, digits and underscores".
- Placeholders: "Add a name", "Value".

## e.ui today
`collection.key_value_editor` stacks a row per pair of a "Key" text field, a "Value" text field and a plain "x" remove button, with an outlined Add button below; every keystroke, remove and add is reported. To reach this design:
- Label the columns once and name each field by its pair ("Value of API_URL"); today every field is labelled "Key" or "Value" on every row.
- Name Remove buttons "Remove API_URL" and draw a `close` icon; today every one is named "x".
- Give the table real cells: today it claims two columns while each row holds three controls and no cell roles.
- Add the empty add-row, duplicate-name validation, secret values, text mode and removal with Undo; add placeholders so empty pairs are not blank frames.
- Take "Key", "Value", "x" and "Add" from the caller for localisation.
- Use outlined dense fields with `on-surface` text (today field text is in `primary`).
