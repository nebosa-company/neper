# Breadcrumbs

Breadcrumbs show where the current page sits in a hierarchy (folders, projects, settings sections) as a trail of its ancestors, each one a link back up, ending with the current place.

## Anatomy
1. Trail: a single row that never wraps.
2. Crumb: an ancestor, `body-medium` text (optional 18 leading icon on the root only) in a 32-tall pressable with `radius-sm` corners.
3. Separator: `chevron-right` at 16, `on-surface-variant`, mirrored in right-to-left layouts; not focusable.
4. Current place: the last item, `on-surface` at weight 600, not a link.
5. Overflow crumb: `more-horiz` in place of the collapsed middle levels, opening a menu of them.
6. Edit field (optional, file browsers): the path as editable text, replacing the trail.

## Variants and when to use
| Variant | Use for |
|---|---|
| Trail | Desktop and expanded layouts with 3 or more levels: a file path, a project's settings section, a docs page. |
| Trail with overflow | The same when the trail is wider than its container. |
| Editable path | File browsers and tools where users type or paste a path. Press the trail's empty space (or Ctrl+L) to edit. |
| Parent link | Compact width: one crumb, the parent with `chevron-left`, 48 target; the rest of the trail is dropped. |

When users move one level at a time and cannot jump, use NavigationStack's Back. Top-level destinations are a DestinationBar. Steps of a task are a Wizard's stepper, not breadcrumbs.

## Specs
| Part | Pointer | Touch |
|---|---|---|
| Crumb height | `control-sm` 32 | `control-lg` 48 |
| Crumb padding | `space-2` 8 sides, `radius-sm` | same |
| Crumb type and colour | `body-medium` 14/20, `on-surface-variant` | same |
| Crumb max width | 200, then ellipsis in the middle ("destination...test.e") | 160 |
| Current place | `body-medium` weight 600, `on-surface`, max 320 | same |
| Root icon | 18 (`icon-sm`), 4 before the label | same |
| Separator | `chevron-right` 16, `on-surface-variant`, no extra margin (crumb padding spaces it) | same |
| Hover | label `on-surface`, state layer `state-hover` | pressed only |
| Drop target | `primary-container`, `on-primary-container` | |
| Overflow menu | Menu spec, 32 items (48 touch), folder icons | |
| Edit field | outlined dense field, full width of the trail, 40 tall | |

## States
- Crumb: rest, hover (label darkens to `on-surface` plus the layer), focus (ring 2px outside), pressed.
- Current place: no interactive states; it is not a Tab stop.
- Drop target: while dragging files or items over a crumb, it fills with `primary-container`; holding over it for `duration-long-2` navigates there.
- Overflowed: the middle crumbs collapse into one `more-horiz` crumb; the first (root) and the last two stay.
- Editing: the field replaces the trail, with the text selected.

## Behaviour
- Press a crumb to navigate to that level; the page replaces the current one and the trail shortens.
- Each crumb and the overflow crumb are Tab stops in order; Enter or Space activates. Left/Right do not move between crumbs (it is a list of links, not a toolbar).
- Overflow is computed from the width: collapse the second crumb first, then the next, into the overflow menu, keeping reading order in the menu.
- Editing: Enter navigates to the typed path (an unknown path shows an inline error under the field and keeps it open), Escape restores the trail; Tab completion of folder names is offered where the host provides it.
- A crumb may open a menu of its siblings from a hover-revealed `chevron-down` in tool apps (file browsers); the crumb itself still navigates.
- Motion: none on navigation; the trail updates in place. The edit field cross-fades in over `duration-short-3` with `ease-standard`.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Pointer; File Explorer conventions: editable path on empty-space press, `chevron-right` separators that open a sibling-folder menu. |
| macOS | Pointer; Finder shows a path bar at the bottom rather than a top trail: place the trail in the window's bottom bar for file browsers, in the content for documents. No editable path (use Go to folder, ⇧⌘G). |
| Linux | Pointer; GNOME Files uses path buttons with an editable location on Ctrl+L; KDE Dolphin uses the same trail with an editable toggle. |
| Android | Parent link on compact; the full trail on tablets at `window-expanded`. |
| iOS | Rare: use the navigation bar's back title. The full trail only in iPad file browsers, as the Files app's path menu on the title. |
| Web | `nav` with `aria-label="Breadcrumb"` and an ordered list; the current item has `aria-current="page"`; links are real `<a>` elements with URLs. |

## Accessibility
- A Navigation landmark named "Location" (or "Breadcrumb"), containing a list; each crumb is a Link named by its level.
- The current place reports Current = page and is text, not a link.
- The overflow crumb is a Button named "Show 3 hidden levels", Has popup = menu, Expanded while open.
- Separators are hidden from the tree; a screen reader reads "Location, list, 4 items, Workspace, link, ...".
- Contrast: `on-surface-variant` on `surface` is 4.5:1 or better; hover raises it to `on-surface`.
- Targets: 32 tall crumbs on pointer, 48 on touch; the separator is not a target.
- Truncated names show their full text in a tooltip and in the accessible name.

## Content
- Crumbs are the levels' own names, exactly as they appear elsewhere: "neper", "lib", "navigation.e". No paraphrase, no casing change for file names.
- The root may be an icon plus a word ("Workspace"); never an icon alone.
- No trailing separator after the current place.

## e.ui today
`navigation.breadcrumbs` writes the names in a row with `space-xs` gaps and literal "/" separators; every name but the last is a `control.link` in a 32 region, and the last is Label-role text. To reach this design:
- Centre each crumb's text in its 32 target: `Region` lays it at Start/Start today, so links ride 6 px above the separators and the current name.
- Replace the "/" text with the `chevron-right` icon hidden from the tree, and stop the Body/Label type mismatch: all crumbs `body-medium`, the current at 600.
- Give the current place Current = page (it has no state today) and make the group a Navigation landmark with a list.
- Draw crumb states (hover, focus ring, pressed) and the drop-target state.
- Add width-driven overflow into a `more-horiz` menu, middle-ellipsis truncation with tooltips, the parent-only compact form and the optional editable path.
