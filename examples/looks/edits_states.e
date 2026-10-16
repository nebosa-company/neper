// The edits in every interaction state the real v3 captures show (docs/ui/looks/ref/windows/states): keyboard focus with the
// caret (the click lands where the capture's caret sits), the spin arrows pressed (v3 draws no pressed face on them: the
// grabs differ from the focused one only in the number the auto-repeat reached), the whole text selected, the ellipsis
// pressed with the text selected, the disabled button edit, and the hot key edit (a native THotKey, drawn here from boxes
// since the library has no such control). Every control stands at the y it has in its Options page (`window_y`), and the
// cell is placed so that the driven click lands on the control.
// scripts/looks_edits_states_eval.py diffs the sheet against the captures (same order).
// Run from the repository root; see docs/ui/looks-howto.md.

use e.gfx.paint
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

// A w x h rectangle of gray `v` at (x, y) of a stack.
fn dot(a: *mem.Arena, x: f32, y: f32, w: f32, h: f32, v: u32) -> (widget.Node, err) {
    var s = sized(w, h)
    s.background = paint.Brush { Solid: control.win_rgb(v, v, v) }
    let (one, one_error) = mem.alloc[widget.Node](a, 1usize)
    if one_error != ok { ret (zero, one_error) }
    one[0usize] = widget.box(0u64, s, zero)
    ret (widget.positioned(0u64, x, y, style.defaults(), one[0usize..1usize]), ok)
}

