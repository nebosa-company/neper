// The toolbar (a row of plain actions), docs/ui/looks/<look>/toolbar.png: at rest, the middle action hovered, pressed, keyboard-focused,
// with a disabled action, and a longer row. Derived: the library's navigation.toolbar through each look's tokens; no reference capture
// beyond the Windows toolbar_button sheet. Run from the repository root.

use e.gfx.scene
use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_y87
use e.ui.looks_e
use e.ui.navigation
use e.ui.widget

// Increased-contrast blue for the toolbar text buttons (any other look is passed through unchanged).
fn build(ctx: *void, a: *mem.Arena, original: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let tones = [2]looks_y87.RoleTone{ looks_y87.RoleTone { role: .Primary, light: 0x0040DDu32, dark: 0x409CFFu32 }, looks_y87.RoleTone { role: .FocusRing, light: 0x0A60FFu32, dark: 0x409CFFu32 } }
    let (tokens, tokens_error) = looks_y87.retoned(a, original.tokens, tones[0usize..2usize])
    if tokens_error != ok { ret (0usize, tokens_error) }
    var themed = *original
    themed.tokens = tokens
    let (count, count_error) = build_base(ctx, a, &themed, cells)
    ret (count, count_error)
}

fn build_base(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (subs, subs_error) = looks_e.submits(a, 1usize)
    if subs_error != ok { ret (0usize, subs_error) }
    let (acts, acts_error) = mem.alloc[navigation.Action](a, 5usize)
    if acts_error != ok { ret (0usize, acts_error) }
    var no_icon: scene.TextureId = zero
    let labels = [5]str{ "Cut", "Copy", "Paste", "Undo", "Redo" }
    var k = 0usize
    while k < 5usize {
        acts[k] = navigation.Action { label: labels[k], action: subs[0usize], icon: no_icon, enabled: true }
        k += 1usize
    }
    let names = [6]str{ "rest", "hover", "pressed", "focus", "one disabled", "five actions" }
    var i = 0usize
    while i < 6usize {
        var count = 3usize
        if i == 5usize { count = 5usize }
        if i == 4usize { acts[1usize].enabled = false }
        let (bar, bar_error) = navigation.toolbar(a, u64((i + 1usize) * 100usize), t, "Edit", acts[0usize..count])
        if bar_error != ok { ret (0usize, bar_error) }
        let (boxed, boxed_error) = looks_e.framed(a, u64((i + 1usize) * 100usize + 90usize), 310.0, 48.0, bar)
        if boxed_error != ok { ret (0usize, boxed_error) }
        cells[i] = looks.Cell { caption: names[i], node: boxed, drive: looks_e.drive_of(i, 1usize, 2usize, 3usize) }
        i += 1usize
    }
    ret (6usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "toolbar", cells: 6usize, columns: 3usize, cell_w: 350.0, cell_h: 86.0, ctx: zero, build: build }
    ret looks_e.run_ten(a, &sheet)
}
