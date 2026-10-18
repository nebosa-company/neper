// libadwaita's own check and radio marks (assets/check-symbolic.symbolic.png and bullet-symbolic.symbolic.png, 14 x 14 alpha masks of the
// icon's SVG), which GTK draws 1:1 in a 20 x 20 indicator at 100 %. At any other scale the vector icons stand in. Round 22, worker lb.

use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.math
use e.mem
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.widget

error TooLarge

type Mark = struct { color: paint.Color, kind: u8 }

fn tick_mask() -> [196]u8 {
    ret [196]u8{
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 35, 91, 6,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 40, 235, 255, 116,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 26, 224, 255, 254, 78,
        0, 0, 0, 0, 0, 0, 0, 0, 14, 207, 255, 255, 123, 0,
        23, 215, 199, 23, 0, 0, 0, 8, 192, 255, 255, 149, 0, 0,
        62, 255, 255, 212, 22, 0, 2, 171, 255, 255, 172, 3, 0, 0,
        1, 153, 255, 255, 211, 21, 149, 255, 255, 192, 8, 0, 0, 0,
        0, 2, 155, 255, 255, 234, 255, 255, 209, 16, 0, 0, 0, 0,
        0, 0, 1, 150, 255, 255, 255, 227, 29, 0, 0, 0, 0, 0,
        0, 0, 0, 1, 151, 255, 236, 40, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 2, 149, 56, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    }
}

fn bullet_mask() -> [196]u8 {
    ret [196]u8{
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 29, 172, 242, 242, 174, 39, 0, 0, 0, 0,
        0, 0, 0, 29, 237, 255, 255, 255, 255, 237, 28, 0, 0, 0,
        0, 0, 0, 172, 255, 255, 255, 255, 255, 255, 170, 0, 0, 0,
        0, 0, 0, 242, 255, 255, 255, 255, 255, 255, 241, 0, 0, 0,
        0, 0, 0, 242, 255, 255, 255, 255, 255, 255, 240, 0, 0, 0,
        0, 0, 0, 174, 255, 255, 255, 255, 255, 255, 172, 0, 0, 0,
        0, 0, 0, 39, 237, 255, 255, 255, 255, 237, 37, 0, 0, 0,
        0, 0, 0, 0, 28, 170, 241, 241, 172, 37, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    }
}

fn measure(ctx: *void, limits: ui_layout.Constraints) -> geometry.Size {
    ret geometry.Size { width: 14.0, height: 14.0 }
}

fn sample(mask: [196]u8, x: f32, y: f32) -> f32 {
    let x0 = math.floor[f32](x)
    let y0 = math.floor[f32](y)
    let fx = x - x0
    let fy = y - y0
    var total: f32 = 0.0
    var k: i32 = 0
    while k < 4 {
        let cx = i32(x0) + (k % 2)
        let cy = i32(y0) + (k / 2)
        var wx = 1.0 - fx
        if k % 2 == 1 { wx = fx }
        var wy = 1.0 - fy
        if k / 2 == 1 { wy = fy }
        if cx >= 0 && cx < 14 && cy >= 0 && cy < 14 { total += wx * wy * f32(mask[usize(cy * 14 + cx)]) }
        k += 1
    }
    ret total / 255.0
}

// At 100 % the mask's pixels as they are; at another scale the same mask filtered bilinearly (GTK would pick the @2 asset).
fn paint_mark(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let mark = mem.cast[*Mark](ctx)
    var mask = tick_mask()
    if mark.kind == 1u8 { mask = bullet_mask() }
    let scale = scene.builder_scale(b)
    let ox = math.floor[f32](area.x * scale + 0.5) / scale
    let oy = math.floor[f32](area.y * scale + 0.5) / scale
    let side = i32(14.0 * scale + 0.5)
    var y: i32 = 0
    while y < side {
        var levels: [32]u8 = zero
        var x: i32 = 0
        while x < side && x < 32 {
            let m = sample(mask, (f32(x) + 0.5) / scale - 0.5, (f32(y) + 0.5) / scale - 0.5)
            levels[usize(x)] = u8(m * mark.color.alpha * 255.0 + 0.5)
            x += 1
        }
        var at: usize = 0usize
        let n = usize(side)
        while at < n && at < 32usize {
            let level = levels[at]
            if level == 0u8 {
                at += 1usize
                continue
            }
            var run: usize = 1usize
            while at + run < n && at + run < 32usize && levels[at + run] == level { run += 1usize }
            try scene.push(b, scene.Command { FillRect: scene.FillRect { rect: geometry.Rect { x: ox + f32(at) / scale, y: oy + f32(y) / scale, width: f32(run) / scale, height: 1.0 / scale }, brush: paint.Brush { Solid: paint.Color { red: mark.color.red, green: mark.color.green, blue: mark.color.blue, alpha: f32(level) / 255.0 } } } })
            at += run
        }
        y += 1
    }
    ret ok
}

// The 14 x 14 mark node: `kind` 0 the tick, 1 the bullet.
fn mark_node(a: *mem.Arena, kind: u8, color: paint.Color) -> (widget.Node, err) {
    let (marks, marks_error) = mem.alloc[Mark](a, 1usize)
    if marks_error != ok { ret (zero, TooLarge) }
    marks[0usize] = Mark { color: color, kind: kind }
    var s = style.defaults()
    s.width = style.Length { Px: 14.0 }
    s.height = style.Length { Px: 14.0 }
    var none: []const widget.Node = zero
    ret (widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&marks[0usize]), measure: measure, paint: paint_mark, state: widget.bytes_of[Mark](&marks[0usize]) } }, style: s, children: none }, ok)
}
