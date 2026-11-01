// The shortcut recorder (control.shortcut_recorder) in all ten looks: docs/ui/looks/<look>/shortcut_recorder.png.
// Derived: one field on the shared tokens, no platform draws it, and the key caps are the chord text (Ctrl+Shift+S) on every
// look (macOS would show glyphs; not drawn). The control has no disabled state.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.input
use e.ui.looks
use e.ui.looks_b_run
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }
fn noop_chord(ctx: *void, value: control.Chord) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [8]str{ "Empty", "Chord set", "Recording", "Hover", "Focus", "Pressed", "Recording, focus", "Single key" }
    let drives = [8]looks.Drive{ .None, .None, .None, .Hover, .Focus, .Press, .Focus, .None }
    let (starts, starts_error) = mem.alloc[widget.Submit](a, 1usize)
    if starts_error != ok { ret (0usize, starts_error) }
    starts[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    var save: control.Chord = zero
    save.key = 83u32
    save.modifiers.control = true
    save.modifiers.shift = true
    var enter: control.Chord = zero
    enter.key = 13u32
    var i = 0usize
    while i < 8usize {
        var chord: control.Chord = zero
        if i == 1usize || i == 3usize || i == 4usize || i == 5usize { chord = save }
        if i == 7usize { chord = enter }
        let recording = i == 2usize || i == 6usize
        let (node, node_error) = control.shortcut_recorder(a, u64((i + 1usize) * 10usize), t, "Save all", chord, recording, &starts[0usize], widget.Change[control.Chord] { ctx: zero, invoke: noop_chord })
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drives[i] }
        i += 1usize
    }
    ret (8usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "shortcut_recorder", cells: 8usize, columns: 4usize, cell_w: 240.0, cell_h: 64.0, ctx: zero, build: build }
    ret looks_b_run.run_ten(a, &sheet)
}
