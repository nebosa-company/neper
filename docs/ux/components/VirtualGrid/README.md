# VirtualGrid

A virtual grid shows a large or paged set of tiles, such as a photo library or an asset catalogue, in a scrolling viewport that builds only the rows in view.

## Anatomy
1. Viewport: the scrolling region on `surface`, clipped.
2. Section header (optional): a sticky bar with the section's title in `title-small`, a count in `body-medium` `on-surface-variant`, and an optional "Select all" text button.
3. Rows of tiles: GridView tiles, usually square photo tiles, `space-1` 4 apart (2 on compact touch).
4. Placeholder tiles: `surface-container-highest` squares for tiles not built or not loaded yet.
5. Scroll thumb: overlay thumb; on touch a scrubber that shows the date or section under it.
6. Selection bar (selection mode): replaces the header with Clear, the count and bulk actions.

## Variants and when to use
| Variant | Use for |
|---|---|
| Uniform grid | Every tile the same size: icons, swatches, thumbnails. |
| Sectioned grid | Tiles grouped by date or folder, each section starting a new row under a sticky header. |
| Paged grid | Server-backed sets that load pages as the viewport nears the end. |

Use GridView for a small set built at once. Use Virtual list when items are rows. A masonry (varying-height) layout is not a Virtual grid: use a Virtual list of rows of cards.

## Specs
| Part | Touch | Pointer (density -1) |
|---|---|---|
| Photo tile minimum | 96 (3 columns at 360 width) | 112 |
| Columns | `floor((width - 2 × padding + gap) / (min + gap))`; tiles stretch to fill | same |
| Gap / padding | 2 / 2 on compact, `space-1` 4 / `space-3` 12 from medium | `space-1` 4 / `space-3` 12 |
| Photo tile | 1:1 media, `radius-sm` 8 (`radius-none` on compact touch) | `radius-sm` 8 |
| Section header | `control-md` 40 (pointer) / `control-lg` 48 (touch); `title-small` `on-surface`, count `body-medium` `on-surface-variant`; `surface-container` while pinned | same |
| Build window | visible rows plus one screen each way; tiles recycled by key | same |
| Placeholder | `surface-container-highest`, same shape as the tile | same |
| Scroll thumb | as Virtual list: 4 wide, 8 on hover or drag, `on-surface-variant` at 50% | same |
| Scrub label | plain tooltip (`inverse-surface`, `body-small`) beside the thumb: the section under it | pointer hosts show it while the thumb is dragged |
| Selected tile | `secondary-container` behind, media inset 8, `radius-xs`, filled check | same |

## States
- Loading: placeholders fill the rows first; each image fades in (`duration-short-4`, `ease-standard`) when decoded. Placeholders never shimmer on reduced motion.
- Scrolling fast: rows past the build window stay placeholders until scrolling slows below one screen per 100ms, then build.
- Selection mode: every tile shows its check (ring when unselected); the header shows the selection bar; section headers gain "Select all" / "Deselect all".
- Tile states (hover, focus, pressed, selected, dragged, disabled) as GridView.
- Error loading a page: a full-width row with "Couldn't load 40 photos" and Retry, in place of the missing rows.
- Empty: as List's empty state, centred.

## Behaviour
- Keyboard: arrows move in two dimensions and scroll the focused tile into view; Up and Down keep the column across sections (to the nearest tile when a row is short); Page Up and Page Down move by a screen of rows; Home and End go to the first and last tile of the set, loading them if needed.
- Selection: Space toggles; Shift+arrows and Shift+click extend a range in reading order; Ctrl+A (⌘A) selects all loaded and unloaded tiles (by key range, not by building them); on touch, a long press selects and a drag after it selects the run of tiles it crosses.
- Pinch (touch) or Ctrl+wheel / Ctrl+plus and minus (desktop) steps the tile size through 3 to 4 levels, keeping the tile under the focal point in place.
- Scrub: dragging the thumb jumps by section and shows the section label; releasing lands on the section's first row.
- Focus and selection are by key; inserts above the viewport keep the visible rows still.
- Motion: tiles animate to new positions on a size change over `duration-medium-2` with `ease-standard`; reduced motion cross-fades.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Density -1; Photos-style grid with Ctrl+wheel zoom; Fluent overlay scrollbar with the scrub label. |
| macOS | Density -1; ⌘+ and ⌘- change tile size; pinch on trackpad; Space opens Quick Look on the focused tile. |
| Linux | Density -1; GNOME's grid uses `radius-sm` tiles and `space-1` gaps as here; KDE may show classic scrollbars. |
| Android | Touch metrics, 3 columns on compact, `radius-none` tiles at 2 gaps; drag-to-select after a long press; the fast-scroll scrubber with dates. |
| iOS | Touch metrics; Select in the navigation bar; drag-to-select with two fingers or after a long press; pinch zoom between levels. |
| Web | Density -1 with a fine pointer; CSS grid rows inside a virtualised block with `content-visibility: auto`; roving focus on `role="gridcell"`. |

## Accessibility
- Role grid named by the pane ("Screenshots"), with the full row count and column count; sections are row groups with their header as a heading.
- Each tile: name from the app (the image's description or file name), position as row and column plus "37 of 2,316"; Selected.
- Placeholders are hidden from the tree; the grid is Busy while loading, and announces "40 more photos loaded" politely only when focus is in the grid.
- Custom actions per tile: Open, Select, Share, Delete.
- Keyboard as in Behaviour; one tab stop for the grid, then Tab to the selection bar.
- Targets: tiles well above 48; checks keep a 48 target on touch.
- Reduced motion: no zoom animation, no fade-in.

## Content
- Section headers: a date or folder name, then the count with its noun: "12 September", "14 screenshots".
- Scrub label: the coarsest useful unit: "August 2026".
- Error rows: what failed and how many: "Couldn't load 40 photos".

## e.ui today
`collection.virtual_grid` lays a `Source`'s cells of `cell_size` into rows of as many as fit across `width` inside a lazy viewport, builds only the visible rows, fills `selection` behind selected cells, and paints the same 4px square `border` thumb as `virtual_list`. To reach this design:
- Stretch tiles to fill each row and derive columns from a minimum tile size.
- Add sticky section headers with row-starting sections, placeholders for unbuilt tiles, and paging.
- Make the thumb a real control with the scrub label; add pinch and Ctrl+wheel size levels.
- Make cells focusable with two-dimensional arrow navigation and the selection model (Shift ranges, select all by key range, drag-to-select on touch).
- Stop reserving `key + 1 + r` for row keys (it collides with the caller's key space); key rows from the tile keys they hold.
- Draw tile states as GridView and replace the `selection` fill with `secondary-container` plus the check.
