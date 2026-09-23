# Pagination

Pagination splits a long result set into numbered pages and lets the person step to the previous or next page or jump to one by number.

## Anatomy
1. Previous button: icon button with `chevron-left`, named "Previous page".
2. Page buttons: numerals in `label-large`, round, `on-surface-variant`.
3. Current page: `secondary-container` fill with `on-secondary-container` numerals, marked current in the tree.
4. Ellipsis: a non-interactive "…" standing for the pages in a gap.
5. Next button: icon button with `chevron-right`, named "Next page".
6. Optional range and page size (table footers): "21–40 of 1,284" and a Rows per page select.

## Variants and when to use
| Variant | Use for |
|---|---|
| Numbered | Search results and archives where people come back to "page 3": first, last, current and two neighbours, ellipses between. |
| Table footer | Under a Table or Data grid on desktop: rows per page, the range, previous and next. No numbers: the range carries position. |
| Compact | Widths under 600: Previous, "Page 12 of 24", Next as text buttons. |

Prefer continuous scrolling (Virtual list with paging) for feeds and browsing, and "Show more" for short expansions. Use Page indicator for a handful of swipeable pages with no numbers.

## Specs
| Part | Touch / default | Pointer (density -1) |
|---|---|---|
| Button | `control-md` 40 circle, min 40 wide, `space-2` 8 sides for 3+ digits | `control-sm` 32 |
| Target | pads to `target-touch` 48 on touch | `target-pointer` 32 |
| Gap | `space-1` 4 | `space-1` 4 |
| Numerals | `label-large`, tabular figures, `on-surface-variant` | same |
| Current | `secondary-container` / `on-secondary-container` | same |
| Ellipsis | 24 wide (20 dense), `on-surface-variant`, not focusable | same |
| Previous / next icons | `icon-md` 24 | `icon-sm` 18 |
| Slots | 7 fixed: first, last, current, two neighbours, two ellipses (a page number stands in for an ellipsis that would hide one page) | same |
| Table footer | `control-lg` 48 tall, `body-medium` `on-surface-variant`, range in `on-surface`, `space-4` 16 between groups, aligned to the end | same |

The slot count is fixed so the control never changes width as the current page moves.

## States
- Hover: `state-hover` layer on the button.
- Focus: `state-focus` layer and the 3px ring outside.
- Pressed: `state-pressed` layer.
- Current: tonal fill; pressing it does nothing.
- Disabled: Previous on the first page and Next on the last, at `on-surface` 38%, not focusable.
- Loading a page: the pressed page becomes current immediately; the result area shows its own loading state. The control stays usable.

## Behaviour
- A press loads that page and moves focus to the top of the results (the results heading), so screen reader and keyboard users start reading the new page; the pagination keeps its position on screen.
- Keyboard: Tab moves through Previous, the page buttons and Next. Left and Right do nothing special; the buttons are ordinary buttons.
- Global shortcuts where the host has them: Alt+Left and Alt+Right (browser history) step pages on the Web, because each page is a URL.
- Changing Rows per page keeps the first visible record in view: 21–40 at 20 per page becomes 1–50 at 50 per page.
- Motion: none on the control; the current fill cross-fades in `duration-short-2`.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Pointer density (32); table footers match WinUI's data-grid footers; buttons get access keys only in the footer's select. |
| macOS | Pointer density; pagination is uncommon in native apps, so prefer continuous scrolling and use the table footer only in data tools. |
| Linux | Pointer density; GNOME apps rarely page: prefer continuous scrolling with "Load more". |
| Android | Touch metrics; compact variant under 600 wide; prefer continuous scrolling in feeds. |
| iOS | Touch metrics (44pt); compact variant; prefer continuous scrolling. |
| Web | Default 40 with a coarse pointer, 32 with a fine one; each page is a real link (`<a href="?page=12">`) with `aria-current="page"` inside `<nav aria-label>`. |

## Accessibility
- Role navigation, named by what it pages ("Results pages"). Each page is a link or button named "Page 12"; the current one is marked current (`aria-current="page"`) and says "current page".
- Previous and next are named "Previous page" and "Next page"; disabled ones report Disabled.
- Ellipses are hidden from the tree.
- After a page change, announce "Page 12 of 24" politely and move focus to the results heading.
- Contrast: numerals 4.5:1 on `surface` and on the current fill; the current page differs by fill, not only colour of text.
- Target: 48 on touch, 32 on pointer, even though the visual is 40 or 32.
- Reduced motion: nothing moves.

## Content
- Numerals only in buttons; the range uses an en dash and the thousands separator of the locale: "21–40 of 1,284".
- Compact text: "Page 12 of 24".
- Labels: "Rows per page", "Previous", "Next". Localised and mirrored in right-to-left (chevrons flip).

## e.ui today
`collection.pagination` draws an outlined "Previous" button, a window of `window` page buttons from `window / 2` before `current`, and an outlined "Next" button, all firing `turn`; the current page is Filled with its fill mixed toward `selection`. To reach this design:
- Replace the sliding window with the fixed seven slots: first, last, current, two neighbours and ellipses, so every page is reachable in two steps.
- Use icon buttons for Previous and Next, round 40 (32 dense) page buttons, and the `secondary-container` current page.
- Take the labels from the caller for localisation; today "Previous" and "Next" are English literals.
- Mark the current page current and the group as navigation; name page buttons "Page 12".
- Add the table-footer variant (range and rows per page) and the compact variant.
- Draw state layers and the focus ring; disabled ends at 38%, not half opacity.
