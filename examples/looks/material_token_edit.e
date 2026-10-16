// The Android look's token edit: an outlined field of input chips (docs/ui/looks/material/token_edit.png), and with the
// chips wrapped over several lines (token_edit_wrapped.png: run with an argument). Run from the repository root.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_change(ctx: *void, value: str) -> err { ret ok }
fn noop_submit(ctx: *void) -> err { ret ok }

// `node` at (`left`, `top`) in a `across` x `high` box: the harness drives the middle of the cell, so the offsets decide which
// part of the control sits under the pointer.
fn at_xy(a: *mem.Arena, node: widget.Node, left: f32, top: f32, across: f32, high: f32) -> (widget.Node, err) {
    var column = looks.size_style(across, high)
    column.padding = style.EdgeLengths { left: style.Length { Px: left }, top: style.Length { Px: top }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 1usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = node
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, column, parts[0usize..1usize]), ok)
}

fn sized(w: f32, h: f32) -> style.Style {
    var s = style.defaults()
    s.width = style.Length { Px: w }
    s.height = style.Length { Px: h }
    ret s
}

// Six cells: three chips at rest, a hovered chip, a hovered close cross, the input focused after two chips, the empty
// field focused (last: the runtime keeps the focus on a tree slot) and at rest with its hint. `wrapped`: seven chips over
// several lines, and one chip.
fn build_set(a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell, wrapped: bool) -> (usize, err) {
    let captions = [6]str{ "Enabled", "Hovered (chip)", "Hovered (close)", "Empty, hint", "Focused, input", "Empty, focused" }
    let names = [8]str{ "Flying", "Trample", "Haste", "Vigilance", "Deathtouch", "Lifelink", "Reach", "Menace" }
    var total = 6usize
    if wrapped { total = 2usize }
    var i = 0usize
    while i < total {
        var count = 3usize
        if i == 3usize || i == 5usize { count = 0usize }
        if i == 4usize { count = 2usize }
        if wrapped {
            count = 7usize
            if i == 1usize { count = 1usize }
        }
        let (shown, shown_error) = mem.alloc[str](a, 8usize)
        if shown_error != ok { ret (0usize, shown_error) }
        let (removes, removes_error) = mem.alloc[widget.Submit](a, 8usize)
        if removes_error != ok { ret (0usize, removes_error) }
        var n = 0usize
        while n < count {
            shown[n] = names[n]
            removes[n] = widget.Submit { ctx: zero, invoke: noop_submit }
            n += 1usize
        }
        let (buffer, buffer_error) = mem.alloc[u8](a, 32usize)
        if buffer_error != ok { ret (0usize, buffer_error) }
        let none_words = [1]str{ "" }
        let picks = [1]widget.Submit{ widget.Submit { ctx: zero, invoke: noop_submit } }
        let (dismiss, dismiss_error) = mem.alloc[widget.Submit](a, 1usize)
        if dismiss_error != ok { ret (0usize, dismiss_error) }
        dismiss[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
        let key = u64(100usize * (i + 1usize))
        var field_w: f32 = 360.0
        if i == 3usize || i == 5usize { field_w = 200.0 }
        if wrapped { field_w = 300.0 }
        let (edit, edit_error) = control.token_field(a, key, t, "Add keyword", shown[0usize..count], removes[0usize..count], buffer, 0usize, widget.Change[str] { ctx: zero, invoke: noop_change }, widget.Submit { ctx: zero, invoke: noop_submit }, none_words[0usize..0usize], 0usize, false, picks[0usize..0usize], widget.Change[usize] { ctx: zero, invoke: noop_active }, &dismiss[0usize], field_w)
        if edit_error != ok { ret (0usize, edit_error) }
        var node = edit
        var drive: looks.Drive = .None
        var left: f32 = 130.0
        var top: f32 = 47.0
        if wrapped {
            top = 8.0
            left = 160.0
        }
        if !wrapped && i == 1usize {
            left = 252.0
            drive = .Hover
        }
        if !wrapped && i == 2usize {
            left = 210.0
            drive = .Hover
        }
        if !wrapped && i == 4usize {
            left = 40.0
            drive = .Focus
        }
        if !wrapped && i == 5usize {
            left = 250.0
            drive = .Focus
        }
        if !wrapped && (i == 0usize || i == 3usize) { left = 120.0 }
        let (placed, placed_error) = at_xy(a, node, left, top, 620.0, high_of(wrapped))
        if placed_error != ok { ret (0usize, placed_error) }
        var caption = captions[i]
        if wrapped {
            caption = "Wrapped, seven chips"
            if i == 1usize { caption = "One chip" }
        }
        cells[i] = looks.Cell { caption: caption, node: placed, drive: drive }
        i += 1usize
    }
    ret (total, ok)
}

fn high_of(wrapped: bool) -> f32 {
    if wrapped { ret 220.0 }
    ret 150.0
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (made, made_error) = build_set(a, t, cells, false)
    ret (made, made_error)
}

fn build_wrapped(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (made, made_error) = build_set(a, t, cells, true)
    ret (made, made_error)
}

fn noop_active(ctx: *void, value: usize) -> err { ret ok }

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len > 1usize {
        let wrapped = looks.Sheet { name: "token_edit_wrapped", cells: 2usize, columns: 2usize, cell_w: 620.0, cell_h: 220.0, ctx: zero, build: build_wrapped }
        ret looks.run_material(a, &wrapped)
    }
    let sheet = looks.Sheet { name: "token_edit", cells: 6usize, columns: 3usize, cell_w: 620.0, cell_h: 150.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
