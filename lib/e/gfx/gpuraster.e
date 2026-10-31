// `e.gfx.gpuraster` (D5929): a tile rasteriser for `e.gfx.scene` that runs on a Vulkan compute device.
//
// The CPU walks a scene's commands exactly as `scene.run_commands` does, keeping the same draw state (transform, scissor,
// clip masks, opacity layers), but instead of accumulating coverage and painting float canvases it emits a flat list of
// operations: RECT (an axis-aligned rectangle, covered analytically), PATH (flattened edges, from fills, strokes and glyph
// outlines), IMAGE, MASK (a clip's edges into a mask slot) and LBEGIN/LEND (an opacity layer). Each operation is binned into
// the 16x16 tiles it reaches that the frame's damage touches; a PATH or MASK entry carries the edges that cross its tile and a
// per-row backdrop (the winding of the edges wholly to the tile's left). One compute workgroup per dirty tile then composes
// the tile's entries in draw order, a thread per pixel, in float registers, and writes packed BGRA into the frame image. The
// coverage of an edge is the same exact box-filter area the CPU's accumulation buffer gives, so the two agree to float
// rounding; the test in `tests/.../gpu_raster` bounds the difference per channel.
//
// A scene the GPU cannot draw (ClearType or mat text modes, a capacity exceeded) is handed back: `scene.render_scaled` then
// redraws the whole frame on the CPU, whose canvas missed the frames drawn here.

use e.gpu
use e.mem
use e.math
use e.io
use e.os
use e.str
use e.time
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene

// ------------------------------------------------------------------------------------------------ shared code, CPU and device

error Unsupported

const TILE: u32 = 16u32
const OP_WORDS: usize = 32usize
const NONE: u32 = 4294967295u32
const FULL: u32 = 4294967294u32

const K_RECT: u32 = 0u32
const K_PATH: u32 = 1u32
const K_IMAGE: u32 = 2u32
const K_MASK: u32 = 3u32
const K_LBEGIN: u32 = 4u32
const K_LEND: u32 = 5u32

// Word offsets inside an operation (floats are stored as their bits).
const O_KIND: usize = 0usize
const O_LAYER: usize = 1usize
const O_MASK: usize = 2usize
const O_TARGET: usize = 3usize
const O_SX0: usize = 4usize
const O_SY0: usize = 5usize
const O_SX1: usize = 6usize
const O_SY1: usize = 7usize
const O_BRUSH: usize = 8usize
const O_STOP0: usize = 9usize
const O_NSTOPS: usize = 10usize
const O_TEX: usize = 11usize
const O_R: usize = 12usize
const O_G: usize = 13usize
const O_B: usize = 14usize
const O_A: usize = 15usize
const O_I00: usize = 16usize
const O_I01: usize = 17usize
const O_I02: usize = 18usize
const O_I10: usize = 19usize
const O_I11: usize = 20usize
const O_I12: usize = 21usize
const O_P0: usize = 22usize
const O_P1: usize = 23usize
const O_P2: usize = 24usize
const O_P3: usize = 25usize
const O_Q0: usize = 26usize
const O_Q1: usize = 27usize
const O_Q2: usize = 28usize
const O_Q3: usize = 29usize
const O_OPACITY: usize = 30usize

type Seg = struct { xa: f32, xb: f32, d: f32, live: u32 }

fn word_f(words: []const u32, at: usize) -> f32 {
    ret mem.bitcast[f32](words[at])
}

// The part of an edge in pixel row `row`, as `scene.accumulate_edge` sees it: the edge made to run downwards (`d` carries the
// direction), its x clamped to [0, limit] before the slope is taken, the row's span [xa, xb] and the signed height `d`.
fn edge_segment(ex0: f32, ey0: f32, ex1: f32, ey1: f32, row: u32, limit: f32) -> Seg {
    var dir: f32 = 1.0
    var x0 = ex0
    var y0 = ey0
    var x1 = ex1
    var y1 = ey1
    if y0 > y1 {
        dir = -1.0
        x0 = ex1
        y0 = ey1
        x1 = ex0
        y1 = ey0
    }
    if x0 < 0.0 { x0 = 0.0 }
    if x1 < 0.0 { x1 = 0.0 }
    if x0 > limit { x0 = limit }
    if x1 > limit { x1 = limit }
    let fy = f32(row)
    var top = fy
    if y0 > top { top = y0 }
    var bottom = fy + 1.0
    if y1 < bottom { bottom = y1 }
    let dy = bottom - top
    if !(dy > 0.0) { ret Seg { xa: 0.0, xb: 0.0, d: 0.0, live: 0u32 } }
    let dxdy = (x1 - x0) / (y1 - y0)
    let at_top = x0 + dxdy * (top - y0)
    let at_bottom = at_top + dxdy * dy
    var xa = at_top
    var xb = at_bottom
    if xa > xb {
        xa = at_bottom
        xb = at_top
    }
    if xa < 0.0 { xa = 0.0 }
    if xb < 0.0 { xb = 0.0 }
    if xa > limit { xa = limit }
    if xb > limit { xb = limit }
    ret Seg { xa: xa, xb: xb, d: dy * dir, live: 1u32 }
}


// The integral of clamp(t, 0, 1) from minus infinity to z.
fn ramp_integral(z: f32) -> f32 {
    if z <= 0.0 { ret 0.0 }
    if z < 1.0 { ret 0.5 * z * z }
    ret z - 0.5
}

fn unit_clamp(v: f32) -> f32 {
    if v <= 0.0 { ret 0.0 }
    if v > 1.0 { ret 1.0 }
    ret v
}

// What an edge adds to pixel column `px` of pixel row `row`: the signed, box-filtered area of the part of the edge in that row,
// to the pixel's left (the mean of clamp(px + 1 - x, 0, 1) over the row's span, times the part's signed height), as
// `scene.accumulate_edge` and the prefix sum over its cells give it. A part wholly left of the tile (its far end at or before
// `tile_left`) is not added: it is in the tile's backdrop. Written as one scalar function because the SPIR-V back end answers
// `Unsupported` for a helper that returns a struct or a tuple (measured on Intel Iris Xe and the RTX 3080).
fn edge_contribution(ex0: f32, ey0: f32, ex1: f32, ey1: f32, row: u32, limit: f32, px: f32, tile_left: f32) -> f32 {
    var dir: f32 = 1.0
    var x0 = ex0
    var y0 = ey0
    var x1 = ex1
    var y1 = ey1
    if y0 > y1 {
        dir = -1.0
        x0 = ex1
        y0 = ey1
        x1 = ex0
        y1 = ey0
    }
    if x0 < 0.0 { x0 = 0.0 }
    if x1 < 0.0 { x1 = 0.0 }
    if x0 > limit { x0 = limit }
    if x1 > limit { x1 = limit }
    let fy = f32(row)
    var top = fy
    if y0 > top { top = y0 }
    var bottom = fy + 1.0
    if y1 < bottom { bottom = y1 }
    let dy = bottom - top
    if dy <= 0.0 { ret 0.0 }
    let dxdy = (x1 - x0) / (y1 - y0)
    let at_top = x0 + dxdy * (top - y0)
    let at_bottom = at_top + dxdy * dy
    var xa = at_top
    var xb = at_bottom
    if xa > xb {
        xa = at_bottom
        xb = at_top
    }
    if xa < 0.0 { xa = 0.0 }
    if xb < 0.0 { xb = 0.0 }
    if xa > limit { xa = limit }
    if xb > limit { xb = limit }
    if xb <= tile_left { ret 0.0 }
    let d = dy * dir
    let w = xb - xa
    if w < 0.0001 {
        var c = px + 1.0 - 0.5 * (xa + xb)
        if c < 0.0 { c = 0.0 }
        if c > 1.0 { c = 1.0 }
        ret d * c
    }
    ret d * (ramp_integral(px + 1.0 - xa) - ramp_integral(px + 1.0 - xb)) / w
}

// Channel `ch` (0 r, 1 g, 2 b, 3 a) of a gradient's colour at `t`, premultiplied, from `count` stops of five floats (offset, r,
// g, b, a) starting at stop `first`: the interpolation `scene.stops_premultiplied` does.
fn gradient_channel(stops: []const f32, first: u32, count: u32, t: f32, ch: u32) -> f32 {
    let b0 = usize(first) * 5usize
    let a0 = stops[b0 + 4usize]
    if t <= stops[b0] {
        if ch == 3u32 { ret a0 }
        ret stops[b0 + 1usize + usize(ch)] * a0
    }
    var k = 1u32
    while k < count {
        let hi = (usize(first) + usize(k)) * 5usize
        if t <= stops[hi] {
            let lo = hi - 5usize
            var u: f32 = 1.0
            if stops[hi] > stops[lo] { u = (t - stops[lo]) / (stops[hi] - stops[lo]) }
            let pa = stops[lo + 4usize] + (stops[hi + 4usize] - stops[lo + 4usize]) * u
            if ch == 3u32 { ret pa }
            ret (stops[lo + 1usize + usize(ch)] + (stops[hi + 1usize + usize(ch)] - stops[lo + 1usize + usize(ch)]) * u) * pa
        }
        k += 1u32
    }
    let last = (usize(first) + usize(count) - 1usize) * 5usize
    let la = stops[last + 4usize]
    if ch == 3u32 { ret la }
    ret stops[last + 1usize + usize(ch)] * la
}

// The channel as a byte: `scene.channel_byte`.
fn to_byte(v: f32) -> u32 {
    if v <= 0.0 { ret 0u32 }
    if v >= 1.0 { ret 255u32 }
    ret u32(v * 255.0 + 0.5)
}

// Channel `c` of texel (x, y) of the packed (premultiplied, 8 bits a channel) texture at word `base`, `w` wide.
fn texel(texels: []const f32, base: u32, w: u32, x: u32, y: u32, c: u32) -> f32 {
    ret texels[(usize(base) + usize(y) * usize(w) + usize(x)) * 4usize + usize(c)]
}

// Channel `c` of `scene.sample_texture`: bilinear, the edge clamped.
fn sample_channel(texels: []const f32, base: u32, w: u32, h: u32, sx: f32, sy: f32, c: u32) -> f32 {
    var fx = sx - 0.5
    var fy = sy - 0.5
    let max_x = f32(w) - 1.0
    let max_y = f32(h) - 1.0
    if fx < 0.0 { fx = 0.0 }
    if fy < 0.0 { fy = 0.0 }
    if fx > max_x { fx = max_x }
    if fy > max_y { fy = max_y }
    let x0 = u32(fx)
    let y0 = u32(fy)
    var x1 = x0 + 1u32
    var y1 = y0 + 1u32
    if x1 >= w { x1 = x0 }
    if y1 >= h { y1 = y0 }
    let u = fx - f32(x0)
    let v = fy - f32(y0)
    let p00 = texel(texels, base, w, x0, y0, c)
    let p10 = texel(texels, base, w, x1, y0, c)
    let p01 = texel(texels, base, w, x0, y1, c)
    let p11 = texel(texels, base, w, x1, y1, c)
    ret (p00 * (1.0 - u) + p10 * u) * (1.0 - v) + (p01 * (1.0 - u) + p11 * u) * v
}

