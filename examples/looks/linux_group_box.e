// The Linux look's group boxes against GTK 4.14 / libadwaita 1.5: a `.card` (200 x 80, its label 24 px from the top) and a
// GtkFrame titled Group (a 200 x 60 child): docs/ui/looks/linux[-dark]/group_box.png, with group_box-vs-ref.png beside it
// (reference on the left, built by scripts/linux_cmp_l1.py). Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget
use e.ui.style

fn content(a: *mem.Arena, t: *const control.Theme, width: f32, height: f32, top: f32) -> (widget.Node, err) {
    var options = control.text_options()
    options.wrap = .None
    let (word, word_error) = control.linux_label(a, 0u64, t, "Content", 0u32)
    if word_error != ok { ret (zero, word_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 1usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = widget.padded(0u64, 0.0, top, 0.0, 0.0, style.defaults(), mem_one(a, word))
    ret (widget.aligned(0u64, .Center, .Start, control.sized_style(width, height), parts[0usize..1usize]), ok)
}

fn mem_one(a: *mem.Arena, node: widget.Node) -> []const widget.Node {
    let (made, made_error) = mem.alloc[widget.Node](a, 1usize)
    if made_error != ok { ret zero }
    made[0usize] = node
    ret made[0usize..1usize]
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    var options = control.group_options()
    options.variant = .Filled
    options.width = 200.0
    let (card_child, card_child_error) = content(a, t, 200.0, 80.0, 24.0)
    if card_child_error != ok { ret (0usize, card_child_error) }
    let (card, card_error) = control.group_box_of(a, 1u64, t, "", options, mem_one(a, card_child))
    if card_error != ok { ret (0usize, card_error) }
    // The 80 high card and the 89 high frame share a cell 101 high: the card stands in an 81 high holder, so
    // both land on whole pixels like the reference crops.
    let box = widget.aligned(0u64, .Start, .Start, control.sized_style(200.0, 80.0), mem_one(a, card))
    let held = widget.aligned(0u64, .Start, .Start, control.sized_style(200.0, 81.0), mem_one(a, box))
    cells[0usize] = looks.Cell { caption: "card", node: held, drive: .None }
    var framed = control.group_options()
    framed.width = 202.0
    let (frame_child, frame_child_error) = content(a, t, 200.0, 60.0, 19.5)
    if frame_child_error != ok { ret (0usize, frame_child_error) }
    let (frame, frame_error) = control.group_box_of(a, 2u64, t, "Group", framed, mem_one(a, frame_child))
    if frame_error != ok { ret (0usize, frame_error) }
    cells[1usize] = looks.Cell { caption: "frame", node: frame, drive: .None }
    ret (2usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "group_box", cells: 2usize, columns: 2usize, cell_w: 220.0, cell_h: 101.0, ctx: zero, build: build }
    ret looks.run_linux(a, &sheet)
}
