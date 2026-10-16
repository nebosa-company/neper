// The edits as the real v3 dialogs show them (TcxMaskEdit, TcxSpinEdit, TcxButtonEdit), one cell
// per instance in the captures docs/ui/looks/ref/windows/dialogs/ (Options: Passwords, Decks,
// Morph, Card Art). Every control stands at the same place in its cell as in the reference
// composite docs/ui/looks/ref/windows/edits_dialog.png, which scripts/looks_edits_ref.py builds
// from those captures, so the Windows render can be diffed against it pixel by pixel.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_change(ctx: *void, value: str) -> err { ret ok }
fn noop_submit(ctx: *void) -> err { ret ok }
fn noop_step(ctx: *void, value: i64) -> err { ret ok }

fn sized(w: f32, h: f32) -> style.Style {
    var s = style.defaults()
    s.width = style.Length { Px: w }
    s.height = style.Length { Px: h }
    ret s
}

// `node` at (8, 4) of a `cell_w` by `cell_h` box (the harness centres that box in its cell).
fn placed(a: *mem.Arena, node: widget.Node) -> (widget.Node, err) {
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, inner_error) }
    inner[0usize] = node
    let (layer, layer_error) = mem.alloc[widget.Node](a, 1usize)
    if layer_error != ok { ret (zero, layer_error) }
    layer[0usize] = widget.positioned(0u64, 8.0, 4.0, style.defaults(), inner[0usize..1usize])
    ret (widget.stack(0u64, sized(520.0, 30.0), layer[0usize..1usize]), ok)
}

fn copy_into(buffer: []u8, words: str) -> usize {
    var n = 0usize
    while n < words.len && n < buffer.len {
        buffer[n] = words[n]
        n += 1usize
    }
    ret n
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [8]str{ "Mask edit, empty (Options Passwords, Old)", "Mask edit, empty (Options Passwords, New)", "Mask edit, empty (Options Passwords, Confirm)", "Spin edit with fast buttons (Options Decks)", "Spin edit (Options Morph)", "Spin edit (Options Morph)", "Button edit (Options Decks)", "Button edit (Options Card Art)" }
    var i = 0usize
    while i < 8usize {
        let (buffer, buffer_error) = mem.alloc[u8](a, 128usize)
        if buffer_error != ok { ret (0usize, buffer_error) }
        let key = u64(10usize * (i + 1usize))
        var node: widget.Node = zero
        let ys = [8]f32{ 89.0, 144.0, 198.0, 159.0, 105.0, 169.0, 94.0, 385.0 }
        let wy = ys[i]
        if i <= 2usize {
            var options = control.field_options()
            options.width = 495.0
            options.window_y = wy
            let (made, made_error) = control.password_field(a, key, t, "Old password", buffer, 0usize, widget.Change[str] { ctx: zero, invoke: noop_change }, widget.Submit { ctx: zero, invoke: noop_submit }, options)
            if made_error != ok { ret (0usize, made_error) }
            node = made
        }
        if i >= 3usize && i <= 5usize {
            var value = 4i64
            var width: f32 = 121.0
            if i == 4usize { value = 650i64 }
            if i == 5usize { value = 500i64 }
            if i != 3usize { width = 67.0 }
            let (made, made_error) = control.windows_spin_with(a, key, t, "Spin", buffer, value, 1i64, 3000i64, 1i64, widget.Change[i64] { ctx: zero, invoke: noop_step }, widget.Change[str] { ctx: zero, invoke: noop_change }, width, i == 3usize, wy)
            if made_error != ok { ret (0usize, made_error) }
            node = made
        }
        if i >= 6usize {
            var words = "C:\\Users\\gaddl\\AppData\\Roaming\\MTG Studio\\My Decks"
            var width: f32 = 495.0
            if i == 7usize {
                words = "C:\\Users\\gaddl\\AppData\\Roaming\\MTG Studio\\Card Art"
                width = 464.0
            }
            let n = copy_into(buffer, words)
            var options = control.field_options()
            options.width = width
            options.window_y = wy
            let action = widget.Submit { ctx: zero, invoke: noop_submit }
            let actions = [1]widget.Submit{ action }
            let (made, made_error) = control.button_edit(a, key, t, "Path", buffer, n, widget.Change[str] { ctx: zero, invoke: noop_change }, action, &actions[0usize], "Browse", options)
            if made_error != ok { ret (0usize, made_error) }
            node = made
        }
        let (at, at_error) = placed(a, node)
        if at_error != ok { ret (0usize, at_error) }
        cells[i] = looks.Cell { caption: captions[i], node: at, drive: .None }
        i += 1usize
    }
    ret (8usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "edits_dialog", cells: 8usize, columns: 1usize, cell_w: 520.0, cell_h: 30.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
