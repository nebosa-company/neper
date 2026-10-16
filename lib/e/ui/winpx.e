// Pixel art at any device scale. The Windows look draws controls from tiles baked from 100 % captures; at a render
// scale of 1.25, 1.5 or 2 a 1 px rectangle lands on fractional device pixels and shows as a dotted seam, a lost
// border or blur. `fill` places a rectangle on whole device pixels instead: each edge is rounded to the nearest
// device pixel, so the tile's neighbours share edges (no seams, no overlaps) and every pixel of the tile is a
// nearest-neighbour scaled block. At scale 1 it is the plain rectangle, so the 100 % renders are unchanged.

use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.math
use e.mem
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.widget

fn edge(v: f32, scale: f32) -> f32 {
    ret math.floor[f32](v * scale + 0.5) / scale
}

// A solid rectangle in logical px, its edges moved to whole device pixels (at least one device pixel wide and high).
fn fill(b: *scene.Builder, x: f32, y: f32, w: f32, h: f32, color: paint.Color) -> err {
    let scale = scene.builder_scale(b)
    var rect = geometry.Rect { x: x, y: y, width: w, height: h }
    if scale != 1.0 {
        let x0 = edge(x, scale)
        let y0 = edge(y, scale)
        var x1 = edge(x + w, scale)
        var y1 = edge(y + h, scale)
        if x1 <= x0 { x1 = x0 + 1.0 / scale }
        if y1 <= y0 { y1 = y0 + 1.0 / scale }
        rect = geometry.Rect { x: x0, y: y0, width: x1 - x0, height: y1 - y0 }
    }
    ret scene.push(b, scene.Command { FillRect: scene.FillRect { rect: rect, brush: paint.Brush { Solid: color } } })
}

// ---- nodes ------------------------------------------------------------------------------------------------------

type Dots = struct { count: usize, codes: []const u8, colors: []const paint.Color, parity: u32, color: paint.Color, across: u32, down: u32, dither: bool }

fn dots_measure(ctx: *void, limits: ui_layout.Constraints) -> geometry.Size {
    ret geometry.Size { width: 0.0, height: 0.0 }
}

// The pixels of a dots node or a dither, each on whole device pixels (`fill`), from the node's origin.
fn dots_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let d = mem.cast[*Dots](ctx)
    if d.dither {
        var y = 0u32
        while y < d.down {
            var x = 0u32
            while x < d.across {
                if (x + y) % 2u32 == d.parity { try fill(b, area.x + f32(x), area.y + f32(y), 1.0, 1.0, d.color) }
                x += 1u32
            }
            y += 1u32
        }
        ret ok
    }
    var i = 0usize
    while i < d.count {
        let code = u32(d.codes[i])
        try fill(b, area.x + f32(code / 16u32), area.y + f32(code % 16u32), 1.0, 1.0, d.colors[i])
        i += 1usize
    }
    ret ok
}

fn dots_node(a: *mem.Arena, d: Dots, w: f32, h: f32) -> (widget.Node, err) {
    let (held, held_error) = mem.alloc[Dots](a, 1usize)
    if held_error != ok { ret (zero, held_error) }
    held[0usize] = d
    var s = style.defaults()
    s.width = style.Length { Px: w }
    s.height = style.Length { Px: h }
    var none: []const widget.Node = zero
    ret (widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&held[0usize]), measure: dots_measure, paint: dots_paint, state: widget.bytes_of[Dots](&held[0usize]) } }, style: s, children: none }, ok)
}

// A bitmap of single pixels: pixel i at (codes[i] / 16, codes[i] % 16) in colors[i], painted in order.
fn sprite(a: *mem.Arena, codes: []const u8, colors: []const paint.Color, w: f32, h: f32) -> (widget.Node, err) {
    let (node, node_error) = dots_node(a, Dots { count: codes.len, codes: codes, colors: colors, parity: 0u32, color: colors[0usize], across: 0u32, down: 0u32, dither: false }, w, h)
    ret (node, node_error)
}

// Every other pixel of a `w` x `h` box, those where x + y has `parity` (0 or 1), in `color`.
fn dither(a: *mem.Arena, w: u32, h: u32, parity: u32, color: paint.Color) -> (widget.Node, err) {
    var none: []const u8 = zero
    var none_colors: []const paint.Color = zero
    let (node, node_error) = dots_node(a, Dots { count: 0usize, codes: none, colors: none_colors, parity: parity, color: color, across: w, down: h, dither: true }, f32(w), f32(h))
    ret (node, node_error)
}
