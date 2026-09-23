# ValidationSummary

A validation summary lists every problem that stopped a submit, at the top of the form. Each entry is a link that moves focus to its field.

## Anatomy
1. Container: `error-container`, `radius-md`, 16 padding. It is the full width of the form.
2. Status icon: 24px `error` glyph in `on-error-container`, top-aligned.
3. Title: `title-small` with the count and the blocked outcome: "2 problems prevent creating the project".
4. Entries: a bulleted list in `body-medium`. Each entry is a link written as "<field label>: <how to fix it>".

## Variants and when to use
| Variant | Container | Use for |
|---|---|---|
| Error | `error-container` / `on-error-container` | Problems that block the submit. The default. |
| Warning | `warning-container` / `on-warning-container` | Problems that don't block. The submit still goes ahead, or the form offers "Save anyway". |

Show a summary when a submit fails and the form has more than three fields or scrolls. For a short form, focus the first invalid field instead. Keep each field's own Field message in both cases: the summary adds to it and does not replace it. For a failure that is not about a field (network, permissions, conflict) use an inline error Banner above the actions. For a problem found while typing, rely on the Field message alone.

## Specs
| Part | Value |
|---|---|
| Container | `radius-md` 12, padding `space-4` 16, icon-to-text gap `space-3` 12 |
| Position | first thing below the form title, above the first section, `space-4` 16 below the title |
| Icon | `icon-md` 24, `on-error-container` (warning: `on-warning-container`) |
| Title | `title-small` 14/20 weight 600 |
| Entries | `body-medium` 14/20, bullets, `space-5` 20 indent, `space-1` 4 between entries |
| Links | inherit the text colour, underlined (2px offset), focus ring 3px 1px outside |
| Max entries | all of them. Beyond 8, show the first 8 and "and 3 more" as a link to the next unlisted field. |

| Part | Colour role |
|---|---|
| Container | `error-container` (warning: `warning-container`) |
| Icon, title, entries, links | `on-error-container` (warning: `on-warning-container`) |
| Focus ring | `focus-ring` |

## States
- Hidden: absent from the layout. It does not reserve space before the first failed submit.
- Shown and focused: appears after a failed submit, takes focus, and shows the focus ring on the container.
- Updating: as the reader fixes fields the entries stay put until the next submit, so the list never shifts under them. Each fixed entry is struck through and gets a check. On the next submit, the summary rebuilds or disappears.
- Link hover: `state-hover` layer behind the link text. Link focus: the ring.

## Behaviour
- On a failed submit: the summary appears (no animation beyond a `duration-short-4` fade with `ease-emphasized-decelerate`), the view scrolls it into view, and it takes focus.
- Activating an entry (click, tap, Enter) moves focus into the field and scrolls the field to the upper third of the view. For a group it focuses the first option. For a text field it selects the text.
- Tab from the summary moves through its links, then into the form in reading order.
- Order: entries follow the fields' reading order, never severity or time.
- Motion with reduced motion: no fade and no smooth scroll.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | The same block at the top of the form or dialog content. Links focus fields and the view scrolls. |
| macOS | Preference windows apply instantly and never need a summary. In sheets and dialogs, show the summary for more than two errors, and otherwise focus the field and show its message. |
| Linux | The same. On GNOME dialogs, which are short, prefer focusing the field. The summary fits Adwaita's preferences pages when they submit. |
| Android | At the top of the scrolling form, below the app bar. It is focused and announced. |
| iOS | As the first section of the grouped list, with the entries as tappable rows that scroll to the field. |
| Web | `role="alert"` is not used for the focused summary: give it `tabindex="-1"`, focus it, and let the focus announce it. Links are same-page `<a href="#field-id">`, and the focus handler places the caret in the field. |

## Accessibility
- The summary is a Group named by its title. Focusing it announces the title and the count ("2 problems prevent creating the project"). It is not also an assertive live region, which would announce it twice.
- Each link's name is the whole entry. Activating it moves focus to the field, where the field's own error message is read as its error.
- The warning variant is a Status (polite) and does not take focus unless the reader submitted.
- Contrast: `on-error-container` on `error-container` is 4.5:1 or better in all four themes. The underline keeps links recognisable without colour.
- Target: each link has at least a 24 tall hit area with a pointer and 48 on touch (the row's padding).

## Content
- Title: count plus the blocked outcome: "2 problems prevent creating the project", "1 problem prevents saving". Not "Errors" or "Please fix the following".
- Entry: "<Field label>: <how to fix it>", reusing the field's error text, lowercased after the colon: "Project name: use lowercase letters, digits and hyphens".
- Warning title: "2 settings need attention".

## e.ui today
`control.validation_summary` builds a `link` in Body `primary` for each Invalid message with text, stacked (`space-xs`) in a `surface` sheet with an `error` border, `radius-sm` and `space-sm` padding. It is an assertive Alert, hidden when empty. To reach this design:
- Fill it with `error-container` and set everything in `on-error-container`. Today the links are `primary`, so only the border says error.
- Add the status icon and a counted title, which the caller passes or the summary derives from `messages` plus an `outcome` string.
- Write each entry as "<label>: <message>", which needs the field labels (add `labels: []const str`), and underline the links.
- Focus the summary when it appears, and make it a named Group instead of an assertive Alert.
- Add the Warning variant for `.Warning` messages.
- Keep entries stable while the reader fixes fields (strike through and check), and rebuild on the next submit.
- Key links by position among the invalid messages or by field key, not `key + 1 + index` over every message.
