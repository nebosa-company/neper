// The whole native Windows 11 dark dialog (docs/ui/looks/ref/windows-native/dark/dialog-active, dialog-inactive; 296 x 129):
// the caption (full width), the 1 px #6A6A6A line under it and the #202020 client inside the invisible 8 px resize border
// (black in a PrintWindow capture), "Plain dialog window." at (28, 45) and the default OK button, 80 x 28 at (198, 81).
// Run from the repository root; see docs/ui/looks-howto.md.

use e.gfx.paint
use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.navigation
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn at(a: *mem.Arena, x: f32, y: f32, node: widget.Node) -> widget.Node {
    ret widget.positioned(0u64, x, y, style.defaults(), control.mem_one_node(a, node))
}

fn solid(a: *mem.Arena, x: f32, y: f32, w: f32, h: f32, value: u32) -> widget.Node {
    var s = control.sized_style(w, h)
    s.background = paint.Brush { Solid: style.hex_raw(value) }
    ret at(a, x, y, widget.box(0u64, s, zero))
}

fn dialog(a: *mem.Arena, t: *const control.Theme, key: widget.Key, active: bool, actions: *const widget.Submit) -> (widget.Node, err) {
    var options = navigation.title_bar_options(.Windows)
    options.active = active
    options.minimizable = false
    options.maximizable = false
    options.icon = false
    options.light = t.tokens.palette != .Dark
    let (bar, bar_error) = navigation.title_bar(a, key, t, "Dialog", options, 296.0)
    if bar_error != ok { ret (zero, bar_error) }
    var face_ink = 0x202020u32
    var line = 0x6A6A6Au32
    var ink = style.hex_raw(0xFFFFFFu32)
    if t.tokens.palette != .Dark {
        face_ink = 0xF0F0F0u32
        line = 0xE5E5E5u32
        ink = style.hex_raw(0x000000u32)
    }
    let (label, label_error) = control.windows_label_faced(a, t, "Plain dialog window.", 12.0, 400u32, ink, false, 0.0, 7u32, 0.0, 0.0, false)
    if label_error != ok { ret (zero, label_error) }
    var bo = control.button_options()
    bo.variant = .Default
    bo.shift_y = 0.5
    bo.width = 79.0
    bo.height = 27.0
    let (ok_button, ok_error) = control.button(a, key + 10u64, t, "OK", actions, bo)
    if ok_error != ok { ret (zero, ok_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 6usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = solid(a, 0.0, 0.0, 296.0, 129.0, 0x000000u32)
    parts[1usize] = solid(a, 8.0, 31.0, 280.0, 90.0, face_ink)
    parts[2usize] = solid(a, 8.0, 31.0, 280.0, 1.0, line)
    parts[3usize] = at(a, 0.0, 0.0, bar)
    parts[4usize] = at(a, 28.0, 45.0, label)
    parts[5usize] = at(a, 199.0, 82.0, ok_button)
    ret (widget.stack(0u64, control.sized_style(296.0, 129.0), parts[0usize..6usize]), ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    var i = 0usize
    while i < 2usize {
        let (node, node_error) = dialog(a, t, u64(i + 1usize) * 100u64, i == 0usize, &actions[0usize])
        if node_error != ok { ret (0usize, node_error) }
        var caption = "dialog-active"
        if i == 1usize { caption = "dialog-inactive" }
        cells[i] = looks.Cell { caption: caption, node: node, drive: .None }
        i += 1usize
    }
    ret (2usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "dialog_native", cells: 2usize, columns: 1usize, cell_w: 300.0, cell_h: 131.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
