# Banner

A banner states a condition that affects a whole view and stays until it is resolved or dismissed, with one or two actions to deal with it: offline, a licence expiring, a failed connection.

## Anatomy
1. Container: `surface-container-low`, `radius-md` inside content, square (`radius-none`) when full-bleed under a bar.
2. Icon well: a 40 circle in the severity's container pair holding its icon (`info`, `check-circle`, `warning`, `error`).
3. Title (optional): `title-small`, `on-surface`.
4. Message: `body-medium`, `on-surface`, one to three lines.
5. Actions: up to two text buttons at the end, below the message (standard) or on the same line (inline).
6. Dismiss (optional): a `close` icon button when the banner can be closed without acting.

## Variants and when to use
| Variant | Layout | Use for |
|---|---|---|
| Standard | message block, actions in a row below, end-aligned | A condition that needs a sentence and a choice. |
| Inline | one line: well, message, action or dismiss | Short conditions; forms and panes. |
| Full-bleed | square, under the app bar, full width | Window-wide conditions (offline, read-only mode). |

| Severity | Well | Icon | Live |
|---|---|---|---|
| Info | `primary-container` / `on-primary-container` | `info` | polite |
| Success | `success-container` / `on-success-container` | `check-circle` | polite |
| Warning | `warning-container` / `on-warning-container` | `warning` | polite |
| Error | `error-container` / `on-error-container` | `error` | assertive |

Use a Snackbar for a passing confirmation, a Dialog when work cannot continue until a decision is made, a Field message for a single field's problem, and the Validation summary for a form's errors.

## Specs
| Part | Standard | Inline |
|---|---|---|
| Container | `surface-container-low`, `radius-md` (full-bleed `radius-none`) | same |
| Padding | `space-4` 16 top and sides, `space-2` 8 bottom (under the actions) | `space-3` 12 vertical, `space-4` 16 sides |
| Well | 40 circle, `icon-md` 24; gap `space-4` 16 to the text | same |
| Title | `title-small`, `on-surface` | none |
| Message | `body-medium`, `on-surface`; 10 top offset to centre on the well's first line | `body-medium`, centred on the well |
| Actions | text buttons 40, `space-2` apart, end-aligned, full row below | at the end of the line |
| Dismiss | 40 icon button, `on-surface-variant` | same |
| Width | the container's; message max 720 per line | same |
| Stack | one banner per view; the most severe wins | same |

## States
- Actions follow Button (hover, focus ring, pressed, disabled).
- The banner itself is not interactive and has no hover.
- Resolving: when the condition clears, the banner collapses; optionally a Success inline banner replaces it for 4 seconds ("Back online").
- Several conditions: show the most severe; a "2 more" text button opens the rest in a sheet or the notification list.

## Behaviour
- Appears at the top of the affected region (under the app bar or at the top of a pane), pushing content down; never floats over content.
- Enters by expanding height over `duration-medium-2` with `ease-emphasized-decelerate`; leaves by collapsing over `duration-short-4` with `ease-emphasized-accelerate`. Content below moves with it.
- Does not take focus. Tab reaches its actions in document order (it is before the content).
- A dismissed banner stays dismissed for the session (or until the condition changes); error banners without a resolution cannot be dismissed.
- Pressing an action that resolves the condition removes the banner and gives the result in place or a snackbar.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | WinUI InfoBar placement: top of the page under the title/command bar; inline layout at density -1 (buttons 32). |
| macOS | Inline layout under the toolbar, full width, square; buttons 32; prefer one action. |
| Linux | Adwaita banner style: full-bleed under the header bar with one action at the end. |
| Android | Standard layout on compact; full-bleed under the top app bar; actions as text buttons. |
| iOS | Full-bleed under the navigation bar, inline layout; one action; no dismiss for errors. |
| Web | A `role="status"` (or `role="alert"` for errors) region placed before the main content; not a fixed overlay. |

## Accessibility
- Role status (polite) for info, success and warning; alert (assertive) for error. Name = title, or the message when there is no title.
- The severity is in the icon and the words: the title or message must say "failed", "expires", "offline"; the well colour is only a reinforcement. The icon is hidden from the tree; add the severity word to the name when the text does not include it ("Warning: ...").
- Message and actions meet 4.5:1 on `surface-container-low` in all themes (action buttons are `primary` on that surface, never on a coloured ground).
- The banner's announcement happens once on appearance; updates in place do not re-announce unless the severity rises.
- Reduced motion: the banner appears and goes without height animation (content jumps once).

## Content
Say what is happening and what to do: "Your licence expires in 5 days. Renew it to keep private builds running after 28 September." Titles are short statements, no "Warning:" prefix (the icon does that). Actions are verbs: "Renew licence", "Retry", "Try it now". Avoid "Dismiss" as a text action; use the close button.

## e.ui today
`control.banner` fills the whole banner with the severity colour (Info `surface-variant`, Success `primary`, Warning `secondary`, Error `error`) with square corners, and `info_bar` adds a close; action and close buttons are the Plain variant in `primary`, invisible on Success (primary on primary) and weak on Error. To reach this design:
- Keep the banner on `surface-container-low` for every severity and carry severity in a 40 icon well in the status container pairs, with the matching icon.
- Use `warning` and `success` roles instead of `secondary` and `primary` for Warning and Success.
- Draw actions as text buttons on the neutral surface (fixes the contrast defect) and the close as a `close` icon button named "Dismiss".
- Add the title, the standard and inline layouts, `radius-md` inside content and full-bleed square under bars.
- Animate enter and leave by height, and set Status versus Alert as listed.
