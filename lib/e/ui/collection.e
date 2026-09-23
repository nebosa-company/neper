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

// --------------------------------------------------- paged collections (D835, P2-06)

// A turn of the page to a given index, for a dot, a button or a key.
type Turn = struct { index: usize, turn: widget.Change[usize] }

fn turn_fire(ctx: *void) -> err {
    let t = mem.cast[*Turn](ctx)
    ret widget.fire_change[usize](t.turn, t.index)
}

// What a page's swipe keeps across the frames of one drag: whether it turned.
type Swipe = struct { turned: bool }

// A page view's drag: the cell the swipe keeps (none on the view's first frame),
// where the pages stand, and whom to tell.
type Paging = struct { cell: *Swipe, has_cell: bool, current: usize, count: usize, threshold: f32, turn: widget.Change[usize] }

fn page_drag(ctx: *void, g: widget.Gesture) -> err {
    let p = mem.cast[*Paging](ctx)
    switch g {
    case .DragStart as at:
        if p.has_cell { p.cell.turned = false }
        ret ok
    case .DragMove as d:
        if !p.has_cell || p.cell.turned { ret ok }
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
        if p.has_cell { p.cell.turned = false }
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
    pagings[0usize] = Paging { cell: none_cell, has_cell: false, current: current, count: pages.len, threshold: width * 0.25, turn: turn }
    // The swipe's cell lives on the view's element from the frame before; on the
    // first frame there is none and a drag that frame turns nothing.
    let (s, state_error) = widget.state_of(t.runtime)
    if state_error == ok {
        let (id, found) = widget.find_by_key(s, key)
        if found == 1usize {
            var build = widget.BuildContext { runtime: t.runtime, element: id, frame: 0u64 }
            let (kept, _, kept_error) = widget.state[Swipe](&build, key, Swipe { turned: false })
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

// A page indicator: a dot a page, keyed `key + 1 + index`, the current one in the
// primary colour and the rest in the border colour, each a tap turning to its
// page; a tab list of tabs in the tree, the current selected.
fn page_indicator(a: *mem.Arena, key: widget.Key, t: *const control.Theme, count: usize, current: usize, turn: widget.Change[usize]) -> (widget.Node, err) {
    if count == 0usize { ret (zero, TooLarge) }
    let (turns, turns_error) = mem.alloc[Turn](a, count)
    if turns_error != ok { ret (zero, TooLarge) }
    let (actions, actions_error) = mem.alloc[widget.Submit](a, count)
    if actions_error != ok { ret (zero, TooLarge) }
    let (dots, dots_error) = mem.alloc[widget.Node](a, count)
    if dots_error != ok { ret (zero, TooLarge) }
    let size = t.tokens.spacing.sm
    var i = 0usize
    while i < count {
        turns[i] = Turn { index: i, turn: turn }
        actions[i] = widget.Submit { ctx: mem.cast[*void](&turns[i]), invoke: turn_fire }
        var dot = control.sized_style(size, size)
        dot.radius = size * 0.5
        var tone: style.ColorRole = .Border
        if i == current { tone = .Primary }
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

// Pagination: a Previous button (keyed `key + 1`), the page numbers around
// `current` -- `window` of them, as digits, the current filled and selected -- keyed
// `key + 3 + index` by page index, and a Next button (`key + 2`), the two disabled
// at the ends; each turns through `turn`. A group in the tree named `label`.
fn pagination(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, count: usize, current: usize, window: usize, turn: widget.Change[usize]) -> (widget.Node, err) {
    if count == 0usize || current >= count || window == 0usize { ret (zero, TooLarge) }
    var first = 0usize
    if current > window / 2usize { first = current - window / 2usize }
    if first + window > count {
        if count > window { first = count - window } else { first = 0usize }
    }
    var shown = window
    if first + shown > count { shown = count - first }
    let (turns, turns_error) = mem.alloc[Turn](a, shown + 2usize)
    if turns_error != ok { ret (zero, TooLarge) }
    let (actions, actions_error) = mem.alloc[widget.Submit](a, shown + 2usize)
    if actions_error != ok { ret (zero, TooLarge) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, shown + 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    var previous = current
    if current > 0usize { previous = current - 1usize }
    var next = current
    if current + 1usize < count { next = current + 1usize }
    turns[0usize] = Turn { index: previous, turn: turn }
    turns[1usize] = Turn { index: next, turn: turn }
    actions[0usize] = widget.Submit { ctx: mem.cast[*void](&turns[0usize]), invoke: turn_fire }
    actions[1usize] = widget.Submit { ctx: mem.cast[*void](&turns[1usize]), invoke: turn_fire }
    var back = control.button_options()
    back.variant = .Outlined
    back.enabled = current > 0usize
    let (back_button, back_error) = control.button(a, key + 1u64, t, "Previous", &actions[0usize], back)
    if back_error != ok { ret (zero, back_error) }
    parts[0usize] = back_button
    var i = 0usize
    while i < shown {
        let page = first + i
        turns[2usize + i] = Turn { index: page, turn: turn }
        actions[2usize + i] = widget.Submit { ctx: mem.cast[*void](&turns[2usize + i]), invoke: turn_fire }
        let (digits, digits_error) = mem.alloc[u8](a, 21usize)
        if digits_error != ok { ret (zero, TooLarge) }
        let digit_count = control.write_i64(digits, i64(page + 1usize))
        let page_key = key + 3u64 + u64(page)
        var variant: style.ControlVariant = .Plain
        if page == current { variant = .Filled }
        let look = style.resolve(t.tokens, variant, control.control_state(t, page_key, true, page == current))
        var caption = control.text_options()
        caption.role = .Label
        caption.wrap = .None
        let (label_node, label_error) = control.colored_text(a, 0u64, digits[0usize..digit_count], t, caption, look.foreground)
        if label_error != ok { ret (zero, label_error) }
        let (numbered, numbered_error) = control.pressable_states(a, page_key, t, 3u8, digits[0usize..digit_count], look, true, page == current, 0u32, 0u32, 0u64, &actions[2usize + i], label_node)
        if numbered_error != ok { ret (zero, numbered_error) }
        parts[1usize + i] = numbered
        i += 1usize
    }
    var forward = control.button_options()
    forward.variant = .Outlined
    forward.enabled = current + 1usize < count
    let (next_button, next_error) = control.button(a, key + 2u64, t, "Next", &actions[1usize], forward)
    if next_error != ok { ret (zero, next_error) }
    parts[shown + 1usize] = next_button
    let (row_node, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row_node[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: t.tokens.spacing.xs }, style.defaults(), parts[0usize..shown + 2usize])
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
    let (kept, _, kept_error) = widget.state[Swipe](&build, key, Swipe { turned: false })
    if kept_error != ok { ret (none, false) }
    ret (kept, true)
}

// A move of a row from one index to another, the explicit action a reorder is.
type Reorder = struct { from: usize, to: usize }

// A row's drag in a reorderable list: which row, how many, how tall each, where
// the list is (by key), and whom to tell on the drop.
type Dragging = struct { runtime: *widget.Runtime, list: widget.Key, index: usize, count: usize, extent: f32, move: widget.Change[Reorder] }

fn reorder_drag(ctx: *void, g: widget.Gesture) -> err {
    let d = mem.cast[*Dragging](ctx)
    switch g {
    case .DragEnd as at:
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
        drags[i] = Dragging { runtime: t.runtime, list: key, index: i, count: items.len, extent: extent, move: move }
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

// A pull's drag: the swipe cell, how far down counts, and whom to tell.
type Pulling = struct { cell: *Swipe, has_cell: bool, threshold: f32, refresh: widget.Submit }

fn pull_drag(ctx: *void, g: widget.Gesture) -> err {
    let p = mem.cast[*Pulling](ctx)
    switch g {
    case .DragStart as at:
        if p.has_cell { p.cell.turned = false }
        ret ok
    case .DragMove as d:
        if !p.has_cell || p.cell.turned { ret ok }
        if d.position.y - d.start.y > p.threshold {
            p.cell.turned = true
            ret widget.fire_submit(p.refresh)
        }
        ret ok
    case .DragEnd as at:
        if p.has_cell { p.cell.turned = false }
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
    pulls[0usize] = Pulling { cell: kept, has_cell: has_cell, threshold: height / 3.0, refresh: *refresh }
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
// the actions are revealed.
type Revealing = struct { cell: *Swipe, has_cell: bool, threshold: f32, reveal: widget.Change[bool] }

fn reveal_drag(ctx: *void, g: widget.Gesture) -> err {
    let r = mem.cast[*Revealing](ctx)
    switch g {
    case .DragStart as at:
        if r.has_cell { r.cell.turned = false }
        ret ok
    case .DragMove as d:
        if !r.has_cell || r.cell.turned { ret ok }
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
        if r.has_cell { r.cell.turned = false }
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
    reveals[0usize] = Revealing { cell: kept, has_cell: has_cell, threshold: width * 0.25, reveal: reveal }
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
    parts[0usize] = widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&reveals[0usize]), invoke: reveal_drag }, gestures: 2u8, enabled: true, focusable: false }, row_style, body[0usize..1usize])
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
        let (opens, opens_error) = mem.alloc[Revealing](a, 1usize)
        if opens_error != ok { ret (zero, TooLarge) }
        opens[0usize] = reveals[0usize]
        more_actions[0usize] = widget.Submit { ctx: mem.cast[*void](&opens[0usize]), invoke: reveal_more }
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

fn reveal_more(ctx: *void) -> err {
    let r = mem.cast[*Revealing](ctx)
    ret widget.fire_change[bool](r.reveal, true)
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
    let (cells, cells_error) = mem.alloc[widget.Node](a, 2usize * columns.len)
    if cells_error != ok { ret (zero, TooLarge) }
    let (drags, drags_error) = mem.alloc[HeaderDrag](a, columns.len)
    if drags_error != ok { ret (zero, TooLarge) }
    let (resizes, resizes_error) = mem.alloc[Resizing](a, columns.len)
    if resizes_error != ok { ret (zero, TooLarge) }
    let grip = t.tokens.spacing.xs
    var i = 0usize
    while i < columns.len {
        let header_key = key + 1u64 + u64(i)
        drags[i] = HeaderDrag { runtime: t.runtime, column: i, sort: sort, reorder: reorder }
        resizes[i] = Resizing { runtime: t.runtime, header: header_key, column: i, low: 2.0 * t.tokens.spacing.lg, resize: resize }
        // The title, with the sort direction after the sorted column's.
        let (title_bytes, title_error) = mem.alloc[u8](a, columns[i].title.len + 2usize)
        if title_error != ok { ret (zero, TooLarge) }
        var n = 0usize
        while n < columns[i].title.len {
            title_bytes[n] = columns[i].title[n]
            n += 1usize
        }
        if i == sort_column {
            title_bytes[n] = 32u8
            title_bytes[n + 1usize] = 94u8
            if descending { title_bytes[n + 1usize] = 118u8 }
            n += 2usize
        }
        var caption = control.text_options()
        caption.role = .Label
        caption.wrap = .None
        caption.ellipsis = "..."
        caption.max_lines = 1u32
        let (title_node, title_node_error) = control.text(a, 0u64, title_bytes[0usize..n], t, caption)
        if title_node_error != ok { ret (zero, title_node_error) }
        let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
        if body_error != ok { ret (zero, TooLarge) }
        body[0usize] = title_node
        // A tap sorts; a drag begins a reorder; a drop on it ends one.
        var head_style = control.sized_style(columns[i].width - grip, t.tokens.metrics.control_height)
        head_style.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceVariant) }
        let pad = style.Length { Px: t.tokens.spacing.xs }
        head_style.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
        head_style.overflow = .Clip
        let (tapped, tapped_error) = mem.alloc[widget.Node](a, 1usize)
        if tapped_error != ok { ret (zero, TooLarge) }
        control.focus_look(t)
        tapped[0usize] = widget.region(header_key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&drags[i]), invoke: header_gesture }, gestures: 1u8 | 2u8 | 8u8, enabled: true, focusable: true }, head_style, body[0usize..1usize])
        var sem: widget.Semantics = zero
        sem.role = 32u8
        sem.label = columns[i].title
        sem.column = u32(i + 1usize)
        sem.column_count = u32(columns.len)
        sem.actions = accessibility.ACTION_PRESS
        if i == sort_column { sem.states = accessibility.STATE_SELECTED }
        cells[2usize * i] = widget.semantics(0u64, sem, style.defaults(), tapped[0usize..1usize])
        var handle = control.sized_style(grip, t.tokens.metrics.control_height)
        handle.background = paint.Brush { Solid: style.color(t.tokens, .Border) }
        cells[2usize * i + 1usize] = widget.region(key + 64u64 + u64(i), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&resizes[i]), invoke: resize_drag }, gestures: 2u8, enabled: true, focusable: false }, handle, zero)
        i += 1usize
    }
    let (row_node, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row_node[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Stretch, gap: 0.0 }, style.defaults(), cells[0usize..2usize * columns.len])
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
    let (boxed, boxed_error) = mem.alloc[widget.Node](a, columns.len)
    if boxed_error != ok { ret (zero, TooLarge) }
    var c = 0usize
    while c < columns.len {
        let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
        if body_error != ok { ret (zero, TooLarge) }
        body[0usize] = cells[c]
        var cell_style = control.sized_style(columns[c].width, extent)
        cell_style.overflow = .Clip
        let pad = style.Length { Px: t.tokens.spacing.xs }
        cell_style.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
        let (framed, framed_error) = mem.alloc[widget.Node](a, 1usize)
        if framed_error != ok { ret (zero, TooLarge) }
        framed[0usize] = widget.box(0u64, cell_style, body[0usize..1usize])
        var cell_sem: widget.Semantics = zero
        cell_sem.role = 14u8
        cell_sem.row = u32(index + 1usize)
        cell_sem.column = u32(c + 1usize)
        boxed[c] = widget.semantics(0u64, cell_sem, style.defaults(), framed[0usize..1usize])
        c += 1usize
    }
    let (picks, picks_error) = mem.alloc[RowPick](a, 1usize)
    if picks_error != ok { ret (zero, TooLarge) }
    picks[0usize] = RowPick { key: row_key, pick: pick }
    var row_style = style.defaults()
    row_style.height = style.Length { Px: extent }
    if selected { row_style.background = paint.Brush { Solid: style.color(t.tokens, .Selection) } }
    let (lined, lined_error) = mem.alloc[widget.Node](a, 1usize)
    if lined_error != ok { ret (zero, TooLarge) }
    lined[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Stretch, gap: 0.0 }, style.defaults(), boxed[0usize..columns.len])
    let (region, region_error) = mem.alloc[widget.Node](a, 1usize)
    if region_error != ok { ret (zero, TooLarge) }
    control.focus_look(t)
    region[0usize] = widget.region(row_key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&picks[0usize]), invoke: row_pick_gesture }, gestures: 1u8 | 4u8, enabled: true, focusable: true }, row_style, lined[0usize..1usize])
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
    let (made, made_error) = tabulated(a, key, t, label, columns, source, selected, sort_column, descending, sort, reorder, resize, pick, extent, offset, change, height, 12u8)
    ret (made, made_error)
}

