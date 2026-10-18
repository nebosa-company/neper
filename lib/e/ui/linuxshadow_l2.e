// The soft shadows of the Linux look (libadwaita 1.5), drawn, not baked: a rounded rectangle's shadow is a stack of layers, each the
// rectangle moved down `oy`, grown by `spread`, blurred by a Gaussian of `sigma` and laid on as black at `alpha`; the blur of a straight
// edge is an error function of the signed distance to the shape, so a pixel's shade is a few square roots and exponentials and the
// result is the same at every size and scale (a cell is one logical pixel). The layers are fitted to the GTK captures in
// docs/ui/looks/ref/linux (the popover of dropdown-open, the AdwAlertDialog of alert-dialog) by scripts/linux/fit_shadow.py; nothing of
// the captures' pixels is in this file. Two users: a popover (`node`: the body is drawn by the popover's own box, the node lays only the
// shade round it) and the alert card (`card_node`: the node draws the card's face too, so the rim pixels the fractional layout leaves are
// exact).

use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.math
use e.mem
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.winpx
use e.ui.widget

type Layer = struct { oy: f32, spread: f32, sigma: f32, alpha: f32 }

// The body rectangle is [area.x + rl, area.y + rt] wide `rw` and high `rh`, with corners of `radius`; `margin` px round it are shaded; `face` is painted (alpha = coverage) when `own_face`.
type Shade = struct { rl: f32, rt: f32, rw: f32, rh: f32, radius: f32, margin: f32, face: paint.Color, own_face: bool, count: usize, layers: [4]Layer }

fn measure(ctx: *void, limits: ui_layout.Constraints) -> geometry.Size {
    ret geometry.Size { width: 0.0, height: 0.0 }
}

// erfc for x >= 0 (Abramowitz and Stegun 7.1.26, within 1.5e-7).
fn erfc_pos(x: f32) -> f32 {
    if x > 5.0 { ret 0.0 }
    let t = 1.0 / (1.0 + 0.3275911 * x)
    let poly = t * (0.254829592 + t * ((0.0 - 0.284496736) + t * (1.421413741 + t * ((0.0 - 1.453152027) + t * 1.061405429))))
    ret poly * math.exp[f32](0.0 - x * x)
}

// alpha * the blurred step at signed distance `d` (negative inside the shape): alpha / 2 * erfc(d / (sigma * sqrt 2)).
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

// The layers' combined shade at (px, py): 1 - the product of what each leaves.
fn shade_at(sh: *Shade, px: f32, py: f32, l: f32, t: f32, r: f32, bt: f32) -> f32 {
    var left: f32 = 1.0
    var k = 0usize
    while k < sh.count {
        let layer = sh.layers[k]
        var rad = sh.radius + layer.spread
        if rad < 0.0 { rad = 0.0 }
        let d = sdf(px, py, l - layer.spread, t - layer.spread + layer.oy, r + layer.spread, bt + layer.spread + layer.oy, rad)
        left = left * (1.0 - blur_step(d, layer.sigma, layer.alpha))
        k += 1usize
    }
    ret 1.0 - left
}

// One row of cells from x0, n of them: the quantised shade (units of 1/512) and the face's coverage (units of 1/255).
fn row_cells(sh: *Shade, yc: f32, x0: i32, n: i32, l: f32, t: f32, r: f32, bt: f32, shaded: []u16, covered: []u8) {
    var i: i32 = 0
    while i < n {
        let px = f32(x0 + i) + 0.5
        let c = math.max[f32](0.0, math.min[f32](1.0, 0.5 - sdf(px, yc, l, t, r, bt, sh.radius)))
        var s: f32 = 0.0
        if c < 1.0 { s = shade_at(sh, px, yc, l, t, r, bt) }
        if !sh.own_face { s = s * (1.0 - c) }
        let qc = u8(c * 255.0 + 0.5)
        var qs = u16(s * 512.0 + 0.5)
        if qc == 255u8 { qs = 0u16 }
        shaded[usize(i)] = qs
        covered[usize(i)] = qc
        i += 1
    }
}

fn emit(b: *scene.Builder, sh: *Shade, x: f32, y: f32, w: f32, h: f32, qs: u16, qc: u8) -> err {
    if qs > 0u16 { try winpx.fill(b, x, y, w, h, paint.rgba(0.0, 0.0, 0.0, f32(qs) / 512.0)) }
    if sh.own_face && qc > 0u8 { try winpx.fill(b, x, y, w, h, paint.rgba(sh.face.red, sh.face.green, sh.face.blue, sh.face.alpha * f32(qc) / 255.0)) }
    ret ok
}

// A row (or, for the straight middle of the rectangle, `rows` equal rows) laid as runs of equal cells.
fn lay_row(b: *scene.Builder, sh: *Shade, y: f32, rows: f32, x0: i32, n: i32, shaded: []const u16, covered: []const u8) -> err {
    var i: i32 = 0
    while i < n {
        let qs = shaded[usize(i)]
        let qc = covered[usize(i)]
        var run: i32 = 1
        while i + run < n && shaded[usize(i + run)] == qs && covered[usize(i + run)] == qc { run += 1 }
        if qs > 0u16 || (sh.own_face && qc > 0u8) { try emit(b, sh, f32(x0 + i), y, f32(run), rows, qs, qc) }
        i += run
    }
    ret ok
}

