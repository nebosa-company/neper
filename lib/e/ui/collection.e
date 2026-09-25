// Collections over the widget tree (D833, widget plan P2-05): lists and grids of
// items a caller's source builds, only the visible ones plus overscan ever made
// into elements (§3.6 of the proposal). A source is bounded and callback-based --
// a count, a stable key an item keeps as the model moves, and a build into the
// frame arena -- never a slice of prebuilt nodes; selection is the caller's set of
// keys; the scroll offset follows D807's rule and every move is reported.

use e.mem
use e.gfx.geometry
use e.gfx.paint
use e.ui.accessibility
use e.ui.control
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.widget

error TooLarge

// A bounded data source: how many items, the stable key of one, and one built
// into the arena as a node (written to `out`).
type Source = struct { ctx: *void, count: fn(*void) -> usize, key: fn(*void, usize) -> widget.Key, build: fn(*void, *mem.Arena, usize, *widget.Node) -> err }

// Whether `key` is among the selected.
fn is_selected(selected: []const widget.Key, key: widget.Key) -> bool {
    var i = 0usize
    while i < selected.len {
        if selected[i] == key { ret true }
        i += 1usize
    }
    ret false
}

// A row of a list: the item over a hairline separator (when asked), `extent` tall
// and `width` wide, a list item in the tree at `index` of `count`, selected when
// its key is.
fn row(a: *mem.Arena, t: *const control.Theme, item: widget.Node, key: widget.Key, index: usize, count: usize, extent: f32, width: f32, separator: bool, selected: bool) -> (widget.Node, err) {
    var parts_count = 1usize
    if separator { parts_count = 2usize }
    let (parts, parts_error) = mem.alloc[widget.Node](a, parts_count)
    if parts_error != ok { ret (zero, TooLarge) }
    // The item fills a fixed extent; with none the row is as tall as the item, since a
    // flex share under an unbounded height (a list in a scroll view) is no height at all.
    var grown = item
    if extent > 0.0 { grown.style.height = style.Length { Flex: 1.0 } }
    parts[0usize] = grown
    if separator {
        let (line, line_error) = control.divider(a, 0u64, t, .Horizontal, 0.0)
        if line_error != ok { ret (zero, line_error) }
        parts[1usize] = line
    }
    var row_style = style.defaults()
    row_style.width = style.Length { Px: width }
    if extent > 0.0 { row_style.height = style.Length { Px: extent } }
    // v2 (D979, docs/ux/components/Row): selected is `secondary-container`.
    if selected { row_style.background = paint.Brush { Solid: style.color(t.tokens, .SecondaryContainer) } }
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(key, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, row_style, parts[0usize..parts_count])
    var sem: widget.Semantics = zero
    sem.role = 11u8
    sem.row = u32(index + 1usize)
    sem.row_count = u32(count)
    if selected { sem.states = accessibility.STATE_SELECTED }
    ret (widget.semantics(0u64, sem, style.defaults(), column[0usize..1usize]), ok)
}

// A list of static rows for a small collection: the caller's items, each a list
// item over a separator, in a column `width` wide; `keys` name them (for the
// selection) and `selected` says which are. A list in the tree named `label`.
fn list(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, items: []const widget.Node, keys: []const widget.Key, selected: []const widget.Key, separators: bool, width: f32) -> (widget.Node, err) {
    if keys.len != items.len { ret (zero, TooLarge) }
    let (rows, rows_error) = mem.alloc[widget.Node](a, items.len)
    if rows_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < items.len {
        let (made, made_error) = row(a, t, items[i], keys[i], i, items.len, 0.0, width, separators && i + 1usize < items.len, is_selected(selected, keys[i]))
        if made_error != ok { ret (zero, made_error) }
        rows[i] = made
        i += 1usize
    }
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), rows[0usize..items.len])
    var sem: widget.Semantics = zero
    sem.role = 10u8
    sem.label = label
    sem.row_count = u32(items.len)
    ret (widget.semantics(key, sem, style.defaults(), column[0usize..1usize]), ok)
}

// A virtual list: the source's items as rows of `extent` each in a lazy viewport
// (keyed `key`) `width` by `height`, only those `widget.visible_range` names at
// `offset` built, keyed by the source so the reconciler recycles the rest; every
// move of the offset reaches `change`. The viewport is the list in the tree; the
// group above it is named `label`.
fn virtual_list(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, source: Source, selected: []const widget.Key, extent: f32, offset: f32, change: widget.Change[f32], separators: bool, width: f32, height: f32) -> (widget.Node, err) {
    if extent <= 0.0 { ret (zero, TooLarge) }
    let total = source.count(source.ctx)
    let (first, count) = widget.visible_range(offset, height, total, extent)
    let (rows, rows_error) = mem.alloc[widget.Node](a, count)
    if rows_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < count {
        let index = first + i
        let item_key = source.key(source.ctx, index)
        var built: widget.Node = zero
        let built_error = source.build(source.ctx, a, index, &built)
        if built_error != ok { ret (zero, built_error) }
        // v2 (D979): no separator under the last row.
        let (made, made_error) = row(a, t, built, item_key, index, total, extent, width, separators && index + 1usize < total, is_selected(selected, item_key))
        if made_error != ok { ret (zero, made_error) }
        rows[i] = made
        i += 1usize
    }
    var view_style = style.defaults()
    view_style.width = style.Length { Px: width }
    view_style.height = style.Length { Px: height }
    view_style.overflow = .Clip
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = widget.scroll(key, widget.Scroll { axis: .Vertical, offset: offset, overscroll: .Clamp, momentum: true, scrollbar: true, thumb: control.with_alpha(style.color(t.tokens, .OnSurfaceVariant), 0.5), change: change, virtual_first: first, virtual_count: total, virtual_extent: extent }, view_style, rows[0usize..count])
    // v2 (D979, docs/ux/components/VirtualList): a list with the full count.
    var sem: widget.Semantics = zero
    sem.role = 10u8
    sem.label = label
    sem.row_count = u32(total)
    ret (widget.semantics(0u64, sem, style.defaults(), body[0usize..1usize]), ok)
}

// How many cells of `cell_width` fit across `width`, at least one.
fn columns_across(width: f32, cell_width: f32, gap: f32) -> usize {
    if cell_width <= 0.0 { ret 1usize }
    var fit = usize((width + gap) / (cell_width + gap))
    if fit < 1usize { fit = 1usize }
    ret fit
}

// A cell of a grid: the item sized to the cell, a cell in the tree at its row and
// column, selected when its key is.
fn cell(a: *mem.Arena, t: *const control.Theme, item: widget.Node, key: widget.Key, row_index: usize, column_index: usize, size: geometry.Size, selected: bool) -> (widget.Node, err) {
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = item
    var cell_style = control.sized_style(size.width, size.height)
    cell_style.overflow = .Clip
    // v2 (D979, docs/ux/components/GridView): a tile is `surface-container-low`
    // with `radius-md`, `secondary-container` when selected.
    cell_style.radius = t.tokens.radii.md
    cell_style.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerLow) }
    if selected { cell_style.background = paint.Brush { Solid: style.color(t.tokens, .SecondaryContainer) } }
    let (boxed, boxed_error) = mem.alloc[widget.Node](a, 1usize)
    if boxed_error != ok { ret (zero, TooLarge) }
    boxed[0usize] = widget.box(key, cell_style, body[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 14u8
    sem.row = u32(row_index + 1usize)
    sem.column = u32(column_index + 1usize)
    if selected { sem.states = accessibility.STATE_SELECTED }
    ret (widget.semantics(0u64, sem, style.defaults(), boxed[0usize..1usize]), ok)
}

// A grid view of static cells: the caller's items as cells of `cell_size`,
// wrapped across `width` -- as many columns as fit, so the count adapts to the
// width -- with `gap` between; `keys` name them and `selected` says which are. A
// grid in the tree named `label` with the row and column counts.
fn grid_view(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, items: []const widget.Node, keys: []const widget.Key, selected: []const widget.Key, cell_size: geometry.Size, gap: f32, width: f32) -> (widget.Node, err) {
    if keys.len != items.len { ret (zero, TooLarge) }
    let columns = columns_across(width, cell_size.width, gap)
    let (cells, cells_error) = mem.alloc[widget.Node](a, items.len)
    if cells_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < items.len {
        let (made, made_error) = cell(a, t, items[i], keys[i], i / columns, i % columns, cell_size, is_selected(selected, keys[i]))
        if made_error != ok { ret (zero, made_error) }
        cells[i] = made
        i += 1usize
    }
    var flow_style = style.defaults()
    flow_style.width = style.Length { Px: width }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = widget.wrap(0u64, ui_layout.Wrap { axis: .Horizontal, main_gap: gap, cross_gap: gap }, flow_style, cells[0usize..items.len])
    var sem: widget.Semantics = zero
    sem.role = 30u8
    sem.label = label
    sem.column_count = u32(columns)
    sem.row_count = u32((items.len + columns - 1usize) / columns)
    ret (widget.semantics(key, sem, style.defaults(), body[0usize..1usize]), ok)
}

// A virtual grid: the source's items as cells of `cell_size` in rows of as many
// as fit across `width`, the rows in a lazy viewport (keyed `key`) `height` tall
// -- only the visible rows' cells built, each row keyed `key + 1 + row` for the
// reconciler -- every move of `offset` reaching `change`. A grid in the tree
// named `label`, the viewport inside it.
fn virtual_grid(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, source: Source, selected: []const widget.Key, cell_size: geometry.Size, gap: f32, offset: f32, change: widget.Change[f32], width: f32, height: f32) -> (widget.Node, err) {
    if cell_size.height <= 0.0 { ret (zero, TooLarge) }
    let total = source.count(source.ctx)
    let columns = columns_across(width, cell_size.width, gap)
    let row_total = (total + columns - 1usize) / columns
    let extent = cell_size.height + gap
    let (first, count) = widget.visible_range(offset, height, row_total, extent)
    let (rows, rows_error) = mem.alloc[widget.Node](a, count)
    if rows_error != ok { ret (zero, TooLarge) }
    var r = 0usize
    while r < count {
        let row_index = first + r
        var across = columns
        if row_index * columns + across > total { across = total - row_index * columns }
        let (cells, cells_error) = mem.alloc[widget.Node](a, across)
        if cells_error != ok { ret (zero, TooLarge) }
        var c = 0usize
        while c < across {
            let index = row_index * columns + c
            let item_key = source.key(source.ctx, index)
            var built: widget.Node = zero
            let built_error = source.build(source.ctx, a, index, &built)
            if built_error != ok { ret (zero, built_error) }
            let (made, made_error) = cell(a, t, built, item_key, row_index, c, cell_size, is_selected(selected, item_key))
            if made_error != ok { ret (zero, made_error) }
            cells[c] = made
            c += 1usize
        }
        var row_style = style.defaults()
        row_style.width = style.Length { Px: width }
        row_style.height = style.Length { Px: extent }
        rows[r] = widget.flex(key + 1u64 + u64(row_index), ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: gap }, row_style, cells[0usize..across])
        r += 1usize
    }
    var view_style = style.defaults()
    view_style.width = style.Length { Px: width }
    view_style.height = style.Length { Px: height }
    view_style.overflow = .Clip
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = widget.scroll(key, widget.Scroll { axis: .Vertical, offset: offset, overscroll: .Clamp, momentum: true, scrollbar: true, thumb: control.with_alpha(style.color(t.tokens, .OnSurfaceVariant), 0.5), change: change, virtual_first: first, virtual_count: row_total, virtual_extent: extent }, view_style, rows[0usize..count])
    var sem: widget.Semantics = zero
    sem.role = 30u8
    sem.label = label
    sem.column_count = u32(columns)
    sem.row_count = u32(row_total)
    ret (widget.semantics(0u64, sem, style.defaults(), body[0usize..1usize]), ok)
}

// --------------------------------------------------- paged collections (D835, P2-06)

// A turn of the page to a given index, for a dot, a button or a key.
type Turn = struct { index: usize, turn: widget.Change[usize] }

fn turn_fire(ctx: *void) -> err {
    let t = mem.cast[*Turn](ctx)
    ret widget.fire_change[usize](t.turn, t.index)
}

// What a page's swipe keeps across the frames of one drag: whether it turned,
// and (D982) how far the drag has moved, for a view that follows it.
type Swipe = struct { turned: bool, moved: f32 }

// A page view's drag: the cell the swipe keeps (none on the view's first frame),
// where the pages stand, and whom to tell; (D982) settling, the drag only moves
// the strip and the release turns past the threshold.
type Paging = struct { cell: *Swipe, has_cell: bool, current: usize, count: usize, threshold: f32, turn: widget.Change[usize], settle: bool }

fn page_drag(ctx: *void, g: widget.Gesture) -> err {
    let p = mem.cast[*Paging](ctx)
    switch g {
    case .DragStart as at:
        if p.has_cell {
            p.cell.turned = false
            p.cell.moved = 0.0
        }
        ret ok
    case .DragMove as d:
        if !p.has_cell { ret ok }
        if p.settle {
            p.cell.moved = d.position.x - d.start.x
            ret ok
        }
        if p.cell.turned { ret ok }
        // The drag's delta is since the last move; the distance is from the start.
        let moved = d.position.x - d.start.x
        if moved < 0.0 - p.threshold && p.current + 1usize < p.count {
            p.cell.turned = true
            ret widget.fire_change[usize](p.turn, p.current + 1usize)
        }
        if moved > p.threshold && p.current > 0usize {
            p.cell.turned = true
            ret widget.fire_change[usize](p.turn, p.current - 1usize)
        }
        ret ok
    case .DragEnd as at:
        if !p.has_cell { ret ok }
        p.cell.turned = false
        let moved = p.cell.moved
        p.cell.moved = 0.0
        if !p.settle { ret ok }
        if moved < 0.0 - p.threshold && p.current + 1usize < p.count { ret widget.fire_change[usize](p.turn, p.current + 1usize) }
        if moved > p.threshold && p.current > 0usize { ret widget.fire_change[usize](p.turn, p.current - 1usize) }
        ret ok
    default:
        ret ok
    }
}

// A page view: the page at `current` alone in a clipped box `width` by `height`
// (keyed `key`), a horizontal drag past a quarter of the width turning to the
// next or the previous page once per drag, Left and Right turning from the
// focused view; every turn reaches `turn` with the index and the caller keeps
// `current`. A group in the tree with the page's position.
fn page_view(a: *mem.Arena, key: widget.Key, t: *const control.Theme, pages: []const widget.Node, current: usize, turn: widget.Change[usize], width: f32, height: f32) -> (widget.Node, err) {
    if pages.len == 0usize || current >= pages.len { ret (zero, TooLarge) }
    let (pagings, pagings_error) = mem.alloc[Paging](a, 1usize)
    if pagings_error != ok { ret (zero, TooLarge) }
    var none_cell: *Swipe = zero
    pagings[0usize] = Paging { cell: none_cell, has_cell: false, current: current, count: pages.len, threshold: width * 0.25, turn: turn, settle: false }
    // The swipe's cell lives on the view's element from the frame before; on the
    // first frame there is none and a drag that frame turns nothing.
    let (s, state_error) = widget.state_of(t.runtime)
    if state_error == ok {
        let (id, found) = widget.find_by_key(s, key)
        if found == 1usize {
            var build = widget.BuildContext { runtime: t.runtime, element: id, frame: 0u64 }
            let (kept, _, kept_error) = widget.state[Swipe](&build, key, Swipe { turned: false, moved: 0.0 })
            if kept_error == ok {
                pagings[0usize].cell = kept
                pagings[0usize].has_cell = true
            }
        }
    }
    let (turns, turns_error) = mem.alloc[Turn](a, 2usize)
    if turns_error != ok { ret (zero, TooLarge) }
    var previous = current
    if current > 0usize { previous = current - 1usize }
    var next = current
    if current + 1usize < pages.len { next = current + 1usize }
    turns[0usize] = Turn { index: previous, turn: turn }
    turns[1usize] = Turn { index: next, turn: turn }
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 2usize)
    if shortcuts_error != ok { ret (zero, TooLarge) }
    shortcuts[0usize] = widget.Shortcut { key: 37u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&turns[0usize]), invoke: turn_fire } }
    shortcuts[1usize] = widget.Shortcut { key: 39u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&turns[1usize]), invoke: turn_fire } }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = pages[current]
    var view_style = control.sized_style(width, height)
    view_style.overflow = .Clip
    let (hit, hit_error) = mem.alloc[widget.Node](a, 1usize)
    if hit_error != ok { ret (zero, TooLarge) }
    control.focus_look(t)
    hit[0usize] = widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&pagings[0usize]), invoke: page_drag }, gestures: 2u8, enabled: true, focusable: true }, view_style, body[0usize..1usize])
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: shortcuts[0usize..2usize], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), hit[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.row = u32(current + 1usize)
    sem.row_count = u32(pages.len)
    ret (widget.semantics(0u64, sem, style.defaults(), scoped[0usize..1usize]), ok)
}

// A page indicator: a dot a page, keyed `key + 1 + index`, each a tap turning to
// its page; a tab list of tabs in the tree, the current selected. v2 (D973): the
// dots are 8 in `outline`, the current a 24 x 8 `primary` pill; the one control
// of the specification is `page_indicator_of`.
fn page_indicator(a: *mem.Arena, key: widget.Key, t: *const control.Theme, count: usize, current: usize, turn: widget.Change[usize]) -> (widget.Node, err) {
    if count == 0usize { ret (zero, TooLarge) }
    let (turns, turns_error) = mem.alloc[Turn](a, count)
    if turns_error != ok { ret (zero, TooLarge) }
    let (actions, actions_error) = mem.alloc[widget.Submit](a, count)
    if actions_error != ok { ret (zero, TooLarge) }
    let (dots, dots_error) = mem.alloc[widget.Node](a, count)
    if dots_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < count {
        turns[i] = Turn { index: i, turn: turn }
        actions[i] = widget.Submit { ctx: mem.cast[*void](&turns[i]), invoke: turn_fire }
        var dot = control.sized_style(8.0, 8.0)
        dot.radius = 4.0
        var tone: style.ColorRole = .Outline
        if i == current {
            tone = .Primary
            dot.width = style.Length { Px: 24.0 }
        }
        dot.background = paint.Brush { Solid: style.color(t.tokens, tone) }
        let (mark, mark_error) = mem.alloc[widget.Node](a, 1usize)
        if mark_error != ok { ret (zero, TooLarge) }
        mark[0usize] = widget.box(0u64, dot, zero)
        // The dot sits in the middle of a hit target a large space square.
        let (centred, centred_error) = mem.alloc[widget.Node](a, 1usize)
        if centred_error != ok { ret (zero, TooLarge) }
        centred[0usize] = widget.aligned(0u64, .Center, .Center, control.sized_style(t.tokens.spacing.lg, t.tokens.spacing.lg), mark[0usize..1usize])
        let (region, region_error) = mem.alloc[widget.Node](a, 1usize)
        if region_error != ok { ret (zero, TooLarge) }
        control.focus_look(t)
        region[0usize] = widget.region(key + 1u64 + u64(i), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&actions[i]), invoke: control.press_tap }, gestures: 1u8 | 4u8, enabled: true, focusable: true }, style.defaults(), centred[0usize..1usize])
        var sem: widget.Semantics = zero
        sem.role = 19u8
        sem.column = u32(i + 1usize)
        sem.column_count = u32(count)
        sem.actions = accessibility.ACTION_PRESS
        if i == current { sem.states = accessibility.STATE_SELECTED }
        dots[i] = widget.semantics(0u64, sem, style.defaults(), region[0usize..1usize])
        i += 1usize
    }
    let (row_node, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row_node[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Center, cross: .Center, gap: 0.0 }, style.defaults(), dots[0usize..count])
    var sem: widget.Semantics = zero
    sem.role = 20u8
    sem.column_count = u32(count)
    ret (widget.semantics(key, sem, style.defaults(), row_node[0usize..1usize]), ok)
}

// A page indicator's form (D973): on media (the dots on a 32 tall
// `surface-container-high` pill) and whether it may turn.
type IndicatorOptions = struct { on_media: bool, disabled: bool }

fn indicator_options() -> IndicatorOptions {
    var out: IndicatorOptions = zero
    ret out
}

// What a tap on the track knows (D973): where the track is, the current page,
// the count and where the current pill's middle stands from the track's start.
type Scrub = struct { runtime: *widget.Runtime, key: widget.Key, current: usize, count: usize, middle: f32, turn: widget.Change[usize] }

fn scrub_gesture(ctx: *void, g: widget.Gesture) -> err {
    let s = mem.cast[*Scrub](ctx)
    switch g {
    case .Tap as at:
        let (area, found) = control.keyed_bounds(s.runtime, s.key)
        if !found { ret ok }
        if at.x < area.x + s.middle {
            if s.current > 0usize { ret widget.fire_change[usize](s.turn, s.current - 1usize) }
            ret ok
        }
        if s.current + 1usize < s.count { ret widget.fire_change[usize](s.turn, s.current + 1usize) }
        ret ok
    default:
        ret ok
    }
}

// v2 (D973, docs/ux/components/PageIndicator): one control, a fully rounded track
// (keyed `key + 1`) 32 tall at pointer density (48 touch), 12 in at the sides
// (16 touch), under the `on-surface` state layer. Its dots are 8 circles in
// `outline` 8 apart, the current page a 24 x 8 `primary` pill; past seven pages
// seven show, the window sliding with the pill, the outermost dots 4 and 6
// where the set continues. On media the dots stand on a 32 tall
// `surface-container-high` pill 12 in. A tap before the pill steps back one
// page, after it forward one; Left, Right, Page Up and Page Down step, Home and
// End go to the ends. A slider named "Page", its value "Page 2 of 5", said
// politely. Disabled, the dots and pill are `on-surface` at 38% and the track
// takes no focus.
// ponytail: no drag to scrub, pill motion or right-to-left mirroring; the focus
// ring is the runtime's.
fn page_indicator_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, count: usize, current: usize, turn: widget.Change[usize], options: IndicatorOptions) -> (widget.Node, err) {
    if count == 0usize || current >= count { ret (zero, TooLarge) }
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    var h: f32 = 32.0
    var pad: f32 = 12.0
    if touch {
        h = 48.0
        pad = 16.0
    }
    let enabled = !options.disabled
    var shown = count
    var first = 0usize
    if count > 7usize {
        shown = 7usize
        if current > 3usize { first = current - 3usize }
        if first + 7usize > count { first = count - 7usize }
    }
    var dot_ink = style.color(t.tokens, .Outline)
    var pill_ink = style.color(t.tokens, .Primary)
    if !enabled {
        dot_ink = control.with_alpha(style.color(t.tokens, .OnSurface), t.tokens.states.disabled_content)
        pill_ink = dot_ink
    }
    var inner: f32 = 0.0
    if options.on_media { inner = 12.0 }
    let (dots, dots_error) = mem.alloc[widget.Node](a, shown)
    if dots_error != ok { ret (zero, TooLarge) }
    var middle = pad + inner
    var v = 0usize
    while v < shown {
        let page = first + v
        var size: f32 = 8.0
        if first > 0usize && v == 0usize { size = 4.0 }
        if first > 0usize && v == 1usize { size = 6.0 }
        if first + shown < count && v + 1usize == shown { size = 4.0 }
        if first + shown < count && v + 2usize == shown { size = 6.0 }
        var dot = control.sized_style(size, size)
        dot.radius = size * 0.5
        dot.background = paint.Brush { Solid: dot_ink }
        if page == current {
            dot = control.sized_style(24.0, 8.0)
            dot.radius = 4.0
            dot.background = paint.Brush { Solid: pill_ink }
            middle += 12.0
        }
        if page < current { middle += size + 8.0 }
        dots[v] = widget.box(0u64, dot, zero)
        v += 1usize
    }
    var row_style = style.defaults()
    row_style.height = style.Length { Px: h }
    if options.on_media {
        row_style.height = style.Length { Px: 32.0 }
        row_style.radius = 16.0
        row_style.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerHigh) }
        let sides = style.Length { Px: inner }
        let flat = style.Length { Px: 0.0 }
        row_style.padding = style.EdgeLengths { left: sides, top: flat, right: sides, bottom: flat }
    }
    let (rows, rows_error) = mem.alloc[widget.Node](a, 1usize)
    if rows_error != ok { ret (zero, TooLarge) }
    rows[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 8.0 }, row_style, dots[0usize..shown])
    if options.on_media {
        let (lifted, lifted_error) = mem.alloc[widget.Node](a, 1usize)
        if lifted_error != ok { ret (zero, TooLarge) }
        lifted[0usize] = rows[0usize]
        var band = style.defaults()
        band.height = style.Length { Px: h }
        rows[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, band, lifted[0usize..1usize])
    }
    let track_key = key + 1u64
    let state = control.control_state(t, track_key, enabled, false)
    var track = style.defaults()
    track.min_height = style.Length { Px: h }
    track.radius = h * 0.5
    track.background = paint.Brush { Solid: control.with_alpha(style.color(t.tokens, .OnSurface), control.state_opacity(t, state)) }
    let sides = style.Length { Px: pad }
    let flat = style.Length { Px: 0.0 }
    track.padding = style.EdgeLengths { left: sides, top: flat, right: sides, bottom: flat }
    let (scrubs, scrubs_error) = mem.alloc[Scrub](a, 1usize)
    if scrubs_error != ok { ret (zero, TooLarge) }
    scrubs[0usize] = Scrub { runtime: t.runtime, key: track_key, current: current, count: count, middle: middle, turn: turn }
    control.focus_look(t)
    let (regions, regions_error) = mem.alloc[widget.Node](a, 1usize)
    if regions_error != ok { ret (zero, TooLarge) }
    regions[0usize] = widget.region(track_key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&scrubs[0usize]), invoke: scrub_gesture }, gestures: 1u8, enabled: enabled, focusable: enabled }, track, rows[0usize..1usize])
    // The keys: Left, Right, Page Up and Page Down step, Home and End go to the
    // ends.
    let (turns, turns_error) = mem.alloc[Turn](a, 4usize)
    if turns_error != ok { ret (zero, TooLarge) }
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 6usize)
    if shortcuts_error != ok { ret (zero, TooLarge) }
    var bound = 0usize
    if enabled && current > 0usize {
        turns[0usize] = Turn { index: current - 1usize, turn: turn }
        turns[1usize] = Turn { index: 0usize, turn: turn }
        let back = widget.Submit { ctx: mem.cast[*void](&turns[0usize]), invoke: turn_fire }
        shortcuts[bound] = widget.Shortcut { key: 37u32, modifiers: zero, action: back }
        shortcuts[bound + 1usize] = widget.Shortcut { key: 33u32, modifiers: zero, action: back }
        shortcuts[bound + 2usize] = widget.Shortcut { key: 36u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&turns[1usize]), invoke: turn_fire } }
        bound += 3usize
    }
    if enabled && current + 1usize < count {
        turns[2usize] = Turn { index: current + 1usize, turn: turn }
        turns[3usize] = Turn { index: count - 1usize, turn: turn }
        let on = widget.Submit { ctx: mem.cast[*void](&turns[2usize]), invoke: turn_fire }
        shortcuts[bound] = widget.Shortcut { key: 39u32, modifiers: zero, action: on }
        shortcuts[bound + 1usize] = widget.Shortcut { key: 34u32, modifiers: zero, action: on }
        shortcuts[bound + 2usize] = widget.Shortcut { key: 35u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&turns[3usize]), invoke: turn_fire } }
        bound += 3usize
    }
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: shortcuts[0usize..bound], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), regions[0usize..1usize])
    // "Page 2 of 5".
    let (said, said_error) = mem.alloc[u8](a, 56usize)
    if said_error != ok { ret (zero, TooLarge) }
    var n = control.copy_text(said, "Page ")
    n += control.write_i64(said[n..56usize], i64(current + 1usize))
    n += control.copy_text(said[n..56usize], " of ")
    n += control.write_i64(said[n..56usize], i64(count))
    var sem: widget.Semantics = zero
    sem.role = 15u8
    sem.label = "Page"
    sem.value = said[0usize..n]
    sem.live = 1u8
    sem.actions = accessibility.ACTION_INCREMENT | accessibility.ACTION_DECREMENT
    if !enabled { sem.states = accessibility.STATE_DISABLED }
    ret (widget.semantics(key, sem, style.defaults(), scoped[0usize..1usize]), ok)
}

// Pagination: a Previous button (keyed `key + 1`), the page numbers around
// `current` -- `window` of them, as digits, the current selected -- keyed
// `key + 3 + index` by page index, and a Next button (`key + 2`), the two disabled
// at the ends; each turns through `turn`. A group in the tree named `label`. v2
// (D973): drawn as `paged` below, the pages named by their digits and the ends
// "Previous" and "Next"; the seven fixed slots of the specification are
// `pagination_of`.
fn pagination(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, count: usize, current: usize, window: usize, turn: widget.Change[usize]) -> (widget.Node, err) {
    if count == 0usize || current >= count || window == 0usize { ret (zero, TooLarge) }
    var first = 0usize
    if current > window / 2usize { first = current - window / 2usize }
    if first + window > count {
        if count > window { first = count - window } else { first = 0usize }
    }
    var shown = window
    if first + shown > count { shown = count - first }
    let (slots, slots_error) = mem.alloc[usize](a, shown)
    if slots_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < shown {
        slots[i] = first + i
        i += 1usize
    }
    let (made, made_error) = paged(a, key, t, label, count, current, slots[0usize..shown], turn, "Previous", "Next", false, false)
    ret (made, made_error)
}

