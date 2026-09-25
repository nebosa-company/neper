# FieldMessage

A field message is the line of text under a control. It holds help, a pending check, a warning, an error or a confirmation, with an icon for every state that isn't plain help.

## Anatomy
1. Status icon: 16px, top-aligned with the first line. Absent for help.
2. Text: `body-small`, wrapping. It is never truncated.
3. Optional counter: `body-small`, tabular figures, pushed to the end, at least 16 from the text.

## Variants and when to use
| Variant | Icon | Text colour | Use for |
|---|---|---|---|
| Help | none | `on-surface-variant` | What to enter or why: "Shown in the sidebar and in URLs". |
| Info | `info` icon in `on-surface-variant` | `on-surface-variant` | Why a control is disabled or set elsewhere: "Set by your organization". |
| Pending | 16px indeterminate progress ring, `primary` | `on-surface-variant` | An asynchronous check that takes longer than 300 ms: "Checking availability". |
| Error | `error` icon in `error` | `error` | A value that blocks submit. Replaces the help text until fixed. |
| Warning | `warning` icon in `warning` | `on-surface-variant` | A value that is allowed but risky: "Larger than this machine's free memory". Does not block submit. |
| Success | `check-circle` in `success` | `on-surface-variant` | Only after an asynchronous check that the reader waited for: "Available". Never for ordinary valid input. |

For an error that concerns the whole form, or several fields at once, use Validation summary or a Banner. For a transient result of an action use a Snackbar.

## Specs
| Part | Value |
|---|---|
| Type | `body-small`: 12/16, letter-spacing 0.4 |
| Icon | 16, stroke 1.75, `space-1` 4 before the text |
| Position | `space-1` 4 below the control. Inset 16 under a boxed field (matching its text), 0 under an outside-labelled or unboxed control. |
| Counter | end-aligned, `space-4` 16 minimum from the text, tabular figures |
| Max length | two lines. A longer explanation belongs in the Field label's help popover. |
| Reserved space | none by default. When fields sit in a grid that must not jump, reserve one line (16) under each field. |

| Part | Colour role |
|---|---|
| Help and warning text | `on-surface-variant` |
| Error text and icon | `error` |
| Warning icon | `warning` |
| Success icon | `success` |
| Pending ring | `primary`, no track |
| Under a disabled control | `on-surface-variant`, not dimmed |

## States
The variant is the state. A message switches variant in place and keeps its position. An error replaces the help text and the help comes back once the error is fixed. Under a disabled control the message keeps full-strength `on-surface-variant`, because it usually says why the control is disabled and must stay readable.

## Behaviour
- Timing follows the control's validation: first on blur or submit, then live while the reader corrects it. A message never appears while the reader is still typing a first value.
- Pending shows only if the check has run 300 ms, which prevents a flash for fast checks. The result replaces it directly.
- Changes swap in place with a `duration-short-2` cross-fade (`ease-standard`). The height changes with no animation, which avoids layout wobble. With reduced motion the cross-fade stays (it is not movement).
- The counter updates on every change. It turns `error` only past the limit and then the text says by how much.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | `body-small` under the control. Fluent InfoBar-style icons. Error text in `error`. |
| macOS | Same placement. macOS forms often place help under a group rather than each field: allow one message per group in a Form. |
| Linux | Same. GNOME's Adwaita entry rows show errors as a row style plus a message below: keep the icon and the text. |
| Android | Under filled fields, inset 16. Matches the Material supporting text. |
| iOS | Under a grouped-list section as a footer for help, and inline under the row for errors. |
| Web | A `<div>` referenced by `aria-describedby`, plus `aria-errormessage` for the error variant. |

## Accessibility
- Help and warning messages are the control's description. An error message is the control's error message, and the control carries the Invalid state.
- Announcements: an error that appears after submit is announced through the Validation summary, not by each message. An error that appears live is announced once, politely, after typing pauses. Pending and success are polite. Help is never live, so changing help text is not announced.
- The icon is decorative (hidden) and the words carry the meaning.
- Contrast: `on-surface-variant` and `error` text are 4.5:1 on `surface` in every theme.
- At 200% text size the message wraps and the counter drops below it.

## Content
- Help: one short sentence, no trailing period for a fragment, a period for a full sentence. Say what, not how the widget works.
- Error: say how to fix it: "Enter a port from 1 to 65535". Not "Invalid", "Error" or "Required field". For a required field say "Enter a project name".
- Warning: say the consequence: "Larger than this machine's free memory".
- Success: one word or two: "Available", "Connected".
- Never blame the reader, and never use exclamation marks.

## e.ui today
`control.field_message` writes a `Message`'s text as a Caption: `text-muted` for Valid, `text` for Warning, `error` for Invalid. It has no icon and no padding. It is a Status controlling the field, polite, and assertive when Invalid. To reach this design:
- Set it in `body-small` with a 16px status icon for error, warning, success and pending, and inset it 16 under boxed fields.
- Colour a warning with its icon, not by switching the text from `text-muted` to `text`. Today the comment and the code disagree about a warning.
- Add a `.Pending` validity with the ring and the 300 ms delay, and a `.Success` validity.
- Add an optional counter slot.
- Stop making help a live region, so changing help is not announced. Make errors polite and live only while the reader is correcting, and leave post-submit announcements to `validation_summary`.
- Relate it as description (help, warning) or error message (invalid) instead of only controlling the field.