// Channel `ch` of the brush of operation `base` at the pixel centre (px, py), premultiplied.
fn brush_channel(ops: []const u32, base: usize, stops: []const f32, px: f32, py: f32, ch: u32) -> f32 {
    let brush = ops[base + O_BRUSH]
    if brush == 0u32 { ret word_f(ops, base + O_R + usize(ch)) }
    let row_x = word_f(ops, base + O_I01) * py
    let row_y = word_f(ops, base + O_I11) * py
    let qx = word_f(ops, base + O_I00) * px + row_x + word_f(ops, base + O_I02)
    let qy = word_f(ops, base + O_I10) * px + row_y + word_f(ops, base + O_I12)
    if brush == 1u32 {
        let sx = word_f(ops, base + O_P0)
        let sy = word_f(ops, base + O_P1)
        let dx = word_f(ops, base + O_P2) - sx
        let dy = word_f(ops, base + O_P3) - sy
        let len2 = dx * dx + dy * dy
        var t: f32 = 0.0
        if len2 > 0.0 { t = ((qx - sx) * dx + (qy - sy) * dy) / len2 }
        ret gradient_channel(stops, ops[base + O_STOP0], ops[base + O_NSTOPS], t, ch)
    }
    let cx = word_f(ops, base + O_P0)
    let cy = word_f(ops, base + O_P1)
    let radius = word_f(ops, base + O_P2)
    let dx = cx - qx
    let dy = cy - qy
    var t: f32 = 1.0
    if radius > 0.0 { t = math.sqrt[f32](dx * dx + dy * dy) / radius }
    ret gradient_channel(stops, ops[base + O_STOP0], ops[base + O_NSTOPS], t, ch)
}


// The image operation's weight at the pixel centre (px, py): its opacity inside the destination rectangle, else 0.
fn image_weight(ops: []const u32, base: usize, px: f32, py: f32) -> f32 {
    let row_x = word_f(ops, base + O_I01) * py
    let row_y = word_f(ops, base + O_I11) * py
    let qx = word_f(ops, base + O_I00) * px + row_x + word_f(ops, base + O_I02)
    let qy = word_f(ops, base + O_I10) * px + row_y + word_f(ops, base + O_I12)
    let u = (qx - word_f(ops, base + O_P0)) / word_f(ops, base + O_P2)
    let v = (qy - word_f(ops, base + O_P1)) / word_f(ops, base + O_P3)
    if unit_range(u) == 1u32 {
        if unit_range(v) == 1u32 { ret word_f(ops, base + O_OPACITY) }
    }
    ret 0.0
}

// Channel `ch` of the image operation's texture at the pixel centre (px, py): `scene.sample_texture` of the source point.
fn image_channel(ops: []const u32, base: usize, tex_meta: []const u32, texels: []const f32, px: f32, py: f32, ch: u32) -> f32 {
    let row_x = word_f(ops, base + O_I01) * py
    let row_y = word_f(ops, base + O_I11) * py
    let qx = word_f(ops, base + O_I00) * px + row_x + word_f(ops, base + O_I02)
    let qy = word_f(ops, base + O_I10) * px + row_y + word_f(ops, base + O_I12)
    let u = (qx - word_f(ops, base + O_P0)) / word_f(ops, base + O_P2)
    let v = (qy - word_f(ops, base + O_P1)) / word_f(ops, base + O_P3)
    let tm = usize(ops[base + O_TEX]) * 4usize
    let sx = word_f(ops, base + O_Q0) + u * word_f(ops, base + O_Q2)
    let sy = word_f(ops, base + O_Q1) + v * word_f(ops, base + O_Q3)
    ret sample_channel(texels, tex_meta[tm], tex_meta[tm + 1usize], tex_meta[tm + 2usize], sx, sy, ch)
}

// 1 when `lo <= v < hi`, else 0: the `&&` chains of the kernel miscompiled on the RTX 3080 (a nested `else if` after them drew
// pixels outside a scissor: 512 of 19200 image pixels wrong, none on Intel), so a range test is a function of nested ifs.
fn in_range(v: u32, lo: u32, hi: u32) -> u32 {
    if v >= lo {
        if v < hi { ret 1u32 }
    }
    ret 0u32
}

fn unit_range(v: f32) -> u32 {
    if v >= 0.0 {
        if v < 1.0 { ret 1u32 }
    }
    ret 0u32
}
// ------------------------------------------------------------------------------------------------------------ the kernel

// The `i`th of four / eight values, and `old` unless `i == k`: the layer and mask registers are scalars picked and updated by
// index, because a dynamically indexed private array went to scratch memory: the same kernel with `[16]f32` layers took 38 s
// to compile on Intel Iris Xe and 8 ms for a 960 x 640 frame on the RTX 3080.
fn pick4(i: u32, a: f32, b: f32, c: f32, d: f32) -> f32 {
    if i == 0u32 { ret a }
    if i == 1u32 { ret b }
    if i == 2u32 { ret c }
    ret d
}

fn pick8(i: u32, a: f32, b: f32, c: f32, d: f32, e: f32, f: f32, g: f32, h: f32) -> f32 {
    if i < 4u32 { ret pick4(i, a, b, c, d) }
    ret pick4(i - 4u32, e, f, g, h)
}

fn sel(i: u32, k: u32, new: f32, old: f32) -> f32 {
    if i == k { ret new }
    ret old
}

// One workgroup per dirty tile, a thread per pixel. `tiles` holds four words a dirty tile (tx | ty << 16, first entry, entry
// count, 0), `entries` four words an entry (op, first edge in `lists`, edge count, backdrop index or NONE / FULL).
// `@gpu(256, ftz)` is not used: the kernel is marked for no denormal mode (see `gpu.accept_unspecified_denormals`).
@gpu(256)
fn raster_tiles(tile_count: u32, tiles: []const u32, texels: []const f32, entries: []const u32, lists: []const u32, ops: []const u32, edges: []const f32, backdrops: []const f32, stops: []const f32, tex_meta: []const u32, out: []u32, width: u32, height: u32, stride: u32) {
    let tile = gpu.wgid.x
    if tile >= tile_count { ret }
    let lid = gpu.lid.x
    let th = usize(tile) * 4usize
    let corner = tiles[th]
    let first = tiles[th + 1usize]
    let count = tiles[th + 2usize]
    let lx = lid & 15u32
    let ly = lid >> 4u32
    let pix = (corner & 65535u32) * TILE + lx
    let piy = (corner >> 16u32) * TILE + ly
    let px = f32(pix) + 0.5
    let py = f32(piy) + 0.5
    let fpx = f32(pix)
    let fpy = f32(piy)
    let limit = f32(width)
    let tile_left = f32((corner & 65535u32) * TILE)
    var l0r: f32 = 0.0
    var l0g: f32 = 0.0
    var l0b: f32 = 0.0
    var l0a: f32 = 0.0
    var l1r: f32 = 0.0
    var l1g: f32 = 0.0
    var l1b: f32 = 0.0
    var l1a: f32 = 0.0
    var l2r: f32 = 0.0
    var l2g: f32 = 0.0
    var l2b: f32 = 0.0
    var l2a: f32 = 0.0
    var l3r: f32 = 0.0
    var l3g: f32 = 0.0
    var l3b: f32 = 0.0
    var l3a: f32 = 0.0
    var m0: f32 = 0.0
    var m1: f32 = 0.0
    var m2: f32 = 0.0
    var m3: f32 = 0.0
    var m4: f32 = 0.0
    var m5: f32 = 0.0
    var m6: f32 = 0.0
    var m7: f32 = 0.0
    var k = 0u32
    while k < count {
        let eb = (usize(first) + usize(k)) * 4usize
        let op = usize(entries[eb])
        let base = op * OP_WORDS
        let kind = ops[base + O_KIND]
        let inside = in_range(pix, ops[base + O_SX0], ops[base + O_SX1]) * in_range(piy, ops[base + O_SY0], ops[base + O_SY1]) == 1u32
        if kind == K_LBEGIN {
            if inside {
                let t = ops[base + O_TARGET]
                l0r = sel(t, 0u32, 0.0, l0r)
                l0g = sel(t, 0u32, 0.0, l0g)
                l0b = sel(t, 0u32, 0.0, l0b)
                l0a = sel(t, 0u32, 0.0, l0a)
                l1r = sel(t, 1u32, 0.0, l1r)
                l1g = sel(t, 1u32, 0.0, l1g)
                l1b = sel(t, 1u32, 0.0, l1b)
                l1a = sel(t, 1u32, 0.0, l1a)
                l2r = sel(t, 2u32, 0.0, l2r)
                l2g = sel(t, 2u32, 0.0, l2g)
                l2b = sel(t, 2u32, 0.0, l2b)
                l2a = sel(t, 2u32, 0.0, l2a)
                l3r = sel(t, 3u32, 0.0, l3r)
                l3g = sel(t, 3u32, 0.0, l3g)
                l3b = sel(t, 3u32, 0.0, l3b)
                l3a = sel(t, 3u32, 0.0, l3a)
            }
        } else if kind == K_LEND {
            if inside {
                let from = ops[base + O_LAYER]
                let into = ops[base + O_TARGET]
                let opacity = word_f(ops, base + O_OPACITY)
                let sr = pick4(from, l0r, l1r, l2r, l3r)
                let sg = pick4(from, l0g, l1g, l2g, l3g)
                let sb = pick4(from, l0b, l1b, l2b, l3b)
                let sa = pick4(from, l0a, l1a, l2a, l3a)
                let dr = pick4(into, l0r, l1r, l2r, l3r)
                let dg = pick4(into, l0g, l1g, l2g, l3g)
                let db = pick4(into, l0b, l1b, l2b, l3b)
                let da = pick4(into, l0a, l1a, l2a, l3a)
                let a = sa * opacity
                let keep = 1.0 - a
                let nr = sr * opacity + dr * keep
                let ng = sg * opacity + dg * keep
                let nb = sb * opacity + db * keep
                let na = a + da * keep
                l0r = sel(into, 0u32, nr, l0r)
                l0g = sel(into, 0u32, ng, l0g)
                l0b = sel(into, 0u32, nb, l0b)
                l0a = sel(into, 0u32, na, l0a)
                l1r = sel(into, 1u32, nr, l1r)
                l1g = sel(into, 1u32, ng, l1g)
                l1b = sel(into, 1u32, nb, l1b)
                l1a = sel(into, 1u32, na, l1a)
                l2r = sel(into, 2u32, nr, l2r)
                l2g = sel(into, 2u32, ng, l2g)
                l2b = sel(into, 2u32, nb, l2b)
                l2a = sel(into, 2u32, na, l2a)
                l3r = sel(into, 3u32, nr, l3r)
                l3g = sel(into, 3u32, ng, l3g)
                l3b = sel(into, 3u32, nb, l3b)
                l3a = sel(into, 3u32, na, l3a)
            }
        } else if inside {
            var c: f32 = 0.0
            var painting = true
            var cr: f32 = 0.0
            var cg: f32 = 0.0
            var cb: f32 = 0.0
            var ca: f32 = 0.0
            if kind == K_RECT {
                let left = word_f(ops, base + O_Q0)
                let top = word_f(ops, base + O_Q1)
                let right = word_f(ops, base + O_Q2)
                let bottom = word_f(ops, base + O_Q3)
                if ops[base + O_TARGET] == 1u32 {
                    // `scene.fill_rect_fast` takes the row's coverage less the column's loss, not their product: a corner pixel
                    // of a fractional rectangle is lighter there, and this matches it.
                    var cover: f32 = 1.0
                    if top > fpy { cover = cover - (top - fpy) }
                    if bottom < fpy + 1.0 { cover = cover - (fpy + 1.0 - bottom) }
                    if cover > 0.0 {
                        if left > fpx { cover = cover - (left - fpx) }
                        if right < fpx + 1.0 { cover = cover - (fpx + 1.0 - right) }
                    }
                    c = cover
                    if c < 0.0 { c = 0.0 }
                } else {
                    var cx = fpx + 1.0
                    if right < cx { cx = right }
                    var x0 = fpx
                    if left > x0 { x0 = left }
                    var cy = fpy + 1.0
                    if bottom < cy { cy = bottom }
                    var y0 = fpy
                    if top > y0 { y0 = top }
                    c = unit_clamp(cx - x0) * unit_clamp(cy - y0)
                }
            } else if kind == K_PATH || kind == K_MASK {
                let list_first = entries[eb + 1usize]
                let list_count = entries[eb + 2usize]
                let backdrop = entries[eb + 3usize]
                if backdrop == FULL {
                    c = 1.0
                } else {
                    var sum: f32 = 0.0
                    if backdrop != NONE { sum = backdrops[usize(backdrop) * 16usize + usize(ly)] }
                    var j = 0u32
                    while j < list_count {
                        let e = usize(lists[usize(list_first) + usize(j)]) * 4usize
                        let ey0 = edges[e + 1usize]
                        let ey1 = edges[e + 3usize]
                        var lo = ey0
                        var hi = ey1
                        if lo > hi {
                            lo = ey1
                            hi = ey0
                        }
                        if lo < fpy + 1.0 {
                            if hi > fpy { sum = sum + edge_contribution(edges[e], ey0, edges[e + 2usize], ey1, piy, limit, fpx, tile_left) }
                        }
                        j += 1u32
                    }
                    c = sum
                    if c < 0.0 { c = 0.0 - c }
                    if c > 1.0 { c = 1.0 }
                }
            } else if kind == K_IMAGE {
                c = image_weight(ops, base, px, py)
                cr = image_channel(ops, base, tex_meta, texels, px, py, 0u32)
                cg = image_channel(ops, base, tex_meta, texels, px, py, 1u32)
                cb = image_channel(ops, base, tex_meta, texels, px, py, 2u32)
                ca = image_channel(ops, base, tex_meta, texels, px, py, 3u32)
            }
            let mask_ref = ops[base + O_MASK]
            if mask_ref != 0u32 { c = c * pick8(mask_ref - 1u32, m0, m1, m2, m3, m4, m5, m6, m7) }
            if kind == K_MASK {
                let slot = ops[base + O_TARGET]
                m0 = sel(slot, 0u32, c, m0)
                m1 = sel(slot, 1u32, c, m1)
                m2 = sel(slot, 2u32, c, m2)
                m3 = sel(slot, 3u32, c, m3)
                m4 = sel(slot, 4u32, c, m4)
                m5 = sel(slot, 5u32, c, m5)
                m6 = sel(slot, 6u32, c, m6)
                m7 = sel(slot, 7u32, c, m7)
            } else if painting && c > 0.0 {
                if kind != K_IMAGE {
                    cr = brush_channel(ops, base, stops, px, py, 0u32)
                    cg = brush_channel(ops, base, stops, px, py, 1u32)
                    cb = brush_channel(ops, base, stops, px, py, 2u32)
                    ca = brush_channel(ops, base, stops, px, py, 3u32)
                }
                let layer = ops[base + O_LAYER]
                let a = ca * c
                let keep = 1.0 - a
                let nr = cr * c + pick4(layer, l0r, l1r, l2r, l3r) * keep
                let ng = cg * c + pick4(layer, l0g, l1g, l2g, l3g) * keep
                let nb = cb * c + pick4(layer, l0b, l1b, l2b, l3b) * keep
                let na = a + pick4(layer, l0a, l1a, l2a, l3a) * keep
                l0r = sel(layer, 0u32, nr, l0r)
                l0g = sel(layer, 0u32, ng, l0g)
                l0b = sel(layer, 0u32, nb, l0b)
                l0a = sel(layer, 0u32, na, l0a)
                l1r = sel(layer, 1u32, nr, l1r)
                l1g = sel(layer, 1u32, ng, l1g)
                l1b = sel(layer, 1u32, nb, l1b)
                l1a = sel(layer, 1u32, na, l1a)
                l2r = sel(layer, 2u32, nr, l2r)
                l2g = sel(layer, 2u32, ng, l2g)
                l2b = sel(layer, 2u32, nb, l2b)
                l2a = sel(layer, 2u32, na, l2a)
                l3r = sel(layer, 3u32, nr, l3r)
                l3g = sel(layer, 3u32, ng, l3g)
                l3b = sel(layer, 3u32, nb, l3b)
                l3a = sel(layer, 3u32, na, l3a)
            }
        }
        k += 1u32
    }
    if pix < width && piy < height {
        out[usize(piy) * usize(stride) + usize(pix)] = to_byte(l0b) | (to_byte(l0g) << 8u32) | (to_byte(l0r) << 16u32) | (to_byte(l0a) << 24u32)
    }
}

