# Picker

A picker is a field-shaped button that shows the chosen option and opens the full list of options to choose one, as a docked menu on pointer hosts and a bottom sheet on touch.

## Anatomy
1. Anchor: a read-only field (outlined dense on desktop, filled on touch) with a floated label, the chosen option, and a trailing `chevron-down` that turns while open.
2. Docked menu (pointer): a Menu surface 4 below the anchor, as wide as it, rows 36 with the chosen one in `secondary-container` and a trailing `check`.
3. Bottom sheet (touch): a modal sheet (`surface-container-low`, `radius-xl` top corners) over a scrim, with a drag handle, a `title-large` title, and radio rows 56 tall.
4. Supporting text: hint or error under the anchor.

## Variants and when to use
| Presentation | Where | Use for |
|---|---|---|
| Docked menu | Pointer hosts; touch lists up to 5 short options on medium windows | The default on Windows, macOS, Linux, desktop Web. |
| Bottom sheet | Compact touch windows; more than 5 options or long labels | Android, iOS, touch Web. |
| Full-screen list with search | More than 15 options on compact | Country, time zone, language. |

Use a Combo box when typing a custom value must work, a Segmented button for 2 to 5 options that fit and should be visible, Radio buttons in forms with 2 to 5 options, and a Multi-select list for several choices.

## Specs
| Part | Docked (density -1) | Sheet (touch) |
|---|---|---|
| Anchor | outlined, 40 tall, `radius-xs`; value `body-medium`; chevron `icon-md` `on-surface-variant` | filled, 56 tall; value `body-large` |
| Surface | `surface-container`, `radius-sm`, `elevation-2`, `space-2` 8 vertical padding | `surface-container-low`, `radius-xl` 28 top, `elevation-1`; `scrim` at `scrim-opacity` behind |
| Width | the anchor's (min 112, max 280 beyond it) | full window width (max 640, centred) |
| Row | 36, `space-3` 12 sides, `body-medium` | `nu-li` 56, radio in a 40 cell, `body-large` |
| Chosen row | `secondary-container`, trailing `check` | radio on (`primary`) |
| Disabled option | `on-surface` 38%, with the reason in the label | same |
| Title | none | `title-large`, `space-6` 24 sides |
| Handle | none | 32x4, `on-surface-variant` 40%, `space-4` from the top |
| Max visible | 8 rows then scroll | 60% of the window height then scroll; drag up to expand |

## States
- Anchor rest, hover (outline `on-surface`), focus (2px `primary` outline, `primary` label), pressed, invalid (`error`, with a message that says what to choose), disabled.
- Open: chevron rotated; anchor keeps its focus look.
- Nothing chosen: placeholder "Choose a target" in `on-surface-variant`; not an error until submit.
- Menu row hover `state-hover`, keyboard active `state-focus`.

## Behaviour
- Press, Enter, Space, Alt+Down or F4 opens with the chosen row active and scrolled into view. Up/Down on a closed anchor change the choice directly on Windows and Linux (not macOS).
- In the list: Up/Down move, Home/End jump, typeahead jumps to the next option starting with the typed letters, Enter or Space picks and closes, Escape closes without change, Tab picks the active row and moves on (docked).
- Picking closes and returns focus to the anchor; the change commits immediately.
- Docked menu: opens with `duration-medium-1`, `ease-emphasized-decelerate`, scaling down from the anchor; closes `duration-short-2`.
- Sheet: slides up over `duration-medium-4` with `ease-emphasized-decelerate`; picking a row closes it after 150ms (so the radio change is seen); drag down, tap the scrim or system back dismisses with `ease-emphasized-accelerate`.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Docked below the anchor (WinUI ComboBox, non-editable); Up/Down change the choice while closed. |
| macOS | NSPopUpButton: the menu opens over the anchor with the chosen item aligned on the anchor's text, check on the left; no Up/Down while closed. |
| Linux | Docked below (GtkDropDown); GNOME shows the check on the end. |
| Android | Exposed dropdown menu for up to 5 short options; bottom sheet otherwise. |
| iOS | A UIMenu from the anchor for short lists; a pushed list or sheet with checkmarks for long ones; no radios (a trailing `check` marks the choice). |
| Web | The anchor is a `button` with `aria-haspopup="listbox"`; pointer layouts dock, touch layouts use the sheet. A native `<select>` is allowed on touch Web. |

## Accessibility
- Anchor: role combo box (or button with has-popup listbox), name = label, value = the chosen option, expanded state.
- Docked list: listbox, options with selected state. Sheet: modal dialog named by the title, containing a radio group; focus moves to the chosen radio on open and returns to the anchor on close.
- Announce the choice after picking ("Build target, Linux arm64").
- Rows 48 on touch, 36 with a pointer (above `target-pointer`).
- Reduced motion: menu and sheet fade in 100ms.

## Content
The label names the setting ("Build target"). Options are short nouns, parallel in form, sentence case ("Linux x86-64"). A disabled option says why in its label ("Web (needs wasm tools)"). The placeholder is a verb phrase ("Choose a target").

## e.ui today
`control.picker` is an Outlined button showing the option; `.Popup` is `select` and `.Sheet` a modal sheet centred in the window (`surface`, border, `radius-md`) with Filled or Plain full-width buttons under a title and no scrim; the sheet's rows are ListItems with no List. To reach this design:
- Draw the anchor as a read-only field (floated label, value, rotating chevron), dense outlined on pointer hosts and filled on touch.
- Make `.Sheet` a bottom sheet with a handle, title, scrim and radio rows, and wrap the rows in a radio group (today list items have no list).
- Style `.Popup` as the docked menu with a checked chosen row, max rows and scrolling.
- Choose the presentation from the host and window size by default (caller may override).
- Add typeahead, Home/End, Alt+Down/F4, closed-state Up/Down where the host does it, and the placeholder and invalid states.
