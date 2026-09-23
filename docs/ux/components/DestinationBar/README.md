# DestinationBar

A destination bar lists an app's top-level places (3 to 7) and shows which one is current; it takes one of three forms, a bottom navigation bar, a side rail or a sidebar, and switches between them by the window's size class, so one model serves every window.

## Anatomy
1. Container: navigation bar (bottom, full width), rail (side, 80 wide) or sidebar (side, 240-360 wide).
2. Destination: an icon (24) and a label; the current destination's icon sits in an indicator pill.
3. Indicator pill: `secondary-container`, `radius-full`; 64 x 32 in the bar, 56 x 32 in the rail, the whole 40-56 row in the sidebar.
4. Badge (optional): a dot or a count on the icon (bar, rail) or a trailing count or word (sidebar).
5. Rail extras (optional): a `menu` button that expands the rail into a modal drawer, and the screen's FAB, above the destinations.
6. Sidebar extras (optional): a header (the app or workspace name), section headings, dividers.

## Variants and when to use
| Form | Window size class | Destinations | Use for |
|---|---|---|---|
| Navigation bar | Compact, under `window-medium` 600 | 3-5 | Phones and narrow windows. Never with a bottom app bar. |
| Rail | Medium and expanded, 600-1199 | 3-7 | Tablets, foldables, narrow desktop windows. |
| Sidebar (standard drawer) | Large, `window-large` 1200 and up | 3-7 top level, plus sections | Desktop windows and wide tablets; the only form that can show sections and counts in words. |

Choose the form with the window size class, not the device: a phone in landscape at 700 gets the rail; a desktop window dragged under 600 gets the bar. An app may pin one form (a desktop-only tool may keep the sidebar and collapse it to the rail under 1200).

More than seven places, or places that need hierarchy, go in a NavigationDrawer. Open documents are DocumentTabs. Sections within one screen are Tabs.

## Specs
| Part | Navigation bar | Rail | Sidebar (pointer, density -2) | Sidebar (touch) |
|---|---|---|---|---|
| Size | `nav-bar` 80 tall, full width | `nav-rail` 80 wide, full height | 240-360 wide (`nav-drawer` max) | 360 max |
| Container | `surface-container` | `surface` | `surface-container-low` | same |
| Padding | 12 top, 16 bottom, 8 sides | 16 top | `space-3` 12 | 12 |
| Destination | flex 1, icon over label, gap 4 | icon over label, gap 4, 12 between | row 40 tall, icon 24 + label, gap 12, 16 start | row 56 tall |
| Pill | 64 x 32 | 56 x 32 | full row, `radius-full` | same |
| Label | `label-medium` 12/16 600 | `label-medium` | `label-large` 14/20 600 | same |
| Rest colours | icon and label `on-surface-variant` | same | same | same |
| Active colours | pill `secondary-container`, icon `on-secondary-container`, label `on-surface` | same | row `secondary-container`, content `on-secondary-container` | same |
| Badge | `nu-badge` on the icon (dot 6, count 16) | same | trailing `label-large` count or word, `on-surface-variant` | same |
| Section heading | | | `label-medium` `on-surface-variant`, 16 start, 16 top | same |
| FAB (rail) | | 56 `nu-fab`, no shadow, 8 below it | | |

## States
- Destination: rest, hover (state layer on the pill in bar and rail, on the row in the sidebar), focus (ring on the pill; inset 3px on sidebar rows), pressed, active.
- Active: pill fills from the centre outwards over `duration-medium-1`; the label weight stays 600 so nothing shifts.
- Badges: dot for "something new", count up to 999 ("999+"); counts in the sidebar may be words ("3 failed").
- Hidden (bar only, optional): slides down with content scrolled down, returns on scroll up.
- Form change: when the size class changes, the bar, rail or sidebar is replaced in place; the current destination is kept.

