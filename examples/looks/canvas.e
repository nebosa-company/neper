// The canvas frame (control.framed_canvas), docs/ui/looks/<look>/canvas.png in all ten looks. The frame is a surface with an
// outline-variant edge and the theme's medium radius around the caller's own paint; here the paint is a small bar chart in
// the theme's primary, secondary and outline-variant roles. Cells: framed, framed with the chart padding, bare (a card's
// media), disabled, a small canvas and a wide one. A canvas is not interactive (the pressable form is overlay.interactive_canvas),
// so there is no hover, focus or pressed cell. Derived through the shared tokens; no platform reference was compared.

use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

type Plot = struct { bar: paint.Color, other: paint.Color, grid: paint.Color }

fn plot_measure(ctx: *void, limits: ui_layout.Constraints) -> geometry.Size {
    ret geometry.Size { width: 0.0, height: 0.0 }
}

fn fill(b: *scene.Builder, x: f32, y: f32, w: f32, h: f32, c: paint.Color) -> err {
    ret scene.push(b, scene.Command { FillRect: scene.FillRect { rect: geometry.Rect { x: x, y: y, width: w, height: h }, brush: paint.Brush { Solid: c } } })
}

fn plot_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let p = mem.cast[*Plot](ctx)
    var line = 0usize
    while line < 4usize {
        try fill(b, area.x, area.y + area.height * f32(line) / 4.0, area.width, 1.0, p.grid)
        line += 1usize
    }
    let heights = [6]f32{ 0.45, 0.70, 0.55, 0.90, 0.35, 0.65 }
    let slot = area.width / 6.0
    var i = 0usize
    while i < 6usize {
        let h = (area.height - 2.0) * heights[i]
        var c = p.bar
        if i == 3usize { c = p.other }
        try fill(b, area.x + slot * f32(i) + slot * 0.18, area.y + area.height - h, slot * 0.64, h, c)
        i += 1usize
    }
    ret ok
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [6]str{ "framed", "padded 16", "bare", "disabled", "small", "wide" }
    let widths = [6]f32{ 200.0, 200.0, 200.0, 200.0, 96.0, 280.0 }
    let heights = [6]f32{ 120.0, 120.0, 120.0, 120.0, 64.0, 96.0 }
    var i = 0usize
    while i < 6usize {
        let (plots, plots_error) = mem.alloc[Plot](a, 1usize)
        if plots_error != ok { ret (0usize, plots_error) }
        plots[0usize] = Plot { bar: style.color(t.tokens, .Primary), other: style.color(t.tokens, .Secondary), grid: style.color(t.tokens, .OutlineVariant) }
        let custom = widget.Custom { ctx: mem.cast[*void](&plots[0usize]), measure: plot_measure, paint: plot_paint, state: widget.bytes_of[Plot](&plots[0usize]) }
        var options = control.canvas_options()
        options.width = widths[i]
        options.height = heights[i]
        options.label = "Sales by month"
        if i == 1usize { options.padding = 16.0 }
        if i == 2usize { options.bare = true }
        if i == 3usize { options.enabled = false }
        let (node, node_error) = control.framed_canvas(a, u64(i + 1usize) * 100u64, t, custom, options)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: .None }
        i += 1usize
    }
    ret (6usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "canvas", cells: 6usize, columns: 3usize, cell_w: 300.0, cell_h: 140.0, ctx: zero, build: build }
    try looks.run_all(a, &sheet)
    try looks.run_linux(a, &sheet)
    try looks.run_cupertino(a, &sheet)
    ret looks.run_material(a, &sheet)
}
