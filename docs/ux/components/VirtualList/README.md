# VirtualList

A virtual list shows a long or unbounded collection as rows in a scrolling viewport, building only the rows in view, so ten rows and ten million cost the same.

## Anatomy
1. Viewport: the scrolling region, clipped, on `surface`.
2. Rows: Row components of one fixed height per list (or a small set of known heights by kind).
3. Sticky section header (optional): a subheader that pins to the viewport's top while its section scrolls; `surface-container` once pinned.
4. Scroll thumb: an overlay thumb on the trailing edge; on touch hosts it becomes a fast-scroll handle with a section bubble.
5. Placeholder rows: skeletons at the real row height for rows whose data has not arrived.
6. End cap: a loading row while the next page loads, then the total at the true end.

## Variants and when to use
| Variant | Use for |
|---|---|
| Fixed height | Logs, results, contacts: every row the same height. The fastest; exact scroll position. |
| Sectioned | Rows grouped by date or letter, with sticky headers and a fast-scroll bubble. |
| Paged source | Server-backed results loaded in pages as the viewport nears the end. |
| Reverse (anchored to the end) | Chat and log tails: new rows appear at the bottom and the view stays pinned to the end until the person scrolls up. |

Use List for fewer than about 200 rows the app can build at once. Use Virtual grid for tiles. Use Table for records in columns.

## Specs
| Part | Value |
|---|---|
| Row height | Row's variant height by density (one line 56 / 48 / 32); fixed per list |
| Build window | the visible rows plus one screen above and one below (overscan), recycled by key |
| Sticky header | Subheader specs; pinned fill `surface-container`, no shadow |
| Scroll thumb (pointer) | 4 wide at rest, 8 on hover or drag, `radius-full`, `on-surface-variant` at 50% (100% while dragged), 2 from the edge; length = viewport² / content, 32 minimum |
| Fast-scroll handle (touch) | 8 by 48, `on-surface-variant`, a 48 wide invisible target; shown while scrolling and for 1.5 s after |
| Section bubble | 56 circle with a square corner toward the thumb, `primary-container` / `on-primary-container`, `headline-small`, `elevation-2`, `space-6` 24 from the edge |
| Placeholder row | the row's height; `nu-skeleton` bars (`surface-container-highest`, `radius-xs`) at 12 and 10 tall, 30 to 70% wide |
| End cap | `control-xl` 56, 24 progress ring and `body-medium` `on-surface-variant` text, centred |

## States
- Idle: the thumb fades out after 1.5 s without scrolling (`duration-medium-1`, `ease-standard`) on hosts with overlay scrollbars; hosts with classic scrollbars keep a visible track.
- Scrolling: thumb shown; rows recycle without flicker; placeholders show for any row whose data is late.
- Dragging the thumb (fast scroll): the thumb is at full opacity and 8 wide; the bubble shows the current section.
- Loading next page: the end cap shows a ring and "Loading more contacts".
- End: the end cap shows the count ("482 contacts") or nothing if the count is already in a header.
- Error loading a page: the end cap becomes "Couldn't load more" with a Retry text button.
- Empty: as List.

## Behaviour
- Scroll by wheel, trackpad, drag (touch), thumb, or keyboard; momentum and edge behaviour are the host's (rubber-band on Apple hosts, stretch overscroll on Android, a hard stop on Windows and Linux).
- Keyboard: Up/Down move focus one row and scroll it into view; Page Up/Down move by a viewport less one row; Home/End go to the first and last row, loading them if needed. Typeahead jumps to the next headline match in loaded rows and asks the source otherwise.
- Focus and selection are by key, not index: a row keeps its focus and selection as rows are inserted above it, and the scroll position stays anchored to the focused (or first visible) row.
- Paging: the next page is requested when the viewport is within one screen of the loaded end.
- Reverse lists stay pinned to the end while the person is at the end; if they have scrolled up, new rows show a "12 new messages" chip that scrolls to the end.
- The thumb: pressing the track pages; dragging the thumb scrolls proportionally; on touch, the fast-scroll handle appears only when the content is more than 4 screens long.
- Motion: sticky headers push each other off rather than overlap. Reduced motion keeps scroll animation instant on programmatic jumps (Home, End, "Jump to latest").

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Density -1; WinUI-style thin overlay scrollbar that expands on hover with arrow buttons; the pane scrolls without momentum on a mouse wheel. |
| macOS | Density -1; overlay scrollers (or legacy scrollbars when the system setting says "Always"); rubber-band at the ends; ⌥-click on the track jumps to that point. |
| Linux | Density -1; GTK overlay scrollbars on GNOME with the hover-to-widen indicator; KDE shows classic scrollbars. |
| Android | Touch metrics; fast-scroll handle and section bubble; stretch overscroll; the top app bar lifts to `surface-container` when content scrolls under it. |
| iOS | Touch metrics; the section index (A to Z) along the trailing edge replaces the bubble in sectioned lists; tapping the status bar scrolls to the top. |
| Web | Density -1 with a fine pointer; native scrolling with `overflow-anchor` and `content-visibility`; `aria-setsize` and `aria-posinset` on each built row. |

## Accessibility
- Role list (or listbox when selectable) with the full count as set size, not the built count; each built row has its true position.
- Screen readers move row by row; moving past the built window asks for more rows, so a reader never reaches a false end.
- Sticky headers are headings that group their rows; the fast-scroll bubble is decorative (the thumb is reported as a scroll bar with a value "Section M").
- Placeholder rows are hidden from the tree; the list is Busy while a page loads and announces "482 contacts loaded" politely when done.
- New rows in a reverse list announce politely ("New message from Maya Kovač") only when the list is focused.
- Contrast and targets follow Row; the fast-scroll handle has a 48 target.
- Reduced motion: no momentum emulation beyond the host's; jumps are instant.

## Content
- End cap: a count with its noun: "482 contacts", "12,480 lines". Loading text names the thing: "Loading more contacts".
- Section headers: a date ("Today", "12 September") or a letter; never both in one list.
- New-content chip: a count and noun: "12 new messages".

## e.ui today
`collection.virtual_list` builds a `Source`'s rows of one fixed `extent` inside a lazy viewport, from one row above to two below the visible range, with a 4px square thumb in `border` that is painted only. To reach this design:
- Widen overscan to a screen each way, recycle by key, and keep the scroll anchored to the focused row across inserts.
- Make the thumb a real control: round it, widen on hover, drag it, page on the track, and add the touch fast-scroll handle and section bubble.
- Add sticky section headers, placeholder rows for late data, paging with an end cap, and reverse (end-anchored) mode.
- Put role list on the viewport (today the role group sits on the node above it and the rows are list items without a list) and report the full count.
- Drop the separator under the last row (today `separators` reaches every row, the last included) and use `outline-variant`.
- Own keyboard movement and typeahead as in List.