// A data grid: the table as a grid in the tree, whose cells the source may build
// as fields, so the caller edits in place; the same contract otherwise.
fn data_grid(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, columns: []const Column, source: TableSource, selected: []const widget.Key, sort_column: usize, descending: bool, sort: widget.Change[usize], reorder: widget.Change[Reorder], resize: widget.Change[ColumnResize], pick: widget.Change[widget.Key], extent: f32, offset: f32, change: widget.Change[f32], height: f32) -> (widget.Node, err) {
    let (made, made_error) = tabulated(a, key, t, label, columns, source, selected, sort_column, descending, sort, reorder, resize, pick, extent, offset, change, height, 30u8)
    ret (made, made_error)
}

fn tabulated(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, columns: []const Column, source: TableSource, selected: []const widget.Key, sort_column: usize, descending: bool, sort: widget.Change[usize], reorder: widget.Change[Reorder], resize: widget.Change[ColumnResize], pick: widget.Change[widget.Key], extent: f32, offset: f32, change: widget.Change[f32], height: f32, role: u8) -> (widget.Node, err) {
    if columns.len == 0usize || columns.len > 60usize || extent <= 0.0 { ret (zero, TooLarge) }
    var width: f32 = 0.0
    var c = 0usize
    while c < columns.len {
        width += columns[c].width
        c += 1usize
    }
    let (head, head_error) = header_row(a, key, t, columns, sort_column, descending, sort, reorder, resize)
    if head_error != ok { ret (zero, head_error) }
    let total = source.count(source.ctx)
    let body_height = height - t.tokens.metrics.control_height
    let (first, count) = widget.visible_range(offset, body_height, total, extent)
    let (rows, rows_error) = mem.alloc[widget.Node](a, count)
    if rows_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < count {
        let index = first + i
        let row_key = source.key(source.ctx, index)
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
        let (made, made_error) = table_row(a, t, columns, cells, row_key, index, total, extent, is_selected(selected, row_key), pick, 13u8)
        if made_error != ok { ret (zero, made_error) }
        rows[i] = made
        i += 1usize
    }
    var view_style = style.defaults()
    view_style.width = style.Length { Px: width }
    view_style.height = style.Length { Px: body_height }
    view_style.overflow = .Clip
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = head
    parts[1usize] = widget.scroll(key, widget.Scroll { axis: .Vertical, offset: offset, overscroll: .Clamp, momentum: true, scrollbar: true, thumb: style.color(t.tokens, .Border), change: change, virtual_first: first, virtual_count: total, virtual_extent: extent }, view_style, rows[0usize..count])
    let (column_node, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column_node[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..2usize])
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
fn tree_rows(a: *mem.Arena, key: widget.Key, t: *const control.Theme, source: TreeSource, expanded: []const widget.Key, selected: []const widget.Key, toggle: widget.Change[widget.Key], pick: widget.Change[widget.Key], guides: bool, columns: []const Column, cells_of: CellSource, extent: f32, width: f32) -> ([]widget.Node, err) {
    var none: []widget.Node = zero
    let (visible, visible_error) = mem.alloc[TreeRow](a, 512usize)
    if visible_error != ok { ret (none, TooLarge) }
    let count = flatten(source, expanded, 0u64, 0usize, visible, 0usize)
    let (rows, rows_error) = mem.alloc[widget.Node](a, count)
    if rows_error != ok { ret (none, TooLarge) }
    let (marks, marks_error) = mem.alloc[control.Mark](a, count)
    if marks_error != ok { ret (none, TooLarge) }
    let (toggles, toggles_error) = mem.alloc[RowPick](a, count)
    if toggles_error != ok { ret (none, TooLarge) }
    let (picks, picks_error) = mem.alloc[RowPick](a, count)
    if picks_error != ok { ret (none, TooLarge) }
    let (keys, keys_error) = mem.alloc[TreeKeys](a, count)
    if keys_error != ok { ret (none, TooLarge) }
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 2usize * count)
    if shortcuts_error != ok { ret (none, TooLarge) }
    let indent = t.tokens.spacing.lg
    let mark_size = t.tokens.text[0usize].line_height
    var i = 0usize
    while i < count {
        let entry = visible[i]
        let open = entry.branch && is_selected(expanded, entry.key)
        let chosen = is_selected(selected, entry.key)
        // The disclosure mark, or its blank for a leaf.
        var mark_node = widget.box(0u64, control.sized_style(mark_size, mark_size), zero)
        if entry.branch {
            marks[i] = control.Mark { color: style.color(t.tokens, .Text), expanded: open, arena: a }
            toggles[i] = RowPick { key: entry.key, pick: toggle }
            let (drawn, drawn_error) = mem.alloc[widget.Node](a, 1usize)
            if drawn_error != ok { ret (none, TooLarge) }
            var no_children: []const widget.Node = zero
            drawn[0usize] = widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&marks[i]), measure: control.mark_measure, paint: control.mark_paint, state: widget.bytes_of[control.Mark](&marks[i]) } }, style: control.sized_style(mark_size, mark_size), children: no_children }
            mark_node = widget.region(key + 1u64 + 2u64 * u64(i), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&toggles[i]), invoke: row_pick_gesture }, gestures: 1u8, enabled: true, focusable: false }, control.sized_style(mark_size, mark_size), drawn[0usize..1usize])
        }
        // The first column: the indent, the mark and the node's own row.
        var built: widget.Node = zero
        let built_error = source.build(source.ctx, a, entry.key, &built)
        if built_error != ok { ret (none, built_error) }
        let (lead, lead_error) = mem.alloc[widget.Node](a, 3usize)
        if lead_error != ok { ret (none, TooLarge) }
        var indent_style = control.sized_style(f32(entry.depth) * indent, mark_size)
        if guides && entry.depth > 0usize {
            // An outline's guide: a hairline down the indent's last step.
            let (guide, guide_error) = mem.alloc[widget.Node](a, 1usize)
            if guide_error != ok { ret (none, TooLarge) }
            var line = style.defaults()
            line.width = style.Length { Px: t.tokens.borders.hairline }
            line.height = style.Length { Percent: 100.0 }
            line.background = paint.Brush { Solid: style.color(t.tokens, .Border) }
            line.margin = style.EdgeLengths { left: style.Length { Px: f32(entry.depth) * indent - indent * 0.5 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
            guide[0usize] = widget.box(0u64, line, zero)
            lead[0usize] = widget.box(0u64, indent_style, guide[0usize..1usize])
        } else {
            lead[0usize] = widget.box(0u64, indent_style, zero)
        }
        lead[1usize] = mark_node
        lead[2usize] = built
        let first_cell = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: t.tokens.spacing.xs }, style.defaults(), lead[0usize..3usize])
        // The row's cells: the first column's, then the table's, or the one alone.
        var cell_count = 1usize
        if columns.len > 0usize { cell_count = columns.len }
        let (cells, cells_error) = mem.alloc[widget.Node](a, cell_count)
        if cells_error != ok { ret (none, TooLarge) }
        cells[0usize] = first_cell
        var c = 1usize
        while c < cell_count {
            var extra: widget.Node = zero
            let extra_error = cells_of.cell(cells_of.ctx, a, entry.key, c, &extra)
            if extra_error != ok { ret (none, extra_error) }
            cells[c] = extra
            c += 1usize
        }
        var whole: [1]Column = zero
        whole[0usize] = Column { title: "", width: width }
        var shaped: []const Column = whole[..]
        if columns.len > 0usize { shaped = columns }
        picks[i] = RowPick { key: entry.key, pick: pick }
        let (made, made_error) = table_row(a, t, shaped, cells[0usize..cell_count], entry.key, entry.index, entry.siblings, extent, chosen, pick, 2u8)
        if made_error != ok { ret (none, made_error) }
        // The keyboard: Left collapses, Right expands, from the focused row.
        keys[i] = TreeKeys { key: entry.key, open: open, toggle: toggle }
        shortcuts[2usize * i] = widget.Shortcut { key: 37u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&keys[i]), invoke: tree_collapse } }
        shortcuts[2usize * i + 1usize] = widget.Shortcut { key: 39u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&keys[i]), invoke: tree_expand } }
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
        let (framed, framed_error) = mem.alloc[widget.Node](a, 1usize)
        if framed_error != ok { ret (none, TooLarge) }
        framed[0usize] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: shortcuts[2usize * i..2usize * i + 2usize], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), scoped[0usize..1usize])
        rows[i] = widget.semantics(0u64, item_sem, style.defaults(), framed[0usize..1usize])
        i += 1usize
    }
    ret (rows[0usize..count], ok)
}

