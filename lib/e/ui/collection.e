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
    var grown = item
    grown.style.height = style.Length { Flex: 1.0 }
    parts[0usize] = grown
    if separator {
        let (line, line_error) = control.divider(a, 0u64, t, .Horizontal, 0.0)
        if line_error != ok { ret (zero, line_error) }
        parts[1usize] = line
    }
    var row_style = style.defaults()
    row_style.width = style.Length { Px: width }
    if extent > 0.0 { row_style.height = style.Length { Px: extent } }
    if selected { row_style.background = paint.Brush { Solid: style.color(t.tokens, .Selection) } }
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
        let (made, made_error) = row(a, t, built, item_key, index, total, extent, width, separators, is_selected(selected, item_key))
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
    body[0usize] = widget.scroll(key, widget.Scroll { axis: .Vertical, offset: offset, overscroll: .Clamp, momentum: true, scrollbar: true, thumb: style.color(t.tokens, .Border), change: change, virtual_first: first, virtual_count: total, virtual_extent: extent }, view_style, rows[0usize..count])
    var sem: widget.Semantics = zero
    sem.role = 2u8
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
    if selected { cell_style.background = paint.Brush { Solid: style.color(t.tokens, .Selection) } }
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
    body[0usize] = widget.scroll(key, widget.Scroll { axis: .Vertical, offset: offset, overscroll: .Clamp, momentum: true, scrollbar: true, thumb: style.color(t.tokens, .Border), change: change, virtual_first: first, virtual_count: row_total, virtual_extent: extent }, view_style, rows[0usize..count])
    var sem: widget.Semantics = zero
    sem.role = 30u8
    sem.label = label
    sem.column_count = u32(columns)
    sem.row_count = u32(row_total)
    ret (widget.semantics(0u64, sem, style.defaults(), body[0usize..1usize]), ok)
}
