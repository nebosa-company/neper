# NavigationSplit

A navigation split is the list-detail layout: a list of items and the selected item's detail side by side when the window is wide enough, and one at a time, with the detail pushed over the list, when it is not.

## Anatomy
1. List pane: the items (a List), with its own header and actions; the selected item is marked.
2. Detail pane: the selected item's content, with its own header and actions.
3. Divider: on touch and tablet hosts a 24 gutter with a 4 x 48 drag handle between rounded panes; on pointer hosts a 1px sash between flush panes.
4. Compact only: the detail's app bar with Back (`arrow-back`) to the list.
5. Empty detail: a short statement when nothing is selected ("Select a build to see its log").

## Variants and when to use
| Variant | Window size class | Layout |
|---|---|---|
| Side by side | Expanded 840+ (and medium when the detail is short) | Both panes; list 360 by default (touch) or 280 (pointer), detail fills the rest. |
| Single pane | Compact under 600, and medium 600-839 by default | The list; selecting pushes the detail; Back returns. |
| With supporting pane | Large 1200+ | A third, narrower pane at the end (an inspector or related items). Use a DockLayout if the user must rearrange it. |

Drill-down more than two levels deep, where each level replaces the last, is a NavigationStack. Resizable tool panels around a document are a DockLayout. Top-level destinations are a DestinationBar beside this layout, not a pane of it.

## Specs
| Part | Touch / tablet | Pointer |
|---|---|---|
| Window padding | `space-4` 16 (`space-6` 24 at large) | 0 (panes flush) |
| List pane | default 360, min 280, max 50%; `surface-container-low`, `radius-lg` | default 280, min 200, max 50%; `surface-container-low`, square |
| Detail pane | fills, min 360; `surface-container-lowest`, `radius-lg` | fills, min 320; `surface`, square |
| Gutter / sash | 24 gutter; handle 4 x 48 `outline`, `radius-full` | 1 `outline-variant` sash, 8 grab area |
| Handle hover | `on-surface-variant` | sash 4 `primary` |
| Handle dragged | 12 x 48 `on-surface` | sash 4 `primary` |
| Handle focus | ring 2px outside | ring round the sash |
| List header | `title-medium`, 16 sides, 16 top | 48 app bar at pointer density |
| List rows | List item two-line 72, selected `secondary-container` | dense two-line 56 |
| Detail header | `headline-small`, 24 sides, 20 top; actions end-aligned | 48 app bar |
| Snap points (touch) | 360, 50%, the list collapsed | none; continuous |

## States
- Side by side, an item selected: its row is `secondary-container`; the detail shows it.
- Side by side, nothing selected: the detail shows the empty statement in `body-medium` `on-surface-variant`, centred.
- Single pane, list: rows pressable; the last-selected row keeps a focus position but no selected fill.
- Single pane, detail: Back in the app bar; the list is not visible.
- Resizing: the handle or sash in its dragged state; the panes reflow live.
- Loading detail: the detail's header shows at once, its body a skeleton; the list stays interactive.

## Behaviour
- Selection: press a row (or Enter on it) to show its detail; in side-by-side mode focus stays in the list so arrow keys can browse, and the detail updates after `duration-short-2` of no further movement.
- Keyboard: Up/Down move in the list, Home/End jump, typeahead finds; Tab moves to the detail; F6 cycles panes; Escape in the detail returns focus to the list (side by side) or goes Back (single pane).
- Back (single pane): the app bar's Back, Escape, the system back gesture, or a swipe from the start edge on iOS; the list returns scrolled to the same row.
- Resizing: drag the handle or sash; on touch the list snaps to 360, 50% or collapsed; double-click the sash (pointer) resets it. Keyboard: Left/Right move by 8, Home/End to the limits.
- Size class change: the selected item survives both ways; going to single pane with an item selected shows the detail with Back.
- Motion: push (single pane) slides the detail in from the end with `ease-emphasized-decelerate` over `duration-medium-2` while the list shifts 30% and fades; Back reverses with `ease-emphasized-accelerate` over `duration-medium-1`; predictive back scales the detail to 90% as the gesture moves (see NavigationStack). Side-by-side detail changes cross-fade over `duration-short-3`. Reduced motion: cross-fade only.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Pointer: flush panes, 1px sash, list 280; the list pane may be the ListDetailsView convention with a 48 header; single pane only under 600 wide windows. |
| macOS | Pointer: `NSSplitView` convention, a hairline divider, list in the content column next to a sidebar (three columns: sidebar, list, detail) in apps like Mail; collapse with the toolbar's column buttons. |
| Linux | Pointer: GNOME `AdwNavigationSplitView` (collapses to a stack under 600 with a Back button in the header bar); KDE uses a Kirigami page row with the same collapse. |
| Android | Touch: M3 list-detail with gutter and handle at expanded; foldables put the hinge in the gutter; predictive back on compact. |
| iOS | `UISplitViewController`: side by side on iPad (list 320pt), a stack on iPhone with the back button titled by the list ("Builds"); swipe from the leading edge goes back. |
| Web | By viewport size class; the selected item is in the URL, so Back in the browser goes back in single pane; `main` holds the detail, the list is a `nav` or a region. |

## Accessibility
- Each pane is a Region named by its header ("Builds", "Build 4127"); the list is a List (or Grid) whose selected row reports Selected (side by side) or Current (single pane).
- The handle and sash are Separators with a value, Increment / Decrement, named "Resize list".
- Selecting in side-by-side mode announces nothing extra (the detail is not moved into); pushing in single pane moves focus to the detail's heading and announces it.
- Back is named "Back to builds".
- Contrast: pane fills are tonal steps; separation never relies on the handle's colour alone (the pane edges are visible at 3:1 via `surface-container` round `surface-container-lowest`).
- Targets: the handle's grab area is 24 x 48 at least (touch 48 x 48 with its padding); the sash's 8 is for pointer hosts only, with keyboard resize as the alternative.
- Reduced motion: no slide on push or Back.

## Content
- List header: the collection's noun ("Builds"). Detail header: the item's name ("Build 4127").
- Empty detail: one sentence, what to do: "Select a build to see its log".
- Back's name uses the list's title: "Back to builds".

## e.ui today
`navigation.navigation_split` shows `primary` and `detail` in a `control.split_view` from the medium size class up (600), or one of them alone in a clipped box on compact, with a 4px `border`-filled handle and 64 minimum per side. To reach this design:
- Move the side-by-side threshold to expanded (840) by default, with an opt-in for medium, and add the large-window supporting pane.
- Draw the two dividers: the 24 gutter with the 4 x 48 handle and rounded panes on touch hosts, the 1px sash with the 4px `primary` hover on pointer hosts; replace the 4px `border` bar.
- In single pane, supply the detail's Back: today there is no bar and no back affordance, so the caller must build one; take `pop` and a title, or compose NavigationStack.
- Raise the minimums (list 200 / 280, detail 320 / 360) and add snap points on touch.
- Name the panes as Regions and the handle "Resize list" (today "Divider"), and add push/Back motion and focus moves.
