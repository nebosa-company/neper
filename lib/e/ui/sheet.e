// A spreadsheet grid (D2283, L090). The first half is the geometry the visual control stands on, pure and widget-free so it can be
// tested against a brute-force model: axes of rows and columns with a default size and sparse overrides (sizes 0 hide),
// merged cells, frozen rows and columns, the part of the sheet in view for a scroll offset and a viewport, the rectangle
// of any cell, which cell a point falls in, a selection grown to take whole merged cells, keyboard navigation that steps over
// merged cells and hidden lines, and the scroll offset that brings a cell into view. A sheet of a million rows costs what
// its overrides cost: positions come from the default size and a prefix sum over the sorted overrides, found by binary
// search. Coordinates are logical pixels. The viewport excludes the row and column headers, which have their own sizes in
// `View`; frozen lines stay at the viewport's start while the rest scrolls under them.

use e.mem
use e.gfx.geometry
use e.gfx.paint
use e.ui.accessibility
use e.ui.control
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.widget

type Override = struct { index: usize, size: f32 }
type Axis = struct { count: usize, default_size: f32, overrides: []const Override, prefix: []const f32 }
type Merge = struct { row: usize, col: usize, rows: usize, cols: usize }
type Merges = struct { items: []const Merge, max_rows: usize }
type Grid = struct { rows: Axis, cols: Axis, merges: Merges, frozen_rows: usize, frozen_cols: usize }
// A viewport in logical pixels: the scroll offsets into the scrollable part, the viewport's size, and the headers' sizes.
type View = struct { x: f32, y: f32, width: f32, height: f32, header_width: f32, header_height: f32 }
type Visible = struct { first_row: usize, last_row: usize, first_col: usize, last_col: usize }
type Selection = struct { row: usize, col: usize, anchor_row: usize, anchor_col: usize }
type Range = struct { row: usize, col: usize, rows: usize, cols: usize }
type Region = enum u8 { Cell, ColumnHeader, RowHeader, Corner, Outside }
type Hit = struct { region: Region, row: usize, col: usize }
type Move = enum u8 { Left, Right, Up, Down, Home, End, PageUp, PageDown, First, Last }
type CellRect = struct { row: usize, col: usize, rows: usize, cols: usize, rect: geometry.Rect, frozen_row: bool, frozen_col: bool }

error Invalid
error TooLarge

// ---- axes -------------------------------------------------------------------------------------------------

// An axis of `count` lines of `default_size`, with `overrides` (strictly ascending indexes below `count`, sizes of 0 or
// more) replacing the default for their lines. Anything else is `Invalid`.
fn axis(a: *mem.Arena, count: usize, default_size: f32, overrides: []const Override) -> (Axis, err) {
    var none = Axis { count: 0usize, default_size: 0.0, overrides: zero, prefix: zero }
    if !(default_size > 0.0) { ret (none, Invalid) }
    var i = 0usize
    while i < overrides.len {
        if overrides[i].index >= count || !(overrides[i].size >= 0.0) { ret (none, Invalid) }
        if i > 0usize && overrides[i].index <= overrides[i - 1usize].index { ret (none, Invalid) }
        i += 1usize
    }
    let (prefix, prefix_error) = mem.alloc[f32](a, overrides.len + 1usize)
    if prefix_error != ok { ret (none, TooLarge) }
    prefix[0usize] = 0.0
    i = 0usize
    while i < overrides.len {
        prefix[i + 1usize] = prefix[i] + (overrides[i].size - default_size)
        i += 1usize
    }
    ret (Axis { count: count, default_size: default_size, overrides: overrides, prefix: prefix[0usize..overrides.len + 1usize] }, ok)
}

// The number of overrides with an index below `index`.
fn overrides_before(ax: Axis, index: usize) -> usize {
    var lo = 0usize
    var hi = ax.overrides.len
    while lo < hi {
        let mid = lo + (hi - lo) / 2usize
        if ax.overrides[mid].index < index { lo = mid + 1usize } else { hi = mid }
    }
    ret lo
}

// Where line `index` starts (`count` gives the axis's total).
fn axis_start(ax: Axis, index: usize) -> f32 {
    var i = index
    if i > ax.count { i = ax.count }
    ret f32(i) * ax.default_size + ax.prefix[overrides_before(ax, i)]
}

fn axis_size(ax: Axis, index: usize) -> f32 {
    let k = overrides_before(ax, index)
    if k < ax.overrides.len && ax.overrides[k].index == index { ret ax.overrides[k].size }
    ret ax.default_size
}

fn axis_total(ax: Axis) -> f32 { ret axis_start(ax, ax.count) }

// The line holding position `pos` (a line owns from its start to the start of the next): the first line for a position
// before the axis, the last for one past it, and never a hidden (size 0) line.
fn axis_index_at(ax: Axis, pos: f32) -> usize {
    if ax.count == 0usize { ret 0usize }
    if pos <= 0.0 {
        var first = 0usize
        while first + 1usize < ax.count && axis_size(ax, first) == 0.0 { first += 1usize }
        ret first
    }
    var lo = 0usize
    var hi = ax.count
    while lo + 1usize < hi {
        let mid = lo + (hi - lo) / 2usize
        if axis_start(ax, mid) <= pos { lo = mid } else { hi = mid }
    }
    var found = lo
    // a hidden line owns nothing: move to the line that does
    while found + 1usize < ax.count && axis_size(ax, found) == 0.0 { found += 1usize }
    if axis_size(ax, found) == 0.0 {
        while found > 0usize && axis_size(ax, found) == 0.0 { found -= 1usize }
    }
    ret found
}

// ---- merges -------------------------------------------------------------------------------------------------

fn merge_before(x: Merge, y: Merge) -> bool {
    if x.row != y.row { ret x.row < y.row }
    ret x.col < y.col
}

// The merges of a sheet, sorted by their top-left cell. Each is at least two cells, inside the sheet, and none may
// overlap another (`Invalid`).
fn merges(a: *mem.Arena, items: []const Merge, row_count: usize, col_count: usize) -> (Merges, err) {
    var none = Merges { items: zero, max_rows: 0usize }
    let (sorted, sorted_error) = mem.alloc[Merge](a, items.len + 1usize)
    if sorted_error != ok { ret (none, TooLarge) }
    var i = 0usize
    while i < items.len {
        let m = items[i]
        if m.rows == 0usize || m.cols == 0usize || m.rows * m.cols < 2usize || m.row + m.rows > row_count || m.col + m.cols > col_count { ret (none, Invalid) }
        // insertion into place
        var at = i
        while at > 0usize && merge_before(m, sorted[at - 1usize]) {
            sorted[at] = sorted[at - 1usize]
            at -= 1usize
        }
        sorted[at] = m
        i += 1usize
    }
    var max_rows = 1usize
    i = 0usize
    while i < items.len {
        if sorted[i].rows > max_rows { max_rows = sorted[i].rows }
        var j = i + 1usize
        while j < items.len && sorted[j].row < sorted[i].row + sorted[i].rows {
            if sorted[j].col < sorted[i].col + sorted[i].cols && sorted[i].col < sorted[j].col + sorted[j].cols { ret (none, Invalid) }
            j += 1usize
        }
        i += 1usize
    }
    ret (Merges { items: sorted[0usize..items.len], max_rows: max_rows }, ok)
}

