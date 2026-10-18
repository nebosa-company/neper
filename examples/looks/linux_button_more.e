// The Linux look's pill button (a captioned circular button, five states) and linked buttons (One, Two, Three) against GTK 4.14 /
// libadwaita 1.5: docs/ui/looks/linux[-dark]/button_more.png, with button_more-vs-ref.png beside it (reference on the left, built
// by scripts/linux_cmp_l1.py). The plain kinds are in button.png (linux_button.e). Run from the repository root; see
// docs/ui/looks-howto.md.

use e.mem
use e.str as strs
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 3usize)
    if actions_error != ok { ret (0usize, actions_error) }
    var k = 0usize
    while k < 3usize {
        actions[k] = widget.Submit { ctx: zero, invoke: noop_submit }
        k += 1usize
    }
    let states = [5]str{ "rest", "hover", "pressed", "focus", "disabled" }
    var i = 0usize
    while i < 5usize {
        var options = control.button_options()
        options.variant = .Tonal
        options.circular = true
        options.height = 44.0
        options.enabled = i != 4usize
        let (node, node_error) = control.button(a, u64(i + 1usize), t, "Button", &actions[0usize], options)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 2usize { drive = .Press }
        if i == 3usize { drive = .Focus }
        let parts = [2]str{ "pill", states[i] }
        let (caption, caption_error) = strs.join(a, parts[0usize..2usize], " ")
        if caption_error != ok { ret (0usize, caption_error) }
        cells[i] = looks.Cell { caption: caption, node: node, drive: drive }
        i += 1usize
    }
    let labels = [3]str{ "One", "Two", "Three" }
    let (linked, linked_error) = control.linux_linked_buttons(a, 100u64, t, labels[0usize..3usize], actions[0usize..3usize], true)
    if linked_error != ok { ret (0usize, linked_error) }
    cells[5usize] = looks.Cell { caption: "linked", node: linked, drive: .None }
    ret (6usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "button_more", cells: 6usize, columns: 3usize, cell_w: 212.0, cell_h: 54.0, ctx: zero, build: build }
    ret looks.run_linux(a, &sheet)
}
