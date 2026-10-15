// The default shift of the button, docs/ui/looks/<look>/button_shift.png (its own app: the harness opens at most
// sixteen rigs per process, and the button sheets use twelve).
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn one(a: *mem.Arena, t: *const control.Theme, action: *const widget.Submit, key: widget.Key, caption: str, variant: style.ControlVariant) -> (widget.Node, err) {
    var options = control.button_options()
    options.variant = variant
    let (node, node_error) = control.button(a, key, t, caption, action, options)
    ret (node, node_error)
}

// The default shift: v3's default button (accent ring) lets go of it while another button of the dialog holds the
// focus or is pressed (states/button-pressed-search-cancel: OK is a plain ring then). Two cells, each a row of
// OK (default) and Cancel as Search for Card lays them out (9 px gap), the pointer on Cancel.
fn build_shift(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let captions = [3]str{ "Rest", "Cancel pressed", "Cancel focused" }
    var i = 0usize
    while i < 3usize {
        let (ok_node, ok_error) = one(a, t, &actions[0usize], u64(i * 10usize + 1usize), "OK", .Default)
        if ok_error != ok { ret (0usize, ok_error) }
        let (cancel_node, cancel_error) = one(a, t, &actions[0usize], u64(i * 10usize + 2usize), "Cancel", .Filled)
        if cancel_error != ok { ret (0usize, cancel_error) }
        let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
        if parts_error != ok { ret (0usize, parts_error) }
        parts[0usize] = ok_node
        parts[1usize] = widget.box(0u64, control.sized_style(11.0, 1.0), zero)
        parts[2usize] = cancel_node
        var holder = style.defaults()
        // the cell centre is the middle of Cancel: the row is 73 + 11 + 73 wide (the visible boxes) and padded on the right by 84
        holder.width = style.Length { Px: 241.0 }
        holder.height = style.Length { Px: 22.0 }
        let row = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, holder, parts[0usize..3usize])
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Press }
        if i == 2usize { drive = .Focus }
        cells[i] = looks.Cell { caption: captions[i], node: row, drive: drive }
        i += 1usize
    }
    ret (3usize, ok)
}


fn main(a: *mem.Arena, args: []str) -> err {
    let shift = looks.Sheet { name: "button_shift", cells: 3usize, columns: 3usize, cell_w: 253.0, cell_h: 40.0, ctx: zero, build: build_shift }
    ret looks.run_all(a, &shift)
}