// A pagination's form (D973): the Previous and Next names (empty: "Previous
// page" and "Next page"), and compact (Previous, "Page 12 of 24", Next).
type PaginationOptions = struct { previous_label: str, next_label: str, compact: bool }

fn pagination_options() -> PaginationOptions {
    var out: PaginationOptions = zero
    ret out
}

// v2 (D973, docs/ux/components/Pagination): seven fixed slots -- the first page,
// the last, the current and its two neighbours, an ellipsis for each gap, a page
// standing in for an ellipsis that would hide only one -- so the control keeps
// its width as the page moves; every page is named "Page 12".
fn pagination_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, count: usize, current: usize, turn: widget.Change[usize], options: PaginationOptions) -> (widget.Node, err) {
    if count == 0usize || current >= count { ret (zero, TooLarge) }
    var shown = count
    if count > 7usize { shown = 7usize }
    let (slots, slots_error) = mem.alloc[usize](a, shown)
    if slots_error != ok { ret (zero, TooLarge) }
    if count <= 7usize {
        var i = 0usize
        while i < count {
            slots[i] = i
            i += 1usize
        }
    } else {
        // An ellipsis is `count`, which no page is.
        slots[0usize] = 0usize
        slots[6usize] = count - 1usize
        if current <= 3usize {
            slots[1usize] = 1usize
            slots[2usize] = 2usize
            slots[3usize] = 3usize
            slots[4usize] = 4usize
            slots[5usize] = count
        } else {
            if current + 4usize >= count {
                slots[1usize] = count
                slots[2usize] = count - 5usize
                slots[3usize] = count - 4usize
                slots[4usize] = count - 3usize
                slots[5usize] = count - 2usize
            } else {
                slots[1usize] = count
                slots[2usize] = current - 1usize
                slots[3usize] = current
                slots[4usize] = current + 1usize
                slots[5usize] = count
            }
        }
    }
    var back = options.previous_label
    if back.len == 0usize { back = "Previous page" }
    var forward = options.next_label
    if forward.len == 0usize { forward = "Next page" }
    let (made, made_error) = paged(a, key, t, label, count, current, slots[0usize..shown], turn, back, forward, true, options.compact)
    ret (made, made_error)
}

// v2 (D973, docs/ux/components/Pagination): Previous (keyed `key + 1`) and Next
// (`key + 2`) are `chevron-left` and `chevron-right` icon buttons in
// `on-surface-variant`, `on-surface` at 38% and out of the Tab order at the ends;
// between them, 4 apart, the pages (keyed `key + 3 + index`) as round buttons 32
// across at pointer density (40 touch), 8 at the sides from three digits, their
// `label-large` numerals in `on-surface-variant` under the state layer, the
// current one `secondary-container` with `on-secondary-container` numerals,
// Selected and Current, and doing nothing when pressed; an ellipsis (a slot of
// `count`) is "…" 20 wide (24 touch) out of the tree. Compact, "Page 12 of 24" in
// `label-large` stands between the buttons. A group named `label` saying the
// current page of the count.
// ponytail: no table-footer variant (range and rows per page); compact keeps the
// icon buttons rather than text buttons; the focus ring is the runtime's.
fn paged(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, count: usize, current: usize, slots: []const usize, turn: widget.Change[usize], previous_label: str, next_label: str, named: bool, compact: bool) -> (widget.Node, err) {
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    var side = t.tokens.sizes.control_sm
    var glyph = t.tokens.sizes.icon_sm
    var gap_width: f32 = 20.0
    if touch {
        side = t.tokens.sizes.control_md
        glyph = t.tokens.sizes.icon_md
        gap_width = 24.0
    }
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    var idle: widget.Submit = zero
    let (turns, turns_error) = mem.alloc[Turn](a, slots.len + 2usize)
    if turns_error != ok { ret (zero, TooLarge) }
    let (actions, actions_error) = mem.alloc[widget.Submit](a, slots.len + 2usize)
    if actions_error != ok { ret (zero, TooLarge) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, slots.len + 3usize)
    if parts_error != ok { ret (zero, TooLarge) }
    var previous = current
    if current > 0usize { previous = current - 1usize }
    var next = current
    if current + 1usize < count { next = current + 1usize }
    turns[0usize] = Turn { index: previous, turn: turn }
    turns[1usize] = Turn { index: next, turn: turn }
    actions[0usize] = widget.Submit { ctx: mem.cast[*void](&turns[0usize]), invoke: turn_fire }
    actions[1usize] = widget.Submit { ctx: mem.cast[*void](&turns[1usize]), invoke: turn_fire }
    let (back_button, back_error) = control.glyph_action(a, key + 1u64, t, .ChevronLeft, previous_label, &actions[0usize], side, glyph, muted, current > 0usize, 0u32, 0u32, 0u64)
    if back_error != ok { ret (zero, back_error) }
    parts[0usize] = back_button
    var n = 1usize
    var caption = control.text_options()
    caption.role = .LabelLarge
    caption.wrap = .None
    if compact {
        let (said, said_error) = mem.alloc[u8](a, 56usize)
        if said_error != ok { ret (zero, TooLarge) }
        var m = control.copy_text(said, "Page ")
        m += control.write_i64(said[m..56usize], i64(current + 1usize))
        m += control.copy_text(said[m..56usize], " of ")
        m += control.write_i64(said[m..56usize], i64(count))
        let (words, words_error) = control.colored_text(a, 0u64, said[0usize..m], t, caption, muted)
        if words_error != ok { ret (zero, words_error) }
        parts[n] = words
        n += 1usize
    } else {
        var i = 0usize
        while i < slots.len {
            let page = slots[i]
            if page >= count {
                let (dots, dots_error) = control.colored_text(a, 0u64, "…", t, caption, muted)
                if dots_error != ok { ret (zero, dots_error) }
                let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
                if held_error != ok { ret (zero, TooLarge) }
                held[0usize] = dots
                let (hidden, hidden_error) = mem.alloc[widget.Node](a, 1usize)
                if hidden_error != ok { ret (zero, TooLarge) }
                hidden[0usize] = widget.aligned(0u64, .Center, .Center, control.sized_style(gap_width, side), held[0usize..1usize])
                var quiet: widget.Semantics = zero
                quiet.hidden = true
                parts[n] = widget.semantics(0u64, quiet, style.defaults(), hidden[0usize..1usize])
                n += 1usize
                i += 1usize
                continue
            }
            turns[2usize + i] = Turn { index: page, turn: turn }
            actions[2usize + i] = widget.Submit { ctx: mem.cast[*void](&turns[2usize + i]), invoke: turn_fire }
            let is_current = page == current
            if is_current { actions[2usize + i] = idle }
            let (digits, digits_error) = mem.alloc[u8](a, 26usize)
            if digits_error != ok { ret (zero, TooLarge) }
            let digit_count = control.write_i64(digits, i64(page + 1usize))
            var name = digits[0usize..digit_count]
            if named {
                let (words, words_error) = mem.alloc[u8](a, 26usize)
                if words_error != ok { ret (zero, TooLarge) }
                var m = control.copy_text(words, "Page ")
                m += control.copy_text(words[m..26usize], digits[0usize..digit_count])
                name = words[0usize..m]
            }
            let page_key = key + 3u64 + u64(page)
            let state = control.control_state(t, page_key, true, is_current)
            var ink = muted
            var look = style.resolve(t.tokens, .Plain, state)
            look.background = control.with_alpha(ink, control.state_opacity(t, state))
            if is_current {
                ink = style.color(t.tokens, .OnSecondaryContainer)
                look.background = style.layer(style.color(t.tokens, .SecondaryContainer), ink, control.state_opacity(t, state))
            }
            look.foreground = ink
            look.border_width = 0.0
            look.opacity = 1.0
            look.radius = side * 0.5
            look.custom_padding = true
            var sides: f32 = 0.0
            if digit_count >= 3usize { sides = 8.0 }
            look.padding = sides
            look.padding_y = 0.0
            look.min_width = side
            look.min_height = side
            let (numeral, numeral_error) = control.colored_text(a, 0u64, digits[0usize..digit_count], t, caption, ink)
            if numeral_error != ok { ret (zero, numeral_error) }
            let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
            if held_error != ok { ret (zero, TooLarge) }
            held[0usize] = numeral
            var centre = style.defaults()
            centre.min_width = style.Length { Px: control.max_zero(side - 2.0 * sides) }
            centre.height = style.Length { Px: side }
            let content = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Center, cross: .Center, gap: 0.0 }, centre, held[0usize..1usize])
            var states = 0u32
            if is_current { states = accessibility.STATE_CURRENT }
            let (numbered, numbered_error) = control.pressable_states(a, page_key, t, 3u8, name, look, true, is_current, states, 0u32, 0u64, &actions[2usize + i], content)
            if numbered_error != ok { ret (zero, numbered_error) }
            parts[n] = numbered
            n += 1usize
            i += 1usize
        }
    }
    let (next_button, next_error) = control.glyph_action(a, key + 2u64, t, .ChevronRight, next_label, &actions[1usize], side, glyph, muted, current + 1usize < count, 0u32, 0u32, 0u64)
    if next_error != ok { ret (zero, next_error) }
    parts[n] = next_button
    n += 1usize
    let (row_node, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row_node[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 4.0 }, style.defaults(), parts[0usize..n])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    sem.row = u32(current + 1usize)
    sem.row_count = u32(count)
    ret (widget.semantics(key, sem, style.defaults(), row_node[0usize..1usize]), ok)
}

// A carousel: a page view (keyed `key`) between a Previous button (`key + 1`)
// and a Next button (`key + 2`), the page indicator (`key + 3`, its dots
// `key + 4 + index`) below; every way of turning reaches the one `turn`.
fn carousel(a: *mem.Arena, key: widget.Key, t: *const control.Theme, pages: []const widget.Node, current: usize, turn: widget.Change[usize], width: f32, height: f32) -> (widget.Node, err) {
    if pages.len == 0usize || current >= pages.len { ret (zero, TooLarge) }
    let (view, view_error) = page_view(a, key, t, pages, current, turn, width, height)
    if view_error != ok { ret (zero, view_error) }
    let (turns, turns_error) = mem.alloc[Turn](a, 2usize)
    if turns_error != ok { ret (zero, TooLarge) }
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 2usize)
    if actions_error != ok { ret (zero, TooLarge) }
    var previous = current
    if current > 0usize { previous = current - 1usize }
    var next = current
    if current + 1usize < pages.len { next = current + 1usize }
    turns[0usize] = Turn { index: previous, turn: turn }
    turns[1usize] = Turn { index: next, turn: turn }
    actions[0usize] = widget.Submit { ctx: mem.cast[*void](&turns[0usize]), invoke: turn_fire }
    actions[1usize] = widget.Submit { ctx: mem.cast[*void](&turns[1usize]), invoke: turn_fire }
    var back = control.button_options()
    back.variant = .Plain
    back.enabled = current > 0usize
    let (back_button, back_error) = control.button(a, key + 1u64, t, "<", &actions[0usize], back)
    if back_error != ok { ret (zero, back_error) }
    var forward = control.button_options()
    forward.variant = .Plain
    forward.enabled = current + 1usize < pages.len
    let (next_button, next_error) = control.button(a, key + 2u64, t, ">", &actions[1usize], forward)
    if next_error != ok { ret (zero, next_error) }
    let (across, across_error) = mem.alloc[widget.Node](a, 3usize)
    if across_error != ok { ret (zero, TooLarge) }
    across[0usize] = back_button
    across[1usize] = view
    across[2usize] = next_button
    let (dots, dots_error) = page_indicator(a, key + 3u64, t, pages.len, current, turn)
    if dots_error != ok { ret (zero, dots_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: t.tokens.spacing.xs }, style.defaults(), across[0usize..3usize])
    parts[1usize] = dots
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Center, gap: t.tokens.spacing.xs }, style.defaults(), parts[0usize..2usize]), ok)
}

// ------------------------------------------------ collection interaction (D839, P2-07)

// The swipe cell of the element under `key` from the frame before, if there is one
// (D835): what a drag that must act once keeps across the frames it lasts.
fn swipe_cell(t: *const control.Theme, key: widget.Key) -> (*Swipe, bool) {
    var none: *Swipe = zero
    let (s, state_error) = widget.state_of(t.runtime)
    if state_error != ok { ret (none, false) }
    let (id, found) = widget.find_by_key(s, key)
    if found != 1usize { ret (none, false) }
    var build = widget.BuildContext { runtime: t.runtime, element: id, frame: 0u64 }
    let (kept, _, kept_error) = widget.state[Swipe](&build, key, Swipe { turned: false, moved: 0.0 })
    if kept_error != ok { ret (none, false) }
    ret (kept, true)
}

// A move of a row from one index to another, the explicit action a reorder is.
type Reorder = struct { from: usize, to: usize }

// A row's drag in a reorderable list: which row, how many, how tall each, where
// the list is (by key), and whom to tell on the drop.
// (D982) The cell keeps how far the row has been dragged, so the list can draw
// it lifted where the pointer holds it.
type Dragging = struct { runtime: *widget.Runtime, list: widget.Key, index: usize, count: usize, extent: f32, move: widget.Change[Reorder], cell: *Swipe, has_cell: bool }

fn reorder_drag(ctx: *void, g: widget.Gesture) -> err {
    let d = mem.cast[*Dragging](ctx)
    switch g {
    case .DragStart as at:
        if d.has_cell { d.cell.moved = 0.0 }
        ret ok
    case .DragMove as dm:
        if d.has_cell { d.cell.moved = dm.position.y - dm.start.y }
        ret ok
    case .DragEnd as at:
        if d.has_cell { d.cell.moved = 0.0 }
        let (area, has_area) = keyed_bounds_of(d.runtime, d.list)
        if !has_area || d.extent <= 0.0 { ret ok }
        var to = 0usize
        if at.y > area.y { to = usize((at.y - area.y) / d.extent) }
        if to >= d.count { to = d.count - 1usize }
        if to == d.index { ret ok }
        ret widget.fire_change[Reorder](d.move, Reorder { from: d.index, to: to })
    default:
        ret ok
    }
}

// A keyboard move of a row by one.
type Nudging = struct { index: usize, count: usize, up: bool, move: widget.Change[Reorder] }

fn reorder_nudge(ctx: *void) -> err {
    let n = mem.cast[*Nudging](ctx)
    if n.up {
        if n.index == 0usize { ret ok }
        ret widget.fire_change[Reorder](n.move, Reorder { from: n.index, to: n.index - 1usize })
    }
    if n.index + 1usize >= n.count { ret ok }
    ret widget.fire_change[Reorder](n.move, Reorder { from: n.index, to: n.index + 1usize })
}

fn keyed_bounds_of(runtime: *widget.Runtime, key: widget.Key) -> (geometry.Rect, bool) {
    let (s, state_error) = widget.state_of(runtime)
    if state_error != ok { ret (zero, false) }
    let (id, count) = widget.find_by_key(s, key)
    if count == 0usize { ret (zero, false) }
    let (area, has_area) = widget.bounds_of(runtime, id)
    ret (area, has_area)
}

// A reorderable list: the caller's rows, `extent` tall each, in a column `width`
// wide (keyed `key`); a row (keyed by its key) is a focusable drag region whose
// drop reports the move from its index to the row under the pointer, and Alt+Up
// and Alt+Down from the focused row report a move by one; the caller reorders
// its model and rebuilds. A list of list items in the tree named `label`.
fn reorderable_list(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, items: []const widget.Node, keys: []const widget.Key, extent: f32, move: widget.Change[Reorder], width: f32) -> (widget.Node, err) {
    if keys.len != items.len || extent <= 0.0 { ret (zero, TooLarge) }
    let (rows, rows_error) = mem.alloc[widget.Node](a, items.len)
    if rows_error != ok { ret (zero, TooLarge) }
    let (drags, drags_error) = mem.alloc[Dragging](a, items.len)
    if drags_error != ok { ret (zero, TooLarge) }
    let (nudges, nudges_error) = mem.alloc[Nudging](a, 2usize * items.len)
    if nudges_error != ok { ret (zero, TooLarge) }
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 2usize * items.len)
    if shortcuts_error != ok { ret (zero, TooLarge) }
    var held: input.Modifiers = zero
    held.alt = true
    var i = 0usize
    while i < items.len {
        var no_cell_yet: *Swipe = zero
        drags[i] = Dragging { runtime: t.runtime, list: key, index: i, count: items.len, extent: extent, move: move, cell: no_cell_yet, has_cell: false }
        nudges[2usize * i] = Nudging { index: i, count: items.len, up: true, move: move }
        nudges[2usize * i + 1usize] = Nudging { index: i, count: items.len, up: false, move: move }
        shortcuts[2usize * i] = widget.Shortcut { key: 38u32, modifiers: held, action: widget.Submit { ctx: mem.cast[*void](&nudges[2usize * i]), invoke: reorder_nudge } }
        shortcuts[2usize * i + 1usize] = widget.Shortcut { key: 40u32, modifiers: held, action: widget.Submit { ctx: mem.cast[*void](&nudges[2usize * i + 1usize]), invoke: reorder_nudge } }
        let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
        if body_error != ok { ret (zero, TooLarge) }
        body[0usize] = items[i]
        var row_style = style.defaults()
        row_style.width = style.Length { Px: width }
        row_style.height = style.Length { Px: extent }
        let (region, region_error) = mem.alloc[widget.Node](a, 1usize)
        if region_error != ok { ret (zero, TooLarge) }
        control.focus_look(t)
        region[0usize] = widget.region(keys[i], widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&drags[i]), invoke: reorder_drag }, gestures: 2u8 | 4u8, enabled: true, focusable: true }, row_style, body[0usize..1usize])
        let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
        if scoped_error != ok { ret (zero, TooLarge) }
        scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: shortcuts[2usize * i..2usize * i + 2usize], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), region[0usize..1usize])
        var sem: widget.Semantics = zero
        sem.role = 11u8
        sem.row = u32(i + 1usize)
        sem.row_count = u32(items.len)
        rows[i] = widget.semantics(0u64, sem, style.defaults(), scoped[0usize..1usize])
        i += 1usize
    }
    var column_style = style.defaults()
    column_style.width = style.Length { Px: width }
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(key, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, column_style, rows[0usize..items.len])
    var sem: widget.Semantics = zero
    sem.role = 10u8
    sem.label = label
    sem.row_count = u32(items.len)
    ret (widget.semantics(0u64, sem, style.defaults(), column[0usize..1usize]), ok)
}

// A pull's drag: the swipe cell, how far down counts, and whom to tell; (D982)
// settling, the drag records the damped pull and the release past the threshold
// refreshes.
type Pulling = struct { cell: *Swipe, has_cell: bool, threshold: f32, refresh: widget.Submit, settle: bool }

// The pull the content shows for a finger's travel (D982): one for one to 40,
// half past it, no more than 120.
fn damped_pull(travel: f32) -> f32 {
    if travel <= 0.0 { ret 0.0 }
    var out = travel
    if out > 40.0 { out = 40.0 + (out - 40.0) * 0.5 }
    if out > 120.0 { out = 120.0 }
    ret out
}

fn pull_drag(ctx: *void, g: widget.Gesture) -> err {
    let p = mem.cast[*Pulling](ctx)
    switch g {
    case .DragStart as at:
        if p.has_cell {
            p.cell.turned = false
            p.cell.moved = 0.0
        }
        ret ok
    case .DragMove as d:
        if !p.has_cell { ret ok }
        if p.settle {
            p.cell.moved = damped_pull(d.position.y - d.start.y)
            ret ok
        }
        if p.cell.turned { ret ok }
        if d.position.y - d.start.y > p.threshold {
            p.cell.turned = true
            ret widget.fire_submit(p.refresh)
        }
        ret ok
    case .DragEnd as at:
        if !p.has_cell { ret ok }
        p.cell.turned = false
        let pulled = p.cell.moved
        p.cell.moved = 0.0
        if p.settle && pulled >= p.threshold { ret widget.fire_submit(p.refresh) }
        ret ok
    default:
        ret ok
    }
}

// Pull to refresh: the content in a box `width` by `height` (keyed `key`) that a
// drag down past a third of the height refreshes, once per pull; while
// `refreshing`, an indeterminate progress ring stands over the top of it; a
// Refresh button (keyed `key + 1`) is the same action for a keyboard or a
// pointer. A group in the tree, busy while refreshing.
fn pull_to_refresh(a: *mem.Arena, key: widget.Key, t: *const control.Theme, content: widget.Node, refreshing: bool, refresh: *const widget.Submit, width: f32, height: f32) -> (widget.Node, err) {
    let (pulls, pulls_error) = mem.alloc[Pulling](a, 1usize)
    if pulls_error != ok { ret (zero, TooLarge) }
    let (kept, has_cell) = swipe_cell(t, key)
    pulls[0usize] = Pulling { cell: kept, has_cell: has_cell, threshold: height / 3.0, refresh: *refresh, settle: false }
    var count = 2usize
    if refreshing { count = 3usize }
    let (parts, parts_error) = mem.alloc[widget.Node](a, count)
    if parts_error != ok { ret (zero, TooLarge) }
    var plain = control.button_options()
    plain.variant = .Plain
    let (again, again_error) = control.button(a, key + 1u64, t, "Refresh", refresh, plain)
    if again_error != ok { ret (zero, again_error) }
    parts[0usize] = again
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = content
    var view_style = control.sized_style(width, height)
    view_style.overflow = .Clip
    parts[1usize] = widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&pulls[0usize]), invoke: pull_drag }, gestures: 2u8, enabled: true, focusable: false }, view_style, body[0usize..1usize])
    if refreshing {
        let (ring, ring_error) = control.progress_ring(a, key + 2u64, t, "Refreshing", 0.0, true, t.tokens.metrics.control_height)
        if ring_error != ok { ret (zero, ring_error) }
        let (lifted, lifted_error) = mem.alloc[widget.Node](a, 1usize)
        if lifted_error != ok { ret (zero, TooLarge) }
        lifted[0usize] = ring
        parts[2usize] = widget.overlay(key + 3u64, widget.Overlay { anchor: key, placement: .Below, offset: geometry.Point { x: (width - t.tokens.metrics.control_height) * 0.5, y: 0.0 - height }, modal: false, dismiss: zero }, style.defaults(), lifted[0usize..1usize])
    }
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..count])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    if refreshing { sem.states = accessibility.STATE_BUSY }
    ret (widget.semantics(0u64, sem, style.defaults(), column[0usize..1usize]), ok)
}

// A row's horizontal swipe: the cell, how far counts, and whom to tell whether
// the actions are revealed; (D982) settling, the drag moves the row and the
// release opens past `threshold`, closes, runs the leading action past it the
// other way, or runs the outermost action past `full`.
type Revealing = struct { cell: *Swipe, has_cell: bool, threshold: f32, reveal: widget.Change[bool], settle: bool, revealed: bool, full: f32, outer: widget.Submit, has_outer: bool, lead: widget.Submit, has_lead: bool }

fn reveal_drag(ctx: *void, g: widget.Gesture) -> err {
    let r = mem.cast[*Revealing](ctx)
    switch g {
    case .DragStart as at:
        if r.has_cell {
            r.cell.turned = false
            r.cell.moved = 0.0
        }
        ret ok
    case .DragMove as d:
        if !r.has_cell { ret ok }
        if r.settle {
            r.cell.moved = d.position.x - d.start.x
            ret ok
        }
        if r.cell.turned { ret ok }
        let moved = d.position.x - d.start.x
        if moved < 0.0 - r.threshold {
            r.cell.turned = true
            ret widget.fire_change[bool](r.reveal, true)
        }
        if moved > r.threshold {
            r.cell.turned = true
            ret widget.fire_change[bool](r.reveal, false)
        }
        ret ok
    case .DragEnd as at:
        if !r.has_cell { ret ok }
        r.cell.turned = false
        let moved = r.cell.moved
        r.cell.moved = 0.0
        if !r.settle { ret ok }
        if r.has_outer && moved < 0.0 - r.full {
            let ran = widget.fire_submit(r.outer)
            if ran != ok { ret ran }
            ret widget.fire_change[bool](r.reveal, false)
        }
        if !r.revealed && moved < 0.0 - r.threshold { ret widget.fire_change[bool](r.reveal, true) }
        if r.revealed && moved > r.threshold { ret widget.fire_change[bool](r.reveal, false) }
        if !r.revealed && r.has_lead && moved > 32.0 { ret widget.fire_submit(r.lead) }
        ret ok
    default:
        ret ok
    }
}

// Swipe actions: a row's content (keyed `key`, a drag region) with `labels`'
// actions revealed at its end while `revealed`: a swipe left past a quarter of
// the width reveals, a swipe right hides, once per swipe, through `reveal`; a
// More button (keyed `key + 1`) reveals for a keyboard or a pointer; the actions
// are buttons keyed `key + 2 + index`. A list item in the tree.
fn swipe_actions(a: *mem.Arena, key: widget.Key, t: *const control.Theme, content: widget.Node, labels: []const str, actions: []const widget.Submit, revealed: bool, reveal: widget.Change[bool], width: f32, height: f32) -> (widget.Node, err) {
    if labels.len != actions.len { ret (zero, TooLarge) }
    let (reveals, reveals_error) = mem.alloc[Revealing](a, 1usize)
    if reveals_error != ok { ret (zero, TooLarge) }
    let (kept, has_cell) = swipe_cell(t, key)
    reveals[0usize] = Revealing { cell: kept, has_cell: has_cell, threshold: width * 0.25, reveal: reveal, settle: false, revealed: revealed, full: 0.0, outer: zero, has_outer: false, lead: zero, has_lead: false }
    var count = 2usize
    if revealed { count = 1usize + labels.len }
    let (parts, parts_error) = mem.alloc[widget.Node](a, count)
    if parts_error != ok { ret (zero, TooLarge) }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = content
    var row_style = style.defaults()
    row_style.width = style.Length { Flex: 1.0 }
    row_style.height = style.Length { Px: height }
    row_style.overflow = .Clip
    parts[0usize] = widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: ctx_of(&reveals[0usize]), invoke: reveal_drag }, gestures: 2u8, enabled: true, focusable: false }, row_style, body[0usize..1usize])
    if revealed {
        var i = 0usize
        while i < labels.len {
            let (act, act_error) = control.button(a, key + 2u64 + u64(i), t, labels[i], &actions[i], control.button_options())
            if act_error != ok { ret (zero, act_error) }
            parts[1usize + i] = act
            i += 1usize
        }
    } else {
        let (more_actions, more_error) = mem.alloc[widget.Submit](a, 1usize)
        if more_error != ok { ret (zero, TooLarge) }
        let (opens, opens_error) = mem.alloc[RevealSet](a, 1usize)
        if opens_error != ok { ret (zero, TooLarge) }
        opens[0usize] = RevealSet { value: true, reveal: reveal }
        more_actions[0usize] = widget.Submit { ctx: ctx_of(&opens[0usize]), invoke: reveal_set_fire }
        var plain = control.button_options()
        plain.variant = .Plain
        let (more, more_button_error) = control.button(a, key + 1u64, t, "More", &more_actions[0usize], plain)
        if more_button_error != ok { ret (zero, more_button_error) }
        parts[1usize] = more
    }
    let (row_node, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    var strip = style.defaults()
    strip.width = style.Length { Px: width }
    row_node[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Stretch, gap: 0.0 }, strip, parts[0usize..count])
    var sem: widget.Semantics = zero
    sem.role = 11u8
    if revealed { sem.states = accessibility.STATE_EXPANDED }
    ret (widget.semantics(0u64, sem, style.defaults(), row_node[0usize..1usize]), ok)
}


// ------------------------------------------------------ rich tabular data (D845, P3-01)

// A column of a table: its title and its width.
type Column = struct { title: str, width: f32 }

// A table's source: the row count, a row's stable key, and one cell built into
// the arena (the row by index, the column by index).
type TableSource = struct { ctx: *void, count: fn(*void) -> usize, key: fn(*void, usize) -> widget.Key, cell: fn(*void, *mem.Arena, usize, usize, *widget.Node) -> err }

// A column resized: which and to what.
type ColumnResize = struct { column: usize, width: f32 }

// A header's gestures: a tap asks to sort by its column, a drag begins a reorder
// carrying the column (D844), a drop of another's ends one.
type HeaderDrag = struct { runtime: *widget.Runtime, column: usize, sort: widget.Change[usize], reorder: widget.Change[Reorder] }

fn header_gesture(ctx: *void, g: widget.Gesture) -> err {
    let h = mem.cast[*HeaderDrag](ctx)
    switch g {
    case .Tap as at:
        ret widget.fire_change[usize](h.sort, h.column)
    case .DragStart as at:
        ret widget.begin_drag(h.runtime, u64(h.column) + 1u64)
    case .Drop as d:
        if d.payload == 0u64 || usize(d.payload - 1u64) == h.column { ret ok }
        ret widget.fire_change[Reorder](h.reorder, Reorder { from: usize(d.payload - 1u64), to: h.column })
    default:
        ret ok
    }
}

type Resizing = struct { runtime: *widget.Runtime, header: widget.Key, column: usize, low: f32, resize: widget.Change[ColumnResize] }

fn resize_drag(ctx: *void, g: widget.Gesture) -> err {
    let r = mem.cast[*Resizing](ctx)
    switch g {
    case .DragMove as d:
        let (area, has_area) = keyed_bounds_of(r.runtime, r.header)
        if !has_area { ret ok }
        var width = d.position.x - area.x
        if width < r.low { width = r.low }
        ret widget.fire_change[ColumnResize](r.resize, ColumnResize { column: r.column, width: width })
    default:
        ret ok
    }
}

