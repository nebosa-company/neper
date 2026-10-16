// The Android look's search bar: a 56 dp surface-container-high pill, the search icon at the start, the query body-large over
// its placeholder and a trailing clear cross, enabled, hovered, focused with text, with text, disabled
// (docs/ui/looks/material/search_bar.png). Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_change(ctx: *void, value: str) -> err { ret ok }
fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [6]str{ "Enabled", "Hovered", "Focused", "Focused, text", "With text", "Disabled" }
    let (clears, clears_error) = mem.alloc[widget.Submit](a, 1usize)
    if clears_error != ok { ret (0usize, clears_error) }
    clears[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    var i = 0usize
    while i < 6usize {
        let (buffer, buffer_error) = mem.alloc[u8](a, 64usize)
        if buffer_error != ok { ret (0usize, buffer_error) }
        let words = "Lightning Bolt"
        var n = 0usize
        if i == 3usize || i == 4usize {
            while n < words.len {
                buffer[n] = words[n]
                n += 1usize
            }
        }
        var options = control.field_options()
        options.width = 320.0
        options.placeholder = "Search cards"
        if i == 5usize { options.enabled = false }
        let (node, node_error) = control.search_field(a, u64(10usize * (i + 1usize)), t, buffer, n, widget.Change[str] { ctx: zero, invoke: noop_change }, widget.Submit { ctx: zero, invoke: noop_submit }, &clears[0usize], options)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 2usize || i == 3usize { drive = .Focus }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (6usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "search_bar", cells: 6usize, columns: 3usize, cell_w: 340.0, cell_h: 70.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
