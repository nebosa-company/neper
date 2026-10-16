// The Cupertino (macOS) help tag: docs/ui/looks/cupertino/hint.png (and cupertino-dark). Four anchors with their tag shown:
// one line, wrapped, with a shortcut, and a short one. (The harness runtime holds 16384 paint commands, so five overlays
// at most: see hint.e.)

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.overlay
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn anchored(a: *mem.Arena, t: *const control.Theme, action: *const widget.Submit, i: usize, text: str, shortcut: str) -> (widget.Node, err) {
    let anchor_key = u64(100usize + i)
    var options = control.button_options()
    options.variant = .Outlined
    let (button, button_error) = control.button(a, anchor_key, t, "Anchor", action, options)
    if button_error != ok { ret (zero, button_error) }
    let (tip, tip_error) = overlay.tooltip_of(a, u64(5000usize + i * 100usize), t, anchor_key, text, shortcut, true)
    if tip_error != ok { ret (zero, tip_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = button
    parts[1usize] = tip
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..2usize]), ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let captions = [4]str{ "Plain", "Wrapped", "With shortcut", "Short" }
    let texts = [4]str{ "Save the deck", "Cards that share a name are counted once,\nwhatever their edition or condition", "Save", "Edition" }
    var i = 0usize
    while i < 4usize {
        var shortcut = ""
        if i == 2usize { shortcut = "Ctrl+S" }
        let (node, node_error) = anchored(a, t, &actions[0usize], i, texts[i], shortcut)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: .None }
        i += 1usize
    }
    ret (4usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "hint", cells: 4usize, columns: 2usize, cell_w: 260.0, cell_h: 90.0, ctx: zero, build: build }
    ret looks.run_cupertino(a, &sheet)
}
