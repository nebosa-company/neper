// Round 62 c: the avatar in all ten looks: initials at 24, 32, 40, 56 and 72, a square one, presence dots, a picture (the
// sample landscape of looks_c), the person glyph when there are no initials, and a pressable one hovered and focused.
// Derived from the shared tokens, no platform capture. Run from the repository root.

use e.gfx.scene
use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_c
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (hold, hold_error) = mem.alloc[widget.Submit](a, 1usize)
    if hold_error != ok { ret (0usize, hold_error) }
    hold[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let captions = [14]str{ "24", "32", "40", "56", "72", "Square", "Online", "Away", "Busy", "Picture", "No initials", "Pressable", "Hovered", "Focused" }
    let sizes = [14]f32{ 24.0, 32.0, 40.0, 56.0, 72.0, 40.0, 40.0, 40.0, 40.0, 56.0, 40.0, 40.0, 40.0, 40.0 }
    let accounts = [14]str{ "ada", "mina", "jon", "lee", "kai", "ada", "mina", "jon", "lee", "kai", "ada", "mina", "mina", "mina" }
    let initials = [14]str{ "AL", "MN", "JB", "LK", "KO", "AL", "MN", "JB", "LK", "KO", "", "MN", "MN", "MN" }
    var i = 0usize
    while i < 14usize {
        var options = control.avatar_options()
        options.size = sizes[i]
        options.account = accounts[i]
        options.initials = initials[i]
        options.label = captions[i]
        if i == 5usize { options.square = true }
        if i == 6usize { options.presence = .Online }
        if i == 7usize { options.presence = .Away }
        if i == 8usize { options.presence = .Busy }
        if i >= 11usize {
            options.action = &hold[0usize]
            options.action_label = "Open profile"
        }
        var picture: scene.TextureId = zero
        if i == 9usize { picture = looks_c.picture }
        let (node, node_error) = control.avatar_of(a, u64((i + 1usize) * 16usize), t, picture, options)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 12usize { drive = .Hover }
        if i == 13usize { drive = .Focus }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (14usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "avatar", cells: 14usize, columns: 5usize, cell_w: 120.0, cell_h: 110.0, ctx: zero, build: build }
    try looks.run_all(a, &sheet)
    try looks.run_material(a, &sheet)
    try looks.run_cupertino(a, &sheet)
    ret looks.run_linux(a, &sheet)
}
