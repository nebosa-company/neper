// The Linux look's toolbar buttons against the real GTK 4.14 / libadwaita 1.5: icon and flat icon buttons in five states, the
// toggle button on and off, an AdwHeaderBar (its window controls drawn by the sheet) and a toolbar of flat icon buttons with a
// separator, docs/ui/looks/linux[-dark]/toolbar_button.png (reference: scripts/linux_cmp_l3.py). Run from the repository root.

use e.gfx.paint
use e.mem
use e.ui.adwicon_l2 as adwicon
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.navigation
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn window_control(a: *mem.Arena, t: *const control.Theme, svg: str, x: f32) -> (widget.Node, err) {
    let (mark, mark_error) = adwicon.icon(a, svg, style.color(t.tokens, .Text), 16.0)
    if mark_error != ok { ret (zero, mark_error) }
    var disc = control.sized_style(24.0, 24.0)
    disc.radius = 12.0
    disc.background = paint.Brush { Solid: style.hexa(0x000000u32, 0.08) }
    if t.tokens.palette == .Dark { disc.background = paint.Brush { Solid: style.hexa(0xFFFFFFu32, 0.1) } }
    let centred = widget.aligned(0u64, .Center, .Center, disc, control.widget_one_of(a, mark))
    ret (widget.positioned(0u64, x, 11.0, style.defaults(), control.widget_one_of(a, centred)), ok)
}

fn header(a: *mem.Arena, t: *const control.Theme, action: *const widget.Submit) -> (widget.Node, err) {
    let (add, add_error) = control.linux_svg_toggle(a, 11u64, t, adwicon.list_add(), "Add", action, 34.0, 16.0, false)
    if add_error != ok { ret (zero, add_error) }
    let (menu, menu_error) = control.linux_svg_toggle(a, 12u64, t, adwicon.open_menu(), "Menu", action, 34.0, 16.0, false)
    if menu_error != ok { ret (zero, menu_error) }
    let (starts, starts_error) = mem.alloc[widget.Node](a, 1usize)
    if starts_error != ok { ret (zero, starts_error) }
    let (ends, ends_error) = mem.alloc[widget.Node](a, 1usize)
    if ends_error != ok { ret (zero, ends_error) }
    starts[0usize] = add
    ends[0usize] = menu
    let (bar, bar_error) = navigation.linux_header_bar(a, 1000u64, t, "Title", "", starts[0usize..1usize], ends[0usize..1usize], 120.0, 420.0)
    if bar_error != ok { ret (zero, bar_error) }
    let (layers, layers_error) = mem.alloc[widget.Node](a, 4usize)
    if layers_error != ok { ret (zero, layers_error) }
    layers[0usize] = bar
    let controls = [3]str{ adwicon.window_minimize(), adwicon.window_maximize(), adwicon.window_close() }
    var i = 0usize
    while i < 3usize {
        let (disc, disc_error) = window_control(a, t, controls[i], 311.0 + 37.0 * f32(i))
        if disc_error != ok { ret (zero, disc_error) }
        layers[1usize + i] = disc
        i += 1usize
    }
    ret (widget.stack(0u64, control.sized_style(420.0, 47.0), layers[0usize..4usize]), ok)
}

fn rule_options() -> control.DividerOptions {
    var options = control.divider_options()
    options.axis = .Vertical
    options.length = 34.0
    options.thick = 1.0
    ret options
}

// Five flat icon buttons (new, open, save, cut, copy) round a separator: 6 px in, 12 apart, the separator a 34 high line.
fn toolbar_row(a: *mem.Arena, t: *const control.Theme, action: *const widget.Submit) -> (widget.Node, err) {
    let icons = [5]str{ adwicon.document_new(), adwicon.document_open(), adwicon.document_save(), adwicon.edit_cut(), adwicon.edit_copy() }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 6usize)
    if parts_error != ok { ret (zero, parts_error) }
    var at = 0usize
    var i = 0usize
    while i < 5usize {
        if i == 3usize {
            let (line, line_error) = control.divider_of(a, 3000u64, t, rule_options())
            if line_error != ok { ret (zero, line_error) }
            parts[at] = line
            at += 1usize
        }
        let (one, one_error) = control.linux_svg_toggle(a, 2000u64 + u64(i), t, icons[i], "Tool", action, 34.0, 16.0, false)
        if one_error != ok { ret (zero, one_error) }
        parts[at] = one
        at += 1usize
        i += 1usize
    }
    var row = control.sized_style(243.0, 46.0)
    row.padding = style.EdgeLengths { left: style.Length { Px: 6.0 }, top: style.Length { Px: 6.0 }, right: style.Length { Px: 6.0 }, bottom: style.Length { Px: 6.0 } }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 12.0 }, row, parts[0usize..at]), ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    var i = 0usize
    while i < 14usize {
        var node: widget.Node = zero
        var w: f32 = 34.0
        var h: f32 = 34.0
        var caption = "toolbar"
        var drive: looks.Drive = .None
        let key = u64(i + 1usize) * 100u64
        if i < 10usize {
            let state = i % 5usize
            var options = control.button_options()
            options.enabled = state != 4usize
            options.variant = .Tonal
            caption = "icon"
            if i >= 5usize {
                options.variant = .Plain
                caption = "flat icon"
            }
            let (made, made_error) = control.button_with_svg(a, key, t, adwicon.edit_copy(), "", &actions[0usize], options)
            if made_error != ok { ret (0usize, made_error) }
            node = made
            if state == 1usize { drive = .Hover }
            if state == 2usize { drive = .Press }
            if state == 3usize { drive = .Focus }
        } else if i < 12usize {
            w = 82.0
            var options = control.button_options()
            options.variant = .Tonal
            caption = "toggle off"
            if i == 10usize { caption = "toggle on" }
            let (made, made_error) = control.toggle_button(a, key, t, "Toggle", i == 10usize, &actions[0usize], options)
            if made_error != ok { ret (0usize, made_error) }
            node = made
        } else if i == 12usize {
            w = 420.0
            h = 47.0
            caption = "header bar"
            let (made, made_error) = header(a, t, &actions[0usize])
            if made_error != ok { ret (0usize, made_error) }
            node = made
        } else {
            w = 243.0
            h = 46.0
            let (made, made_error) = toolbar_row(a, t, &actions[0usize])
            if made_error != ok { ret (0usize, made_error) }
            node = made
        }
        let x = f32(usize(430.0 - w) / 2usize)
        let y = f32(usize(60.0 - h) / 2usize)
        let held = widget.positioned(0u64, x, y, control.sized_style(w, h), control.widget_one_of(a, node))
        cells[i] = looks.Cell { caption: caption, node: widget.stack(0u64, control.sized_style(430.0, 60.0), control.widget_one_of(a, held)), drive: drive }
        i += 1usize
    }
    ret (14usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "toolbar_button", cells: 14usize, columns: 2usize, cell_w: 430.0, cell_h: 60.0, ctx: zero, build: build }
    ret looks.run_linux(a, &sheet)
}