// A tree: the visible rows (the expanded nodes' children only) in a column
// `width` wide, each a tap region keyed by its node reporting it through `pick`,
// its disclosure mark and Left/Right reporting it through `toggle` (the caller
// keeps `expanded`), `selected` marking any number; a tree of tree items in the
// tree named `label`.
fn tree(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, source: TreeSource, expanded: []const widget.Key, selected: []const widget.Key, toggle: widget.Change[widget.Key], pick: widget.Change[widget.Key], extent: f32, width: f32) -> (widget.Node, err) {
    let (made, made_error) = treed(a, key, t, label, source, expanded, selected, toggle, pick, false, extent, width)
    ret (made, made_error)
}

// An outline: a tree with a guide line down each level's indent.
fn outline(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, source: TreeSource, expanded: []const widget.Key, selected: []const widget.Key, toggle: widget.Change[widget.Key], pick: widget.Change[widget.Key], extent: f32, width: f32) -> (widget.Node, err) {
    let (made, made_error) = treed(a, key, t, label, source, expanded, selected, toggle, pick, true, extent, width)
    ret (made, made_error)
}

fn no_cell(ctx: *void, a: *mem.Arena, row_key: widget.Key, column: usize, out: *widget.Node) -> err {
    *out = widget.box(0u64, style.defaults(), zero)
    ret ok
}

