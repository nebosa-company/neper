// Round 62, lane h: shared helpers of the collection sheets (examples/looks/h_*.e). No drawing lives here; the controls draw
// through the shared tokens.

use e.mem
use e.ui.collection
use e.ui.control
use e.ui.looks
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }
fn noop_usize(ctx: *void, value: usize) -> err { ret ok }
fn noop_bool(ctx: *void, value: bool) -> err { ret ok }
fn noop_f32(ctx: *void, value: f32) -> err { ret ok }
fn noop_edit(ctx: *void, value: collection.PairEdit) -> err { ret ok }
fn noop_move(ctx: *void, value: collection.Reorder) -> err { ret ok }

fn word(a: *mem.Arena, t: *const control.Theme, value: str) -> (widget.Node, err) {
    let (made, made_error) = control.text(a, 0u64, value, t, control.text_options())
    ret (made, made_error)
}

// The sheet under all ten looks: Neper, Windows and their darks (run_all), Linux, Cupertino and Material, Light and Dark each.
fn run_ten(a: *mem.Arena, s: *const looks.Sheet) -> err {
    try looks.run_all(a, s)
    try looks.run_linux(a, s)
    try looks.run_cupertino(a, s)
    try looks.run_material(a, s)
    ret ok
}

// Text nodes for `labels`, into `out`.
fn words(a: *mem.Arena, t: *const control.Theme, labels: []const str, out: []widget.Node) -> err {
    var i = 0usize
    while i < labels.len {
        let (made, made_error) = word(a, t, labels[i])
        if made_error != ok { ret made_error }
        out[i] = made
        i += 1usize
    }
    ret ok
}

fn bytes_of(a: *mem.Arena, value: str) -> ([]u8, err) {
    let (buf, buf_error) = mem.alloc[u8](a, value.len + 8usize)
    if buf_error != ok { ret (zero, buf_error) }
    var i = 0usize
    while i < value.len {
        buf[i] = value[i]
        i += 1usize
    }
    ret (buf, ok)
}

// A key-value pair holding `name` and `value`.
fn pair(a: *mem.Arena, name: str, value: str) -> (collection.Pair, err) {
    let (n, n_error) = bytes_of(a, name)
    if n_error != ok { ret (zero, n_error) }
    let (v, v_error) = bytes_of(a, value)
    if v_error != ok { ret (zero, v_error) }
    ret (collection.Pair { name: n, name_len: name.len, value: v, value_len: value.len }, ok)
}

// `items` stacked top to bottom with `gap` between (copied into the arena: the node outlives the caller's array).
fn column(a: *mem.Arena, items: []const widget.Node, gap: f32) -> (widget.Node, err) {
    let (kept, kept_error) = mem.alloc[widget.Node](a, items.len)
    if kept_error != ok { ret (zero, kept_error) }
    var i = 0usize
    while i < items.len {
        kept[i] = items[i]
        i += 1usize
    }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: gap }, style.defaults(), kept[0usize..items.len]), ok)
}
