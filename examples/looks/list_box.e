// The list box (TcxListBox) in every state under every look: docs/ui/looks/<look>/list_box.png.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn pick_actions(a: *mem.Arena, n: usize) -> ([]widget.Submit, err) {
    let (picks, picks_error) = mem.alloc[widget.Submit](a, n)
    if picks_error != ok { ret (zero, picks_error) }
    var i = 0usize
    while i < n {
        picks[i] = widget.Submit { ctx: zero, invoke: noop_submit }
        i += 1usize
    }
    ret (picks, ok)
}

fn one(a: *mem.Arena, t: *const control.Theme, key: widget.Key, items: []const str, selected: usize, rows: u32) -> (widget.Node, err) {
    let (picks, picks_error) = pick_actions(a, items.len)
    if picks_error != ok { ret (zero, picks_error) }
    let (made, made_error) = control.list_box(a, key, t, "Format", items, selected, picks, rows, 130.0)
    ret (made, made_error)
}

// Eight cells: a short list with one row chosen, the pointer over a row, keyboard focus, a list
// past its rows (the viewport scrolls), the last row chosen, no rows, long rows, no choice.
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [8]str{ "Normal", "Hover", "Focus", "Scrolling", "Last row chosen", "Empty", "Long rows", "No choice" }
    let formats = [6]str{ "Standard", "Modern", "Pioneer", "Commander", "Vintage", "Legacy" }
    let many = [14]str{ "Alchemy", "Brawl", "Commander", "Explorer", "Freeform", "Historic", "Legacy", "Modern", "Momir", "Pauper", "Pioneer", "Standard", "Timeless", "Vintage" }
    let long = [4]str{ "Two-Headed Giant Constructed", "Commander 1v1", "Tribal Wars with a name too long to fit", "Singleton" }
    let none: []const str = zero
    var i = 0usize
    while i < 8usize {
        var items: []const str = formats[0usize..6usize]
        var selected = 1usize
        var rows = 6u32
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 2usize { drive = .Focus }
        if i == 3usize {
            items = many[0usize..14usize]
            selected = 3usize
        }
        if i == 4usize { selected = 5usize }
        if i == 5usize { items = none }
        if i == 6usize {
            items = long[0usize..4usize]
            selected = 2usize
        }
        if i == 7usize { selected = 99usize }
        let (node, node_error) = one(a, t, u64(i + 1usize) * 100u64, items, selected, rows)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (8usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "list_box", cells: 8usize, columns: 4usize, cell_w: 150.0, cell_h: 124.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