fn treed(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, source: TreeSource, expanded: []const widget.Key, selected: []const widget.Key, toggle: widget.Change[widget.Key], pick: widget.Change[widget.Key], guides: bool, extent: f32, width: f32) -> (widget.Node, err) {
    var no_columns: []const Column = zero
    var none_ctx: *void = zero
    let (rows, rows_error) = tree_rows(a, key, t, source, expanded, selected, toggle, pick, guides, no_columns, CellSource { ctx: none_ctx, cell: no_cell }, extent, width)
    if rows_error != ok { ret (zero, rows_error) }
    var column_style = style.defaults()
    column_style.width = style.Length { Px: width }
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
// whose items are rows of cells.
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
    let (rows, rows_error) = tree_rows(a, key + 128u64, t, source, expanded, selected, toggle, pick, false, columns, cells_of, extent, width)
    if rows_error != ok { ret (zero, rows_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = head
    parts[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), rows)
    var column_style = style.defaults()
    column_style.width = style.Length { Px: width }
    let (column_node, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column_node[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, column_style, parts[0usize..2usize])
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
// in the tree named `label`.
fn property_grid(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, source: PropertySource, collapsed: []const widget.Key, toggle: widget.Change[widget.Key], name_width: f32, width: f32) -> (widget.Node, err) {
    let total = source.count(source.ctx)
    if total > 256usize { ret (zero, TooLarge) }
    let (rows, rows_error) = mem.alloc[widget.Node](a, total)
    if rows_error != ok { ret (zero, TooLarge) }
    let (blocks, blocks_error) = mem.alloc[widget.Node](a, total)
    if blocks_error != ok { ret (zero, TooLarge) }
    let (toggles, toggles_error) = mem.alloc[GroupToggle](a, total)
    if toggles_error != ok { ret (zero, TooLarge) }
    let (actions, actions_error) = mem.alloc[widget.Submit](a, total)
    if actions_error != ok { ret (zero, TooLarge) }
    var block_count = 0usize
    var i = 0usize
    while i < total {
        // The group from `i` on: its rows into `rows`, then one block of them.
        let head = source.property(source.ctx, i)
        var end = i
        while end < total && same_text(source.property(source.ctx, end).group, head.group) { end += 1usize }
        let group_key = u64(i) + 1u64
        let open = !is_selected(collapsed, group_key)
        var r = i
        while r < end {
            let p = source.property(source.ctx, r)
            var caption = control.text_options()
            caption.role = .Label
            caption.wrap = .None
            caption.ellipsis = "..."
            caption.max_lines = 1u32
            let (name_node, name_error) = control.text(a, 0u64, p.name, t, caption)
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
            let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
            if pair_error != ok { ret (zero, TooLarge) }
            pair[0usize] = widget.semantics(0u64, name_sem, name_style, named[0usize..1usize])
            var editor: widget.Node = zero
            let editor_error = source.editor(source.ctx, a, r, &editor)
            if editor_error != ok { ret (zero, editor_error) }
            let (valued, valued_error) = mem.alloc[widget.Node](a, 1usize)
            if valued_error != ok { ret (zero, TooLarge) }
            valued[0usize] = editor
            var value_sem: widget.Semantics = zero
            value_sem.role = 14u8
            value_sem.row = u32(r + 1usize)
            value_sem.column = 2u32
            var value_style = style.defaults()
            value_style.width = style.Length { Px: width - name_width }
            pair[1usize] = widget.semantics(0u64, value_sem, value_style, valued[0usize..1usize])
            let (lined, lined_error) = mem.alloc[widget.Node](a, 1usize)
            if lined_error != ok { ret (zero, TooLarge) }
            lined[0usize] = widget.flex(p.key, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: t.tokens.spacing.xs }, style.defaults(), pair[0usize..2usize])
            var row_sem: widget.Semantics = zero
            row_sem.role = 13u8
            row_sem.row = u32(r + 1usize)
            row_sem.row_count = u32(total)
            rows[r] = widget.semantics(0u64, row_sem, style.defaults(), lined[0usize..1usize])
            r += 1usize
        }
        let group_rows = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: t.tokens.spacing.xs }, style.defaults(), rows[i..end])
        if head.group.len == 0usize {
            blocks[block_count] = group_rows
        } else {
            toggles[block_count] = GroupToggle { key: group_key, toggle: toggle }
            actions[block_count] = widget.Submit { ctx: mem.cast[*void](&toggles[block_count]), invoke: group_toggle_fire }
            let (opened, opened_error) = control.disclosure(a, key + 1u64 + u64(i), t, head.group, open, &actions[block_count], group_rows)
            if opened_error != ok { ret (zero, opened_error) }
            blocks[block_count] = opened
        }
        block_count += 1usize
        i = end
    }
    var column_style = style.defaults()
    column_style.width = style.Length { Px: width }
    let (column_node, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column_node[0usize] = widget.flex(key, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: t.tokens.spacing.sm }, column_style, blocks[0usize..block_count])
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
// of two columns in the tree named `label`.
fn key_value_editor(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, pairs: []const Pair, edit: widget.Change[PairEdit], remove: widget.Change[usize], add: *const widget.Submit, width: f32) -> (widget.Node, err) {
    if pairs.len > 128usize { ret (zero, TooLarge) }
    let (rows, rows_error) = mem.alloc[widget.Node](a, pairs.len + 1usize)
    if rows_error != ok { ret (zero, TooLarge) }
    let (changes, changes_error) = mem.alloc[PairChange](a, 2usize * pairs.len)
    if changes_error != ok { ret (zero, TooLarge) }
    let (removes, removes_error) = mem.alloc[PairRemove](a, pairs.len)
    if removes_error != ok { ret (zero, TooLarge) }
    let (actions, actions_error) = mem.alloc[widget.Submit](a, pairs.len)
    if actions_error != ok { ret (zero, TooLarge) }
    let field_width = (width - t.tokens.metrics.hit_target - 2.0 * t.tokens.spacing.xs) * 0.5
    var i = 0usize
    while i < pairs.len {
        changes[2usize * i] = PairChange { index: i, value: false, edit: edit }
        changes[2usize * i + 1usize] = PairChange { index: i, value: true, edit: edit }
        removes[i] = PairRemove { index: i, remove: remove }
        actions[i] = widget.Submit { ctx: mem.cast[*void](&removes[i]), invoke: pair_remove_fire }
        let (cells, cells_error) = mem.alloc[widget.Node](a, 3usize)
        if cells_error != ok { ret (zero, TooLarge) }
        var options = control.field_options()
        options.width = field_width
        let (name_field, name_error) = control.text_field(a, key + 1u64 + 3u64 * u64(i), t, "Key", pairs[i].name, pairs[i].name_len, widget.Change[str] { ctx: mem.cast[*void](&changes[2usize * i]), invoke: pair_change_fire }, zero, options)
        if name_error != ok { ret (zero, name_error) }
        cells[0usize] = name_field
        let (value_field, value_error) = control.text_field(a, key + 2u64 + 3u64 * u64(i), t, "Value", pairs[i].value, pairs[i].value_len, widget.Change[str] { ctx: mem.cast[*void](&changes[2usize * i + 1usize]), invoke: pair_change_fire }, zero, options)
        if value_error != ok { ret (zero, value_error) }
        cells[1usize] = value_field
        var plain = control.button_options()
        plain.variant = .Plain
        let (gone, gone_error) = control.button(a, key + 3u64 + 3u64 * u64(i), t, "x", &actions[i], plain)
        if gone_error != ok { ret (zero, gone_error) }
        cells[2usize] = gone
        let (lined, lined_error) = mem.alloc[widget.Node](a, 1usize)
        if lined_error != ok { ret (zero, TooLarge) }
        lined[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .End, gap: t.tokens.spacing.xs }, style.defaults(), cells[0usize..3usize])
        var row_sem: widget.Semantics = zero
        row_sem.role = 13u8
        row_sem.row = u32(i + 1usize)
        row_sem.row_count = u32(pairs.len)
        rows[i] = widget.semantics(0u64, row_sem, style.defaults(), lined[0usize..1usize])
        i += 1usize
    }
    var outlined = control.button_options()
    outlined.variant = .Outlined
    let (more, more_error) = control.button(a, key + 3u64 * u64(pairs.len) + 4u64, t, "Add", add, outlined)
    if more_error != ok { ret (zero, more_error) }
    rows[pairs.len] = more
    var column_style = style.defaults()
    column_style.width = style.Length { Px: width }
    let (column_node, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column_node[0usize] = widget.flex(key, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: t.tokens.spacing.xs }, column_style, rows[0usize..pairs.len + 1usize])
    var sem: widget.Semantics = zero
    sem.role = 12u8
    sem.label = label
    sem.row_count = u32(pairs.len)
    sem.column_count = 2u32
    ret (widget.semantics(0u64, sem, style.defaults(), column_node[0usize..1usize]), ok)
}
