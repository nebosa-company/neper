# Outline

An outline is a tree of a document's headings, with guide lines down each level and the section in view marked, for finding your place in and jumping around a long document.

## Anatomy
1. Header: "Outline" in `title-small`, with Collapse all and an optional filter field.
2. Items: Tree items (inset `radius-sm` rows, twisty, label), one per heading.
3. Number (optional): the heading's section number in `body-medium` `on-surface-variant`, tabular, 28 minimum width.
4. Guides: 1px `outline-variant` lines, one per ancestor level, through the centre of that level's twisty, continuous from row to row.
5. Current marker: the heading whose section is in view: a 3px `primary` bar at the pane's leading edge, label and number in `primary` weight 600.
6. Filter results (optional): matches with their ancestors; ancestors in `on-surface-variant`, the matched text bold; a count at the end.

## Variants and when to use
| Variant | Use for |
|---|---|
| Sidebar outline | Long documents, specs and code files beside the content on medium and wider windows. |
| Outline sheet | Compact touch screens: the same outline in a bottom sheet from a toolbar button. |
| Symbol outline | Code: headings are classes and functions with their icons; numbers off. |

Use Tree for hierarchies that are not a document's structure (files, settings). Use Tabs or a Navigation drawer for a handful of top-level pages. Use Breadcrumbs to show only the path to the current section.

## Specs
| Part | Touch | Pointer (density -2) |
|---|---|---|
| Row | 48, inset `space-2`, `radius-sm` | 32 |
| Indent step | `space-6` 24 | `space-5` 20 |
| Guides | 1px `outline-variant`, x = start padding 4 + 12 + level × step | same |
| Number | `body-medium` `on-surface-variant`, tabular, min 28 | same |
| Label | `body-large` | `body-medium` |
| Current | 3px `primary` bar, `space-2` inset top and bottom, square on the pane side; label `primary` 600 | same |
| Header | `control-lg` 48 | `control-md` 40, `title-small`, `space-4` start |
| Filter field | 32 outlined field, `space-3` 12 padding | same |
| Filter count | `body-small` `on-surface-variant`, centred, 40 tall | same |

## States
- Item states as Tree: hover, focus (inset ring), pressed, selected, expanded and collapsed.
- Current: follows scrolling; changes when a new heading's top crosses 25% of the document viewport's height. It is not selection: a selected item (picked from the outline) and the current one can differ until the scroll settles.
- Collapsed ancestor of the current section: the ancestor shows the current marker instead, so position is never hidden.
- Filtering: non-matching branches hide; ancestors of matches stay, dimmed; no matches shows "No headings match" with Clear.
- Empty: "No headings" with a short hint ("Headings you add appear here").
- Stale: while the document re-parses, the outline keeps the old items and shows no spinner unless it takes over 1 s.

## Behaviour
- Pointer and touch: pressing an item scrolls the document so the heading sits at the top (with `space-4` to spare) and moves keyboard focus to the heading in the document; on touch the sheet then closes.
- Keyboard: as Tree (Up, Down, Left to parent or collapse, Right to child or expand, Home, End, typeahead); Enter jumps to the heading; Escape returns focus to the document at the current position.
- Follow mode: the outline scrolls itself to keep the current item in view unless the person has scrolled the outline in the last 3 s.
- Collapse all: collapses to top-level headings; a second press expands all.
- Filter: typing narrows the outline; Down moves into the results; Enter jumps to the first match.
- Drag and drop (editable documents): dragging a heading moves its whole section, with the drop line from Reorderable list.
- Motion: the current marker slides between items over `duration-medium-2` with `ease-standard`; jumps scroll the document smoothly over `duration-long-2`. Reduced motion: the marker and the document jump.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Sidebar at density -2; Ctrl+Shift+O (or the app's) focuses the outline; the current bar matches Fluent's selection pill. |
| macOS | Sidebar at density -2 in a source-list pane; ⌃⌘S toggles the sidebar; symbols use SF-style icons from the set. |
| Linux | Sidebar at density -2; GNOME places it in a split view's sidebar. |
| Android | Outline sheet from a toolbar button on compact; sidebar on expanded widths. |
| iOS | Outline sheet (medium detent) on compact; sidebar on iPad; tapping the status bar still scrolls the document to the top. |
| Web | Sidebar in a `<nav aria-label="Outline">`; items are links to heading anchors so they work without script; `aria-current="location"` on the current item. |

## Accessibility
- Role tree named "Outline of <document>", or a navigation landmark with nested lists of links on the Web.
- Items report level, position, Expanded, and Current (`aria-current` location) for the section in view.
- Jumping moves focus to the heading in the document and announces it ("3.2 Keyboard, heading level 2").
- Filtering announces the count politely ("2 of 38 headings").
- Guides and the current bar are decorative; current is also exposed as a state and shown by weight.
- Contrast: numbers `on-surface-variant` 4.5:1; guides decorative; the current bar `primary` 3:1.
- Target: 32 rows (pointer), 48 (touch).
- Reduced motion as in Behaviour.

## Content
- Items show headings exactly as written, including numbers if the document numbers them; do not invent numbers.
- Header: "Outline". Empty: "No headings". Filter placeholder: "Filter headings".

## e.ui today
`collection.outline` is `collection.tree` with guides on: each nested row gets a `border-hairline` line down the last step of its indent, only as tall as the indent box. To reach this design:
- Draw one guide per ancestor level, full row height and continuous across rows; today only the last step gets a line, and it is 20px tall, so guides break into dashes and a depth-2 row shows no level-1 guide.
- Add the current-section marker that follows the document's scroll, and follow mode.
- Add numbers, the header with Collapse all, filtering with ancestors, and the touch sheet.
- Jump focus to the heading on activation and report `aria-current` location.
- Inherit every Tree fix: no 512-row cap, a visible focus ring, full keyboard model.