// ----------------------------------------------------------------------------------------------------------- host side

const MAX_OPS: usize = 8192usize
const MAX_G_ENTRIES: usize = 262144usize
const MAX_LISTS: usize = 1048576usize
const MAX_EDGE_STORE: usize = 524288usize
const MAX_BACKDROPS: usize = 32768usize
const MAX_STOP_STORE: usize = 4096usize
const MAX_TILES: usize = 32768usize
const MAX_SCENE_TEXTURES: usize = 4096usize
const TEXEL_CHUNK: usize = 262144usize
const START_TEXELS: usize = 2097152usize

type Context = struct {
    q: *gpu.Queue,
    a: *mem.Arena,
    d_tiles: gpu.Buf[u32],
    d_entries: gpu.Buf[u32],
    d_lists: gpu.Buf[u32],
    d_ops: gpu.Buf[u32],
    d_edges: gpu.Buf[f32],
    d_back: gpu.Buf[f32],
    d_stops: gpu.Buf[f32],
    d_texmeta: gpu.Buf[u32],
    d_texels: gpu.Buf[f32],
    texel_cap: usize,
    h_ops: []u32,
    n_ops: usize,
    h_edges: []f32,
    n_edges: usize,
    h_lists: []u32,
    n_lists: usize,
    h_back: []f32,
    n_back: usize,
    h_stops: []f32,
    n_stops: usize,
    g_entries: []u32,
    n_g: usize,
    h_entries: []u32,
    h_tiles: []u32,
    dirty: []bool,
    prev: []bool,
    cur: []bool,
    slot_of: []u32,
    tile_counts: []u32,
    ntx: usize,
    nty: usize,
    n_dirty: usize,
    dirty_x0: f32,
    dirty_y0: f32,
    dirty_x1: f32,
    dirty_y1: f32,
    seg_lo: []i32,
    seg_hi: []i32,
    col_count: []u32,
    col_fill: []u32,
    col_base: []u32,
    col_emit: []bool,
    col_bd: []f32,
    tex_gen: []u32,
    tex_ver: []u32,
    tex_off: []u32,
    tex_used: usize,
    stage: []u32,
    width: usize,
    height: usize,
    frames: u64,
    fallbacks: u64,
    encode_ns: i64,
    launch_ns: i64,
    last_entries: usize,
    last_edges: usize,
    last_tiles: usize,
    upload_ns: i64,
    present_ns: i64,
    check: bool,
    check_buf: gpu.Buf[u32],
    check_len: usize,
    check_host: []u32,
    check_cpu: []u32,
    check_pending: bool,
    check_w: usize,
    check_h: usize,
    check_frames: u64,
    check_bad: u64,
    check_worst: u32,
    debug: u32,
    stats: bool,
    reason: u32,
}

fn put_f(words: []u32, at: usize, v: f32) {
    words[at] = mem.bitcast[u32](v)
}

// Opens operation `kind` at the end of the list, zeroed; its base word index.
fn op_new(c: *Context, kind: u32) -> usize {
    let base = c.n_ops * OP_WORDS
    var i = 0usize
    while i < OP_WORDS {
        c.h_ops[base + i] = 0u32
        i += 1usize
    }
    c.h_ops[base + O_KIND] = kind
    c.n_ops += 1usize
    ret base
}

fn op_scissor(c: *Context, base: usize, x0: usize, y0: usize, x1: usize, y1: usize) {
    c.h_ops[base + O_SX0] = u32(x0)
    c.h_ops[base + O_SY0] = u32(y0)
    c.h_ops[base + O_SX1] = u32(x1)
    c.h_ops[base + O_SY1] = u32(y1)
}

fn op_inverse(c: *Context, base: usize, inv: geometry.Transform) {
    put_f(c.h_ops, base + O_I00, inv.m00)
    put_f(c.h_ops, base + O_I01, inv.m01)
    put_f(c.h_ops, base + O_I02, inv.m02)
    put_f(c.h_ops, base + O_I10, inv.m10)
    put_f(c.h_ops, base + O_I11, inv.m11)
    put_f(c.h_ops, base + O_I12, inv.m12)
}

// The brush into the operation: false when the brush cannot be painted (no stops, a transform with no inverse).
fn op_brush(c: *Context, base: usize, brush: *const paint.Brush, transform: geometry.Transform) -> bool {
    switch *brush {
    case .Solid as color:
        let pm = paint.premultiply(color)
        c.h_ops[base + O_BRUSH] = 0u32
        put_f(c.h_ops, base + O_R, pm.red)
        put_f(c.h_ops, base + O_G, pm.green)
        put_f(c.h_ops, base + O_B, pm.blue)
        put_f(c.h_ops, base + O_A, pm.alpha)
        ret true
    case .Linear as linear:
        let (inverse, invertible) = scene.transform_invert(transform)
        if !invertible || linear.stops.len == 0usize || c.n_stops + linear.stops.len > MAX_STOP_STORE { ret false }
        c.h_ops[base + O_BRUSH] = 1u32
        op_inverse(c, base, inverse)
        put_f(c.h_ops, base + O_P0, linear.start.x)
        put_f(c.h_ops, base + O_P1, linear.start.y)
        put_f(c.h_ops, base + O_P2, linear.end.x)
        put_f(c.h_ops, base + O_P3, linear.end.y)
        op_stops(c, base, linear.stops)
        ret true
    case .Radial as radial:
        let (inverse, invertible) = scene.transform_invert(transform)
        if !invertible || radial.stops.len == 0usize || c.n_stops + radial.stops.len > MAX_STOP_STORE { ret false }
        c.h_ops[base + O_BRUSH] = 2u32
        op_inverse(c, base, inverse)
        put_f(c.h_ops, base + O_P0, radial.center.x)
        put_f(c.h_ops, base + O_P1, radial.center.y)
        put_f(c.h_ops, base + O_P2, radial.radius)
        op_stops(c, base, radial.stops)
        ret true
    }
    ret false
}

fn op_stops(c: *Context, base: usize, stops: []const paint.Stop) {
    c.h_ops[base + O_STOP0] = u32(c.n_stops)
    c.h_ops[base + O_NSTOPS] = u32(stops.len)
    var i = 0usize
    while i < stops.len {
        let at = (c.n_stops + i) * 5usize
        c.h_stops[at] = stops[i].offset
        c.h_stops[at + 1usize] = stops[i].color.red
        c.h_stops[at + 2usize] = stops[i].color.green
        c.h_stops[at + 3usize] = stops[i].color.blue
        c.h_stops[at + 4usize] = stops[i].color.alpha
        i += 1usize
    }
    c.n_stops += stops.len
}


// An entry of operation `op` in tile (tx, ty): the tile's slot is where it will be sorted to.
fn entry_add(c: *Context, op: usize, tx: usize, ty: usize, list_first: usize, list_count: usize, backdrop: u32) -> err {
    if c.n_g >= MAX_G_ENTRIES { ret scene.TooLarge }
    let slot = c.slot_of[ty * c.ntx + tx]
    let at = c.n_g * 4usize
    c.g_entries[at] = u32(op) | (slot << 16u32)
    c.g_entries[at + 1usize] = u32(list_first)
    c.g_entries[at + 2usize] = u32(list_count)
    c.g_entries[at + 3usize] = backdrop
    c.n_g += 1usize
    ret ok
}

