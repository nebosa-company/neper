// The Linux look's spinner (round 22, worker lb): GtkSpinner is libadwaita's `process-working-symbolic` icon (a spiral outline, drawn at
// 2 x as a 32 x 32 raster) turned about its centre by the animation, the raster filtered bilinearly as GTK turns a texture. The tile is the
// icon's own SVG (Adwaita icon theme) filled non-zero by scripts/gen_spinner_lb.py, not a capture; the rest angle is the one the library's
// still capture shows (130.25 degrees clockwise), and the head turns on from there.

use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.math
use e.mem
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.widget

error TooLarge

type Spin = struct { ink: paint.Color, turn: f32 }

fn tile() -> [1024]u8 {
    ret [1024]u8{
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 15, 85, 147, 181, 216, 208, 108, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 42, 161, 250, 255, 255, 255, 255, 255, 255, 110, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 9, 143, 253, 255, 255, 255, 255, 255, 255, 255, 255, 211, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 28, 213, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 215, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 36, 227, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 127, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 13, 214, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 236, 135, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 165, 255, 255, 255, 255, 255, 255, 255, 221, 114, 43, 11, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 60, 255, 255, 255, 255, 255, 255, 252, 123, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 193, 255, 255, 255, 255, 255, 249, 78, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 6, 5, 0, 0, 0,
        0, 0, 37, 254, 255, 255, 255, 255, 255, 107, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 4, 9, 7, 10, 3, 0, 0,
        0, 0, 123, 255, 255, 255, 255, 255, 201, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 11, 12, 14, 14, 16, 4, 0, 0,
        0, 0, 166, 252, 251, 253, 254, 254, 96, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 17, 15, 19, 22, 21, 15, 0, 0,
        0, 0, 205, 245, 247, 250, 249, 249, 29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 21, 24, 25, 23, 27, 20, 0, 0,
        0, 0, 223, 223, 255, 239, 239, 254, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 32, 31, 30, 33, 30, 23, 0, 0,
        0, 0, 223, 223, 245, 238, 230, 246, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 35, 38, 37, 33, 37, 29, 0, 0,
        0, 0, 178, 232, 232, 228, 227, 225, 40, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 12, 47, 41, 41, 45, 38, 28, 0, 0,
        0, 0, 142, 226, 224, 224, 219, 220, 94, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 25, 51, 52, 52, 52, 50, 28, 0, 0,
        0, 0, 86, 223, 220, 219, 215, 215, 176, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 50, 62, 58, 58, 53, 51, 12, 0, 0,
        0, 0, 23, 212, 211, 212, 213, 209, 204, 84, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 31, 70, 68, 64, 61, 58, 50, 8, 0, 0,
        0, 0, 0, 151, 209, 208, 205, 203, 195, 185, 40, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 22, 80, 75, 72, 69, 66, 62, 43, 0, 0, 0,
        0, 0, 0, 46, 206, 204, 200, 194, 194, 180, 174, 63, 0, 0, 0, 0, 0, 0, 0, 2, 41, 93, 81, 85, 74, 75, 74, 65, 15, 0, 0, 0,
        0, 0, 0, 0, 129, 202, 194, 190, 183, 188, 175, 173, 131, 53, 36, 16, 20, 32, 49, 87, 103, 94, 95, 83, 88, 73, 75, 44, 0, 0, 0, 0,
        0, 0, 0, 0, 15, 168, 193, 186, 186, 176, 173, 168, 163, 153, 149, 141, 133, 126, 117, 114, 105, 99, 89, 94, 83, 84, 65, 9, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 36, 171, 183, 179, 177, 170, 164, 163, 153, 142, 137, 135, 124, 117, 118, 110, 103, 99, 88, 89, 82, 15, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 33, 164, 180, 174, 168, 159, 158, 148, 147, 147, 131, 126, 125, 118, 109, 106, 102, 98, 78, 17, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 19, 123, 169, 166, 158, 155, 150, 138, 141, 130, 126, 125, 119, 111, 106, 103, 63, 11, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 1, 50, 127, 158, 155, 148, 141, 134, 134, 128, 127, 119, 110, 79, 24, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 28, 57, 105, 109, 105, 96, 98, 82, 34, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    }
}

fn measure(ctx: *void, limits: ui_layout.Constraints) -> geometry.Size {
    ret geometry.Size { width: 32.0, height: 32.0 }
}

// The tile at (x, y) in its own pixels, bilinear, 0 outside.
fn sample(px: [1024]u8, x: f32, y: f32) -> f32 {
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
        if cx >= 0 && cx < 32 && cy >= 0 && cy < 32 { total += wx * wy * f32(px[usize(cy * 32 + cx)]) }
        k += 1
    }
    ret total / 255.0
}

fn paint_spin(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let spin = mem.cast[*Spin](ctx)
    let scale = scene.builder_scale(b)
    let px = tile()
    let angle = 2.2733 + spin.turn * 6.2831855
    let c = math.cos[f32](angle)
    let s = math.sin[f32](angle)
    let side = i32(32.0 * scale + 0.5)
    var y: i32 = 0
    while y < side {
        var levels: [192]u8 = zero
        var x: i32 = 0
        let n = usize(side)
        while x < side {
            let lx = (f32(x) + 0.5) / scale - 16.0
            let ly = (f32(y) + 0.5) / scale - 16.0
            let sx = c * lx + s * ly + 15.5
            let sy = 0.0 - s * lx + c * ly + 15.5
            var m = sample(px, sx, sy)
            if m > 1.0 { m = 1.0 }
            levels[usize(x)] = u8(m * spin.ink.alpha * 255.0 + 0.5)
            x += 1
        }
        var at: usize = 0usize
        while at < n {
            let level = levels[at]
            if level == 0u8 {
                at += 1usize
                continue
            }
            var run: usize = 1usize
            while at + run < n && levels[at + run] == level { run += 1usize }
            try scene.push(b, scene.Command { FillRect: scene.FillRect { rect: geometry.Rect { x: area.x + f32(at) / scale, y: area.y + f32(y) / scale, width: f32(run) / scale, height: 1.0 / scale }, brush: paint.Brush { Solid: paint.Color { red: spin.ink.red, green: spin.ink.green, blue: spin.ink.blue, alpha: f32(level) / 255.0 } } } })
            at += run
        }
        y += 1
    }
    ret ok
}

// A 32 x 32 node painting the spinner at `turn` turns past its rest angle in `ink`.
fn node(a: *mem.Arena, key: widget.Key, ink: paint.Color, turn: f32) -> (widget.Node, err) {
    let (spins, spins_error) = mem.alloc[Spin](a, 1usize)
    if spins_error != ok { ret (zero, TooLarge) }
    spins[0usize] = Spin { ink: ink, turn: turn }
    var s = style.defaults()
    s.width = style.Length { Px: 32.0 }
    s.height = style.Length { Px: 32.0 }
    var none: []const widget.Node = zero
    ret (widget.Node { key: key, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&spins[0usize]), measure: measure, paint: paint_spin, state: widget.bytes_of[Spin](&spins[0usize]) } }, style: s, children: none }, ok)
}
