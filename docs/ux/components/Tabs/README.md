# Tabs

Tabs switch between peer views of the same subject in place, one visible at a time; primary tabs sit under the app bar for a page's main views, secondary tabs inside a pane.

## Anatomy
1. Tab bar: `surface`, a 1px `outline-variant` line along the bottom.
2. Tab: a label (and optional icon above it), the whole cell pressable.
3. Active indicator: primary tabs 3px `primary`, top corners rounded, as wide as the label; secondary tabs 2px across the whole tab.
4. Optional badge: a count on the icon, or after the label on text-only tabs.
5. Overflow button (scrollable bar on pointer hosts): an icon button at the end.
6. Page: the selected tab's content, directly below the bar.

## Variants and when to use
| Variant | Indicator | Label colour (active) | Use for |
|---|---|---|---|
| Primary | 3px, label width, `primary` | `primary` | The main views of a page, under the top app bar. |
| Primary with icon | same, under the label | `primary` | Top-level views on touch with recognisable icons. 64 tall. |
| Secondary | 2px full width, `primary` | `on-surface` | Views inside a pane or card, or below primary tabs. |
| Fixed | tabs share the width | | 2 to 4 tabs on compact. |
| Scrollable | tabs size to their label, start-aligned | | 5 or more, or long labels; the default on desktop. |

Use a Segmented button to switch a mode within one view (List/Board), a Navigation bar or rail for app destinations, and Document tabs for closable open files.

## Specs
| Part | Default (touch) | Dense (density -1) |
|---|---|---|
| Tab height | `control-lg` 48; 64 with icon | `control-md` 40; 56 with icon |
| Tab padding | `space-4` 16 sides; min width 90 fixed, 48 scrollable | same, min width 48 |
| Label | `title-small` (14/20, 600) | same |
| Icon | `icon-md`, 2px above the label | same |
| Label colour | active `primary` (secondary: `on-surface`), others `on-surface-variant` | same |
| Indicator | primary 3px, `radius` 3px top, label width (min 24); secondary 2px full | same |
| Bar line | `divider` 1, `outline-variant` | same |
| Scrollable start inset | `space-4` 16 on compact, `space-6` 24 on medium and up | `space-2` 8 |
| Badge | count badge on the icon, or `space-1` after the label | same |
| Focus ring | inset 3px | same |

## States
- Hover `state-hover` of the label colour over the tab; focus `state-focus` plus the inset ring; pressed `state-pressed` (ripple on touch).
- Active: label in its active colour and the indicator. Never convey selection by weight or colour alone: the indicator is always drawn.
- Disabled: label `on-surface` 38%, not focusable, skipped by arrow keys. Prefer hiding a tab over disabling it unless its absence would confuse.
- Loading page: keep the bar interactive, show Skeleton in the page.

## Behaviour
- Pressing a tab selects it and shows its page at once (automatic activation). Keep each tab's scroll position.
- Keyboard: Tab enters the bar at the selected tab; Left and Right move and select (mirrored in right-to-left); Home and End go to the first and last; Tab again moves into the page. Ctrl+Tab and Ctrl+Shift+Tab cycle tabs from inside the page on desktop.
- The indicator slides and resizes to the new tab over `duration-medium-2` with `ease-standard`; the page cross-fades (`duration-short-4`) or, on compact touch, slides with the swipe.
- Touch: swiping the page moves between fixed tabs. Scrollable bars scroll horizontally and bring the selected tab fully into view.
- Pointer: a scrollable bar that overflows shows a fade at the clipped edge and a chevron button that pages it; the wheel scrolls it.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Dense, scrollable, start-aligned; WinUI Pivot style labels are not used; Ctrl+Tab cycles. |
| macOS | Dense; for a window's top-level views prefer a Segmented button in the toolbar (the macOS idiom); secondary tabs inside inspectors. Ctrl+Tab cycles. |
| Linux | Dense; GNOME uses a view switcher in the header bar on wide windows and a bottom bar on narrow ones; KDE uses tabs as specified. |
| Android | Default; fixed primary tabs under the app bar; swipe between pages. |
| iOS | Default; for top-level destinations use the Navigation bar (tab bar) instead; tabs only as a Segmented control or secondary tabs in a view. |
| Web | Default on touch, dense with a fine pointer; `role="tablist"` / `tab` / `tabpanel` with roving tabindex. |

## Accessibility
- Bar role tab list (with its orientation); each tab role tab, name = label (+ badge, e.g. "Pull requests, 12"), state selected; the page role tab panel labelled by its tab.
- Roving focus: only the selected tab is in the Tab order.
- Screen readers announce "tab, 2 of 6, selected". The badge count is part of the name, never a separate node.
- Label contrast 4.5:1 for active and inactive tabs; the indicator 3:1 against `surface`.
- Reduced motion: the indicator jumps; the page cross-fades in 100ms.

## Content
One or two words, nouns, sentence case: "Overview", "Pull requests". No verbs, no truncation on fixed tabs (switch to scrollable instead). Counts go in a badge, not "(12)".

## e.ui today
`control.tabs` draws Plain `pressable`s with a `border-thick` underline as wide as the label and a 50% `selection` tint on the selected tab; `control.tab_view` adds the page. To reach this design:
- Drop the selection tint; set labels in `on-surface-variant` with the active one `primary` (the source sets `primary` on a label that is already `primary`, so selection shows only by the line).
- Draw the 3px primary indicator with rounded top corners, and the secondary 2px full-width variant; add the 1px bar line.
- Add icon tabs, badges, fixed versus scrollable layout, the overflow button and horizontal scrolling.
- Add Home/End, skip disabled tabs, the inset focus ring and state layers.
- Animate the indicator between tabs; keep per-page scroll state in `tab_view`.