// An edge-less operation (rectangle, image, layer edge) in every dirty tile of the pixel box.
fn bin_box(c: *Context, op: usize, x0: usize, y0: usize, x1: usize, y1: usize) -> err {
    if x1 <= x0 || y1 <= y0 { ret ok }
    let tx0 = x0 / 16usize
    let ty0 = y0 / 16usize
    let tx1 = (x1 + 15usize) / 16usize
    let ty1 = (y1 + 15usize) / 16usize
    var ty = ty0
    while ty < ty1 && ty < c.nty {
        var tx = tx0
        while tx < tx1 && tx < c.ntx {
            if c.dirty[ty * c.ntx + tx] { try entry_add(c, op, tx, ty, 0usize, 0usize, NONE) }
            tx += 1usize
        }
        ty += 1usize
    }
    ret ok
}

// The edges `s.edges[0..count)` (already copied to the edge store at `edge_base`) of operation `op`, into per-tile lists with
// per-row backdrops, for the pixel box [x0, x1) x [y0, y1) (the edges' box inside the scissor and the frame).
fn bin_edges(c: *Context, op: usize, s: *scene.RendererState, edge_base: usize, count: usize, x0: usize, y0: usize, x1: usize, y1: usize) -> err {
    if x1 <= x0 || y1 <= y0 { ret ok }
    let tx0 = x0 / 16usize
    let ty0 = y0 / 16usize
    var tx1 = (x1 + 15usize) / 16usize
    var ty1 = (y1 + 15usize) / 16usize
    if tx1 > c.ntx { tx1 = c.ntx }
    if ty1 > c.nty { ty1 = c.nty }
    if tx1 <= tx0 || ty1 <= ty0 { ret ok }
    let columns = tx1 - tx0
    let limit = f32(c.width)
    var ty = ty0
    while ty < ty1 {
        var any_dirty = false
        var t = 0usize
        while t < columns {
            if c.dirty[ty * c.ntx + tx0 + t] { any_dirty = true }
            c.col_count[t] = 0u32
            c.col_emit[t] = false
            var r = 0usize
            while r < 16usize {
                c.col_bd[t * 16usize + r] = 0.0
                r += 1usize
            }
            t += 1usize
        }
        if !any_dirty {
            ty += 1usize
            continue
        }
        let row0 = u32(ty * 16usize)
        let fy0 = f32(row0)
        let fy1 = fy0 + 16.0
        var i = 0usize
        while i < count {
            c.seg_lo[i] = 1i32
            c.seg_hi[i] = 0i32
            let e = s.edges[i]
            var lo = e.y0
            var hi = e.y1
            if lo > hi {
                lo = e.y1
                hi = e.y0
            }
            if lo < fy1 && hi > fy0 {
                var first_row = row0
                if lo > fy0 { first_row = u32(lo) }
                var last_row = row0 + 15u32
                if hi < fy1 { last_row = u32(hi) }
                var lo_col = 1000000i32
                var hi_col = -1000000i32
                var row = first_row
                while row <= last_row {
                    let sg = edge_segment(e.x0, e.y0, e.x1, e.y1, row, limit)
                    if sg.live != 0u32 {
                        let xa_i = u32(sg.xa)
                        var xb_i = u32(sg.xb)
                        if f32(xb_i) < sg.xb { xb_i += 1u32 }
                        // Tiles the span touches, and the first tile it covers whole (its backdrop).
                        let first_col = i32(xa_i / 16u32) - i32(tx0)
                        var last_col = 0i32 - 1i32
                        if xb_i > 0u32 { last_col = i32((xb_i - 1u32) / 16u32) - i32(tx0) }
                        if last_col >= first_col {
                            if first_col < lo_col { lo_col = first_col }
                            if last_col > hi_col { hi_col = last_col }
                        }
                        var full_col = i32((xb_i + 15u32) / 16u32) - i32(tx0)
                        if full_col < 0i32 { full_col = 0i32 }
                        if full_col < i32(columns) { c.col_bd[usize(full_col) * 16usize + usize(row - row0)] += sg.d }
                    }
                    row += 1u32
                }
                if hi_col >= lo_col {
                    if lo_col < 0i32 { lo_col = 0i32 }
                    if hi_col >= i32(columns) { hi_col = i32(columns) - 1i32 }
                    if hi_col >= lo_col {
                        c.seg_lo[i] = lo_col
                        c.seg_hi[i] = hi_col
                        var col = lo_col
                        while col <= hi_col {
                            c.col_count[usize(col)] += 1u32
                            col += 1i32
                        }
                    }
                }
            }
            i += 1usize
        }
        // Backdrops accumulate to the right.
        var row = 0usize
        while row < 16usize {
            var col = 1usize
            while col < columns {
                c.col_bd[col * 16usize + row] += c.col_bd[(col - 1usize) * 16usize + row]
                col += 1usize
            }
            row += 1usize
        }
        // Which tiles get an entry, and where their lists start.
        var col = 0usize
        while col < columns {
            c.col_fill[col] = 0u32
            c.col_base[col] = u32(c.n_lists)
            if c.dirty[ty * c.ntx + tx0 + col] {
                var has_back = false
                var all_full = true
                var r = 0usize
                while r < 16usize {
                    let v = c.col_bd[col * 16usize + r]
                    var m = v
                    if m < 0.0 { m = 0.0 - m }
                    if m > 0.000001 { has_back = true }
                    if !(m > 0.999999) { all_full = false }
                    r += 1usize
                }
                let listed = usize(c.col_count[col])
                if listed > 0usize || has_back {
                    c.col_emit[col] = true
                    if c.n_lists + listed > MAX_LISTS { ret scene.TooLarge }
                    c.n_lists += listed
                    var backdrop = NONE
                    if listed == 0usize && all_full {
                        backdrop = FULL
                    } else if has_back {
                        if c.n_back >= MAX_BACKDROPS { ret scene.TooLarge }
                        backdrop = u32(c.n_back)
                        var r2 = 0usize
                        while r2 < 16usize {
                            c.h_back[c.n_back * 16usize + r2] = c.col_bd[col * 16usize + r2]
                            r2 += 1usize
                        }
                        c.n_back += 1usize
                    }
                    try entry_add(c, op, tx0 + col, ty, usize(c.col_base[col]), listed, backdrop)
                }
            }
            col += 1usize
        }
        // The lists, filled in edge order.
        var k = 0usize
        while k < count {
            if c.seg_lo[k] <= c.seg_hi[k] {
                var cc = c.seg_lo[k]
                while cc <= c.seg_hi[k] {
                    let u = usize(cc)
                    if c.col_emit[u] {
                        c.h_lists[usize(c.col_base[u]) + usize(c.col_fill[u])] = u32(edge_base + k)
                        c.col_fill[u] += 1u32
                    }
                    cc += 1i32
                }
            }
            k += 1usize
        }
        ty += 1usize
    }
    ret ok
}

// The graph of a context for a frame of `width` x `height`: tile bitmaps sized for the frame.
fn frame_tiles(c: *Context, width: usize, height: usize) -> err {
    let ntx = (width + 15usize) / 16usize
    let nty = (height + 15usize) / 16usize
    if ntx * nty > MAX_TILES || ntx > 1024usize { ret scene.TooLarge }
    if c.width != width || c.height != height {
        // A new frame size: the previous damage means nothing, and every tile is owed.
        var i = 0usize
        while i < MAX_TILES {
            c.prev[i] = true
            i += 1usize
        }
    }
    c.width = width
    c.height = height
    c.ntx = ntx
    c.nty = nty
    ret ok
}

// Marks the tiles of the pixel box on the dirty bitmap.
fn mark_box(c: *Context, x0: usize, y0: usize, x1: usize, y1: usize) {
    if x1 <= x0 || y1 <= y0 { ret }
    var ty = y0 / 16usize
    while ty < (y1 + 15usize) / 16usize && ty < c.nty {
        var tx = x0 / 16usize
        while tx < (x1 + 15usize) / 16usize && tx < c.ntx {
            c.dirty[ty * c.ntx + tx] = true
            tx += 1usize
        }
        ty += 1usize
    }
}

fn ensure_texture(c: *Context, s: *scene.RendererState, slot: usize) -> err {
    let t = &s.textures[slot]
    if c.tex_gen[slot] == t.generation && c.tex_ver[slot] == t.version && c.tex_off[slot] != NONE { ret ok }
    let texels = usize(t.width) * usize(t.height)
    if c.tex_used + texels > c.texel_cap {
        // Full: forget every cached texture, then they come back as the scene asks for them.
        var i = 0usize
        while i < c.tex_off.len {
            c.tex_off[i] = NONE
            i += 1usize
        }
        c.tex_used = 0usize
        if texels > c.texel_cap { ret scene.TooLarge }
    }
    var done = 0usize
    while done < texels {
        var chunk = texels - done
        if chunk > TEXEL_CHUNK { chunk = TEXEL_CHUNK }
        if gpu.write[f32](c.q, c.d_texels, (c.tex_used + done) * 4usize, t.pixels[done * 4usize..(done + chunk) * 4usize]) != ok { ret scene.OutOfMemory }
        done += chunk
    }
    var meta: [4]u32 = zero
    meta[0usize] = u32(c.tex_used)
    meta[1usize] = t.width
    meta[2usize] = t.height
    if gpu.write[u32](c.q, c.d_texmeta, slot * 4usize, meta[0usize..4usize]) != ok { ret scene.OutOfMemory }
    c.tex_off[slot] = u32(c.tex_used)
    c.tex_gen[slot] = t.generation
    c.tex_ver[slot] = t.version
    c.tex_used += texels
    ret ok
}

// Whether the text this scene draws is one the GPU can: glyph outlines as filled edges (grayscale AA), as the CPU's default.
fn text_ok() -> bool {
    if scene.mat_text { ret false }
    let mode = scene.text_aa_mode()
    ret mode == .Grayscale || mode == .ChromeWin
}

