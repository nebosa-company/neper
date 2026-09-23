# Tree

A tree shows a hierarchy as indented, expandable rows, so people can browse and pick items at any depth: project files, a settings hierarchy, a table of contents.

## Anatomy
1. Container: `surface`, `space-1` 4 top and bottom padding; usually a sidebar pane.
2. Tree item: a row inset `space-2` 8 from the pane's sides, `radius-sm`, one line.
3. Indent: `space-5` 20 per level (pointer) or `space-6` 24 (touch), before the twisty.
4. Twisty: `chevron-right` `icon-sm` 18 in a 24 box, `on-surface-variant`; rotates 90° when expanded; an empty 24 box on leaves keeps labels aligned.
5. Icon (optional): `icon-sm` 18, `on-surface-variant` (folder, file, or the item's own).
6. Label: `body-medium`, ellipsised at the end (file names in the middle).
7. Trailing meta (optional): `label-small` `on-surface-variant`: a count, a status word.
8. State layer and inset focus ring.

## Variants and when to use
| Variant | Use for |
|---|---|
| Navigation tree | Sidebars that open what is picked (files, settings sections): single selection follows activation. |
| Selection tree | Choosing several nodes (folders to sync): a leading checkbox per item; a parent shows mixed when some children are checked. |
| Lazy tree | Hierarchies loaded on expand (remote folders): a Loading child row while fetching. |

Use Outline when the hierarchy is a document's structure and position matters. Use Tree table when nodes have attributes in columns. Use a List with drill-in navigation on compact touch screens when the hierarchy is deeper than three levels.

## Specs
| Part | Touch | Pointer (density -2, default for trees) | Pointer (density -1) |
|---|---|---|---|
| Row height | `control-lg` 48 | `control-sm` 32 | `control-md` 40 |
| Row inset | `space-2` 8 each side, `radius-sm` 8 | same | same |
| Indent step | `space-6` 24 | `space-5` 20 | `space-5` 20 |
| Start padding | `space-1` 4 before the first twisty | same | same |
| Twisty | 24 box, `icon-sm` 18 chevron, `on-surface-variant` | same | same |
| Twisty to icon to label gap | `space-2` 8 | same | same |
| Icon | `icon-sm` 18 (`icon-md` 24 on touch) | `icon-sm` | `icon-sm` |
| Label | `body-large` | `body-medium` | `body-medium` |
| Meta | `label-small`, `on-surface-variant` | same | same |
| Selected | `secondary-container`, all content `on-secondary-container` | same | same |
| Drop target | 2px `primary` inset outline, `primary` at 8% fill, a meta hint "Drop to move" | same | same |
| Rename field | an outlined field, 24 tall, inside the row | same | same |
| Loading child | a 18 progress ring in the icon slot and "Loading" in `on-surface-variant` | same | same |

## States
- Hover: `state-hover` layer over the inset row.
- Focus: inset 3px ring; independent of selection (Ctrl+arrows move focus without selecting in multi-select trees).
- Pressed: `state-pressed` layer; ripple on Android.
- Selected: `secondary-container` fill; in single-select navigation trees the selected item is also the one whose content is open.
- Expanded / collapsed: the twisty's rotation; children appear or disappear below.
- Dragged: the row lifts (`surface-container-high`, `elevation-4`); a folder under the pointer takes the drop-target look, and hovering it for 700ms expands it.
- Renaming: the label becomes a field with the name selected up to the extension.
- Loading children, and load failed ("Couldn't load. Retry" as a child row with a text button).
- Disabled: 38% content, not selectable, still focusable so its reason ("Locked") can be read.

## Behaviour
- Pointer: click the twisty to expand or collapse; click the row to select (and open, in navigation trees); double-click a branch toggles it.
- Touch: tapping a branch's row toggles it and selects it; tapping a leaf opens it.
- Keyboard (one tab stop): Up and Down move; Right expands a closed branch, or moves to its first child when open; Left collapses an open branch, or moves to the parent; Home and End go to the first and last visible item; `*` expands all siblings; Enter opens; F2 renames; Delete deletes (with Undo); typeahead moves to the next visible item starting with the typed letters.
- Multi-select trees: Space toggles, Shift+Up/Down extends, Ctrl+A selects all visible.
- Expand state and scroll position persist per tree.
- Long trees virtualise like Virtual list; a tree never silently drops rows.
- Motion: children expand with a height and fade over `duration-medium-2`, `ease-emphasized-decelerate`, and collapse over `duration-short-4`, `ease-emphasized-accelerate`; the twisty rotates in `duration-short-3`, `ease-standard`. Reduced motion: children appear at once, the twisty flips without rotating.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Density -2 (32) as in Explorer's navigation pane; Fluent selection with a 3px leading `primary` pill; F2 rename; numpad `+` and `-` expand and collapse. |
| macOS | Density -2 with `body-medium` in sidebars (source-list style, disclosure on the leading edge); ⌥-click on a twisty expands all descendants; Return renames, ⌘Delete deletes. |
| Linux | Density -2; GTK tree expanders; KDE draws branch lines optionally (use Outline for that). |
| Android | Touch 48; prefer drill-in Lists beyond three levels; long press for the item menu. |
| iOS | Touch 48 (44pt); outline-style disclosure rows as in Files' sidebar (UICollectionView list with outline disclosure); drill-in on compact. |
| Web | Density by pointer; `role="tree"` with `treeitem`, `aria-level`, `aria-setsize`, `aria-posinset`, `aria-expanded`; roving tabindex. |

## Accessibility
- Role tree, named by the pane ("Project files"); multi-select trees set multiselectable.
- Each item is a treeitem with level, position among siblings, set size, Expanded (branches only), Selected, Busy while loading children, Disabled.
- Actions: Expand, Collapse, Open, Rename and the item's menu actions as custom actions.
- Announcements: expanding announces the number of children ("ui, expanded, 3 items"); drops announce the result ("control.e moved to data").
- Contrast: labels 4.5:1 on `surface` and `secondary-container`; the twisty and icons in `on-surface-variant` hold 3:1.
- Target: 32 rows on pointer (the minimum), 48 on touch; the twisty's hit area is the full row height by 24 plus the indent's half step.
- Reduced motion as in Behaviour.

## Content
- Labels are node names as stored; do not add counts to the label (use meta).
- Meta: a word or count: "Modified", "12", "Locked".
- Loading and error child rows: "Loading", "Couldn't load. Retry".

## e.ui today
`collection.tree` flattens a `TreeSource`'s expanded nodes into `table_row`s of one `width`-wide cell with an indent of `depth × space-lg`, a filled-triangle mark (blank for leaves) and the caller's content; Left and Right toggle, a tap on the mark toggles, a row tap picks. To reach this design:
- Remove the 512-visible-row cap (`tree_rows` allocates 512 and `flatten` silently drops the rest) and virtualise the rows.
- Draw the twisty as a rotating `chevron-right` in a 24 box, with the 20/24 indent steps, inset `radius-sm` rows and the icon and meta slots.
- Paint the focus ring (rows show none today) and add Up/Down, Right-to-child, Left-to-parent, Home, End, `*`, typeahead, F2 and Enter.
- Expose Expand and Collapse as actions on the item; the mark is not focusable and not in the tree.
- Add hover, pressed, selected (`secondary-container`), drag and drop, rename, loading-children and disabled states.
