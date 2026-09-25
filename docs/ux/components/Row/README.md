# Row

A row is one item of a list: a headline with up to two lines of support, framed by an optional leading visual and trailing meta or control, that the person reads, opens or selects.

## Anatomy
1. Container: full width, square, no fill at rest; 56 tall for one line, 72 for two, 88 for three (touch).
2. Leading slot (optional): a 24 icon (`icon-md`), a 40 avatar, a 56 thumbnail (`radius-sm`), or a checkbox or radio in its 40 state-layer circle.
3. Overline (optional, three-line only): `label-small`, above the headline.
4. Headline: `body-large`, one line, ellipsised at the end.
5. Supporting text (optional): `body-medium`, one line (two-line row) or two lines (three-line row).
6. Trailing slot (optional): meta text in `label-small`, a 24 icon, a tag, a switch, an icon button, or a chevron for navigation.
7. State layer: `on-surface` over the whole row.
8. Focus ring: 3px `focus-ring`, inset 3px (the row is edge to edge).

## Variants and when to use
| Variant | Height (touch / pointer / dense) | Use for |
|---|---|---|
| One line | 56 / 48 / 32 | Files, settings, menu-like pick lists: a name is enough. |
| Two line | 72 / 64 / 48 | People, builds, messages: a name plus one fact (status, email, time). |
| Three line | 88 / 80 / not offered | A title with a sentence of preview (review threads, notifications). Never clamp more than two supporting lines. |
| Navigation row | as one or two line + chevron | Opens a detail page or a sub-list; the trailing value shows the current setting ("System"). |
| Control row | as one or two line + checkbox, radio or switch | Settings. The whole row toggles the control. |

A row with columns under headers is a Table row. A row with hidden per-row actions on touch is Swipe actions. A row the person drags into order lives in a Reorderable list. A single boolean setting outside a list is a Switch row.

## Specs
| Part | Touch | Pointer (density -1) | Dense (density -2) |
|---|---|---|---|
| Height, one line | `control-xl` 56 | `control-lg` 48 | `control-sm` 32 |
| Height, two / three line | 72 / 88 | 64 / 80 | 48 / none |
| Padding | `space-4` 16 start, `space-6` 24 end, `space-2` 8 top and bottom | same | `space-4` start, `space-3` end, 0 top and bottom |
| Leading to text gap | `space-4` 16 | `space-4` 16 | `space-3` 12 |
| Leading icon | `icon-md` 24, `on-surface-variant` | `icon-md` 24 | `icon-sm` 18 |
| Avatar / thumbnail | 40 circle / 56 `radius-sm` | 40 / 56 | 24 (`nu-avatar sm`) / none |
| Checkbox, radio | in a 40 circle, the row's start padding drops to `space-1` 4 so the mark aligns with icons | same | 32 circle |
| Overline | `label-small`, `on-surface-variant` | same | none |
| Headline | `body-large`, `on-surface` | `body-large` (`body-medium` on macOS) | `body-medium` |
| Supporting | `body-medium`, `on-surface-variant` | same | `body-small` |
| Trailing meta | `label-small`, `on-surface-variant`; trailing icons `icon-md` | same | `label-small`, icons `icon-sm` |
| Selected | `secondary-container` fill, all content `on-secondary-container` | same | same |
| Divider (from List) | `divider` 1px `outline-variant`, full width or inset 72 to the text | same | same |

