// The Linux look's page controls against the real GTK 4.14 / libadwaita 1.5: a GtkNotebook with its tabs on top and on the left,
// an AdwTabBar over its page and an AdwViewSwitcher, docs/ui/looks/linux[-dark]/page_control.png (reference:
// scripts/linux_cmp_l3.py). The notebook is the tab header the control builds, a 1 px frame round it and the page beside it.
// Run from the repository root.

use e.gfx.paint
use e.mem
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

// A frame of `w` x `h` (1 px #dddddd) holding the header at (1, 1), the page (the view colour) and its label.
fn notebook(a: *mem.Arena, t: *const control.Theme, vertical: bool, w: f32, h: f32, picks: []const widget.Submit) -> (widget.Node, err) {
    let labels = [3]str{ "General", "Advanced", "About" }
    var options = control.tabs_options()
    options.vertical = vertical
    options.width = w - 2.0
    if vertical { options.width = h - 2.0 }
    let (header, header_error) = control.tabs_of(a, 1000u64, t, labels[0usize..3usize], 1usize, picks, options)
    if header_error != ok { ret (zero, header_error) }
    var frame = control.sized_style(w, h)
    frame.border = style.Border { width: 1.0, color: control.linux_rule(t) }
    let (layers, layers_error) = mem.alloc[widget.Node](a, 4usize)
    if layers_error != ok { ret (zero, layers_error) }
    layers[0usize] = widget.box(0u64, frame, zero)
    // the page: the view colour right of (or below) the header, its title centred
    var page_x: f32 = 1.0
    var page_y: f32 = 38.0
    var page_w = w - 2.0
    var page_h = h - 39.0
    if vertical {
        page_x = 88.0
        page_y = 1.0
        page_w = w - 89.0
        page_h = h - 2.0
    }
    var page = control.sized_style(page_w, page_h)
    page.background = paint.Brush { Solid: style.color(t.tokens, .Surface) }
    let (said, said_error) = control.text(a, 0u64, "Advanced page", t, control.text_options())
    if said_error != ok { ret (zero, said_error) }
    let page_node = widget.aligned(0u64, .Center, .Center, page, control.widget_one_of(a, said))
    layers[1usize] = widget.positioned(0u64, page_x, page_y, style.defaults(), control.widget_one_of(a, page_node))
    layers[2usize] = widget.positioned(0u64, 1.0, 1.0, style.defaults(), control.widget_one_of(a, header))
    ret (widget.stack(0u64, control.sized_style(w, h), layers[0usize..3usize]), ok)
}

// The tab bar over its page: three tabs, the first chosen with its close button and the fade the scrolled strip's edge puts on it.
fn tab_bar(a: *mem.Arena, t: *const control.Theme, picks: []const widget.Submit) -> (widget.Node, err) {
    let labels = [3]str{ "Tab one", "Tab two", "Tab three" }
    let lefts = [3]f32{ 6.0, 112.0, 245.0 }
    let widths = [3]f32{ 106.0, 133.0, 133.0 }
    let (bar, bar_error) = control.linux_tab_bar(a, 2000u64, t, labels[0usize..3usize], 0usize, picks, lefts[0usize..3usize], widths[0usize..3usize], 36.0, 380.0)
    if bar_error != ok { ret (zero, bar_error) }
    let (said, said_error) = control.text(a, 0u64, "Tab one", t, control.text_options())
    if said_error != ok { ret (zero, said_error) }
    let page = widget.aligned(0u64, .Center, .Center, control.sized_style(380.0, 60.0), control.widget_one_of(a, said))
    let (layers, layers_error) = mem.alloc[widget.Node](a, 2usize)
    if layers_error != ok { ret (zero, layers_error) }
    layers[0usize] = bar
    layers[1usize] = widget.positioned(0u64, 0.0, 47.0, style.defaults(), control.widget_one_of(a, page))
    ret (widget.stack(0u64, control.sized_style(380.0, 107.0), layers[0usize..2usize]), ok)
}

// The view switcher over its page's one letter.
fn view_switcher(a: *mem.Arena, t: *const control.Theme, picks: []const widget.Submit) -> (widget.Node, err) {
    let labels = [2]str{ "General", "Advanced" }
    let kinds = [2]control.GlyphKind{ .Picture, .Picture }
    let lefts = [2]f32{ 0.0, 122.0 }
    let widths = [2]f32{ 120.0, 121.0 }
    let (switcher, switcher_error) = control.linux_view_switcher(a, 3000u64, t, labels[0usize..2usize], kinds[0usize..2usize], 0usize, picks, lefts[0usize..2usize], widths[0usize..2usize], 243.0)
    if switcher_error != ok { ret (zero, switcher_error) }
    let (said, said_error) = control.text(a, 0u64, "A", t, control.text_options())
    if said_error != ok { ret (zero, said_error) }
    let page = widget.aligned(0u64, .Center, .Center, control.sized_style(243.0, 25.0), control.widget_one_of(a, said))
    let (layers, layers_error) = mem.alloc[widget.Node](a, 2usize)
    if layers_error != ok { ret (zero, layers_error) }
    layers[0usize] = switcher
    layers[1usize] = widget.positioned(0u64, 0.0, 26.0, style.defaults(), control.widget_one_of(a, page))
    ret (widget.stack(0u64, control.sized_style(243.0, 49.0), layers[0usize..2usize]), ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (picks, picks_error) = mem.alloc[widget.Submit](a, 3usize)
    if picks_error != ok { ret (0usize, picks_error) }
    var i = 0usize
    while i < 3usize {
        picks[i] = widget.Submit { ctx: zero, invoke: noop_submit }
        i += 1usize
    }
    let names = [4]str{ "notebook, tabs on top", "notebook, tabs on the left", "tab bar", "view switcher" }
    var k = 0usize
    while k < 4usize {
        var w: f32 = 259.0
        var h: f32 = 129.0
        if k == 1usize {
            w = 329.0
            h = 142.0
        }
        if k == 2usize {
            w = 380.0
            h = 107.0
        }
        if k == 3usize {
            w = 243.0
            h = 49.0
        }
        var node: widget.Node = zero
        if k < 2usize {
            let (made, made_error) = notebook(a, t, k == 1usize, w, h, picks[0usize..3usize])
            if made_error != ok { ret (0usize, made_error) }
            node = made
        } else if k == 2usize {
            let (made, made_error) = tab_bar(a, t, picks[0usize..3usize])
            if made_error != ok { ret (0usize, made_error) }
            node = made
        } else {
            let (made, made_error) = view_switcher(a, t, picks[0usize..2usize])
            if made_error != ok { ret (0usize, made_error) }
            node = made
        }
        let x = f32(usize(390.0 - w) / 2usize)
        let y = f32(usize(150.0 - h) / 2usize)
        let held = widget.positioned(0u64, x, y, control.sized_style(w, h), control.widget_one_of(a, node))
        cells[k] = looks.Cell { caption: names[k], node: widget.stack(0u64, control.sized_style(390.0, 150.0), control.widget_one_of(a, held)), drive: .None }
        k += 1usize
    }
    ret (4usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "page_control", cells: 4usize, columns: 2usize, cell_w: 390.0, cell_h: 150.0, ctx: zero, build: build }
    ret looks.run_linux(a, &sheet)
}