// The merge holding cell (`row`, `col`), if any.
fn merge_at(m: Merges, row: usize, col: usize) -> (Merge, bool) {
    var none = Merge { row: row, col: col, rows: 1usize, cols: 1usize }
    // the merges whose top row is in [row - max_rows + 1, row]
    var lo = 0usize
    var hi = m.items.len
    while lo < hi {
        let mid = lo + (hi - lo) / 2usize
        if m.items[mid].row + m.max_rows <= row { lo = mid + 1usize } else { hi = mid }
    }
    var i = lo
    while i < m.items.len && m.items[i].row <= row {
        let c = m.items[i]
        if row < c.row + c.rows && col >= c.col && col < c.col + c.cols { ret (c, true) }
        i += 1usize
    }
    ret (none, false)
}

// A grid: its axes, merges and the number of frozen rows and columns. A merge may not cross the freeze lines.
fn grid(rows: Axis, cols: Axis, merge_list: Merges, frozen_rows: usize, frozen_cols: usize) -> (Grid, err) {
    var none: Grid = zero
    if frozen_rows > rows.count || frozen_cols > cols.count { ret (none, Invalid) }
    var i = 0usize
    while i < merge_list.items.len {
        let m = merge_list.items[i]
        if (m.row < frozen_rows && m.row + m.rows > frozen_rows) || (m.col < frozen_cols && m.col + m.cols > frozen_cols) { ret (none, Invalid) }
        i += 1usize
    }
    ret (Grid { rows: rows, cols: cols, merges: merge_list, frozen_rows: frozen_rows, frozen_cols: frozen_cols }, ok)
}

// The cell that owns (`row`, `col`): itself, or the top-left cell of its merge, with the merge's extent.
fn owner(g: Grid, row: usize, col: usize) -> Range {
    let (m, found) = merge_at(g.merges, row, col)
    if found { ret Range { row: m.row, col: m.col, rows: m.rows, cols: m.cols } }
    ret Range { row: row, col: col, rows: 1usize, cols: 1usize }
}

// ---- the viewport -------------------------------------------------------------------------------------------

// The size of the frozen part: the height of the frozen rows and the width of the frozen columns.
fn frozen_size(g: Grid) -> (f32, f32) {
    ret (axis_start(g.cols, g.frozen_cols), axis_start(g.rows, g.frozen_rows))
}

// The room the scrolling part has in the viewport, and how far it can scroll.
fn scroll_limits(g: Grid, v: View) -> (f32, f32) {
    let (frozen_width, frozen_height) = frozen_size(g)
    let room_x = v.width - frozen_width
    let room_y = v.height - frozen_height
    var max_x = (axis_total(g.cols) - frozen_width) - room_x
    var max_y = (axis_total(g.rows) - frozen_height) - room_y
    if max_x < 0.0 { max_x = 0.0 }
    if max_y < 0.0 { max_y = 0.0 }
    ret (max_x, max_y)
}

// The scroll offsets of `v` kept inside what the sheet allows.
fn clamp_scroll(g: Grid, v: View) -> (f32, f32) {
    let (max_x, max_y) = scroll_limits(g, v)
    var x = v.x
    var y = v.y
    if x < 0.0 { x = 0.0 }
    if y < 0.0 { y = 0.0 }
    if x > max_x { x = max_x }
    if y > max_y { y = max_y }
    ret (x, y)
}

// The rows and columns of the scrolling part that show in the viewport, partly shown ones included, widened to the merges
// that reach into view from outside it. The ranges are half open and may be empty.
fn visible_range(g: Grid, v: View) -> Visible {
    let (frozen_width, frozen_height) = frozen_size(g)
    let start_x = frozen_width + v.x
    let start_y = frozen_height + v.y
    var out = Visible { first_row: g.frozen_rows, last_row: g.frozen_rows, first_col: g.frozen_cols, last_col: g.frozen_cols }
    if g.rows.count > g.frozen_rows && v.height > frozen_height {
        out.first_row = axis_index_at(g.rows, start_y)
        if out.first_row < g.frozen_rows { out.first_row = g.frozen_rows }
        var last = axis_index_at(g.rows, start_y + (v.height - frozen_height) - 0.001) + 1usize
        if start_y >= axis_total(g.rows) { last = out.first_row }
        out.last_row = last
    }
    if g.cols.count > g.frozen_cols && v.width > frozen_width {
        out.first_col = axis_index_at(g.cols, start_x)
        if out.first_col < g.frozen_cols { out.first_col = g.frozen_cols }
        var last = axis_index_at(g.cols, start_x + (v.width - frozen_width) - 0.001) + 1usize
        if start_x >= axis_total(g.cols) { last = out.first_col }
        out.last_col = last
    }
    // merges that start before the window but reach into it, a frozen line's merges included, until nothing moves
    var changed = true
    while changed {
        changed = false
        var i = 0usize
        while i < g.merges.items.len {
            let m = g.merges.items[i]
            if m.row >= g.frozen_rows {
                let cols_in_view = m.col < g.frozen_cols || (m.col < out.last_col && m.col + m.cols > out.first_col)
                if m.row < out.first_row && m.row + m.rows > out.first_row && cols_in_view {
                    out.first_row = m.row
                    changed = true
                }
            }
            if m.col >= g.frozen_cols {
                let rows_in_view = m.row < g.frozen_rows || (m.row < out.last_row && m.row + m.rows > out.first_row)
                if m.col < out.first_col && m.col + m.cols > out.first_col && rows_in_view {
                    out.first_col = m.col
                    changed = true
                }
            }
            i += 1usize
        }
    }
    ret out
}

// A line's screen position on one axis (relative to the viewport's start): frozen lines stand at their own place, the
// others are moved by the frozen part and the scroll.
fn screen_start(ax: Axis, frozen: usize, scroll: f32, index: usize) -> f32 {
    if index < frozen { ret axis_start(ax, index) }
    ret axis_start(ax, frozen) + axis_start(ax, index) - axis_start(ax, frozen) - scroll
}

// The rectangle of the cell that owns (`row`, `col`) in viewport coordinates (the headers not included). A merge that
// stands in the scrolling part is moved with it as a whole.
fn cell_rect(g: Grid, v: View, row: usize, col: usize) -> CellRect {
    let o = owner(g, row, col)
    let x = screen_start(g.cols, g.frozen_cols, v.x, o.col)
    let y = screen_start(g.rows, g.frozen_rows, v.y, o.row)
    let width = axis_start(g.cols, o.col + o.cols) - axis_start(g.cols, o.col)
    let height = axis_start(g.rows, o.row + o.rows) - axis_start(g.rows, o.row)
    ret CellRect { row: o.row, col: o.col, rows: o.rows, cols: o.cols, rect: geometry.rect(x, y, width, height), frozen_row: o.row < g.frozen_rows, frozen_col: o.col < g.frozen_cols }
}