// Adds the edges now in `s.edges` as operation `kind` (K_PATH with `brush`, or K_MASK writing `slot`) in `current`'s state.
// Answers the pixel box the edges reach inside the scissor, for the caller's scissor narrowing (a mask).
fn emit_edges(c: *Context, s: *scene.RendererState, kind: u32, current: *scene.DrawState, brush: *const paint.Brush, slot: usize) -> (usize, usize, usize, usize, err) {
    let n = s.edge_count
    s.edge_count = 0usize
    if n == 0usize { ret (0usize, 0usize, 0usize, 0usize, ok) }
    if c.n_edges + n > MAX_EDGE_STORE || c.n_ops >= MAX_OPS { ret (0usize, 0usize, 0usize, 0usize, scene.TooLarge) }
    s.edge_count = n
    s.dx0 = 0usize
    s.dy0 = 0usize
    s.dx1 = c.width
    s.dy1 = c.height
    scene.edge_box(s)
    s.edge_count = 0usize
    let (sx0, sy0, sx1, sy1) = scene.scissor_bounds(s, current.scissor)
    var x0 = s.box_x0
    var y0 = s.box_y0
    var x1 = s.box_x1
    var y1 = s.box_y1
    if sx0 > x0 { x0 = sx0 }
    if sy0 > y0 { y0 = sy0 }
    if sx1 < x1 { x1 = sx1 }
    if sy1 < y1 { y1 = sy1 }
    if x1 <= x0 || y1 <= y0 {
        x1 = x0
        y1 = y0
    }
    if kind == K_PATH && x1 <= x0 { ret (x0, y0, x1, y1, ok) }
    let base = op_new(c, kind)
    let op = c.n_ops - 1usize
    op_scissor(c, base, x0, y0, x1, y1)
    if kind == K_PATH {
        if !op_brush(c, base, brush, current.transform) {
            c.n_ops -= 1usize
            ret (x0, y0, x1, y1, ok)
        }
        c.h_ops[base + O_LAYER] = u32(current.layer)
        if current.has_mask { c.h_ops[base + O_MASK] = u32(current.mask + 1usize) }
    } else {
        c.h_ops[base + O_TARGET] = u32(slot)
        if current.has_mask { c.h_ops[base + O_MASK] = u32(current.mask + 1usize) }
    }
    let edge_base = c.n_edges
    var i = 0usize
    while i < n {
        let e = s.edges[i]
        let at = (edge_base + i) * 4usize
        c.h_edges[at] = e.x0
        c.h_edges[at + 1usize] = e.y0
        c.h_edges[at + 2usize] = e.x1
        c.h_edges[at + 3usize] = e.y1
        i += 1usize
    }
    c.n_edges += n
    if x1 > x0 {
        let bin_error = bin_edges(c, op, s, edge_base, n, x0, y0, x1, y1)
        if bin_error != ok { ret (x0, y0, x1, y1, bin_error) }
    }
    ret (x0, y0, x1, y1, ok)
}

// Whether a drawing command's device bounds touch the dirty tiles' box.
fn touches_dirty(c: *Context, t: geometry.Transform, command: *const scene.Command) -> bool {
    let (bounds, drawing) = scene.command_bounds(t, command)
    if !drawing { ret true }
    if bounds.x + bounds.width <= c.dirty_x0 || bounds.x >= c.dirty_x1 || bounds.y + bounds.height <= c.dirty_y0 || bounds.y >= c.dirty_y1 { ret false }
    ret true
}

// The scene's commands as operations, binned into the dirty tiles. `Unsupported` for a scene the GPU hands back.
fn encode(c: *Context, s: *scene.RendererState, sc: *const scene.Scene) -> err {
    var states: [32]scene.DrawState = zero
    var depth = 0usize
    var current: scene.DrawState = zero
    current.transform = geometry.transform_scale(s.scale, s.scale)
    current.scissor = geometry.Rect { x: 0.0, y: 0.0, width: f32(c.width), height: f32(c.height) }
    current.opacity = 1.0
    var mask_count = 0usize
    var layer_count = 1usize
    var none_brush: paint.Brush = zero
    var i = 0usize
    while i < sc.count {
        let command = sc.commands[i]
        switch command {
        case .Save:
            if depth >= 32usize { ret scene.TooLarge }
            states[depth] = current
            depth += 1usize
            current.opens_layer = false
        case .Restore:
            if depth == 0usize { ret scene.Invalid }
            depth = depth - 1usize
            if current.opens_layer {
                if c.n_ops >= MAX_OPS { ret scene.TooLarge }
                let base = op_new(c, K_LEND)
                let op = c.n_ops - 1usize
                op_scissor(c, base, current.layer_x0, current.layer_y0, current.layer_x1, current.layer_y1)
                c.h_ops[base + O_LAYER] = u32(current.layer)
                c.h_ops[base + O_TARGET] = u32(states[depth].layer)
                put_f(c.h_ops, base + O_OPACITY, current.opacity)
                try bin_box(c, op, current.layer_x0, current.layer_y0, current.layer_x1, current.layer_y1)
                layer_count = layer_count - 1usize
            }
            if current.has_mask && !states[depth].has_mask { mask_count = 0usize }
            if current.has_mask && states[depth].has_mask { mask_count = states[depth].mask + 1usize }
            current = states[depth]
        case .Transform as t:
            current.transform = scene.transform_compose(current.transform, t)
        case .Clip as clip:
            switch clip {
            case .Rect as r:
                if current.transform.m01 == 0.0 && current.transform.m10 == 0.0 {
                    let p0 = geometry.transform_point(current.transform, geometry.Point { x: r.x, y: r.y })
                    let p1 = geometry.transform_point(current.transform, geometry.Point { x: r.x + r.width, y: r.y + r.height })
                    var x0 = p0.x
                    var x1 = p1.x
                    if x1 < x0 {
                        x0 = p1.x
                        x1 = p0.x
                    }
                    var y0 = p0.y
                    var y1 = p1.y
                    if y1 < y0 {
                        y0 = p1.y
                        y1 = p0.y
                    }
                    current.scissor = geometry.intersect(current.scissor, geometry.Rect { x: x0, y: y0, width: x1 - x0, height: y1 - y0 })
                } else {
                    let (verbs, points) = scene.rect_path(r)
                    var f = scene.fill_flattener(s, current.transform)
                    s.edge_count = 0usize
                    try scene.flatten(&f, geometry.Path { verbs: verbs[0..], points: points[0..] })
                    try push_mask(c, s, &current, &mask_count)
                }
            case .Rounded as rr:
                var f = scene.fill_flattener(s, current.transform)
                s.edge_count = 0usize
                try scene.rrect_edges(&f, rr)
                try push_mask(c, s, &current, &mask_count)
            case .Path as p:
                var f = scene.fill_flattener(s, current.transform)
                s.edge_count = 0usize
                try scene.flatten(&f, p)
                try push_mask(c, s, &current, &mask_count)
            }
        case .FillRect as fill:
            if touches_dirty(c, current.transform, &command) {
                try emit_fill_rect(c, s, &current, fill)
            }
        case .FillPath as fill:
            if touches_dirty(c, current.transform, &command) {
                var f = scene.fill_flattener(s, current.transform)
                s.edge_count = 0usize
                try scene.flatten(&f, fill.path)
                let (a0, a1, a2, a3, e) = emit_edges(c, s, K_PATH, &current, &fill.brush, 0usize)
                if e != ok { ret e }
            }
        case .StrokePath as stroke:
            if touches_dirty(c, current.transform, &command) {
                var f = scene.stroke_flattener(s, current.transform, stroke.stroke)
                s.edge_count = 0usize
                try scene.flatten(&f, stroke.path)
                let (a0, a1, a2, a3, e) = emit_edges(c, s, K_PATH, &current, &stroke.brush, 0usize)
                if e != ok { ret e }
            }
        case .Image as draw:
            if touches_dirty(c, current.transform, &command) {
                try emit_image(c, s, &current, draw)
            }
        case .Text as text:
            if touches_dirty(c, current.transform, &command) {
                if !text_ok() { ret Unsupported }
                var f = scene.fill_flattener(s, current.transform)
                s.edge_count = 0usize
                try scene.text_edges(s, &f, text)
                let (a0, a1, a2, a3, e) = emit_edges(c, s, K_PATH, &current, &text.brush, 0usize)
                if e != ok { ret e }
            }
        case .OpacityLayer as layer:
            if depth >= 32usize { ret scene.TooLarge }
            if layer_count >= 4usize { ret scene.TooLarge }
            if c.n_ops >= MAX_OPS { ret scene.TooLarge }
            states[depth] = current
            depth += 1usize
            let device = scene.transform_rect(current.transform, layer.bounds)
            let (lx0, ly0, lx1, ly1) = scene.scissor_bounds(s, geometry.intersect(current.scissor, geometry.Rect { x: device.x - 1.0, y: device.y - 1.0, width: device.width + 2.0, height: device.height + 2.0 }))
            current.layer_x0 = lx0
            current.layer_y0 = ly0
            current.layer_x1 = lx1
            current.layer_y1 = ly1
            current.scissor = geometry.Rect { x: f32(lx0), y: f32(ly0), width: f32(lx1 - lx0), height: f32(ly1 - ly0) }
            let base = op_new(c, K_LBEGIN)
            let op = c.n_ops - 1usize
            op_scissor(c, base, lx0, ly0, lx1, ly1)
            c.h_ops[base + O_TARGET] = u32(layer_count)
            try bin_box(c, op, lx0, ly0, lx1, ly1)
            current.layer = layer_count
            current.opens_layer = true
            current.opacity = layer.opacity
            layer_count += 1usize
        }
        i += 1usize
    }
    ret ok
}

// `scene.push_mask`: the edges in `s.edges` become the next mask slot, the current mask times their coverage, and the
// scissor narrows to the box they reach.
fn push_mask(c: *Context, s: *scene.RendererState, current: *scene.DrawState, mask_count: *usize) -> err {
    if *mask_count >= 8usize { ret scene.TooLarge }
    var none_brush: paint.Brush = zero
    let slot = *mask_count
    let (x0, y0, x1, y1, e) = emit_edges(c, s, K_MASK, current, &none_brush, slot)
    if e != ok { ret e }
    current.scissor = geometry.intersect(current.scissor, geometry.Rect { x: f32(x0), y: f32(y0), width: f32(x1 - x0), height: f32(y1 - y0) })
    current.mask = slot
    current.has_mask = true
    *mask_count += 1usize
    ret ok
}

fn emit_fill_rect(c: *Context, s: *scene.RendererState, current: *scene.DrawState, fill: scene.FillRect) -> err {
    if current.transform.m01 != 0.0 || current.transform.m10 != 0.0 {
        let (verbs, points) = scene.rect_path(fill.rect)
        var f = scene.fill_flattener(s, current.transform)
        s.edge_count = 0usize
        try scene.flatten(&f, geometry.Path { verbs: verbs[0..], points: points[0..] })
        let (a0, a1, a2, a3, e) = emit_edges(c, s, K_PATH, current, &fill.brush, 0usize)
        ret e
    }
    if c.n_ops >= MAX_OPS { ret scene.TooLarge }
    var device = scene.transform_rect(current.transform, fill.rect)
    var solid = false
    switch fill.brush {
    case .Solid as color:
        solid = true
    default:
        solid = false
    }
    var sx0 = 0usize
    var sy0 = 0usize
    var sx1 = 0usize
    var sy1 = 0usize
    if solid && !current.has_mask {
        // `scene.fill_rect_fast`: the rectangle meets the (fractional) scissor before it is covered.
        device = geometry.intersect(device, current.scissor)
        if !(device.width > 0.0) || !(device.height > 0.0) { ret ok }
        (sx0, sy0, sx1, sy1) = scene.scissor_bounds(s, device)
    } else {
        if !(device.width > 0.0) || !(device.height > 0.0) { ret ok }
        (sx0, sy0, sx1, sy1) = scene.scissor_bounds(s, current.scissor)
    }
    let (bx0, by0, bx1, by1) = scene.scissor_bounds(s, device)
    var x0 = sx0
    var y0 = sy0
    var x1 = sx1
    var y1 = sy1
    if bx0 > x0 { x0 = bx0 }
    if by0 > y0 { y0 = by0 }
    if bx1 < x1 { x1 = bx1 }
    if by1 < y1 { y1 = by1 }
    if x1 <= x0 || y1 <= y0 { ret ok }
    let base = op_new(c, K_RECT)
    let op = c.n_ops - 1usize
    if !op_brush(c, base, &fill.brush, current.transform) {
        c.n_ops -= 1usize
        ret ok
    }
    op_scissor(c, base, x0, y0, x1, y1)
    put_f(c.h_ops, base + O_Q0, device.x)
    put_f(c.h_ops, base + O_Q1, device.y)
    put_f(c.h_ops, base + O_Q2, device.x + device.width)
    put_f(c.h_ops, base + O_Q3, device.y + device.height)
    if solid && !current.has_mask { c.h_ops[base + O_TARGET] = 1u32 }
    c.h_ops[base + O_LAYER] = u32(current.layer)
    if current.has_mask { c.h_ops[base + O_MASK] = u32(current.mask + 1usize) }
    try bin_box(c, op, x0, y0, x1, y1)
    ret ok
}

