# GroupBox

A group box gathers related controls under a visible title, so a settings page or form reads as a few named sections instead of one long list.

## Anatomy
1. Title: `title-small`, `on-surface`, above the box.
2. Optional description: `body-small`, `on-surface-variant`, under the title.
3. Box: outlined (`outline-variant`) or filled (`surface-container-low`), `radius-md`, clipping its rows.
4. Rows: one control each, separated by 1 px `outline-variant` dividers inset 0.
5. Optional group message: `body-small` with an icon under the box, for group-level validation.
6. Optional disclosure: a chevron at the title row's end when the group collapses.

## Variants and when to use
| Variant | Box | Use for |
|---|---|---|
| Outlined | `surface` + 1 px `outline-variant` | Settings and forms on pointer hosts. The default on Windows, Linux and Web. |
| Filled | `surface-container-low`, no edge | Grouped settings on touch hosts and macOS (inset grouped lists). |
| Plain | no box, title only | Short forms where fields already have their own outlines (text fields, selects): the title and spacing do the grouping. |
| Collapsible | either box, with a chevron | Advanced or rarely changed settings. Collapsed shows a one-line summary. |

For a single choice among options use Radio group (it is a group box with radio semantics). For a raised item use Card. For a docked region use a Pane. Never nest group boxes: use a subheader inside the box instead.

## Specs
| Part | Value |
|---|---|
| Title | `title-small` 14/20 600, `on-surface`, `space-1` 4 inset from the box edge |
| Description | `body-small` 12/16, `on-surface-variant`, 2 px below the title, max 2 lines |
| Title to box | `space-2` 8 |
| Box | `radius-md` 12; outlined 1 px `outline-variant` on `surface`; filled `surface-container-low` |
| Row | min height `control-lg` 48 (touch `control-xl` 56), padding `space-1` by `space-4`, `space-4` gap label to control |
| Row text | `body-medium` 14/20 (touch `body-large`), supporting `body-small` `on-surface-variant` |
| Row divider | 1 px `outline-variant`, full width |
| Control position | trailing, vertically centred (switches, values, chevrons); leading for checkboxes and radios |
| Group message | `body-small` `error` with a 16 `error` icon, `space-1` gap, `space-2` below the box |
| Between groups | `space-6` 24 (`space-8` 32 on expanded windows) |
| Width | fills the form column, max 640 |

## States
- Rest; the rows carry their own control states.
- Invalid (group-level): the box edge becomes 2 px `error` and the message shows below with the `error` icon. Field-level errors stay on the field.
- Disabled: title and rows at 38% `on-surface`, box edge `on-surface` 12%; the description stays at full contrast and says why.
- Collapsible hover and pressed: state layer over the title row; focus: ring 3 px inset (`focus-ring`) on the title row because it is edge-to-edge in the box.
- Expanding: the box height animates over `duration-medium-2` with `ease-emphasized-decelerate`, collapsing with `ease-emphasized-accelerate`; the chevron turns 180 degrees over `duration-short-3` with `ease-standard`.

## Behaviour
- The group is not a Tab stop; Tab moves through its controls in order. A collapsible group's title row is one stop (Enter or Space toggles, Right expands, Left collapses).
- A row whose whole area toggles its control (a switch row) takes the press anywhere in the row, with the row's state layer.
- Group validation runs when the person leaves the group or submits, never while they are still choosing.
- Rows never scroll inside the box; the page scrolls.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Outlined with WinUI settings-card rows (48 tall, `radius-md`); no classic etched frame with the title in the border. |
| macOS | Filled, like System Settings' grouped form (`surface-container-low`, `radius-md`), title above in `title-small`; rows 40 tall at density -1. |
| Linux | GNOME: Adwaita preferences group (boxed list, outlined look, title above). KDE: plain groups with a title and no box (Kirigami FormLayout). |
| Android | Filled; rows 56 with `body-large`; the title in `primary` `title-small` as a preference category. |
| iOS | Filled inset-grouped list; title as the section header in `on-surface-variant`, description as the section footer below the box. |
| Web | `<fieldset>` with a visually styled `<legend>` for control groups, or a `<section>` with a heading for settings. |

## Accessibility
- Role Group named by the title, described by the description.
- Group-level errors are in the group's description and announced when they appear (assertive once, after submit).
- A collapsible group's title row is a Button with Expanded / Collapsed and controls the box.
- Disabled groups report Disabled on each control, and the description explains why.
- Contrast: title and row text 4.5:1; the outlined edge is decorative, so the title and spacing must still group the rows without it.
- Reduced motion: expand and collapse without height animation.

## Content
- Titles are short nouns, sentence case, no colon: "Build", "Notifications", "Advanced".
- Descriptions say the scope or the reason: "Applies to every branch in this project".
- Group errors say the fix: "Choose at least one target".
- Collapsed summaries count and flag changes: "4 settings, 1 changed".

## e.ui today
`control.group_box` stacks a Label-role label over a `surface` box with a `border-regular` `border` edge, `radius-sm`, `space-md` padding and children in a column with no gap, in a Group node named `label`. To reach this design:
- Use `title-small` for the title and add an optional description.
- Round the box to `radius-md`, use `outline-variant` at 1 px, and add the filled and plain variants.
- Lay children out as rows with dividers and row padding instead of a padded column the caller spaces by hand.
- Add the group-level invalid state and message, the disabled state, and the collapsible form with Expanded semantics.