fn overlaps(r: geometry.Rect, width: f32, height: f32) -> bool {
    ret r.x < width && r.x + r.width > 0.0 && r.y < height && r.y + r.height > 0.0 && r.width > 0.0 && r.height > 0.0
}

// Every cell that draws in the viewport -- one entry per owning cell, covered cells left out -- the frozen corner, the
// frozen rows, the frozen columns and the scrolling part, in row-major order of their top-left cells within each.
fn visible_cells(a: *mem.Arena, g: Grid, v: View) -> ([]const CellRect, err) {
    let vis = visible_range(g, v)
    let (frozen_width, frozen_height) = frozen_size(g)
    let rows_shown = vis.last_row - vis.first_row + g.frozen_rows
    let cols_shown = vis.last_col - vis.first_col + g.frozen_cols
    let (out, out_error) = mem.alloc[CellRect](a, rows_shown * cols_shown + 1usize)
    if out_error != ok { ret (zero, TooLarge) }
    var n = 0usize
    var r_pass = 0usize
    while r_pass < 2usize {
        var r = 0usize
        var r_end = g.frozen_rows
        if r_pass == 1usize {
            r = vis.first_row
            r_end = vis.last_row
        }
        while r < r_end {
            var c_pass = 0usize
            while c_pass < 2usize {
                var c = 0usize
                var c_end = g.frozen_cols
                if c_pass == 1usize {
                    c = vis.first_col
                    c_end = vis.last_col
                }
                while c < c_end {
                    let o = owner(g, r, c)
                    let cr = cell_rect(g, v, o.row, o.col)
                    let under_columns = !cr.frozen_col && cr.rect.x + cr.rect.width <= frozen_width
                    let under_rows = !cr.frozen_row && cr.rect.y + cr.rect.height <= frozen_height
                    if overlaps(cr.rect, v.width, v.height) && !under_columns && !under_rows && !listed(out[..n], cr.row, cr.col) {
                        out[n] = cr
                        n += 1usize
                    }
                    c += 1usize
                }
                c_pass += 1usize
            }
            r += 1usize
        }
        r_pass += 1usize
    }
    ret (out[..n], ok)
}

fn listed(items: []const CellRect, row: usize, col: usize) -> bool {
    var i = 0usize
    while i < items.len {
        if items[i].row == row && items[i].col == col { ret true }
        i += 1usize
    }
    ret false
}

// Which part of the sheet the point (`x`, `y`) -- relative to the control's top-left corner, headers included -- is in,
// and for a cell its owning cell. Points beyond the cells (but in the viewport) are `Outside`.
fn hit_test(g: Grid, v: View, x: f32, y: f32) -> Hit {
    var none = Hit { region: .Outside, row: 0usize, col: 0usize }
    if x < 0.0 || y < 0.0 || x >= v.header_width + v.width || y >= v.header_height + v.height { ret none }
    let in_row_header = x < v.header_width
    let in_col_header = y < v.header_height
    if in_row_header && in_col_header { ret Hit { region: .Corner, row: 0usize, col: 0usize } }
    let (frozen_width, frozen_height) = frozen_size(g)
    var col = 0usize
    var row = 0usize
    if !in_row_header {
        let px = x - v.header_width
        if px < frozen_width { col = axis_index_at(g.cols, px) } else { col = axis_index_at(g.cols, px + v.x) }
        if px >= frozen_width && px + v.x >= axis_total(g.cols) { ret none }
    }
    if !in_col_header {
        let py = y - v.header_height
        if py < frozen_height { row = axis_index_at(g.rows, py) } else { row = axis_index_at(g.rows, py + v.y) }
        if py >= frozen_height && py + v.y >= axis_total(g.rows) { ret none }
    }
    if in_row_header { ret Hit { region: .RowHeader, row: row, col: 0usize } }
    if in_col_header { ret Hit { region: .ColumnHeader, row: 0usize, col: col } }
    let o = owner(g, row, col)
    ret Hit { region: .Cell, row: o.row, col: o.col }
}

// ---- selection and movement ---------------------------------------------------------------------------------

// The selected block, grown until it takes every merge it touches whole.
fn selection_range(g: Grid, s: Selection) -> Range {
    var r0 = s.row
    var r1 = s.anchor_row
    if r1 < r0 {
        r0 = s.anchor_row
        r1 = s.row
    }
    var c0 = s.col
    var c1 = s.anchor_col
    if c1 < c0 {
        c0 = s.anchor_col
        c1 = s.col
    }
    // inclusive bounds, widened while a merge pokes out
    var changed = true
    while changed {
        changed = false
        var i = 0usize
        while i < g.merges.items.len {
            let m = g.merges.items[i]
            let touches = m.row <= r1 && m.row + m.rows > r0 && m.col <= c1 && m.col + m.cols > c0
            if touches {
                if m.row < r0 {
                    r0 = m.row
                    changed = true
                }
                if m.row + m.rows - 1usize > r1 {
                    r1 = m.row + m.rows - 1usize
                    changed = true
                }
                if m.col < c0 {
                    c0 = m.col
                    changed = true
                }
                if m.col + m.cols - 1usize > c1 {
                    c1 = m.col + m.cols - 1usize
                    changed = true
                }
            }
            i += 1usize
        }
    }
    ret Range { row: r0, col: c0, rows: r1 - r0 + 1usize, cols: c1 - c0 + 1usize }
}

// The next line from `index` in a direction on one axis, over hidden lines; `index` itself when there is none.
fn step_line(ax: Axis, index: usize, forward: bool) -> usize {
    var i = index
    while true {
        if forward {
            if i + 1usize >= ax.count { ret index }
            i += 1usize
        } else {
            if i == 0usize { ret index }
            i -= 1usize
        }
        if axis_size(ax, i) > 0.0 { ret i }
    }
    ret index
}

// A new selection after `how`. The active cell is always the owner of a merge; a step leaves the active cell's merge whole
// and lands on the cell beyond it (its owner when that is merged too); `extend` keeps the anchor, else the anchor follows.
// `Home` and `End` go to the first and last visible column of the row, `First` and `Last` to the corners of the sheet,
// `PageUp` and `PageDown` move `page` rows.
fn navigate(g: Grid, s: Selection, how: Move, extend: bool, page: usize) -> Selection {
    let here = owner(g, s.row, s.col)
    var row = here.row
    var col = here.col
    if how == .Left {
        col = step_line(g.cols, here.col, false)
    }
    if how == .Right {
        let edge = here.col + here.cols - 1usize
        let next = step_line(g.cols, edge, true)
        if next == edge { col = here.col } else { col = next }
    }
    if how == .Up {
        row = step_line(g.rows, here.row, false)
    }
    if how == .Down {
        let edge = here.row + here.rows - 1usize
        let next = step_line(g.rows, edge, true)
        if next == edge { row = here.row } else { row = next }
    }
    if how == .Home { col = first_line(g.cols) }
    if how == .End { col = last_line(g.cols) }
    if how == .First {
        row = first_line(g.rows)
        col = first_line(g.cols)
    }
    if how == .Last {
        row = last_line(g.rows)
        col = last_line(g.cols)
    }
    if how == .PageUp || how == .PageDown {
        var k = 0usize
        while k < page {
            let before = row
            row = step_line(g.rows, row, how == .PageDown)
            if row == before { break }
            k += 1usize
        }
    }
    // the cell landed on may be covered by a merge: take its owner
    let landed = owner(g, row, col)
    var out = Selection { row: landed.row, col: landed.col, anchor_row: landed.row, anchor_col: landed.col }
    if extend {
        out.anchor_row = s.anchor_row
        out.anchor_col = s.anchor_col
    }
    ret out
}

