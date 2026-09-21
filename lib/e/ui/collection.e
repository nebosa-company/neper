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
