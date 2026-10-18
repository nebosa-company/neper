// The elevation shadows of the Android look (Material 3 levels 1 to 5), drawn, not baked: a rounded rectangle's shade is a stack of
// Gaussian layers (the model of linuxshadow_l2.e: a layer is the rectangle moved down `oy`, grown by `spread`, blurred by `sigma`, laid on as
// black at `alpha`; the blur of an edge is an error function of the signed distance, so a pixel's shade is a few square roots and exponentials
// and the result is the same at every size and scale). Every level is two layers, fitted to Material Web's own md-elevation renders by
// scripts/material/fit_shadow.py (docs/ui/looks/ref/material/*/elevation-level1..5-rest; rms 0.0002 to 0.0015 of full scale); no pixel of the
// captures is in this file. The widget runtime calls `paint_level` under a box whose style asks for `shade` > 0 (so this module imports nothing
// from widget); the body is the box's own face, which the shade never covers (its coverage is subtracted).

use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.math

type Layer = struct { oy: f32, spread: f32, sigma: f32, alpha: f32 }

// erfc for x >= 0 (Abramowitz and Stegun 7.1.26, within 1.5e-7).
fn erfc_pos(x: f32) -> f32 {
    if x > 5.0 { ret 0.0 }
    let t = 1.0 / (1.0 + 0.3275911 * x)
    let poly = t * (0.254829592 + t * ((0.0 - 0.284496736) + t * (1.421413741 + t * ((0.0 - 1.453152027) + t * 1.061405429))))
    ret poly * math.exp[f32](0.0 - x * x)
}

// alpha * the blurred step at signed distance `d` (negative inside the shape).
fn blur_step(d: f32, sigma: f32, alpha: f32) -> f32 {
    let x = d / (sigma * 1.41421356)
    if x >= 0.0 { ret 0.5 * alpha * erfc_pos(x) }
    ret 0.5 * alpha * (2.0 - erfc_pos(0.0 - x))
}

// The signed distance from (px, py) to the rounded rectangle [l, r] x [t, bt] with corners `rad`.
fn sdf(px: f32, py: f32, l: f32, t: f32, r: f32, bt: f32, rad: f32) -> f32 {
    let qx = math.abs[f32](px - (l + r) * 0.5) - (r - l) * 0.5 + rad
    let qy = math.abs[f32](py - (t + bt) * 0.5) - (bt - t) * 0.5 + rad
    let ox = math.max[f32](qx, 0.0)
    let oy = math.max[f32](qy, 0.0)
    ret math.sqrt[f32](ox * ox + oy * oy) + math.min[f32](math.max[f32](qx, qy), 0.0) - rad
}

fn layer_of(level: u8, k: usize) -> Layer {
    if level <= 1u8 {
        if k == 0usize { ret Layer { oy: 0.9942, spread: 0.0 - 0.2108, sigma: 1.3601, alpha: 0.5477 } }
        ret Layer { oy: 1.0105, spread: 3.2642, sigma: 0.4276, alpha: 0.0071 }
    }
    if level == 2u8 {
        if k == 0usize { ret Layer { oy: 1.1565, spread: 0.0 - 0.4321, sigma: 1.1034, alpha: 0.4020 } }
        ret Layer { oy: 2.0313, spread: 2.8881, sigma: 2.6242, alpha: 0.1131 }
    }
    if level == 3u8 {
        if k == 0usize { ret Layer { oy: 1.2462, spread: 0.0 - 0.2383, sigma: 1.5004, alpha: 0.3371 } }
        ret Layer { oy: 4.0487, spread: 3.6885, sigma: 3.6524, alpha: 0.1253 }
    }
    if level == 4u8 {
        if k == 0usize { ret Layer { oy: 2.1060, spread: 0.0 - 0.1560, sigma: 1.4124, alpha: 0.3216 } }
        ret Layer { oy: 6.0910, spread: 3.9654, sigma: 4.2823, alpha: 0.1442 }
    }
    if k == 0usize { ret Layer { oy: 4.2761, spread: 0.0 - 0.1824, sigma: 2.2760, alpha: 0.3192 } }
    ret Layer { oy: 8.1716, spread: 6.2625, sigma: 5.1341, alpha: 0.1363 }
}

