// navigation.multi_document_workspace under all ten looks: docs/ui/looks/<look>/workspace.png. The tab strip over the
// current document's view: first or second document current, unsaved and pinned documents, and no document open.
// Derived from the shared tokens; no platform reference is captured. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_f
use e.ui.navigation
use e.ui.widget

fn no_pick(ctx: *void, value: usize) -> err { ret ok }
fn no_move(ctx: *void, value: navigation.DocumentMove) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [5]str{ "First current", "Second current", "Unsaved", "Pinned", "No documents" }
    let (docs, docs_error) = mem.alloc[navigation.Document](a, 3usize)
    if docs_error != ok { ret (0usize, docs_error) }
    var i = 0usize
    while i < 5usize {
        docs[0usize] = navigation.Document { key: 101u64, title: "main.e", dirty: false, pinned: i == 3usize }
        docs[1usize] = navigation.Document { key: 102u64, title: "layout.e", dirty: i == 2usize, pinned: false }
        docs[2usize] = navigation.Document { key: 103u64, title: "notes.md", dirty: false, pinned: false }
        var current = 0usize
        if i == 1usize || i == 2usize { current = 1usize }
        var count = 3usize
        if i == 4usize { count = 0usize }
        let (view, view_error) = control.text(a, 0u64, "Editing the document", t, control.text_options())
        if view_error != ok { ret (0usize, view_error) }
        let (node, node_error) = navigation.multi_document_workspace(a, u64((i + 1usize) * 1000usize), t, "Workspace", docs[0usize..count], current, view, widget.Change[usize] { ctx: zero, invoke: no_pick }, widget.Change[usize] { ctx: zero, invoke: no_pick }, widget.Change[navigation.DocumentMove] { ctx: zero, invoke: no_move }, 380.0, 150.0)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: .None }
        i += 1usize
    }
    ret (5usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "workspace", cells: 5usize, columns: 3usize, cell_w: 400.0, cell_h: 190.0, ctx: zero, build: build }
    ret looks_f.run_ten(a, &sheet)
}