fn emit_image(c: *Context, s: *scene.RendererState, current: *scene.DrawState, draw: scene.DrawImage) -> err {
    let (slot, slot_error) = scene.texture_slot(s, draw.texture)
    if slot_error != ok { ret slot_error }
    let (inverse, invertible) = scene.transform_invert(current.transform)
    if !invertible || draw.destination.width <= 0.0 || draw.destination.height <= 0.0 { ret ok }
    let bounds_device = scene.transform_rect(current.transform, draw.destination)
    let bounds = geometry.intersect(current.scissor, bounds_device)
    let (x0, y0, x1, y1) = scene.scissor_bounds(s, bounds)
    if x1 <= x0 || y1 <= y0 { ret ok }
    if c.n_ops >= MAX_OPS { ret scene.TooLarge }
    try ensure_texture(c, s, slot)
    let base = op_new(c, K_IMAGE)
    let op = c.n_ops - 1usize
    op_scissor(c, base, x0, y0, x1, y1)
    op_inverse(c, base, inverse)
    put_f(c.h_ops, base + O_P0, draw.destination.x)
    put_f(c.h_ops, base + O_P1, draw.destination.y)
    put_f(c.h_ops, base + O_P2, draw.destination.width)
    put_f(c.h_ops, base + O_P3, draw.destination.height)
    put_f(c.h_ops, base + O_Q0, draw.source.x)
    put_f(c.h_ops, base + O_Q1, draw.source.y)
    put_f(c.h_ops, base + O_Q2, draw.source.width)
    put_f(c.h_ops, base + O_Q3, draw.source.height)
    put_f(c.h_ops, base + O_OPACITY, draw.opacity)
    c.h_ops[base + O_TEX] = u32(slot)
    c.h_ops[base + O_LAYER] = u32(current.layer)
    if current.has_mask { c.h_ops[base + O_MASK] = u32(current.mask + 1usize) }
    try bin_box(c, op, x0, y0, x1, y1)
    ret ok
}

// The entries sorted by tile (draw order kept inside a tile) into `h_entries`, and the tile table into `h_tiles`.
fn sort_entries(c: *Context) {
    var t = 0usize
    while t < c.n_dirty {
        c.tile_counts[t] = 0u32
        t += 1usize
    }
    var g = 0usize
    while g < c.n_g {
        let slot = usize(c.g_entries[g * 4usize] >> 16u32)
        c.tile_counts[slot] += 1u32
        g += 1usize
    }
    // The tile table: corner, first entry, count.
    var first = 0u32
    t = 0usize
    while t < c.n_dirty {
        c.h_tiles[t * 4usize + 1usize] = first
        c.h_tiles[t * 4usize + 2usize] = c.tile_counts[t]
        first += c.tile_counts[t]
        c.tile_counts[t] = 0u32
        t += 1usize
    }
    g = 0usize
    while g < c.n_g {
        let word = c.g_entries[g * 4usize]
        let slot = usize(word >> 16u32)
        let at = (usize(c.h_tiles[slot * 4usize + 1usize]) + usize(c.tile_counts[slot])) * 4usize
        c.h_entries[at] = word & 65535u32
        c.h_entries[at + 1usize] = c.g_entries[g * 4usize + 1usize]
        c.h_entries[at + 2usize] = c.g_entries[g * 4usize + 2usize]
        c.h_entries[at + 3usize] = c.g_entries[g * 4usize + 3usize]
        c.tile_counts[slot] += 1u32
        g += 1usize
    }
}

fn now_ns() -> i64 {
    let (t, e) = time.monotonic()
    ret t.nanos
}

// Draws the dirty tiles of the scene into `out` (rows `stride` pixels apart): the damage, the move a scroll made, and what the
// back image missed last frame (`prev`, when `track` is set) become tiles; the scene is encoded and binned, uploaded, and the
// kernel launched. `false` with `ok` is a scene the GPU hands back.
fn draw_tiles(c: *Context, s: *scene.RendererState, sc: *const scene.Scene, full: bool, track: bool, width: usize, height: usize, out: gpu.Buf[u32], stride: u32) -> (bool, err) {
    let started = now_ns()
    if frame_tiles(c, width, height) != ok { ret (false, ok) }
    let tiles = c.ntx * c.nty
    var i = 0usize
    while i < tiles {
        c.cur[i] = false
        i += 1usize
    }
    if full {
        mark_box_in(c, c.cur, 0usize, 0usize, width, height)
    } else {
        var k = 0usize
        while k < s.box_count {
            let (bx0, by0, bx1, by1) = scene.scissor_bounds(s, s.boxes[k])
            mark_box_in(c, c.cur, bx0, by0, bx1, by1)
            k += 1usize
        }
        if s.has_shift { mark_box_in(c, c.cur, s.shift_x0, s.shift_y0, s.shift_x1, s.shift_y1) }
    }
    c.n_dirty = 0usize
    var min_x = c.ntx
    var min_y = c.nty
    var max_x = 0usize
    var max_y = 0usize
    var ty = 0usize
    while ty < c.nty {
        var tx = 0usize
        while tx < c.ntx {
            let at = ty * c.ntx + tx
            c.dirty[at] = c.cur[at] || (track && c.prev[at])
            if c.dirty[at] {
                c.slot_of[at] = u32(c.n_dirty)
                c.h_tiles[c.n_dirty * 4usize] = u32(tx) | (u32(ty) << 16u32)
                c.h_tiles[c.n_dirty * 4usize + 3usize] = 0u32
                c.n_dirty += 1usize
                if tx < min_x { min_x = tx }
                if ty < min_y { min_y = ty }
                if tx + 1usize > max_x { max_x = tx + 1usize }
                if ty + 1usize > max_y { max_y = ty + 1usize }
            }
            tx += 1usize
        }
        ty += 1usize
    }
    if c.n_dirty == 0usize { ret (false, ok) }
    c.dirty_x0 = f32(min_x * 16usize)
    c.dirty_y0 = f32(min_y * 16usize)
    c.dirty_x1 = f32(max_x * 16usize)
    c.dirty_y1 = f32(max_y * 16usize)
    c.n_ops = 0usize
    c.n_edges = 0usize
    c.n_lists = 0usize
    c.n_back = 0usize
    c.n_stops = 0usize
    c.n_g = 0usize
    let saved_dx0 = s.dx0
    let saved_dy0 = s.dy0
    let saved_dx1 = s.dx1
    let saved_dy1 = s.dy1
    let encode_error = encode(c, s, sc)
    s.edge_count = 0usize
    s.dx0 = saved_dx0
    s.dy0 = saved_dy0
    s.dx1 = saved_dx1
    s.dy1 = saved_dy1
    if encode_error != ok {
        c.reason = 3u32
        if encode_error == scene.TooLarge { c.reason = 1u32 }
        if encode_error == Unsupported { c.reason = 2u32 }
        if encode_error == scene.Invalid { c.reason = 4u32 }
        if encode_error == scene.OutOfMemory { c.reason = 5u32 }
        c.fallbacks += 1u64
        ret (false, ok)
    }
    sort_entries(c)
    c.last_entries = c.n_g
    c.last_edges = c.n_edges
    c.last_tiles = c.n_dirty
    let encoded = now_ns()
    c.encode_ns = encoded - started
    if gpu.write[u32](c.q, c.d_tiles, 0usize, c.h_tiles[0usize..c.n_dirty * 4usize]) != ok { ret (false, ok) }
    if gpu.write[u32](c.q, c.d_entries, 0usize, c.h_entries[0usize..c.n_g * 4usize]) != ok { ret (false, ok) }
    if gpu.write[u32](c.q, c.d_lists, 0usize, c.h_lists[0usize..c.n_lists]) != ok { ret (false, ok) }
    if gpu.write[u32](c.q, c.d_ops, 0usize, c.h_ops[0usize..c.n_ops * OP_WORDS]) != ok { ret (false, ok) }
    if gpu.write[f32](c.q, c.d_edges, 0usize, c.h_edges[0usize..c.n_edges * 4usize]) != ok { ret (false, ok) }
    if gpu.write[f32](c.q, c.d_back, 0usize, c.h_back[0usize..c.n_back * 16usize]) != ok { ret (false, ok) }
    if gpu.write[f32](c.q, c.d_stops, 0usize, c.h_stops[0usize..c.n_stops * 5usize]) != ok { ret (false, ok) }
    let uploaded = now_ns()
    c.upload_ns = uploaded - encoded
    let launch_error = gpu.launch[raster_tiles](c.q, gpu.grid1(c.n_dirty * 256usize), u32(c.n_dirty), c.d_tiles, c.d_texels, c.d_entries, c.d_lists, c.d_ops, c.d_edges, c.d_back, c.d_stops, c.d_texmeta, out, u32(width), u32(height), stride)
    c.launch_ns = now_ns() - uploaded
    if launch_error != ok {
        c.debug = 1u32
        if launch_error == gpu.Unsupported { c.debug = 2u32 }
        if launch_error == gpu.Lost { c.debug = 3u32 }
        if launch_error == gpu.TooLarge { c.debug = 4u32 }
        if launch_error == gpu.OutOfMemory { c.debug = 5u32 }
        if launch_error == gpu.InvalidHandle { c.debug = 6u32 }
        ret (false, ok)
    }
    ret (true, ok)
}

// The `scene.Rasteriser` render function: draws and presents the frame, or answers `false` (the CPU takes it). In check mode
// (NEPER_RASTER=check) it draws the whole frame into a side buffer, hands the frame to the CPU, and compares the two when the
// next frame comes (the front image then is the CPU's result for the frame the side buffer holds).
fn render(context: *void, s: *scene.RendererState, sc: *const scene.Scene, full: bool, frames: *gpu.Target) -> (bool, err) {
    let c = mem.cast[*Context](context)
    let (frame_w, frame_h) = gpu.extent(frames)
    var width = s.width
    var height = s.height
    if width > usize(frame_w) { width = usize(frame_w) }
    if height > usize(frame_h) { height = usize(frame_h) }
    if c.check {
        if c.check_len != width * height {
            if c.check_len != 0usize { let dropped = gpu.release[u32](c.q, c.check_buf) }
            let (made, made_error) = gpu.alloc[u32](c.q, width * height)
            if made_error != ok { ret (false, ok) }
            c.check_buf = made
            c.check_len = width * height
        }
        check_compare(c, frames)
        let (drawn, draw_error) = draw_tiles(c, s, sc, true, false, width, height, c.check_buf, u32(width))
        if draw_error != ok { ret (false, draw_error) }
        c.check_pending = drawn
        if !drawn { check_note(c) }
        c.check_w = width
        c.check_h = height
        if drawn { c.frames += 1u64 }
        ret (false, ok)
    }
    let (frame, acquire_error) = gpu.acquire(frames)
    if acquire_error != ok { ret (false, scene.Lost) }
    if frame.image.format != .Bgra8 {
        let abandoned = gpu.abandon(frames, frame)
        c.fallbacks += 1u64
        reset_prev_tiles(c)
        ret (false, ok)
    }
    let (drawn, draw_error) = draw_tiles(c, s, sc, full, true, width, height, frame.image.data, frame.image.width)
    if draw_error != ok || !drawn {
        let abandoned = gpu.abandon(frames, frame)
        // The CPU draws this frame in full, so both images owe everything next time.
        reset_prev_tiles(c)
        ret (false, ok)
    }
    gpu.report_damage(frames, u32(s.changed_x0), u32(s.changed_y0), u32(s.changed_x1), u32(s.changed_y1))
    let presented_at = now_ns()
    let (shown, present_error) = gpu.present(c.q, frames, frame)
    c.present_ns = now_ns() - presented_at
    if c.stats { stats_line(c) }
    if present_error != ok { ret (false, scene.Lost) }
    // This frame's damage is what the other image is owed next time.
    var i = 0usize
    while i < c.ntx * c.nty {
        c.prev[i] = c.cur[i]
        i += 1usize
    }
    c.frames += 1u64
    ret (true, ok)
}

