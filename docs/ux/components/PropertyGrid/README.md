# PropertyGrid

A property grid is an inspector: one object's properties as name and value rows in collapsible groups, each value edited in place with the right editor, for tools that tune many settings of a selected thing.

## Anatomy
1. Header: the object's kind in `title-medium` and its name in `body-medium` `on-surface-variant` ("Button save"), or the count when several are selected ("3 buttons").
2. Filter field: a 32 outlined search field, "Filter properties".
3. Group header: a twisty, the group name in `title-small`, and when collapsed a count in `label-small` ("6 properties").
4. Property row: the name (`body-medium` `on-surface-variant`) in a fixed-width column, the editor in the value column, a reset slot at the end.
5. Editors: dense fields, selects, switches, checkboxes, steppers, colour swatches with their token or value; read-only values as plain `on-surface-variant` text.
6. Modified marker: the name in `on-surface` weight 600 plus a Reset icon button, when the value differs from the default.
7. Validation message: under the editor, `body-small` in `error` with the `error` icon.

## Variants and when to use
| Variant | Use for |
|---|---|
| Grouped | Objects with more than about eight properties: groups by purpose (Content, Style, Behaviour, Accessibility). |
| Flat | Up to about eight properties: no group headers. |
| Multi-object | Several objects selected: shared properties only; differing values show "Mixed" and a checkbox shows mixed. |

Use a Form for a task with a submit (sign-up, create project). Use Key-value editor when the person names the entries. Use Data grid to edit the same properties of many records side by side. On touch hosts a property grid becomes a grouped List of settings rows, each opening its own picker.

## Specs
| Part | Pointer (density -2, default) | Pointer (density -1) | Touch |
|---|---|---|---|
| Row height | `control-md` 40 min | 48 | grouped List rows, 56 |
| Name column | 40 to 45% of the width, min 96, ellipsised; the divider between columns is draggable | same | a row's headline |
| Row padding | start `space-2` + twisty 24 + `space-1` (names align under group names), end `space-2` | same | List |
| Editor | 32 tall dense field: `surface-container-highest`, `radius-xs` top, 1px `on-surface-variant` indicator (2px `primary` focused, 2px `error` invalid) | 40 | a picker opened from the row |
| Switch | 52 × 32 scaled to 75% (39 × 24) | full size | full size |
| Reset slot | 32 wide; `refresh` icon button `control-sm` 32, `icon-sm` | same | in the picker |
| Group header | `control-sm` 32, `title-small` `on-surface`, twisty 24, `space-2` above | 40 | the grouped list title, `label-medium` |
| Group count | `label-small`, `on-surface-variant`, end-aligned, only while collapsed | same | none |
| Colour swatch | 20, `radius-xs`, 1px `outline-variant` edge, with the value in `code` | same | same |
| Validation | `body-small` `error` with 16 `error` icon, under the editor, row grows | same | field supporting text |
| Selected row (property picked for docs or binding) | `secondary-container` | same | none |

## States
- Row hover: `state-hover` layer over the row; the Reset button stays visible only on modified rows.
- Editor focus: the editor's own focus look (2px `primary` indicator); rows themselves are not focusable except in keyboard row mode.
- Modified: bold name plus Reset; "Modified" in the row's description.
- Invalid: the editor's `error` indicator and icon, and the message under it; the old value keeps applying until a valid one is committed.
- Mixed (multi-object): "Mixed" placeholder in `on-surface-variant`; typing sets all selected objects.
- Read-only: value as text in `on-surface-variant`, not focusable in Tab order but reachable by arrows; description "Read only" and why ("Set by the theme").
- Collapsed group: header only, with its count; its modified count too ("6 properties, 1 modified").
- Filtered: groups with no match hide; matches in names are bold; "No properties match" with Clear.

## Behaviour
- Editors commit on Enter, on blur, and on each toggle; Escape reverts a field being edited. Numbers accept arithmetic ("16*2") and units the property allows ("2rem" where supported).
- Keyboard: Tab moves between editors, skipping collapsed groups; Up and Down move between rows (row mode) from a group header or name; Left collapses and Right expands a group header; Enter or Space toggles a header; Ctrl+Backspace (⌘⌫) resets the focused property.
- Dragging a numeric property's name left and right scrubs its value (desktop tools), with Shift for 10x steps.
- The name column's divider can be dragged; its width persists.
- Collapsed groups and the filter persist per object kind.
- The grid changes with the selection immediately; an editor that has focus commits first.
- Motion: groups expand and collapse over `duration-medium-2` (emphasized easings); Reset cross-fades the value in `duration-short-2`. Reduced motion: instant.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Density -2; Visual Studio-style categorised grid with a sort toggle (Categorised / Alphabetical); F4 focuses the properties pane. |
| macOS | Density -2 inspector in a trailing sidebar (as Xcode or Keynote); groups as disclosure sections; ⌥⌘1..n switch inspector tabs when there are several. |
| Linux | Density -2; libadwaita apps use preference rows (density -1) in a sidebar. |
| Android | A grouped settings List; values open dialogs, menus or pickers; Reset in each picker. |
| iOS | A grouped List (inset grouped) in a sheet or popover; values push pickers; switches inline. |
| Web | Density -2 with a fine pointer; `role="treegrid"` (groups as rows with `aria-expanded`) or a set of `<fieldset>`s with legends; editors are real inputs with `<label>`s. |

## Accessibility
- Role treegrid named "Properties of button save" (or grouped fieldsets); group headers are rows with Expanded; property rows have the name as row header and the editor as the cell.
- Each editor's accessible name is the property name ("Minimum width"), with its description: "Modified", "Read only, set by the theme", or the validation message.
- Reset buttons are named "Reset variant".
- Mixed values report as mixed (checkbox) or "Mixed" as the field's value text.
- Contrast: names `on-surface-variant` 4.5:1; editors' indicators 3:1; modified is shown by weight and the Reset button, never colour alone.
- Target: 32 editors (the pointer minimum); touch hosts use 56 list rows.
- Reduced motion as in Behaviour.

## Content
- Property names: sentence case nouns, the same words as the API's concept, not its identifier: "Minimum width", not "minWidth".
- Group names: "Content", "Style", "Behaviour", "Accessibility".
- Messages say what is valid: "Enter a number of pixels, 0 or more".
- Placeholders suggest an action for empty optional values: "Add a tooltip".

## e.ui today
`collection.property_grid` lists a `PropertySource`'s properties (up to 256) with the name in a `name_width` column and the caller's editor beside it, runs of one group under a `control.disclosure` heading in `primary`. To reach this design:
- Key groups by their name, not their position: today a group's key is its first index plus one, so inserting a property changes which group `collapsed` shuts, and a one-property group's content key collides with the next heading.
- Fix the row width: each row is `name_width + space-xs + (width - name_width)` and overflows by `space-xs` (28px when grouped); align grouped and ungrouped editors in one value column.
- Restyle headings as `title-small` `on-surface` with a twisty and the collapsed count, instead of a `primary` pressable.
- Add the filter, the modified marker with Reset, validation messages, read-only values and the Mixed state for multi-object selection.
- Add row keyboard mode and name each editor by its property.