// The header row: a column header a column (keyed `key + 1 + index`), a tap
// reporting the column through `sort` and a drag of one dropped on another
// reporting a `Reorder`; the sorted column marked with its direction; a resize
// handle after each (keyed `key + 64 + index`) whose drag reports the width.
fn header_row(a: *mem.Arena, key: widget.Key, t: *const control.Theme, columns: []const Column, sort_column: usize, descending: bool, sort: widget.Change[usize], reorder: widget.Change[Reorder], resize: widget.Change[ColumnResize]) -> (widget.Node, err) {
    let (made, made_error) = header_cells(a, key, t, columns, sort_column, descending, sort, reorder, resize, header_height(t), cell_padding(t), 0.0)
    ret (made, made_error)
}

// A table's header height (D980): 56 on touch, 48 with a pointer, 40 dense.
fn header_height(t: *const control.Theme) -> f32 {
    let d = density_of(t)
    if d == 2usize { ret 56.0 }
    if d == 0usize { ret 40.0 }
    ret 48.0
}

// A table's row height (D980): 48 on touch, 40 with a pointer, 32 dense.
fn table_row_height(t: *const control.Theme) -> f32 {
    let d = density_of(t)
    if d == 2usize { ret 48.0 }
    if d == 0usize { ret 32.0 }
    ret 40.0
}

// A table cell's side padding (D980): 16, 12 dense.
fn cell_padding(t: *const control.Theme) -> f32 {
    if density_of(t) == 0usize { ret 12.0 }
    ret 16.0
}

// v2 (D980, docs/ux/components/HeaderRow): a `surface-container` row `height`
// tall over a 1px `outline-variant` line, `lead` blank on
// `surface-container-low` first (a data grid's row numbers); a header cell a
// column, `pad` in at the sides, its `title-small` title in
// `on-surface-variant` (`on-surface` when sorted) with an 18 `arrow-up` or
// `arrow-down` 4 after it when sorted (a faint one at 50% on hover), under the
// `on-surface` state layer; after each an 8 wide resize handle drawing a 1px
// `outline-variant` line inset 12 top and bottom (8 when `height` is 40), a
// full-height 3px `primary` bar while hovered or dragged.
// ponytail: no numeric (end-aligned) columns, filter mark, select-all
// checkbox, grouped tier, keyboard resizing, reorder lift or aria-sort; the
// handles keep their `key + 64 + index` keys.
fn header_cells(a: *mem.Arena, key: widget.Key, t: *const control.Theme, columns: []const Column, sort_column: usize, descending: bool, sort: widget.Change[usize], reorder: widget.Change[Reorder], resize: widget.Change[ColumnResize], height: f32, pad: f32, lead: f32) -> (widget.Node, err) {
    let (cells, cells_error) = mem.alloc[widget.Node](a, 2usize * columns.len + 1usize)
    if cells_error != ok { ret (zero, TooLarge) }
    let (drags, drags_error) = mem.alloc[HeaderDrag](a, columns.len)
    if drags_error != ok { ret (zero, TooLarge) }
    let (resizes, resizes_error) = mem.alloc[Resizing](a, columns.len)
    if resizes_error != ok { ret (zero, TooLarge) }
    let grip: f32 = 8.0
    let inner = height - t.tokens.sizes.divider
    let inset = control.if_else(height <= 40.0, 8.0, 12.0)
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    let strong = style.color(t.tokens, .OnSurface)
    var n = 0usize
    if lead > 0.0 {
        var corner = control.sized_style(lead, inner)
        corner.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerLow) }
        cells[n] = widget.box(0u64, corner, zero)
        n += 1usize
    }
    var i = 0usize
    while i < columns.len {
        let header_key = key + 1u64 + u64(i)
        drags[i] = HeaderDrag { runtime: t.runtime, column: i, sort: sort, reorder: reorder }
        resizes[i] = Resizing { runtime: t.runtime, header: header_key, column: i, low: 2.0 * t.tokens.spacing.lg, resize: resize }
        let state = control.control_state(t, header_key, true, false)
        let sorted = i == sort_column
        var caption = control.text_options()
        caption.role = .TitleSmall
        caption.wrap = .None
        caption.ellipsis = "…"
        caption.max_lines = 1u32
        var ink = muted
        if sorted { ink = strong }
        let (title_node, title_node_error) = control.colored_text(a, 0u64, columns[i].title, t, caption, ink)
        if title_node_error != ok { ret (zero, title_node_error) }
        let (body, body_error) = mem.alloc[widget.Node](a, 2usize)
        if body_error != ok { ret (zero, TooLarge) }
        body[0usize] = title_node
        var b = 1usize
        if sorted || state.hovered {
            var kind: control.GlyphKind = .ArrowUp
            if sorted && descending { kind = .ArrowDown }
            if !sorted { ink = control.with_alpha(muted, 0.5) }
            let (arrow, arrow_error) = control.icon_square(a, ink, kind, t.tokens.sizes.icon_sm)
            if arrow_error != ok { ret (zero, arrow_error) }
            body[1usize] = arrow
            b = 2usize
        }
        var line_style = style.defaults()
        line_style.height = style.Length { Flex: 1.0 }
        let (content, content_error) = mem.alloc[widget.Node](a, 1usize)
        if content_error != ok { ret (zero, TooLarge) }
        content[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 4.0 }, line_style, body[0usize..b])
        // A tap sorts; a drag begins a reorder; a drop on it ends one.
        var head_style = control.sized_style(control.max_zero(columns[i].width - grip), inner)
        head_style.background = paint.Brush { Solid: control.with_alpha(strong, control.state_opacity(t, state)) }
        let sides = style.Length { Px: pad }
        let flat = style.Length { Px: 0.0 }
        head_style.padding = style.EdgeLengths { left: sides, top: flat, right: sides, bottom: flat }
        head_style.overflow = .Clip
        let (tapped, tapped_error) = mem.alloc[widget.Node](a, 1usize)
        if tapped_error != ok { ret (zero, TooLarge) }
        control.focus_look(t)
        tapped[0usize] = widget.region(header_key, widget.Region { gesture: widget.GestureAction { ctx: ctx_of(&drags[i]), invoke: header_gesture }, gestures: 1u8 | 2u8 | 4u8 | 8u8, enabled: true, focusable: true }, head_style, content[0usize..1usize])
        var sem: widget.Semantics = zero
        sem.role = 32u8
        sem.label = columns[i].title
        sem.column = u32(i + 1usize)
        sem.column_count = u32(columns.len)
        sem.actions = accessibility.ACTION_PRESS
        if sorted { sem.states = accessibility.STATE_SELECTED }
        cells[n] = widget.semantics(0u64, sem, style.defaults(), tapped[0usize..1usize])
        n += 1usize
        // The resize handle: a 1px line, or the 3px `primary` bar while hovered
        // or dragged.
        let grip_key = key + 64u64 + u64(i)
        let grip_state = control.control_state(t, grip_key, true, false)
        let active = grip_state.hovered || grip_state.pressed
        var mark = control.sized_style(1.0, control.max_zero(inner - 2.0 * inset))
        mark.background = paint.Brush { Solid: style.color(t.tokens, .OutlineVariant) }
        mark.margin = style.EdgeLengths { left: style.Length { Px: 3.0 }, top: style.Length { Px: inset }, right: flat, bottom: flat }
        if active {
            mark = control.sized_style(3.0, inner)
            mark.background = paint.Brush { Solid: style.color(t.tokens, .Primary) }
            mark.margin = style.EdgeLengths { left: style.Length { Px: 2.0 }, top: flat, right: flat, bottom: flat }
        }
        let (drawn, drawn_error) = mem.alloc[widget.Node](a, 1usize)
        if drawn_error != ok { ret (zero, TooLarge) }
        drawn[0usize] = widget.box(0u64, mark, zero)
        cells[n] = widget.region(grip_key, widget.Region { gesture: widget.GestureAction { ctx: ctx_of(&resizes[i]), invoke: resize_drag }, gestures: 2u8 | 4u8, enabled: true, focusable: false }, control.sized_style(grip, inner), drawn[0usize..1usize])
        n += 1usize
        i += 1usize
    }
    var band = style.defaults()
    band.height = style.Length { Px: inner }
    band.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainer) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Stretch, gap: 0.0 }, band, cells[0usize..n])
    var rule = style.defaults()
    rule.height = style.Length { Px: t.tokens.sizes.divider }
    rule.background = paint.Brush { Solid: style.color(t.tokens, .OutlineVariant) }
    parts[1usize] = widget.box(0u64, rule, zero)
    let (row_node, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row_node[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, style.defaults(), parts[0usize..2usize])
    var sem: widget.Semantics = zero
    sem.role = 13u8
    ret (widget.semantics(0u64, sem, style.defaults(), row_node[0usize..1usize]), ok)
}

// A row's tap reporting its key.
type RowPick = struct { key: widget.Key, pick: widget.Change[widget.Key] }

fn row_pick_gesture(ctx: *void, g: widget.Gesture) -> err {
    if g.tag != .Tap { ret ok }
    let r = mem.cast[*RowPick](ctx)
    ret widget.fire_change[widget.Key](r.pick, r.key)
}

// One row of cells `extent` tall: the cells sized by their columns in a row, the
// row a focusable tap region keyed by the row's key reporting it through `pick`,
// selected in the selection colour; a row of cells in the tree at `index`.
fn table_row(a: *mem.Arena, t: *const control.Theme, columns: []const Column, cells: []const widget.Node, row_key: widget.Key, index: usize, count: usize, extent: f32, selected: bool, pick: widget.Change[widget.Key], role: u8) -> (widget.Node, err) {
    let (made, made_error) = table_row_of(a, t, columns, cells, row_key, index, count, extent, selected, pick, role, cell_padding(t), false, false)
    ret (made, made_error)
}

// v2 (D980, docs/ux/components/TableRow): the cells at their columns' widths,
// `pad` in at the sides with their content centred in the height, under the
// `on-surface` state layer over the whole row; selected, the row is
// `secondary-container` (its layer `on-secondary-container`). A data grid's row
// (`grid`) starts with its 40 wide row number in `label-medium`
// `on-surface-variant` on `surface-container-low`, end-aligned 8 in, and has a
// 1px `outline-variant` line after every cell. The focus ring is the runtime's,
// inset where the viewport clips it.
// ponytail: no selection checkbox column, disclosure and detail row, hover row
// actions, disabled, dragged or loading looks; the caller's cells keep their
// own colours when the row is selected.
fn table_row_of(a: *mem.Arena, t: *const control.Theme, columns: []const Column, cells: []const widget.Node, row_key: widget.Key, index: usize, count: usize, extent: f32, selected: bool, pick: widget.Change[widget.Key], role: u8, pad: f32, grid: bool, owned: bool) -> (widget.Node, err) {
    let (boxed, boxed_error) = mem.alloc[widget.Node](a, 2usize * columns.len + 1usize)
    if boxed_error != ok { ret (zero, TooLarge) }
    let sides = style.Length { Px: pad }
    let flat = style.Length { Px: 0.0 }
    let rule = style.color(t.tokens, .OutlineVariant)
    var n = 0usize
    if grid {
        let (digits, digits_error) = mem.alloc[u8](a, 24usize)
        if digits_error != ok { ret (zero, TooLarge) }
        let digit_count = control.write_i64(digits, i64(index + 1usize))
        var caption = control.text_options()
        caption.role = .LabelMedium
        caption.wrap = .None
        let (number, number_error) = control.colored_text(a, 0u64, digits[0usize..digit_count], t, caption, style.color(t.tokens, .OnSurfaceVariant))
        if number_error != ok { ret (zero, number_error) }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (zero, TooLarge) }
        held[0usize] = number
        var numbered = control.sized_style(40.0, extent)
        numbered.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerLow) }
        numbered.padding = style.EdgeLengths { left: flat, top: flat, right: style.Length { Px: 8.0 }, bottom: flat }
        boxed[n] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .End, cross: .Center, gap: 0.0 }, numbered, held[0usize..1usize])
        n += 1usize
    }
    var c = 0usize
    while c < columns.len {
        let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
        if body_error != ok { ret (zero, TooLarge) }
        body[0usize] = cells[c]
        var width = columns[c].width
        if grid { width -= t.tokens.sizes.divider }
        var cell_style = control.sized_style(control.max_zero(width), extent)
        cell_style.overflow = .Clip
        cell_style.padding = style.EdgeLengths { left: sides, top: flat, right: sides, bottom: flat }
        let (framed, framed_error) = mem.alloc[widget.Node](a, 1usize)
        if framed_error != ok { ret (zero, TooLarge) }
        framed[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Center, cross: .Start, gap: 0.0 }, cell_style, body[0usize..1usize])
        var cell_sem: widget.Semantics = zero
        cell_sem.role = 14u8
        cell_sem.row = u32(index + 1usize)
        cell_sem.column = u32(c + 1usize)
        boxed[n] = widget.semantics(0u64, cell_sem, style.defaults(), framed[0usize..1usize])
        n += 1usize
        if grid {
            var line = control.sized_style(t.tokens.sizes.divider, extent)
            line.background = paint.Brush { Solid: rule }
            boxed[n] = widget.box(0u64, line, zero)
            n += 1usize
        }
        c += 1usize
    }
    let (picks, picks_error) = mem.alloc[RowPick](a, 1usize)
    if picks_error != ok { ret (zero, TooLarge) }
    picks[0usize] = RowPick { key: row_key, pick: pick }
    let state = control.control_state(t, row_key, true, selected)
    var fill = control.with_alpha(style.color(t.tokens, .OnSurface), control.state_opacity(t, state))
    if selected { fill = style.layer(style.color(t.tokens, .SecondaryContainer), style.color(t.tokens, .OnSecondaryContainer), control.state_opacity(t, state)) }
    var row_style = style.defaults()
    row_style.height = style.Length { Px: extent }
    row_style.background = paint.Brush { Solid: fill }
    let (lined, lined_error) = mem.alloc[widget.Node](a, 1usize)
    if lined_error != ok { ret (zero, TooLarge) }
    lined[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Stretch, gap: 0.0 }, style.defaults(), boxed[0usize..n])
    let (region, region_error) = mem.alloc[widget.Node](a, 1usize)
    if region_error != ok { ret (zero, TooLarge) }
    control.focus_look(t)
    var gestures = 5u8
    if owned { gestures = 4u8 }
    region[0usize] = widget.region(row_key, widget.Region { gesture: widget.GestureAction { ctx: ctx_of(&picks[0usize]), invoke: row_pick_gesture }, gestures: gestures, enabled: true, focusable: !owned }, row_style, lined[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = role
    sem.row = u32(index + 1usize)
    sem.row_count = u32(count)
    if selected { sem.states = accessibility.STATE_SELECTED }
    ret (widget.semantics(0u64, sem, style.defaults(), region[0usize..1usize]), ok)
}

// A table: the header row over the source's rows in a lazy viewport (keyed
// `key`), `extent` each, only those in view built; a header tap reports the
// column to sort by (the caller sorts its model), a header dragged onto another
// reports a `Reorder` of columns, a handle dragged reports a `ColumnResize` (the
// caller keeps the columns); a row tap reports the row's key through `pick` and
// `selected` marks rows. A table in the tree named `label`.
fn table(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, columns: []const Column, source: TableSource, selected: []const widget.Key, sort_column: usize, descending: bool, sort: widget.Change[usize], reorder: widget.Change[Reorder], resize: widget.Change[ColumnResize], pick: widget.Change[widget.Key], extent: f32, offset: f32, change: widget.Change[f32], height: f32) -> (widget.Node, err) {
    let (made, made_error) = tabulated(a, key, t, label, columns, source, selected, sort_column, descending, sort, reorder, resize, pick, extent, offset, change, height, 12u8, false)
    ret (made, made_error)
}

// A data grid: the table as a grid in the tree, whose cells the source may build
// as fields, so the caller edits in place; the same contract otherwise.
fn data_grid(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, columns: []const Column, source: TableSource, selected: []const widget.Key, sort_column: usize, descending: bool, sort: widget.Change[usize], reorder: widget.Change[Reorder], resize: widget.Change[ColumnResize], pick: widget.Change[widget.Key], extent: f32, offset: f32, change: widget.Change[f32], height: f32) -> (widget.Node, err) {
    let (made, made_error) = tabulated(a, key, t, label, columns, source, selected, sort_column, descending, sort, reorder, resize, pick, extent, offset, change, height, 30u8, false)
    ret (made, made_error)
}

// v2 (D984, docs/ux/components/DataGrid): the editable grid's core over
// caller-owned state. A cell is what the source says of it: its text, an error
// message (invalid when not empty), whether it is edited and unsaved (dirty) and
// whether it is read only.
type GridCell = struct { text: str, message: str, dirty: bool, read_only: bool }
type GridSource = struct { ctx: *void, count: fn(*void) -> usize, cell: fn(*void, usize, usize) -> GridCell }

// The grid's state, which the caller keeps: the active cell, the range's anchor
// (the active cell when there is no range), edit mode and the draft's length in
// the caller's buffer.
type GridState = struct { row: usize, column: usize, anchor_row: usize, anchor_column: usize, editing: bool, len: usize }

// What a key, a tap or the editor asks: Move and Extend (the range from the
// anchor) to a cell, Edit (the caller puts the value in the draft and its length
// in `next.len`), Type (the draft is `text` now), Commit (the draft is the value
// of the cell at `row`, `column`) and Cancel. `next` is the caller's next state.
type GridEventKind = enum u8 { Move, Extend, Edit, Replace, Type, Commit, Cancel, Paste, Clear, Undo, FillDown }
type GridEvent = struct { kind: GridEventKind, row: usize, column: usize, next: GridState, text: str }

// An event fired, then the focus to the element keyed `to.key` (a tapped cell
// takes the grid's focus with it).
type GridFire = struct { event: GridEvent, change: widget.Change[GridEvent], to: control.FocusTo }

fn grid_fire(ctx: *void) -> err {
    let f = back_of[GridFire](ctx)
    let fired = widget.fire_change[GridEvent](f.change, f.event)
    if fired != ok || f.to.key == 0u64 || mem.address_of(f.to.runtime) == 0usize { ret fired }
    ret control.focus_to_fire(ctx_of(&f.to))
}

fn grid_typed(ctx: *void, value: str) -> err {
    let f = back_of[GridFire](ctx)
    var event = f.event
    event.next.len = value.len
    event.text = value
    ret widget.fire_change[GridEvent](f.change, event)
}

type GridInput = struct { state: GridState, change: widget.Change[GridEvent] }

fn grid_input(ctx: *void, event: input.Event) -> err {
    let g = back_of[GridInput](ctx)
    switch event {
    case .Text as t:
        if t.text.len == 0usize { ret ok }
        var next = g.state
        next.editing = true
        next.len = t.text.len
        ret widget.fire_change[GridEvent](g.change, GridEvent { kind: .Replace, row: g.state.row, column: g.state.column, next: next, text: t.text })
    default:
        ret ok
    }
}

// The grid's keys: in navigation mode the arrows, Home and End (with Ctrl, the
// grid's first and last cell), Page Up and Page Down (`page` rows) move the
// active cell, with Shift extending the range; Tab wraps by cell; Ctrl+A selects
// all; F8 visits the next invalid cell; Enter or F2 edits; Escape drops the
// range. In edit mode the editor keeps the arrows; Enter and Tab commit and move,
// Escape cancels.
type GridKeys = struct { state: GridState, rows: usize, columns: usize, page: usize, source: GridSource, arena: *mem.Arena, runtime: *widget.Runtime, change: widget.Change[GridEvent] }

fn grid_copy_text(a: *mem.Arena, source: GridSource, s: GridState) -> (str, err) {
    var row_lo = s.row
    var row_hi = s.anchor_row
    var column_lo = s.column
    var column_hi = s.anchor_column
    if row_lo > row_hi {
        row_lo = s.anchor_row
        row_hi = s.row
    }
    if column_lo > column_hi {
        column_lo = s.anchor_column
        column_hi = s.column
    }
    var size = row_hi - row_lo
    size += (row_hi - row_lo + 1usize) * (column_hi - column_lo)
    var r = row_lo
    while r <= row_hi {
        var c = column_lo
        while c <= column_hi {
            size += source.cell(source.ctx, r, c).text.len
            c += 1usize
        }
        r += 1usize
    }
    if size == 0usize { ret ("", ok) }
    let (out, out_error) = mem.alloc[u8](a, size)
    if out_error != ok { ret ("", TooLarge) }
    var n = 0usize
    r = row_lo
    while r <= row_hi {
        if r > row_lo {
            out[n] = 10u8
            n += 1usize
        }
        var c = column_lo
        while c <= column_hi {
            if c > column_lo {
                out[n] = 9u8
                n += 1usize
            }
            let value = source.cell(source.ctx, r, c).text
            var i = 0usize
            while i < value.len {
                out[n] = value[i]
                n += 1usize
                i += 1usize
            }
            c += 1usize
        }
        r += 1usize
    }
    ret (out[0usize..n], ok)
}

fn grid_key(ctx: *void, k: input.KeyEvent) -> err {
    let g = back_of[GridKeys](ctx)
    if g.rows == 0usize { ret ok }
    let code = widget.key_code(k.key.physical)
    let s = g.state
    var next = s
    var kind: GridEventKind = .Move
    if s.editing {
        if code == 27u32 {
            kind = .Cancel
        } else if code == 13u32 {
            kind = .Commit
            if k.modifiers.shift {
                if s.row > 0usize { next.row = s.row - 1usize }
            } else if s.row + 1usize < g.rows { next.row = s.row + 1usize }
        } else if code == 9u32 {
            kind = .Commit
            var flat = s.row * g.columns + s.column
            let count = g.rows * g.columns
            if k.modifiers.shift { flat = (flat + count - 1usize) % count } else { flat = (flat + 1usize) % count }
            next.row = flat / g.columns
            next.column = flat % g.columns
        } else {
            ret ok
        }
        next.editing = false
        next.anchor_row = next.row
        next.anchor_column = next.column
        ret widget.fire_change[GridEvent](g.change, GridEvent { kind: kind, row: s.row, column: s.column, next: next, text: "" })
    }
    let command = k.modifiers.control || k.modifiers.meta
    if command && code == 67u32 {
        let (text, text_error) = grid_copy_text(g.arena, g.source, s)
        if text_error != ok { ret text_error }
        ret widget.clipboard_set(g.runtime, text)
    }
    if command && code == 86u32 {
        let (text, text_error) = widget.clipboard_get(g.runtime, g.arena)
        if text_error != ok { ret text_error }
        ret widget.fire_change[GridEvent](g.change, GridEvent { kind: .Paste, row: s.row, column: s.column, next: next, text: text })
    }
    if command && code == 90u32 { ret widget.fire_change[GridEvent](g.change, GridEvent { kind: .Undo, row: s.row, column: s.column, next: next, text: "" }) }
    if command && (code == 68u32 || code == 13u32) { ret widget.fire_change[GridEvent](g.change, GridEvent { kind: .FillDown, row: s.row, column: s.column, next: next, text: "" }) }
    if code == 46u32 { ret widget.fire_change[GridEvent](g.change, GridEvent { kind: .Clear, row: s.row, column: s.column, next: next, text: "" }) }
    if code == 13u32 || code == 113u32 {
        next.editing = true
        ret widget.fire_change[GridEvent](g.change, GridEvent { kind: .Edit, row: s.row, column: s.column, next: next, text: "" })
    }
    var r = s.row
    var c = s.column
    if code == 9u32 {
        var flat = r * g.columns + c
        let count = g.rows * g.columns
        if k.modifiers.shift { flat = (flat + count - 1usize) % count } else { flat = (flat + 1usize) % count }
        r = flat / g.columns
        c = flat % g.columns
    }
    if code == 65u32 && (k.modifiers.control || k.modifiers.meta) {
        next.row = g.rows - 1usize
        next.column = g.columns - 1usize
        next.anchor_row = 0usize
        next.anchor_column = 0usize
        ret widget.fire_change[GridEvent](g.change, GridEvent { kind: .Extend, row: s.row, column: s.column, next: next, text: "" })
    }
    if code == 32u32 && k.modifiers.shift {
        next.column = g.columns - 1usize
        next.anchor_row = s.row
        next.anchor_column = 0usize
        ret widget.fire_change[GridEvent](g.change, GridEvent { kind: .Extend, row: s.row, column: s.column, next: next, text: "" })
    }
    if code == 32u32 && command {
        next.row = g.rows - 1usize
        next.anchor_row = 0usize
        next.anchor_column = s.column
        ret widget.fire_change[GridEvent](g.change, GridEvent { kind: .Extend, row: s.row, column: s.column, next: next, text: "" })
    }
    if code == 119u32 {
        let count = g.rows * g.columns
        var i = 1usize
        while i <= count {
            let flat = (s.row * g.columns + s.column + i) % count
            let target_row = flat / g.columns
            let target_column = flat % g.columns
            if g.source.cell(g.source.ctx, target_row, target_column).message.len > 0usize {
                next.row = target_row
                next.column = target_column
                next.anchor_row = target_row
                next.anchor_column = target_column
                ret widget.fire_change[GridEvent](g.change, GridEvent { kind: .Move, row: s.row, column: s.column, next: next, text: "" })
            }
            i += 1usize
        }
        ret ok
    }
    if code == 38u32 && r > 0usize { r -= 1usize }
    if code == 40u32 && r + 1usize < g.rows { r += 1usize }
    if code == 37u32 && c > 0usize { c -= 1usize }
    if code == 39u32 && c + 1usize < g.columns { c += 1usize }
    if code == 36u32 {
        c = 0usize
        if k.modifiers.control { r = 0usize }
    }
    if code == 35u32 {
        c = g.columns - 1usize
        if k.modifiers.control { r = g.rows - 1usize }
    }
    if code == 33u32 {
        if r > g.page { r -= g.page } else { r = 0usize }
    }
    if code == 34u32 {
        r += g.page
        if r + 1usize > g.rows { r = g.rows - 1usize }
    }
    let moving = code == 9u32 || code == 27u32 || (code >= 33u32 && code <= 40u32)
    if !moving { ret ok }
    next.row = r
    next.column = c
    if k.modifiers.shift && code != 27u32 {
        kind = .Extend
    } else {
        next.anchor_row = r
        next.anchor_column = c
    }
    ret widget.fire_change[GridEvent](g.change, GridEvent { kind: kind, row: s.row, column: s.column, next: next, text: "" })
}

fn span_of(a: usize, b: usize) -> usize {
    if a > b { ret a - b + 1usize }
    ret b - a + 1usize
}

fn within(v: usize, a: usize, b: usize) -> bool {
    ret (v >= a && v <= b) || (v >= b && v <= a)
}

// What `data_grid_of` hands its table: the caller's source, state and change.
type GridBuild = struct { source: GridSource, t: *const control.Theme, state: GridState, change: widget.Change[GridEvent], holder: widget.Key }

fn grid_count(ctx: *void) -> usize {
    let b = back_of[GridBuild](ctx)
    ret b.source.count(b.source.ctx)
}

fn grid_row_key(ctx: *void, index: usize) -> widget.Key {
    ret 0u64
}

// One cell: filling it, a 2 wide bar at its start (`primary` when dirty), then
// 10 in an 18 `error` icon when invalid and the `body-medium` value in
// `on-surface` (`on-surface-variant` read only), under a 2px `error` inset
// outline when invalid; in a range of more than one cell it is
// `primary-container` with `on-primary-container` content. A tap moves the
// active cell here and takes the grid's focus.
fn grid_cell(ctx: *void, a: *mem.Arena, index: usize, at: usize, out: *widget.Node) -> err {
    let b = back_of[GridBuild](ctx)
    let t = b.t
    let s = b.state
    let value = b.source.cell(b.source.ctx, index, at)
    let ranged = span_of(s.row, s.anchor_row) * span_of(s.column, s.anchor_column) > 1usize && within(index, s.row, s.anchor_row) && within(at, s.column, s.anchor_column)
    let invalid = value.message.len > 0usize
    var ink = style.color(t.tokens, .OnSurface)
    if value.read_only { ink = style.color(t.tokens, .OnSurfaceVariant) }
    if ranged { ink = style.color(t.tokens, .OnPrimaryContainer) }
    let (inner, inner_error) = mem.alloc[widget.Node](a, 2usize)
    if inner_error != ok { ret TooLarge }
    var n = 0usize
    if invalid {
        var mark = control.icon_options()
        mark.size = t.tokens.sizes.icon_sm
        mark.color = .Error
        let (icon, icon_error) = control.icon_of(a, 0u64, t, .Alert, mark)
        if icon_error != ok { ret icon_error }
        inner[n] = icon
        n += 1usize
    }
    var caption = control.text_options()
    caption.role = .BodyMedium
    caption.wrap = .None
    let (said, said_error) = control.colored_text(a, 0u64, value.text, t, caption, ink)
    if said_error != ok { ret said_error }
    inner[n] = said
    n += 1usize
    let flat = style.Length { Px: 0.0 }
    var body_style = style.defaults()
    body_style.width = style.Length { Flex: 1.0 }
    body_style.padding = style.EdgeLengths { left: style.Length { Px: 10.0 }, top: flat, right: style.Length { Px: 12.0 }, bottom: flat }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret TooLarge }
    var bar = style.defaults()
    bar.width = style.Length { Px: t.tokens.sizes.outline_focused }
    if value.dirty { bar.background = paint.Brush { Solid: style.color(t.tokens, .Primary) } }
    parts[0usize] = widget.box(0u64, bar, zero)
    parts[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 4.0 }, body_style, inner[0usize..n])
    var cell_style = style.defaults()
    cell_style.width = style.Length { Percent: 100.0 }
    cell_style.height = style.Length { Percent: 100.0 }
    if ranged { cell_style.background = paint.Brush { Solid: style.color(t.tokens, .PrimaryContainer) } }
    if invalid { cell_style.border = style.Border { width: t.tokens.sizes.outline_focused, color: style.color(t.tokens, .Error) } }
    let (lined, lined_error) = mem.alloc[widget.Node](a, 1usize)
    if lined_error != ok { ret TooLarge }
    lined[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Stretch, gap: 0.0 }, cell_style, parts[0usize..2usize])
    var next = s
    next.row = index
    next.column = at
    next.anchor_row = index
    next.anchor_column = at
    next.editing = false
    let (fires, fires_error) = mem.alloc[GridFire](a, 1usize)
    if fires_error != ok { ret TooLarge }
    fires[0usize] = GridFire { event: GridEvent { kind: .Move, row: s.row, column: s.column, next: next, text: "" }, change: b.change, to: control.FocusTo { runtime: t.runtime, key: b.holder } }
    let (taps, taps_error) = mem.alloc[widget.Submit](a, 1usize)
    if taps_error != ok { ret TooLarge }
    taps[0usize] = widget.Submit { ctx: ctx_of(&fires[0usize]), invoke: grid_fire }
    let (tapped, tapped_error) = mem.alloc[widget.Node](a, 1usize)
    if tapped_error != ok { ret TooLarge }
    var fill = style.defaults()
    fill.width = style.Length { Percent: 100.0 }
    fill.height = style.Length { Percent: 100.0 }
    tapped[0usize] = widget.region(0u64, widget.Region { gesture: widget.GestureAction { ctx: ctx_of(&taps[0usize]), invoke: control.press_tap }, gestures: 1u8, enabled: true, focusable: false }, fill, lined[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.value = value.text
    if value.read_only {
        sem.states = accessibility.STATE_READ_ONLY
        sem.hint = "Read only"
    }
    if value.dirty { sem.hint = "Edited" }
    if invalid {
        sem.states = sem.states | accessibility.STATE_INVALID
        sem.hint = value.message
    }
    if ranged { sem.states = sem.states | accessibility.STATE_SELECTED }
    *out = widget.semantics(0u64, sem, fill, tapped[0usize..1usize])
    ret ok
}

// "1 error", "3 errors", "2 cells selected": a count and its noun.
fn count_words(a: *mem.Arena, count: usize, one: str, many: str) -> (str, err) {
    let (said, said_error) = mem.alloc[u8](a, 48usize)
    if said_error != ok { ret ("", TooLarge) }
    var n = control.write_i64(said, i64(count))
    var noun = many
    if count == 1usize { noun = one }
    n += control.copy_text(said[n..48usize], noun)
    ret (said[0usize..n], ok)
}

// v2 (D984, docs/ux/components/DataGrid): the data grid's core over the
// caller's `state` (see `GridState`, `GridEvent`). The D980 dense frame (40
// header, `extent` rows -- 32 at 0 -- with the 40 wide row numbers and grid lines
// both ways) holds the source's cells, drawn by `grid_cell`. One active cell,
// ringed with an inset 3px `focus-ring`, is the grid's one focusable element
// (keyed `key + 1`), so the focus stays with it as it moves; the grid's scope
// takes every key (`grid_key`). In edit mode the active cell's editor (keyed
// `key + 2`) stands over it in a modal layer that takes the focus: a
// `body-medium` field on `surface-container-highest` inside a 2px `primary`
// inset outline, caret `primary`, 12 in, editing the caller's `draft` (its
// first `state.len` bytes); a press outside commits. Under the grid a 40
// status bar, 12 in, says the error count in `error` after an 18 `error` icon
// and, for a range, "N cells selected" in `body-medium` `on-surface-variant`.
// Every change reaches `change` as a `GridEvent` carrying the next state.
// ponytail: text cells only -- no checkbox, select or date cells; no
// double-click, Shift+click, pointer row/column selection, clipboard
// parsing and mutation, hover cell layer, error tooltip, saving
// or disabled looks, cross-fade, or touch sheet; the caller keeps the active
// row in view (the ring is held inside the viewport).
fn data_grid_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, columns: []const Column, source: GridSource, state: GridState, draft: []u8, change: widget.Change[GridEvent], extent: f32, offset: f32, scrolled: widget.Change[f32], height: f32) -> (widget.Node, err) {
    if columns.len == 0usize || columns.len > 60usize { ret (zero, TooLarge) }
    var row_extent = extent
    if !(row_extent > 0.0) { row_extent = 32.0 }
    let total = source.count(source.ctx)
    let (builds, builds_error) = mem.alloc[GridBuild](a, 1usize)
    if builds_error != ok { ret (zero, TooLarge) }
    builds[0usize] = GridBuild { source: source, t: t, state: state, change: change, holder: key + 1u64 }
    let table_source = TableSource { ctx: ctx_of(&builds[0usize]), count: grid_count, key: grid_row_key, cell: grid_cell }
    var none: [1]widget.Key = zero
    let (table_node, table_error) = tabulated(a, key + 16u64, t, label, columns, table_source, none[0usize..0usize], columns.len, false, zero, zero, zero, zero, row_extent, offset, scrolled, height - 40.0, 30u8, true)
    if table_error != ok { ret (zero, table_error) }
    var width: f32 = 40.0
    var x: f32 = 40.0
    var c = 0usize
    while c < columns.len {
        if c < state.column { x += columns[c].width }
        width += columns[c].width
        c += 1usize
    }
    let active_w = control.max_zero(columns[state.column].width - t.tokens.sizes.divider)
    let active_h = row_extent - t.tokens.sizes.divider
    let grid_height = height - 40.0
    var y = 40.0 + f32(state.row) * row_extent - offset
    if y > grid_height - active_h { y = grid_height - active_h }
    if y < 40.0 { y = 40.0 }
    // The active cell: its ring, and the focusable holder inside a clip its
    // size, so the runtime's ring lies inside it too.
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, TooLarge) }
    var fill = style.defaults()
    fill.width = style.Length { Percent: 100.0 }
    fill.height = style.Length { Percent: 100.0 }
    control.focus_look(t)
    let (inputs, inputs_error) = mem.alloc[GridInput](a, 1usize)
    if inputs_error != ok { ret (zero, TooLarge) }
    inputs[0usize] = GridInput { state: state, change: change }
    held[0usize] = widget.button(key + 1u64, widget.Button { action: widget.Action { ctx: ctx_of(&inputs[0usize]), invoke: grid_input }, enabled: true }, fill, zero)
    var ring = control.sized_style(active_w, active_h)
    ring.overflow = .Clip
    ring.border = style.Border { width: t.tokens.metrics.focus_ring, color: style.color(t.tokens, .FocusRing) }
    let (ringed, ringed_error) = mem.alloc[widget.Node](a, 1usize)
    if ringed_error != ok { ret (zero, TooLarge) }
    ringed[0usize] = widget.box(0u64, ring, held[0usize..1usize])
    let (layers, layers_error) = mem.alloc[widget.Node](a, 3usize)
    if layers_error != ok { ret (zero, TooLarge) }
    layers[0usize] = table_node
    layers[1usize] = widget.positioned(0u64, x, y, style.defaults(), ringed[0usize..1usize])
    var layer_count = 2usize
    if state.editing {
        let (fires, fires_error) = mem.alloc[GridFire](a, 2usize)
        if fires_error != ok { ret (zero, TooLarge) }
        var committed = state
        committed.editing = false
        if state.row + 1usize < total { committed.row = state.row + 1usize }
        committed.anchor_row = committed.row
        committed.anchor_column = committed.column
        let no_focus = control.FocusTo { runtime: t.runtime, key: 0u64 }
        fires[0usize] = GridFire { event: GridEvent { kind: .Commit, row: state.row, column: state.column, next: committed, text: "" }, change: change, to: no_focus }
        fires[1usize] = GridFire { event: GridEvent { kind: .Type, row: state.row, column: state.column, next: state, text: "" }, change: change, to: no_focus }
        let (look, look_error) = control.text_style(a, t, .BodyMedium)
        if look_error != ok { ret (zero, look_error) }
        let line = style.text_style(t.tokens, .BodyMedium).line_height
        var editor_style = control.sized_style(active_w, active_h)
        editor_style.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerHighest) }
        editor_style.border = style.Border { width: t.tokens.sizes.outline_focused, color: style.color(t.tokens, .Primary) }
        let sides = style.Length { Px: 12.0 }
        let ends = style.Length { Px: control.max_zero((active_h - line) * 0.5) }
        editor_style.padding = style.EdgeLengths { left: sides, top: ends, right: sides, bottom: ends }
        let (edits, edits_error) = mem.alloc[widget.Node](a, 1usize)
        if edits_error != ok { ret (zero, TooLarge) }
        edits[0usize] = widget.edit(key + 2u64, widget.Edit { buffer: draft, len: state.len, style: look, color: style.color(t.tokens, .OnSurface), selection: style.color(t.tokens, .TextSelection), change: widget.Change[str] { ctx: ctx_of(&fires[1usize]), invoke: grid_typed }, submit: zero, enabled: true, read_only: false, multiline: false, secret: false, marked: zero, caret: style.color(t.tokens, .Primary), untabbed: false, ringed: false }, editor_style)
        layers[2usize] = widget.overlay(0u64, widget.Overlay { anchor: key + 1u64, placement: .TopCenter, offset: zero, modal: true, dismiss: widget.Submit { ctx: ctx_of(&fires[0usize]), invoke: grid_fire } }, style.defaults(), edits[0usize..1usize])
        layer_count = 3usize
    }
    var stack_style = control.sized_style(width, grid_height)
    stack_style.overflow = .Clip
    // The status bar.
    var errors = 0usize
    var i = 0usize
    while i < total {
        c = 0usize
        while c < columns.len {
            if source.cell(source.ctx, i, c).message.len > 0usize { errors += 1usize }
            c += 1usize
        }
        i += 1usize
    }
    let chosen = span_of(state.row, state.anchor_row) * span_of(state.column, state.anchor_column)
    let (said, said_error) = mem.alloc[widget.Node](a, 4usize)
    if said_error != ok { ret (zero, TooLarge) }
    var n = 0usize
    var caption = control.text_options()
    caption.role = .BodyMedium
    caption.wrap = .None
    if errors > 0usize {
        var mark = control.icon_options()
        mark.size = t.tokens.sizes.icon_sm
        mark.color = .Error
        let (icon, icon_error) = control.icon_of(a, 0u64, t, .Alert, mark)
        if icon_error != ok { ret (zero, icon_error) }
        let (words, words_error) = count_words(a, errors, " error", " errors")
        if words_error != ok { ret (zero, words_error) }
        let (count_node, count_error) = control.colored_text(a, key + 4u64, words, t, caption, style.color(t.tokens, .Error))
        if count_error != ok { ret (zero, count_error) }
        said[n] = icon
        said[n + 1usize] = count_node
        n += 2usize
    }
    if chosen > 1usize {
        let (words, words_error) = count_words(a, chosen, " cell selected", " cells selected")
        if words_error != ok { ret (zero, words_error) }
        let (chosen_node, chosen_error) = control.colored_text(a, key + 5u64, words, t, caption, style.color(t.tokens, .OnSurfaceVariant))
        if chosen_error != ok { ret (zero, chosen_error) }
        said[n] = chosen_node
        n += 1usize
    }
    var bar_style = control.sized_style(width, 40.0)
    let flat = style.Length { Px: 0.0 }
    let sides = style.Length { Px: 12.0 }
    bar_style.padding = style.EdgeLengths { left: sides, top: flat, right: sides, bottom: flat }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = widget.stack(0u64, stack_style, layers[0usize..layer_count])
    var status_sem: widget.Semantics = zero
    status_sem.live = 1u8
    let (bar_nodes, bar_error) = mem.alloc[widget.Node](a, 1usize)
    if bar_error != ok { ret (zero, TooLarge) }
    bar_nodes[0usize] = widget.flex(key + 6u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 8.0 }, bar_style, said[0usize..n])
    parts[1usize] = widget.semantics(0u64, status_sem, style.defaults(), bar_nodes[0usize..1usize])
    let (column_node, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column_node[0usize] = widget.flex(key, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..2usize])
    let (keyed, keyed_error) = mem.alloc[GridKeys](a, 1usize)
    if keyed_error != ok { ret (zero, TooLarge) }
    var page = 1usize
    if row_extent > 0.0 && grid_height - 40.0 > row_extent { page = usize((grid_height - 40.0) / row_extent) }
    keyed[0usize] = GridKeys { state: state, rows: total, columns: columns.len, page: page, source: source, arena: a, runtime: t.runtime, change: change }
    ret (widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: zero, default_action: zero, cancel_action: zero, keys: widget.Change[input.KeyEvent] { ctx: ctx_of(&keyed[0usize]), invoke: grid_key } }, style.defaults(), column_node[0usize..1usize]), ok)
}

