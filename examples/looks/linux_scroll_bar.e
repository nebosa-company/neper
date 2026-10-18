// The Linux look's scroll bar against the real GTK 4.14 / libadwaita 1.5: lone horizontal and vertical bars (rest, hovered,
// insensitive), a scrolled window with overlay indicators (hidden at rest) and one with both classic bars,
// docs/ui/looks/linux[-dark]/scroll_bar.png (reference: scripts/linux_cmp_l3.py). Run from the repository root.

use e.gfx.paint
use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

// A scrolled window of 160 x 120: a 1 px #dddddd frame (what the library's gallery draws round it) over the window colour.
fn frame_node(t: *const control.Theme) -> widget.Node {
    var s = control.sized_style(160.0, 120.0)
    s.border = style.Border { width: 1.0, color: control.linux_rule(t) }
    s.position = .Absolute
    ret widget.box(0u64, s, zero)
}

fn bar_at(a: *mem.Arena, node: widget.Node, x: f32, y: f32) -> widget.Node {
    var s = style.defaults()
    s.position = .Absolute
    s.margin = style.EdgeLengths { left: style.Length { Px: x }, top: style.Length { Px: y }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    ret widget.box(0u64, s, control.widget_one_of(a, node))
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [8]str{ "h rest", "v rest", "h hover", "v hover", "h insensitive", "v insensitive", "overlay", "classic" }
    var i = 0usize
    while i < 8usize {
        var node: widget.Node = zero
        var w: f32 = 200.0
        var h: f32 = 20.0
        let key = u64(i + 1usize) * 100u64
        if i < 6usize {
            if i % 2usize == 0usize {
                let (made, made_error) = control.linux_scroll_bar(a, key, t, false, 200.0, 727.3, 160.0, i < 4usize)
                if made_error != ok { ret (0usize, made_error) }
                node = made
            } else {
                w = 20.0
                h = 160.0
                let (made, made_error) = control.linux_scroll_bar(a, key, t, true, 160.0, 595.3, 134.0, i < 4usize)
                if made_error != ok { ret (0usize, made_error) }
                node = made
            }
        } else if i == 6usize {
            w = 160.0
            h = 120.0
            var block = control.sized_style(158.0, 400.0)
            block.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
            let (area, area_error) = control.scroll_area(a, key, t, .Vertical, 158.0, 118.0, 0.0, 400.0, control.widget_one_of(a, widget.box(0u64, block, zero)))
            if area_error != ok { ret (0usize, area_error) }
            let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
            if parts_error != ok { ret (0usize, parts_error) }
            parts[0usize] = frame_node(t)
            parts[1usize] = bar_at(a, area, 1.0, 1.0)
            node = widget.stack(0u64, control.sized_style(160.0, 120.0), parts[0usize..2usize])
        } else {
            w = 160.0
            h = 120.0
            let (vbar, vbar_error) = control.linux_scroll_bar(a, key, t, true, 98.0, 240.1, 17.15, true)
            if vbar_error != ok { ret (0usize, vbar_error) }
            let (hbar, hbar_error) = control.linux_scroll_bar(a, key + 50u64, t, false, 138.0, 476.1, 24.15, true)
            if hbar_error != ok { ret (0usize, hbar_error) }
            let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
            if parts_error != ok { ret (0usize, parts_error) }
            parts[0usize] = frame_node(t)
            parts[1usize] = bar_at(a, vbar, 139.0, 1.0)
            parts[2usize] = bar_at(a, hbar, 1.0, 99.0)
            node = widget.stack(0u64, control.sized_style(160.0, 120.0), parts[0usize..3usize])
        }
        let x = f32(usize(210.0 - w) / 2usize)
        let y = f32(usize(170.0 - h) / 2usize)
        let held = widget.positioned(0u64, x, y, control.sized_style(w, h), control.widget_one_of(a, node))
        var drive: looks.Drive = .None
        if i == 2usize || i == 3usize { drive = .Hover }
        cells[i] = looks.Cell { caption: names[i], node: widget.stack(0u64, control.sized_style(210.0, 170.0), control.widget_one_of(a, held)), drive: drive }
        i += 1usize
    }
    ret (8usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "scroll_bar", cells: 8usize, columns: 2usize, cell_w: 210.0, cell_h: 170.0, ctx: zero, build: build }
    ret looks.run_linux(a, &sheet)
}
