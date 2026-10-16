// Round 10: a pixel tile as a node, for the marks and chrome read from the native Windows 11 captures (e.ui.winnative).
// A value is 0xAARRGGBB; alpha 0 is not painted, a partial alpha is the edge's coverage over whatever lies below.
// Every pixel goes through `winpx.fill`, so a scaled render shows a nearest-neighbour block with no seams.

use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.mem
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.winpx
use e.ui.widget

type Tile = struct { w: usize, h: usize, px: []const u32 }

fn tile_measure(ctx: *void, limits: ui_layout.Constraints) -> geometry.Size {
    ret geometry.Size { width: 0.0, height: 0.0 }
}

fn tile_color(v: u32) -> paint.Color {
    var c = style.hex_raw(v & 0xFFFFFFu32)
    let alpha = v >> 24u32
    if alpha != 0u32 && alpha < 255u32 { c.alpha = f32(alpha) / 255.0 }
    ret c
}

// Paints runs of equal pixels in a row as one rectangle.
fn tile_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let t = mem.cast[*Tile](ctx)
    let ox = f32(i32(area.x + 0.5))
    let oy = f32(i32(area.y + 0.5))
    var r = 0usize
    while r < t.h {
        var c = 0usize
        while c < t.w {
            let v = t.px[r * t.w + c]
            if (v >> 24u32) == 0u32 {
                c += 1usize
                continue
            }
            var run = 1usize
            while c + run < t.w && t.px[r * t.w + c + run] == v { run += 1usize }
            try winpx.fill(b, ox + f32(c), oy + f32(r), f32(run), 1.0, tile_color(v))
            c += run
        }
        r += 1usize
    }
    ret ok
}

// The tile `px` (`w` x `h`) as a node of that size. The pixels are copied into the arena.
fn tile_node(a: *mem.Arena, w: usize, h: usize, px: []const u32) -> (widget.Node, err) {
    let (made, made_error) = mem.alloc[Tile](a, 1usize)
    if made_error != ok { ret (zero, made_error) }
    let (copy, copy_error) = mem.alloc[u32](a, w * h)
    if copy_error != ok { ret (zero, copy_error) }
    var i = 0usize
    while i < w * h {
        copy[i] = px[i]
        i += 1usize
    }
    made[0usize] = Tile { w: w, h: h, px: copy }
    var s = style.defaults()
    s.width = style.Length { Px: f32(w) }
    s.height = style.Length { Px: f32(h) }
    var none: []const widget.Node = zero
    ret (widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&made[0usize]), measure: tile_measure, paint: tile_paint, state: widget.bytes_of[Tile](&made[0usize]) } }, style: s, children: none }, ok)
}