## Behaviour
- Press a destination to go to its root; pressing the current destination again scrolls it to the top and then pops it to its root.
- Each destination keeps its own navigation stack: switching back returns to where the user left it.
- Keyboard: the bar (or rail, sidebar) is one Tab stop; Left/Right (bar) or Up/Down (rail, sidebar) move focus, Home/End jump, Enter or Space activates. Ctrl+1..9 goes to a destination on pointer hosts.
- Destinations never scroll horizontally; a sidebar with more items than fit scrolls vertically inside itself.
- Rail's `menu` button opens the NavigationDrawer (modal) with the same destinations plus secondary ones.
- Motion: pill in with `ease-emphasized-decelerate` over `duration-medium-1`; content change between destinations is a fade through (out `duration-short-3` with `ease-emphasized-accelerate`, in `duration-medium-1` with `ease-emphasized-decelerate`). Form changes are instant. Reduced motion: cross-fade.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Sidebar at pointer density (40 rows) by default, collapsing to the rail (as WinUI NavigationView's compact mode) under 1200 and to a top/bottom bar only in very narrow windows. The sidebar can be collapsed by the user with a `menu` button at its top. |
| macOS | Sidebar in the window's sidebar area (source list look: translucent `surface-container-low`, 28-32 rows, section headings); collapsible with ⌃⌘S; no rail or bottom bar at desktop sizes. |
| Linux | Sidebar (GNOME `AdwNavigationSplitView` sidebar) collapsing to a bottom view switcher bar in narrow windows; KDE: sidebar with the desktop's list density. |
| Android | Bar on compact, rail on medium and expanded, sidebar (standard drawer) at large; system back leaves the current destination's stack, then goes to the start destination, then exits. |
| iOS | Tab bar (49pt, labels 10pt) on iPhone: up to five, "More" beyond; iPad: the sidebar-adaptable tab bar (floating at top) that becomes a sidebar. No rail. |
| Web | By viewport size class; `nav` landmark with links (`aria-current="page"`); the URL reflects the destination. |

## Accessibility
- A Navigation landmark named "Main"; destinations are Links (or Tabs if content changes without a URL) with Current = page on the active one.
- Names are the labels; a badge adds to the name ("Builds, 3 new"); a dot badge adds "new".
- Labels are always shown in the bar and rail (no icon-only destinations); icons alone would fail the "name visible" rule.
- Contrast: labels `on-surface-variant` on `surface-container` 4.5:1 or better; the active icon on its pill likewise; the pill itself 3:1 against the container is not required because the label weight and icon colour also change.
- Targets: each bar destination is at least 48 x 48 (the whole column is pressable), rail items 56 x 56, sidebar rows 40 (pointer) or 56 (touch).
- Form changes keep focus on the same destination.
- Reduced motion: pill appears without growth; content cross-fades.

## Content
- Labels: one short noun each, 1-2 words, sentence case: "Home", "Projects", "Builds", "Settings". No verbs ("View builds"), no truncation: shorten the label instead.
- Order by frequency of use; Settings last. The same order in every form.
- Sidebar sections are nouns ("Teams"), not labels with colons.

## e.ui today
`navigation.destination_bar` draws the destinations as tabs on a `surface-variant` sheet in `.Bottom`, `.Rail` or `.Sidebar` form (the wrappers `navigation_rail`, `bottom_navigation` and `sidebar` fix it), and `destination_form(width)` picks the form from the size class. To reach this design:
- Add an icon per destination and draw the three forms per spec: 80 bar on `surface-container` with 64 x 32 pills, 80 rail on `surface` with 56 x 32 pills, sidebar rows with a full pill; today `.Rail` and `.Sidebar` differ only in `extent`.
- Replace the Filled selected tab (`primary` mixed 50% toward selection, `on-primary` label) with the `secondary-container` pill and keep rest items `on-surface-variant`, not Plain `primary`.
- Centre each label and icon: `Region` lays content at Start/Start, so every label hugs its tab's top-left.
- Draw the focus ring (`pressable_states` drops `look.focus_ring`) and give each destination its column or row index; the list has only a count.
- Move `destination_form`'s thresholds to 600 (bar to rail) and 1200 (rail to sidebar), and add badges, the rail's menu and FAB slots, sidebar sections and Current = page semantics (Links in a Navigation landmark instead of a TabList).
