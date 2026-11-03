// The duration picker (overlay.duration_picker) in all ten looks: docs/ui/looks/<look>/duration_picker.png. Derived: hour,
// minute and second steppers on the shared tokens; each look's stepper draws as its own stepper does. No platform has this
// control. Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.time
use e.ui.control
use e.ui.looks
use e.ui.looks_y85
use e.ui.looks_z87
use e.ui.overlay
use e.ui.widget

fn noop_duration(ctx: *void, value: time.Duration) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, base: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    // Cupertino only: glyphs and the keyboard ring take the increased-contrast blue; other looks get their own tokens back.
    let (tokens, tokens_error) = looks_y85.tinted_ring(a, base.tokens, 0x0040DDu32, 0x409CFFu32)
    if tokens_error != ok { ret (0usize, tokens_error) }
    var themed = *base
    themed.tokens = tokens
    let t = &themed
    let names = [5]str{ "1 h 30 min", "Zero", "Long", "Hover", "Focus" }
    let drives = [5]looks.Drive{ .None, .None, .None, .Hover, .Focus }
    var i = 0usize
    while i < 5usize {
        var value = time.Duration { nanos: (3600i64 + 1800i64) * 1000000000i64 }
        if i == 1usize { value = time.Duration { nanos: 0i64 } }
        if i == 2usize { value = time.Duration { nanos: (123i64 * 3600i64 + 45i64 * 60i64 + 6i64) * 1000000000i64 } }
        let (node, node_error) = overlay.duration_picker(a, u64((i + 1usize) * 10usize), t, "Duration", value, widget.Change[time.Duration] { ctx: zero, invoke: noop_duration })
        if node_error != ok { ret (0usize, node_error) }
        var shown = node
        if t.tokens.profile == .Neper {
            let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
            if held_error != ok { ret (0usize, held_error) }
            held[0usize] = node
            shown = widget.aligned(0u64, .Center, .Center, looks.size_style(300.0, 40.0), held[0usize..1usize])
        }
        // Android: the pointer on the Minutes plus button (the centre of the cell falls on the gap between steppers, so Hover equalled Rest)
        if i == 3usize { looks_z87.aim(t, i, 45.0, 0.0) }
        cells[i] = looks.Cell { caption: names[i], node: shown, drive: drives[i] }
        i += 1usize
    }
    ret (5usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    looks.pad_neper(70.0, 16.0)
    let sheet = looks.Sheet { name: "duration_picker", cells: 5usize, columns: 3usize, cell_w: 250.0, cell_h: 90.0, ctx: zero, build: build }
    // Cupertino steppers are 94 wide; the shared cell clipped them, so this look gets a wider cell (the other looks keep theirs).
    let wide = looks.Sheet { name: "duration_picker", cells: 5usize, columns: 3usize, cell_w: 400.0, cell_h: 90.0, ctx: zero, build: build }
    try looks.run_all(a, &sheet)
    try looks.run_linux(a, &sheet)
    try looks.run_cupertino(a, &wide)
    // Android: three steppers of 40 dp icon buttons are 450 wide; in 250 the pills squeezed the buttons to 22 and the dash and plus marks degenerated
    let android = looks.Sheet { name: "duration_picker", cells: 5usize, columns: 2usize, cell_w: 520.0, cell_h: 90.0, ctx: zero, build: build }
    ret looks.run_material(a, &android)
}
