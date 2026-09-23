# List

A list is a vertical run of rows on one surface, optionally in sections and optionally selectable, for a short collection the app can build in full.

## Anatomy
1. Container: `surface` (full bleed) or `surface-container-low` with `radius-md` (grouped), `space-2` 8 padding top and bottom when full bleed.
2. Rows: Row components, all of one line count within a section where possible.
3. Subheader (optional): `title-small` in `primary`, `space-4` 16 sides, 16 above and 8 below, sticky while its section scrolls.
4. Dividers (optional): 1px `outline-variant`, full width between sections, inset 72 (to the text) or 16 between rows.
5. Selection bar (multi-select only): replaces the header while rows are selected: a Clear button, the count in `title-medium`, and the bulk actions.
6. Empty and loading states: in place of the rows, never beside them.

## Variants and when to use
| Variant | Container | Use for |
|---|---|---|
| Full bleed | `surface`, square | The main content of a pane: files, activity, people. |
| Grouped | `surface-container-low`, `radius-md`, `space-4` from the page edge, a `label-medium` group title above and an optional footnote below | Settings pages and forms made of rows; iOS and GNOME settings. |
| Navigation | Rows with trailing chevrons, no selection | A menu of destinations. |
| Single select | Selected row filled and checked | Pick one; the choice applies at once. For a pick-one field use Select or Radio instead. |
| Multi select | Leading checkboxes, a selection bar | Bulk actions on items (delete, share, move). |

Use Virtual list when the collection is long (more than about 200 rows) or unbounded. Use Reorderable list when the person sets the order. Use List box for a plain pick-one list of strings inside a form. Use Table when items have more than two attributes to compare.

## Specs
| Part | Value |
|---|---|
| Container padding | `space-2` 8 top and bottom (full bleed); 0 when grouped |
| Grouped container | `surface-container-low`, `radius-md` 12, `space-4` 16 from the page edge; rows 48 on touch, 40 on pointer hosts |
| Group title | `label-medium`, `on-surface-variant`, `space-4` 16 inset, `space-2` 8 above the container |
| Group footnote | `body-small`, `on-surface-variant`, `space-4` inset, `space-2` below |
| Subheader | `title-small`, `primary`, padding 16 / 16 / 8; sticky with a `surface-container` fill once stuck |
| Divider | `divider` 1px `outline-variant`; inset 72 after avatar or icon rows, 16 in grouped lists, 0 between sections |
| Selection bar | `control-lg` 48 (pointer) / `app-bar` 64 (touch), `surface-container`, count in `title-medium` |
| Rows | Row specs; one line 56 / 48 / 32 by density |
| Empty state | `icon-lg` 36 in `on-surface-variant`, `title-medium` headline, `body-medium` text, a tonal button; `space-6` 24 padding |
| Loading | 3 to 8 skeleton rows (`surface-container-highest`, `radius-xs` bars, the avatar circle) matching the real row's height |

## States
- Rows carry their own hover, focus, pressed, selected and disabled looks (see Row). The list adds none.
- Focus within: the list has one tab stop; the focused row shows the ring. Entering the list focuses the selected row, or the first.
- Selection mode (multi select): the selection bar is shown and every row's leading slot becomes a checkbox; leaving the mode (Clear, Escape, last row unchecked) restores the header.
- Empty: the empty state stands centred in the list's area with one action to fill it.
- Loading: skeleton rows while the first page loads; if loading takes over 10 seconds, add "Still loading" text under them. Refreshing a list that has rows keeps the rows and shows Pull to refresh or a linear progress under the header.
- Error: a Banner in place of the rows, with Retry.

## Behaviour
- Keyboard: Up and Down move focus between rows; Home and End jump to the first and last; Page Up and Page Down move by a screenful. Typeahead: typing letters moves to the next row whose headline starts with them (a 500ms buffer).
- Single select: arrows move focus and selection together; Enter opens.
- Multi select: Space toggles the focused row; Shift+Up/Down extends; Ctrl+A (⌘A) selects all; Shift+click selects a range; Ctrl-click (⌘-click) toggles one. On touch, a long press enters selection mode and selects the row; then a tap toggles.
- Escape clears the selection first, then leaves selection mode.
- The list scrolls in its own pane; subheaders stick to its top. Keeping focus visible scrolls the focused row fully into view with `space-2` to spare.
- Rows enter (a new item) with a 100% height grow plus fade in `duration-medium-1`, `ease-emphasized-decelerate`; removed rows collapse in `duration-short-4`, `ease-emphasized-accelerate`. Reduced motion cross-fades.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Density -1; single select follows focus as in WinUI ListView; selected rows get Fluent's leading 3px pill; Ctrl+A, Shift+click and Ctrl+click select. |
| macOS | Density -1; sidebars (source lists) use `surface-container-low` inset selection with `radius-sm`; ⌘A, ⌘-click, Shift-click; Space opens Quick Look in file lists; no ripple. |
| Linux | Density -1; grouped lists match libadwaita boxed lists (`radius-md`, separators between rows); KDE uses full-bleed lists. |
| Android | Touch metrics; long press starts selection mode; the selection bar replaces the top app bar. |
| iOS | Touch metrics; grouped lists use the inset grouped style; Edit mode shows leading selection circles; separators inset to the text; swipe actions on rows. |
| Web | Density -1 with a fine pointer, touch with a coarse one; `role="list"` or `role="listbox"` with `aria-activedescendant`; links for navigation rows. |

## Accessibility
- Role list for a read-only or navigation list, listbox (with `aria-multiselectable` for multi select) when rows are selectable options. Name: the pane's title or the subheader ("Activity").
- Each row reports position and set size; subheaders are headings level 3 and group their rows.
- Selection changes are announced ("2 selected"); entering selection mode announces "Selection mode".
- Empty and error states are announced once as a status when they replace rows.
- Loading lists set Busy on the list and announce "Loading" once; skeleton rows are hidden from the tree.
- Keyboard as in Behaviour; nothing is reachable only by long press or swipe.
- Contrast and target sizes follow Row. Grouped containers need no outline: `surface-container-low` on `surface` is decorative; row content keeps 4.5:1.
- Reduced motion: insert and remove cross-fade.

## Content
- Subheaders: a time or a category, one or two words: "Today", "Earlier", "Pinned".
- Empty state: say what goes here and how to add it: "No recent projects" / "Projects you open appear here" / "New project". No blame, no exclamation.
- Selection bar: a count, "2 selected"; actions as icons with names.
- Footnotes in grouped lists: one sentence, sentence case, no period when it is a fragment.

## e.ui today
`collection.list` stacks the caller's prebuilt items, each in `collection.row`, with `border` hairlines between them and `selection` behind selected ones; it takes no input. To reach this design:
- Own the keyboard: one tab stop, Up/Down/Home/End/Page keys, typeahead, and selection with Space, Shift and Ctrl/⌘. Today selection changes come only from the items.
- Add selection modes (none, single, multi) with the checkbox leading slot and the selection bar.
- Add subheaders (sticky), inset dividers in `outline-variant`, and the grouped container.
- Add empty, loading and error states in place of the rows.
- Report role listbox when selectable, and announce selection counts; today the role is list with no selection model.
- Animate inserts and removals as specified.
