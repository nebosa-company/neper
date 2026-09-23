# ToggleButton

A toggle button is a labelled button that stays on or off, for a mode that reads as an action: follow output, watch mode, word wrap.

## Anatomy
1. Container: 40 tall; `radius-full` when off, `radius-md` 12 when on (the shape change marks the state without colour).
2. Label: `label-large`, sentence case, one line.
3. Optional leading icon: `icon-sm` 18; switches to its filled form when on.
4. State layer and focus ring, as Button.

## Variants and when to use
| Variant | Off | On | Use for |
|---|---|---|---|
| Filled (default) | `surface-container-high` / `on-surface-variant` | `primary` / `on-primary` | The main mode of a view: Follow output, Live. |
| Tonal | `surface-container-high` / `on-surface-variant` | `secondary-container` / `on-secondary-container` | Secondary modes, several side by side. |
| Outlined | 1 px `outline` / `on-surface-variant` | `inverse-surface` / `inverse-on-surface`, no edge | Toolbars on `surface` where fills would be heavy: Pin, Wrap. |
| Connected group | inner corners `radius-xs`, outer `radius-full`, 2 px gaps | the on item becomes a full pill | Several independent toggles of one kind: Whitespace, Minimap, Line numbers. |

Use Switch for a setting that applies immediately and persists (in a settings list). Use Checkbox in a form that is submitted. Use Icon button (toggle) when an icon alone is clear. Use Segmented button when the options exclude each other.

## Specs
| | Small (density -1) | Default |
|---|---|---|
| Height | `control-sm` 32 | `control-md` 40 |
| Radius off / on | `radius-full` / `radius-sm` 8 | `radius-full` / `radius-md` 12 |
| Side padding | `space-4` 16 | `space-6` 24 (`space-4` on the icon side) |
| Label | `label-large` 14/20 600 | `label-large` |
| Icon | `icon-sm` 18, `space-2` 8 gap | same |
| Minimum width | 48 | 48 |
| Group gap | 2 px | 2 px |
| Group inner radius | `radius-xs` 4 | `radius-xs` 4 |
| Target | 32 | 48 on touch hosts |

## States
- Hover: `state-hover` layer in the label colour.
- Focus: `state-focus` layer and the focus ring 3 px `focus-ring`, 2 px outside (keyboard only).
- Pressed: `state-pressed` layer; ripple on touch.
- On: the fill and the squared corners; the corner radius and colour change together over `duration-short-3` with `ease-standard`.
- Disabled: container `on-surface` 12%, label 38%, keeping the on/off shape so the state still reads.
- The label does not change between off and on, so the name is stable; the one exception is a verb/adjective pair that readers would expect ("Pin" / "Pinned") with the accessible name kept as "Pin".

## Behaviour
- A press flips the state and applies it immediately; there is no Apply.
- Enter and Space toggle a focused toggle button.
- In a connected group each button is its own Tab stop (they are independent); arrow keys also move between them.
- If the mode cannot turn on (no output to follow), keep the button enabled and show why in a snackbar or tooltip rather than silently refusing.
- Keyboard shortcuts toggle it too, and the button shows the change.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Small in command bars; WinUI ToggleButton semantics; the shortcut in the tooltip. |
| macOS | Small; in toolbars prefer the icon-only toggle; push-on-push-off NSButton semantics; ⌘ shortcut in the tooltip. |
| Linux | Small; GNOME header bar toggles are flat until on: use outlined. |
| Android | Default 40 with 48 targets; ripple. |
| iOS | Default with 44 pt targets; prefer a Switch in lists and menus (a toggle in UIMenu shows a check); no ripple. |
| Web | `<button aria-pressed>`; never change `aria-label` on toggle. |

## Accessibility
- Role Button with the Pressed (toggle) state, named by the label; Press toggles.
- State changes are reported by the Pressed state; no extra announcement.
- State is not colour alone: the corner radius changes and icons fill.
- Contrast: label 4.5:1 on each container; the off container is decorative, so the label and shape must carry the control.
- Target: 48 on touch hosts, 32 with a fine pointer.
- Reduced motion: shape and colour swap without animating.

## Content
- Name the mode, not the command: "Follow output", "Word wrap", not "Turn on word wrap".
- Sentence case, 1-3 words, no trailing punctuation.

## e.ui today
`control.toggle_button` is the Button pressable with a caller-kept `selected` flag: selected mixes the variant's fill 50% toward `selection`, and the tree gets Selected. To reach this design:
- Give off and on their own containers (off `surface-container-high`, on `primary`, or the tonal and outlined pairs); a 50% `selection` mix of `primary` is barely visible.
- Change the corner radius from `radius-full` to `radius-md` when on, and fill the leading icon, so the state reads without colour.
- Report Pressed (a toggle), not Selected.
- Draw the focus ring (`pressable_states` ignores `focus_ring`) and state layers.
- Add the connected group layout.