Top alignment: in a three-line row the leading and trailing slots align to the top of the text (4 below the row's top padding); in one and two line rows they centre.

## States
- Hover: `on-surface` layer at `state-hover` over the whole row (pointer hosts only).
- Focus: `state-focus` layer plus the inset 3px ring. The ring follows keyboard focus only.
- Pressed: `state-pressed` layer; on Android and touch Web a ripple spreads from the touch point over `duration-medium-2` with `ease-standard`.
- Selected: `secondary-container` fill with `on-secondary-container` content; in a single-select list a trailing check (`check`, `icon-md`) as well, so selection never rests on colour alone.
- Dragged (in a Reorderable list): `surface-container-high`, `elevation-4`, `state-dragged` layer.
- Disabled: every part at `on-surface` 38%, avatar and controls at 38% opacity, no state layer, not focusable. Say why in the supporting text ("Requires a signed-in account").
- Activated (the row whose detail is open in a list-detail layout): as Selected, without the check.

## Behaviour
- A row has one primary action. Tap or click anywhere outside a trailing control runs it: open, navigate, or toggle the row's control.
- A trailing icon button or switch is a second target with its own state layer; it never also triggers the row.
- Control rows: the whole row toggles its checkbox, radio or switch; Space toggles from the keyboard.
- Enter opens the row; Space selects or toggles it. Shift+F10 or the Menu key opens the row's context menu, as does a secondary click or a long press (touch, 500ms, with a haptic tick on Android and iOS).
- Text never wraps into a taller row than the variant: the headline ellipsises at the end, supporting text clamps and ellipsises. File names ellipsise in the middle ("release-notes-…-final.md") so the extension stays visible.
- Selection changes animate the fill in `duration-short-3` with `ease-standard`.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Density -1 (48 one line); selected rows also show a 3px `primary` pill at the leading edge, like Fluent list views; Shift+F10 and the Menu key open the context menu. |
| macOS | Density -1 with `body-medium` headlines in sidebars and source lists; selection is a rounded `radius-sm` inset fill in sidebars; ⌘-click toggles one row's selection, Control-click opens the context menu. No ripple. |
| Linux | Density -1; GNOME (libadwaita) places a trailing chevron on navigation rows and a switch on setting rows exactly as here; KDE may use density -2 in dense views. |
| Android | Touch metrics; ripple on press; long press starts selection mode in selectable lists. |
| iOS | Touch metrics with 44pt floor; separators inset to the text; navigation rows use the chevron; no ripple (the layer darkens); swipe gestures come from Swipe actions. |
| Web | Density -1 with a fine pointer, touch metrics with a coarse one (`pointer: coarse`); a navigation row is a real `<a>` so middle-click and "open in new tab" work. |

## Accessibility
- Role list item (or option inside a listbox, row inside a grid when the list is interactive with selection). Position in set and set size are exposed.
- Name: the headline; description: the supporting text and meta, read in visual order ("Maya Kovač, Approved build 4128, 2 minutes ago").
- States: Selected, Checked (control rows), Disabled, Expanded when the row opens a nested list in place.
- Actions: Activate (primary), plus a custom action for each trailing button and swipe action ("Delete", "Archive") so they are reachable without the gesture.
- Keyboard: Tab reaches the list, arrows move between rows (see List); Tab from a row reaches its trailing control, then the next focusable after the list.
- Contrast: headline 4.5:1 on its row in every state including Selected (7:1 in high contrast); supporting text `on-surface-variant` holds 4.5:1 on `surface`.
- Target: the row itself is the target (48 minimum on touch, 32 dense); trailing icon buttons keep a 48 target on touch even inside a 56 row.
- Status in a row (Modified, Failed) is a tag or icon with a word, never a coloured headline alone.
- Reduced motion: selection and state changes cross-fade in `duration-short-2`.

## Content
- Headline: the thing's name, as the person would say it: "Maya Kovač", "build.neper.toml", "Appearance". No verbs unless the row is an action ("Add account").
- Supporting: one fact, sentence case, no trailing period: "Approved build 4128", "Every 30 seconds".
- Meta: short, relative or counted: "2 min", "48 files", "Owner". Numerals, no units spelled out.
- Overline: a category of two words or fewer: "Design review".

## e.ui today
`collection.row` wraps the caller's item with no padding, gap or slots of its own, fills `selection` when selected and draws a `border` hairline under it. To reach this design:
- Give the row its anatomy: leading, overline, headline, supporting and trailing slots with the spacing and type above, instead of an opaque caller node.
- Set the variant heights (56/72/88 touch, 48/64/80 pointer, 32/48 dense) from density instead of the caller's `extent`.
- Make the row focusable with a primary action; draw the hover, focus (inset ring), pressed and dragged state layers. Today it has no action, no focus and no state look.
- Replace the `selection` fill with `secondary-container` and `on-secondary-container` content, and add the trailing check for single select.
- Move the separator to List (full or 72 inset) and use `outline-variant`, not `border`.
- Report the name and description from the headline and supporting text so the list item is not announced empty.
