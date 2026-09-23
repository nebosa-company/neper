# NavigationStack

A navigation stack is drill-down navigation: each choice pushes a page on top of the last, the top page fills the view under an app bar with Back, and Back, Escape or the system back gesture pops it to reveal the page beneath.

## Anatomy
1. Page: the top of the stack, filling the stack's area.
2. App bar: the page's title; Back (`arrow-back`) leads whenever there is a page beneath.
3. Page beneath: kept alive (state, scroll position), visible only during a transition or a predictive back gesture.
4. Pointer hosts only, deeper than two levels: Breadcrumbs in the bar in place of the title.

## Variants and when to use
| Variant | Use for |
|---|---|
| Stack | Drill-down in one pane: project, then branch, then build. Compact windows, and a single pane of a NavigationSplit. |
| Stack with breadcrumbs | Pointer hosts with deep hierarchies (settings, file trees) where jumping several levels up is common. |
| Modal stack | A multi-page flow in a sheet or full-screen dialog (share, add account): Close at the root instead of Back, Back on pushed pages. |

When the list and the detail fit side by side, use NavigationSplit. Fixed ordered steps are a Wizard. Switching among top-level places is a DestinationBar (each destination keeps its own stack).

## Specs
| Part | Touch | Pointer |
|---|---|---|
| App bar | small 64 (or medium / large at the root), see AppBar | 48, `title-medium` |
| Back | icon button 40, `arrow-back` 24, `on-surface` | 32, 18 icon |
| Title | `title-large`, 8 after Back | `title-medium`, or Breadcrumbs from 3 levels |
| Page | fills; `surface` | same |
| Predictive back | top page scales to 90%, `radius-xl` corners, `elevation-3`, moves up to 8% toward the end; page beneath at 90% opacity on `surface-container-highest` | none |
| Transition offset | incoming page from 100% at the end; outgoing moves 30% to the start and fades to 0 | incoming from 8% with fade (a shorter move reads better on large windows) |

## States
- Root: no Back (a `menu` button or nothing leads); the title is the section's name.
- Pushed: Back leads; the title is the page's name.
- Transitioning: push or pop in progress; input on the outgoing page is ignored.
- Predictive back: during an Android back gesture (or an iOS edge swipe) the top page follows the finger; releasing past the threshold commits the pop, otherwise it springs back.
- Unsaved changes on the top page: popping asks first ("Discard changes to build settings?") with Discard and Keep editing.

## Behaviour
- Push on a pick: a row press, Enter on a focused row, or a link; the new page's heading receives focus.
- Pop: Back, Escape, Alt+Left (Windows, Linux, Web), ⌘[ (macOS), the mouse's back button, the system back gesture, an edge swipe on iOS. Pop to root: press the current DestinationBar item again, or a breadcrumb.
- After a pop, focus returns to the element that pushed the page (the row), and the page beneath keeps its scroll position.
- The stack is the caller's model; the component reports pop and never changes the stack itself.
- Deep links build the whole stack beneath the target page so Back works as if the user had drilled down.
- Motion: push with `ease-emphasized-decelerate` over `duration-medium-2`; pop with `ease-emphasized-accelerate` over `duration-medium-1`; predictive back follows the gesture, then completes with `ease-emphasized-decelerate` over `duration-short-4` (commit) or `ease-standard` over `duration-short-4` (cancel). Reduced motion: cross-fade over `duration-short-3`, no slide or scale.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Pointer bar; Back in the bar (or the title bar's back button for a single-window app); Alt+Left and the mouse back button pop; entrance motion is a short slide-up fade (the Windows page transition). |
| macOS | Back is a toolbar button (`chevron-left`) with ⌘[; no large movement: the content cross-fades or slides 8%; swipe with two fingers on a trackpad pops. |
| Linux | GNOME `AdwNavigationView`: Back in the header bar, Alt+Left, mouse back, a swipe on touchpads; KDE Kirigami page stack with the same shortcuts. |
| Android | Touch bar; predictive back gesture with the scale-and-round preview; the system back leaves the stack before leaving the destination. |
| iOS | `UINavigationController`: Back is `chevron-left` plus the previous page's title (truncated to "Back" when long); interactive edge swipe from the leading edge; large title at the root collapsing on scroll. |
| Web | Each push is a history entry and a URL; the browser's Back pops; the in-page Back uses the same history (never a separate stack). |

## Accessibility
- The page is the Main landmark (or a Region inside a pane), named by its title; the title is a Heading level 1.
- Back is a Button named "Back to projects" (the page it returns to), not a bare "Back".
- On push, focus moves to the new page's heading and it is announced; on pop, focus returns to the pushing control and nothing else is announced.
- Escape pops only when no inner control (a field, a menu) consumes it first.
- Contrast and targets follow AppBar: 48 touch targets, 32 on pointer.
- Reduced motion: cross-fade only; predictive back shows no scale.

## Content
- Titles are the page's noun, identical to the row that opened it ("neper", "Branches").
- Back's accessible name uses the page below's title; its visible label is the icon (plus that title on iOS).
- Discard prompts say what is lost: "Discard changes to build settings?".

## e.ui today
`navigation.navigation_stack` shows the top page under an `app_bar` titled by it, with a worded "Back" action that fires `pop` while there is a page beneath, and a scope where Escape (and so the host's back gesture) pops. To reach this design:
- Make Back visible: it is a worded Plain action whose `primary` label lands on the `primary` bar (see AppBar), so today only Escape and the back gesture make it discoverable. Use the `arrow-back` icon button named "Back to <previous title>".
- Adopt the AppBar redesign (`surface` bar, 64 touch / 48 pointer, `title-large` / `title-medium`).
- Add push and pop transitions and the predictive back preview, which need the page beneath rendered during a transition; keep it in the tree as inert.
- Move focus to the new heading on push and back to the pushing element on pop; restore scroll positions.
- Add Alt+Left, ⌘[ and mouse-back handling, the breadcrumbs option, and a discard-changes guard hook before `pop` fires.
