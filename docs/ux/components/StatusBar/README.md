# StatusBar

A status bar runs along a desktop window's bottom edge and shows passive, glanceable state about the window's content (the last result, background progress, the cursor position, the file's encoding), with each item optionally opening the place where it can be changed.

## Anatomy
1. Container: full-bleed, square, 24 tall, `surface-container`.
2. Start group: the message item (the latest result or current activity), then counts (errors, warnings) and background progress.
3. Spacer.
4. End group: context items (cursor position, indentation, encoding, line endings, language), then notifications.
5. Item: an optional 16 icon and a short `body-small` text, 8 padding each side; pressable items have a state layer.
6. Progress meter (optional): a 48 x 4 linear bar with a percentage in words.

## Variants and when to use
| Variant | Container | Use for |
|---|---|---|
| Default | `surface-container`, `on-surface-variant` | Every document or tool window on pointer hosts. |
| Mode | `primary-container`, `on-primary-container` | A session that changes how the window behaves (debugging, presenting, offline editing). The mode is always named in the first item. |
| Touch hosts | none | No status bar. Transient results go in a Snackbar, persistent state moves into the page (a Banner, or the app bar's subtitle). |

Something the user must act on is a Banner. A result that needs a single optional action is a Snackbar. A panel of problems is a DockPanel opened from the status item.

## Specs
| Part | Value |
|---|---|
| Height | `control-xs` 24 (pointer); 28 on Windows with text scaling over 125% (grows with the text) |
| Padding | `space-1` 4 at the ends; items `space-2` 8 each side |
| Item gap | 0 (item padding spaces them); groups split by the spacer |
| Type | `body-small` 12/16 |
| Icons | 16, `on-surface-variant`; error items `error`, warning items `warning` (always with a count or a word) |
| Container | `surface-container`; mode `primary-container` |
| Text | `on-surface-variant`; mode `on-primary-container` |
| Hover | state layer at `state-hover` over the item's full height |
| Focus | ring inset 3px (the item is edge-to-edge in the bar) |
| Meter | 48 x 4, `radius-full`, `primary` on `secondary-container` |
| Divider above | none: the tonal step from `surface` separates it |

## States
- Idle: message shows the last result ("Build succeeded in 4.2 s") until replaced; it never clears itself to empty.
- Busy: an item shows the activity and progress ("Indexing 64%"); indeterminate work shows the activity without a number.
- Problems: error and warning counts show icon plus number; a failed result shows icon plus words ("Build failed: 3 errors").
- Mode: the whole bar changes to `primary-container` over `duration-short-4` with `ease-standard`.
- Item states: hover, focus (inset ring), pressed; non-pressable items have none.

## Behaviour
- Pressable items open what they describe: counts open the problems panel, "Ln 42, Col 7" opens Go to line, "Spaces: 4" opens indentation settings, "UTF-8" opens Reopen with encoding.
- Items keep their place; a new item appears in its group, never pushing the end group. When the window narrows, end items drop from the least useful (line endings, then encoding) and the message truncates with an ellipsis; its full text is its tooltip.
- The bar is one Tab stop reached by F6 (the pane cycle); arrow keys move between pressable items, Home and End jump to the ends, Escape returns focus to the editor.
- A message persists; it is replaced, not timed out.
- No motion except the mode's colour change; text changes in place with no animation.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | 24 tall (grows with text scaling); items pressable; F6 cycles into it. Classic apps may show a size grip at the end: omit it, the window edge resizes. |
| macOS | Rare in native apps: prefer a bottom bar of 22 inside the window's content with the same items, or the window's subtitle for one fact. No mode colour; use the item's words. |
| Linux | 24 tall; GNOME apps seldom use one (follow the app's domain: editors and IDEs keep it); KDE apps show it by default and let the user hide it (View menu). |
| Android | None. Use a Snackbar for results and a Banner for a mode. |
| iOS | None. Use the toolbar's status text (the centre of a bottom toolbar) for one fact, a Snackbar-like toast for results. |
| Web | Shown at `window-expanded` and up for tool apps; hidden below, with its content moved to snackbars. A `<footer>` with `role="status"` on the message item only. |

## Accessibility
- The bar is a Group named "Status bar"; the message item is a Status with polite live updates, so only it is announced; counts announce only when they change from zero or back.
- Every item has a name in words: "0 errors, 2 warnings", "Line 42, column 7", "Notifications" (for the bell).
- Pressable items are Buttons; their tooltip says what they open ("Go to line").
- Contrast: `on-surface-variant` 12 px text on `surface-container` is 4.5:1 or better; mode colours likewise.
- Targets: 24 tall items with a 32 minimum width meet the pointer minimum horizontally; offer every action another way (menu or command palette), since the bar's height is below `target-pointer`.
- Reduced motion: no change needed.

## Content
- Results in past tense with a number: "Build succeeded in 4.2 s", "Saved", "3 files changed".
- Activities in present tense: "Indexing 64%", "Syncing 12 of 40 files". No trailing ellipsis or period.
- Context items terse and literal: "Ln 42, Col 7", "UTF-8", "Spaces: 4".
- A mode names itself: "Debugging build-4128", not a colour.

## e.ui today
`navigation.status_bar` spreads text-only `sections` across `width` as Captions (11/14) on `surface-variant` with `space-xs` padding and marks the whole bar a polite live Status named by the first section. To reach this design:
- Turn sections into items with an optional icon, an optional action (`widget.Submit`) and a tooltip; make pressable items Buttons with state layers and the inset focus ring.
- Fix the height at 24 and use `body-small` 12/16 on `surface-container`; lay out start and end groups with a spacer instead of space-between (which spreads three sections across the whole bar).
- Make only the message item live, so a cursor move does not announce the whole bar.
- Add the progress meter item, error and warning counts with icons, and the mode variant.
- Add narrowing rules (drop end items by priority, truncate the message with its tooltip).
