// The large title navigation bar (Apple's large title; the other looks draw the library's large app bar), docs/ui/looks/<look>/large_title.png:
// the inline title, the large title, large with a back button and an action, large scrolled (collapsed), centred. Run from the repository root.
// Derived: Cupertino from HIG numbers (34 pt bold title); the other looks show what navigation.app_bar_of draws for size Large.

use e.gfx.scene
use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_e
use e.ui.navigation
use e.ui.widget

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (subs, subs_error) = looks_e.submits(a, 2usize)
    if subs_error != ok { ret (0usize, subs_error) }
    var no_icon: scene.TextureId = zero
    let (lead, lead_error) = mem.alloc[navigation.Action](a, 1usize)
    if lead_error != ok { ret (0usize, lead_error) }
    let (trail, trail_error) = mem.alloc[navigation.Action](a, 2usize)
    if trail_error != ok { ret (0usize, trail_error) }
    lead[0usize] = navigation.Action { label: "Cancel", action: subs[0usize], icon: no_icon, enabled: true }
    trail[0usize] = navigation.Action { label: "Edit", action: subs[1usize], icon: no_icon, enabled: true }
    trail[1usize] = navigation.Action { label: "Done", action: subs[1usize], icon: no_icon, enabled: false }
    let names = [6]str{ "inline title", "large title", "large, back + action", "large, scrolled", "large, cancel + edit", "large, disabled action" }
    var i = 0usize
    while i < 6usize {
        var options = navigation.app_bar_options()
        var leading: []const navigation.Action = lead[0usize..0usize]
        var trailing: []const navigation.Action = trail[0usize..1usize]
        if i >= 1usize { options.size = .Large }
        if i == 2usize {
            options.back_label = "Library"
            options.back = subs[0usize]
        }
        if i == 3usize { options.scrolled = true }
        if i == 4usize { leading = lead[0usize..1usize] }
        if i == 5usize { trailing = trail[1usize..2usize] }
        // The top app bar drops a lone disabled action; the Android sheet shows a disabled Done beside a live Edit instead.
        if i == 5usize && t.tokens.profile == .MaterialLike { trailing = trail[0usize..2usize] }
        let (bar, bar_error) = navigation.app_bar_of(a, u64((i + 1usize) * 1000usize), t, "Library", leading, trailing, options, 330.0)
        if bar_error != ok { ret (0usize, bar_error) }
        var caption = names[i]
        if i == 5usize && t.tokens.profile == .MaterialLike { caption = "large, Done disabled beside Edit" }
        cells[i] = looks.Cell { caption: caption, node: bar, drive: .None }
        i += 1usize
    }
    ret (6usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "large_title", cells: 6usize, columns: 3usize, cell_w: 346.0, cell_h: 124.0, ctx: zero, build: build }
    ret looks_e.run_ten(a, &sheet)
}
