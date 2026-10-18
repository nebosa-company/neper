// The Linux look's check button against the real GTK 4.14 / libadwaita 1.5 one: off, on and mixed in five states (rest, hover,
// pressed, keyboard focus, disabled), docs/ui/looks/linux[-dark]/checkbox.png, with checkbox-vs-ref.png beside it
// (reference on the left, built by scripts/linux_cmp_l1.py). Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.str as strs
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let rows = [3]str{ "off", "on", "mixed" }
    let states = [5]str{ "rest", "hover", "pressed", "focus", "disabled" }
    var i = 0usize
    while i < 15usize {
        let row = i / 5usize
        let state = i % 5usize
        let (node, node_error) = control.checkbox(a, u64(i + 1usize), t, "Check", row == 1usize, row == 2usize, &actions[0usize], state != 4usize)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if state == 1usize { drive = .Hover }
        if state == 2usize { drive = .Press }
        if state == 3usize { drive = .Focus }
        let parts = [2]str{ rows[row], states[state] }
        let (caption, caption_error) = strs.join(a, parts[0usize..2usize], " ")
        if caption_error != ok { ret (0usize, caption_error) }
        cells[i] = looks.Cell { caption: caption, node: node, drive: drive }
        i += 1usize
    }
    ret (15usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "checkbox", cells: 15usize, columns: 5usize, cell_w: 101.0, cell_h: 44.0, ctx: zero, build: build }
    ret looks.run_linux(a, &sheet)
}