fn shade_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let sh = mem.cast[*Shade](ctx)
    let l = area.x + sh.rl
    let t = area.y + sh.rt
    let r = l + sh.rw
    let bt = t + sh.rh
    let x0 = i32(math.floor[f32](l - sh.margin))
    let x1 = i32(math.ceil[f32](r + sh.margin))
    let y0 = i32(math.floor[f32](t - sh.margin))
    let y1 = i32(math.ceil[f32](bt + sh.margin))
    let n = x1 - x0
    if n <= 0 || n > 640 { ret ok }
    // Rows whose centre is clear of every layer's corner arcs are all one row (the shade there is a function of x alone).
    var omax: f32 = 0.0
    var omin: f32 = 0.0
    var k = 0usize
    while k < sh.count {
        omax = math.max[f32](omax, sh.layers[k].oy)
        omin = math.min[f32](omin, sh.layers[k].oy)
        k += 1usize
    }
    let mid0 = i32(math.ceil[f32](t + sh.radius + omax - 0.5))
    let mid1 = i32(math.floor[f32](bt - sh.radius + omin - 0.5)) + 1
    var shaded: [640]u16 = zero
    var covered: [640]u8 = zero
    var y = y0
    while y < y1 {
        if y >= mid0 && y < mid1 {
            row_cells(sh, f32(mid0) + 0.5, x0, n, l, t, r, bt, shaded[0usize..640usize], covered[0usize..640usize])
            try lay_row(b, sh, f32(mid0), f32(mid1 - mid0), x0, n, shaded[0usize..640usize], covered[0usize..640usize])
            y = mid1
            continue
        }
        row_cells(sh, f32(y) + 0.5, x0, n, l, t, r, bt, shaded[0usize..640usize], covered[0usize..640usize])
        try lay_row(b, sh, f32(y), 1.0, x0, n, shaded[0usize..640usize], covered[0usize..640usize])
        y += 1
    }
    ret ok
}

fn made_node(a: *mem.Arena, sh: Shade, w: f32, h: f32) -> (widget.Node, err) {
    var s = style.defaults()
    s.width = style.Length { Px: w }
    s.height = style.Length { Px: h }
    var none: []const widget.Node = zero
    let (specs, specs_error) = mem.alloc[Shade](a, 1usize)
    if specs_error != ok { ret (zero, specs_error) }
    specs[0usize] = sh
    ret (widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&specs[0usize]), measure: measure, paint: shade_paint, state: widget.bytes_of[Shade](&specs[0usize]) } }, style: s, children: none }, ok)
}

// The popover's shade: a zero-size node, first in the popover's column, round the `w` x `h` popover whose content box starts (`dx`, `dy`)
// inside it (its padding); the node's own top left is that content origin. The body is the popover's own box.
fn node(a: *mem.Arena, w: f32, h: f32, dx: f32, dy: f32, body: paint.Color) -> (widget.Node, err) {
    var sh: Shade = zero
    sh.rl = 0.0 - dx
    sh.rt = 0.0 - dy
    sh.rw = w
    sh.rh = h
    sh.radius = 10.94
    sh.margin = 30.0
    sh.count = 3usize
    sh.layers[0usize] = Layer { oy: 0.0 - 0.2114, spread: 0.6359, sigma: 0.4844, alpha: 0.0725 }
    sh.layers[1usize] = Layer { oy: 1.0095, spread: 2.2083, sigma: 1.2566, alpha: 0.0823 }
    sh.layers[2usize] = Layer { oy: 1.9056, spread: 5.9225, sigma: 5.1493, alpha: 0.0355 }
    let (made, made_error) = made_node(a, sh, 0.0, 0.0)
    ret (made, made_error)
}

// The alert card, `w` x `h`: the node fills the card's box and paints the card's face and the shade round it. The card is GTK's fraction of
// a pixel larger than its layout box, which is the 1 px rim the capture shows.
fn card_node(a: *mem.Arena, w: f32, h: f32, face: paint.Color) -> (widget.Node, err) {
    var sh: Shade = zero
    sh.rl = 0.0 - 0.4149
    sh.rt = 0.0 - 0.3541
    sh.rw = w + 0.8298
    sh.rh = h + 0.7306
    sh.radius = 13.0085
    sh.margin = 46.0
    sh.own_face = true
    sh.face = face
    sh.count = 3usize
    sh.layers[0usize] = Layer { oy: 0.1296, spread: 0.777, sigma: 0.5818, alpha: 0.0663 }
    sh.layers[1usize] = Layer { oy: 2.6152, spread: 3.2317, sigma: 4.2192, alpha: 0.0772 }
    sh.layers[2usize] = Layer { oy: 4.1836, spread: 19.6311, sigma: 8.3439, alpha: 0.033 }
    let (made, made_error) = made_node(a, sh, w, h)
    ret (made, made_error)
}

// Round 22: the GtkPopoverMenu's shade (fitted to menu-edit@1x by scripts/linux/fit_shadow.py menu: rms 0.6 of 255), round the `w` x `h`
// surface this node fills; the body is the menu's own box.
fn menu_node(a: *mem.Arena, w: f32, h: f32) -> (widget.Node, err) {
    var sh: Shade = zero
    sh.rw = w
    sh.rh = h
    sh.radius = 11.1438
    sh.margin = 30.0
    sh.count = 3usize
    sh.layers[0usize] = Layer { oy: 1.0323, spread: 2.1648, sigma: 1.1524, alpha: 0.0817 }
    sh.layers[1usize] = Layer { oy: 0.0 - 0.2148, spread: 0.6979, sigma: 0.4, alpha: 0.0527 }
    sh.layers[2usize] = Layer { oy: 1.9128, spread: 4.9148, sigma: 5.7962, alpha: 0.0433 }
    let (made, made_error) = made_node(a, sh, w, h)
    ret (made, made_error)
}
