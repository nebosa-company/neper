// navigation.document_tabs under all ten looks: docs/ui/looks/<look>/document_tabs.png. Three tabs with the first or the
// second current, a tab with unsaved changes, a pinned tab, and the hovered, pressed and keyboard-focused states.
// Derived: every look draws the tab strip from the shared tokens (no platform reference is captured for it).
// Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_f
use e.ui.navigation
use e.ui.widget

fn no_pick(ctx: *void, value: usize) -> err { ret ok }
fn no_move(ctx: *void, value: navigation.DocumentMove) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [8]str{ "First current", "Second current", "Unsaved changes", "Pinned tab", "Hover", "Pressed", "Keyboard focus", "One tab" }
    let (docs, docs_error) = mem.alloc[navigation.Document](a, 3usize)
    if docs_error != ok { ret (0usize, docs_error) }
    var i = 0usize
    while i < 8usize {
        docs[0usize] = navigation.Document { key: 101u64, title: "main.e", dirty: false, pinned: false }
        docs[1usize] = navigation.Document { key: 102u64, title: "layout.e", dirty: i == 2usize, pinned: false }
        docs[2usize] = navigation.Document { key: 103u64, title: "notes.md", dirty: false, pinned: i == 3usize }
        var current = 0usize
        if i == 1usize || i == 2usize { current = 1usize }
        if i == 3usize { current = 0usize }
        var count = 3usize
        if i == 7usize { count = 1usize }
        let (node, node_error) = navigation.document_tabs(a, u64((i + 1usize) * 1000usize), t, "Documents", docs[0usize..count], current, widget.Change[usize] { ctx: zero, invoke: no_pick }, widget.Change[usize] { ctx: zero, invoke: no_pick }, widget.Change[navigation.DocumentMove] { ctx: zero, invoke: no_move })
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 4usize || i == 5usize { drive = .Hover }
        if i == 5usize { drive = .Press }
        if i == 6usize { drive = .Focus }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (8usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "document_tabs", cells: 8usize, columns: 2usize, cell_w: 400.0, cell_h: 60.0, ctx: zero, build: build }
    ret looks_f.run_ten(a, &sheet)
}
