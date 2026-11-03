// The bottom app bar, docs/ui/looks/<look>/bottom_app_bar.png: the action row with and without the floating action button, two and four
// actions, an action disabled. Derived: the library's bottom bar (Material 3 bottom app bar) drawn through each look's tokens; Apple and
// GNOME have no such bar. Run from the repository root.

use e.gfx.scene
use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_e
use e.ui.looks_z87
use e.ui.navigation
use e.ui.widget

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (subs, subs_error) = looks_e.submits(a, 1usize)
    if subs_error != ok { ret (0usize, subs_error) }
    let (acts, acts_error) = mem.alloc[navigation.Action](a, 5usize)
    if acts_error != ok { ret (0usize, acts_error) }
    var no_icon: scene.TextureId = zero
    let labels = [5]str{ "Search", "Share", "Archive", "Delete", "Compose" }
    var k = 0usize
    while k < 5usize {
        acts[k] = navigation.Action { label: labels[k], action: subs[0usize], icon: no_icon, enabled: true }
        k += 1usize
    }
    let names = [6]str{ "two actions + fab", "four actions + fab", "two actions, no fab", "one disabled", "hover", "focus" }
    // Android: two more cells, hover over the first action and keyboard focus (the other looks keep the four)
    var n = 4usize
    if t.tokens.profile == .MaterialLike { n = 6usize }
    var i = 0usize
    while i < n {
        var count = 2usize
        if i == 1usize { count = 4usize }
        var fab = acts[4usize]
        if i == 2usize { fab.label = "" }
        acts[1usize].enabled = i != 3usize
        let (bar, bar_error) = navigation.bottom_app_bar(a, u64((i + 1usize) * 100usize), t, "Actions", acts[0usize..count], &fab, 360.0)
        if bar_error != ok { ret (0usize, bar_error) }
        var drive: looks.Drive = .None
        if i == 4usize { drive = .Hover }
        if i == 5usize { drive = .Focus }
        if i == 4usize { looks_z87.aim(t, i, 0.0 - 152.0, 0.0) }
        cells[i] = looks.Cell { caption: names[i], node: bar, drive: drive }
        i += 1usize
    }
    ret (n, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "bottom_app_bar", cells: 4usize, columns: 2usize, cell_w: 376.0, cell_h: 112.0, ctx: zero, build: build }
    try looks.run_all(a, &sheet)
    try looks.run_cupertino(a, &sheet)
    try looks.run_linux(a, &sheet)
    let android = looks.Sheet { name: "bottom_app_bar", cells: 6usize, columns: 2usize, cell_w: 376.0, cell_h: 112.0, ctx: zero, build: build }
    ret looks.run_material(a, &android)
}