fn first_line(ax: Axis) -> usize {
    var i = 0usize
    while i + 1usize < ax.count && axis_size(ax, i) == 0.0 { i += 1usize }
    ret i
}

fn last_line(ax: Axis) -> usize {
    if ax.count == 0usize { ret 0usize }
    var i = ax.count - 1usize
    while i > 0usize && axis_size(ax, i) == 0.0 { i -= 1usize }
    ret i
}

// The scroll offsets that bring the owner of (`row`, `col`) fully into view with the least movement from `v`'s: a cell
// already in view keeps them, a frozen line needs none, and one larger than the viewport is aligned to its start.
fn reveal(g: Grid, v: View, row: usize, col: usize) -> (f32, f32) {
    let o = owner(g, row, col)
    let (frozen_width, frozen_height) = frozen_size(g)
    var x = v.x
    var y = v.y
    if o.col >= g.frozen_cols {
        let left = axis_start(g.cols, o.col) - frozen_width
        let right = axis_start(g.cols, o.col + o.cols) - frozen_width
        let room = v.width - frozen_width
        if left < x || right - left > room { x = left } else if right > x + room { x = right - room }
    }
    if o.row >= g.frozen_rows {
        let top = axis_start(g.rows, o.row) - frozen_height
        let bottom = axis_start(g.rows, o.row + o.rows) - frozen_height
        let room = v.height - frozen_height
        if top < y || bottom - top > room { y = top } else if bottom > y + room { y = bottom - room }
    }
    let probe = View { x: x, y: y, width: v.width, height: v.height, header_width: v.header_width, header_height: v.header_height }
    let (cx, cy) = clamp_scroll(g, probe)
    ret (cx, cy)
}

// ---------------------------------------------------------------- the control (D2283, part 2)

// The visual control over the geometry above: headers lettered and numbered, only the cells in view built, merged cells
// as one, frozen lines held in place, cell fills, ink and borders, a selection range and an active cell, in-cell editing
// in an editor over the cell, content (a chart, say) laid over a block of cells, wheel and key scrolling that keeps the
// active cell in view. The caller owns the state and the text: the control builds what it is given and reports what the user
// asked as `SheetEvent`s carrying the state the user's action leads to.

type Align = enum u8 { Left, Center, Right }
type CellStyle = struct {
    fill: paint.Color, filled: bool, ink: paint.Color, inked: bool, bold: bool, align: Align,
    top: bool, right: bool, bottom: bool, left: bool, border: paint.Color,
}
type SheetCell = struct { text: str, style: CellStyle, read_only: bool }
type SheetSource = struct { ctx: *void, cell: fn(*void, usize, usize) -> SheetCell }
// Content laid over the cells `rows` by `cols` from (`row`, `col`), clipped to the sheet; its rectangle is `embed_rect`.
type Embed = struct { row: usize, col: usize, rows: usize, cols: usize, label: str, content: widget.Node }
type SheetState = struct { selection: Selection, editing: bool, len: usize, scroll_x: f32, scroll_y: f32 }
type SheetEventKind = enum u8 { Select, Extend, Edit, Type, Commit, Cancel, Scroll }
// `state` is the state the action leads to; a Commit carries the edited cell and its text, a Type the new length.
type SheetEvent = struct { kind: SheetEventKind, state: SheetState, row: usize, col: usize, text: str }
type SheetOptions = struct { header_width: f32, header_height: f32, disabled: bool }

fn sheet_options() -> SheetOptions {
    ret SheetOptions { header_width: 48.0, header_height: 24.0, disabled: false }
}

// Column names: A to Z, then AA, AB, and so on.
fn column_name(a: *mem.Arena, col: usize) -> (str, err) {
    let (buf, buf_error) = mem.alloc[u8](a, 8usize)
    if buf_error != ok { ret ("", TooLarge) }
    var digits: [8]u8 = zero
    var n = 0usize
    var rest = col + 1usize
    while rest > 0usize && n < 8usize {
        let digit = (rest - 1usize) % 26usize
        digits[n] = u8(65usize + digit)
        n += 1usize
        rest = (rest - 1usize) / 26usize
    }
    var i = 0usize
    while i < n {
        buf[i] = digits[n - 1usize - i]
        i += 1usize
    }
    ret (buf[..n], ok)
}

fn number_name(a: *mem.Arena, value: usize) -> (str, err) {
    let (buf, buf_error) = mem.alloc[u8](a, 24usize)
    if buf_error != ok { ret ("", TooLarge) }
    var digits: [24]u8 = zero
    var n = 0usize
    var rest = value
    if rest == 0usize {
        digits[0] = 48u8
        n = 1usize
    }
    while rest > 0usize {
        digits[n] = u8(48usize + rest % 10usize)
        n += 1usize
        rest = rest / 10usize
    }
    var i = 0usize
    while i < n {
        buf[i] = digits[n - 1usize - i]
        i += 1usize
    }
    ret (buf[..n], ok)
}

// The cell's address, `B7`.
fn cell_name(a: *mem.Arena, row: usize, col: usize) -> (str, err) {
    let (letters, letters_error) = column_name(a, col)
    if letters_error != ok { ret ("", letters_error) }
    let (digits, digits_error) = number_name(a, row + 1usize)
    if digits_error != ok { ret ("", digits_error) }
    let (buf, buf_error) = mem.alloc[u8](a, letters.len + digits.len)
    if buf_error != ok { ret ("", TooLarge) }
    mem.copy[u8](buf, letters)
    mem.copy[u8](buf[letters.len..], digits)
    ret (buf[..letters.len + digits.len], ok)
}

// The rectangle `embed` covers in viewport coordinates (the headers not included), from the first cell's to the last's.
fn embed_rect(g: Grid, v: View, e: Embed) -> geometry.Rect {
    let first = cell_rect(g, v, e.row, e.col)
    var last_row = e.row + e.rows - 1usize
    var last_col = e.col + e.cols - 1usize
    if last_row >= g.rows.count { last_row = g.rows.count - 1usize }
    if last_col >= g.cols.count { last_col = g.cols.count - 1usize }
    let last = cell_rect(g, v, last_row, last_col)
    let x = first.rect.x
    let y = first.rect.y
    ret geometry.rect(x, y, last.rect.x + last.rect.width - x, last.rect.y + last.rect.height - y)
}

// The view a control `width` by `height` shows: the headers cut off, the scroll kept inside the sheet.
fn sheet_view(g: Grid, state: SheetState, width: f32, height: f32, options: SheetOptions) -> View {
    var v = View { x: state.scroll_x, y: state.scroll_y, width: width - options.header_width, height: height - options.header_height, header_width: options.header_width, header_height: options.header_height }
    let (x, y) = clamp_scroll(g, v)
    v.x = x
    v.y = y
    ret v
}