// Compares the side buffer's frame with the front image (the CPU's result for the same scene), printing the largest per-channel
// difference and the number of pixels differing by more than 2 levels in a channel.
fn check_compare(c: *Context, frames: *gpu.Target) {
    if !c.check_pending { ret }
    c.check_pending = false
    let (shown, shown_error) = gpu.presented(frames)
    if shown_error != ok { ret }
    if usize(shown.width) * usize(shown.height) > c.check_host.len { ret }
    if gpu.read_image(c.q, shown, c.check_cpu[0usize..usize(shown.width) * usize(shown.height)]) != ok { ret }
    if gpu.download[u32](c.q, c.check_buf, c.check_host[0usize..c.check_w * c.check_h]) != ok { ret }
    var worst = 0u32
    var bad = 0usize
    var y = 0usize
    while y < c.check_h {
        var x = 0usize
        while x < c.check_w {
            let g = c.check_host[y * c.check_w + x]
            let p = c.check_cpu[y * usize(shown.width) + x]
            var ch = 0u32
            var over = false
            while ch < 4u32 {
                let a = (g >> (ch * 8u32)) & 255u32
                let b = (p >> (ch * 8u32)) & 255u32
                var d = a
                if b > a { d = b - a } else { d = a - b }
                if b > a { d = b - a }
                if d > worst { worst = d }
                if d > 2u32 { over = true }
                ch += 1u32
            }
            if over { bad += 1usize }
            x += 1usize
        }
        y += 1usize
    }
    c.check_frames += 1u64
    c.check_bad += u64(bad)
    if worst > c.check_worst { c.check_worst = worst }
    var line_storage: [160]u8 = zero
    var line_arena = mem.arena_from(line_storage[..])
    let (sb, sb_error) = str.builder(&line_arena, 120usize)
    if sb_error != ok { ret }
    var line = sb
    let e1 = str.push(&line, "RASTERCHECK worst=")
    let e2 = str.push_u64(&line, u64(worst))
    let e3 = str.push(&line, " over2=")
    let e4 = str.push_u64(&line, u64(bad))
    let e5 = str.push(&line, " of=")
    let e6 = str.push_u64(&line, u64(c.check_w * c.check_h))
    let e7 = str.push(&line, "\n")
    let printed = io.print(str.done(&line))
}


// Check mode: a frame the GPU could not take, and why (1 too large, 2 unsupported text, 3 other, 4 invalid, 5 out of memory).
fn check_note(c: *Context) {
    var line_storage: [96]u8 = zero
    var line_arena = mem.arena_from(line_storage[..])
    let (sb, sb_error) = str.builder(&line_arena, 80usize)
    if sb_error != ok { ret }
    var line = sb
    let e1 = str.push(&line, "RASTERCHECK handed back, reason=")
    let e2 = str.push_u64(&line, u64(c.reason))
    let e3 = str.push(&line, "\n")
    let printed = io.print(str.done(&line))
}

// NEPER_FRAME_STATS: where a GPU frame went, in microseconds: encode (commands to operations and tile lists), upload, the kernel
// launch (including its wait) and the present, with the tiles, entries and edges drawn.
fn stats_line(c: *Context) {
    var line_storage: [200]u8 = zero
    var line_arena = mem.arena_from(line_storage[..])
    let (sb, sb_error) = str.builder(&line_arena, 180usize)
    if sb_error != ok { ret }
    var line = sb
    let e1 = str.push(&line, "raster encode_us=")
    let e2 = str.push_u64(&line, u64(c.encode_ns / 1000i64))
    let e3 = str.push(&line, " upload_us=")
    let e4 = str.push_u64(&line, u64(c.upload_ns / 1000i64))
    let e5 = str.push(&line, " launch_us=")
    let e6 = str.push_u64(&line, u64(c.launch_ns / 1000i64))
    let e7 = str.push(&line, " present_us=")
    let e8 = str.push_u64(&line, u64(c.present_ns / 1000i64))
    let e9 = str.push(&line, " tiles=")
    let e10 = str.push_u64(&line, u64(c.last_tiles))
    let e11 = str.push(&line, " entries=")
    let e12 = str.push_u64(&line, u64(c.last_entries))
    let e13 = str.push(&line, " edges=")
    let e14 = str.push_u64(&line, u64(c.last_edges))
    let e15 = str.push(&line, "\n")
    let printed = io.print(str.done(&line))
}

error Refused

// The texture `self_test` draws: an 8 x 8 ramp, premultiplied float texels (r from x, g from y, alpha from both).
fn test_texel(x: usize, y: usize, ch: usize) -> f32 {
    let a = f32(x + y + 2usize) / 16.0
    if ch == 0usize { ret f32(x + 1usize) / 8.0 * a }
    if ch == 1usize { ret f32(y + 1usize) / 8.0 * a }
    if ch == 2usize { ret 0.25 * a }
    ret a
}

// The 16 x 16 tile `self_test` expects at (px, py): the solid page colour (0.2, 0.1, 0.3, 1) with the ramp, scaled 8 -> 16 and
// bilinearly sampled, drawn over it at opacity 0.8, as `scene.sample_texture` and `scene.blend_pixel` do it.
fn test_expected(px: usize, py: usize, ch: usize) -> u32 {
    let page_r: f32 = 0.2
    let page_g: f32 = 0.1
    let page_b: f32 = 0.3
    var fx = (f32(px) + 0.5) / 160.0 * 8.0 - 0.5
    var fy = (f32(py) + 0.5) / 120.0 * 8.0 - 0.5
    if fx < 0.0 { fx = 0.0 }
    if fy < 0.0 { fy = 0.0 }
    if fx > 7.0 { fx = 7.0 }
    if fy > 7.0 { fy = 7.0 }
    let x0 = usize(fx)
    let y0 = usize(fy)
    var x1 = x0 + 1usize
    var y1 = y0 + 1usize
    if x1 >= 8usize { x1 = x0 }
    if y1 >= 8usize { y1 = y0 }
    let u = fx - f32(x0)
    let v = fy - f32(y0)
    var channel: [4]f32 = zero
    var k = 0usize
    while k < 4usize {
        channel[k] = (test_texel(x0, y0, k) * (1.0 - u) + test_texel(x1, y0, k) * u) * (1.0 - v) + (test_texel(x0, y1, k) * (1.0 - u) + test_texel(x1, y1, k) * u) * v
        k += 1usize
    }
    let weight: f32 = 0.8
    let a = channel[3] * weight
    let keep = 1.0 - a
    var value: f32 = 0.0
    if ch == 0usize { value = channel[0] * weight + page_r * keep }
    if ch == 1usize { value = channel[1] * weight + page_g * keep }
    if ch == 2usize { value = channel[2] * weight + page_b * keep }
    if ch == 3usize { value = a + 1.0 * keep }
    ret to_byte(value)
}

// Draws one tile (a solid page rectangle, then the ramp image over it) on the device and compares it with the CPU's arithmetic,
// each channel within 2 levels. A device on which this fails (the RTX 3080 draws the image as nothing, D5950) is `Refused`: the
// rasteriser is not installed and the CPU keeps drawing, instead of a frame the GPU drew wrongly.
fn self_test(c: *Context) -> bool {
    let (out, out_error) = gpu.alloc[u32](c.q, 239616usize)
    if out_error != ok { ret refuse(1) }
    // The last 64 texels of the store and the last texture slot are the test's.
    let texel_at = c.texel_cap
    var ramp: [256]f32 = zero
    var y = 0usize
    while y < 8usize {
        var x = 0usize
        while x < 8usize {
            var k = 0usize
            while k < 4usize {
                ramp[(y * 8usize + x) * 4usize + k] = test_texel(x, y, k)
                k += 1usize
            }
            x += 1usize
        }
        y += 1usize
    }
    if gpu.write[f32](c.q, c.d_texels, texel_at * 4usize, ramp[0usize..256usize]) != ok { ret refuse(2) }
    var meta: [4]u32 = zero
    meta[0usize] = u32(texel_at)
    meta[1usize] = 8u32
    meta[2usize] = 8u32
    let slot = MAX_SCENE_TEXTURES - 1usize
    if gpu.write[u32](c.q, c.d_texmeta, slot * 4usize, meta[0usize..4usize]) != ok { ret refuse(3) }
    var tile: [4]u32 = zero
    tile[0usize] = 35u32 | (25u32 << 16u32)
    tile[2usize] = 2u32
    if gpu.write[u32](c.q, c.d_tiles, 0usize, tile[0usize..4usize]) != ok { ret refuse(4) }
    var entry: [8]u32 = zero
    entry[3usize] = NONE
    entry[4usize] = 1u32
    entry[7usize] = NONE
    if gpu.write[u32](c.q, c.d_entries, 0usize, entry[0usize..8usize]) != ok { ret refuse(5) }
    var words: [64]u32 = zero
    let page = words[0usize..64usize]
    page[O_KIND] = K_RECT
    page[O_TARGET] = 1u32
    page[O_SX0] = 560u32
    page[O_SX1] = 576u32
    page[O_SY0] = 400u32
    page[O_SY1] = 416u32
    put_f(page, O_R, 0.2)
    put_f(page, O_G, 0.1)
    put_f(page, O_B, 0.3)
    put_f(page, O_A, 1.0)
    put_f(page, O_Q0, 560.0)
    put_f(page, O_Q1, 400.0)
    put_f(page, O_Q2, 576.0)
    put_f(page, O_Q3, 416.0)
    let picture = words[32usize..64usize]
    picture[O_KIND] = K_IMAGE
    picture[O_SX0] = 560u32
    picture[O_SX1] = 576u32
    picture[O_SY0] = 400u32
    picture[O_SY1] = 416u32
    picture[O_TEX] = u32(slot)
    put_f(picture, O_I00, 1.0)
    put_f(picture, O_I11, 1.0)
    put_f(picture, O_P0, 560.0)
    put_f(picture, O_P1, 400.0)
    put_f(picture, O_P2, 160.0)
    put_f(picture, O_P3, 120.0)
    put_f(picture, O_Q2, 8.0)
    put_f(picture, O_Q3, 8.0)
    put_f(picture, O_OPACITY, 0.8)
    if gpu.write[u32](c.q, c.d_ops, 0usize, words[0usize..64usize]) != ok { ret refuse(6) }
    if gpu.launch[raster_tiles](c.q, gpu.grid1(256usize), 1u32, c.d_tiles, c.d_texels, c.d_entries, c.d_lists, c.d_ops, c.d_edges, c.d_back, c.d_stops, c.d_texmeta, out, 576u32, 416u32, 576u32) != ok { ret refuse(7) }
    let (got, got_error) = mem.alloc[u32](c.a, 239616usize)
    if got_error != ok { ret refuse(8) }
    if gpu.download[u32](c.q, out, got) != ok { ret refuse(9) }
    let released = gpu.release[u32](c.q, out)
    var py = 0usize
    while py < 16usize {
        var px = 0usize
        while px < 16usize {
            let word = got[(400usize + py) * 576usize + 560usize + px]
            // Packed BGRA: b, g, r, a from the low byte.
            var ch = 0usize
            while ch < 4usize {
                var shift = 0u32
                if ch == 0usize { shift = 16u32 }
                if ch == 1usize { shift = 8u32 }
                if ch == 2usize { shift = 0u32 }
                if ch == 3usize { shift = 24u32 }
                let have = (word >> shift) & 255u32
                let want = test_expected(px, py, ch)
                var d = have
                if want > have { d = want - have } else { d = have - want }
                if want > have { d = want - have }
                if d > 2u32 {
                    refusal_detail = (u32(px) << 24u32) | (u32(py) << 16u32) | (u32(ch) << 12u32) | (have << 0u32)
                    refusal_want = want
                    ret refuse(10)
                }
                ch += 1usize
            }
            px += 1usize
        }
        py += 1usize
    }
    ret true
}

