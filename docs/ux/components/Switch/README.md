# Switch

A switch turns a single setting on or off, and the change takes effect immediately.

## Anatomy
1. Track: 52 by 32, fully rounded. Off, it is `surface-container-highest` with a 2px `outline` edge. On, it is `primary` with no edge.
2. Thumb: a 16px `outline` disc at the start when off, and a 24px `on-primary` disc at the end when on. Pressed, it grows to 28.
3. Optional thumb icon: 16px, `close` when off (the thumb becomes 24) and `check` when on. It makes the state readable without colour.
4. State layer: a 40px circle centred on the thumb.
5. Label: outside the switch, leading it in a row (settings) or following it (inline). It is never inside the track.

## Variants and when to use
| Variant | Use for |
|---|---|
| Plain | Dense settings where the row label already makes the state obvious. |
| With icons | The default in settings lists and anywhere the state must read without colour, such as high contrast themes or small screens. |
| Settings row | A list row (icon, headline, supporting text) with the switch trailing. The whole row toggles. |
| Inline | A switch before a short label in a toolbar or a card: "Live preview". |

Use a Checkbox when the choice is applied by a Submit button, or when there are several related options in a form. Use a Toggle button or a selected Icon button for a view mode in a toolbar (bold, word wrap). Use Radio buttons or a Segmented button when both states need a name ("Light" and "Dark"). A switch never asks for confirmation. If turning it on or off needs one, use a button.

## Specs
| Part | Value |
|---|---|
| Track | 52 x 32, `radius-full`; off edge 2px `outline` |
| Thumb | off 16 (24 with an icon), on 24, pressed 28, centred vertically; 8 inset off, 4 inset on |
| Thumb icon | 16, stroke 2.25; off `surface-container-highest` on an `outline` thumb, on `on-primary-container` on an `on-primary` thumb |
| State layer | 40 circle on the thumb: `on-surface` off, `primary` on |
| Target | 48 tall on touch (the track plus 8 above and below), 32 with a pointer, and the whole row in a settings row |
| Settings row | 72 (two lines) or 56 (one line), 16 sides, leading icon 24, switch 16 from the end |
| Label gap (inline) | `space-3` 12 |
| Dense (density -2) | 40 x 24 track, thumbs 12, 18 and 20, for tool windows only |

| Part | Colour role |
|---|---|
| Track off / on | `surface-container-highest` with an `outline` edge / `primary` |
| Thumb off / on | `outline` (pressed and hover `on-surface-variant`) / `on-primary` (hover `primary-container`) |
| Disabled track off / on | `surface-container-highest` 12% with an `on-surface` 12% edge / `on-surface` 12% |
| Disabled thumb off / on | `on-surface` 38% / `surface` |
| Row text | headline `on-surface`, supporting `on-surface-variant`; disabled row at 38%, the reason kept at `on-surface-variant` |

## States
- Off and on, each with hover (`state-hover` circle), focus (`state-focus` circle plus the 3px ring 2px outside the track), pressed (`state-pressed` circle and a 28 thumb), and disabled.
- In a settings row the row takes the hover and pressed layers and the inset focus ring. The switch shows only its thumb state.
- Pending: when the setting needs a round trip, the switch moves at once and a 16px ring replaces the thumb icon until the result arrives. On failure it moves back and a snackbar says why.

## Behaviour
- A press toggles on release. A drag moves the thumb, and releasing past the middle sets the state.
- In a settings row, a press anywhere in the row toggles.
- Keyboard: Space toggles, and Enter toggles too (switches are not form submit fields). Arrow keys do nothing.
- Motion: the thumb slides and resizes over `duration-short-3` with `ease-standard`, and the track colour cross-fades at the same time. The icon cross-fades. With reduced motion the thumb jumps and the colours cross-fade.
- The change applies at once. Never pair a switch with Save.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Fluent ToggleSwitch placement: label above or leading, "On" or "Off" text after the switch optional. The same 52 x 32 track (Fluent's 40 x 20 at dense). Space toggles. |
| macOS | Use the dense 40 x 24 switch, trailing in preference rows. Checkboxes remain the macOS norm in dialogs, so switches are for settings panes only. No thumb icons (macOS draws none). |
| Linux | GTK switch trailing in Adwaita action rows. KDE prefers checkboxes in settings: use checkboxes under Plasma. |
| Android | Material 3 switch as specified, with icons. The whole list row toggles and a ripple runs on the row. |
| iOS | 51 x 31 native proportions, trailing in grouped rows. `success` (green) on is optional per app, with `primary` as the default. No icons. The row does not highlight on tap. |
| Web | `role="switch"` on a `<button>` with `aria-checked`, or `<input type="checkbox" role="switch">`. |

## Accessibility
- Role switch, name = the row headline or inline label, checked on or off, and a Toggle action. The supporting text is the description.
- A disabled switch keeps its state readable and its reason (the supporting text) announced.
- The thumb icons are decorative. The state comes from the role.
- Contrast: the off track edge and thumb are 3:1 against the surface. The on thumb is 3:1 against `primary`.
- Target: 48 on touch. In rows the whole row is the target.
- Reduced motion: no slide.
- Screen readers announce "Build on save, switch, on". After toggling they announce only the new state.

## Content
Label the setting, not the action: "Build on save", not "Turn on build on save". Positive phrasing so that on means yes. Supporting text explains the effect in one line: "Rebuilds the changed modules in the background". No "On" or "Off" in the label.

## e.ui today
`control.switch_control` draws a track `control-height / 2` tall and 1.75 times as wide, with a knob 4px smaller inset 2px. On is the Filled look (`primary` track, `on-primary` knob, at the end). Off is the Outlined look (`surface` track, `border` edge, `primary` knob). The label sits beside it in a `hit-target` box, with role Switch and checked when on. To reach this design:
- Size it 52 x 32, with a 16px off thumb in `outline`, a 24 on thumb, and a 28 pressed thumb, on a `surface-container-highest` off track with a 2px `outline` edge.
- Add the optional thumb icons (`close` and `check`).
- Add hover, focus (ring) and pressed looks and the 40px state circle. Today `control_state` feeds only the colours and focus is invisible.
- Animate the thumb over `duration-short-3`, and support dragging.
- Add a settings-row form (icon, headline, supporting text, trailing switch, the whole row as the target) and allow the label to lead.
- Replace the opacity-based disabled look with the specified 12% and 38% colours.
- Add a pending state for switches that wait on a round trip.
