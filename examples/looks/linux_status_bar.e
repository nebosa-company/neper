// The Linux look's status bar against the real GTK 4.14 / libadwaita 1.5: an AdwHeaderBar with a subtitle (the library's capture
// carries its window controls, drawn here by the sheet as the three 24 px circles they are) and a GtkActionBar with a status text
// and a position, docs/ui/looks/linux[-dark]/status_bar.png (reference: scripts/linux_cmp_l3.py). Run from the repository root.

use e.gfx.paint
use e.mem
use e.ui.control
use e.ui.looks
use e.ui.navigation
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

// A window control: a 24 px circle in the text colour at 8 % holding a 16 px glyph.
fn window_control(a: *mem.Arena, t: *const control.Theme, kind: control.GlyphKind, x: f32) -> (widget.Node, err) {
    let (mark, mark_error) = control.icon_square(a, style.color(t.tokens, .Text), kind, 16.0)
    if mark_error != ok { ret (zero, mark_error) }
    var disc = control.sized_style(24.0, 24.0)
    disc.radius = 12.0
    disc.background = paint.Brush { Solid: style.hexa(0x000000u32, 0.08) }
    if t.tokens.palette == .Dark { disc.background = paint.Brush { Solid: style.hexa(0xFFFFFFu32, 0.1) } }
    let centred = widget.aligned(0u64, .Center, .Center, disc, control.widget_one_of(a, mark))
    ret (widget.positioned(0u64, x, 11.0, style.defaults(), control.widget_one_of(a, centred)), ok)
}

fn header(a: *mem.Arena, t: *const control.Theme, action: *const widget.Submit) -> (widget.Node, err) {
    var options = control.button_options()
    options.variant = .Plain
    let (add, add_error) = control.button_with_glyph(a, 11u64, t, .Add, "", action, options)
    if add_error != ok { ret (zero, add_error) }
    let (menu, menu_error) = control.button_with_glyph(a, 12u64, t, .Menu, "", action, options)
    if menu_error != ok { ret (zero, menu_error) }
    let (starts, starts_error) = mem.alloc[widget.Node](a, 1usize)
    if starts_error != ok { ret (zero, starts_error) }
    let (ends, ends_error) = mem.alloc[widget.Node](a, 1usize)
    if ends_error != ok { ret (zero, ends_error) }
    starts[0usize] = add
    ends[0usize] = menu
    let (bar, bar_error) = navigation.linux_header_bar(a, 1000u64, t, "Title", "Subtitle", starts[0usize..1usize], ends[0usize..1usize], 120.0, 420.0)
    if bar_error != ok { ret (zero, bar_error) }
    let (layers, layers_error) = mem.alloc[widget.Node](a, 4usize)
    if layers_error != ok { ret (zero, layers_error) }
    layers[0usize] = bar
    let kinds = [3]control.GlyphKind{ .Dash, .Maximize, .Cross }
    var i = 0usize
    while i < 3usize {
        let (disc, disc_error) = window_control(a, t, kinds[i], 311.0 + 37.0 * f32(i))
        if disc_error != ok { ret (zero, disc_error) }
        layers[1usize + i] = disc
        i += 1usize
    }
    ret (widget.stack(0u64, control.sized_style(420.0, 47.0), layers[0usize..4usize]), ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let (head, head_error) = header(a, t, &actions[0usize])
    if head_error != ok { ret (0usize, head_error) }
    let held = widget.positioned(0u64, 5.0, 6.0, control.sized_style(420.0, 47.0), control.widget_one_of(a, head))
    cells[0usize] = looks.Cell { caption: "header bar with subtitle", node: widget.stack(0u64, control.sized_style(430.0, 60.0), control.widget_one_of(a, held)), drive: .None }
    let (items, items_error) = mem.alloc[navigation.StatusItem](a, 2usize)
    if items_error != ok { ret (0usize, items_error) }
    items[0usize] = navigation.status_item("Status text")
    items[1usize] = navigation.status_item("Ln 1, Col 1")
    items[1usize].end = true
    let (bar, bar_error) = navigation.status_bar_of(a, 2000u64, t, items[0usize..2usize], false, 360.0)
    if bar_error != ok { ret (0usize, bar_error) }
    let placed = widget.positioned(0u64, 35.0, 14.0, control.sized_style(360.0, 32.0), control.widget_one_of(a, bar))
    cells[1usize] = looks.Cell { caption: "action bar", node: widget.stack(0u64, control.sized_style(430.0, 60.0), control.widget_one_of(a, placed)), drive: .None }
    ret (2usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "status_bar", cells: 2usize, columns: 1usize, cell_w: 430.0, cell_h: 60.0, ctx: zero, build: build }
    ret looks.run_linux(a, &sheet)
}
