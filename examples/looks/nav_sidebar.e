// The sidebar, docs/ui/looks/<look>/sidebar.png: three destinations with the first selected, the second hovered,
// pressed, keyboard-focused, and four destinations. Derived: the library's sidebar through each look's tokens; no platform capture.
// Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_y87
use e.ui.looks_e
use e.ui.looks_y63
use e.ui.navigation
use e.ui.widget

// The chosen row takes the accent white text holds 4.5:1 on (any other look is passed through unchanged).
fn build(ctx: *void, a: *mem.Arena, original: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let tones = [2]looks_y87.RoleTone{ looks_y87.RoleTone { role: .Primary, light: 0x0A60FFu32, dark: 0x0B57D0u32 }, looks_y87.RoleTone { role: .FocusRing, light: 0x0A60FFu32, dark: 0x409CFFu32 } }
    let (tokens, tokens_error) = looks_y87.retoned(a, original.tokens, tones[0usize..2usize])
    if tokens_error != ok { ret (0usize, tokens_error) }
    var themed = *original
    themed.tokens = tokens
    let (count, count_error) = build_base(ctx, a, &themed, cells)
    ret (count, count_error)
}

fn build_base(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (subs, subs_error) = looks_e.submits(a, 4usize)
    if subs_error != ok { ret (0usize, subs_error) }
    let labels = [4]str{ "Home", "Search", "Library", "Profile" }
    let names = [5]str{ "rest", "hover", "pressed", "focus", "four, last selected" }
    var i = 0usize
    while i < 5usize {
        var count = 3usize
        var selected = 0usize
        if i == 4usize {
            count = 4usize
            selected = 3usize
        }
        // the focus cell: the middle destination selected and the stack centred, where the harness clicks before Tab
        if i == 3usize { selected = 1usize }
        let (rail, rail_error) = navigation.sidebar(a, u64((i + 1usize) * 100usize), t, labels[0usize..count], selected, subs[0usize..count], 200.0)
        if rail_error != ok { ret (0usize, rail_error) }
        var frame_h: f32 = 200.0
        if t.tokens.profile == .MaterialLike && count == 4usize { frame_h = 248.0 }
        let (boxed, boxed_error) = looks_e.framed(a, u64((i + 1usize) * 100usize + 90usize), 200.0, frame_h, rail)
        var shown = boxed
        if i == 3usize {
            let (middle, middle_error) = looks_y63.framed_center(a, u64((i + 1usize) * 100usize + 90usize), 200.0, 200.0, rail)
            if middle_error != ok { ret (0usize, middle_error) }
            shown = middle
        }
        if boxed_error != ok { ret (0usize, boxed_error) }
        cells[i] = looks.Cell { caption: names[i], node: shown, drive: looks_e.drive_of(i, 1usize, 2usize, 3usize) }
        i += 1usize
    }
    ret (5usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "sidebar", cells: 5usize, columns: 3usize, cell_w: 230.0, cell_h: 240.0, ctx: zero, build: build }
    try looks_e.run_ten(a, &sheet)
    // Android (round 86): the 56 dp rows of the four-item cell need a taller cell than the other looks' 40 and 44 dp rows (a fixed cell squeezed them to 44), so the sheet is drawn again for Material alone.
    let tall = looks.Sheet { name: "sidebar", cells: 5usize, columns: 3usize, cell_w: 230.0, cell_h: 320.0, ctx: zero, build: build }
    ret looks.run_material(a, &tall)
}
