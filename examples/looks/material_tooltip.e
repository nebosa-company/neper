// The Android look's tooltips, docs/ui/looks/material/tooltip.png: a plain tooltip over an anchor and a rich tooltip with a
// subhead. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.overlay
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn anchored(a: *mem.Arena, t: *const control.Theme, action: *const widget.Submit, i: usize, rich: bool, text: str, subhead: str) -> (widget.Node, err) {
    let anchor_key = u64(100usize + i)
    var options = control.button_options()
    options.variant = .Tonal
    let (button, button_error) = control.button(a, anchor_key, t, "Anchor", action, options)
    if button_error != ok { ret (zero, button_error) }
    var tip: widget.Node = zero
    if rich {
        let (items, items_error) = mem.alloc[overlay.MenuItem](a, 1usize)
        if items_error != ok { ret (zero, items_error) }
        items[0usize] = overlay.MenuItem { label: "Learn more", action: *action, enabled: true }
        let (made, made_error) = overlay.rich_tooltip(a, u64(5000usize + i * 100usize), t, anchor_key, subhead, text, items[0usize..1usize], true)
        if made_error != ok { ret (zero, made_error) }
        tip = made
    } else {
        let (made, made_error) = overlay.tooltip_of(a, u64(5000usize + i * 100usize), t, anchor_key, text, "", true)
        if made_error != ok { ret (zero, made_error) }
        tip = made
    }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = button
    parts[1usize] = tip
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..2usize]), ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let captions = [3]str{ "Plain", "Plain, long", "Rich, subhead and action" }
    let texts = [3]str{ "Add to favorites", "Cards that share a name are\ncounted once, whatever their edition", "Prices are refreshed every night from TCGplayer and can lag a day." }
    var i = 0usize
    while i < 3usize {
        var subhead = ""
        if i == 2usize { subhead = "Price refresh" }
        let (node, node_error) = anchored(a, t, &actions[0usize], i, i == 2usize, texts[i], subhead)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: .None }
        i += 1usize
    }
    ret (3usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "tooltip", cells: 3usize, columns: 3usize, cell_w: 320.0, cell_h: 280.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
