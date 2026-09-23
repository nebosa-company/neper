# FontPicker

A font picker chooses a font family, style and size together with a live preview, for editor, terminal and document settings.

## Anatomy
1. Trigger (compact and forms): a field showing "Family, size" set in the chosen face, with a trailing chevron.
2. Panel: `surface-container-low`, `radius-md`, 16 padding, two columns.
3. Search field: dense outlined with a leading `search` icon.
4. Family list: a `surface` list, `radius-sm`, grouped (Recent, Monospace, All fonts) with subheaders; each row names the family in its own face; the chosen row in `secondary-container` with a `check`.
5. Style picker: a dense Picker (Regular, Italic, Bold, ...), listing only the faces the family has.
6. Size spin box: dense, in points (or pixels where the host uses them).
7. Feature toggles (optional): filter chips such as Ligatures; a tag for "Variable font".
8. Preview: `surface`, 1px `outline-variant`, `radius-sm`, showing sample text in the chosen face and size, captioned "Preview, 13 pt".

## Variants and when to use
| Variant | Use for |
|---|---|
| Panel (inline) | A settings page on pointer hosts: Editor font, Terminal font. |
| Trigger + popover | A toolbar or inspector; the panel opens anchored to the trigger. |
| Trigger + sheet | Touch hosts: a full-height sheet with the list and a sticky preview. |
| Family only | A Picker or Combo box when style and size are set elsewhere. |

Use a Combo box for size alone (presets plus typing), and the host's system font dialog when the app edits rich documents and the host provides one (see Platform adaptation).

## Specs
| Part | Value |
|---|---|
| Panel | `surface-container-low`, `radius-md`, padding `space-4` 16, columns `space-4` apart; list column 260 |
| Search | dense outlined field, 40 |
| Family list | `surface`, `radius-sm`, 196 min (5 to 8 rows), scrolls; rows 40 (`nu-li dense`), family name 15/20 in its own face |
| Subheaders | `title-small` at 12, `primary`, padding `space-2` `space-4` `space-1` |
| Chosen row | `secondary-container` / `on-secondary-container`, trailing `check` `icon-sm` |
| Style and size | dense Picker 160 wide, dense Spin box 104 wide, 1 to 288 pt, step 1 |
| Feature chips | filter chips 32, `space-2` apart |
| Preview | `surface`, 1px `outline-variant`, `radius-sm`, padding `space-3` `space-4`, min 88 tall; caption `label-small` `on-surface-variant` |
| Trigger | the Text field (filled on touch, outlined dense on pointer), value in the chosen face |

## States
- Family rows: hover `state-hover`, keyboard active `state-focus` + inset ring, chosen `secondary-container`.
- Missing font (a saved family not installed): the trigger shows the name in the fallback face with a `warning` icon and "Not installed, using Segoe UI".
- Loading families: Skeleton rows; the first time the list renders each name in its face, rows that are still loading show the name in `font-sans`.
- No search results: a compact Empty state in the list ("No fonts match "zz"").
- Disabled: all parts disabled, with the reason in supporting text ("Managed by your workspace").

## Behaviour
- Typing in search filters families by name (and by tag: "mono", "serif"); Down moves from the search into the list.
- In the list: Up/Down move and choose (the preview follows at once), Home/End, Page Up/Down, typeahead by name.
- Choosing a family keeps the style if the new family has it, else falls back to Regular and says so in the style picker.
- Changes apply live to the preview; they apply to the app when the setting commits (immediately in settings pages; on "Apply" inside a dialog).
- Recently used families appear first, up to 5.
- The popover and sheet open with the Menu and Sheet motion; nothing inside animates.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Panel inline in settings at density -1; families from DirectWrite; sizes in points. |
| macOS | For text documents use the system Font Panel (⌘T) via NSFontManager; for app settings use this panel; sizes in points. |
| Linux | Families from fontconfig; the GTK font chooser dialog may be used for documents; group by fontconfig spacing (monospace). |
| Android | Trigger opens a full-height sheet; bundled and downloadable fonts; sizes in sp. |
| iOS | Trigger opens a sheet; UIFontPickerViewController is allowed for documents; sizes in points; Dynamic Type sizes offered as presets. |
| Web | Local font access needs permission; without it, list the app's bundled fonts and the generic families; sizes in px. |

## Accessibility
- The panel is a group named by the setting ("Editor font"); the list is a listbox named "Family"; style and size are named "Style" and "Size" and drawn as visible labels.
- Family rows expose the family name as text (never an image of the face).
- Announce the chosen family, style and size after each change ("Cascadia Code, Regular, 13 points").
- Decorative and symbol fonts show their name in `font-sans` in addition to their face, so the row is readable.
- Rows 40 with a pointer, 56 in the touch sheet.

## Content
Family names are shown exactly as the font names itself. Group names are plain: "Recent", "Monospace", "All fonts". The preview uses content from the app's domain (a code sample for an editor), not "The quick brown fox" by default; people can type their own.

## e.ui today
`control.font_picker` stacks a bordered `list_box` of families, a `segmented_control` of styles, a `stepper` for size (4 to 288) and a square-cornered preview; no part draws a label ("Family", "Style", "Size" exist only in the tree, in English), and `families[family]` is read without a bounds check. To reach this design:
- Lay out the two-column panel on `surface-container-low` with visible labels, a search field and a grouped family list rendering each family in its face.
- Replace the segmented styles with a dense Picker limited to the family's faces, and the stepper with a dense Spin box.
- Draw the preview with `radius-sm`, a caption and domain sample text; add the trigger field and the popover and sheet presentations.
- Bounds-check `family` (fall back to the first family and flag the missing font) and localise the part names.
- Add search filtering, recent families and live preview on arrow keys.
