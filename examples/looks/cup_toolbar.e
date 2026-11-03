// The Cupertino toolbar button and navigation bar: docs/ui/looks/cupertino/toolbar_button.png (and cupertino-dark).
// Toolbar glyph buttons: rest, hover, pressed, keyboard focus, on (toggle); then the iOS navigation bar: back button and
// trailing action, a title with leading and trailing actions, the large-title bar.

use e.gfx.scene
use e.mem
use e.ui.control
use e.ui.looks
use e.ui.navigation
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, base: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    // This sheet only: Apple's increased-contrast blue (0040DD light, 409CFF dark) for the accent, so the bar text holds 4.5:1; every
    // other sheet keeps systemBlue.
    let (copy, copy_error) = mem.alloc[style.ThemeTokens](a, 1usize)
    if copy_error != ok { ret (0usize, copy_error) }
    copy[0usize] = *base.tokens
    var blue = 0x0040DDu32
    if base.tokens.palette == .Dark { blue = 0x409CFFu32 }
    style.puta(&copy[0usize], .Primary, blue, 1.0)
    var local = *base
    local.tokens = &copy[0usize]
    let t = &local
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let names = [8]str{ "rest", "hover", "pressed", "focus", "on", "nav: back, action", "nav: actions", "nav: large title" }
    var i = 0usize
    while i < 5usize {
        let key = u64((i + 1usize) * 10usize)
        var node: widget.Node = zero
        if i == 4usize {
            let (made, made_error) = control.glyph_toggle(a, key, t, .Search, "Search", &actions[0usize], 32.0, 20.0, true)
            if made_error != ok { ret (0usize, made_error) }
            node = made
        } else {
            let (made, made_error) = control.glyph_button(a, key, t, .Search, "Search", &actions[0usize], 32.0, 20.0)
            if made_error != ok { ret (0usize, made_error) }
            node = made
        }
        var drive: looks.Drive = .None
        if i == 1usize { drive = .Hover }
        if i == 2usize { drive = .Press }
        if i == 3usize { drive = .Focus }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        i += 1usize
    }
    let (lead, lead_error) = mem.alloc[navigation.Action](a, 1usize)
    if lead_error != ok { ret (0usize, lead_error) }
    let (trail, trail_error) = mem.alloc[navigation.Action](a, 2usize)
    if trail_error != ok { ret (0usize, trail_error) }
    var no_icon: scene.TextureId = zero
    lead[0usize] = navigation.Action { label: "Cancel", action: actions[0usize], icon: no_icon, enabled: true }
    trail[0usize] = navigation.Action { label: "Edit", action: actions[0usize], icon: no_icon, enabled: true }
    trail[1usize] = navigation.Action { label: "Done", action: actions[0usize], icon: no_icon, enabled: false }
    var k = 5usize
    while k < 8usize {
        var options = navigation.app_bar_options()
        var leading: []const navigation.Action = lead[0usize..0usize]
        var trailing: []const navigation.Action = trail[0usize..1usize]
        if k == 5usize {
            options.back_label = "Settings"
            options.back = actions[0usize]
        }
        if k == 6usize {
            leading = lead[0usize..1usize]
            trailing = trail[0usize..1usize]
        }
        if k == 7usize {
            options.size = .Large
            trailing = trail[0usize..1usize]
        }
        let (bar, bar_error) = navigation.app_bar_of(a, u64((k + 1usize) * 1000usize), t, "Library", leading, trailing, options, 330.0)
        if bar_error != ok { ret (0usize, bar_error) }
        cells[k] = looks.Cell { caption: names[k], node: bar, drive: .None }
        k += 1usize
    }
    ret (8usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "toolbar_button", cells: 8usize, columns: 4usize, cell_w: 346.0, cell_h: 104.0, ctx: zero, build: build }
    ret looks.run_cupertino(a, &sheet)
}
