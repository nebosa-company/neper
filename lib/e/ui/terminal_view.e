// Terminal scrollback as a virtual list (D4500, L136): the lines of an `e.ui.terminal` buffer -- scrollback then
// live rows, or the live rows alone on the alternate screen -- as the `e.ui.collection.Source` of a virtual list,
// so only the lines in view (plus overscan) are ever built, and the helpers a host needs around it: stable line
// keys, the offset that follows the newest output, the offset that stays put as old lines fall off the history,
// the cell under a point, and the keys of the lines a selection touches (for the list's `selected`).
//
// Line keys are `sb_dropped + buffer line + 1`: a line keeps its key while it moves from the live rows into
// scrollback and while older lines are evicted (the list's recycling and scroll anchoring depend on that). Alternate
// screen rows are keyed in a separate range (bit 62), by row. A key is only as stable as the line: `resize_reflow`
// and `reset` renumber (they add what they drop to `sb_dropped`, so no old key is reused).
// The widget does not own the terminal: the caller feeds `e.ui.terminal`, keeps the `Viewport` and the arena it
// points into alive for as long as the list is built from it, and rebuilds the list after output.

use e.mem
use e.ui.collection
use e.ui.control
use e.ui.terminal as tm
use e.ui.widget

type Viewport = struct { t: *const tm.Term, theme: *const control.Theme }

const ALT_KEY_BIT: u64 = 4611686018427387904u64

fn viewport(t: *const tm.Term, theme: *const control.Theme) -> Viewport {
    ret Viewport { t: t, theme: theme }
}

// The first buffer line of the list: the alternate screen has no scrollback.
fn base_line(v: *const Viewport) -> usize {
    if v.t.alt { ret v.t.sb_len }
    ret 0usize
}

// Lines the list holds.
fn line_total(v: *const Viewport) -> usize {
    if v.t.alt { ret v.t.rows }
    ret tm.line_count(v.t)
}

// The buffer line (the coordinate `e.ui.terminal` selections use) of list item `index`.
fn buffer_line(v: *const Viewport, index: usize) -> usize {
    ret base_line(v) + index
}

fn line_key(v: *const Viewport, index: usize) -> widget.Key {
    let line = buffer_line(v, index)
    if v.t.alt { ret ALT_KEY_BIT | u64(line - v.t.sb_len + 1usize) }
    ret u64(v.t.sb_dropped + line + 1usize)
}

fn count_of(ctx: *void) -> usize {
    let v = mem.cast[*Viewport](ctx)
    ret line_total(v)
}

fn key_of(ctx: *void, index: usize) -> widget.Key {
    let v = mem.cast[*Viewport](ctx)
    ret line_key(v, index)
}

// One line: its text with trailing blanks trimmed, in the monospace face, unwrapped.
fn build_of(ctx: *void, a: *mem.Arena, index: usize, out: *widget.Node) -> err {
    let v = mem.cast[*Viewport](ctx)
    let (buf, buf_error) = mem.alloc[u8](a, v.t.cols * 4usize + 1usize)
    if buf_error != ok { ret buf_error }
    let n = tm.line_text(v.t, buffer_line(v, index), buf)
    var options = control.text_options()
    options.wrap = .None
    options.mono = true
    let (made, made_error) = control.text(a, 0u64, buf[0usize..n], v.theme, options)
    if made_error != ok { ret made_error }
    *out = made
    ret ok
}

// The list's data source. `v` must outlive every list built from it.
fn source(v: *Viewport) -> collection.Source {
    ret collection.Source { ctx: mem.cast[*void](v), count: count_of, key: key_of, build: build_of }
}

// The scrollback list: `extent` is the line height, `selected` the keys `selected_keys` returned.
fn list(a: *mem.Arena, key: widget.Key, v: *Viewport, label: str, selected: []const widget.Key, extent: f32, offset: f32, change: widget.Change[f32], width: f32, height: f32) -> (widget.Node, err) {
    let (node, node_error) = collection.virtual_list(a, key, v.theme, label, source(v), selected, extent, offset, change, false, width, height)
    ret (node, node_error)
}

// The offset that shows the newest line at the bottom of a list `height` tall.
fn bottom_offset(v: *const Viewport, extent: f32, height: f32) -> f32 {
    let room = f32(line_total(v)) * extent - height
    if room < 0.0 { ret 0.0 }
    ret room
}

// Whether `offset` shows the newest line (within half a line).
fn at_bottom(v: *const Viewport, offset: f32, extent: f32, height: f32) -> bool {
    ret offset + extent * 0.5 >= bottom_offset(v, extent, height)
}

// The offset to show after output: pinned to the bottom when the view was there, else kept on the same lines --
// `dropped_before` is `sb_dropped` when `offset` was taken, and every line evicted since moves the content up one
// `extent`.
fn follow(v: *const Viewport, offset: f32, extent: f32, height: f32, was_at_bottom: bool, dropped_before: usize) -> f32 {
    let bottom = bottom_offset(v, extent, height)
    if was_at_bottom { ret bottom }
    var moved = offset
    if v.t.sb_dropped > dropped_before && !v.t.alt { moved = offset - f32(v.t.sb_dropped - dropped_before) * extent }
    if moved < 0.0 { ret 0.0 }
    if moved > bottom { ret bottom }
    ret moved
}

// The buffer line and column under a point `x`, `y` (list-local, y from the top of the list) at `offset`, with
// cells `cell_width` wide: clamped to the buffer and the row.
fn cell_at(v: *const Viewport, offset: f32, extent: f32, cell_width: f32, x: f32, y: f32) -> (usize, usize) {
    var index = 0usize
    let total = line_total(v)
    if extent > 0.0 && y + offset > 0.0 { index = usize((y + offset) / extent) }
    if total == 0usize { ret (0usize, 0usize) }
    if index >= total { index = total - 1usize }
    var col = 0usize
    if cell_width > 0.0 && x > 0.0 { col = usize(x / cell_width) }
    if col >= v.t.cols { col = v.t.cols - 1usize }
    ret (buffer_line(v, index), col)
}

// The keys of the items in [first, first + count) that `sel` touches, at most `out.len` of them; the list marks
// those rows selected. Pass the range `widget.visible_range` gives for the list's offset.
fn selected_keys(v: *const Viewport, sel: *const tm.Selection, first: usize, count: usize, out: []widget.Key) -> usize {
    if sel.mode == tm.SEL_NONE || count == 0usize { ret 0usize }
    let (first_line, _, last_line, _) = tm.selection_range(v.t, sel)
    var n = 0usize
    var i = 0usize
    while i < count && n < out.len {
        let line = buffer_line(v, first + i)
        if line >= first_line && line <= last_line {
            out[n] = line_key(v, first + i)
            n += 1usize
        }
        i += 1usize
    }
    ret n
}
