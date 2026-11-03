// The terminal scrollback list (e.ui.terminal_view.list), docs/ui/looks/<look>/terminal_view.png in all ten looks. The lines of
// an e.ui.terminal buffer as a virtual list of monospace rows: at the newest line, scrolled to the oldest, a selection of three
// lines, hover, keyboard focus and an empty buffer. The viewer draws plain line text (colours and the cursor are not in the
// list, only the text of each line), on the list's own surface and row look from the shared tokens. Derived; no platform
// terminal was compared.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_x63
use e.ui.looks_z85
use e.ui.terminal as tm
use e.ui.terminal_view as tv
use e.ui.widget

// One buffer per cell: a row's key is its line number, so cells sharing a buffer would share keys and the pointer would light the first.
type Terms = struct { cell: [6]tm.Term }

fn feed_text(t: *tm.Term, s: str) {
    tm.feed(t, s)
    tm.feed(t, "\r\n")
}


fn nothing(ctx: *void, value: f32) -> err { ret ok }

fn pick(s: *Terms, i: usize) -> *tm.Term {
    ret &s.cell[i]
}

fn extent() -> f32 { ret 18.0 }
fn height() -> f32 { ret 108.0 }
fn width() -> f32 { ret 340.0 }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [6]str{ "newest line", "scrolled to the oldest", "three lines selected", "hover", "focus", "empty" }
    let change = widget.Change[f32] { ctx: nil, invoke: nothing }
    let (mono, mono_error) = looks_x63.mono_theme(a, t)
    if mono_error != ok { ret (0usize, mono_error) }
    var i = 0usize
    while i < 6usize {
        let (views, views_error) = mem.alloc[tv.Viewport](a, 1usize)
        if views_error != ok { ret (0usize, views_error) }
        views[0usize] = tv.viewport(pick(mem.cast[*Terms](ctx), i), mono)
        let v = &views[0usize]
        var offset = tv.bottom_offset(v, extent(), height())
        if i == 1usize { offset = 0.0 }
        var picked: [8]widget.Key = zero
        var marked = 0usize
        if i == 2usize {
            let first = tv.line_total(v) - 6usize
            var sel = tm.selection_start(tm.SEL_CHAR, tv.buffer_line(v, first + 1usize), 0usize)
            tm.selection_extend(&sel, tv.buffer_line(v, first + 3usize), 9usize)
            marked = tv.selected_keys(v, &sel, first, 6usize, picked[0..])
        }
        let (node, node_error) = tv.list(a, u64(i + 1usize) * 10000000u64, v, "Terminal output", picked[0usize..marked], extent(), offset, change, width(), height())
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 3usize { drive = .Hover }
        if i == 4usize { drive = .Focus }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        if i == 3usize { looks.aim(i, 0.0, 18.0) }
        i += 1usize
    }
    ret (6usize, ok)
}

fn fill(full: *tm.Term) {
    feed_text(full, "$ neper build examples/looks/button.e")
    feed_text(full, "checking e.ui.control ... ok")
    feed_text(full, "checking e.ui.looks ... ok")
    feed_text(full, "compiling 214 files")
    feed_text(full, "warning: unused variable `scale`")
    feed_text(full, "  --> lib/e/ui/looks.e:412")
    feed_text(full, "linking build/windows/button.exe")
    feed_text(full, "executable written")
    feed_text(full, "$ build/windows/button.exe")
    feed_text(full, "rendering 10 looks at 1.0 and 1.5")
    feed_text(full, "wrote docs/ui/looks/neper/button.png")
    feed_text(full, "wrote docs/ui/looks/windows/button.png")
    feed_text(full, "wrote docs/ui/looks/linux/button.png")
    feed_text(full, "done in 17.6 s")
    tm.feed(full, "$ ")
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (terms, terms_error) = mem.alloc[Terms](a, 1usize)
    if terms_error != ok { ret terms_error }
    var i = 0usize
    while i < 6usize {
        let (made, made_error) = tm.new(a, 48usize, 6usize, 48usize, 6usize, 100usize)
        if made_error != ok { ret made_error }
        terms[0usize].cell[i] = made
        if i != 5usize { fill(&terms[0usize].cell[i]) }
        terms[0usize].cell[i].sb_dropped = i * 1000usize
        i += 1usize
    }
    looks_z85.rows_hover(true)
    let sheet = looks.Sheet { name: "terminal_view", cells: 6usize, columns: 2usize, cell_w: 360.0, cell_h: 128.0, ctx: mem.cast[*void](&terms[0usize]), build: build }
    try looks.run_all(a, &sheet)
    try looks.run_linux(a, &sheet)
    try looks.run_cupertino(a, &sheet)
    ret looks.run_material(a, &sheet)
}
