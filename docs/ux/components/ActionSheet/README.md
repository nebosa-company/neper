# ActionSheet

An action sheet is a modal set of two to six actions about one thing (a file, a build, a message) that rises from the bottom on touch hosts; on pointer hosts the same actions appear as a menu at the anchor.

## Anatomy
1. Scrim: `scrim` at 32%.
2. Header (optional): what the actions apply to, in `body-small` `on-surface-variant` with the name in weight 600 ("build-4128.zip · 24 MB").
3. Actions: full-width rows.
4. Destructive action (optional): in `error`, last, after a separator (Android) or last in the group (iOS).
5. Cancel (iOS): a separate group below the actions, weight 600. Android has no Cancel row: dragging down, the scrim and Back cancel.
6. Container: iOS grouped cards (`surface-container-high`, `radius-md`, 8 from the edges); Android a modal bottom sheet (`surface-container-low`, `radius-xl` top corners, drag handle).

## Variants and when to use
| Variant | Host | Look |
|---|---|---|
| Grouped | iOS, iPadOS compact | Centred labels in `primary`, 56 rows, hairline separators, Cancel in its own group. |
| Sheet of rows | Android, touch Web | A modal bottom sheet with 48 list rows, leading 24 icons, start-aligned `body-large` labels. |
| Menu | Windows, macOS, Linux, desktop Web, iPad regular | A pointer Menu at the anchor with the same items; no Cancel row. |

Use Menu when there is a visible anchor on pointer hosts, Dialog (with icon) to confirm one destructive action, Sheet for anything with controls, and Share on iOS and Android where the host has a share sheet (route "Share" to it).

## Specs
| Part | Grouped (iOS) | Sheet of rows (Android) |
|---|---|---|
| Container | `surface-container-high`, `radius-md` 12, `elevation-3`; 8 from the window edges and between groups | `surface-container-low`, `radius-xl` 28 top corners, `elevation-3` |
| Header | `body-small` in `on-surface-variant`, centred, `space-3` 12 by `space-4` 16 | `body-small` in `on-surface-variant`, start, `space-1` 4 top, `space-2` 8 bottom, `space-4` 16 sides |
| Row | 56 tall, label centred | 48 tall, `space-4` 16 sides, icon 24 then label at `space-4` 16 |
| Label | `body-large` in `primary`; Cancel weight 600 | `body-large` in `on-surface`; icon `on-surface-variant` |
| Destructive | `body-large` in `error` | label and icon in `error`, after a `divider` with 8 around |
| Separators | `divider` in `outline-variant` between rows | none between rows |
| Drag handle | none | 32 by 4, as Sheet |
| Max actions | 6 (then use a list screen) | 6 |

## States
- Row pressed: `on-surface` layer at `state-pressed` (iOS darkens, no ripple; Android ripples).
- Row focus (keyboard, iPad and Android with a keyboard): `state-focus` plus the focus ring inset 3px.
- Disabled action: label at `on-surface` 38%; prefer omitting an action that can never apply here.
- Menu presentation takes Menu's states.

## Behaviour
- A press on an action runs it and closes the sheet; the destructive action may then need its own confirmation only if it cannot be undone (prefer undo via Snackbar).
- Cancel (iOS), the scrim, system back (Android), Escape and dragging down (Android) close without acting.
- Keyboard: focus goes to the first action; Up and Down move, Enter runs, Escape cancels; focus returns to the anchor.
- On iPad regular width and on pointer hosts, present as a menu or popover at the anchor instead; never slide a sheet from the bottom of a large window.
- Motion: enter over `duration-medium-4` with `ease-emphasized-decelerate` sliding up with the scrim fading in; leave over `duration-short-4` with `ease-emphasized-accelerate`. Reduced motion: fade.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Menu at the anchor (pointer density); from a touch-only interaction, a context menu at the touch point. |
| macOS | Native menu (`NSMenu`) at the anchor; no action sheets. |
| Linux | Menu at the anchor; GNOME a popover menu. |
| Android | Modal bottom sheet of rows as specified; predictive back; share goes to the system share sheet. |
| iOS | Native `UIAlertController(.actionSheet)` on iPhone, which becomes a popover from the anchor on iPad; the destructive action uses the destructive style; Cancel is the cancel style. |
| Web | Coarse pointer and compact: the sheet of rows in a `<dialog>`; fine pointer: a menu. |

## Accessibility
- Role Dialog with the Modal state, labelled by the header (or by the anchor's label); each action a Button. In the menu presentation, Menu and MenuItem.
- The destructive action says so in its label ("Delete build"), not by colour alone.
- Screen readers announce "build-4128.zip, 4 actions"; on iOS the Cancel action is the escape (two-finger scrub) action.
- Contrast: `primary` and `error` labels 4.5:1 on `surface-container-high`; `on-surface` on `surface-container-low`.
- Targets: 56 and 48 rows, full width.
- Reduced motion: fade.

## Content
- Actions are verbs with an object where it helps: "Save to Files", "Copy link", "Delete build". Sentence case, no period, one line.
- Header: the object's name and one fact ("24 MB, created today"); no question, no instructions.
- Cancel is always "Cancel".

## e.ui today
`overlay.action_sheet` builds a square `surface` bottom panel (from `overlay.bottom_sheet`) with a title row and a Plain `x` button, then every `DialogButton` as a full-width Outlined button with its label at the start, then an Outlined "Cancel". To reach this design:
- Drop the `x` close button: Cancel, the scrim, Back and Escape already close it, and today both do the same thing.
- Localise Cancel instead of the literal English string, and wire a `Cancel`-kind action to Escape (today only `dismiss` is).
- Replace the Outlined buttons with rows: grouped and centred on iOS, a sheet of icon rows on Android; `Destructive` becomes an `error` label, not an `error` fill.
- Add an optional header line, the 32% scrim and rounded containers; stop computing the height from the button count and let the content size it.
- Present as a menu at the anchor on pointer hosts and iPad regular widths, and use the native action sheet on iOS.
