// The date range picker (overlay.date_range_picker) in all ten looks: docs/ui/looks/<look>/date_range_picker.png (the field in
// its states) and date_range_picker_open.png (the open calendar with the range banded; one cell, the flyout needs the room).
// Derived: the field and flyout read the shared tokens; Linux shows a menu button with a popover, Windows a drop-down field.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.time
use e.ui.control
use e.ui.looks
use e.ui.looks_b_run
use e.ui.overlay
use e.ui.style
use e.ui.widget
use e.ui.layout as ui_layout
use e.ui.looks_y85
use e.ui.looks_y87

fn noop_submit(ctx: *void) -> err { ret ok }
fn noop_date(ctx: *void, value: time.Date) -> err { ret ok }

fn day(d: u8) -> time.Date { ret time.Date { year: 2026i32, month: 10u8, day: d } }

fn field(a: *mem.Arena, t: *const control.Theme, key: u64, has_range: bool, open: bool) -> (widget.Node, err) {
    let (toggle, toggle_error) = mem.alloc[widget.Submit](a, 1usize)
    if toggle_error != ok { ret (zero, toggle_error) }
    toggle[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let (node, node_error) = overlay.date_range_picker(a, key, t, "Choose dates", day(12u8), day(18u8), has_range, open, &toggle[0usize], day(1u8), widget.Change[time.Date] { ctx: zero, invoke: noop_date }, widget.Change[time.Date] { ctx: zero, invoke: noop_date })
    ret (node, node_error)
}

// Chosen ends, the band and the links hold 4.5:1 (white on 0A60FF, near-black on 409CFF; band digits 0040DD on DCE8FF, 9CC8FF on 1E3A66).
var tone_store: [5]looks_y87.RoleTone = zero
fn range_tones() -> []looks_y87.RoleTone {
    tone_store[0usize] = looks_y87.RoleTone { role: .Primary, light: 0x0A60FFu32, dark: 0x409CFFu32 }
    tone_store[1usize] = looks_y87.RoleTone { role: .OnPrimary, light: 0xFFFFFFu32, dark: 0x0B0B0Cu32 }
    tone_store[2usize] = looks_y87.ring_tone()
    tone_store[3usize] = looks_y87.RoleTone { role: .PrimaryContainer, light: 0xDCE8FFu32, dark: 0x1E3A66u32 }
    tone_store[4usize] = looks_y87.RoleTone { role: .OnPrimaryContainer, light: 0x0040DDu32, dark: 0x9CC8FFu32 }
    ret tone_store[0usize..5usize]
}

fn build(ctx: *void, a: *mem.Arena, base: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    // Cupertino only: accent text, selected tint and keyboard ring hold the contrast rule (0045E6 light, 409CFF dark); other looks unchanged.
    let (tokens, tokens_error) = looks_y87.retoned(a, base.tokens, range_tones())
    if tokens_error != ok { ret (0usize, tokens_error) }
    var local = *base
    local.tokens = tokens
    let t = &local
    let names = [5]str{ "Empty", "Range chosen", "Hover", "Focus", "Pressed" }
    let drives = [5]looks.Drive{ .None, .None, .Hover, .Focus, .Press }
    var i = 0usize
    while i < 5usize {
        let (node, node_error) = field(a, t, u64((i + 1usize) * 10000usize), i != 0usize, false)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drives[i] }
        i += 1usize
    }
    ret (5usize, ok)
}

// The control 12 px below the top of its cell, so the flyout under it stays inside the window.
fn build_open(ctx: *void, a: *mem.Arena, base: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    // Cupertino only: accent text, selected tint and keyboard ring hold the contrast rule (0045E6 light, 409CFF dark); other looks unchanged.
    let (tokens, tokens_error) = looks_y87.retoned(a, base.tokens, range_tones())
    if tokens_error != ok { ret (0usize, tokens_error) }
    var local = *base
    local.tokens = tokens
    let t = &local
    let (node, node_error) = field(a, t, 7u64 * 10000u64, true, true)
    if node_error != ok { ret (0usize, node_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (0usize, parts_error) }
    parts[0usize] = widget.box(0u64, looks.size_style(1.0, 12.0), zero)
    parts[1usize] = node
    let column = looks.size_style(340.0, 420.0)
    cells[0usize] = looks.Cell { caption: "Open, range banded", node: widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Center, gap: 0.0 }, column, parts[0usize..2usize]), drive: .None }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "date_range_picker", cells: 5usize, columns: 3usize, cell_w: 250.0, cell_h: 70.0, ctx: zero, build: build }
    try looks_b_run.run_ten(a, &sheet)
    let open = looks.Sheet { name: "date_range_picker_open", cells: 1usize, columns: 1usize, cell_w: 340.0, cell_h: 420.0, ctx: zero, build: build_open }
    ret looks_b_run.run_ten(a, &open)
}
