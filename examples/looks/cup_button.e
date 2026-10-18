// The Cupertino button in every variant and state: docs/ui/looks/cupertino/button.png (and cupertino-dark).
// Run from the repository root; see docs/ui/looks-howto.md. Apple platforms have no live reference here:
// the geometry is the published iOS configuration / macOS bezel metrics (notes in status.d/zzzz-cupertino.json).

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn variant_of(row: usize) -> style.ControlVariant {
    if row == 1usize { ret .Tonal }
    if row == 2usize { ret .Elevated }
    if row == 3usize { ret .Plain }
    if row == 4usize { ret .Outlined }
    if row == 6usize { ret .Default }
    if row == 7usize { ret .Outlined }
    ret .Filled
}

// Rows 0..4: filled, tinted, gray, plain, macOS bordered; each rest, hover, pressed, focus, disabled.
// Row 5: sizes and kinds; rows 6 and 7: the macOS default and bordered push buttons at 22 and 28.
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let action = &actions[0usize]
    let states = [5]str{ "rest", "hover", "pressed", "focus", "disabled" }
    let names = [8]str{ "Filled", "Tinted", "Gray", "Plain", "Bordered", "", "Default", "Bordered" }
    var i = 0usize
    while i < 40usize {
        let row = i / 5usize
        let col = i % 5usize
        var options = control.button_options()
        options.variant = variant_of(row)
        var word = "Continue"
        var caption = names[row]
        var drive: looks.Drive = .None
        if row <= 4usize || row >= 6usize {
            if col == 1usize { drive = .Hover }
            if col == 2usize { drive = .Press }
            if col == 3usize { drive = .Focus }
            if col == 4usize { options.enabled = false }
            caption = states[col]
            if row == 4usize { options.height = 22.0 }
            if row == 6usize { options.height = 22.0 }
            if row == 7usize { options.height = 28.0 }
            if row == 4usize || row == 7usize { word = "Cancel" }
            if row == 6usize { word = "OK" }
        }
        if row == 5usize {
            if col == 0usize {
                options.height = 50.0
                caption = "large 50"
            }
            if col == 1usize {
                options.height = 34.0
                caption = "medium 34"
            }
            if col == 2usize {
                options.height = 28.0
                caption = "small 28"
            }
            if col == 3usize {
                options.variant = .Danger
                caption = "destructive"
                word = "Delete"
            }
            if col == 4usize {
                options.loading = true
                caption = "loading"
            }
        }
        let (node, node_error) = control.button(a, u64(i + 1usize), t, word, action, options)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: caption, node: node, drive: drive }
        i += 1usize
    }
    ret (40usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "button", cells: 40usize, columns: 5usize, cell_w: 124.0, cell_h: 54.0, ctx: zero, build: build }
    ret looks.run_cupertino(a, &sheet)
}