// v2 (D980, docs/ux/components/Table, DataGrid): the header (`header_cells`)
// over the rows (`table_row_of`) in a clipped viewport on `surface`, each row
// but the last over a 1px `outline-variant` divider, the runtime's rounded
// thumb in `on-surface-variant` at 50%; an `extent` of 0 takes the density's
// row height (48 / 40 / 32). A table's header and padding follow the density; a
// data grid (`role` 30) is dense whatever the theme: a 40 header, 32 rows
// (unless `extent` says otherwise), 12 padding, the row-number column and grid
// lines both ways. Up, Down, Home and End move the focus among the built rows.
// (D984) `owned` rows (`data_grid_of`'s) are neither focusable nor tapped and
// hold their cells unpadded: the cells draw their own looks.
// ponytail: no toolbar, selection bar, footer, pinned column, horizontal
// scroll, loading, empty or error state; `data_grid` keeps the caller's cells
// as its editors -- `data_grid_of` is the one with the DataGrid's core.
fn tabulated(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, columns: []const Column, source: TableSource, selected: []const widget.Key, sort_column: usize, descending: bool, sort: widget.Change[usize], reorder: widget.Change[Reorder], resize: widget.Change[ColumnResize], pick: widget.Change[widget.Key], extent: f32, offset: f32, change: widget.Change[f32], height: f32, role: u8, owned: bool) -> (widget.Node, err) {
    if columns.len == 0usize || columns.len > 60usize { ret (zero, TooLarge) }
    let grid = role == 30u8
    var row_extent = extent
    if !(row_extent > 0.0) { row_extent = control.if_else(grid, 32.0, table_row_height(t)) }
    let head_height = control.if_else(grid, 40.0, header_height(t))
    let pad = control.if_else(grid, 12.0, cell_padding(t))
    let lead = control.if_else(grid, 40.0, 0.0)
    var width: f32 = lead
    var c = 0usize
    while c < columns.len {
        width += columns[c].width
        c += 1usize
    }
    let (head, head_error) = header_cells(a, key, t, columns, sort_column, descending, sort, reorder, resize, head_height, pad, lead)
    if head_error != ok { ret (zero, head_error) }
    let total = source.count(source.ctx)
    let body_height = height - head_height
    let (first, count) = widget.visible_range(offset, body_height, total, row_extent)
    let (rows, rows_error) = mem.alloc[widget.Node](a, count)
    if rows_error != ok { ret (zero, TooLarge) }
    let (keys, keys_error) = mem.alloc[widget.Key](a, count)
    if keys_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < count {
        let index = first + i
        let row_key = source.key(source.ctx, index)
        keys[i] = row_key
        let (cells, cells_error) = mem.alloc[widget.Node](a, columns.len)
        if cells_error != ok { ret (zero, TooLarge) }
        c = 0usize
        while c < columns.len {
            var built: widget.Node = zero
            let built_error = source.cell(source.ctx, a, index, c, &built)
            if built_error != ok { ret (zero, built_error) }
            cells[c] = built
            c += 1usize
        }
        let lined = index + 1usize < total
        let (made, made_error) = table_row_of(a, t, columns, cells, row_key, index, total, row_extent - control.if_else(lined, t.tokens.sizes.divider, 0.0), is_selected(selected, row_key), pick, 13u8, control.if_else(owned, 0.0, pad), grid, owned)
        if made_error != ok { ret (zero, made_error) }
        rows[i] = made
        i += 1usize
    }
    if !owned {
        let rove_error = roving(a, t, rows, keys, 1usize)
        if rove_error != ok { ret (zero, rove_error) }
    }
    i = 0usize
    while i < count {
        if first + i + 1usize < total {
            let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
            if pair_error != ok { ret (zero, TooLarge) }
            pair[0usize] = rows[i]
            var rule = style.defaults()
            rule.height = style.Length { Px: t.tokens.sizes.divider }
            rule.background = paint.Brush { Solid: style.color(t.tokens, .OutlineVariant) }
            pair[1usize] = widget.box(0u64, rule, zero)
            rows[i] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, style.defaults(), pair[0usize..2usize])
        }
        i += 1usize
    }
    var view_style = style.defaults()
    view_style.width = style.Length { Px: width }
    view_style.height = style.Length { Px: body_height }
    view_style.overflow = .Clip
    view_style.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = head
    parts[1usize] = widget.scroll(key, widget.Scroll { axis: .Vertical, offset: offset, overscroll: .Clamp, momentum: true, scrollbar: true, thumb: control.with_alpha(style.color(t.tokens, .OnSurfaceVariant), 0.5), change: change, virtual_first: first, virtual_count: total, virtual_extent: row_extent }, view_style, rows[0usize..count])
    var column_style = style.defaults()
    column_style.width = style.Length { Px: width }
    let (column_node, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column_node[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, column_style, parts[0usize..2usize])
    var sem: widget.Semantics = zero
    sem.role = role
    sem.label = label
    sem.row_count = u32(total)
    sem.column_count = u32(columns.len)
    ret (widget.semantics(0u64, sem, style.defaults(), column_node[0usize..1usize]), ok)
}

// A cell builder for a tree table's columns past the first: one cell into the
// arena for a row's key and a column.
type CellSource = struct { ctx: *void, cell: fn(*void, *mem.Arena, widget.Key, usize, *widget.Node) -> err }

// A tree's source: a parent's child count (the root under key 0), a child's
// stable key, whether a node has children, and a node's row built into the arena.
type TreeSource = struct { ctx: *void, count: fn(*void, widget.Key) -> usize, key: fn(*void, widget.Key, usize) -> widget.Key, has_children: fn(*void, widget.Key) -> bool, build: fn(*void, *mem.Arena, widget.Key, *widget.Node) -> err }

// A visible tree row: its key, its depth, its index among its siblings and their
// count, and whether it may expand.
type TreeRow = struct { key: widget.Key, depth: usize, index: usize, siblings: usize, branch: bool }

// The visible rows of a tree, depth first, only the expanded nodes' children
// asked for; the count (at most `out.len`).
fn flatten(source: TreeSource, expanded: []const widget.Key, parent: widget.Key, depth: usize, out: []TreeRow, at: usize) -> usize {
    var n = at
    let count = source.count(source.ctx, parent)
    var i = 0usize
    while i < count && n < out.len {
        let child = source.key(source.ctx, parent, i)
        let branch = source.has_children(source.ctx, child)
        out[n] = TreeRow { key: child, depth: depth, index: i, siblings: count, branch: branch }
        n += 1usize
        if branch && is_selected(expanded, child) { n = flatten(source, expanded, child, depth + 1usize, out, n) }
        i += 1usize
    }
    ret n
}

// A tree row's keys: Left collapses (or nothing), Right expands, through `toggle`.
type TreeKeys = struct { key: widget.Key, open: bool, toggle: widget.Change[widget.Key] }

fn tree_expand(ctx: *void) -> err {
    let k = mem.cast[*TreeKeys](ctx)
    if k.open { ret ok }
    ret widget.fire_change[widget.Key](k.toggle, k.key)
}

fn tree_collapse(ctx: *void) -> err {
    let k = mem.cast[*TreeKeys](ctx)
    if !k.open { ret ok }
    ret widget.fire_change[widget.Key](k.toggle, k.key)
}

// The rows of a tree or a tree table: each indented by its depth with a
// disclosure mark (keyed `key + 1 + 2 * position`, a tap reporting the node through
// `toggle`) before the content, the row itself (keyed by the node) a focusable tap
// region reporting the node through `pick`, Left and Right on it collapsing and
// expanding; a tree item in the tree with its level, expanded state and position.
// v2 (D981, docs/ux/components/Tree, Outline, TreeTable): the indent is 20 a
// level (24 on touch); the twisty an 18 `chevron-right` (`chevron-down` when
// open) in `on-surface-variant` in a 24 box, an empty 24 box on a leaf, 8
// before the content. A tree's row (no `columns`) is inset 8 at the sides with
// `radius-sm`, 4 before the first twisty, `extent` tall (0: 32 with a pointer,
// the trees' dense default, 48 on touch), under the `on-surface` state layer,
// `secondary-container` when selected; with `guides`, a 1px `outline-variant`
// line the row's height through the middle of each ancestor level's twisty, so
// the lines run on from row to row; the `current` node's row (0: none) carries
// a 3px `primary` bar at its start, inset 8 top and bottom. A tree table's row
// is a table row (`table_row_of`: 40 with a pointer, 48 touch, 32 dense, 16 in)
// over a full-width 1px `outline-variant` divider, the last excepted. Up, Down,
// Home and End move the focus among the visible rows.
// ponytail: at most 512 visible rows, not virtualised; no icon or meta slot,
// twisty rotation, Right-to-child or Left-to-parent, `*`, typeahead, rename,
// drag and drop, loading or disabled rows, and no Expand/Collapse actions.
fn tree_rows(a: *mem.Arena, key: widget.Key, t: *const control.Theme, source: TreeSource, expanded: []const widget.Key, selected: []const widget.Key, toggle: widget.Change[widget.Key], pick: widget.Change[widget.Key], guides: bool, columns: []const Column, cells_of: CellSource, extent: f32, width: f32, current: widget.Key) -> ([]widget.Node, err) {
    var none: []widget.Node = zero
    let (visible, visible_error) = mem.alloc[TreeRow](a, 512usize)
    if visible_error != ok { ret (none, TooLarge) }
    let count = flatten(source, expanded, 0u64, 0usize, visible, 0usize)
    let (rows, rows_error) = mem.alloc[widget.Node](a, count)
    if rows_error != ok { ret (none, TooLarge) }
    let (toggles, toggles_error) = mem.alloc[RowPick](a, count)
    if toggles_error != ok { ret (none, TooLarge) }
    let (picks, picks_error) = mem.alloc[RowPick](a, count)
    if picks_error != ok { ret (none, TooLarge) }
    let (keys, keys_error) = mem.alloc[TreeKeys](a, count)
    if keys_error != ok { ret (none, TooLarge) }
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 6usize * count)
    if shortcuts_error != ok { ret (none, TooLarge) }
    let (moves, moves_error) = mem.alloc[control.FocusTo](a, 6usize * count)
    if moves_error != ok { ret (none, TooLarge) }
    let tabled = columns.len > 0usize
    let touch = density_of(t) == 2usize
    let step = control.if_else(touch, 24.0, 20.0)
    var row_extent = extent
    if !(row_extent > 0.0) {
        row_extent = control.if_else(touch, 48.0, 32.0)
        if tabled { row_extent = table_row_height(t) }
    }
    let start = control.if_else(tabled, 0.0, 4.0)
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    let flat = style.Length { Px: 0.0 }
    var i = 0usize
    while i < count {
        let entry = visible[i]
        let open = entry.branch && is_selected(expanded, entry.key)
        let chosen = is_selected(selected, entry.key)
        let lined = tabled && i + 1usize < count
        let tall = row_extent - control.if_else(lined, t.tokens.sizes.divider, 0.0)
        // The twisty, or its blank for a leaf.
        var twisty = widget.box(0u64, control.sized_style(24.0, 24.0), zero)
        if entry.branch {
            toggles[i] = RowPick { key: entry.key, pick: toggle }
            var kind: control.GlyphKind = .ChevronRight
            if open { kind = .ChevronDown }
            // The 18 icon (its 1.5 inset kept) centred in the 24 box.
            let (chevron, chevron_error) = control.stroked_glyph(a, muted, kind, 15.0, 18.0 * 1.75 / 24.0)
            if chevron_error != ok { ret (none, chevron_error) }
            let (drawn, drawn_error) = mem.alloc[widget.Node](a, 1usize)
            if drawn_error != ok { ret (none, TooLarge) }
            drawn[0usize] = chevron
            var box_style = control.sized_style(24.0, 24.0)
            let around = style.Length { Px: 4.5 }
            box_style.padding = style.EdgeLengths { left: around, top: around, right: around, bottom: around }
            twisty = widget.region(key + 1u64 + 2u64 * u64(i), widget.Region { gesture: widget.GestureAction { ctx: ctx_of(&toggles[i]), invoke: row_pick_gesture }, gestures: 1u8, enabled: true, focusable: false }, box_style, drawn[0usize..1usize])
        }
        var built: widget.Node = zero
        let built_error = source.build(source.ctx, a, entry.key, &built)
        if built_error != ok { ret (none, built_error) }
        // The indent, with an outline's guides through each ancestor's twisty.
        let indent_width = start + f32(entry.depth) * step
        var indent = widget.box(0u64, control.sized_style(indent_width, tall), zero)
        if guides && !tabled && entry.depth > 0usize {
            let (lines, lines_error) = mem.alloc[widget.Node](a, entry.depth)
            if lines_error != ok { ret (none, TooLarge) }
            var l = 0usize
            while l < entry.depth {
                var line = control.sized_style(t.tokens.sizes.divider, tall)
                line.background = paint.Brush { Solid: style.color(t.tokens, .OutlineVariant) }
                lines[l] = widget.positioned(0u64, start + 12.0 + f32(l) * step, 0.0, line, zero)
                l += 1usize
            }
            indent = widget.stack(0u64, control.sized_style(indent_width, tall), lines[0usize..entry.depth])
        }
        let (lead, lead_error) = mem.alloc[widget.Node](a, 4usize)
        if lead_error != ok { ret (none, TooLarge) }
        lead[0usize] = indent
        lead[1usize] = twisty
        lead[2usize] = widget.box(0u64, control.sized_style(8.0, 0.0), zero)
        lead[3usize] = built
        var lead_style = style.defaults()
        lead_style.height = style.Length { Px: tall }
        let first_cell = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, lead_style, lead[0usize..4usize])
        picks[i] = RowPick { key: entry.key, pick: pick }
        var made: widget.Node = zero
        if tabled {
            let (cells, cells_error) = mem.alloc[widget.Node](a, columns.len)
            if cells_error != ok { ret (none, TooLarge) }
            cells[0usize] = first_cell
            var c = 1usize
            while c < columns.len {
                var extra: widget.Node = zero
                let extra_error = cells_of.cell(cells_of.ctx, a, entry.key, c, &extra)
                if extra_error != ok { ret (none, extra_error) }
                cells[c] = extra
                c += 1usize
            }
            let (tabled_row, tabled_error) = table_row_of(a, t, columns, cells, entry.key, entry.index, entry.siblings, tall, chosen, pick, 2u8, cell_padding(t), false, false)
            if tabled_error != ok { ret (none, tabled_error) }
            made = tabled_row
        } else {
            let state = control.control_state(t, entry.key, true, chosen)
            var fill = control.with_alpha(style.color(t.tokens, .OnSurface), control.state_opacity(t, state))
            if chosen { fill = style.layer(style.color(t.tokens, .SecondaryContainer), style.color(t.tokens, .OnSecondaryContainer), control.state_opacity(t, state)) }
            var row_style = control.sized_style(control.max_zero(width - 16.0), tall)
            row_style.margin = style.EdgeLengths { left: style.Length { Px: 8.0 }, top: flat, right: style.Length { Px: 8.0 }, bottom: flat }
            row_style.radius = t.tokens.radii.sm
            row_style.background = paint.Brush { Solid: fill }
            let (inside, inside_error) = mem.alloc[widget.Node](a, 2usize)
            if inside_error != ok { ret (none, TooLarge) }
            inside[0usize] = first_cell
            var parts = 1usize
            if current != 0u64 && entry.key == current {
                var bar = control.sized_style(3.0, control.max_zero(tall - 16.0))
                bar.background = paint.Brush { Solid: style.color(t.tokens, .Primary) }
                inside[1usize] = widget.positioned(0u64, 0.0, 8.0, bar, zero)
                parts = 2usize
            }
            let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
            if body_error != ok { ret (none, TooLarge) }
            body[0usize] = widget.stack(0u64, control.sized_style(control.max_zero(width - 16.0), tall), inside[0usize..parts])
            control.focus_look(t)
            made = widget.region(entry.key, widget.Region { gesture: widget.GestureAction { ctx: ctx_of(&picks[i]), invoke: row_pick_gesture }, gestures: 1u8 | 4u8, enabled: true, focusable: true }, row_style, body[0usize..1usize])
        }
        // The keyboard: Left collapses, Right expands, from the focused row.
        keys[i] = TreeKeys { key: entry.key, open: open, toggle: toggle }
        let base = 6usize * i
        shortcuts[base] = widget.Shortcut { key: 37u32, modifiers: zero, action: widget.Submit { ctx: ctx_of(&keys[i]), invoke: tree_collapse } }
        shortcuts[base + 1usize] = widget.Shortcut { key: 39u32, modifiers: zero, action: widget.Submit { ctx: ctx_of(&keys[i]), invoke: tree_expand } }
        // Up, Down, Home and End in the same scope: a level fewer than `roving`.
        var bound = base + 2usize
        if mem.address_of(t.runtime) != 0usize {
            if i > 0usize {
                bind_move(moves, shortcuts, bound, t.runtime, visible[i - 1usize].key, 38u32)
                bound += 1usize
            }
            if i + 1usize < count {
                bind_move(moves, shortcuts, bound, t.runtime, visible[i + 1usize].key, 40u32)
                bound += 1usize
            }
            bind_move(moves, shortcuts, bound, t.runtime, visible[0usize].key, 36u32)
            bind_move(moves, shortcuts, bound + 1usize, t.runtime, visible[count - 1usize].key, 35u32)
            bound += 2usize
        }
        let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
        if scoped_error != ok { ret (none, TooLarge) }
        scoped[0usize] = made
        var item_sem: widget.Semantics = zero
        item_sem.role = 29u8
        item_sem.level = u8(entry.depth + 1usize)
        item_sem.row = u32(entry.index + 1usize)
        item_sem.row_count = u32(entry.siblings)
        if open { item_sem.states = accessibility.STATE_EXPANDED }
        if chosen { item_sem.states = item_sem.states | accessibility.STATE_SELECTED }
        if current != 0u64 && entry.key == current { item_sem.states = item_sem.states | accessibility.STATE_CURRENT }
        let (framed, framed_error) = mem.alloc[widget.Node](a, 1usize)
        if framed_error != ok { ret (none, TooLarge) }
        framed[0usize] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: shortcuts[base..bound], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), scoped[0usize..1usize])
        rows[i] = widget.semantics(0u64, item_sem, style.defaults(), framed[0usize..1usize])
        i += 1usize
    }
    if tabled {
        i = 0usize
        while i + 1usize < count {
            let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
            if pair_error != ok { ret (none, TooLarge) }
            pair[0usize] = rows[i]
            var rule = style.defaults()
            rule.height = style.Length { Px: t.tokens.sizes.divider }
            rule.background = paint.Brush { Solid: style.color(t.tokens, .OutlineVariant) }
            pair[1usize] = widget.box(0u64, rule, zero)
            rows[i] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, style.defaults(), pair[0usize..2usize])
            i += 1usize
        }
    }
    ret (rows[0usize..count], ok)
}

