// The Linux look's combo boxes against the real GTK 4.14 / libadwaita 1.5 ones (docs/ui/looks/ref/linux, scripts/linux_cmp_l2.py): the
// drop down (a read-only combo box) at rest, hovered, pressed, focused and disabled, the combo box with an entry at rest, focused and
// disabled. docs/ui/looks/linux[-dark]/combo_box.png; the open list is combo_box_open.png. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.looks
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }
fn noop_typed(ctx: *void, value: str) -> err { ret ok }
fn noop_pick(ctx: *void, index: usize) -> err { ret ok }

fn actions(a: *mem.Arena, n: usize) -> ([]widget.Submit, err) {
    let (picks, picks_error) = mem.alloc[widget.Submit](a, n)
    if picks_error != ok { ret (zero, picks_error) }
    var i = 0usize
    while i < n {
        picks[i] = widget.Submit { ctx: zero, invoke: noop_submit }
        i += 1usize
    }
    ret (picks, ok)
}

// One combo box showing `value` among `choices`.
fn one(a: *mem.Arena, t: *const control.Theme, key: widget.Key, value: str, choices: []const str, open: bool, options: control.FieldOptions) -> (widget.Node, err) {
    let (buffer, buffer_error) = mem.alloc[u8](a, 64usize)
    if buffer_error != ok { ret (zero, buffer_error) }
    let n = control.copy_text(buffer, value)
    let (picks, picks_error) = actions(a, choices.len)
    if picks_error != ok { ret (zero, picks_error) }
    let (toggle, toggle_error) = actions(a, 1usize)
    if toggle_error != ok { ret (zero, toggle_error) }
    var active = 0usize
    var i = 0usize
    while i < choices.len {
        if choices[i].len == value.len && choices[i][0usize] == value[0usize] { active = i }
        i += 1usize
    }
    let (node, node_error) = control.combo_box(a, key, t, "Choice", buffer, n, widget.Change[str] { ctx: zero, invoke: noop_typed }, choices, active, open, picks, widget.Change[usize] { ctx: zero, invoke: noop_pick }, &toggle[0usize], options)
    ret (node, node_error)
}

fn one_node(a: *mem.Arena, node: widget.Node) -> []const widget.Node {
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret zero }
    held[0usize] = node
    ret held[0usize..1usize]
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    control.set_native_caret_off(true)
    let names = [8]str{ "drop down", "hover", "pressed", "focus", "disabled", "with entry", "entry focus", "entry disabled" }
    let (list3, list3_error) = mem.alloc[str](a, 3usize)
    if list3_error != ok { ret (0usize, list3_error) }
    list3[0usize] = "First"
    list3[1usize] = "Second"
    list3[2usize] = "Third"
    let (list2, list2_error) = mem.alloc[str](a, 2usize)
    if list2_error != ok { ret (0usize, list2_error) }
    list2[0usize] = "One"
    list2[1usize] = "Two"
    var i = 0usize
    while i < 8usize {
        var options = control.field_options()
        options.width = 160.0
        options.read_only = true
        var value = "First"
        var choices: []const str = list3[0usize..3usize]
        if i >= 5usize {
            options.width = 203.0
            options.read_only = false
            value = "One"
            choices = list2[0usize..2usize]
        }
        if i == 4usize || i == 7usize { options.enabled = false }
        let (node, node_error) = one(a, t, u64(10usize * (i + 1usize)), value, choices, false, options)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 2usize { drive = .Press }
        if i == 3usize || i == 6usize { drive = .Focus }
        // The entry's focus click lands on its text, not on the arrow button at the far end.
        if i == 6usize { looks.aim(i, -60.0, 0.0) }
        // Every control sits at the left of a 203 px box, which the harness centres, so none lands on a half pixel.
        var row = looks.size_style(203.0, 34.0)
        cells[i] = looks.Cell { caption: names[i], node: widget.aligned(0u64, .Start, .Center, row, one_node(a, node)), drive: drive }
        i += 1usize
    }
    ret (8usize, ok)
}

// The open drop down: the button and its list (the chosen item "First" with its check). The list stands under the button, so the cell
// gives it room; the comparer finds the popover by its colour.
fn build_open(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    control.set_native_caret_off(true)
    let (list3, list3_error) = mem.alloc[str](a, 3usize)
    if list3_error != ok { ret (0usize, list3_error) }
    list3[0usize] = "First"
    list3[1usize] = "Second"
    list3[2usize] = "Third"
    var options = control.field_options()
    options.width = 160.0
    options.read_only = true
    let (node, node_error) = one(a, t, 10u64, "First", list3[0usize..3usize], true, options)
    if node_error != ok { ret (0usize, node_error) }
    var room = looks.size_style(300.0, 230.0)
    room.padding = style.EdgeLengths { left: style.Length { Px: 20.0 }, top: style.Length { Px: 20.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    let column = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, room, one_node(a, node))
    cells[0usize] = looks.Cell { caption: "open", node: column, drive: .None }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "combo_box", cells: 8usize, columns: 3usize, cell_w: 213.0, cell_h: 44.0, ctx: zero, build: build }
    try looks.run_linux(a, &sheet)
    let open = looks.Sheet { name: "combo_box_open", cells: 1usize, columns: 1usize, cell_w: 300.0, cell_h: 230.0, ctx: zero, build: build_open }
    ret looks.run_linux(a, &open)
}