type SheetKeys = struct {
    g: Grid, state: SheetState, source: SheetSource, view: View, change: widget.Change[SheetEvent], draft: []u8,
    page_rows: usize, runtime: *widget.Runtime, key: widget.Key, options: SheetOptions,
}

fn with_selection(g: Grid, s: SheetState, selection: Selection, view: View) -> SheetState {
    var next = s
    next.selection = selection
    next.editing = false
    next.len = 0usize
    let (x, y) = reveal(g, view, selection.row, selection.col)
    next.scroll_x = x
    next.scroll_y = y
    ret next
}

fn sheet_key(ctx: *void, k: input.KeyEvent) -> err {
    let s = mem.cast[*SheetKeys](ctx)
    if s.options.disabled || s.g.rows.count == 0usize || s.g.cols.count == 0usize { ret ok }
    let code = widget.key_code(k.key.physical)
    let sel = s.state.selection
    if s.state.editing {
        if code == 27u32 {
            var next = s.state
            next.editing = false
            next.len = 0usize
            ret fire_sheet(s, SheetEvent { kind: .Cancel, state: next, row: sel.row, col: sel.col, text: "" })
        }
        if code == 13u32 || code == 9u32 {
            var how: Move = .Down
            if code == 9u32 { how = .Right }
            if k.modifiers.shift && code == 13u32 { how = .Up }
            if k.modifiers.shift && code == 9u32 { how = .Left }
            let moved = navigate(s.g, sel, how, false, s.page_rows)
            var next = with_selection(s.g, s.state, moved, s.view)
            next.len = 0usize
            ret fire_sheet(s, SheetEvent { kind: .Commit, state: next, row: sel.row, col: sel.col, text: str_of(s.draft, s.state.len) })
        }
        ret ok
    }
    var how: Move = .Right
    var moves = true
    if code == 37u32 { how = .Left } else if code == 39u32 { how = .Right } else if code == 38u32 { how = .Up } else if code == 40u32 { how = .Down } else if code == 36u32 {
        how = .Home
        if k.modifiers.control { how = .First }
    } else if code == 35u32 {
        how = .End
        if k.modifiers.control { how = .Last }
    } else if code == 33u32 { how = .PageUp } else if code == 34u32 { how = .PageDown } else if code == 9u32 {
        how = .Right
        if k.modifiers.shift { how = .Left }
    } else if code == 13u32 && !k.modifiers.shift {
        moves = false
    } else if code == 113u32 {
        moves = false
    } else {
        ret ok
    }
    if !moves {
        let value = s.source.cell(s.source.ctx, sel.row, sel.col)
        if value.read_only { ret ok }
        var next = s.state
        next.editing = true
        next.len = 0usize
        ret fire_sheet(s, SheetEvent { kind: .Edit, state: next, row: sel.row, col: sel.col, text: "" })
    }
    let extend = k.modifiers.shift && code != 9u32
    let moved = navigate(s.g, sel, how, extend, s.page_rows)
    let next = with_selection(s.g, s.state, moved, s.view)
    var kind: SheetEventKind = .Select
    if extend { kind = .Extend }
    ret widget.fire_change[SheetEvent](s.change, SheetEvent { kind: kind, state: next, row: moved.row, col: moved.col, text: "" })
}

fn str_of(buf: []u8, len: usize) -> str {
    if len > buf.len { ret buf[..buf.len] }
    ret buf[..len]
}

// A typed character starts editing the active cell with that text.
fn sheet_input(ctx: *void, event: input.Event) -> err {
    let s = mem.cast[*SheetKeys](ctx)
    if s.options.disabled || s.state.editing { ret ok }
    switch event {
    case .Text as typed:
        if typed.text.len == 0usize || typed.text.len > s.draft.len { ret ok }
        let sel = s.state.selection
        let value = s.source.cell(s.source.ctx, sel.row, sel.col)
        if value.read_only { ret ok }
        mem.copy[u8](s.draft, typed.text)
        var next = s.state
        next.editing = true
        next.len = typed.text.len
        ret fire_sheet(s, SheetEvent { kind: .Edit, state: next, row: sel.row, col: sel.col, text: typed.text })
    default:
        ret ok
    }
}

type SheetPress = struct { keys: *SheetKeys, drag: bool }

fn sheet_press(ctx: *void, gesture: widget.Gesture) -> err {
    let p = mem.cast[*SheetPress](ctx)
    let s = p.keys
    if s.options.disabled { ret ok }
    switch gesture {
    case .Tap as at:
        ret sheet_point(s, at, false)
    case .DoubleTap as at:
        let hit = hit_test(s.g, s.view, at.x, at.y)
        if hit.region != .Cell { ret ok }
        let value = s.source.cell(s.source.ctx, hit.row, hit.col)
        if value.read_only { ret ok }
        var next = with_selection(s.g, s.state, Selection { row: hit.row, col: hit.col, anchor_row: hit.row, anchor_col: hit.col }, s.view)
        next.editing = true
        ret fire_sheet(s, SheetEvent { kind: .Edit, state: next, row: hit.row, col: hit.col, text: "" })
    case .DragMove as drag:
        // the anchor is where the drag began, whatever the pointer's slop did to the first event
        let began = hit_test(s.g, s.view, drag.start.x, drag.start.y)
        let now = hit_test(s.g, s.view, drag.position.x, drag.position.y)
        if began.region != .Cell || now.region != .Cell { ret sheet_point(s, drag.position, true) }
        var next = s.state
        next.selection = Selection { row: now.row, col: now.col, anchor_row: began.row, anchor_col: began.col }
        next.editing = false
        next.len = 0usize
        ret widget.fire_change[SheetEvent](s.change, SheetEvent { kind: .Extend, state: next, row: now.row, col: now.col, text: "" })
    case .Wheel as wheel:
        var v = s.view
        let (max_x, max_y) = scroll_limits(s.g, v)
        var next = s.state
        if widget.modifiers(s.runtime).shift {
            next.scroll_x = next.scroll_x - wheel.notches * s.g.cols.default_size
            if next.scroll_x < 0.0 { next.scroll_x = 0.0 }
            if next.scroll_x > max_x { next.scroll_x = max_x }
        } else {
            next.scroll_y = next.scroll_y - wheel.notches * s.g.rows.default_size * 3.0
            if next.scroll_y < 0.0 { next.scroll_y = 0.0 }
            if next.scroll_y > max_y { next.scroll_y = max_y }
        }
        ret widget.fire_change[SheetEvent](s.change, SheetEvent { kind: .Scroll, state: next, row: next.selection.row, col: next.selection.col, text: "" })
    default:
        ret ok
    }
}