// A tree: the visible rows (the expanded nodes' children only) in a column
// `width` wide, each a tap region keyed by its node reporting it through `pick`,
// its disclosure mark and Left/Right reporting it through `toggle` (the caller
// keeps `expanded`), `selected` marking any number; a tree of tree items in the
// tree named `label`.
fn tree(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, source: TreeSource, expanded: []const widget.Key, selected: []const widget.Key, toggle: widget.Change[widget.Key], pick: widget.Change[widget.Key], extent: f32, width: f32) -> (widget.Node, err) {
    let (made, made_error) = treed(a, key, t, label, source, expanded, selected, toggle, pick, false, extent, width, 0u64)
    ret (made, made_error)
}

// An outline: a tree with a guide line down each level's indent.
fn outline(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, source: TreeSource, expanded: []const widget.Key, selected: []const widget.Key, toggle: widget.Change[widget.Key], pick: widget.Change[widget.Key], extent: f32, width: f32) -> (widget.Node, err) {
    let (made, made_error) = treed(a, key, t, label, source, expanded, selected, toggle, pick, true, extent, width, 0u64)
    ret (made, made_error)
}

// v2 (D981, docs/ux/components/Outline): the outline under its header -- 40
// tall (48 on touch), "Outline" in `title-small` `on-surface` 16 in, and a
// Collapse all text button (keyed `key + 2`) firing `collapse` at its end --
// with the `current` node, the heading whose section is in view, marked by its
// 3px `primary` bar and reported Current.
// ponytail: the bar sits at the row's start, 8 in from the pane, not on the
// pane's edge; no numbers, filter, follow mode or `primary` 600 label (the
// caller builds the label).
fn outline_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, source: TreeSource, expanded: []const widget.Key, selected: []const widget.Key, toggle: widget.Change[widget.Key], pick: widget.Change[widget.Key], current: widget.Key, collapse: *const widget.Submit, extent: f32, width: f32) -> (widget.Node, err) {
    let (made, made_error) = treed(a, key, t, label, source, expanded, selected, toggle, pick, true, extent, width, current)
    if made_error != ok { ret (zero, made_error) }
    var heading = control.text_options()
    heading.role = .TitleSmall
    heading.wrap = .None
    let (title, title_error) = control.colored_text(a, 0u64, "Outline", t, heading, style.color(t.tokens, .OnSurface))
    if title_error != ok { ret (zero, title_error) }
    var plain = control.button_options()
    plain.variant = .Plain
    let (fold, fold_error) = control.button(a, key + 2u64, t, "Collapse all", collapse, plain)
    if fold_error != ok { ret (zero, fold_error) }
    let (bar_parts, bar_parts_error) = mem.alloc[widget.Node](a, 3usize)
    if bar_parts_error != ok { ret (zero, TooLarge) }
    bar_parts[0usize] = title
    bar_parts[1usize] = widget.spacer(0u64, 1.0)
    bar_parts[2usize] = fold
    var band = control.sized_style(width, control.if_else(density_of(t) == 2usize, 48.0, 40.0))
    band.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let flat = style.Length { Px: 0.0 }
    band.padding = style.EdgeLengths { left: style.Length { Px: 16.0 }, top: flat, right: style.Length { Px: 4.0 }, bottom: flat }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, band, bar_parts[0usize..3usize])
    parts[1usize] = made
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..2usize]), ok)
}

fn no_cell(ctx: *void, a: *mem.Arena, row_key: widget.Key, column: usize, out: *widget.Node) -> err {
    *out = widget.box(0u64, style.defaults(), zero)
    ret ok
}

// v2 (D981, docs/ux/components/Tree): the rows on `surface` with 4 above and
// below.
fn treed(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, source: TreeSource, expanded: []const widget.Key, selected: []const widget.Key, toggle: widget.Change[widget.Key], pick: widget.Change[widget.Key], guides: bool, extent: f32, width: f32, current: widget.Key) -> (widget.Node, err) {
    var no_columns: []const Column = zero
    var none_ctx: *void = zero
    let (rows, rows_error) = tree_rows(a, key, t, source, expanded, selected, toggle, pick, guides, no_columns, CellSource { ctx: none_ctx, cell: no_cell }, extent, width, current)
    if rows_error != ok { ret (zero, rows_error) }
    var column_style = style.defaults()
    column_style.width = style.Length { Px: width }
    column_style.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let four = style.Length { Px: 4.0 }
    let flat = style.Length { Px: 0.0 }
    column_style.padding = style.EdgeLengths { left: flat, top: four, right: flat, bottom: four }
    let (column_node, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column_node[0usize] = widget.flex(key, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, column_style, rows)
    var sem: widget.Semantics = zero
    sem.role = 28u8
    sem.label = label
    ret (widget.semantics(0u64, sem, style.defaults(), column_node[0usize..1usize]), ok)
}

// A tree table: the tree's rows under a header of `columns` (the first column
// holding the tree, the others' cells built by `cell` for a row's key), the header
// sorting, reordering and resizing as a table's; a tree in the tree named `label`
// whose items are rows of cells. v2 (D981, docs/ux/components/TreeTable): the
// v2 header row over table rows with full-width dividers on `surface`.
// ponytail: no viewport or virtualisation, treegrid role, footer or per-parent
// sort.
fn tree_table(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, columns: []const Column, source: TreeSource, cells_of: CellSource, expanded: []const widget.Key, selected: []const widget.Key, toggle: widget.Change[widget.Key], pick: widget.Change[widget.Key], sort_column: usize, descending: bool, sort: widget.Change[usize], reorder: widget.Change[Reorder], resize: widget.Change[ColumnResize], extent: f32) -> (widget.Node, err) {
    if columns.len == 0usize { ret (zero, TooLarge) }
    let (head, head_error) = header_row(a, key, t, columns, sort_column, descending, sort, reorder, resize)
    if head_error != ok { ret (zero, head_error) }
    var width: f32 = 0.0
    var c = 0usize
    while c < columns.len {
        width += columns[c].width
        c += 1usize
    }
    let (rows, rows_error) = tree_rows(a, key + 128u64, t, source, expanded, selected, toggle, pick, false, columns, cells_of, extent, width, 0u64)
    if rows_error != ok { ret (zero, rows_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, rows.len + 1usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = head
    var r = 0usize
    while r < rows.len {
        parts[1usize + r] = rows[r]
        r += 1usize
    }
    var column_style = style.defaults()
    column_style.width = style.Length { Px: width }
    column_style.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let (column_node, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column_node[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, column_style, parts[0usize..rows.len + 1usize])
    var sem: widget.Semantics = zero
    sem.role = 28u8
    sem.label = label
    sem.column_count = u32(columns.len)
    ret (widget.semantics(0u64, sem, style.defaults(), column_node[0usize..1usize]), ok)
}

// ------------------------------------------------------- property editing (D851, P3-02)

// A property of a property grid: its stable key, its name and its group.
type Property = struct { key: widget.Key, name: str, group: str }

// A property grid's source: the count, a property by index, and its editor built
// into the arena -- a field, a checkbox, a select, whatever the caller edits it
// with, keyed by the caller.
type PropertySource = struct { ctx: *void, count: fn(*void) -> usize, property: fn(*void, usize) -> Property, editor: fn(*void, *mem.Arena, usize, *widget.Node) -> err }

fn same_text(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

// A group's toggle reporting the group's key.
type GroupToggle = struct { key: widget.Key, toggle: widget.Change[widget.Key] }

fn group_toggle_fire(ctx: *void) -> err {
    let g = mem.cast[*GroupToggle](ctx)
    ret widget.fire_change[widget.Key](g.toggle, g.key)
}

// A property grid: the properties in source order, a group heading (D826's
// disclosure, keyed `key + 1 + index` of the group's first property, its group
// key that index plus one) wherever the group changes, shut while its key is in
// `collapsed`, its header reporting the key through `toggle`; under it a row a
// property, the name in the left column (`name_width` wide, a row header in the
// tree) and the editor in the right, `width` wide in all. A table of two columns
// in the tree named `label`. v2 (D983): drawn as `property_grid_of`.
fn property_grid(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, source: PropertySource, collapsed: []const widget.Key, toggle: widget.Change[widget.Key], name_width: f32, width: f32) -> (widget.Node, err) {
    let (made, made_error) = property_grid_of(a, key, t, label, source, collapsed, toggle, name_width, width, property_grid_options())
    ret (made, made_error)
}

// A property's standing (D983): whether it differs from its default, and the
// message saying what is wrong with it (empty when nothing is).
type PropertyStatus = struct { modified: bool, message: str }

// A property grid's form (D983): the object's kind and name for the header
// (none when both are empty); the filter field's buffer, length and change (no
// field unless `has_filter`); and each property's status with the reset that
// sets one back to its default by index (neither unless `has_status`).
type PropertyGridOptions = struct { kind: str, name: str, filter: []u8, filter_len: usize, filtering: widget.Change[str], has_filter: bool, status: fn(*void, usize) -> PropertyStatus, has_status: bool, reset: widget.Change[usize] }

fn property_grid_options() -> PropertyGridOptions {
    var out: PropertyGridOptions = zero
    ret out
}

fn folded(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

// Whether `needle` stands in `hay`, ASCII case folded; an empty needle does.
fn contains_folded(hay: str, needle: []const u8) -> bool {
    if needle.len == 0usize { ret true }
    if needle.len > hay.len { ret false }
    var at = 0usize
    while at + needle.len <= hay.len {
        var k = 0usize
        while k < needle.len && folded(hay[at + k]) == folded(needle[k]) { k += 1usize }
        if k == needle.len { ret true }
        at += 1usize
    }
    ret false
}

// v2 (D983, docs/ux/components/PropertyGrid): a header, when there is a kind or
// a name, of the kind in `title-medium` over the name in `body-medium`
// `on-surface-variant`, 8 in; a 32 filter field "Filter properties" (keyed
// `key + 300`) 8 in, the rows narrowed to names holding its text (case
// folded) and a group with none left out. A group heading (keyed `key + 1 +
// index` of its first property, the group key that index plus one) is a
// button 32 tall (40 on touch) 8 below the one before: an 18 `chevron-right`
// (`chevron-down` open) in `on-surface-variant` in a 24 box, the `title-small`
// name in `on-surface` and, while shut, "6 properties" in `label-small`
// `on-surface-variant` at the end, under the `on-surface` layer. A property row
// is at least 40 tall (56 on touch), its `body-medium` `on-surface-variant`
// name ellipsised in the `name_width` column, 36 in when grouped (8 + the
// twisty's 24 + 4, under the group names) or 8, and the editor in the rest, 8
// from the end, so every row is `width` wide. With a status, the last 32 of
// the row are the reset slot: a modified property's name turns `on-surface`
// and its slot holds a 32 `refresh` icon button in `on-surface-variant`
// (keyed `key + 400 + index`, named "Reset NAME") reporting the index through
// `reset`; a message stands under the editor in `body-small` `error` after a
// 16 `error` icon, and the row grows.
// ponytail: groups are still keyed by position; the modified name is not 600
// weight (no weighted role); read-only and Mixed values are the caller's
// editors; no draggable column divider, selected row or touch list form.
fn property_grid_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, source: PropertySource, collapsed: []const widget.Key, toggle: widget.Change[widget.Key], name_width: f32, width: f32, options: PropertyGridOptions) -> (widget.Node, err) {
    let total = source.count(source.ctx)
    if total > 256usize { ret (zero, TooLarge) }
    let touch = density_of(t) == 2usize
    let row_min = control.if_else(touch, 56.0, 40.0)
    let head_h = control.if_else(touch, 40.0, 32.0)
    let needle = options.filter[0usize..options.filter_len]
    var grouped = false
    var g = 0usize
    while g < total {
        if source.property(source.ctx, g).group.len > 0usize { grouped = true }
        g += 1usize
    }
    let start = control.if_else(grouped, 36.0, 8.0)
    let value_width = control.max_zero(width - name_width - 8.0)
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    let flat = style.Length { Px: 0.0 }
    let (rows, rows_error) = mem.alloc[widget.Node](a, total)
    if rows_error != ok { ret (zero, TooLarge) }
    let (blocks, blocks_error) = mem.alloc[widget.Node](a, total + 2usize)
    if blocks_error != ok { ret (zero, TooLarge) }
    let (toggles, toggles_error) = mem.alloc[GroupToggle](a, total)
    if toggles_error != ok { ret (zero, TooLarge) }
    let (actions, actions_error) = mem.alloc[widget.Submit](a, total)
    if actions_error != ok { ret (zero, TooLarge) }
    let (resets, resets_error) = mem.alloc[Turn](a, total)
    if resets_error != ok { ret (zero, TooLarge) }
    let (reset_actions, reset_actions_error) = mem.alloc[widget.Submit](a, total)
    if reset_actions_error != ok { ret (zero, TooLarge) }
    var slot: f32 = 0.0
    if options.has_status { slot = 32.0 }
    var block_count = 0usize
    if options.kind.len > 0usize || options.name.len > 0usize {
        var heading = control.text_options()
        heading.wrap = .None
        heading.role = .TitleMedium
        let (kind_node, kind_error) = control.colored_text(a, 0u64, options.kind, t, heading, style.color(t.tokens, .OnSurface))
        if kind_error != ok { ret (zero, kind_error) }
        heading.role = .BodyMedium
        let (name_node, name_error) = control.colored_text(a, 0u64, options.name, t, heading, muted)
        if name_error != ok { ret (zero, name_error) }
        let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
        if pair_error != ok { ret (zero, TooLarge) }
        pair[0usize] = kind_node
        pair[1usize] = name_node
        var head_style = style.defaults()
        let eight = style.Length { Px: 8.0 }
        head_style.padding = style.EdgeLengths { left: eight, top: eight, right: eight, bottom: eight }
        blocks[block_count] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, head_style, pair[0usize..2usize])
        block_count += 1usize
    }
    if options.has_filter {
        var field = control.field_options()
        field.placeholder = "Filter properties"
        field.width = control.max_zero(width - 16.0)
        field.height = 32.0
        let (filter_node, filter_error) = control.text_field(a, key + 300u64, t, "Filter properties", options.filter, options.filter_len, options.filtering, zero, field)
        if filter_error != ok { ret (zero, filter_error) }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (zero, TooLarge) }
        held[0usize] = filter_node
        blocks[block_count] = widget.padded(0u64, 8.0, 4.0, 8.0, 4.0, style.defaults(), held[0usize..1usize])
        block_count += 1usize
    }
    var i = 0usize
    while i < total {
        // The group from `i` on: its matching rows into `rows`, then one block.
        let head = source.property(source.ctx, i)
        var end = i
        while end < total && same_text(source.property(source.ctx, end).group, head.group) { end += 1usize }
        let group_key = u64(i) + 1u64
        let open = head.group.len == 0usize || !is_selected(collapsed, group_key)
        var matched = 0usize
        var r = i
        while r < end {
            let p = source.property(source.ctx, r)
            if contains_folded(p.name, needle) {
                if open {
                    var standing: PropertyStatus = zero
                    if options.has_status { standing = options.status(source.ctx, r) }
                    var name_ink = muted
                    if standing.modified { name_ink = style.color(t.tokens, .OnSurface) }
                    var caption = control.text_options()
                    caption.role = .BodyMedium
                    caption.wrap = .None
                    caption.ellipsis = "…"
                    caption.max_lines = 1u32
                    let (name_node, name_error) = control.colored_text(a, 0u64, p.name, t, caption, name_ink)
                    if name_error != ok { ret (zero, name_error) }
                    let (named, named_error) = mem.alloc[widget.Node](a, 1usize)
                    if named_error != ok { ret (zero, TooLarge) }
                    named[0usize] = name_node
                    var name_sem: widget.Semantics = zero
                    name_sem.role = 31u8
                    name_sem.label = p.name
                    name_sem.row = u32(r + 1usize)
                    name_sem.column = 1u32
                    var name_style = style.defaults()
                    name_style.width = style.Length { Px: name_width }
                    name_style.overflow = .Clip
                    name_style.padding = style.EdgeLengths { left: style.Length { Px: start }, top: flat, right: style.Length { Px: 8.0 }, bottom: flat }
                    let (pair, pair_error) = mem.alloc[widget.Node](a, 3usize)
                    if pair_error != ok { ret (zero, TooLarge) }
                    pair[0usize] = widget.semantics(0u64, name_sem, name_style, named[0usize..1usize])
                    var editor: widget.Node = zero
                    let editor_error = source.editor(source.ctx, a, r, &editor)
                    if editor_error != ok { ret (zero, editor_error) }
                    let (valued, valued_error) = mem.alloc[widget.Node](a, 1usize)
                    if valued_error != ok { ret (zero, TooLarge) }
                    valued[0usize] = editor
                    if standing.message.len > 0usize {
                        // The message under the editor; the row grows.
                        let err_ink = style.color(t.tokens, .Error)
                        let (mark, mark_error) = control.icon_square(a, err_ink, .Alert, 16.0)
                        if mark_error != ok { ret (zero, mark_error) }
                        var small = control.text_options()
                        small.role = .BodySmall
                        small.wrap = .None
                        let (said, said_error) = control.colored_text(a, 0u64, standing.message, t, small, err_ink)
                        if said_error != ok { ret (zero, said_error) }
                        let (stacked, stacked_error) = mem.alloc[widget.Node](a, 4usize)
                        if stacked_error != ok { ret (zero, TooLarge) }
                        stacked[0usize] = mark
                        stacked[1usize] = said
                        stacked[2usize] = editor
                        stacked[3usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 4.0 }, style.defaults(), stacked[0usize..2usize])
                        valued[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 4.0 }, style.defaults(), stacked[2usize..4usize])
                    }
                    var value_sem: widget.Semantics = zero
                    value_sem.role = 14u8
                    value_sem.row = u32(r + 1usize)
                    value_sem.column = 2u32
                    var value_style = style.defaults()
                    value_style.width = style.Length { Px: control.max_zero(value_width - slot) }
                    pair[1usize] = widget.semantics(0u64, value_sem, value_style, valued[0usize..1usize])
                    var parts_in_row = 2usize
                    if options.has_status {
                        pair[2usize] = widget.box(0u64, control.sized_style(32.0, 32.0), zero)
                        if standing.modified {
                            resets[r] = Turn { index: r, turn: options.reset }
                            reset_actions[r] = widget.Submit { ctx: ctx_of(&resets[r]), invoke: turn_fire }
                            let (named_reset, named_reset_error) = joined(a, "Reset", "", p.name)
                            if named_reset_error != ok { ret (zero, named_reset_error) }
                            let (again, again_error) = glyph_in(a, key + 400u64 + u64(r), t, .Refresh, named_reset, &reset_actions[r], 32.0, t.tokens.sizes.icon_sm, control.with_alpha(style.color(t.tokens, .OnSurface), 0.0), muted, false, true)
                            if again_error != ok { ret (zero, again_error) }
                            pair[2usize] = again
                        }
                        parts_in_row = 3usize
                    }
                    var line_style = style.defaults()
                    line_style.width = style.Length { Px: width }
                    line_style.min_height = style.Length { Px: row_min }
                    line_style.padding = style.EdgeLengths { left: flat, top: flat, right: style.Length { Px: 8.0 }, bottom: flat }
                    let (lined, lined_error) = mem.alloc[widget.Node](a, 1usize)
                    if lined_error != ok { ret (zero, TooLarge) }
                    lined[0usize] = widget.flex(p.key, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, line_style, pair[0usize..parts_in_row])
                    var row_sem: widget.Semantics = zero
                    row_sem.role = 13u8
                    row_sem.row = u32(r + 1usize)
                    row_sem.row_count = u32(total)
                    rows[i + matched] = widget.semantics(0u64, row_sem, style.defaults(), lined[0usize..1usize])
                }
                matched += 1usize
            }
            r += 1usize
        }
        if matched == 0usize {
            i = end
            continue
        }
        var shown_rows = matched
        if !open { shown_rows = 0usize }
        let group_rows = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), rows[i..i + shown_rows])
        if head.group.len == 0usize {
            blocks[block_count] = group_rows
        } else {
            toggles[block_count] = GroupToggle { key: group_key, toggle: toggle }
            actions[block_count] = widget.Submit { ctx: ctx_of(&toggles[block_count]), invoke: group_toggle_fire }
            let heading_key = key + 1u64 + u64(i)
            let state = control.control_state(t, heading_key, true, false)
            var kind: control.GlyphKind = .ChevronRight
            if open { kind = .ChevronDown }
            let (chevron, chevron_error) = control.stroked_glyph(a, muted, kind, 15.0, 18.0 * 1.75 / 24.0)
            if chevron_error != ok { ret (zero, chevron_error) }
            let (drawn, drawn_error) = mem.alloc[widget.Node](a, 1usize)
            if drawn_error != ok { ret (zero, TooLarge) }
            drawn[0usize] = chevron
            let (parts, parts_error) = mem.alloc[widget.Node](a, 4usize)
            if parts_error != ok { ret (zero, TooLarge) }
            parts[0usize] = widget.padded(0u64, 4.5, 4.5, 4.5, 4.5, control.sized_style(24.0, 24.0), drawn[0usize..1usize])
            var title = control.text_options()
            title.role = .TitleSmall
            title.wrap = .None
            let (said, said_error) = control.colored_text(a, 0u64, head.group, t, title, style.color(t.tokens, .OnSurface))
            if said_error != ok { ret (zero, said_error) }
            parts[1usize] = said
            parts[2usize] = widget.spacer(0u64, 1.0)
            var p_count = 3usize
            if !open {
                let (counted, counted_error) = mem.alloc[u8](a, 40usize)
                if counted_error != ok { ret (zero, TooLarge) }
                var m = control.write_i64(counted, i64(matched))
                if matched == 1usize { m += control.copy_text(counted[m..40usize], " property") } else { m += control.copy_text(counted[m..40usize], " properties") }
                var small = control.text_options()
                small.role = .LabelSmall
                small.wrap = .None
                let (count_node, count_error) = control.colored_text(a, 0u64, counted[0usize..m], t, small, muted)
                if count_error != ok { ret (zero, count_error) }
                parts[3usize] = count_node
                p_count = 4usize
            }
            var bar_style = style.defaults()
            bar_style.width = style.Length { Px: control.max_zero(width - 16.0) }
            let content = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 4.0 }, bar_style, parts[0usize..p_count])
            var look = style.resolve(t.tokens, .Plain, state)
            look.background = control.with_alpha(style.color(t.tokens, .OnSurface), control.state_opacity(t, state))
            look.foreground = style.color(t.tokens, .OnSurface)
            look.border_width = 0.0
            look.opacity = 1.0
            look.radius = 0.0
            look.custom_padding = true
            look.padding = 8.0
            look.padding_y = control.max_zero((head_h - 24.0) * 0.5)
            look.min_height = head_h
            look.min_width = width
            var states = 0u32
            if open { states = accessibility.STATE_EXPANDED }
            let (header, header_error) = control.pressable_states(a, heading_key, t, 3u8, head.group, look, true, false, states, 0u32, 0u64, &actions[block_count], content)
            if header_error != ok { ret (zero, header_error) }
            let (stacked, stacked_error) = mem.alloc[widget.Node](a, 2usize)
            if stacked_error != ok { ret (zero, TooLarge) }
            stacked[0usize] = header
            stacked[1usize] = group_rows
            var group_style = style.defaults()
            if block_count > 0usize { group_style.padding = style.EdgeLengths { left: flat, top: style.Length { Px: 8.0 }, right: flat, bottom: flat } }
            blocks[block_count] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, group_style, stacked[0usize..2usize])
        }
        block_count += 1usize
        i = end
    }
    var column_style = style.defaults()
    column_style.width = style.Length { Px: width }
    let (column_node, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column_node[0usize] = widget.flex(key, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, column_style, blocks[0usize..block_count])
    var sem: widget.Semantics = zero
    sem.role = 12u8
    sem.label = label
    sem.row_count = u32(total)
    sem.column_count = 2u32
    ret (widget.semantics(0u64, sem, style.defaults(), column_node[0usize..1usize]), ok)
}

// A pair of a key-value editor: the caller's two buffers and their lengths.
type Pair = struct { name: []u8, name_len: usize, value: []u8, value_len: usize }

// An edit of a pair: which, whether the value (else the name), the text typed.
type PairEdit = struct { index: usize, value: bool, text: str }

type PairChange = struct { index: usize, value: bool, edit: widget.Change[PairEdit] }

fn pair_change_fire(ctx: *void, text: str) -> err {
    let c = mem.cast[*PairChange](ctx)
    ret widget.fire_change[PairEdit](c.edit, PairEdit { index: c.index, value: c.value, text: text })
}

type PairRemove = struct { index: usize, remove: widget.Change[usize] }

fn pair_remove_fire(ctx: *void) -> err {
    let r = mem.cast[*PairRemove](ctx)
    ret widget.fire_change[usize](r.remove, r.index)
}

// A key-value editor: a row a pair -- a name field (keyed `key + 1 + 3 * index`),
// a value field (`key + 2 + 3 * index`) and a remove button (`key + 3 + 3 * index`)
// -- every keystroke reaching `edit` with the pair, the side and the text, a
// remove reaching `remove` with the index, and an Add button (keyed
// `key + 3 * pairs.len + 4`) firing `add`; the caller keeps the pairs. A table
// of two columns in the tree named `label`. v2 (D983): drawn as
// `key_value_editor_of`.
fn key_value_editor(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, pairs: []const Pair, edit: widget.Change[PairEdit], remove: widget.Change[usize], add: *const widget.Submit, width: f32) -> (widget.Node, err) {
    let (made, made_error) = key_value_editor_of(a, key, t, label, pairs, edit, remove, add, width, key_value_options())
    ret (made, made_error)
}

// A key-value editor's words (D983): the column labels, the Add button's
// label and the Remove buttons' verb, for localisation.
type KeyValueOptions = struct { name_label: str, value_label: str, add_label: str, remove_label: str, duplicate_message: str }

fn key_value_options() -> KeyValueOptions {
    ret KeyValueOptions { name_label: "Name", value_label: "Value", add_label: "Add variable", remove_label: "Remove", duplicate_message: "Duplicate name" }
}

// Two words and a third joined by spaces into the arena ("Remove API_URL").
fn joined(a: *mem.Arena, first: str, second: str, third: []const u8) -> (str, err) {
    let (bytes, bytes_error) = mem.alloc[u8](a, first.len + second.len + third.len + 2usize)
    if bytes_error != ok { ret ("", TooLarge) }
    var n = control.copy_text(bytes, first)
    if second.len > 0usize {
        bytes[n] = 32u8
        n += 1usize
        n += control.copy_text(bytes[n..bytes.len], second)
    }
    if third.len > 0usize {
        bytes[n] = 32u8
        n += 1usize
        var k = 0usize
        while k < third.len {
            bytes[n + k] = third[k]
            k += 1usize
        }
        n += third.len
    }
    ret (bytes[0usize..n], ok)
}

