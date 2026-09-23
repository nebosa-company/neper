# GridView

A grid view lays a small set of items out as equal tiles in rows that reflow with the width, for browsing things that are recognised by their picture: designs, images, folders.

## Anatomy
1. Grid: equal columns across the available width, `space-2` 8 gaps both ways, `space-4` 16 (compact) or `space-6` 24 page margins.
2. Tile container: `surface-container-low`, `radius-md`, clips its media.
3. Media: 4:3 (or 1:1) thumbnail, edge to edge at the top; a `surface-container-highest` fill with an `icon-lg` glyph while the image loads or when there is none.
4. Caption: name in `title-small`, one line; meta in `body-small` `on-surface-variant`, one line.
5. Selection check: a 24 circle at the top start; `primary` with an `on-primary` tick when selected, a 2px `on-surface-variant` ring when not (selection mode only).
6. State layer: `on-surface` over the whole tile, above the media.
7. Focus ring: 3px `focus-ring`, 2px outside the tile.

## Variants and when to use
| Variant | Tile | Use for |
|---|---|---|
| Media tile | 4:3 media plus caption, `surface-container-low` | Designs, documents with previews, projects. |
| Square media | 1:1 media, caption optional | Images, avatars, swatches. |
| Icon tile | 64 icon area plus a centred one-line name, no container until hovered or selected | Desktop file and folder views. |

Use Virtual grid when there are more than about 100 tiles or the set is paged. Use Card when each item needs actions or more than two lines of text. Use List when the items are recognised by name rather than picture.

## Specs
| Part | Touch | Pointer (density -1) |
|---|---|---|
| Minimum tile width | 160 (media), 96 (icon) | 144 (media), 88 (icon) |
| Columns | `floor((width + 8) / (min + 8))`, at least 2 on compact; tiles stretch to fill | same |
| Gap | `space-2` 8 | `space-2` 8 |
| Tile radius | `radius-md` 12 | `radius-md` 12 |
| Tile fill | `surface-container-low` | same |
| Media | 4:3, `surface-container-highest`, `icon-lg` 36 `on-surface-variant` placeholder | same |
| Caption padding | `space-2` 8 top, `space-3` 12 sides and bottom | same |
| Name / meta | `title-small` `on-surface` / `body-small` `on-surface-variant` | same |
| Icon tile | 64 icon area, `icon-lg`, name `body-medium` centred, two lines max for names | same, one line with middle ellipsis |
| Selected | tile `secondary-container`, content `on-secondary-container`; media insets `space-2` 8 with `radius-xs` 4 (12 less 8) | same |
| Check | 24 circle, `space-2` from the corner (`space-3` when selected), 16 tick at 2.5 stroke | same |

## States
- Hover: `state-hover` layer over the whole tile; icon tiles gain a `surface-container-low` fill. The check ring appears on hover even outside selection mode, as the way in.
- Focus: `state-focus` layer and the outside ring.
- Pressed: `state-pressed` layer; ripple on Android.
- Selected: `secondary-container` fill, media shrinks inward by 8 (`duration-short-3`, `ease-standard`), and the filled check: fill, shape and mark, never colour alone.
- Dragged: `elevation-4`, `state-dragged` layer; the tile lifts 4 and other tiles reflow round the gap.
- Disabled: content at 38%, media at 38% opacity, no layer, not focusable; the meta says why ("Archived, read only").
- Loading: tiles show skeleton media and caption bars; images fade in over `duration-short-4` when decoded.
- Empty: as List's empty state, centred in the grid's area.

## Behaviour
- Tap or click opens the item; outside selection mode a click on the check (or Ctrl/⌘-click, or a long press on touch) starts selection.
- Keyboard: arrows move focus in two dimensions; Left and Right wrap to the previous and next row; Home and End go to the first and last tile of the row, Ctrl+Home and Ctrl+End to the first and last tile. Page Up and Page Down move by a screen of rows.
- Selection: Space toggles; Shift+arrows extend from the anchor in reading order; Ctrl+A (⌘A) selects all; Escape clears. Rubber-band selection with a pointer drag on the empty area (desktop).
- Typeahead moves to the next tile whose name starts with the typed letters.
- Reflow: the column count changes with the width; tiles animate to their new positions in `duration-medium-1` with `ease-standard`; reduced motion snaps.
- Drag and drop: tiles can be dropped on a folder tile (it takes the `drop` look: a 2px `primary` inset outline) or reordered when the grid is ordered by hand.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Density -1; icon tiles as in File Explorer's large-icons view, selection fill with a 1px `primary` outline in high contrast; Ctrl+click and Shift+click select. |
| macOS | Density -1; icon tiles select the icon area and the name separately (a `radius-sm` highlight on each), as in Finder; Space opens Quick Look; ⌘-click toggles. |
| Linux | Density -1; GNOME Files style icon grid; KDE follows Dolphin with the check shown on hover. |
| Android | Touch metrics, at least 2 columns; long press enters selection mode and the top app bar becomes a selection bar. |
| iOS | Touch metrics; Select in the navigation bar enters selection mode; checks sit at the bottom trailing corner as in Photos; context menu on long press with a lifted preview. |
| Web | Density -1 with a fine pointer; CSS grid with `repeat(auto-fill, minmax(144px, 1fr))`; `role="grid"` with roving focus. |

## Accessibility
- Role grid (with rows and cells) when tiles are selectable or navigable in two dimensions; a list of links when tiles only open. Name: the pane's title.
- Each tile: name = the caption name; description = the meta; state Selected; position as row and column plus the flat index ("7 of 24").
- Actions: Open, Select, and the tile's context menu actions as custom actions.
- Keyboard as in Behaviour; one tab stop for the whole grid.
- Contrast: captions 4.5:1 on the tile fill in every state; the unselected check ring is `on-surface-variant`, 3:1 or better on media placeholders and on `surface-container-lowest` behind it.
- Target: tiles far exceed 48; the check has a 48 (touch) or 32 (pointer) target around its 24 circle.
- Images need alternative text from the app; a tile with only an image uses the file name as its name.
- Reduced motion: no reflow animation, no selection inset animation.

## Content
- Names: the item's own name; file names keep their extension and ellipsise in the middle.
- Meta: one fact, relative dates up to a week ("Edited 2 h ago", "Edited yesterday"), then dates ("Edited 12 Sep").
- No text on top of media.

## e.ui today
`collection.grid_view` wraps prebuilt items in `collection.cell`s of an exact `cell_size`, packs as many columns as fit (spare width left at the end), fills `selection` behind selected cells, and gives cells no focus or input. To reach this design:
- Stretch tiles to fill the row instead of leaving spare width at the end; derive columns from a minimum tile width.
- Give the tile its anatomy (container, media, caption, check) instead of a bare clipped box, with `radius-md` and the tonal fill.
- Make cells focusable with two-dimensional arrow navigation, Home/End, typeahead and the selection model.
- Draw hover, focus, pressed, dragged and selected looks; replace the `selection` fill with `secondary-container` plus the check.
- Add loading (skeleton) and empty states, and drag-and-drop targets.
