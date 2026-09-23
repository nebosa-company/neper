# Divider

A divider is a thin line that separates groups of content in lists, menus, toolbars and panes when spacing alone is not enough.

## Anatomy
1. Line: 1 px (`divider`), `outline-variant`.
2. Insets: the start (and optionally end) margin that aligns the line with content.
3. Optional label: a word or section name in `label-medium`, splitting the line.

## Variants and when to use
| Variant | Geometry | Use for |
|---|---|---|
| Full width | edge to edge | Between sections of a list or a page; under a pane header. |
| Inset | starts at the text's start (56 after a 24 lead, 72 after a 40 avatar) | Between rows of a list with leading icons or avatars, so leads read as one column. |
| Middle inset | `space-4` 16 each side | Inside cards, menus and dialogs. |
| Vertical | 1 px wide, 24 tall in toolbars, full height between panes | Between toolbar groups; between docked panes. |
| Labelled | line, word, line | "or" between alternative flows; a date section in a long list ("Older than 30 days"). |

Prefer space before a divider: `space-6` between groups usually separates better. A card, group box or list section already draws its own edge. A draggable pane edge is a Split view sash, not a divider (the sash uses a divider at rest).

## Specs
| Part | Value |
|---|---|
| Thickness | `divider` 1 px at every density and scale (a hairline of one device pixel on 2× displays is not used) |
| Colour | `outline-variant`; `outline` only for a divider that must be seen in high contrast between two equal surfaces |
| Horizontal margins | full width 0; inset: text start; middle `space-4` 16 |
| Vertical margins | 0 in lists (rows carry their own padding); `space-2` 8 above and below between page sections |
| Vertical divider in a toolbar | 24 tall, `space-2` 8 each side |
| Label | `label-medium` 12/16, `on-surface-variant`, `space-3` 12 from the lines; start label with a 16 lead line |
| Sash (in Split view) | 9 wide hit area around the 1 px line; hover shows a 3 px `primary` handle |

## States
A divider is static: no hover, focus or disabled states. As a Split view sash it gains hover (3 px `primary` handle, `col-resize` cursor), focus (ring around the hit area) and dragged states.

## Behaviour
- Dividers never take input or focus.
- In a list, the divider belongs to the row above it, so reordering and deleting rows move it with them; the last row has none.
- Lists with dividers between every row are rare; use them only for rows with a lot of content, otherwise spacing and row height are enough.
- In RTL, insets mirror to the right.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Menu separators are middle inset; list dividers are rare (WinUI lists use spacing); toolbar dividers are vertical 24 tall. |
| macOS | Menu separators are middle inset, drawn by NSMenu; source lists use no dividers; table views use an inset divider. |
| Linux | GTK boxed lists have full-width dividers between every row; KDE lists usually none. Follow the desktop. |
| Android | Inset dividers under avatars, full width between sections. |
| iOS | Inset dividers between every row of a grouped list, starting at the text; none after the last row. |
| Web | `<hr>` for thematic breaks (role separator); decorative dividers are CSS borders with no semantics. |

## Accessibility
- Decorative by default: hidden from the tree.
- A divider that separates groups in a menu or toolbar is a Separator (role separator), so readers announce the group change.
- Contrast: `outline-variant` is decorative (under 3:1 by design); never rely on a divider alone to separate interactive regions, add space or a heading.
- High contrast themes raise dividers to `outline`.

## Content
- Labelled dividers: a short phrase in sentence case, no punctuation: "Older than 30 days". A lone connective stays lowercase: "or".
- Section labels name the group, not the divider: "Today", "Pinned", never "Separator".

## e.ui today
`control.divider` fills a `border-hairline` box in `border` across `axis`, `length` long or 100%, hidden from the tree. To reach this design:
- Colour it `outline-variant` (the `border` role maps to `outline`, too strong for a divider).
- Add inset and middle-inset options (a start and end margin) instead of leaving the parent to fake them with padding.
- Add the labelled divider.
- Report Separator when it splits menu or toolbar groups; keep it hidden when decorative.
