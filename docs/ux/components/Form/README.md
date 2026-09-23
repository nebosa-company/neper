# Form

A form lays out a set of Form fields that are submitted together. It owns the column grid, the section headings, the submit and cancel actions, and what happens when a submit fails.

## Anatomy
1. Title: `title-large` in a dialog or page, or the app bar title in a full-screen form.
2. Required legend: "* Required" in `body-small`, top end. Only present when the form marks required fields.
3. Section heading: `title-small`, `on-surface`, above a group of fields.
4. Fields: Form fields on a 1- or 2-column grid. A field may span both columns.
5. Validation summary: appears above the first section after a failed submit.
6. Action row: Cancel (outlined) then the submit button (filled) at the end, or an action bar pinned to the bottom of a scrolling form.

## Variants and when to use
| Variant | Layout | Use for |
|---|---|---|
| Stacked, one column | Fields full width, labels floating or above | Compact windows (below 600), sheets, and forms of up to about six fields. |
| Two columns | Grid of 2, 24 gutter, labels above | Expanded windows (840 and up) with related short fields (name and visibility, branch and timeout). Long text always spans both columns. |
| Label column | Labels leading in a fixed column (at least 120, end-aligned) | macOS preference windows and wide settings dialogs. |
| Full-screen (compact) | App bar with close, title and a text submit action | Creating or editing an object on a phone when the form doesn't fit a dialog. |
| Instant-apply settings | No submit. Each control applies on change. | Preferences where every change is safe and reversible. Use switches, not checkboxes, there. |

A form with one field and one action (rename, search, invite by email) is a Dialog or an inline field, not a Form. Multi-step input is a Wizard or Stepper.

## Specs
| Part | Compact (touch) | Medium and expanded (pointer) |
|---|---|---|
| Columns | 1 | 1 up to 840, 2 from 840 (`window-expanded`) |
| Column gutter | none | `space-6` 24 |
| Between fields | `space-4` 16 (fields carry their 20 of support text) | `space-5` 20 |
| Section heading | `title-small`, `space-6` 24 above, `space-3` 12 below | same |
| Padding | `space-4` 16 sides | `space-6` 24 in a dialog or card |
| Field height | 56 filled | 40 dense (labels above) or 48 floating |
| Max width | the window | 720 for a two-column form, 480 for one column |
| Action row | text submit in the app bar, or full-width filled button at the bottom | end-aligned, `space-2` 8 apart, Cancel then submit |
| Action bar (scrolling form) | pinned, `surface-container`, 1px `outline-variant` top edge | same, `space-3` 12 by `space-6` 24 |

Colour: the form is `surface` (a dialog's `surface-container-high` when inside one). Sections are separated by space, not by dividers or cards.

## States
- Pristine: submit is enabled. Never disable submit only because required fields are empty: let the reader submit, then show what is missing.
- Invalid after submit: the Validation summary appears and takes focus, and each invalid field shows its error.
- Submitting: fields become read-only (not disabled, so values stay readable), Cancel stays enabled, and the submit button shows a progress ring at its own width. After 10 seconds, the action bar says what is happening ("Still creating the project").
- Submit failed (server or network): an inline error Banner above the actions with a retry. Field values are kept.
- Dirty: leaving the form with unsaved changes asks to discard them in a Dialog. Instant-apply forms never ask.

## Behaviour
- Enter in a single-line field submits the form. Enter in a text area inserts a newline, and Ctrl+Enter (⌘Return) submits from anywhere.
- Escape cancels a form in a dialog or sheet (with the dirty check). In a page it does nothing.
- Tab order follows reading order: row by row in a two-column grid, left to right then down. Never column by column.
- On a failed submit, focus moves to the Validation summary and the view scrolls it into view (`duration-medium-2`, `ease-standard`; a jump with reduced motion).
- The keyboard never covers the focused field or its message: on touch the form scrolls it into the visible area.
- Fields reflow between one and two columns at 840 with no animation.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Labels above, dense 40 fields in settings and dialogs. In a dialog the submit button comes first and Cancel last, as Fluent's content dialog orders them. In a page, keep Cancel then submit, end-aligned. Enter submits, Escape cancels. |
| macOS | Preference windows use the label column and apply instantly with no buttons. Sheets and dialogs end with Cancel then the default button (rightmost). ⌘. cancels. |
| Linux | GNOME: labels above or Adwaita preference rows, instant apply in preferences, header-bar buttons (Cancel left, submit right) in dialogs. KDE: label column with colons and the button box at the bottom. |
| Android | Stacked filled fields. Full-screen form with close and a text Save action in the app bar on compact. The IME action moves Next through fields, then Done submits. |
| iOS | Grouped inset lists (label leading, value trailing) for settings. A modal sheet with Cancel (leading) and Done (trailing, bold) in the navigation bar for create and edit. |
| Web | A real `<form>` with a `<button type="submit">`. Native constraint validation is disabled in favour of this pattern (`novalidate`), and `autocomplete` is set on fields. |

## Accessibility
- Role Form, named by its title. Sections are Groups named by their headings.
- Required, invalid and description relationships come from each Form field. The form adds only the summary and the busy state (Busy while submitting).
- After a failed submit the summary is focused and announced: "2 problems prevent creating the project".
- Submit stays enabled so keyboard and screen reader users can discover what is missing. A disabled submit gives them nothing to act on.
- The action bar is not a landmark. Its buttons are reachable in reading order after the last field.
- Reduced motion: no scroll animation to the summary, and messages appear without fading.

## Content
- Title: the task as a verb and noun: "New project", "Edit build settings".
- Submit label: the outcome, matching the title: "Create project", "Save settings". Not "Submit" or "OK".
- Section headings: nouns: "General", "Build", "Notifications".
- Required legend: "* Required", only when asterisks are used.

## e.ui today
`control.form` lays its fields out in a vertical flex (`space-md` gap) below the Expanded size class, and in a horizontal wrap (`space-lg` by `space-md`) at 840 and over. It sits under a scope where Enter is `submit` and Escape is `cancel`, is a Group named `label`, and draws no buttons. To reach this design:
- Replace the Expanded wrap with a real 2-column grid (24 gutter), with a `span` option per field. Today the wrap lets 160-wide fields pack as many to a line as fit.
- Use `space-5` 20 between fields on pointer hosts and 16 on touch.
- Add section headings, the required legend and the action row, or an action bar that pins while the form scrolls. Today the caller builds its own buttons.
- Add a submitting state: fields read-only, Busy on the form, and a ring in the submit button.
- On a failed submit, focus the `validation_summary` and scroll to it.
- Make the role Form instead of Group, and send Ctrl+Enter (⌘Return) to `submit` from a text area.
