# SplitButton

A split button joins a main action to a menu of its close variants, so the common choice is one press and the alternatives one more: Merge with Squash and Rebase behind it.

## Anatomy
1. Leading button: the action's label (and optional icon); outer corners `radius-full`, inner corners `radius-xs`.
2. Gap: 2px of the background between the parts.
3. Trailing button: 44 wide with an 18px `chevron-down`; inner corners `radius-xs`, outer `radius-full`. While the menu is open it becomes a full circle and the chevron turns 180°.
4. Menu: a standard Menu anchored below the whole split button, start-aligned.
5. State layers and focus ring on each part separately.

## Variants and when to use
| Variant | Container | Label | Use for |
|---|---|---|---|
| Filled | `primary` | `on-primary` | The view's main action with variants: Merge, Publish. |
| Tonal | `secondary-container` | `on-secondary-container` | A frequent secondary action with variants: Run build, Export. |
| Outlined | none, 1px `outline` each part | `primary` | Beside a filled button, or in dense toolbars. |
| Elevated | `surface-container-low` + `elevation-1` | `primary` | Over images or patterned backgrounds only. |

Use a Button when there are no variants, a Menu button (icon or text button with a menu) when no single action leads, and a Segmented button when the choice is a persistent mode rather than an action.

## Specs
| Part | Small (density -1) | Default | Large |
|---|---|---|---|
| Height | `control-sm` 32 | `control-md` 40 | `control-xl` 56 |
| Leading padding | `space-4` 16 each side | `space-6` 24 start, `space-4` 16 end | `space-8` 32 start, `space-6` 24 end |
| Trailing width | 36 | 44 | 64 |
| Chevron | `icon-sm` 18 | `icon-sm` 18 | `icon-md` 24 |
| Inner corners | `radius-xs` 4 | `radius-xs` 4 | `radius-sm` 8 |
| Gap | 2 | 2 | 2 |
| Label | `label-large` | `label-large` | `body-large` 600 |
| Menu offset | `space-1` 4 below | 4 | 4 |
| Target | each part pads to `target-pointer` | pads to `target-touch` on touch | 56 |

## States
- Each part has its own hover (`state-hover`), focus (`state-focus` + ring), and pressed (`state-pressed`) layer; the other part does not react.
- Open: trailing part fully round, chevron rotated, holds `state-pressed` until the menu closes.
- Disabled: both parts on-surface 12%/38%. Disable the menu part alone when only the variants are unavailable.
- Loading: the leading label is replaced by a 18px circular progress, width kept; the menu part stays enabled.

## Behaviour
- Leading press runs the current default. Trailing press, Alt+Down or F4 (on Windows), or a long press on the leading part (touch), opens the menu.
- The menu lists all variants including the current default, marked with a check and `secondary-container`. Picking one runs it; if the button is "sticky", it also becomes the new default and the leading label changes.
- In the menu: Up/Down move, Home/End jump, Enter runs, Escape closes and returns focus to the trailing part, typeahead jumps by first letter.
- The parts are two Tab stops; Left/Right do not move between them.
- Menu opens with `duration-medium-1` and `ease-emphasized-decelerate`, scaling from the button's edge; it closes with `duration-short-4` and `ease-emphasized-accelerate`. The trailing part morphs to round with `ease-standard`, `duration-short-3`.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Density -1; the WinUI SplitButton idiom; Alt+Down opens the menu; access key on the leading label. |
| macOS | Density -1; in toolbars use the native pull-down style (the chevron attached to a bordered button); the menu is an NSMenu with a check on the default. |
| Linux | Density -1; GTK/Adwaita split button in header bars: the flat look (text variant) is allowed there. |
| Android | Default; long-press the leading part also opens the menu; the menu may open as a bottom sheet when it has more than five items. |
| iOS | Default; the trailing part opens a UIMenu; no ripple. |
| Web | Two `button` elements in a group; the trailing one `aria-haspopup="menu"`, `aria-expanded`. |

## Accessibility
- A group named by the action. Leading part: role button, name = label. Trailing part: role button with has-popup menu, expanded state, name = "<label> options" ("Merge options").
- The menu is role menu with menu item radio children when the default is sticky (checked = the default).
- Each part has a target of at least 32 (pointer) or 48 (touch). Both parts' contrast is the Button's.
- Announce the new default when it changes ("Merge button, Squash and merge").
- Reduced motion: the menu fades in 100ms; the trailing part changes shape without morphing.

## Content
The leading label is the verb and outcome of the default ("Squash and merge"). Menu items name every variant fully, in the same verb form ("Rebase and merge"), not fragments ("Rebase"). Sentence case, no ellipses unless the item opens a dialog.

## e.ui today
`control.split_button` sets two Filled pressables side by side, a hairline apart, each with `radius-md` on all four corners, a 12px triangle for the menu part, and `open` changing only the tree. To reach this design:
- Shape the pair as one pill: outer `radius-full`, inner `radius-xs`, 2px apart; make the trailing part round and flip the chevron while open (today an open menu cannot be seen on the button).
- Replace the triangle with `chevron-down` at `icon-sm`; size the trailing part 44 (36 small).
- Add Tonal, Outlined and Elevated variants and the small and large sizes.
- Name the menu part "<label> options" instead of the literal "More"; add Alt+Down / F4.
- Support a sticky default whose menu item is checked, and anchor `overlay.menu` to the whole button, not only `key + 1`.