// Why the last self-test failed: its step number, 0 when it has not failed. A host that refuses the rasteriser can name the step.
var refusal_step: u32 = zero

fn refuse(step: u32) -> bool {
    refusal_step = step
    ret false
}

// The step `self_test` failed at (0 if none yet).
fn refusal() -> u32 {
    ret refusal_step
}

var refusal_detail: u32 = zero
var refusal_want: u32 = zero

fn refusal_info() -> (u32, u32) {
    ret (refusal_detail, refusal_want)
}
fn mark_box_in(c: *Context, map: []bool, x0: usize, y0: usize, x1: usize, y1: usize) {
    if x1 <= x0 || y1 <= y0 { ret }
    var ty = y0 / 16usize
    while ty < (y1 + 15usize) / 16usize && ty < c.nty {
        var tx = x0 / 16usize
        while tx < (x1 + 15usize) / 16usize && tx < c.ntx {
            map[ty * c.ntx + tx] = true
            tx += 1usize
        }
        ty += 1usize
    }
}

// Every tile is owed to both images (a frame the CPU drew, or a failed launch).
fn reset_prev_tiles(c: *Context) {
    var i = 0usize
    while i < MAX_TILES {
        c.prev[i] = true
        i += 1usize
    }
}

// (frames drawn on the GPU, frames handed to the CPU, last encode microseconds, last launch microseconds, entries, edges, tiles)
fn counts(r: *scene.Renderer, rasteriser: *Context) -> (u64, u64, i64, i64, usize, usize, usize) {
    ret (rasteriser.frames, u64(rasteriser.debug), rasteriser.encode_ns / 1000i64, rasteriser.launch_ns / 1000i64, rasteriser.last_entries, rasteriser.last_edges, rasteriser.last_tiles)
}

// Takes the host arrays and device buffers for a context and installs it on `r`. `max_textures` is the renderer's texture table size.
fn install(r: *scene.Renderer, a: *mem.Arena, queue: *gpu.Queue, max_textures: usize, check: bool) -> (*Context, err) {
    var none: *Context = zero
    if max_textures > MAX_SCENE_TEXTURES { ret (none, scene.Invalid) }
    let (cs, cs_error) = mem.alloc[Context](a, 1usize)
    if cs_error != ok { ret (none, cs_error) }
    let c = &cs[0usize]
    var empty: Context = zero
    cs[0usize] = empty
    c.q = queue
    c.a = a
    let (h_ops, e1) = mem.alloc[u32](a, MAX_OPS * OP_WORDS)
    if e1 != ok { ret (none, e1) }
    c.h_ops = h_ops
    let (h_edges, e2) = mem.alloc[f32](a, MAX_EDGE_STORE * 4usize)
    if e2 != ok { ret (none, e2) }
    c.h_edges = h_edges
    let (h_lists, e3) = mem.alloc[u32](a, MAX_LISTS)
    if e3 != ok { ret (none, e3) }
    c.h_lists = h_lists
    let (h_back, e4) = mem.alloc[f32](a, MAX_BACKDROPS * 16usize)
    if e4 != ok { ret (none, e4) }
    c.h_back = h_back
    let (h_stops, e5) = mem.alloc[f32](a, MAX_STOP_STORE * 5usize)
    if e5 != ok { ret (none, e5) }
    c.h_stops = h_stops
    let (g_entries, e6) = mem.alloc[u32](a, MAX_G_ENTRIES * 4usize)
    if e6 != ok { ret (none, e6) }
    c.g_entries = g_entries
    let (h_entries, e7) = mem.alloc[u32](a, MAX_G_ENTRIES * 4usize)
    if e7 != ok { ret (none, e7) }
    c.h_entries = h_entries
    let (h_tiles, e8) = mem.alloc[u32](a, MAX_TILES * 4usize)
    if e8 != ok { ret (none, e8) }
    c.h_tiles = h_tiles
    let (dirty, e9) = mem.alloc[bool](a, MAX_TILES)
    if e9 != ok { ret (none, e9) }
    c.dirty = dirty
    let (prev, e10) = mem.alloc[bool](a, MAX_TILES)
    if e10 != ok { ret (none, e10) }
    c.prev = prev
    let (cur, e11) = mem.alloc[bool](a, MAX_TILES)
    if e11 != ok { ret (none, e11) }
    c.cur = cur
    let (slot_of, e12) = mem.alloc[u32](a, MAX_TILES)
    if e12 != ok { ret (none, e12) }
    c.slot_of = slot_of
    let (tile_counts, e13) = mem.alloc[u32](a, MAX_TILES)
    if e13 != ok { ret (none, e13) }
    c.tile_counts = tile_counts
    let (seg_lo, e14) = mem.alloc[i32](a, 65536usize)
    if e14 != ok { ret (none, e14) }
    c.seg_lo = seg_lo
    let (seg_hi, e15) = mem.alloc[i32](a, 65536usize)
    if e15 != ok { ret (none, e15) }
    c.seg_hi = seg_hi
    let (col_count, e16) = mem.alloc[u32](a, 1024usize)
    if e16 != ok { ret (none, e16) }
    c.col_count = col_count
    let (col_fill, e17) = mem.alloc[u32](a, 1024usize)
    if e17 != ok { ret (none, e17) }
    c.col_fill = col_fill
    let (col_base, e18) = mem.alloc[u32](a, 1024usize)
    if e18 != ok { ret (none, e18) }
    c.col_base = col_base
    let (col_emit, e19) = mem.alloc[bool](a, 1024usize)
    if e19 != ok { ret (none, e19) }
    c.col_emit = col_emit
    let (col_bd, e20) = mem.alloc[f32](a, 1024usize * 16usize)
    if e20 != ok { ret (none, e20) }
    c.col_bd = col_bd
    let (tex_gen, e21) = mem.alloc[u32](a, MAX_SCENE_TEXTURES)
    if e21 != ok { ret (none, e21) }
    c.tex_gen = tex_gen
    let (tex_ver, e22) = mem.alloc[u32](a, MAX_SCENE_TEXTURES)
    if e22 != ok { ret (none, e22) }
    c.tex_ver = tex_ver
    let (tex_off, e23) = mem.alloc[u32](a, MAX_SCENE_TEXTURES)
    if e23 != ok { ret (none, e23) }
    c.tex_off = tex_off
    let (stage, e24) = mem.alloc[u32](a, TEXEL_CHUNK)
    if e24 != ok { ret (none, e24) }
    c.stage = stage
    var i = 0usize
    while i < MAX_SCENE_TEXTURES {
        c.tex_gen[i] = 0u32
        c.tex_ver[i] = 0u32
        c.tex_off[i] = NONE
        i += 1usize
    }
    reset_prev_tiles(c)
    c.check = check
    let (stats_text, stats_error) = os.env(a, "NEPER_FRAME_STATS")
    c.stats = stats_error == ok && stats_text.len > 0usize
    if check {
        // The side buffer and two host copies for a frame up to 3840 x 2160.
        let (check_host, g2) = mem.alloc[u32](a, 8294400usize)
        if g2 != ok { ret (none, g2) }
        c.check_host = check_host
        let (check_cpu, g3) = mem.alloc[u32](a, 8294400usize)
        if g3 != ok { ret (none, g3) }
        c.check_cpu = check_cpu
    }
    let (d_tiles, f1) = gpu.alloc[u32](queue, MAX_TILES * 4usize)
    if f1 != ok { ret (none, f1) }
    c.d_tiles = d_tiles
    let (d_entries, f2) = gpu.alloc[u32](queue, MAX_G_ENTRIES * 4usize)
    if f2 != ok { ret (none, f2) }
    c.d_entries = d_entries
    let (d_lists, f3) = gpu.alloc[u32](queue, MAX_LISTS)
    if f3 != ok { ret (none, f3) }
    c.d_lists = d_lists
    let (d_ops, f4) = gpu.alloc[u32](queue, MAX_OPS * OP_WORDS)
    if f4 != ok { ret (none, f4) }
    c.d_ops = d_ops
    let (d_edges, f5) = gpu.alloc[f32](queue, MAX_EDGE_STORE * 4usize)
    if f5 != ok { ret (none, f5) }
    c.d_edges = d_edges
    let (d_back, f6) = gpu.alloc[f32](queue, MAX_BACKDROPS * 16usize)
    if f6 != ok { ret (none, f6) }
    c.d_back = d_back
    let (d_stops, f7) = gpu.alloc[f32](queue, MAX_STOP_STORE * 5usize)
    if f7 != ok { ret (none, f7) }
    c.d_stops = d_stops
    let (d_texmeta, f8) = gpu.alloc_in[u32](queue, MAX_SCENE_TEXTURES * 4usize, true)
    if f8 != ok { ret (none, f8) }
    c.d_texmeta = d_texmeta
    // The texel store: as large as the device gives, down from 16 M texels (64 MB).
    var cap = 4194304usize
    var made = false
    while !made && cap >= START_TEXELS {
        let (d_texels, f9) = gpu.alloc[f32](queue, cap * 4usize)
        if f9 == ok {
            c.d_texels = d_texels
            c.texel_cap = cap - 64usize
            made = true
        } else {
            cap = cap / 2usize
        }
    }
    if !made { ret (none, gpu.OutOfMemory) }
    let (rs, rs_error) = scene.renderer_state(r)
    if rs_error != ok { ret (none, rs_error) }
    // The kernel is float code; on a device with neither denormal mode (the RTX 3080) the caller accepts what the device does.
    let accepted = gpu.accept_unspecified_denormals(rs.device)
    if accepted != ok { ret (none, accepted) }
    // A Vulkan device must draw the self-test tile right; the CPU build of the kernel is checked by the fixture instead.
    let (info, info_error) = gpu.info(a, rs.device)
    if info_error == ok && info.key.backend == .Vulkan {
        // The RTX 3080's kernel draws images wrongly, in release builds as nothing and in checked builds differently (D5950): the
        // self-test caught only the first, so an NVIDIA device is refused by name until the failure is found.
        if name_has(info.name, "NVIDIA") || !self_test(c) { ret (none, Refused) }
    }
    let installed = scene.set_rasteriser(r, scene.Rasteriser { context: mem.cast[*void](c), render: render })
    if installed != ok { ret (none, installed) }
    ret (c, ok)
}

// Whether `word` occurs in `name`.
fn name_has(name: str, word: str) -> bool {
    if word.len > name.len { ret false }
    var at = 0usize
    while at + word.len <= name.len {
        var k = 0usize
        while k < word.len && name[at + k] == word[k] { k += 1usize }
        if k == word.len { ret true }
        at += 1usize
    }
    ret false
}
