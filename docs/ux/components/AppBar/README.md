# AppBar

An app bar heads a screen or pane with its title, a navigation action and the few actions that act on the whole view; four top sizes set how loud the title is, and the bottom app bar carries the actions within thumb reach on touch hosts.

## Anatomy
1. Container: full-bleed, square, `surface` at rest and `surface-container` once content scrolls under it.
2. Leading navigation action (optional): one icon button, Back (`arrow-back`) on a pushed page or Open navigation (`menu`) on a top-level one.
3. Title: one line, cut with an ellipsis; in the top row for small and center-aligned, on its own line below the row for medium and large.
4. Trailing actions: up to three icon buttons, then More (`more-vert`) for the rest; an avatar may stand as the last one.
5. Bottom app bar only: up to four icon buttons at the start and an optional FAB at the end.

## Variants and when to use
| Variant | Height | Title | Use for |
|---|---|---|---|
| Small | `app-bar` 64 | `title-large`, start | The default for any screen or pane. |
| Center-aligned | 64 | `title-large`, centred | A single top-level screen with at most one trailing action (compact only; on wider windows use small). |
| Medium | 112 | `headline-small`, own line | A top-level screen whose title should lead; collapses to small on scroll. |
| Large | 152 | `headline-medium`, own line | The first screen of a section: "Projects", "Inbox". Collapses to small on scroll. |
| Contextual | 64 | "3 selected", `title-large` | Replaces the top bar while a selection is active; Close clears the selection. |
| Bottom app bar | `nav-bar` 80 | none | Touch hosts, compact width, a screen with 2-4 frequent actions and a FAB. Never together with a navigation bar. |
| Pointer (density -1) | `control-lg` 48 | `title-medium` | Desktop panes, dialogs full-screen on desktop, settings pages inside a window. |

A row of commands on the view below (bold, align, zoom) is a Toolbar. A window's File/Edit/View menus are a MenuBar. The app's top-level destinations are a DestinationBar, not app bar actions.

## Specs
| Part | Small / center | Medium | Large | Bottom | Pointer |
|---|---|---|---|---|---|
| Height | 64 | 112 | 152 | 80 | 48 |
| Side padding | `space-1` 4 (icon buttons carry their own 8) | 4; title `space-4` 16 | 4; title 16 | start 4, end `space-4` 16 | 4 |
| Title type | `title-large` 22/28 | `headline-small` 24/32 | `headline-medium` 28/36 | none | `title-medium` 16/24 600 |
| Title position | row, 8 after the leading button (16 with none) | bottom, 16 above the edge | bottom, 28 above the edge | | row |
| Icon buttons | `control-md` 40, 24 icon, gap `space-1` | same | same | same | `control-sm` 32, 18 icon |
| FAB | | | | 56, `radius-lg`, no shadow (it sits on the bar) | |
| Container | `surface`; scrolled `surface-container` | same | same | `surface-container` | `surface`; scrolled `surface-container` |
| Title colour | `on-surface` | `on-surface` | `on-surface` | | `on-surface` |
| Icon colour | leading `on-surface`, trailing `on-surface-variant` | same | same | `on-surface-variant` | same |
| Contextual | `secondary-container`, content `on-secondary-container` | | | | |

No bar draws a divider: the tonal change on scroll separates it from the content. No bar casts a shadow.

## States
- At rest: `surface`, flush with the page.
- Scrolled: when any content sits under the bar, the container changes to `surface-container` over `duration-short-4` with `ease-standard`. Medium and large collapse to small as the page scrolls, the headline cross-fading into the row title over the first 40 px of travel.
- Hidden on scroll (optional, compact only): the bar slides up with content scrolled down and returns on any upward scroll.
- Action states: every icon button has its hover, focus (ring) and pressed layers; a disabled action is hidden rather than dimmed unless its absence would move the others.
- Contextual: enters with the first selection, leaves when the selection is empty.

## Behaviour
- The title never wraps and never scrolls; it truncates at the end. The full title is the bar's accessible name and a tooltip on hover.
- Tab order: navigation action, then trailing actions left to right, then the page. The bar is not a stop itself.
- Back (leading) pops the NavigationStack; Escape and the host's back gesture do the same.
- Overflow: actions beyond three go into More, in the same order; an action never moves between the bar and More while the window keeps its size class.
- Tap the bar's empty space on iOS scrolls the page to the top.
- Motion: collapse and expand follow the scroll position (no easing); the contextual bar enters with `ease-emphasized-decelerate` over `duration-medium-2` and leaves with `ease-emphasized-accelerate` over `duration-short-4`. Reduced motion: cross-fade over `duration-short-3`.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Pointer density: 48 bar, 32 icon buttons. In a window with a custom title bar, the app bar merges with the caption area and leaves the caption buttons (min, max, close) at the end; drag the empty space to move the window. |
| macOS | Pointer density. The window's toolbar is the app bar: title in the unified title bar next to the traffic lights, actions at the end; no leading menu button (the sidebar toggle is used instead). Large titles are not used. |
| Linux | Pointer density. On GNOME the app bar is the header bar (title centred, actions at both ends, close button at the end); on KDE the title stays in the window frame and the bar holds actions only. |
| Android | Default sizes; small, medium and large; bottom app bar allowed; the system back gesture pops. Edge-to-edge: the bar pads under the status bar inset. |
| iOS | 44pt row; title centred (center-aligned is the default) and the large title (34pt) is the default top level, collapsing on scroll; Back shows the previous page's title next to the chevron. No bottom app bar: use a tab bar or a toolbar. |
| Web | Default sizes on touch, pointer density at `window-expanded` and up; a real `<header>` with an `<h1>`; sticky, not fixed. |

## Accessibility
- The bar is a Toolbar landmark (Web: `header` / banner) named by the title; the title is a Heading level 1.
- Every icon action has a name ("Search builds", "More options") and a tooltip with the same text; More reports Has popup = menu.
- The contextual bar announces "3 selected" politely when it appears and on each change; Close is named "Clear selection".
- Contrast: title and icons are `on-surface`/`on-surface-variant` on `surface` or `surface-container`, 4.5:1 or better in every theme.
- Targets: 48 on touch; 32 icon buttons on pointer hosts keep a 32 target.
- Reduced motion: no collapse animation; medium and large snap to small at the collapse point.

## Content
- Title: the screen's noun, not an instruction: "Builds", "Deployment history". Sentence case, no trailing punctuation, 1-3 words (fits 24 characters on compact).
- Contextual title: the count and state, "3 selected", never "3 items selected!".
- Action names are verbs or familiar nouns: "Search builds", "Filter", "Share".

## e.ui today
`navigation.app_bar` builds leading actions, a level-1 heading title and trailing actions in a row on `primary`, 48 tall with `space-sm` padding. To reach this design:
- Paint the bar `surface` (then `surface-container` on scroll) with `on-surface` content, not `primary`: today every worded action is Plain with a `primary` label on the `primary` bar and is invisible.
- Add sizes: small 64, center-aligned, medium 112 and large 152 with the headline line, plus the pointer 48 density, and a `scrolled: bool` (or scroll offset) input that drives the tonal change and collapse.
- Cap trailing actions at three and build the More menu from the rest (`overlay.menu_button`); keep the 8-leading limit only as an input check.
- Add the contextual variant (`selected_count`, a clear action) and a separate `navigation.bottom_app_bar` with a FAB slot.
- Use `title-large` for the title (today the Title role at 20/28 600) and change the group role to Toolbar.
- Give Back an icon (`arrow-back`) and the name "Back" (see NavigationStack).
