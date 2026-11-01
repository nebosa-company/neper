// Round 62 c: the key caps (a shortcut chord drawn as keys) in all ten looks: single keys, chords of two and three, the
// compact form. Derived: the cap shape comes from the shared tokens, no platform capture. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [8]str{ "Single key", "Chord of two", "Chord of three", "Function key", "Named key", "Compact single", "Compact chord", "Arrow keys" }
    let chords = [8]str{ "Esc", "Ctrl+S", "Ctrl+Shift+P", "F5", "Alt+Enter", "K", "Ctrl+K", "Shift+Up" }
    var i = 0usize
    while i < 8usize {
        var node: widget.Node = zero
        var node_error = ok
        if i == 5usize || i == 6usize {
            let (made, made_error) = control.compact_key_caps(a, t, chords[i])
            node = made
            node_error = made_error
        } else {
            let (made, made_error) = control.key_caps(a, t, chords[i])
            node = made
            node_error = made_error
        }
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: .None }
        i += 1usize
    }
    ret (8usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "key_caps", cells: 8usize, columns: 4usize, cell_w: 190.0, cell_h: 56.0, ctx: zero, build: build }
    try looks.run_all(a, &sheet)
    try looks.run_material(a, &sheet)
    try looks.run_cupertino(a, &sheet)
    ret looks.run_linux(a, &sheet)
}
