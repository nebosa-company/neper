# Button

A button starts an action with one press; five variants set its emphasis, from filled for a view's main action down to text for a quiet one.

## Anatomy
1. Container: fully rounded (`radius-full`), 40 tall.
2. Label: `label-large`, sentence case, one line.
3. Optional icon: 18px (`icon-sm`), leading (or trailing for "Next"-style actions), 8px from the label.
4. State layer: the label colour over the container at the state's opacity.
5. Focus ring: 3px `focus-ring`, 2px outside.

## Variants and when to use
| Variant | Container | Label | Use for |
|---|---|---|---|
| Filled | `primary` | `on-primary` | The one main action of a view: Save, Send, Create. At most one per view. |
| Tonal | `secondary-container` | `on-secondary-container` | An important action that should not compete with the filled one: Duplicate, Export. |
| Elevated | `surface-container-low` + `elevation-1` | `primary` | A button that must separate from a patterned or image background. Use rarely. |
| Outlined | none, 1px `outline` | `primary` | Secondary actions beside a filled one: Cancel, Back. |
| Text | none | `primary` | The quietest action: in dialogs, cards, snackbars and banners, or "Learn more". |
| Danger | `error` (filled) or `error` label (text, outlined) | `on-error` | Irreversible actions, after a confirmation step, never as the only way to cancel. |

For an icon alone use Icon button. For the screen's primary creation action use the FAB. For one of a small set of options use Segmented button.

## Specs
| | Small (density -1) | Default | Large |
|---|---|---|---|
| Height | `control-sm` 32 | `control-md` 40 | `control-xl` 56 |
| Side padding | `space-4` 16 | `space-6` 24 (`space-4` on the icon side) | `space-8` 32 |
| Label | `label-large` | `label-large` | `body-large` weight 600 |
| Minimum width | 48 | 48 | 48 |
| Target | pads to `target-pointer` | pads to `target-touch` on touch hosts | 56 |

Buttons in a row sit `space-2` apart; in a dialog's action row they align to the end.

## States
- Hover: state layer at `state-hover`; an elevated button also rises to `elevation-2`.
- Focus: `state-focus` layer plus the focus ring. The ring shows only after keyboard navigation, never after a press.
- Pressed: `state-pressed` layer; on touch hosts a ripple spreads from the touch point over `duration-medium-2` with `ease-standard`. With reduced motion there is no ripple; the pressed layer alone shows the press.
- Disabled: container `on-surface` at 12%, label at 38%, no shadow, not focusable. Prefer an enabled button that explains what is missing over a disabled one that can't.
- Loading: the label is kept and replaced by a 18px circular progress in the label colour; the width must not change.

## Behaviour
- Press on release inside the bounds; dragging out cancels.
- Enter and Space press a focused button. In a dialog, Enter presses the default button and Escape the cancel one.
- A button never changes its own label to show a result: show a snackbar instead.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Default density -1 in tool windows (32 tall); keyboard access keys underline on Alt; the default button in a dialog is the filled one. |
| macOS | Density -1; in dialogs the default button is last (rightmost) and Escape maps to Cancel; ⌘. also cancels. |
| Linux | Density -1 on GNOME and KDE; GNOME orders dialog buttons with the affirmative last, KDE first (follow the desktop). |
| Android | Default size; 48 targets; ripple on press. |
| iOS | Default size with 44pt minimum; no ripple (the state layer darkens instead); the affirmative action is last and bold in alerts. |
| Web | Default size; `:focus-visible` for the ring; a real `<button>` element. |

## Accessibility
- Role button, name = the label (or the icon's label), Press action. Disabled buttons report Disabled.
- Label contrast is 4.5:1 or better on its container in every theme (7:1 in high contrast).
- A toggle button reports Pressed (checked) state; use Icon button's selected variant or Segmented button instead of changing the label.

## Content
Start with a verb, name the outcome: "Save changes", "Delete project", not "OK" or "Yes". Two to three words. Sentence case. No trailing punctuation.

## e.ui today
`control.button` builds a Filled, Outlined or Plain look from `style.resolve`, 32 tall with `radius-md` 8 corners and 12px sides. To reach this design:
- Add the Tonal, Elevated and Danger variants, and map Plain to Text.
- Round to `radius-full`, 40 tall by default, 24px sides, `label-large` at 600.
- Draw state layers instead of mixing the fill toward `text` or `background`.
- Paint the focus ring: `pressable_states` drops `look.focus_ring`, so no focused button shows focus today.
- Add a leading icon slot and a loading state.
- Centre the label: a Region lays its content out at the start, so a stretched button's label sits top-left.