// The hot key edit (THotKey, Options Shortcuts) 325 x 22: the grey two-pixel frame as the capture shows it (the corner
// pixels differ between rest and focus), white face, "Ctrl + N" at rest or "Ctrl + O" focused and, focused, the caret after it.
fn hot_key(a: *mem.Arena, t: *const control.Theme, focused: bool, shortcut: str) -> (widget.Node, err) {
    let (layers, layers_error) = mem.alloc[widget.Node](a, 40usize)
    if layers_error != ok { ret (zero, layers_error) }
    var n = 0usize
    let (face, face_error) = dot(a, 0.0, 0.0, 325.0, 22.0, 255u32)
    if face_error != ok { ret (zero, face_error) }
    layers[n] = face
    n += 1usize
    let xs = [8]f32{ 2.0, 2.0, 2.0, 2.0, 0.0, 1.0, 323.0, 324.0 }
    let ys = [8]f32{ 0.0, 1.0, 20.0, 21.0, 2.0, 2.0, 2.0, 2.0 }
    let ws = [8]f32{ 321.0, 321.0, 321.0, 321.0, 1.0, 1.0, 1.0, 1.0 }
    let hs = [8]f32{ 1.0, 1.0, 1.0, 1.0, 18.0, 18.0, 18.0, 18.0 }
    let vs = [8]u32{ 202u32, 185u32, 213u32, 178u32, 156u32, 238u32, 186u32, 201u32 }
    var i = 0usize
    while i < 8usize {
        let (bar, bar_error) = dot(a, xs[i], ys[i], ws[i], hs[i], vs[i])
        if bar_error != ok { ret (zero, bar_error) }
        layers[n] = bar
        n += 1usize
        i += 1usize
    }
    // Corners (top-left, top-right, bottom-left, bottom-right), each the pixels (x0 y0), (x1 y0), (x0 y1), (x1 y1).
    var corners = [16]u32{ 222u32, 204u32, 179u32, 182u32, 212u32, 232u32, 174u32, 212u32, 170u32, 204u32, 210u32, 182u32, 179u32, 208u32, 194u32, 226u32 }
    if focused { corners = [16]u32{ 210u32, 202u32, 160u32, 179u32, 204u32, 226u32, 161u32, 203u32, 159u32, 202u32, 191u32, 179u32, 171u32, 202u32, 181u32, 218u32 } }
    let cx = [4]f32{ 0.0, 323.0, 0.0, 323.0 }
    let cy = [4]f32{ 0.0, 0.0, 20.0, 20.0 }
    var c = 0usize
    while c < 4usize {
        var k = 0usize
        while k < 4usize {
            let (px, px_error) = dot(a, cx[c] + f32(k % 2usize), cy[c] + f32(k / 2usize), 1.0, 1.0, corners[c * 4usize + k])
            if px_error != ok { ret (zero, px_error) }
            layers[n] = px
            n += 1usize
            k += 1usize
        }
        c += 1usize
    }
    let (ft, ft_error) = control.windows_edit_theme(a, t, 13.0)
    if ft_error != ok { ret (zero, ft_error) }
    var words = control.text_options()
    words.role = .BodyMedium
    words.wrap = .None
    let (label, label_error) = control.colored_text(a, 0u64, shortcut, &ft, words, control.win_rgb(0u32, 0u32, 0u32))
    if label_error != ok { ret (zero, label_error) }
    let (one, one_error) = mem.alloc[widget.Node](a, 1usize)
    if one_error != ok { ret (zero, one_error) }
    one[0usize] = label
    layers[n] = widget.positioned(0u64, 3.0, 4.0, style.defaults(), one[0usize..1usize])
    n += 1usize
    if focused {
        let (bar, bar_error) = dot(a, 42.0, 3.0, 1.0, 14.0, 47u32)
        if bar_error != ok { ret (zero, bar_error) }
        layers[n] = bar
        n += 1usize
        let (soft, soft_error) = dot(a, 43.0, 3.0, 1.0, 14.0, 208u32)
        if soft_error != ok { ret (zero, soft_error) }
        layers[n] = soft
        n += 1usize
    }
    ret (widget.stack(0u64, sized(325.0, 22.0), layers[0usize..n]), ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [16]str{ "Mask edit, focused (Options Passwords, New Password)", "Mask edit, focused (Options Passwords, Old Password)", "Spin edit with fast buttons, focused (Options Decks)", "Spin edit, up arrow pressed (Options Decks)", "Spin edit, down arrow pressed (Options Decks)", "Spin edit, left button pressed (Options Decks)", "Spin edit, right button pressed (Options Decks)", "Spin edit, focused (Options Morph)", "Spin edit, up arrow pressed (Options Morph)", "Spin edit, down arrow pressed (Options Morph)", "Button edit, focused (Options Decks)", "Button edit, text selected (Options Decks)", "Button edit, ellipsis pressed (Options Decks)", "Button edit, disabled (Options Card Art)", "Hot key edit (Options Shortcuts), rest", "Hot key edit (Options Shortcuts), focused" }
    let drives = [16]looks.Drive{ .Focus, .Focus, .Focus, .Focus, .Focus, .Focus, .Focus, .Caret2, .Focus, .Focus, .Caret33, .Select, .SelectPress, .None, .None, .None }
    let ys = [16]f32{ 144.0, 89.0, 159.0, 159.0, 159.0, 159.0, 159.0, 105.0, 105.0, 105.0, 94.0, 94.0, 94.0, 385.0, 414.0, 414.0 }
    let xs = [16]f32{ 8.0, 8.0, 440.0, 440.0, 440.0, 440.0, 440.0, 480.0, 460.0, 460.0, 311.0, 311.0, 9.0, 8.0, 8.0, 8.0 }
    let numbers = [16]i64{ 0i64, 0i64, 4i64, 5i64, 4i64, 1i64, 11i64, 650i64, 650i64, 650i64, 0i64, 0i64, 0i64, 0i64, 0i64, 0i64 }
    var i = 0usize
    while i < 16usize {
        let (buffer, buffer_error) = mem.alloc[u8](a, 128usize)
        if buffer_error != ok { ret (0usize, buffer_error) }
        let key = u64(10usize * (i + 1usize))
        var node: widget.Node = zero
        if i == 0usize || i == 1usize {
            var options = control.field_options()
            options.width = 495.0
            options.window_y = ys[i]
            let (made, made_error) = control.password_field(a, key, t, "Password", buffer, 0usize, widget.Change[str] { ctx: zero, invoke: noop_change }, widget.Submit { ctx: zero, invoke: noop_submit }, options)
            if made_error != ok { ret (0usize, made_error) }
            node = made
        }
        if i >= 2usize && i <= 9usize {
            var width: f32 = 121.0
            if i >= 7usize { width = 67.0 }
            let (made, made_error) = control.windows_spin_with(a, key, t, "Spin", buffer, numbers[i], 0i64, 3000i64, 1i64, widget.Change[i64] { ctx: zero, invoke: noop_step }, widget.Change[str] { ctx: zero, invoke: noop_change }, width, i <= 6usize, ys[i])
            if made_error != ok { ret (0usize, made_error) }
            node = made
        }
        if i >= 10usize && i <= 13usize {
            var words = "C:\\Users\\gaddl\\AppData\\Roaming\\MTG Studio\\My Decks"
            var width: f32 = 495.0
            if i == 13usize {
                words = "MTG Studio Download (all editions + promos)"
                width = 464.0
            }
            let n = copy_into(buffer, words)
            var options = control.field_options()
            options.width = width
            options.window_y = ys[i]
            options.enabled = i != 13usize
            let action = widget.Submit { ctx: zero, invoke: noop_submit }
            let actions = [1]widget.Submit{ action }
            let (made, made_error) = control.button_edit(a, key, t, "Path", buffer, n, widget.Change[str] { ctx: zero, invoke: noop_change }, action, &actions[0usize], "Browse", options)
            if made_error != ok { ret (0usize, made_error) }
            node = made
        }
        if i >= 14usize {
            let (made, made_error) = hot_key(a, t, i == 15usize, if_else_text(i == 15usize))
            if made_error != ok { ret (0usize, made_error) }
            node = made
        }
        let (at, at_error) = placed(a, node, xs[i])
        if at_error != ok { ret (0usize, at_error) }
        cells[i] = looks.Cell { caption: captions[i], node: at, drive: drives[i] }
        i += 1usize
    }
    ret (16usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "edits_states", cells: 16usize, columns: 1usize, cell_w: 990.0, cell_h: 30.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}

// The capture's shortcut: the focused grab shows Ctrl + O, the rest grab Ctrl + N.
fn if_else_text(focused: bool) -> str {
    if focused { ret "Ctrl + O" }
    ret "Ctrl + N"
}