// The shade at (px, py) of the body [l, r] x [t, bt]: 1 - the product of what each layer leaves.
fn shade_at(level: u8, radius: f32, px: f32, py: f32, l: f32, t: f32, r: f32, bt: f32) -> f32 {
    var left: f32 = 1.0
    var k = 0usize
    while k < 2usize {
        let layer = layer_of(level, k)
        var rad = radius + layer.spread
        if rad < 0.0 { rad = 0.0 }
        let d = sdf(px, py, l - layer.spread, t - layer.spread + layer.oy, r + layer.spread, bt + layer.spread + layer.oy, rad)
        left = left * (1.0 - blur_step(d, layer.sigma, layer.alpha))
        k += 1usize
    }
    ret 1.0 - left
}

fn edge(v: f32, scale: f32) -> f32 {
    ret math.floor[f32](v * scale + 0.5) / scale
}

// A solid rectangle in logical px, its edges moved to whole device pixels (as e.ui.winpx.fill does).
fn fill(b: *scene.Builder, x: f32, y: f32, w: f32, h: f32, color: paint.Color) -> err {
    let scale = scene.builder_scale(b)
    var rect = geometry.Rect { x: x, y: y, width: w, height: h }
    if scale != 1.0 || scene.pixel_exact_at_one_on() {
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

// One row of cells from x0, n of them: the quantised shade (units of 1/512), the body's coverage taken out.
fn row_cells(level: u8, radius: f32, yc: f32, x0: i32, n: i32, l: f32, t: f32, r: f32, bt: f32, shaded: []u16) {
    var i: i32 = 0
    while i < n {
        let px = f32(x0 + i) + 0.5
        let c = math.max[f32](0.0, math.min[f32](1.0, 0.5 - sdf(px, yc, l, t, r, bt, radius)))
        var s: f32 = 0.0
        if c < 1.0 { s = shade_at(level, radius, px, yc, l, t, r, bt) * (1.0 - c) }
        shaded[usize(i)] = u16(s * 512.0 + 0.5)
        i += 1
    }
}

fn lay_row(b: *scene.Builder, y: f32, rows: f32, x0: i32, n: i32, shaded: []const u16) -> err {
    var i: i32 = 0
    while i < n {
        let qs = shaded[usize(i)]
        var run: i32 = 1
        while i + run < n && shaded[usize(i + run)] == qs { run += 1 }
        if qs > 0u16 { try fill(b, f32(x0 + i), y, f32(run), rows, paint.rgba(0.0, 0.0, 0.0, f32(qs) / 512.0)) }
        i += run
    }
    ret ok
}

// The shade of `level` (1 to 5) round the rounded rectangle `body` with corners of `radius`, laid under it.
fn paint_level(b: *scene.Builder, body: geometry.Rect, radius: f32, level: u8) -> err {
    let l = body.x
    let t = body.y
    let r = body.x + body.width
    let bt = body.y + body.height
    let x0 = i32(math.floor[f32](l - 40.0))
    let x1 = i32(math.ceil[f32](r + 40.0))
    let y0 = i32(math.floor[f32](t - 40.0))
    let y1 = i32(math.ceil[f32](bt + 40.0))
    let n = x1 - x0
    if n <= 0 || n > 640 { ret ok }
    // Rows clear of every layer's corner arcs are all one row (the shade there is a function of x alone).
    let mid0 = i32(math.ceil[f32](t + radius + 9.0 - 0.5))
    let mid1 = i32(math.floor[f32](bt - radius - 0.5)) + 1
    var shaded: [640]u16 = zero
    var y = y0
    while y < y1 {
        if y >= mid0 && y < mid1 {
            row_cells(level, radius, f32(mid0) + 0.5, x0, n, l, t, r, bt, shaded[0usize..640usize])
            try lay_row(b, f32(mid0), f32(mid1 - mid0), x0, n, shaded[0usize..640usize])
            y = mid1
            continue
        }
        row_cells(level, radius, f32(y) + 0.5, x0, n, l, t, r, bt, shaded[0usize..640usize])
        try lay_row(b, f32(y), 1.0, x0, n, shaded[0usize..640usize])
        y += 1
    }
    ret ok
}
