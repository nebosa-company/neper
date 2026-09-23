# EmptyState

An empty state fills a view that has nothing to show, saying why it is empty and what to do next, for first use, filtered searches with no results, and cleared queues.

## Anatomy
1. Art: an icon (`icon-lg` 36, or 24 compact) centred in a 72 (48 compact) `secondary-container` circle, `on-secondary-container`.
2. Title: `headline-small` (`title-medium` compact), `on-surface`, centred.
3. Message: `body-medium`, `on-surface-variant`, centred, at most two lines.
4. Actions (optional): a filled button for the next step, and a text button for an alternative; compact uses a single outlined small button.
5. Region: centred in the empty view, max 360 wide.

## Variants and when to use
| Variant | Art | Actions | Use for |
|---|---|---|---|
| First use | the object's icon | filled "New ..." + text alternative | A collection that has never had items. |
| No results | `search` | outlined "Clear filters" | A search or filter that matches nothing. |
| All done | `check-circle` | none | An inbox, review queue or task list that was emptied. |
| Compact | 48 circle, `title-medium` | one small button | Inside a pane, a card, a list-detail's detail, a sidebar. |

Use a Skeleton while content is loading, a Banner or an inline error when something failed (with Retry), and a Placeholder for an intentionally blank slot in a layout.

## Specs
| Part | Page | Compact |
|---|---|---|
| Padding | `space-10` 40 top and bottom, `space-6` 24 sides | `space-6` 24 vertical, `space-4` 16 sides |
| Max width | 360 | the container's, max 320 |
| Art | 72 circle, `icon-lg` 36, `secondary-container` / `on-secondary-container` | 48, `icon-md` 24 |
| Art to title | `space-4` 16 | `space-2` 8 |
| Title | `headline-small` 24/32 | `title-medium` 16/24 |
| Gap title to message | `space-2` 8 | `space-1` 4 |
| Message | `body-medium`, `on-surface-variant` | same |
| Actions | `space-6` 24 above; filled + text, `space-2` apart | `space-4` 16 above; one outlined `sm` |
| Position | centred in the view, optically raised 10% on tall views | centred |

## States
- Static: empty states have no hover or focus of their own; only their buttons do.
- After a filter change: a no-results state replaces the list with a `duration-short-4` cross-fade.
- Permission-limited: "You don't have access to builds" with a text button "Request access", no filled button.
- Offline or failed: not an empty state. Use a Banner or an inline error with Retry.

## Behaviour
- Appears only after loading completes with zero items; never flashes between skeleton and content.
- The filled button starts the most likely next step; the text button offers a real alternative, not "Learn more" unless documentation is the next step.
- When an action creates the first item, the list replaces the empty state in place and focus moves to the new item.
- No motion beyond the cross-fade; the art does not animate.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Compact in panes; page variant in main views; buttons at density -1 (32). |
| macOS | Compact styling preferred (macOS empty views are quiet); the title may be `title-medium` even on pages. |
| Linux | GNOME Adwaita status page: the page variant, art may be larger (72 icon without circle is also acceptable). |
| Android | Page variant; the FAB may be the next step instead of a filled button (then show only the message). |
| iOS | ContentUnavailableView conventions: title, message and one action; search uses the system no-results form. |
| Web | Page variant; the title is a heading at the view's level. |

## Accessibility
- The region is a group (or status, when it appears after a filter change) with the title as its name and the message as its description.
- The art is decorative and hidden from the tree (do not name it with the title again).
- After a search change, announce the title politely ("No builds match arm64 nightly").
- Title and message meet 4.5:1; buttons follow Button.
- Reduced motion: the cross-fade stays (it is not movement).

## Content
Title: say what is empty, plainly: "No projects yet", "No builds match "arm64 nightly"", "You're all caught up". Message: one sentence on why or what to do. Buttons: verbs naming the outcome ("New project", "Clear filters"). No blame, no jokes, no exclamation marks.

## e.ui today
`control.empty_state` centres an optional untinted texture icon at 64, a Title-role title, a muted Body message and an optional default Filled button, with padding `space-lg`; the icon is an Image named by the title, so screen readers read the title twice. To reach this design:
- Draw the art as a Neper icon in a `secondary-container` circle (72 or 48) instead of an untinted texture, and hide it from the tree.
- Set the title in `headline-small` (compact `title-medium`) and cap the width at 360.
- Add a second (text) action and the compact variant with one outlined small button.
- Add the no-results and all-done variants and announce the title after filter changes.