// A point pressed or dragged over: a cell selects (or extends from the anchor), a header selects its whole line.
fn sheet_point(s: *SheetKeys, at: geometry.Point, extend: bool) -> err {
    let hit = hit_test(s.g, s.view, at.x, at.y)
    var picked = s.state.selection
    if hit.region == .Cell {
        picked.row = hit.row
        picked.col = hit.col
        if !extend && !widget.modifiers(s.runtime).shift {
            picked.anchor_row = hit.row
            picked.anchor_col = hit.col
        }
    } else if hit.region == .ColumnHeader {
        picked = Selection { row: 0usize, col: hit.col, anchor_row: s.g.rows.count - 1usize, anchor_col: hit.col }
    } else if hit.region == .RowHeader {
        picked = Selection { row: hit.row, col: 0usize, anchor_row: hit.row, anchor_col: s.g.cols.count - 1usize }
    } else if hit.region == .Corner {
        picked = Selection { row: 0usize, col: 0usize, anchor_row: s.g.rows.count - 1usize, anchor_col: s.g.cols.count - 1usize }
    } else {
        ret ok
    }
    var kind: SheetEventKind = .Select
    if extend || widget.modifiers(s.runtime).shift { kind = .Extend }
    var next = s.state
    next.selection = picked
    next.editing = false
    next.len = 0usize
    ret widget.fire_change[SheetEvent](s.change, SheetEvent { kind: kind, state: next, row: picked.row, col: picked.col, text: "" })
}

fn sheet_typed(ctx: *void, value: str) -> err {
    let s = mem.cast[*SheetKeys](ctx)
    var next = s.state
    next.len = value.len
    ret widget.fire_change[SheetEvent](s.change, SheetEvent { kind: .Type, state: next, row: s.state.selection.row, col: s.state.selection.col, text: value })
}

// Fire an event, then put the focus where the new state wants it: the editor while one is open, else the sheet's holder
// (the editor, or the holder, appears in the next frame; the runtime carries the request across it).
fn fire_sheet(s: *SheetKeys, event: SheetEvent) -> err {
    let fired = widget.fire_change[SheetEvent](s.change, event)
    if fired != ok { ret fired }
    if event.kind == .Edit { ret widget.focus_key(s.runtime, s.key + 2u64) }
    if event.kind == .Commit || event.kind == .Cancel { ret widget.focus_key(s.runtime, s.key + 1u64) }
    ret ok
}

fn cell_ink(t: *const control.Theme, c: SheetCell) -> paint.Color {
    if c.style.inked { ret c.style.ink }
    if c.read_only { ret style.color(t.tokens, .OnSurfaceVariant) }
    ret style.color(t.tokens, .OnSurface)
}

// One cell: a box one pixel short of the cell on its right and bottom, so the sheet's `outline-variant` ground shows between
// cells as the grid lines (a merged cell has none inside), with its fill, its text aligned in it, and a 2px border on the
// sides it asks for.
fn sheet_cell_node(a: *mem.Arena, t: *const control.Theme, rect: geometry.Rect, c: SheetCell, key: widget.Key, row: usize, col: usize, rows: usize, cols: usize, g: Grid) -> (widget.Node, err) {
    var fill = style.color(t.tokens, .Background)
    if c.style.filled { fill = c.style.fill }
    var words = control.text_options()
    words.role = .BodyMedium
    words.wrap = .None
    if c.style.bold { words.weight = 700u32 }
    let (word, word_error) = control.colored_text(a, 0u64, c.text, t, words, cell_ink(t, c))
    if word_error != ok { ret (zero, word_error) }
    var word_count = 1usize
    if c.text.len == 0usize { word_count = 0usize }
    var placement: ui_layout.MainAlign = .Start
    if c.style.align == .Center { placement = .Center }
    if c.style.align == .Right { placement = .End }
    var box = control.sized_style(rect.width - 1.0, rect.height - 1.0)
    box.background = paint.Brush { Solid: fill }
    box.padding = style.EdgeLengths { left: style.Length { Px: 6.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 6.0 }, bottom: style.Length { Px: 0.0 } }
    box.overflow = .Clip
    if c.style.top || c.style.right || c.style.bottom || c.style.left {
        // the border sides as thin boxes laid over the cell
        let (edges, edges_error) = mem.alloc[widget.Node](a, 5usize)
        if edges_error != ok { ret (zero, TooLarge) }
        var e = 0usize
        let w = rect.width - 1.0
        let h = rect.height - 1.0
        let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
        if inner_error != ok { ret (zero, TooLarge) }
        inner[0usize] = word
        edges[e] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: placement, cross: .Center, gap: 0.0 }, box, inner[0usize..word_count])
        e += 1usize
        if c.style.top {
            var edge = control.sized_style(w, 2.0)
            edge.background = paint.Brush { Solid: c.style.border }
            edges[e] = widget.positioned(0u64, 0.0, 0.0, style.defaults(), mem_one(a, widget.box(0u64, edge, zero)))
            e += 1usize
        }
        if c.style.bottom {
            var edge = control.sized_style(w, 2.0)
            edge.background = paint.Brush { Solid: c.style.border }
            edges[e] = widget.positioned(0u64, 0.0, h - 2.0, style.defaults(), mem_one(a, widget.box(0u64, edge, zero)))
            e += 1usize
        }
        if c.style.left {
            var edge = control.sized_style(2.0, h)
            edge.background = paint.Brush { Solid: c.style.border }
            edges[e] = widget.positioned(0u64, 0.0, 0.0, style.defaults(), mem_one(a, widget.box(0u64, edge, zero)))
            e += 1usize
        }
        if c.style.right {
            var edge = control.sized_style(2.0, h)
            edge.background = paint.Brush { Solid: c.style.border }
            edges[e] = widget.positioned(0u64, w - 2.0, 0.0, style.defaults(), mem_one(a, widget.box(0u64, edge, zero)))
            e += 1usize
        }
        var sem_b: widget.Semantics = zero
        sem_b.role = 14u8
        let (name_b, name_b_error) = cell_name(a, row, col)
        if name_b_error != ok { ret (zero, name_b_error) }
        sem_b.label = name_b
        sem_b.value = c.text
        sem_b.row = u32(row + 1usize)
        sem_b.column = u32(col + 1usize)
        sem_b.row_count = u32(g.rows.count)
        sem_b.column_count = u32(g.cols.count)
        if c.read_only { sem_b.states = accessibility.STATE_READ_ONLY }
        ret (widget.semantics(key, sem_b, control.sized_style(rect.width, rect.height), mem_one(a, widget.stack(0u64, control.sized_style(w, h), edges[0usize..e]))), ok)
    }
    var sem: widget.Semantics = zero
    sem.role = 14u8
    let (name, name_error) = cell_name(a, row, col)
    if name_error != ok { ret (zero, name_error) }
    sem.label = name
    sem.value = c.text
    sem.row = u32(row + 1usize)
    sem.column = u32(col + 1usize)
    sem.row_count = u32(g.rows.count)
    sem.column_count = u32(g.cols.count)
    if c.read_only { sem.states = accessibility.STATE_READ_ONLY }
    let (cell_inner, cell_inner_error) = mem.alloc[widget.Node](a, 1usize)
    if cell_inner_error != ok { ret (zero, TooLarge) }
    cell_inner[0usize] = word
    ret (widget.semantics(key, sem, control.sized_style(rect.width, rect.height), mem_one(a, widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: placement, cross: .Center, gap: 0.0 }, box, cell_inner[0usize..word_count]))), ok)
}

