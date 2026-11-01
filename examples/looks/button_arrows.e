// The two arrow buttons of the Options Card Art page (TcxButton 25 x 28, picture only, v3's blue and gray arrow bitmaps):
// the disabled up and enabled down arrow of ref/windows/states/dialog-options-cardart-rest and the enabled up and disabled
// down arrow of button-image-pressed-options-cardart-move-up (the grab's "pressed" button was pressed and has already handled
// the click, so every arrow shows its rest look). The box is cropped with 5 px of its dialog around it (see button_states.e);
// the arrow bitmaps are v3 artwork, drawn here as a placeholder glyph and masked out of the comparison.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.gfx.paint
use e.mem
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let captions = [4]str{ "up, disabled", "down, enabled", "up, enabled", "down, disabled" }
    let enabled = [4]bool{ false, true, true, false }
    let ys = [4]f32{ 89.0, 123.0, 89.0, 123.0 }
    var i = 0usize
    while i < 4usize {
        // the Options form's DPI phase (examples/looks/dialog.e): the button at client (685, y)
        var options = control.button_options()
        options.width = 25.0
        options.height = 28.0
        options.enabled = enabled[i]
        options.shift_x = 0.03 + 685.0 * 0.000714
        options.shift_y = 0.03 + ys[i] * 0.000990
        options.ring_x = 0.0 - 0.005 + 685.0 * 0.000738
        options.ring_y = 0.0 - 0.0243 + ys[i] * 0.000742
        let (node, node_error) = control.button_with_glyph(a, u64(i + 1usize), t, .Refresh, "", &actions[0usize], options)
        if node_error != ok { ret (0usize, node_error) }
        var holder = control.sized_style(33.0, 38.0)
        if t.tokens.profile == .Windows { holder.background = paint.Brush { Solid: style.hex(0xF0F0F0u32) } }
        let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
        if inner_error != ok { ret (0usize, inner_error) }
        inner[0usize] = widget.positioned(0u64, 5.0, 5.0, style.defaults(), control.mem_one_node(a, node))
        cells[i] = looks.Cell { caption: captions[i], node: widget.stack(0u64, holder, inner[0usize..1usize]), drive: .None }
        i += 1usize
    }
    ret (4usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "button_arrows", cells: 4usize, columns: 4usize, cell_w: 45.0, cell_h: 50.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
