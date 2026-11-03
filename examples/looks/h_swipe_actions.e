// The collection swipe actions (collection.swipe_actions): a row whose end actions are revealed by a swipe or a More button.
// Sheet "swipe_actions": rest, revealed (Archive, Delete), hover, keyboard focus.
// Derived: the row, More button and action tiles come from the shared tokens of each look; the mid-swipe drag is not drawn
// and no reference capture exists.

use e.mem
use e.ui.collection
use e.ui.control
use e.ui.looks
use e.ui.looks_h as h
use e.ui.looks_z87
use e.ui.widget

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [4]str{ "rest", "revealed", "hover", "focus" }
    var i = 0usize
    while i < 4usize {
        let (content, content_error) = h.word(a, t, "Message from Ada")
        if content_error != ok { ret (0usize, content_error) }
        let labels = [2]str{ "Archive", "Delete" }
        let actions = [2]widget.Submit{ widget.Submit { ctx: zero, invoke: h.noop_submit }, widget.Submit { ctx: zero, invoke: h.noop_submit } }
        let (node, node_error) = collection.swipe_actions(a, u64((i + 1usize) * 100usize), t, content, labels[0usize..2usize], actions[0usize..2usize], i == 1usize, widget.Change[bool] { ctx: zero, invoke: h.noop_bool }, 300.0, 48.0)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 2usize { drive = .Hover }
        // Android: the hover cell points at the More button at the row's end
        if i == 2usize { looks_z87.aim(t, i, 118.0, 15.0) }
        if i == 3usize { drive = .Focus }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    ret (4usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "swipe_actions", cells: 4usize, columns: 2usize, cell_w: 320.0, cell_h: 90.0, ctx: zero, build: build }
    ret h.run_ten(a, &sheet)
}