// v2 (D983, docs/ux/components/KeyValueEditor): the column labels once, "Name"
// and "Value" in `label-medium` `on-surface-variant` 8 in; a row a pair of an
// outlined 40 name field (32 dense) and value field, 2 to 3 of the width left
// by a 40 remove button (32 dense), 8 apart (4 dense), rows 8 apart: the
// fields named "Name" and "Value of NAME" with placeholders, the remove a
// `close` icon button in `on-surface-variant` named "Remove NAME". A name that
// repeats an earlier one marks its field invalid with "Duplicate name" in
// `body-small` `error` after a 16 `error` icon under the row. An "Add variable"
// text button 8 below (keyed as before). A table of three columns named
// `label`, its rows Rows of Cells.
// ponytail: no empty add-row, secret values, text mode, ordered variant,
// removal with Undo, `code` names, or the touch list form; the Add button has
// no `add` glyph.
fn key_value_editor_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, pairs: []const Pair, edit: widget.Change[PairEdit], remove: widget.Change[usize], add: *const widget.Submit, width: f32, options: KeyValueOptions) -> (widget.Node, err) {
    if pairs.len > 128usize { ret (zero, TooLarge) }
    let dense = density_of(t) == 0usize
    let field_h = control.if_else(dense, 32.0, 40.0)
    let gap = control.if_else(dense, 4.0, 8.0)
    let remove_w = control.if_else(dense, 32.0, 40.0)
    let avail = control.max_zero(width - remove_w - 2.0 * gap)
    let name_w = avail * 0.4
    let value_w = avail - name_w
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    let (rows, rows_error) = mem.alloc[widget.Node](a, 2usize * pairs.len + 2usize)
    if rows_error != ok { ret (zero, TooLarge) }
    let (changes, changes_error) = mem.alloc[PairChange](a, 2usize * pairs.len)
    if changes_error != ok { ret (zero, TooLarge) }
    let (removes, removes_error) = mem.alloc[PairRemove](a, pairs.len)
    if removes_error != ok { ret (zero, TooLarge) }
    let (actions, actions_error) = mem.alloc[widget.Submit](a, pairs.len)
    if actions_error != ok { ret (zero, TooLarge) }
    var n = 0usize
    // The column labels, once.
    var caption = control.text_options()
    caption.role = .LabelMedium
    caption.wrap = .None
    let (name_head, name_head_error) = control.colored_text(a, 0u64, options.name_label, t, caption, muted)
    if name_head_error != ok { ret (zero, name_head_error) }
    let (value_head, value_head_error) = control.colored_text(a, 0u64, options.value_label, t, caption, muted)
    if value_head_error != ok { ret (zero, value_head_error) }
    let (heads, heads_error) = mem.alloc[widget.Node](a, 4usize)
    if heads_error != ok { ret (zero, TooLarge) }
    heads[0usize] = name_head
    heads[1usize] = value_head
    heads[2usize] = widget.padded(0u64, 8.0, 0.0, 0.0, 0.0, control.sized_style(name_w, 0.0), heads[0usize..1usize])
    heads[3usize] = widget.padded(0u64, 8.0, 0.0, 0.0, 0.0, control.sized_style(value_w, 0.0), heads[1usize..2usize])
    rows[n] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: gap }, style.defaults(), heads[2usize..4usize])
    n += 1usize
    var i = 0usize
    while i < pairs.len {
        changes[2usize * i] = PairChange { index: i, value: false, edit: edit }
        changes[2usize * i + 1usize] = PairChange { index: i, value: true, edit: edit }
        removes[i] = PairRemove { index: i, remove: remove }
        actions[i] = widget.Submit { ctx: ctx_of(&removes[i]), invoke: pair_remove_fire }
        let name_text = pairs[i].name[0usize..pairs[i].name_len]
        var repeated = false
        var k = 0usize
        while k < i {
            if name_text.len > 0usize && same_text(pairs[k].name[0usize..pairs[k].name_len], name_text) { repeated = true }
            k += 1usize
        }
        let (cells, cells_error) = mem.alloc[widget.Node](a, 6usize)
        if cells_error != ok { ret (zero, TooLarge) }
        var field = control.field_options()
        field.width = name_w
        field.height = field_h
        field.placeholder = options.name_label
        field.invalid = repeated
        let (name_field, name_error) = control.text_field(a, key + 1u64 + 3u64 * u64(i), t, options.name_label, pairs[i].name, pairs[i].name_len, widget.Change[str] { ctx: ctx_of(&changes[2usize * i]), invoke: pair_change_fire }, zero, field)
        if name_error != ok { ret (zero, name_error) }
        let (value_name, value_name_error) = joined(a, options.value_label, "of", name_text)
        if value_name_error != ok { ret (zero, value_name_error) }
        field.width = value_w
        field.placeholder = options.value_label
        field.invalid = false
        let (value_field, value_error) = control.text_field(a, key + 2u64 + 3u64 * u64(i), t, value_name, pairs[i].value, pairs[i].value_len, widget.Change[str] { ctx: ctx_of(&changes[2usize * i + 1usize]), invoke: pair_change_fire }, zero, field)
        if value_error != ok { ret (zero, value_error) }
        let (remove_name, remove_name_error) = joined(a, options.remove_label, "", name_text)
        if remove_name_error != ok { ret (zero, remove_name_error) }
        let (gone, gone_error) = glyph_in(a, key + 3u64 + 3u64 * u64(i), t, .Cross, remove_name, &actions[i], remove_w, control.if_else(dense, t.tokens.sizes.icon_sm, t.tokens.sizes.icon_md), control.with_alpha(style.color(t.tokens, .OnSurface), 0.0), muted, false, true)
        if gone_error != ok { ret (zero, gone_error) }
        cells[0usize] = name_field
        cells[1usize] = value_field
        cells[2usize] = gone
        var c = 0usize
        while c < 3usize {
            var cell_sem: widget.Semantics = zero
            cell_sem.role = 14u8
            cell_sem.row = u32(i + 1usize)
            cell_sem.column = u32(c + 1usize)
            cells[3usize + c] = widget.semantics(0u64, cell_sem, style.defaults(), cells[c..c + 1usize])
            c += 1usize
        }
        let (lined, lined_error) = mem.alloc[widget.Node](a, 1usize)
        if lined_error != ok { ret (zero, TooLarge) }
        lined[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: gap }, style.defaults(), cells[3usize..6usize])
        var row_sem: widget.Semantics = zero
        row_sem.role = 13u8
        row_sem.label = name_text
        row_sem.row = u32(i + 1usize)
        row_sem.row_count = u32(pairs.len)
        rows[n] = widget.semantics(0u64, row_sem, style.defaults(), lined[0usize..1usize])
        n += 1usize
        if repeated {
            let err_ink = style.color(t.tokens, .Error)
            let (mark, mark_error) = control.icon_square(a, err_ink, .Alert, 16.0)
            if mark_error != ok { ret (zero, mark_error) }
            var small = control.text_options()
            small.role = .BodySmall
            small.wrap = .None
            let (said, said_error) = control.colored_text(a, 0u64, options.duplicate_message, t, small, err_ink)
            if said_error != ok { ret (zero, said_error) }
            let (note, note_error) = mem.alloc[widget.Node](a, 2usize)
            if note_error != ok { ret (zero, TooLarge) }
            note[0usize] = mark
            note[1usize] = said
            rows[n] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 4.0 }, style.defaults(), note[0usize..2usize])
            n += 1usize
        }
        i += 1usize
    }
    var plain = control.button_options()
    plain.variant = .Plain
    let (more, more_error) = control.button(a, key + 3u64 * u64(pairs.len) + 4u64, t, options.add_label, add, plain)
    if more_error != ok { ret (zero, more_error) }
    rows[n] = more
    n += 1usize
    var column_style = style.defaults()
    column_style.width = style.Length { Px: width }
    let (column_node, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column_node[0usize] = widget.flex(key, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: gap }, column_style, rows[0usize..n])
    var sem: widget.Semantics = zero
    sem.role = 12u8
    sem.label = label
    sem.row_count = u32(pairs.len)
    sem.column_count = 3u32
    ret (widget.semantics(0u64, sem, style.defaults(), column_node[0usize..1usize]), ok)
}

// ------------------------------------------------------- v2 collections (D979, P5-12)

// A row's content (D979, docs/ux/components/Row): the headline, the supporting
// line and the overline (either may be empty), the meta at the end, a leading
// and a trailing glyph, whether it is selected (and then marked with a trailing
// check, for a single-select list), disabled, and its primary action.
type RowItem = struct { headline: str, supporting: str, overline: str, meta: str, leading: control.GlyphKind, has_leading: bool, trailing: control.GlyphKind, has_trailing: bool, selected: bool, check: bool, disabled: bool, action: widget.Submit }

fn row_item(headline: str) -> RowItem {
    var out: RowItem = zero
    out.headline = headline
    ret out
}

// The density a collection draws at: 2 touch, 1 pointer, 0 dense.
fn density_of(t: *const control.Theme) -> usize {
    if t.tokens.metrics.control_height > t.tokens.sizes.control_sm { ret 2usize }
    if t.tokens.metrics.control_height < t.tokens.sizes.control_sm { ret 0usize }
    ret 1usize
}

// A row's height for its line count: 56 / 72 / 88 on touch, 48 / 64 / 80 with a
// pointer, 32 / 48 dense.
fn row_height(t: *const control.Theme, lines: usize) -> f32 {
    let d = density_of(t)
    var base: f32 = 48.0
    if d == 2usize { base = 56.0 }
    if d == 0usize { base = 32.0 }
    var extra = lines
    if extra > 0usize { extra -= 1usize }
    if extra > 2usize { extra = 2usize }
    ret base + 16.0 * f32(extra)
}

fn row_lines(item: *const RowItem) -> usize {
    var lines = 1usize
    if item.supporting.len > 0usize { lines += 1usize }
    if item.overline.len > 0usize { lines += 1usize }
    ret lines
}

// v2 (D979, docs/ux/components/Row): a full-width square row (keyed `key`), its
// height by line count and density (`row_height`), 16 in at the start and 24 at
// the end (12 dense), 8 above and below (0 dense); a leading 24 glyph (18 dense)
// in `on-surface-variant` 16 before the text (12 dense); the `label-small`
// overline and `body-medium` supporting line in `on-surface-variant` round the
// `body-large` headline (`body-medium` dense, supporting `body-small`) in
// `on-surface`, one line each, ellipsised; the `label-small` meta and a 24
// trailing glyph at the end; the `on-surface` state layer over the whole row.
// Selected, the row is `secondary-container` and every part
// `on-secondary-container`, with a trailing check when asked. Disabled, every
// part is `on-surface` at 38%, under no layer and out of the Tab order. A tap
// runs the action; a list item in the tree named by the headline, described by
// the supporting line, at `index` of `count`.
// ponytail: no avatar, thumbnail or control leading slot, no context menu,
// long press or selection animation; the focus ring is the runtime's, inset
// where the list clips it.
fn row_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, item: *const RowItem, index: usize, count: usize, width: f32) -> (widget.Node, err) {
    let (made, made_error) = row_sized(a, key, t, item, index, count, width, row_height(t, row_lines(item)))
    ret (made, made_error)
}

fn row_sized(a: *mem.Arena, key: widget.Key, t: *const control.Theme, item: *const RowItem, index: usize, count: usize, width: f32, height: f32) -> (widget.Node, err) {
    let dense = density_of(t) == 0usize
    let lines = row_lines(item)
    let enabled = !item.disabled
    let state = control.control_state(t, key, enabled, item.selected)
    let surface_ink = style.color(t.tokens, .OnSurface)
    var ink = surface_ink
    var muted = style.color(t.tokens, .OnSurfaceVariant)
    var fill = control.with_alpha(surface_ink, control.state_opacity(t, state))
    if item.selected {
        ink = style.color(t.tokens, .OnSecondaryContainer)
        muted = ink
        fill = style.layer(style.color(t.tokens, .SecondaryContainer), ink, control.state_opacity(t, state))
    }
    if !enabled {
        ink = control.with_alpha(surface_ink, t.tokens.states.disabled_content)
        muted = ink
        fill = control.with_alpha(surface_ink, 0.0)
    }
    let glyph_side = control.if_else(dense, t.tokens.sizes.icon_sm, t.tokens.sizes.icon_md)
    let (parts, parts_error) = mem.alloc[widget.Node](a, 5usize)
    if parts_error != ok { ret (zero, TooLarge) }
    var p = 0usize
    if item.has_leading {
        let (lead, lead_error) = control.icon_square(a, muted, item.leading, glyph_side)
        if lead_error != ok { ret (zero, lead_error) }
        parts[p] = lead
        p += 1usize
    }
    // The text: overline, headline and supporting line, one line each.
    let (words, words_error) = mem.alloc[widget.Node](a, 3usize)
    if words_error != ok { ret (zero, TooLarge) }
    var w = 0usize
    var caption = control.text_options()
    caption.wrap = .None
    caption.max_lines = 1u32
    caption.ellipsis = "…"
    if item.overline.len > 0usize {
        caption.role = .LabelSmall
        let (over, over_error) = control.colored_text(a, 0u64, item.overline, t, caption, muted)
        if over_error != ok { ret (zero, over_error) }
        words[w] = over
        w += 1usize
    }
    caption.role = .BodyLarge
    if dense { caption.role = .BodyMedium }
    let (head, head_error) = control.colored_text(a, 0u64, item.headline, t, caption, ink)
    if head_error != ok { ret (zero, head_error) }
    words[w] = head
    w += 1usize
    if item.supporting.len > 0usize {
        caption.role = .BodyMedium
        if dense { caption.role = .BodySmall }
        let (support, support_error) = control.colored_text(a, 0u64, item.supporting, t, caption, muted)
        if support_error != ok { ret (zero, support_error) }
        words[w] = support
        w += 1usize
    }
    var text_style = style.defaults()
    text_style.width = style.Length { Flex: 1.0 }
    parts[p] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Center, cross: .Start, gap: 0.0 }, text_style, words[0usize..w])
    p += 1usize
    if item.meta.len > 0usize {
        caption.role = .LabelSmall
        let (meta_node, meta_error) = control.colored_text(a, 0u64, item.meta, t, caption, muted)
        if meta_error != ok { ret (zero, meta_error) }
        parts[p] = meta_node
        p += 1usize
    }
    if item.check && item.selected {
        let (tick, tick_error) = control.icon_square(a, ink, .Check, t.tokens.sizes.icon_md)
        if tick_error != ok { ret (zero, tick_error) }
        parts[p] = tick
        p += 1usize
    } else if item.has_trailing {
        let (tail, tail_error) = control.icon_square(a, muted, item.trailing, glyph_side)
        if tail_error != ok { ret (zero, tail_error) }
        parts[p] = tail
        p += 1usize
    }
    // Three lines put the slots at the top of the text, 4 below the padding.
    var cross: ui_layout.CrossAlign = .Center
    if lines >= 3usize { cross = .Start }
    var line_style = style.defaults()
    line_style.width = style.Length { Percent: 100.0 }
    line_style.height = style.Length { Flex: 1.0 }
    let content = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: cross, gap: control.if_else(dense, 12.0, 16.0) }, line_style, parts[0usize..p])
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, TooLarge) }
    held[0usize] = content
    var row_style = style.defaults()
    row_style.width = style.Length { Percent: 100.0 }
    if width > 0.0 { row_style.width = style.Length { Px: width } }
    row_style.height = style.Length { Px: height }
    row_style.background = paint.Brush { Solid: fill }
    let side = style.Length { Px: control.if_else(dense, 0.0, 8.0) }
    row_style.padding = style.EdgeLengths { left: style.Length { Px: 16.0 }, top: side, right: style.Length { Px: control.if_else(dense, 12.0, 24.0) }, bottom: side }
    let (region, region_error) = mem.alloc[widget.Node](a, 1usize)
    if region_error != ok { ret (zero, TooLarge) }
    control.focus_look(t)
    region[0usize] = widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: ctx_of(&item.action), invoke: control.press_tap }, gestures: 1u8 | 4u8, enabled: enabled, focusable: enabled }, row_style, held[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 11u8
    sem.label = item.headline
    sem.hint = item.supporting
    sem.row = u32(index + 1usize)
    sem.row_count = u32(count)
    sem.actions = accessibility.ACTION_PRESS
    if item.selected { sem.states = accessibility.STATE_SELECTED }
    if !enabled { sem.states = sem.states | accessibility.STATE_DISABLED }
    ret (widget.semantics(0u64, sem, style.defaults(), region[0usize..1usize]), ok)
}

// A typed pointer as a callback's context (D982): the one widening cast the
// v2 collections share. The build's unsafe inventory lists a function once per
// kind of unsafe operation, and the example app's build manifest (65536 bytes
// plus 512 a module, src/tool.e) had room for no more such functions.
// ponytail: a src/ fix sizing the manifest by its inventory would let each
// builder cast for itself again.
fn ctx_of[T: type](p: *const T) -> *void {
    ret mem.cast[*void](p)
}

// A callback's context back as its type (D984): the narrowing twin of `ctx_of`,
// so the data grid's callbacks hold no cast of their own.
fn back_of[T: type](ctx: *void) -> *T {
    ret mem.cast[*T](ctx)
}

// One arrow of a roving focus (D979): the key moving it to the element keyed
// `key`, through the accordion's `control.FocusTo`.
fn bind_move(moves: []control.FocusTo, shortcuts: []widget.Shortcut, at: usize, runtime: *widget.Runtime, key: widget.Key, code: u32) {
    moves[at] = control.FocusTo { runtime: runtime, key: key }
    shortcuts[at] = widget.Shortcut { key: code, modifiers: zero, action: widget.Submit { ctx: ctx_of(&moves[at]), invoke: control.focus_to_fire } }
}

// Roving focus over `nodes` keyed `keys`, `across` to a row (1 for a list), each
// node wrapped in a scope (D979): Up and Down move a row, Left and Right one
// item when there are columns, Home and End to the first and last.
fn roving(a: *mem.Arena, t: *const control.Theme, nodes: []widget.Node, keys: []const widget.Key, across: usize) -> err {
    let n = nodes.len
    if n == 0usize || mem.address_of(t.runtime) == 0usize { ret ok }
    let (moves, moves_error) = mem.alloc[control.FocusTo](a, 6usize * n)
    if moves_error != ok { ret TooLarge }
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 6usize * n)
    if shortcuts_error != ok { ret TooLarge }
    let (held, held_error) = mem.alloc[widget.Node](a, n)
    if held_error != ok { ret TooLarge }
    var i = 0usize
    while i < n {
        let base = 6usize * i
        var k = base
        if i >= across {
            bind_move(moves, shortcuts, k, t.runtime, keys[i - across], 38u32)
            k += 1usize
        }
        if i + across < n {
            bind_move(moves, shortcuts, k, t.runtime, keys[i + across], 40u32)
            k += 1usize
        }
        if across > 1usize && i > 0usize {
            bind_move(moves, shortcuts, k, t.runtime, keys[i - 1usize], 37u32)
            k += 1usize
        }
        if across > 1usize && i + 1usize < n {
            bind_move(moves, shortcuts, k, t.runtime, keys[i + 1usize], 39u32)
            k += 1usize
        }
        bind_move(moves, shortcuts, k, t.runtime, keys[0usize], 36u32)
        bind_move(moves, shortcuts, k + 1usize, t.runtime, keys[n - 1usize], 35u32)
        k += 2usize
        held[i] = nodes[i]
        nodes[i] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: shortcuts[base..k], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), held[i..i + 1usize])
        i += 1usize
    }
    ret ok
}

// A list's form (D979): grouped (`surface-container-low`, `radius-md`) or full
// bleed; dividers between rows inset by `inset` (16 when grouped and 0); a
// subheader over the rows; a group title above and a footnote below (grouped);
// the width (0: the parent's); and the empty state's statement and suggestion.
type ListOptions = struct { grouped: bool, dividers: bool, inset: f32, subheader: str, title: str, footnote: str, width: f32, empty_title: str, empty_message: str }

fn list_options() -> ListOptions {
    var out: ListOptions = zero
    ret out
}

// v2 (D979, docs/ux/components/List): the rows (`row_of`, keyed by `keys`) on
// `surface` with 8 above and below, or grouped on `surface-container-low` with
// `radius-md`, no padding, its `label-medium` `on-surface-variant` title 16 in
// and 8 above and its `body-small` footnote 16 in and 8 below; 1px
// `outline-variant` dividers between rows, inset `inset` (16 grouped); a
// `title-small` `primary` subheader 16 in, 16 above and 8 below. One Tab stop a
// row with Up, Down, Home and End moving the focus. With no rows and an
// `empty_title`, the compact empty state stands in their place. A list named
// `label` with its count.
// ponytail: no selection model (the caller sets `selected`), no Page keys,
// typeahead, selection bar, sticky subheader, loading rows or insert motion.
fn list_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, items: []const RowItem, keys: []const widget.Key, options: ListOptions) -> (widget.Node, err) {
    if keys.len != items.len { ret (zero, TooLarge) }
    let (rows, rows_error) = mem.alloc[widget.Node](a, items.len)
    if rows_error != ok { ret (zero, TooLarge) }
    var width = options.width
    var i = 0usize
    while i < items.len {
        let (made, made_error) = row_of(a, keys[i], t, &items[i], i, items.len, width)
        if made_error != ok { ret (zero, made_error) }
        rows[i] = made
        i += 1usize
    }
    let rove_error = roving(a, t, rows, keys, 1usize)
    if rove_error != ok { ret (zero, rove_error) }
    var inset = options.inset
    if options.grouped && !(inset > 0.0) { inset = 16.0 }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize * items.len + 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    var p = 0usize
    if options.subheader.len > 0usize {
        var heading = control.text_options()
        heading.role = .TitleSmall
        heading.wrap = .None
        let (said, said_error) = control.colored_text(a, 0u64, options.subheader, t, heading, style.color(t.tokens, .Primary))
        if said_error != ok { ret (zero, said_error) }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (zero, TooLarge) }
        held[0usize] = said
        parts[p] = widget.padded(0u64, 16.0, 16.0, 16.0, 8.0, style.defaults(), held[0usize..1usize])
        p += 1usize
    }
    i = 0usize
    while i < items.len {
        if options.dividers && i > 0usize {
            var line = control.divider_options()
            line.start = inset
            let (drawn, drawn_error) = control.divider_of(a, 0u64, t, line)
            if drawn_error != ok { ret (zero, drawn_error) }
            parts[p] = drawn
            p += 1usize
        }
        parts[p] = rows[i]
        p += 1usize
        i += 1usize
    }
    if items.len == 0usize && options.empty_title.len > 0usize {
        var empty = control.empty_options()
        empty.compact = true
        empty.width = width
        let (said, said_error) = control.empty_state_of(a, key + 1u64, t, options.empty_title, options.empty_message, empty)
        if said_error != ok { ret (zero, said_error) }
        parts[p] = said
        p += 1usize
    }
    var box_style = style.defaults()
    if width > 0.0 { box_style.width = style.Length { Px: width } }
    if options.grouped {
        box_style.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerLow) }
        box_style.radius = t.tokens.radii.md
        box_style.overflow = .Clip
    } else {
        box_style.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
        let eight = style.Length { Px: 8.0 }
        let none = style.Length { Px: 0.0 }
        box_style.padding = style.EdgeLengths { left: none, top: eight, right: none, bottom: eight }
    }
    let body = widget.flex(key, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, box_style, parts[0usize..p])
    let (outer, outer_error) = mem.alloc[widget.Node](a, 3usize)
    if outer_error != ok { ret (zero, TooLarge) }
    var o = 0usize
    var note = control.text_options()
    note.wrap = .None
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    if options.grouped && options.title.len > 0usize {
        note.role = .LabelMedium
        let (said, said_error) = control.colored_text(a, 0u64, options.title, t, note, muted)
        if said_error != ok { ret (zero, said_error) }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (zero, TooLarge) }
        held[0usize] = said
        outer[o] = widget.padded(0u64, 16.0, 0.0, 16.0, 8.0, style.defaults(), held[0usize..1usize])
        o += 1usize
    }
    outer[o] = body
    o += 1usize
    if options.grouped && options.footnote.len > 0usize {
        note.role = .BodySmall
        let (said, said_error) = control.colored_text(a, 0u64, options.footnote, t, note, muted)
        if said_error != ok { ret (zero, said_error) }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (zero, TooLarge) }
        held[0usize] = said
        outer[o] = widget.padded(0u64, 16.0, 8.0, 16.0, 0.0, style.defaults(), held[0usize..1usize])
        o += 1usize
    }
    var sem: widget.Semantics = zero
    sem.role = 10u8
    sem.label = label
    sem.row_count = u32(items.len)
    ret (widget.semantics(0u64, sem, style.defaults(), outer[0usize..o]), ok)
}

// A source of rows (D979): the count, a row's stable key and its content.
type RowSource = struct { ctx: *void, count: fn(*void) -> usize, key: fn(*void, usize) -> widget.Key, item: fn(*void, usize) -> RowItem }

// A virtual list's form (D979): the rows' line count (one height a list),
// dividers and their inset, the viewport's size, the offset and whom to tell.
type VirtualListOptions = struct { lines: usize, dividers: bool, inset: f32, width: f32, height: f32, offset: f32, change: widget.Change[f32] }

fn virtual_list_options() -> VirtualListOptions {
    var out: VirtualListOptions = zero
    out.lines = 1usize
    ret out
}

// v2 (D979, docs/ux/components/VirtualList): the source's rows as `row_of`
// rows of one height for `lines` in a clipped viewport (keyed `key`) on
// `surface`, only those in view built (one above, two below) and keyed by the
// source; a 1px `outline-variant` divider inset `inset` under every row but the
// last; the runtime's rounded thumb in `on-surface-variant` at 50%; Up, Down,
// Home and End moving the focus among the built rows. A list named `label` with
// the full count, each row at its true position.
// ponytail: overscan is not a screen each way, the focus does not scroll to
// rows outside the window; no sticky headers, placeholders, end cap, paging or
// end-anchored mode.
fn virtual_list_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, source: RowSource, options: VirtualListOptions) -> (widget.Node, err) {
    let extent = row_height(t, options.lines)
    let total = source.count(source.ctx)
    let (first, count) = widget.visible_range(options.offset, options.height, total, extent)
    let (items, items_error) = mem.alloc[RowItem](a, count)
    if items_error != ok { ret (zero, TooLarge) }
    let (keys, keys_error) = mem.alloc[widget.Key](a, count)
    if keys_error != ok { ret (zero, TooLarge) }
    let (rows, rows_error) = mem.alloc[widget.Node](a, count)
    if rows_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < count {
        let index = first + i
        items[i] = source.item(source.ctx, index)
        keys[i] = source.key(source.ctx, index)
        let lined = options.dividers && index + 1usize < total
        let (made, made_error) = row_sized(a, keys[i], t, &items[i], index, total, options.width, extent - control.if_else(lined, t.tokens.sizes.divider, 0.0))
        if made_error != ok { ret (zero, made_error) }
        rows[i] = made
        i += 1usize
    }
    let rove_error = roving(a, t, rows, keys, 1usize)
    if rove_error != ok { ret (zero, rove_error) }
    i = 0usize
    while i < count {
        if options.dividers && first + i + 1usize < total {
            let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
            if pair_error != ok { ret (zero, TooLarge) }
            pair[0usize] = rows[i]
            var line = control.divider_options()
            line.start = options.inset
            let (drawn, drawn_error) = control.divider_of(a, 0u64, t, line)
            if drawn_error != ok { ret (zero, drawn_error) }
            pair[1usize] = drawn
            rows[i] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, style.defaults(), pair[0usize..2usize])
        }
        i += 1usize
    }
    var view_style = control.sized_style(options.width, options.height)
    view_style.overflow = .Clip
    view_style.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = widget.scroll(key, widget.Scroll { axis: .Vertical, offset: options.offset, overscroll: .Clamp, momentum: true, scrollbar: true, thumb: control.with_alpha(style.color(t.tokens, .OnSurfaceVariant), 0.5), change: options.change, virtual_first: first, virtual_count: total, virtual_extent: extent }, view_style, rows[0usize..count])
    var sem: widget.Semantics = zero
    sem.role = 10u8
    sem.label = label
    sem.row_count = u32(total)
    ret (widget.semantics(0u64, sem, style.defaults(), body[0usize..1usize]), ok)
}

// A tile of a grid (D979, docs/ux/components/GridView): its name and meta, its
// media (or none, for the placeholder), whether it is selected or disabled, and
// its action.
type Tile = struct { name: str, meta: str, media: widget.Node, has_media: bool, selected: bool, disabled: bool, action: widget.Submit }

fn tile_of_name(name: str) -> Tile {
    var out: Tile = zero
    out.name = name
    ret out
}

