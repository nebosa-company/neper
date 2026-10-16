// The empty token edits of the v3 Filter dialog's Cards tab (docs/ui/looks/ref/windows/states/tab-selected-filter-cards):
// three TdxTokenEdit boxes 315 wide and 46, 46 and 27 high, drawn like a plain edit (rim, foot). Each stands at the y it
// has in the dialog (`window_y`). scripts/looks_edits_more.py token_edit_dialog diffs the sheet against the capture.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.gfx.paint
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_change(ctx: *void, value: str) -> err { ret ok }
fn noop_submit(ctx: *void) -> err { ret ok }
fn noop_active(ctx: *void, value: usize) -> err { ret ok }

fn sized(w: f32, h: f32) -> style.Style {
    var s = style.defaults()
    s.width = style.Length { Px: w }
    s.height = style.Length { Px: h }
    ret s
}

// `node` at (8, 4) of a 340 x 54 box. Under the Windows look the edit stands on the #F9F9F9 face of the Search for Text group
// box, as in the capture: the reference crop is the edit plus 2 px of that face on every side (319 x (h + 5)).
fn placed(a: *mem.Arena, t: *const control.Theme, node: widget.Node, h: f32) -> (widget.Node, err) {
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, inner_error) }
    inner[0usize] = node
    let (face, face_error) = mem.alloc[widget.Node](a, 1usize)
    if face_error != ok { ret (zero, face_error) }
    var face_style = sized(319.0, h + 5.0)
    if t.tokens.profile == .Windows { face_style.background = paint.Brush { Solid: style.hex(16382457u32) } }
    if t.tokens.profile == .Windows && t.tokens.palette == .Dark { face_style.background = paint.Brush { Solid: style.hex(0x272727u32) } }
    face[0usize] = widget.box(0u64, face_style, zero)
    let (layer, layer_error) = mem.alloc[widget.Node](a, 2usize)
    if layer_error != ok { ret (zero, layer_error) }
    layer[0usize] = widget.positioned(0u64, 6.0, 2.0, style.defaults(), face[0usize..1usize])
    layer[1usize] = widget.positioned(0u64, 8.0, 4.0, style.defaults(), inner[0usize..1usize])
    ret (widget.stack(0u64, sized(340.0, 54.0), layer[0usize..2usize]), ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [3]str{ "Token edit, empty, 315 x 46 (Filter Cards, first)", "Token edit, empty, 315 x 46 (Filter Cards, second)", "Token edit, empty, 315 x 27 (Filter Cards, third)" }
    let heights = [3]f32{ 46.0, 46.0, 27.0 }
    let ys = [3]f32{ 86.0, 137.0, 188.0 }
    var i = 0usize
    while i < 3usize {
        let (buffer, buffer_error) = mem.alloc[u8](a, 32usize)
        if buffer_error != ok { ret (0usize, buffer_error) }
        let none_words = [1]str{ "" }
        let picks = [1]widget.Submit{ widget.Submit { ctx: zero, invoke: noop_submit } }
        let none_tokens = [1]str{ "" }
        let none_removes = [1]widget.Submit{ widget.Submit { ctx: zero, invoke: noop_submit } }
        let dismiss = widget.Submit { ctx: zero, invoke: noop_submit }
        let key = u64(100usize * (i + 1usize))
        let (edit, edit_error) = control.token_field_sized(a, key, t, "", none_tokens[0usize..0usize], none_removes[0usize..0usize], buffer, 0usize, widget.Change[str] { ctx: zero, invoke: noop_change }, widget.Submit { ctx: zero, invoke: noop_submit }, none_words[0usize..0usize], 0usize, false, picks[0usize..0usize], widget.Change[usize] { ctx: zero, invoke: noop_active }, &dismiss, 315.0, heights[i], ys[i])
        if edit_error != ok { ret (0usize, edit_error) }
        let (at, at_error) = placed(a, t, edit, heights[i])
        if at_error != ok { ret (0usize, at_error) }
        cells[i] = looks.Cell { caption: captions[i], node: at, drive: .None }
        i += 1usize
    }
    ret (3usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "token_edit_dialog", cells: 3usize, columns: 1usize, cell_w: 340.0, cell_h: 54.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
