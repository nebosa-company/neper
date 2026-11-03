// Round 62 c: the notification list in all ten looks: three notices, one notice, none, and the clear action hovered and
// pressed. Derived from the shared tokens, no platform capture. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_y85
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, base: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    // Cupertino only: accent text and the keyboard ring take the increased-contrast blue (0x0040DD, 0x409CFF); other looks get their own tokens back.
    let (tokens, tokens_error) = looks_y85.tinted_ring(a, base.tokens, 0x0040DDu32, 0x409CFFu32)
    if tokens_error != ok { ret (0usize, tokens_error) }
    var themed = *base
    themed.tokens = tokens
    let t = &themed
    let (notices, notices_error) = mem.alloc[control.Notice](a, 3usize)
    if notices_error != ok { ret (0usize, notices_error) }
    let go = widget.Submit { ctx: zero, invoke: noop_submit }
    notices[0usize] = control.Notice { text: "Prices refreshed", action_label: "View", action: go, dismiss: go }
    notices[1usize] = control.Notice { text: "Deck saved", action_label: "", action: zero, dismiss: go }
    notices[2usize] = control.Notice { text: "Import finished: 2 cards were not found", action_label: "Details", action: go, dismiss: go }
    let (clear, clear_error) = mem.alloc[widget.Submit](a, 1usize)
    if clear_error != ok { ret (0usize, clear_error) }
    clear[0usize] = go
    let captions = [5]str{ "Three notices", "One notice", "Empty", "Clear hovered", "Clear pressed" }
    let counts = [5]usize{ 3usize, 1usize, 0usize, 3usize, 3usize }
    // Cupertino (round 87): the three-notice list stands tall enough for its third row.
    var listh: f32 = 260.0
    if t.tokens.profile == .CupertinoLike { listh = 300.0 }
    // Android (round 88): 56 dp header, two-line text and the action put the third row's action at about 310
    if t.tokens.profile == .MaterialLike { listh = 330.0 }
    var i = 0usize
    while i < 5usize {
        let (node, node_error) = control.notification_list(a, u64((i + 1usize) * 64usize), t, "Notifications", notices[0usize..counts[i]], &clear[0usize], 340.0, listh)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 3usize { drive = .Hover }
        if i == 4usize { drive = .Press }
        if i == 3usize || i == 4usize {
            var up: f32 = 0.0 - 100.0
            if t.tokens.profile == .MaterialLike { up = 30.0 - listh * 0.5 }
            looks.aim(i, 123.0, up)
        }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (5usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "notification_list", cells: 5usize, columns: 3usize, cell_w: 370.0, cell_h: 300.0, ctx: zero, build: build }
    try looks.run_all(a, &sheet)
    let android = looks.Sheet { name: "notification_list", cells: 5usize, columns: 3usize, cell_w: 370.0, cell_h: 370.0, ctx: zero, build: build }
    try looks.run_material(a, &android)
    try looks.run_cupertino(a, &sheet)
    ret looks.run_linux(a, &sheet)
}
