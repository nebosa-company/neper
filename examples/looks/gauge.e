// The gauge (control.gauge) in all ten looks: docs/ui/looks/<look>/gauge.png. Derived: the arc and readout read the shared
// tokens (Primary, Warning, Error, SurfaceContainerHighest); no platform draws this control, so no reference exists.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_b_run
use e.ui.widget
use e.ui.looks_y87
use e.ui.style

// Cupertino only: the roles this sheet draws with take tones that hold 4.5:1 (any other look is passed through unchanged).
fn build(ctx: *void, a: *mem.Arena, original: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let tones = [3]looks_y87.RoleTone{ looks_y87.blue_tone(), looks_y87.orange_tone(.Warning), looks_y87.RoleTone { role: .Error, light: 0xD70015u32, dark: 0xFF453Au32 } }
    let (tokens, tokens_error) = looks_y87.retoned(a, original.tokens, tones[0usize..3usize])
    if tokens_error != ok { ret (0usize, tokens_error) }
    var themed = *original
    themed.tokens = tokens
    let (count, count_error) = build_base(ctx, a, &themed, cells)
    ret (count, count_error)
}

fn build_base(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [8]str{ "42 %", "0 %", "100 %", "warning 72 %", "critical 93 %", "no data", "stale", "loading" }
    let values = [8]f32{ 42.0, 0.0, 100.0, 72.0, 93.0, 0.0, 42.0, 0.0 }
    var i = 0usize
    while i < 8usize {
        var options = control.gauge_options()
        options.unit = "CPU load"
        if i == 3usize || i == 4usize {
            options.warn = 0.6
            options.critical = 0.9
        }
        if i == 5usize { options.no_data = true }
        if i == 6usize { options.stale = true }
        if i == 7usize { options.loading = true }
        let (node, node_error) = control.gauge_of(a, u64((i + 1usize) * 10usize), t, "Processor", values[i], 0.0, 100.0, 96.0, options)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: .None }
        i += 1usize
    }
    ret (8usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "gauge", cells: 8usize, columns: 4usize, cell_w: 150.0, cell_h: 170.0, ctx: zero, build: build }
    ret looks_b_run.run_ten(a, &sheet)
}
