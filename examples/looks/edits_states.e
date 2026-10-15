// The edits in the interaction states the real v3 captures show (docs/ui/looks/ref/windows/states): keyboard focus with the
// caret, the whole text selected, the ellipsis pressed, and the disabled button edit. Every control stands at the y it has
// in its Options page (`window_y`, the foot's drift), and the cell is placed so that the driven click lands on the control.
// scripts/looks_edits_states_eval.py diffs the sheet against the captures.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
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

// `node` at (x, 4) of a 990 x 30 box.
fn placed(a: *mem.Arena, node: widget.Node, x: f32) -> (widget.Node, err) {
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, inner_error) }
    inner[0usize] = node
    let (layer, layer_error) = mem.alloc[widget.Node](a, 1usize)
    if layer_error != ok { ret (zero, layer_error) }
    layer[0usize] = widget.positioned(0u64, x, 4.0, style.defaults(), inner[0usize..1usize])
    ret (widget.stack(0u64, sized(990.0, 30.0), layer[0usize..1usize]), ok)
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
    let captions = [8]str{ "Mask edit, focused (Options Passwords)", "Spin edit with fast buttons, focused (Options Decks)", "Spin edit, focused (Options Morph)", "Button edit, focused (Options Decks)", "Button edit, text selected (Options Decks)", "Button edit, ellipsis pressed (Options Decks)", "Button edit, disabled (Options Card Art)", "Mask edit, text and caret (Options Passwords)" }
    let drives = [8]looks.Drive{ .Focus, .Focus, .Focus, .Focus, .Select, .Press, .None, .Focus }
    let ys = [8]f32{ 144.0, 159.0, 105.0, 94.0, 94.0, 94.0, 385.0, 144.0 }
    let xs = [8]f32{ 8.0, 440.0, 460.0, 395.0, 395.0, 8.0, 8.0, 8.0 }
    var i = 0usize
    while i < 8usize {
        let (buffer, buffer_error) = mem.alloc[u8](a, 128usize)
        if buffer_error != ok { ret (0usize, buffer_error) }
        let key = u64(10usize * (i + 1usize))
        var node: widget.Node = zero
        if i == 0usize || i == 7usize {
            var options = control.field_options()
            options.width = 495.0
            options.window_y = ys[i]
            var n = 0usize
            if i == 7usize { n = copy_into(buffer, "secret") }
            let (made, made_error) = control.password_field(a, key, t, "New password", buffer, n, widget.Change[str] { ctx: zero, invoke: noop_change }, widget.Submit { ctx: zero, invoke: noop_submit }, options)
            if made_error != ok { ret (0usize, made_error) }
            node = made
        }
        if i == 1usize || i == 2usize {
            var width: f32 = 121.0
            var value = 4i64
            if i == 2usize {
                width = 67.0
                value = 650i64
            }
            let (made, made_error) = control.windows_spin_with(a, key, t, "Spin", buffer, value, 1i64, 3000i64, 1i64, widget.Change[i64] { ctx: zero, invoke: noop_step }, widget.Change[str] { ctx: zero, invoke: noop_change }, width, i == 1usize, ys[i])
            if made_error != ok { ret (0usize, made_error) }
            node = made
        }
        if i >= 3usize && i <= 6usize {
            var words = "C:\\Users\\gaddl\\AppData\\Roaming\\MTG Studio\\My Decks"
            var width: f32 = 495.0
            if i == 6usize {
                words = "MTG Studio Download (all editions + promos)"
                width = 464.0
            }
            let n = copy_into(buffer, words)
            var options = control.field_options()
            options.width = width
            options.window_y = ys[i]
            options.enabled = i != 6usize
            let action = widget.Submit { ctx: zero, invoke: noop_submit }
            let actions = [1]widget.Submit{ action }
            let (made, made_error) = control.button_edit(a, key, t, "Path", buffer, n, widget.Change[str] { ctx: zero, invoke: noop_change }, action, &actions[0usize], "Browse", options)
            if made_error != ok { ret (0usize, made_error) }
            node = made
        }
        let (at, at_error) = placed(a, node, xs[i])
        if at_error != ok { ret (0usize, at_error) }
        cells[i] = looks.Cell { caption: captions[i], node: at, drive: drives[i] }
        i += 1usize
    }
    ret (8usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "edits_states", cells: 8usize, columns: 1usize, cell_w: 990.0, cell_h: 30.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