fn mem_one(a: *mem.Arena, node: widget.Node) -> []const widget.Node {
    let (one, one_error) = mem.alloc[widget.Node](a, 1usize)
    if one_error != ok { ret zero }
    one[0usize] = node
    ret one[0usize..1usize]
}

// A header cell of `width` by `height` showing `text`, `selected` when the selection covers its line.
fn header_node(a: *mem.Arena, t: *const control.Theme, text: str, width: f32, height: f32, selected: bool) -> (widget.Node, err) {
    var ground = style.color(t.tokens, .SurfaceContainerHigh)
    var ink = style.color(t.tokens, .OnSurfaceVariant)
    if selected {
        ground = style.color(t.tokens, .PrimaryContainer)
        ink = style.color(t.tokens, .OnPrimaryContainer)
    }
    var box = control.sized_style(width, height)
    box.background = paint.Brush { Solid: ground }
    var words = control.text_options()
    words.role = .LabelMedium
    words.wrap = .None
    let (word, word_error) = control.colored_text(a, 0u64, text, t, words, ink)
    if word_error != ok { ret (zero, word_error) }
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, TooLarge) }
    inner[0usize] = word
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Center, cross: .Center, gap: 0.0 }, box, inner[0usize..1usize]), ok)
}

// The sheet, `width` by `height`. Keys from `key`: the focus holder `+ 1`, the editor `+ 2`, a cell `+ 4096 + row * 1024 + col`
// (so a sheet of up to 1024 columns), an embed `+ 1048576 + index`, the headers `+ 2097152 + index` (columns) and
// `+ 3145728 + index` (rows). `draft` holds the text being edited, `state.len` of it long.
fn sheet(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, g: Grid, source: SheetSource, state: SheetState, draft: []u8, embeds: []const Embed, change: widget.Change[SheetEvent], width: f32, height: f32, options: SheetOptions) -> (widget.Node, err) {
    if g.cols.count > 1024usize || g.rows.count == 0usize || g.cols.count == 0usize { ret (zero, TooLarge) }
    let view = sheet_view(g, state, width, height, options)
    let (cells, cells_error) = visible_cells(a, g, view)
    if cells_error != ok { ret (zero, cells_error) }
    let range = selection_range(g, state.selection)
    var body = control.sized_style(view.width, view.height)
    body.overflow = .Clip
    body.background = paint.Brush { Solid: style.color(t.tokens, .OutlineVariant) }
    // cells: scrolled ones first, then the frozen rows and columns over them
    let (layers, layers_error) = mem.alloc[widget.Node](a, cells.len * 2usize + 8usize)
    if layers_error != ok { ret (zero, TooLarge) }
    let (embed_layers, embed_layers_error) = mem.alloc[widget.Node](a, embeds.len + 1usize)
    if embed_layers_error != ok { ret (zero, TooLarge) }
    let (top, top_error) = mem.alloc[widget.Node](a, 4usize)
    if top_error != ok { ret (zero, TooLarge) }
    var n = 0usize
    var pass = 0usize
    while pass < 3usize {
        var i = 0usize
        while i < cells.len {
            let cr = cells[i]
            var layer = 0usize
            if cr.frozen_row || cr.frozen_col { layer = 1usize }
            if cr.frozen_row && cr.frozen_col { layer = 2usize }
            if layer == pass {
                let value = source.cell(source.ctx, cr.row, cr.col)
                let (node, node_error) = sheet_cell_node(a, t, cr.rect, value, key + 4096u64 + u64(cr.row) * 1024u64 + u64(cr.col), cr.row, cr.col, cr.rows, cr.cols, g)
                if node_error != ok { ret (zero, node_error) }
                layers[n] = widget.positioned(0u64, cr.rect.x, cr.rect.y, style.defaults(), mem_one(a, node))
                n += 1usize
                // the selection tints the cell
                if cr.row >= range.row && cr.row < range.row + range.rows && cr.col >= range.col && cr.col < range.col + range.cols && range.rows * range.cols > 1usize {
                    var tint = control.sized_style(cr.rect.width, cr.rect.height)
                    tint.background = paint.Brush { Solid: control.with_alpha(style.color(t.tokens, .Primary), 0.16) }
                    layers[n] = widget.positioned(0u64, cr.rect.x, cr.rect.y, style.defaults(), mem_one(a, widget.box(0u64, tint, zero)))
                    n += 1usize
                }
            }
            i += 1usize
        }
        pass += 1usize
    }
    // embedded content
    var e = 0usize
    while e < embeds.len {
        let rect = embed_rect(g, view, embeds[e])
        var frame = control.sized_style(rect.width, rect.height)
        frame.overflow = .Clip
        let (content, content_error) = mem.alloc[widget.Node](a, 1usize)
        if content_error != ok { ret (zero, TooLarge) }
        content[0usize] = embeds[e].content
        var sem: widget.Semantics = zero
        sem.role = 8u8
        sem.label = embeds[e].label
        let (frame_cell, frame_cell_error) = mem.alloc[widget.Node](a, 1usize)
        if frame_cell_error != ok { ret (zero, TooLarge) }
        frame_cell[0usize] = widget.stack(key + 1048576u64 + u64(e), frame, content[0usize..1usize])
        embed_layers[e] = widget.positioned(0u64, rect.x, rect.y, style.defaults(), mem_one(a, widget.semantics(0u64, sem, style.defaults(), frame_cell[0usize..1usize])))
        e += 1usize
    }
    // the active cell: a ring, and the focusable holder inside it; the editor opens over it
    let active = cell_rect(g, view, state.selection.row, state.selection.col)
    let (keys, keys_error) = mem.alloc[SheetKeys](a, 1usize)
    if keys_error != ok { ret (zero, TooLarge) }
    let (frozen_w, frozen_h) = frozen_size(g)
    var page = usize((view.height - frozen_h) / g.rows.default_size)
    if page == 0usize { page = 1usize }
    keys[0usize] = SheetKeys { g: g, state: state, source: source, view: view, change: change, draft: draft, page_rows: page, runtime: t.runtime, key: key, options: options }
    var fill = style.defaults()
    fill.width = style.Length { Percent: 100.0 }
    fill.height = style.Length { Percent: 100.0 }
    control.focus_look(t)
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, TooLarge) }
    held[0usize] = widget.button(key + 1u64, widget.Button { action: widget.Action { ctx: mem.cast[*void](&keys[0usize]), invoke: sheet_input }, enabled: !options.disabled }, fill, zero)
    var ring = control.sized_style(active.rect.width, active.rect.height)
    ring.overflow = .Clip
    ring.border = style.Border { width: 2.0, color: style.color(t.tokens, .Primary) }
    let (ringed, ringed_error) = mem.alloc[widget.Node](a, 1usize)
    if ringed_error != ok { ret (zero, TooLarge) }
    ringed[0usize] = widget.box(0u64, ring, held[0usize..1usize])
    var tn = 0usize
    top[tn] = widget.stack(0u64, control.sized_style(view.width, view.height), layers[0usize..n])
    tn += 1usize
    top[tn] = widget.stack(0u64, control.sized_style(view.width, view.height), embed_layers[0usize..e])
    tn += 1usize
    top[tn] = widget.positioned(0u64, active.rect.x, active.rect.y, style.defaults(), ringed[0usize..1usize])
    tn += 1usize
    // the editor, over the active cell
    if state.editing && !options.disabled {
        let (look, look_error) = control.text_style(a, t, .BodyMedium)
        if look_error != ok { ret (zero, look_error) }
        let line = style.text_style(t.tokens, .BodyMedium).line_height
        var editor_style = control.sized_style(active.rect.width, active.rect.height)
        editor_style.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerHighest) }
        editor_style.border = style.Border { width: 2.0, color: style.color(t.tokens, .Primary) }
        let sides = style.Length { Px: 6.0 }
        let ends = style.Length { Px: control.max_zero((active.rect.height - line) * 0.5) }
        editor_style.padding = style.EdgeLengths { left: sides, top: ends, right: sides, bottom: ends }
        let (edits, edits_error) = mem.alloc[widget.Node](a, 1usize)
        if edits_error != ok { ret (zero, TooLarge) }
        edits[0usize] = widget.edit(key + 2u64, widget.Edit { buffer: draft, len: state.len, style: look, color: style.color(t.tokens, .OnSurface), selection: style.color(t.tokens, .TextSelection), change: widget.Change[str] { ctx: mem.cast[*void](&keys[0usize]), invoke: sheet_typed }, submit: zero, enabled: true, read_only: false, multiline: false, secret: false, marked: style.color(t.tokens, .Primary), caret: style.color(t.tokens, .OnSurface), untabbed: false, ringed: false }, editor_style)
        let (named, named_error) = control.named_editor(a, key + 2u64, label, "", false, editor_style, edits[0usize])
        if named_error != ok { ret (zero, named_error) }
        top[tn] = widget.positioned(0u64, active.rect.x, active.rect.y, style.defaults(), mem_one(a, named))
        tn += 1usize
    }
    let body_node = widget.stack(0u64, body, top[0usize..tn])
    // headers: column letters over the columns in view, row numbers beside the rows
    let vis = visible_range(g, view)
    let (col_heads, col_heads_error) = mem.alloc[widget.Node](a, g.frozen_cols + (vis.last_col - vis.first_col) + 1usize)
    if col_heads_error != ok { ret (zero, TooLarge) }
    var ch = 0usize
    var pass_c = 0usize
    while pass_c < 2usize {
        var c = 0usize
        var c_end = g.frozen_cols
        if pass_c == 1usize {
            c = vis.first_col
            c_end = vis.last_col
        }
        while c < c_end {
            let size = axis_size(g.cols, c)
            if size > 0.0 {
                let (name, name_error) = column_name(a, c)
                if name_error != ok { ret (zero, name_error) }
                let chosen = c >= range.col && c < range.col + range.cols
                let (node, node_error) = header_node(a, t, name, size, options.header_height, chosen)
                if node_error != ok { ret (zero, node_error) }
                col_heads[ch] = widget.positioned(key + 2097152u64 + u64(c), screen_start(g.cols, g.frozen_cols, view.x, c), 0.0, style.defaults(), mem_one(a, node))
                ch += 1usize
            }
            c += 1usize
        }
        pass_c += 1usize
    }
    let (row_heads, row_heads_error) = mem.alloc[widget.Node](a, g.frozen_rows + (vis.last_row - vis.first_row) + 1usize)
    if row_heads_error != ok { ret (zero, TooLarge) }
    var rh = 0usize
    var pass_r = 0usize
    while pass_r < 2usize {
        var r = 0usize
        var r_end = g.frozen_rows
        if pass_r == 1usize {
            r = vis.first_row
            r_end = vis.last_row
        }
        while r < r_end {
            let size = axis_size(g.rows, r)
            if size > 0.0 {
                let (name, name_error) = number_name(a, r + 1usize)
                if name_error != ok { ret (zero, name_error) }
                let chosen = r >= range.row && r < range.row + range.rows
                let (node, node_error) = header_node(a, t, name, options.header_width, size, chosen)
                if node_error != ok { ret (zero, node_error) }
                row_heads[rh] = widget.positioned(key + 3145728u64 + u64(r), 0.0, screen_start(g.rows, g.frozen_rows, view.y, r), style.defaults(), mem_one(a, node))
                rh += 1usize
            }
            r += 1usize
        }
        pass_r += 1usize
    }
    var col_strip = control.sized_style(view.width, options.header_height)
    col_strip.overflow = .Clip
    var row_strip = control.sized_style(options.header_width, view.height)
    row_strip.overflow = .Clip
    let (corner, corner_error) = header_node(a, t, "", options.header_width, options.header_height, false)
    if corner_error != ok { ret (zero, corner_error) }
    let (frame, frame_error) = mem.alloc[widget.Node](a, 4usize)
    if frame_error != ok { ret (zero, TooLarge) }
    frame[0usize] = widget.positioned(0u64, options.header_width, options.header_height, style.defaults(), mem_one(a, body_node))
    frame[1usize] = widget.positioned(0u64, options.header_width, 0.0, style.defaults(), mem_one(a, widget.stack(0u64, col_strip, col_heads[0usize..ch])))
    frame[2usize] = widget.positioned(0u64, 0.0, options.header_height, style.defaults(), mem_one(a, widget.stack(0u64, row_strip, row_heads[0usize..rh])))
    frame[3usize] = widget.positioned(0u64, 0.0, 0.0, style.defaults(), mem_one(a, corner))
    // the pointer: one region over everything
    let (presses, presses_error) = mem.alloc[SheetPress](a, 1usize)
    if presses_error != ok { ret (zero, TooLarge) }
    presses[0usize] = SheetPress { keys: &keys[0usize], drag: false }
    var area = control.sized_style(width, height)
    area.overflow = .Clip
    area.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let (area_nodes, area_nodes_error) = mem.alloc[widget.Node](a, 1usize)
    if area_nodes_error != ok { ret (zero, TooLarge) }
    area_nodes[0usize] = widget.stack(0u64, area, frame[0usize..4usize])
    let region = widget.region(key + 3u64, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&presses[0usize]), invoke: sheet_press }, gestures: widget.GESTURE_TAP | widget.GESTURE_DRAG | widget.GESTURE_WHEEL, enabled: !options.disabled, focusable: false }, control.sized_style(width, height), area_nodes[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 30u8
    sem.label = label
    sem.row_count = u32(g.rows.count)
    sem.column_count = u32(g.cols.count)
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, TooLarge) }
    inner[0usize] = region
    let scoped = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: zero, default_action: zero, cancel_action: zero, keys: widget.Change[input.KeyEvent] { ctx: mem.cast[*void](&keys[0usize]), invoke: sheet_key } }, style.defaults(), inner[0usize..1usize])
    let (wrapped, wrapped_error) = mem.alloc[widget.Node](a, 1usize)
    if wrapped_error != ok { ret (zero, TooLarge) }
    wrapped[0usize] = scoped
    ret (widget.semantics(key, sem, control.sized_style(width, height), wrapped[0usize..1usize]), ok)
}