// v2 (D979, docs/ux/components/GridView, VirtualGrid): a tile `side` wide
// (keyed `key`). A media tile is `surface-container-low` with `radius-md`: its
// 4:3 media edge to edge at the top, then its `title-small` `on-surface` name
// and `body-small` `on-surface-variant` meta 8 below the media and 12 in. A
// photo tile is its 1:1 media alone with `radius-sm`. Media is
// `surface-container-highest` with a 36 picture glyph in `on-surface-variant`
// when there is none. Selected, the tile is `secondary-container`, its content
// `on-secondary-container`, the media inset 8 with `radius-xs`, and the check
// filled: a 24 `primary` circle with an `on-primary` tick, 12 from the corner;
// while selecting, an unselected tile shows the check as a 2px
// `on-surface-variant` ring 8 from the corner. The `on-surface` state layer lies
// on the tile. Disabled, content at 38% and media at 38% opacity, out of the Tab
// order. A cell in the tree named by the name, described by the meta.
// ponytail: the state layer lies under the media, not over it; the check's tick
// strokes 2 rather than 2.5; no drag, drop look or icon tile.
fn tile_node(a: *mem.Arena, key: widget.Key, t: *const control.Theme, item: *const Tile, row_index: usize, column_index: usize, side: f32, photo: bool, selecting: bool) -> (widget.Node, err) {
    let enabled = !item.disabled
    let state = control.control_state(t, key, enabled, item.selected)
    let surface_ink = style.color(t.tokens, .OnSurface)
    var ink = surface_ink
    var muted = style.color(t.tokens, .OnSurfaceVariant)
    var base = style.color(t.tokens, .SurfaceContainerLow)
    if photo { base = control.with_alpha(surface_ink, 0.0) }
    if item.selected {
        base = style.color(t.tokens, .SecondaryContainer)
        ink = style.color(t.tokens, .OnSecondaryContainer)
        muted = ink
    }
    if !enabled {
        ink = control.with_alpha(surface_ink, t.tokens.states.disabled_content)
        muted = ink
    }
    let fill = style.layer(base, ink, control.state_opacity(t, state))
    var tile_radius = t.tokens.radii.md
    if photo { tile_radius = t.tokens.radii.sm }
    var inset: f32 = 0.0
    if item.selected { inset = 8.0 }
    let media_width = control.max_zero(side - 2.0 * inset)
    var media_height = media_width * 0.75
    if photo { media_height = media_width }
    var media_style = control.sized_style(media_width, media_height)
    media_style.overflow = .Clip
    if item.selected { media_style.radius = t.tokens.radii.xs } else if photo { media_style.radius = tile_radius }
    media_style.margin = style.EdgeLengths { left: style.Length { Px: inset }, top: style.Length { Px: inset }, right: style.Length { Px: inset }, bottom: style.Length { Px: 0.0 } }
    if !enabled { media_style.opacity = t.tokens.states.disabled_content }
    let (shown, shown_error) = mem.alloc[widget.Node](a, 1usize)
    if shown_error != ok { ret (zero, TooLarge) }
    if item.has_media {
        shown[0usize] = item.media
    } else {
        media_style.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerHighest) }
        let (art, art_error) = control.icon_square(a, style.color(t.tokens, .OnSurfaceVariant), .Picture, 36.0)
        if art_error != ok { ret (zero, art_error) }
        shown[0usize] = art
    }
    let (column_parts, column_error) = mem.alloc[widget.Node](a, 2usize)
    if column_error != ok { ret (zero, TooLarge) }
    column_parts[0usize] = widget.aligned(0u64, .Center, .Center, media_style, shown[0usize..1usize])
    var c = 1usize
    if !photo {
        let (words, words_error) = mem.alloc[widget.Node](a, 2usize)
        if words_error != ok { ret (zero, TooLarge) }
        var caption = control.text_options()
        caption.wrap = .None
        caption.max_lines = 1u32
        caption.ellipsis = "…"
        caption.role = .TitleSmall
        let (named, named_error) = control.colored_text(a, 0u64, item.name, t, caption, ink)
        if named_error != ok { ret (zero, named_error) }
        words[0usize] = named
        var w = 1usize
        if item.meta.len > 0usize {
            caption.role = .BodySmall
            let (meta_node, meta_error) = control.colored_text(a, 0u64, item.meta, t, caption, muted)
            if meta_error != ok { ret (zero, meta_error) }
            words[1usize] = meta_node
            w = 2usize
        }
        var caption_style = style.defaults()
        caption_style.padding = style.EdgeLengths { left: style.Length { Px: 12.0 }, top: style.Length { Px: 8.0 }, right: style.Length { Px: 12.0 }, bottom: style.Length { Px: 12.0 } }
        column_parts[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, caption_style, words[0usize..w])
        c = 2usize
    }
    let (stacked, stacked_error) = mem.alloc[widget.Node](a, 2usize)
    if stacked_error != ok { ret (zero, TooLarge) }
    stacked[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), column_parts[0usize..c])
    var s_count = 1usize
    if item.selected || selecting {
        var mark = control.sized_style(24.0, 24.0)
        mark.radius = 12.0
        var corner: f32 = 8.0
        let (tick, tick_error) = mem.alloc[widget.Node](a, 1usize)
        if tick_error != ok { ret (zero, TooLarge) }
        var ticks = 0usize
        if item.selected {
            corner = 12.0
            mark.background = paint.Brush { Solid: style.color(t.tokens, .Primary) }
            let (drawn, drawn_error) = control.mark_glyph(a, style.color(t.tokens, .OnPrimary), .Check, 16.0)
            if drawn_error != ok { ret (zero, drawn_error) }
            tick[0usize] = drawn
            ticks = 1usize
        } else {
            mark.border = style.Border { width: 2.0, color: style.color(t.tokens, .OnSurfaceVariant) }
        }
        let (centred, centred_error) = mem.alloc[widget.Node](a, 1usize)
        if centred_error != ok { ret (zero, TooLarge) }
        centred[0usize] = widget.aligned(0u64, .Center, .Center, mark, tick[0usize..ticks])
        stacked[1usize] = widget.positioned(0u64, corner, corner, style.defaults(), centred[0usize..1usize])
        s_count = 2usize
    }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, TooLarge) }
    held[0usize] = widget.stack(0u64, style.defaults(), stacked[0usize..s_count])
    var tile_style = style.defaults()
    tile_style.width = style.Length { Px: side }
    tile_style.radius = tile_radius
    tile_style.overflow = .Clip
    tile_style.background = paint.Brush { Solid: fill }
    if photo { tile_style.height = style.Length { Px: side } }
    let (region, region_error) = mem.alloc[widget.Node](a, 1usize)
    if region_error != ok { ret (zero, TooLarge) }
    control.focus_look(t)
    region[0usize] = widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: ctx_of(&item.action), invoke: control.press_tap }, gestures: 1u8 | 4u8, enabled: enabled, focusable: enabled }, tile_style, held[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 14u8
    sem.label = item.name
    sem.hint = item.meta
    sem.row = u32(row_index + 1usize)
    sem.column = u32(column_index + 1usize)
    sem.actions = accessibility.ACTION_PRESS
    if item.selected { sem.states = accessibility.STATE_SELECTED }
    if !enabled { sem.states = sem.states | accessibility.STATE_DISABLED }
    ret (widget.semantics(0u64, sem, style.defaults(), region[0usize..1usize]), ok)
}

// A grid's form (D979): the least tile width (0: 144 with a pointer, 160 on
// touch), whether it is selecting (every tile shows its check), and the width.
type GridOptions = struct { min_width: f32, selecting: bool, width: f32 }

fn grid_options() -> GridOptions {
    var out: GridOptions = zero
    ret out
}

// v2 (D979, docs/ux/components/GridView): media tiles (`tile_node`, keyed by
// `keys`) in `floor((width + 8) / (min + 8))` equal columns 8 apart both ways,
// stretched to fill the width; arrows move the focus in two dimensions, Home
// and End to the first and last. A grid named `label` with its counts.
// ponytail: no selection model, typeahead, Page keys, rubber band, reflow
// motion, loading or empty state; the caller keeps the page margins.
fn grid_view_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, tiles: []const Tile, keys: []const widget.Key, options: GridOptions) -> (widget.Node, err) {
    if keys.len != tiles.len { ret (zero, TooLarge) }
    var least = options.min_width
    if !(least > 0.0) { least = control.if_else(density_of(t) == 2usize, 160.0, 144.0) }
    let columns = columns_across(options.width, least, 8.0)
    let side = (options.width - 8.0 * f32(columns - 1usize)) / f32(columns)
    let (cells, cells_error) = mem.alloc[widget.Node](a, tiles.len)
    if cells_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < tiles.len {
        let (made, made_error) = tile_node(a, keys[i], t, &tiles[i], i / columns, i % columns, side, false, options.selecting)
        if made_error != ok { ret (zero, made_error) }
        cells[i] = made
        i += 1usize
    }
    let rove_error = roving(a, t, cells, keys, columns)
    if rove_error != ok { ret (zero, rove_error) }
    var flow_style = style.defaults()
    flow_style.width = style.Length { Px: options.width }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = widget.wrap(key, ui_layout.Wrap { axis: .Horizontal, main_gap: 8.0, cross_gap: 8.0 }, flow_style, cells[0usize..tiles.len])
    var sem: widget.Semantics = zero
    sem.role = 30u8
    sem.label = label
    sem.column_count = u32(columns)
    sem.row_count = u32((tiles.len + columns - 1usize) / columns)
    ret (widget.semantics(0u64, sem, style.defaults(), body[0usize..1usize]), ok)
}

// A source of tiles (D979): the count, a tile's stable key and its content.
type TileSource = struct { ctx: *void, count: fn(*void) -> usize, key: fn(*void, usize) -> widget.Key, tile: fn(*void, usize) -> Tile }

// A virtual grid's form (D979): the least tile width (0: 112 with a pointer, 96
// on touch), selecting, the viewport's size, the offset and whom to tell.
type VirtualGridOptions = struct { min_width: f32, selecting: bool, width: f32, height: f32, offset: f32, change: widget.Change[f32] }

fn virtual_grid_options() -> VirtualGridOptions {
    var out: VirtualGridOptions = zero
    ret out
}

// v2 (D979, docs/ux/components/VirtualGrid): photo tiles (`tile_node`, 1:1,
// `radius-sm`) in `floor((width - 24 + 4) / (min + 4))` columns 4 apart, 12 in
// at the sides, stretched to fill, in a clipped viewport (keyed `key`) on
// `surface`; only the visible rows built, each tile keyed by the source; the
// runtime's rounded thumb in `on-surface-variant` at 50%; arrows, Home and End
// move the focus among the built tiles. A grid named `label` with its counts.
// ponytail: rows are keyed by position, not by the tiles they hold; no 12 top
// padding, sticky section headers, placeholders, paging, scrub label or size
// levels; focus does not scroll to unbuilt rows.
fn virtual_grid_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, source: TileSource, options: VirtualGridOptions) -> (widget.Node, err) {
    var least = options.min_width
    if !(least > 0.0) { least = control.if_else(density_of(t) == 2usize, 96.0, 112.0) }
    let total = source.count(source.ctx)
    let usable = control.max_zero(options.width - 24.0)
    let columns = columns_across(usable, least, 4.0)
    let side = (usable - 4.0 * f32(columns - 1usize)) / f32(columns)
    let row_total = (total + columns - 1usize) / columns
    let extent = side + 4.0
    let (first, count) = widget.visible_range(options.offset, options.height, row_total, extent)
    var built_first = first * columns
    var built = count * columns
    if built_first > total { built_first = total }
    if built_first + built > total { built = total - built_first }
    let (tiles, tiles_error) = mem.alloc[Tile](a, built)
    if tiles_error != ok { ret (zero, TooLarge) }
    let (keys, keys_error) = mem.alloc[widget.Key](a, built)
    if keys_error != ok { ret (zero, TooLarge) }
    let (cells, cells_error) = mem.alloc[widget.Node](a, built)
    if cells_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < built {
        let index = built_first + i
        tiles[i] = source.tile(source.ctx, index)
        keys[i] = source.key(source.ctx, index)
        let (made, made_error) = tile_node(a, keys[i], t, &tiles[i], index / columns, index % columns, side, true, options.selecting)
        if made_error != ok { ret (zero, made_error) }
        cells[i] = made
        i += 1usize
    }
    let rove_error = roving(a, t, cells, keys, columns)
    if rove_error != ok { ret (zero, rove_error) }
    let (rows, rows_error) = mem.alloc[widget.Node](a, count)
    if rows_error != ok { ret (zero, TooLarge) }
    var r = 0usize
    var made_rows = 0usize
    while r < count {
        let from = r * columns
        if from >= built { break }
        var to = from + columns
        if to > built { to = built }
        var line = style.defaults()
        line.width = style.Length { Px: options.width }
        line.height = style.Length { Px: extent }
        line.padding = style.EdgeLengths { left: style.Length { Px: 12.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 12.0 }, bottom: style.Length { Px: 0.0 } }
        rows[r] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 4.0 }, line, cells[from..to])
        made_rows += 1usize
        r += 1usize
    }
    var view_style = control.sized_style(options.width, options.height)
    view_style.overflow = .Clip
    view_style.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = widget.scroll(key, widget.Scroll { axis: .Vertical, offset: options.offset, overscroll: .Clamp, momentum: true, scrollbar: true, thumb: control.with_alpha(style.color(t.tokens, .OnSurfaceVariant), 0.5), change: options.change, virtual_first: first, virtual_count: row_total, virtual_extent: extent }, view_style, rows[0usize..made_rows])
    var sem: widget.Semantics = zero
    sem.role = 30u8
    sem.label = label
    sem.column_count = u32(columns)
    sem.row_count = u32(row_total)
    ret (widget.semantics(0u64, sem, style.defaults(), body[0usize..1usize]), ok)
}

// --------------------------------------------- v2 paged and gestured collections (D982)

// A glyph button on a given container (D982): a `side` circle of `container`
// (transparent for none), a 1px `outline` ring when `outlined`, its `glyph` in
// `ink` under the ink's state layer; disabled, the glyph `on-surface` at 38%
// and the container `on-surface` at 12%, under no layer.
fn glyph_in(a: *mem.Arena, key: widget.Key, t: *const control.Theme, kind: control.GlyphKind, label: str, action: *const widget.Submit, side: f32, glyph: f32, container: paint.Color, ink: paint.Color, outlined: bool, enabled: bool) -> (widget.Node, err) {
    let state = control.control_state(t, key, enabled, false)
    let surface_ink = style.color(t.tokens, .OnSurface)
    var shown = ink
    var ground = style.layer(container, ink, control.state_opacity(t, state))
    if !enabled {
        shown = control.with_alpha(surface_ink, t.tokens.states.disabled_content)
        ground = container
        if container.alpha > 0.0 { ground = control.with_alpha(surface_ink, t.tokens.states.disabled_container) }
    }
    var look = style.resolve(t.tokens, .Plain, state)
    look.background = ground
    look.foreground = shown
    look.border_width = 0.0
    if outlined {
        look.border_width = 1.0
        look.border = style.color(t.tokens, .Outline)
        if !enabled { look.border = control.with_alpha(surface_ink, t.tokens.states.disabled_container) }
    }
    look.opacity = 1.0
    look.radius = side * 0.5
    look.custom_padding = true
    look.padding = (side - glyph) * 0.5
    look.padding_y = (side - glyph) * 0.5
    look.min_width = side
    look.min_height = side
    let (mark, mark_error) = control.icon_square(a, shown, kind, glyph)
    if mark_error != ok { ret (zero, mark_error) }
    let (node, node_error) = control.pressable_states(a, key, t, 3u8, label, look, enabled, false, 0u32, 0u32, 0u64, action, mark)
    ret (node, node_error)
}

// Whether the pointer or the keyboard is on the element under `key`.
fn engaged(t: *const control.Theme, key: widget.Key) -> bool {
    let state = control.control_state(t, key, true, false)
    ret state.hovered || state.focus_visible
}

// A page view's form (D982): its name, full bleed (square, the indicator
// overlaid) or inset, whether it shows the page indicator, and its size.
type PageViewOptions = struct { label: str, full_bleed: bool, indicator: bool, width: f32, height: f32 }

fn page_view_options() -> PageViewOptions {
    var out: PageViewOptions = zero
    out.indicator = true
    ret out
}

// v2 (D982, docs/ux/components/PageView): the viewport (keyed `key`) `width` by
// `height` on `surface-container-low`, `radius-md` inset (square full bleed),
// clipping a strip of the pages side by side: the drag moves the strip with the
// finger (a third as far past either end) and the release turns past half the
// width. With a pointer, while the viewport or a button is hovered or focused,
// tonal 40 icon buttons (`secondary-container` / `on-secondary-container`, 24
// chevrons) stand 12 in from the sides, vertically centred: Previous (keyed
// `key + 1`) and Next (`key + 2`), each gone at its end. Left, Right, Page Up
// and Page Down step, Home and End go to the ends. The page indicator
// (`page_indicator_of`, keyed `key + 3`) stands 12 below, or, full bleed, on its
// media pill 16 above the bottom edge. A group named `label` saying "2 of 4",
// said politely.
// ponytail: no settle motion, fling velocity or reduced-motion cross-fade; the
// neighbours are built only while the strip is dragged.
fn page_view_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, pages: []const widget.Node, current: usize, turn: widget.Change[usize], options: PageViewOptions) -> (widget.Node, err) {
    if pages.len == 0usize || current >= pages.len { ret (zero, TooLarge) }
    let w = options.width
    let h = options.height
    let (kept, has_cell) = swipe_cell(t, key)
    var moved: f32 = 0.0
    if has_cell { moved = kept.moved }
    if moved > 0.0 && current == 0usize { moved = moved / 3.0 }
    if moved < 0.0 && current + 1usize == pages.len { moved = moved / 3.0 }
    let (pagings, pagings_error) = mem.alloc[Paging](a, 1usize)
    if pagings_error != ok { ret (zero, TooLarge) }
    pagings[0usize] = Paging { cell: kept, has_cell: has_cell, current: current, count: pages.len, threshold: w * 0.5, turn: turn, settle: true }
    // The strip: the current page and, while dragged, its neighbours.
    let (strip, strip_error) = mem.alloc[widget.Node](a, 3usize)
    if strip_error != ok { ret (zero, TooLarge) }
    var n = 0usize
    var from = current
    if current > 0usize { from = current - 1usize }
    var page = from
    while page < pages.len && page <= current + 1usize {
        if page == current || moved != 0.0 {
            let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
            if held_error != ok { ret (zero, TooLarge) }
            held[0usize] = pages[page]
            strip[n] = widget.positioned(0u64, (f32(page) - f32(current)) * w + moved, 0.0, control.sized_style(w, h), held[0usize..1usize])
            n += 1usize
        }
        page += 1usize
    }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = widget.stack(0u64, control.sized_style(w, h), strip[0usize..n])
    var view_style = control.sized_style(w, h)
    view_style.overflow = .Clip
    view_style.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerLow) }
    if !options.full_bleed { view_style.radius = t.tokens.radii.md }
    control.focus_look(t)
    let (layers, layers_error) = mem.alloc[widget.Node](a, 4usize)
    if layers_error != ok { ret (zero, TooLarge) }
    layers[0usize] = widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: ctx_of(&pagings[0usize]), invoke: page_drag }, gestures: 2u8 | 4u8, enabled: true, focusable: true }, view_style, body[0usize..1usize])
    var l = 1usize
    // The keys and the buttons turn through the same `Turn`s.
    let (turns, turns_error) = mem.alloc[Turn](a, 4usize)
    if turns_error != ok { ret (zero, TooLarge) }
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 4usize)
    if actions_error != ok { ret (zero, TooLarge) }
    var previous = current
    if current > 0usize { previous = current - 1usize }
    var next = current
    if current + 1usize < pages.len { next = current + 1usize }
    turns[0usize] = Turn { index: previous, turn: turn }
    turns[1usize] = Turn { index: next, turn: turn }
    turns[2usize] = Turn { index: 0usize, turn: turn }
    turns[3usize] = Turn { index: pages.len - 1usize, turn: turn }
    var k = 0usize
    while k < 4usize {
        actions[k] = widget.Submit { ctx: ctx_of(&turns[k]), invoke: turn_fire }
        k += 1usize
    }
    let touch = density_of(t) == 2usize
    let shown = !touch && (engaged(t, key) || engaged(t, key + 1u64) || engaged(t, key + 2u64))
    let tonal = style.color(t.tokens, .SecondaryContainer)
    let tonal_ink = style.color(t.tokens, .OnSecondaryContainer)
    if shown && current > 0usize {
        let (back, back_error) = glyph_in(a, key + 1u64, t, .ChevronLeft, "Previous page", &actions[0usize], 40.0, 24.0, tonal, tonal_ink, false, true)
        if back_error != ok { ret (zero, back_error) }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (zero, TooLarge) }
        held[0usize] = back
        layers[l] = widget.positioned(0u64, 12.0, (h - 40.0) * 0.5, style.defaults(), held[0usize..1usize])
        l += 1usize
    }
    if shown && current + 1usize < pages.len {
        let (forward, forward_error) = glyph_in(a, key + 2u64, t, .ChevronRight, "Next page", &actions[1usize], 40.0, 24.0, tonal, tonal_ink, false, true)
        if forward_error != ok { ret (zero, forward_error) }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (zero, TooLarge) }
        held[0usize] = forward
        layers[l] = widget.positioned(0u64, w - 52.0, (h - 40.0) * 0.5, style.defaults(), held[0usize..1usize])
        l += 1usize
    }
    var total_h = h
    if options.indicator {
        var dots_options = indicator_options()
        dots_options.on_media = options.full_bleed
        let (dots, dots_error) = page_indicator_of(a, key + 3u64, t, pages.len, current, turn, dots_options)
        if dots_error != ok { ret (zero, dots_error) }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (zero, TooLarge) }
        held[0usize] = dots
        let band = control.if_else(touch, 48.0, 32.0)
        var y = h + 12.0
        if options.full_bleed { y = h - 16.0 - band } else { total_h = h + 12.0 + band }
        let (centred, centred_error) = mem.alloc[widget.Node](a, 1usize)
        if centred_error != ok { ret (zero, TooLarge) }
        centred[0usize] = widget.aligned(0u64, .Center, .Center, control.sized_style(w, band), held[0usize..1usize])
        layers[l] = widget.positioned(0u64, 0.0, y, style.defaults(), centred[0usize..1usize])
        l += 1usize
    }
    let (stacked, stacked_error) = mem.alloc[widget.Node](a, 1usize)
    if stacked_error != ok { ret (zero, TooLarge) }
    stacked[0usize] = widget.stack(0u64, control.sized_style(w, total_h), layers[0usize..l])
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 6usize)
    if shortcuts_error != ok { ret (zero, TooLarge) }
    shortcuts[0usize] = widget.Shortcut { key: 37u32, modifiers: zero, action: actions[0usize] }
    shortcuts[1usize] = widget.Shortcut { key: 33u32, modifiers: zero, action: actions[0usize] }
    shortcuts[2usize] = widget.Shortcut { key: 39u32, modifiers: zero, action: actions[1usize] }
    shortcuts[3usize] = widget.Shortcut { key: 34u32, modifiers: zero, action: actions[1usize] }
    shortcuts[4usize] = widget.Shortcut { key: 36u32, modifiers: zero, action: actions[2usize] }
    shortcuts[5usize] = widget.Shortcut { key: 35u32, modifiers: zero, action: actions[3usize] }
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: shortcuts[0usize..6usize], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), stacked[0usize..1usize])
    let (said, said_error) = mem.alloc[u8](a, 48usize)
    if said_error != ok { ret (zero, TooLarge) }
    var m = control.write_i64(said, i64(current + 1usize))
    m += control.copy_text(said[m..48usize], " of ")
    m += control.write_i64(said[m..48usize], i64(pages.len))
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = options.label
    sem.value = said[0usize..m]
    sem.live = 1u8
    sem.row = u32(current + 1usize)
    sem.row_count = u32(pages.len)
    ret (widget.semantics(0u64, sem, style.defaults(), scoped[0usize..1usize]), ok)
}

// A carousel item's container colours (D982).
type CarouselTone = enum u8 { Surface, Primary, Secondary, Tertiary }

// A carousel item: its title and meta, its container, its media (or none) and
// its action.
type CarouselItem = struct { title: str, meta: str, tone: CarouselTone, media: widget.Node, has_media: bool, action: widget.Submit }

fn carousel_item(title: str) -> CarouselItem {
    var out: CarouselItem = zero
    out.title = title
    ret out
}

// How a carousel lays its items out (D982).
type CarouselLayout = enum u8 { MultiBrowse, Hero, Uncontained }

// A carousel's form (D982): the layout, the header's title, the width, the item
// height (0: 200, 160 uncontained, 280 hero from 600 wide) and the uncontained
// item width (0: 180).
type CarouselOptions = struct { layout: CarouselLayout, title: str, width: f32, height: f32, item_width: f32 }

fn carousel_options() -> CarouselOptions {
    var out: CarouselOptions = zero
    ret out
}

// v2 (D982, docs/ux/components/Carousel): a strip of the items from `current`,
// 8 apart, 16 in from the sides (24 from 600 wide), clipped at the end. A
// multi-browse strip shows a large item (what is left after a 200 medium and a
// 56 small one), the medium and the small; a hero strip (and a multi-browse one
// too narrow for three) a large item and the small peek; an uncontained strip
// items `item_width` wide until the edge. An item (keyed by `keys`) is
// `radius-md`, filled with its tone's container (`surface-container-highest`,
// `primary-container`, `secondary-container`, `tertiary-container`) under the
// state layer of its `on-` colour, 16 in, its media at the top and its
// `title-medium` title and `body-small` meta, one line each, at the bottom; a
// small item shows its media alone. With a pointer, a header over the strip:
// the `title-medium` title in `on-surface` and outlined 40 icon buttons (32
// dense) 8 apart at the end, Previous (`key + 1`) and Next (`key + 2`),
// disabled at the ends; Left and Right step from the strip. A group named
// `label`, each item a group named by its title.
// ponytail: the strip steps an item at a time through `current` rather than
// scrolling freely with snapping; items do not grow and shrink as they pass
// the leading edge; no "Show all" on touch.
fn carousel_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, items: []const CarouselItem, keys: []const widget.Key, current: usize, turn: widget.Change[usize], options: CarouselOptions) -> (widget.Node, err) {
    if items.len == 0usize || keys.len != items.len || current >= items.len { ret (zero, TooLarge) }
    let inset = control.if_else(options.width < 600.0, 16.0, 24.0)
    let span = control.max_zero(options.width - 2.0 * inset)
    var item_h = options.height
    if !(item_h > 0.0) {
        item_h = 200.0
        if options.layout == .Uncontained { item_h = 160.0 }
        if options.layout == .Hero && options.width >= 600.0 { item_h = 280.0 }
    }
    var fixed = options.item_width
    if !(fixed > 0.0) { fixed = 180.0 }
    // The widths of the items from `current`: large, medium, small, or fixed.
    var large = span - 200.0 - 56.0 - 16.0
    var hero = options.layout == .Hero
    if options.layout == .MultiBrowse && large < 200.0 { hero = true }
    if hero { large = span - 56.0 - 8.0 }
    let (cells, cells_error) = mem.alloc[widget.Node](a, items.len)
    if cells_error != ok { ret (zero, TooLarge) }
    var n = 0usize
    var x: f32 = 0.0
    var i = current
    while i < items.len && x < span {
        var wide = fixed
        var small = false
        if options.layout != .Uncontained {
            let slot = i - current
            if slot == 0usize { wide = large }
            if slot == 1usize && !hero { wide = 200.0 }
            if (slot == 1usize && hero) || slot == 2usize {
                wide = 56.0
                small = true
            }
            if (hero && slot > 1usize) || slot > 2usize { break }
        }
        let (made, made_error) = carousel_item_node(a, keys[i], t, &items[i], wide, item_h, small)
        if made_error != ok { ret (zero, made_error) }
        cells[n] = made
        n += 1usize
        x += wide + 8.0
        i += 1usize
    }
    // Left and Right step from the strip.
    let (turns, turns_error) = mem.alloc[Turn](a, 2usize)
    if turns_error != ok { ret (zero, TooLarge) }
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 2usize)
    if actions_error != ok { ret (zero, TooLarge) }
    var previous = current
    if current > 0usize { previous = current - 1usize }
    var next = current
    if current + 1usize < items.len { next = current + 1usize }
    turns[0usize] = Turn { index: previous, turn: turn }
    turns[1usize] = Turn { index: next, turn: turn }
    actions[0usize] = widget.Submit { ctx: ctx_of(&turns[0usize]), invoke: turn_fire }
    actions[1usize] = widget.Submit { ctx: ctx_of(&turns[1usize]), invoke: turn_fire }
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 2usize)
    if shortcuts_error != ok { ret (zero, TooLarge) }
    shortcuts[0usize] = widget.Shortcut { key: 37u32, modifiers: zero, action: actions[0usize] }
    shortcuts[1usize] = widget.Shortcut { key: 39u32, modifiers: zero, action: actions[1usize] }
    var strip_style = control.sized_style(options.width, item_h)
    strip_style.overflow = .Clip
    let flat = style.Length { Px: 0.0 }
    strip_style.padding = style.EdgeLengths { left: style.Length { Px: inset }, top: flat, right: flat, bottom: flat }
    let (strip, strip_error) = mem.alloc[widget.Node](a, 1usize)
    if strip_error != ok { ret (zero, TooLarge) }
    strip[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 8.0 }, strip_style, cells[0usize..n])
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    var p = 0usize
    let touch = density_of(t) == 2usize
    if !touch {
        let side = control.if_else(density_of(t) == 0usize, 32.0, 40.0)
        let glyph = control.if_else(density_of(t) == 0usize, t.tokens.sizes.icon_sm, t.tokens.sizes.icon_md)
        let clear = control.with_alpha(style.color(t.tokens, .OnSurface), 0.0)
        let ink = style.color(t.tokens, .OnSurfaceVariant)
        let (back, back_error) = glyph_in(a, key + 1u64, t, .ChevronLeft, "Previous", &actions[0usize], side, glyph, clear, ink, true, current > 0usize)
        if back_error != ok { ret (zero, back_error) }
        let (forward, forward_error) = glyph_in(a, key + 2u64, t, .ChevronRight, "Next", &actions[1usize], side, glyph, clear, ink, true, current + 1usize < items.len)
        if forward_error != ok { ret (zero, forward_error) }
        var heading = control.text_options()
        heading.role = .TitleMedium
        heading.wrap = .None
        let (said, said_error) = control.colored_text(a, 0u64, options.title, t, heading, style.color(t.tokens, .OnSurface))
        if said_error != ok { ret (zero, said_error) }
        let (head_parts, head_parts_error) = mem.alloc[widget.Node](a, 4usize)
        if head_parts_error != ok { ret (zero, TooLarge) }
        head_parts[0usize] = said
        head_parts[1usize] = widget.spacer(0u64, 1.0)
        head_parts[2usize] = back
        head_parts[3usize] = forward
        var head_style = style.defaults()
        head_style.width = style.Length { Px: options.width }
        head_style.padding = style.EdgeLengths { left: style.Length { Px: inset }, top: flat, right: style.Length { Px: inset }, bottom: style.Length { Px: 8.0 } }
        parts[p] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 8.0 }, head_style, head_parts[0usize..4usize])
        p += 1usize
    }
    parts[p] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: shortcuts[0usize..2usize], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), strip[0usize..1usize])
    p += 1usize
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    sem.row = u32(current + 1usize)
    sem.row_count = u32(items.len)
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(key, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..p])
    ret (widget.semantics(0u64, sem, style.defaults(), column[0usize..1usize]), ok)
}

fn carousel_item_node(a: *mem.Arena, key: widget.Key, t: *const control.Theme, item: *const CarouselItem, wide: f32, tall: f32, small: bool) -> (widget.Node, err) {
    var fill = style.color(t.tokens, .SurfaceContainerHighest)
    var ink = style.color(t.tokens, .OnSurface)
    if item.tone == .Primary {
        fill = style.color(t.tokens, .PrimaryContainer)
        ink = style.color(t.tokens, .OnPrimaryContainer)
    }
    if item.tone == .Secondary {
        fill = style.color(t.tokens, .SecondaryContainer)
        ink = style.color(t.tokens, .OnSecondaryContainer)
    }
    if item.tone == .Tertiary {
        fill = style.color(t.tokens, .TertiaryContainer)
        ink = style.color(t.tokens, .OnTertiaryContainer)
    }
    let state = control.control_state(t, key, true, false)
    let (parts, parts_error) = mem.alloc[widget.Node](a, 4usize)
    if parts_error != ok { ret (zero, TooLarge) }
    var n = 0usize
    if item.has_media {
        parts[n] = item.media
        n += 1usize
    }
    if !small {
        parts[n] = widget.spacer(0u64, 1.0)
        n += 1usize
        var caption = control.text_options()
        caption.wrap = .None
        caption.max_lines = 1u32
        caption.ellipsis = "…"
        caption.role = .TitleMedium
        let (named, named_error) = control.colored_text(a, 0u64, item.title, t, caption, ink)
        if named_error != ok { ret (zero, named_error) }
        parts[n] = named
        n += 1usize
        if item.meta.len > 0usize {
            caption.role = .BodySmall
            let (meta_node, meta_error) = control.colored_text(a, 0u64, item.meta, t, caption, ink)
            if meta_error != ok { ret (zero, meta_error) }
            parts[n] = meta_node
            n += 1usize
        }
    }
    var item_style = control.sized_style(wide, tall)
    item_style.radius = t.tokens.radii.md
    item_style.overflow = .Clip
    item_style.background = paint.Brush { Solid: style.layer(fill, ink, control.state_opacity(t, state)) }
    let sixteen = style.Length { Px: control.if_else(small, 0.0, 16.0) }
    item_style.padding = style.EdgeLengths { left: sixteen, top: sixteen, right: sixteen, bottom: sixteen }
    var cross: ui_layout.CrossAlign = .Start
    var main: ui_layout.MainAlign = .Start
    if small {
        cross = .Center
        main = .Center
    }
    let (content, content_error) = mem.alloc[widget.Node](a, 1usize)
    if content_error != ok { ret (zero, TooLarge) }
    var column_style = style.defaults()
    column_style.width = style.Length { Percent: 100.0 }
    column_style.height = style.Length { Percent: 100.0 }
    content[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: main, cross: cross, gap: 0.0 }, column_style, parts[0usize..n])
    control.focus_look(t)
    let (region, region_error) = mem.alloc[widget.Node](a, 1usize)
    if region_error != ok { ret (zero, TooLarge) }
    region[0usize] = widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: ctx_of(&item.action), invoke: control.press_tap }, gestures: 1u8 | 4u8, enabled: true, focusable: true }, item_style, content[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = item.title
    sem.hint = item.meta
    sem.actions = accessibility.ACTION_PRESS
    ret (widget.semantics(0u64, sem, style.defaults(), region[0usize..1usize]), ok)
}

// A pull to refresh's form (D982): the refresh command's name and the size.
type PullOptions = struct { label: str, width: f32, height: f32 }

fn pull_options() -> PullOptions {
    var out: PullOptions = zero
    out.label = "Refresh"
    ret out
}

// v2 (D982, docs/ux/components/PullToRefresh). On touch: the content (keyed
// `key`) follows a downward pull, one for one to 40 and half past it (120 at
// most), and the release past 80 refreshes; the indicator, a 40
// `surface-container-high` circle at elevation 2, centred, slides down with
// the pull (12 below the top at 80), its 2.5 `primary` arc (60% until half the
// threshold) growing to 80% of the ring at 80; armed past 80 it is
// `primary-container` with an `on-primary-container` arc. While `refreshing`
// the indicator rests 12 down, its arc a spinning quarter, and the content
// stands 64 down. With a pointer: a toolbar row with a 40 `refresh` icon button
// (32 dense, keyed `key + 1`, named `label`, disabled while refreshing), F5
// and Ctrl+R refreshing from within, and an indeterminate linear progress
// under it while refreshing. A group named `label`, busy while refreshing.
// ponytail: the pull starts anywhere, not only at the top of a scroll; the
// arc does not spin on its own (the caller's frames would); no new-row tag,
// outcome snackbar or settle motion.
fn pull_to_refresh_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, content: widget.Node, refreshing: bool, refresh: *const widget.Submit, options: PullOptions) -> (widget.Node, err) {
    let w = options.width
    let h = options.height
    let touch = density_of(t) == 2usize
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, TooLarge) }
    held[0usize] = content
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = options.label
    if refreshing { sem.states = accessibility.STATE_BUSY }
    if !touch {
        let side = control.if_else(density_of(t) == 0usize, 32.0, 40.0)
        let glyph = control.if_else(density_of(t) == 0usize, t.tokens.sizes.icon_sm, t.tokens.sizes.icon_md)
        let (again, again_error) = glyph_in(a, key + 1u64, t, .Refresh, options.label, refresh, side, glyph, control.with_alpha(style.color(t.tokens, .OnSurface), 0.0), style.color(t.tokens, .OnSurfaceVariant), false, !refreshing)
        if again_error != ok { ret (zero, again_error) }
        let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
        if parts_error != ok { ret (zero, TooLarge) }
        let (bar_parts, bar_parts_error) = mem.alloc[widget.Node](a, 2usize)
        if bar_parts_error != ok { ret (zero, TooLarge) }
        bar_parts[0usize] = widget.spacer(0u64, 1.0)
        bar_parts[1usize] = again
        var bar_style = style.defaults()
        bar_style.width = style.Length { Px: w }
        parts[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, bar_style, bar_parts[0usize..2usize])
        var n = 1usize
        var used = side
        if refreshing {
            let (busy, busy_error) = control.progress_bar(a, key + 3u64, t, options.label, 0.0, true, w)
            if busy_error != ok { ret (zero, busy_error) }
            parts[n] = busy
            n += 1usize
            used += 4.0
        }
        var view_style = control.sized_style(w, control.max_zero(h - used))
        view_style.overflow = .Clip
        parts[n] = widget.box(key, view_style, held[0usize..1usize])
        n += 1usize
        let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 2usize)
        if shortcuts_error != ok { ret (zero, TooLarge) }
        var bound = 0usize
        if !refreshing {
            var ctrl: input.Modifiers = zero
            ctrl.control = true
            shortcuts[0usize] = widget.Shortcut { key: 116u32, modifiers: zero, action: *refresh }
            shortcuts[1usize] = widget.Shortcut { key: 82u32, modifiers: ctrl, action: *refresh }
            bound = 2usize
        }
        let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
        if column_error != ok { ret (zero, TooLarge) }
        column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..n])
        let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
        if scoped_error != ok { ret (zero, TooLarge) }
        scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: shortcuts[0usize..bound], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), column[0usize..1usize])
        ret (widget.semantics(0u64, sem, style.defaults(), scoped[0usize..1usize]), ok)
    }
    let (kept, has_cell) = swipe_cell(t, key)
    var pulled: f32 = 0.0
    if has_cell && !refreshing { pulled = kept.moved }
    let (pulls, pulls_error) = mem.alloc[Pulling](a, 1usize)
    if pulls_error != ok { ret (zero, TooLarge) }
    var quiet: widget.Submit = zero
    pulls[0usize] = Pulling { cell: kept, has_cell: has_cell, threshold: 80.0, refresh: *refresh, settle: true }
    if refreshing { pulls[0usize].refresh = quiet }
    var offset = pulled
    if refreshing { offset = 64.0 }
    let (layers, layers_error) = mem.alloc[widget.Node](a, 2usize)
    if layers_error != ok { ret (zero, TooLarge) }
    layers[0usize] = widget.positioned(0u64, 0.0, offset, control.sized_style(w, h), held[0usize..1usize])
    var l = 1usize
    if refreshing || pulled > 0.0 {
        let armed = !refreshing && pulled >= 80.0
        var disc = control.sized_style(40.0, 40.0)
        disc.radius = 20.0
        disc.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerHigh) }
        disc.shadow = style.Shadow { offset: geometry.Point { x: 0.0, y: 2.0 }, color: paint.rgba(0.0, 0.0, 0.0, t.tokens.elevation[2usize]) }
        var arc_ink = style.color(t.tokens, .Primary)
        if armed {
            disc.background = paint.Brush { Solid: style.color(t.tokens, .PrimaryContainer) }
            arc_ink = style.color(t.tokens, .OnPrimaryContainer)
        }
        if !refreshing && pulled < 40.0 { arc_ink = control.with_alpha(arc_ink, 0.6) }
        var share: f32 = 0.25
        if !refreshing {
            share = pulled / 80.0
            if share > 1.0 { share = 1.0 }
            share = share * 0.8
        }
        let ring = control.Ring { track: control.with_alpha(arc_ink, 0.0), fill: arc_ink, share: share, thickness: 2.5, arena: a, start: 0.0, sweep: 6.2831855, gap: 0.0, band: zero, band_from: 2.0 }
        let (arc, arc_error) = control.ring_node(a, key + 2u64, ring, 18.5)
        if arc_error != ok { ret (zero, arc_error) }
        let (drawn, drawn_error) = mem.alloc[widget.Node](a, 1usize)
        if drawn_error != ok { ret (zero, TooLarge) }
        drawn[0usize] = arc
        let around = style.Length { Px: 10.75 }
        disc.padding = style.EdgeLengths { left: around, top: around, right: around, bottom: around }
        let (discs, discs_error) = mem.alloc[widget.Node](a, 1usize)
        if discs_error != ok { ret (zero, TooLarge) }
        discs[0usize] = widget.box(0u64, disc, drawn[0usize..1usize])
        var y: f32 = 12.0
        if !refreshing { y = control.max_zero(pulled * 52.0 / 80.0 - 40.0) }
        layers[1usize] = widget.positioned(0u64, (w - 40.0) * 0.5, y, style.defaults(), discs[0usize..1usize])
        l = 2usize
    }
    let (stacked, stacked_error) = mem.alloc[widget.Node](a, 1usize)
    if stacked_error != ok { ret (zero, TooLarge) }
    stacked[0usize] = widget.stack(0u64, control.sized_style(w, h), layers[0usize..l])
    var view_style = control.sized_style(w, h)
    view_style.overflow = .Clip
    let (region, region_error) = mem.alloc[widget.Node](a, 1usize)
    if region_error != ok { ret (zero, TooLarge) }
    region[0usize] = widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: ctx_of(&pulls[0usize]), invoke: pull_drag }, gestures: 2u8, enabled: true, focusable: false }, view_style, stacked[0usize..1usize])
    ret (widget.semantics(0u64, sem, style.defaults(), region[0usize..1usize]), ok)
}

// A swipe action's colours (D982).
type SwipeTone = enum u8 { Neutral, Accent, Destructive }

// An action behind a row: its label, glyph, colours and action.
type SwipeAction = struct { label: str, glyph: control.GlyphKind, tone: SwipeTone, action: widget.Submit }

// A swipe row's form (D982): the leading action (none when empty), its size.
type SwipeOptions = struct { leading: []const SwipeAction, width: f32, height: f32 }

fn swipe_options() -> SwipeOptions {
    var out: SwipeOptions = zero
    ret out
}

// A setting of whether the actions are revealed, for Escape (D982).
type RevealSet = struct { value: bool, reveal: widget.Change[bool] }

fn reveal_set_fire(ctx: *void) -> err {
    let r = mem.cast[*RevealSet](ctx)
    ret widget.fire_change[bool](r.reveal, r.value)
}

// One 80 wide action tile (D982), `wide` across: its container and `on-`
// colour by tone, the 24 glyph 4 above the `label-medium` label, centred.
fn swipe_tile(a: *mem.Arena, key: widget.Key, t: *const control.Theme, act: *const SwipeAction, wide: f32, tall: f32) -> (widget.Node, err) {
    var fill = style.color(t.tokens, .SecondaryContainer)
    var ink = style.color(t.tokens, .OnSecondaryContainer)
    if act.tone == .Accent {
        fill = style.color(t.tokens, .Primary)
        ink = style.color(t.tokens, .OnPrimary)
    }
    if act.tone == .Destructive {
        fill = style.color(t.tokens, .Error)
        ink = style.color(t.tokens, .OnError)
    }
    let state = control.control_state(t, key, true, false)
    let (mark, mark_error) = control.icon_square(a, ink, act.glyph, t.tokens.sizes.icon_md)
    if mark_error != ok { ret (zero, mark_error) }
    var caption = control.text_options()
    caption.role = .LabelMedium
    caption.wrap = .None
    let (said, said_error) = control.colored_text(a, 0u64, act.label, t, caption, ink)
    if said_error != ok { ret (zero, said_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = mark
    parts[1usize] = said
    var look = style.resolve(t.tokens, .Plain, state)
    look.background = style.layer(fill, ink, control.state_opacity(t, state))
    look.foreground = ink
    look.border_width = 0.0
    look.opacity = 1.0
    look.radius = 0.0
    look.custom_padding = true
    look.padding = 0.0
    look.padding_y = 0.0
    look.min_width = wide
    look.min_height = tall
    var column_style = control.sized_style(wide, tall)
    let content = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Center, cross: .Center, gap: 4.0 }, column_style, parts[0usize..2usize])
    let (made, made_error) = control.pressable(a, key, t, 3u8, act.label, look, true, false, &act.action, content)
    ret (made, made_error)
}

// v2 (D982, docs/ux/components/SwipeActions): the row (keyed `key`, focusable)
// on `surface` slides over its actions, following the finger: the trailing
// actions (keyed `key + 2 + index`) are 80 wide tiles the row's height at its
// end, each its tone's container (`secondary-container`, `primary`, `error`)
// with a 24 glyph over a `label-medium` label; the one leading action (`key +
// 16`) a tile at its start. Revealed, the row stands the tiles' width to the
// start; the release opens past 40% of that, closes the other way, runs the
// leading action past 32, and past 60% of the width runs the outermost trailing
// action, its tile stretched to the row's end. With a pointer, while the row
// or one of them is hovered or focused, the actions are also 32 icon buttons
// (`key + 8 + index`) in `on-surface-variant` 4 apart at the row's end; Escape
// closes. A list item in the tree, Expanded while revealed.
// ponytail: no fling velocity, rubber band or settle motion, and no custom
// accessibility actions; the actions reach the keyboard as the hover buttons.
fn swipe_actions_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, content: widget.Node, actions: []const SwipeAction, revealed: bool, reveal: widget.Change[bool], options: SwipeOptions) -> (widget.Node, err) {
    if actions.len == 0usize || actions.len > 3usize || options.leading.len > 1usize { ret (zero, TooLarge) }
    let w = options.width
    let h = options.height
    let stop = 80.0 * f32(actions.len)
    let (kept, has_cell) = swipe_cell(t, key)
    let (reveals, reveals_error) = mem.alloc[Revealing](a, 1usize)
    if reveals_error != ok { ret (zero, TooLarge) }
    reveals[0usize] = Revealing { cell: kept, has_cell: has_cell, threshold: stop * 0.4, reveal: reveal, settle: true, revealed: revealed, full: w * 0.6, outer: actions[actions.len - 1usize].action, has_outer: true, lead: zero, has_lead: options.leading.len == 1usize }
    if options.leading.len == 1usize { reveals[0usize].lead = options.leading[0usize].action }
    var offset: f32 = 0.0
    if revealed { offset = 0.0 - stop }
    if has_cell { offset += kept.moved }
    if offset < 0.0 - w { offset = 0.0 - w }
    var most: f32 = 0.0
    if options.leading.len == 1usize { most = 80.0 }
    if offset > most { offset = most }
    let (layers, layers_error) = mem.alloc[widget.Node](a, 6usize)
    if layers_error != ok { ret (zero, TooLarge) }
    var l = 0usize
    if offset < 0.0 - w * 0.6 {
        // The full swipe: the outermost tile alone, stretched.
        let (tile, tile_error) = swipe_tile(a, key + 2u64 + u64(actions.len - 1usize), t, &actions[actions.len - 1usize], 0.0 - offset, h)
        if tile_error != ok { ret (zero, tile_error) }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (zero, TooLarge) }
        held[0usize] = tile
        layers[l] = widget.positioned(0u64, w + offset, 0.0, style.defaults(), held[0usize..1usize])
        l += 1usize
    } else {
        var i = 0usize
        while i < actions.len {
            let (tile, tile_error) = swipe_tile(a, key + 2u64 + u64(i), t, &actions[i], 80.0, h)
            if tile_error != ok { ret (zero, tile_error) }
            let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
            if held_error != ok { ret (zero, TooLarge) }
            held[0usize] = tile
            layers[l] = widget.positioned(0u64, w - stop + 80.0 * f32(i), 0.0, style.defaults(), held[0usize..1usize])
            l += 1usize
            i += 1usize
        }
    }
    if options.leading.len == 1usize {
        let (tile, tile_error) = swipe_tile(a, key + 16u64, t, &options.leading[0usize], 80.0, h)
        if tile_error != ok { ret (zero, tile_error) }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (zero, TooLarge) }
        held[0usize] = tile
        layers[l] = widget.positioned(0u64, 0.0, 0.0, style.defaults(), held[0usize..1usize])
        l += 1usize
    }
    // The row over them, on `surface`.
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = content
    var row_style = control.sized_style(w, h)
    row_style.overflow = .Clip
    row_style.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    control.focus_look(t)
    let (region, region_error) = mem.alloc[widget.Node](a, 1usize)
    if region_error != ok { ret (zero, TooLarge) }
    region[0usize] = widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: ctx_of(&reveals[0usize]), invoke: reveal_drag }, gestures: 2u8 | 4u8, enabled: true, focusable: true }, row_style, body[0usize..1usize])
    layers[l] = widget.positioned(0u64, offset, 0.0, style.defaults(), region[0usize..1usize])
    l += 1usize
    // With a pointer, the actions as hover buttons at the row's end.
    let touch = density_of(t) == 2usize
    var hovering = engaged(t, key)
    var b = 0usize
    while b < actions.len {
        if engaged(t, key + 8u64 + u64(b)) { hovering = true }
        b += 1usize
    }
    if !touch && hovering && offset == 0.0 {
        let (buttons, buttons_error) = mem.alloc[widget.Node](a, actions.len)
        if buttons_error != ok { ret (zero, TooLarge) }
        let clear = control.with_alpha(style.color(t.tokens, .OnSurface), 0.0)
        b = 0usize
        while b < actions.len {
            let (made, made_error) = glyph_in(a, key + 8u64 + u64(b), t, actions[b].glyph, actions[b].label, &actions[b].action, 32.0, t.tokens.sizes.icon_sm, clear, style.color(t.tokens, .OnSurfaceVariant), false, true)
            if made_error != ok { ret (zero, made_error) }
            buttons[b] = made
            b += 1usize
        }
        let across = 32.0 * f32(actions.len) + 4.0 * f32(actions.len - 1usize)
        let (strip, strip_error) = mem.alloc[widget.Node](a, 1usize)
        if strip_error != ok { ret (zero, TooLarge) }
        strip[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 4.0 }, style.defaults(), buttons[0usize..actions.len])
        layers[l] = widget.positioned(0u64, w - 8.0 - across, (h - 32.0) * 0.5, style.defaults(), strip[0usize..1usize])
        l += 1usize
    }
    var frame = control.sized_style(w, h)
    frame.overflow = .Clip
    let (stacked, stacked_error) = mem.alloc[widget.Node](a, 1usize)
    if stacked_error != ok { ret (zero, TooLarge) }
    stacked[0usize] = widget.stack(0u64, frame, layers[0usize..l])
    let (sets, sets_error) = mem.alloc[RevealSet](a, 1usize)
    if sets_error != ok { ret (zero, TooLarge) }
    sets[0usize] = RevealSet { value: false, reveal: reveal }
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 1usize)
    if shortcuts_error != ok { ret (zero, TooLarge) }
    shortcuts[0usize] = widget.Shortcut { key: 27u32, modifiers: zero, action: widget.Submit { ctx: ctx_of(&sets[0usize]), invoke: reveal_set_fire } }
    var bound = 0usize
    if revealed { bound = 1usize }
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: shortcuts[0usize..bound], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), stacked[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 11u8
    if revealed { sem.states = accessibility.STATE_EXPANDED }
    ret (widget.semantics(0u64, sem, style.defaults(), scoped[0usize..1usize]), ok)
}

// v2 (D982, docs/ux/components/ReorderableList): `row_of` rows (keyed by `keys`)
// of one height, each with its drag handle, a 24 `drag-handle` glyph in
// `on-surface-variant`: leading in a 32 target with a pointer, trailing in a 48
// target on touch, the target keyed `key + 1 + index`. While a handle is
// dragged its row lifts where the pointer holds it: `surface-container-high`
// under the `on-surface` layer at 16% (`state-dragged`), elevation 4,
// `radius-sm`, inset 8 from the sides; the rows between it and where it would
// land make room, and that gap is `surface-container-low`. The drop reports
// the move; Alt or Ctrl with Up or Down moves the focused row by one; Up, Down,
// Home and End move the focus. Each row stands in a holder keyed `key + 1 +
// count + index`, so the lifted one keeps its elements -- and the drag its
// handle -- when it moves to the top of the stack. A list named `label`.
// ponytail: the handle shows at rest rather than only on hover; no lift scale,
// drop line, auto-scroll, keyboard pick-up (Space) or move actions.
fn reorderable_list_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, items: []const RowItem, keys: []const widget.Key, move: widget.Change[Reorder], width: f32) -> (widget.Node, err) {
    if keys.len != items.len || items.len == 0usize { ret (zero, TooLarge) }
    let n = items.len
    let touch = density_of(t) == 2usize
    let tall = row_height(t, row_lines(&items[0usize]))
    // Who is being dragged, and where it would land.
    var lifted = n
    var moved: f32 = 0.0
    let (cells, cells_error) = mem.alloc[*Swipe](a, n)
    if cells_error != ok { ret (zero, TooLarge) }
    let (has, has_error) = mem.alloc[bool](a, n)
    if has_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < n {
        let (kept, has_cell) = swipe_cell(t, key + 1u64 + u64(i))
        cells[i] = kept
        has[i] = has_cell
        if has_cell && kept.moved != 0.0 {
            lifted = i
            moved = kept.moved
        }
        i += 1usize
    }
    var landing = lifted
    if lifted < n {
        var spot = f32(lifted) + moved / tall
        if spot < 0.0 { spot = 0.0 }
        landing = usize(spot + 0.5)
        if landing >= n { landing = n - 1usize }
    }
    let (shown, shown_error) = mem.alloc[RowItem](a, n)
    if shown_error != ok { ret (zero, TooLarge) }
    let (drags, drags_error) = mem.alloc[Dragging](a, n)
    if drags_error != ok { ret (zero, TooLarge) }
    let (nudges, nudges_error) = mem.alloc[Nudging](a, 2usize * n)
    if nudges_error != ok { ret (zero, TooLarge) }
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 4usize * n)
    if shortcuts_error != ok { ret (zero, TooLarge) }
    let (rows, rows_error) = mem.alloc[widget.Node](a, n)
    if rows_error != ok { ret (zero, TooLarge) }
    let (layers, layers_error) = mem.alloc[widget.Node](a, n + 1usize)
    if layers_error != ok { ret (zero, TooLarge) }
    var alt: input.Modifiers = zero
    alt.alt = true
    var ctrl: input.Modifiers = zero
    ctrl.control = true
    let grab = control.if_else(touch, 48.0, 32.0)
    i = 0usize
    while i < n {
        shown[i] = items[i]
        if touch {
            shown[i].has_trailing = true
            shown[i].trailing = .DragHandle
            shown[i].check = false
        } else {
            shown[i].has_leading = true
            shown[i].leading = .DragHandle
        }
        var wide = width
        if i == lifted { wide = control.max_zero(width - 16.0) }
        let (made, made_error) = row_sized(a, keys[i], t, &shown[i], i, n, wide, tall)
        if made_error != ok { ret (zero, made_error) }
        // The handle's target over the glyph.
        drags[i] = Dragging { runtime: t.runtime, list: key, index: i, count: n, extent: tall, move: move, cell: cells[i], has_cell: has[i] }
        var grip_x: f32 = 12.0
        if touch { grip_x = wide - 24.0 - 12.0 - grab }
        let (grip, grip_error) = mem.alloc[widget.Node](a, 1usize)
        if grip_error != ok { ret (zero, TooLarge) }
        grip[0usize] = widget.region(key + 1u64 + u64(i), widget.Region { gesture: widget.GestureAction { ctx: ctx_of(&drags[i]), invoke: reorder_drag }, gestures: 2u8 | 4u8, enabled: true, focusable: false }, control.sized_style(grab, grab), zero)
        let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
        if pair_error != ok { ret (zero, TooLarge) }
        pair[0usize] = made
        pair[1usize] = widget.positioned(0u64, grip_x, (tall - grab) * 0.5, style.defaults(), grip[0usize..1usize])
        var row_style = control.sized_style(wide, tall)
        if i == lifted {
            row_style.background = paint.Brush { Solid: style.layer(style.color(t.tokens, .SurfaceContainerHigh), style.color(t.tokens, .OnSurface), 0.16) }
            row_style.radius = t.tokens.radii.sm
            row_style.shadow = style.Shadow { offset: geometry.Point { x: 0.0, y: 4.0 }, color: paint.rgba(0.0, 0.0, 0.0, t.tokens.elevation[4usize]) }
        }
        rows[i] = widget.stack(0u64, row_style, pair[0usize..2usize])
        nudges[2usize * i] = Nudging { index: i, count: n, up: true, move: move }
        nudges[2usize * i + 1usize] = Nudging { index: i, count: n, up: false, move: move }
        let up = widget.Submit { ctx: ctx_of(&nudges[2usize * i]), invoke: reorder_nudge }
        let down = widget.Submit { ctx: ctx_of(&nudges[2usize * i + 1usize]), invoke: reorder_nudge }
        shortcuts[4usize * i] = widget.Shortcut { key: 38u32, modifiers: alt, action: up }
        shortcuts[4usize * i + 1usize] = widget.Shortcut { key: 40u32, modifiers: alt, action: down }
        shortcuts[4usize * i + 2usize] = widget.Shortcut { key: 38u32, modifiers: ctrl, action: up }
        shortcuts[4usize * i + 3usize] = widget.Shortcut { key: 40u32, modifiers: ctrl, action: down }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (zero, TooLarge) }
        held[0usize] = rows[i]
        rows[i] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: shortcuts[4usize * i..4usize * i + 4usize], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), held[0usize..1usize])
        i += 1usize
    }
    let rove_error = roving(a, t, rows, keys, 1usize)
    if rove_error != ok { ret (zero, rove_error) }
    // Place the rows: the gap first, the others round it, the lifted one last.
    var l = 0usize
    if lifted < n {
        var gap = control.sized_style(width, tall)
        gap.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerLow) }
        layers[l] = widget.positioned(0u64, 0.0, f32(landing) * tall, gap, zero)
        l += 1usize
    }
    i = 0usize
    while i < n {
        if i != lifted {
            var slot = i
            if lifted < n && lifted < i && i <= landing { slot = i - 1usize }
            if lifted < n && landing <= i && i < lifted { slot = i + 1usize }
            let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
            if held_error != ok { ret (zero, TooLarge) }
            held[0usize] = rows[i]
            layers[l] = widget.positioned(key + 1u64 + u64(n + i), 0.0, f32(slot) * tall, style.defaults(), held[0usize..1usize])
            l += 1usize
        }
        i += 1usize
    }
    if lifted < n {
        var y = f32(lifted) * tall + moved
        if y < 0.0 { y = 0.0 }
        if y > f32(n - 1usize) * tall { y = f32(n - 1usize) * tall }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (zero, TooLarge) }
        held[0usize] = rows[lifted]
        layers[l] = widget.positioned(key + 1u64 + u64(n + lifted), 8.0, y, style.defaults(), held[0usize..1usize])
        l += 1usize
    }
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.stack(key, control.sized_style(width, f32(n) * tall), layers[0usize..l])
    var sem: widget.Semantics = zero
    sem.role = 10u8
    sem.label = label
    sem.row_count = u32(n)
    ret (widget.semantics(0u64, sem, style.defaults(), column[0usize..1usize]), ok)
}
