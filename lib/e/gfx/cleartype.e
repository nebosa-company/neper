// A ClearType rasteriser for hinted glyph outlines (`e.text.tthint`). The model was fitted to the text the Windows GDI
// ClearType renderer draws: every pixel row is sampled by five scanlines (at the tenths 0.1, 0.3, ... 0.9 of the row), each
// scanline by six samples across a pixel (at the twelfths 1/12, 3/12, ...), and the coverage of a pixel's red, green and blue
// subpixels is the number of set samples in the six-sample window centred on the subpixel (columns 2m-2 .. 2m+3 for subpixel m,
// so neighbouring subpixels share four of six), divided by five and rounded half up to 0..6 sixths.
//
// The outline is kept as the curves it is, split where a quadratic turns in y into pieces that run one way, and not flattened:
// a piece that reaches the middle of a pixel row is taken at that middle for all five scanlines of the row (the edge is the same
// on each, however slanted or curved), and a piece that ends inside the row is taken at its end nearest the middle. That is how
// GDI's coverage of a bowl or a diagonal has the crisp 2-4-6 ramps and the half-column 1-3-5 ones it has, which a flattened
// outline sampled scanline by scanline blurs into 1-2-3-4-5-6.
//
// `blend` composes the 0..6 coverage onto a colour as GDI does, byte for byte: a gamma of 1.2 on each channel through 8-bit tables
// (see `blend_byte`).
//
// `begin` opens a buffer over a window of device pixels and `add_glyph` rasterises hinted outlines into it, taking the larger
// of two glyphs' coverage where they meet, so a run drawn glyph by glyph is the same as the run at once.

use e.math
use e.mem
use e.text.tthint

const MAX_PIECES: usize = 6000usize
const MAX_CROSS: usize = 160usize
const MAX_COLS: usize = 6144usize
const MAX_BUFFER: usize = 3145728usize

// A piece is a line (`quad` false) or a quadratic from (x0, y0) by control (cx, cy) to (x1, y1), monotone in y.
type Scratch = struct { x0: []f64, y0: []f64, cx: []f64, cy: []f64, x1: []f64, y1: []f64, quad: []bool, n: usize, counts: []i64, line: []i64, kbuf: []u8, kx0: i64, ky0: i64, kw: usize, kh: usize, hx: [160]f64, hd: [160]i64, over: bool }

// Variants of the sampler under test: 1 weights the five lines 1 2 3 2 1, 2 takes a piece's x at the line instead of the row's middle,
// 4 takes a line along an edge both ways.
var raster_mode: i64 = zero

fn set_raster(n: i64) { raster_mode = n }

fn scratch(a: *mem.Arena) -> (*Scratch, err) {
    let (cells, cells_error) = mem.alloc[Scratch](a, 1usize)
    if cells_error != ok { ret (zero, cells_error) }
    let sc = &cells[0usize]
    var blank: Scratch = zero
    *sc = blank
    let (x0, e0) = mem.alloc[f64](a, MAX_PIECES)
    if e0 != ok { ret (zero, e0) }
    let (y0, e1) = mem.alloc[f64](a, MAX_PIECES)
    if e1 != ok { ret (zero, e1) }
    let (cx, e2) = mem.alloc[f64](a, MAX_PIECES)
    if e2 != ok { ret (zero, e2) }
    let (cy, e3) = mem.alloc[f64](a, MAX_PIECES)
    if e3 != ok { ret (zero, e3) }
    let (x1, e4) = mem.alloc[f64](a, MAX_PIECES)
    if e4 != ok { ret (zero, e4) }
    let (y1, e5) = mem.alloc[f64](a, MAX_PIECES)
    if e5 != ok { ret (zero, e5) }
    let (quad, e6) = mem.alloc[bool](a, MAX_PIECES)
    if e6 != ok { ret (zero, e6) }
    let (counts, e7) = mem.alloc[i64](a, MAX_COLS + 24usize)
    if e7 != ok { ret (zero, e7) }
    let (kbuf, e8) = mem.alloc[u8](a, MAX_BUFFER)
    if e8 != ok { ret (zero, e8) }
    let (line, e9) = mem.alloc[i64](a, MAX_COLS + 24usize)
    if e9 != ok { ret (zero, e9) }
    sc.x0 = x0
    sc.y0 = y0
    sc.cx = cx
    sc.cy = cy
    sc.x1 = x1
    sc.y1 = y1
    sc.quad = quad
    sc.counts = counts
    sc.line = line
    sc.kbuf = kbuf
    ret (sc, ok)
}

// Opens the buffer over the device pixels `x0..x0+w` by `y0..y0+h`, empty. False when it would not fit.
fn begin(sc: *Scratch, x0: i64, y0: i64, w: usize, h: usize) -> bool {
    if w == 0usize || h == 0usize || w * h * 3usize > MAX_BUFFER { ret false }
    sc.kx0 = x0
    sc.ky0 = y0
    sc.kw = w
    sc.kh = h
    var i = 0usize
    while i < w * h * 3usize {
        sc.kbuf[i] = 0u8
        i += 1usize
    }
    ret true
}

// The coverage (0..6) of the red (`sub` 0), green or blue subpixel of device pixel (px, py), 0 outside the window.
fn coverage(sc: *Scratch, px: i64, py: i64, sub: usize) -> i64 {
    if px < sc.kx0 || py < sc.ky0 || px >= sc.kx0 + i64(sc.kw) || py >= sc.ky0 + i64(sc.kh) { ret 0i64 }
    ret i64(sc.kbuf[(usize(py - sc.ky0) * sc.kw + usize(px - sc.kx0)) * 3usize + sub])
}

fn add_line(sc: *Scratch, ax: f64, ay: f64, bx: f64, by: f64) {
    if ay == by { ret }
    if sc.n >= MAX_PIECES {
        sc.over = true
        ret
    }
    sc.x0[sc.n] = ax
    sc.y0[sc.n] = ay
    sc.x1[sc.n] = bx
    sc.y1[sc.n] = by
    sc.quad[sc.n] = false
    sc.n += 1usize
}

fn add_monotone(sc: *Scratch, ax: f64, ay: f64, qx: f64, qy: f64, bx: f64, by: f64) {
    if ay == by { ret }
    if sc.n >= MAX_PIECES {
        sc.over = true
        ret
    }
    sc.x0[sc.n] = ax
    sc.y0[sc.n] = ay
    sc.cx[sc.n] = qx
    sc.cy[sc.n] = qy
    sc.x1[sc.n] = bx
    sc.y1[sc.n] = by
    sc.quad[sc.n] = true
    sc.n += 1usize
}

// A quadratic, cut where its y turns round.
fn add_quad(sc: *Scratch, ax: f64, ay: f64, qx: f64, qy: f64, bx: f64, by: f64) {
    let den = ay - 2.0f64 * qy + by
    var t = -1.0f64
    if den != 0.0f64 { t = (ay - qy) / den }
    if t > 0.0f64 && t < 1.0f64 {
        let a1x = ax + (qx - ax) * t
        let a1y = ay + (qy - ay) * t
        let b1x = qx + (bx - qx) * t
        let b1y = qy + (by - qy) * t
        let mx = a1x + (b1x - a1x) * t
        let my = a1y + (b1y - a1y) * t
        add_monotone(sc, ax, ay, a1x, a1y, mx, my)
        add_monotone(sc, mx, my, b1x, b1y, bx, by)
    } else {
        add_monotone(sc, ax, ay, qx, qy, bx, by)
    }
}

// The outline's contours as pieces in device 26.6 units: the pen is a whole pixel, the glyph's left phantom point on it.
fn flatten(sc: *Scratch, o: *const tthint.Outline, pen: i64) {
    sc.n = 0usize
    sc.over = false
    let ox = f64(pen * 64i64 - o.pp1x)
    var first = 0usize
    var c = 0usize
    while c < o.nends {
        let last = o.ends[c]
        c += 1usize
        if last < first || last >= o.n {
            first = last + 1usize
            continue
        }
        // The start: the first on-curve point, else the midpoint of the last and first.
        var start = first
        var found = false
        var i = first
        while i <= last && !found {
            if (o.tags[i] & 1i64) != 0i64 {
                start = i
                found = true
            }
            i += 1usize
        }
        let count = last - first + 1usize
        var curx = 0.0f64
        var cury = 0.0f64
        if found {
            curx = ox + f64(o.cur[2usize * start])
            cury = f64(o.cur[2usize * start + 1usize])
        } else {
            curx = ox + f64(o.cur[2usize * first] + o.cur[2usize * last]) / 2.0f64
            cury = f64(o.cur[2usize * first + 1usize] + o.cur[2usize * last + 1usize]) / 2.0f64
        }
        let firstx = curx
        let firsty = cury
        var has_ctrl = false
        var ctrlx = 0.0f64
        var ctrly = 0.0f64
        var k = 0usize
        // The points in order after `start`, wrapping round to the start itself last; every point in order when none is on the curve.
        while k < count {
            var index = first + k
            if found { index = first + (start - first + 1usize + k) % count }
            k += 1usize
            let x = ox + f64(o.cur[2usize * index])
            let y = f64(o.cur[2usize * index + 1usize])
            if (o.tags[index] & 1i64) != 0i64 {
                if !has_ctrl {
                    add_line(sc, curx, cury, x, y)
                } else {
                    add_quad(sc, curx, cury, ctrlx, ctrly, x, y)
                    has_ctrl = false
                }
                curx = x
                cury = y
            } else {
                if has_ctrl {
                    let mx = (ctrlx + x) / 2.0f64
                    let my = (ctrly + y) / 2.0f64
                    add_quad(sc, curx, cury, ctrlx, ctrly, mx, my)
                    curx = mx
                    cury = my
                }
                ctrlx = x
                ctrly = y
                has_ctrl = true
            }
        }
        if has_ctrl {
            add_quad(sc, curx, cury, ctrlx, ctrly, firstx, firsty)
        } else if curx != firstx || cury != firsty {
            add_line(sc, curx, cury, firstx, firsty)
        }
        first = last + 1usize
    }
}

// The x of piece `e` where its y is `y`.
fn piece_x(sc: *Scratch, e: usize, y: f64) -> f64 {
    let ax = sc.x0[e]
    let ay = sc.y0[e]
    let bx = sc.x1[e]
    let by = sc.y1[e]
    if !sc.quad[e] {
        let t = (y - ay) / (by - ay)
        ret ax + t * (bx - ax)
    }
    let qx = sc.cx[e]
    let qy = sc.cy[e]
    let a = ay - 2.0f64 * qy + by
    let b = 2.0f64 * (qy - ay)
    let c = ay - y
    var t = 0.0f64
    var small = a
    if small < 0.0f64 { small = 0.0f64 - small }
    if small < 0.000000000001f64 {
        t = (0.0f64 - c) / b
    } else {
        var disc = b * b - 4.0f64 * a * c
        if disc < 0.0f64 { disc = 0.0f64 }
        let r = math.sqrt[f64](disc)
        let t1 = (0.0f64 - b + r) / (2.0f64 * a)
        let t2 = (0.0f64 - b - r) / (2.0f64 * a)
        if t1 >= 0.0f64 && t1 <= 1.0f64 { t = t1 } else { t = t2 }
    }
    if t < 0.0f64 { t = 0.0f64 }
    if t > 1.0f64 { t = 1.0f64 }
    let u = 1.0f64 - t
    ret u * u * ax + 2.0f64 * t * u * qx + t * t * bx
}

// One sample line's spans into the column counts: the winding rule over the pieces crossing `yc`, each covered sample worth `wgt`.
// `upper` flips which end of a piece counts at a y where a piece ends exactly on the line (lower end in, upper out; or the reverse), so
// a line that runs along an edge counts the edge's samples either way: GDI's samples on the outline are inside. Answers whether a
// piece had an end on the line, which is when the other convention is worth a second pass.
fn scanline(sc: *Scratch, yc: f64, yrow: f64, xlo64: f64, cols: usize, wgt: i64, upper: bool, xline: bool) -> bool {
    var m = 0usize
    var e = 0usize
    var tie = false
    while e < sc.n {
        let y0 = sc.y0[e]
        let y1 = sc.y1[e]
        if y0 == yc || y1 == yc { tie = true }
        var crosses = (y0 <= yc) != (y1 <= yc)
        if upper { crosses = (y0 < yc) != (y1 < yc) }
        if crosses {
            var x = 0.0f64
            if xline {
                x = piece_x(sc, e, yc)
            } else if (y0 <= yrow) != (y1 <= yrow) {
                x = piece_x(sc, e, yrow)
            } else {
                var d0 = y0 - yrow
                var d1 = y1 - yrow
                if d0 < 0.0f64 { d0 = 0.0f64 - d0 }
                if d1 < 0.0f64 { d1 = 0.0f64 - d1 }
                if d0 < d1 { x = sc.x0[e] } else { x = sc.x1[e] }
            }
            var dir = -1i64
            if y1 > y0 { dir = 1i64 }
            if m < MAX_CROSS {
                // Insertion by (x, direction).
                var at = m
                while at > 0usize && (sc.hx[at - 1usize] > x || (sc.hx[at - 1usize] == x && sc.hd[at - 1usize] > dir)) {
                    sc.hx[at] = sc.hx[at - 1usize]
                    sc.hd[at] = sc.hd[at - 1usize]
                    at = at - 1usize
                }
                sc.hx[at] = x
                sc.hd[at] = dir
                m += 1usize
            }
        }
        e += 1usize
    }
    // The samples of this line, 1 each, so that a sample two spans cover (or two passes) counts once.
    var w = 0i64
    var i = 0usize
    while i + 1usize < m {
        w = w + sc.hd[i]
        if w != 0i64 {
            let xa = sc.hx[i]
            let xb = sc.hx[i + 1usize]
            var ka = i64(math.ceil[f64]((xa - xlo64) * 6.0f64 / 64.0f64 - 0.5f64 - 0.000000001f64))
            var kb = i64(math.floor[f64]((xb - xlo64) * 6.0f64 / 64.0f64 - 0.5f64 + 0.000000001f64))
            if ka < 0i64 { ka = 0i64 }
            if kb > i64(cols) - 1i64 { kb = i64(cols) - 1i64 }
            var k = ka
            while k <= kb {
                sc.line[usize(k) + 12usize] = wgt
                k += 1i64
            }
        }
        i += 1usize
    }
    ret tie
}

// Rasterises the outline into the buffer (clipped to its window). False when the glyph has too many pieces or is too wide.
fn add_glyph(sc: *Scratch, o: *const tthint.Outline, pen: i64, baseline: i64) -> bool {
    if o.n == 0usize { ret true }
    flatten(sc, o, pen)
    if sc.over { ret false }
    var minx = o.cur[0usize]
    var maxx = minx
    var miny = o.cur[1usize]
    var maxy = miny
    var i = 1usize
    while i < o.n {
        let x = o.cur[2usize * i]
        let y = o.cur[2usize * i + 1usize]
        if x < minx { minx = x }
        if x > maxx { maxx = x }
        if y < miny { miny = y }
        if y > maxy { maxy = y }
        i += 1usize
    }
    let lo = pen + tthint.fdiv(minx - o.pp1x, 64i64) - 2i64
    let hi = pen + tthint.fdiv(maxx - o.pp1x + 63i64, 64i64) + 3i64
    let y_lo = tthint.fdiv(miny, 64i64) - 1i64
    let y_hi = tthint.fdiv(maxy + 63i64, 64i64) + 1i64
    let cols = usize(hi - lo) * 6usize
    if cols > MAX_COLS { ret false }
    let xlo64 = f64(lo * 64i64)
    var mode = raster_mode & 15i64
    if mode == 0i64 {
        mode = 7i64
        if o.hinted { mode = 12i64 }
    }
    let subs = usize(hi - lo) * 3usize
    var r = y_hi - 1i64
    while r >= y_lo {
        // The device row of pixel row r (up from the baseline).
        let row = baseline - 1i64 - r
        if row >= sc.ky0 && row < sc.ky0 + i64(sc.kh) {
            var z = 0usize
            while z < cols + 24usize {
                sc.counts[z] = 0i64
                z += 1usize
            }
            // Five sample lines to the row at .1 .3 .5 .7 .9, weighted 1 2 3 2 1 (a vertical triangle filter), each a plain
            // inside-or-not test of six samples to the pixel; a sample line that runs along an outline's edge is taken both ways.
            var j = 0usize
            while j < 5usize {
                let yc = f64(r * 64i64) + (f64(j) + 0.5f64) * 64.0f64 / 5.0f64
                var wgt = 1i64
                if (mode & 8i64) != 0i64 {
                    wgt = 9i64
                    if j != 2usize {
                        j += 1usize
                        continue
                    }
                }
                if (mode & 1i64) != 0i64 && (mode & 8i64) == 0i64 {
                    if j == 1usize || j == 3usize { wgt = 2i64 }
                    if j == 2usize { wgt = 3i64 }
                }
                z = 0usize
                while z < cols + 24usize {
                    sc.line[z] = 0i64
                    z += 1usize
                }
                let xline = (mode & 2i64) != 0i64
                let yrow = f64(r * 64i64) + 32.0f64
                let tie = scanline(sc, yc, yrow, xlo64, cols, wgt, false, xline)
                if tie && (mode & 4i64) != 0i64 { let again = scanline(sc, yc, yrow, xlo64, cols, wgt, true, xline) }
                z = 0usize
                while z < cols + 24usize {
                    sc.counts[z] = sc.counts[z] + sc.line[z]
                    z += 1usize
                }
                j += 1usize
            }
            var m = 0usize
            while m < subs {
                var n = 0i64
                var q = 0usize
                while q < 6usize {
                    n = n + sc.counts[2usize * m + q + 12usize - 2usize]
                    q += 1usize
                }
                if n > 0i64 {
                    var kv = (n * 2i64 + 5i64) / 10i64
                    if (mode & 9i64) != 0i64 { kv = (n + 4i64) / 9i64 }
                    if kv > 6i64 { kv = 6i64 }
                    let sx = lo * 3i64 + i64(m)
                    let col = sx - sc.kx0 * 3i64
                    if col >= 0i64 && col < i64(sc.kw) * 3i64 {
                        let at = usize(row - sc.ky0) * sc.kw * 3usize + usize(col)
                        if i64(sc.kbuf[at]) < kv { sc.kbuf[at] = u8(kv) }
                    }
                }
                m += 1usize
            }
        }
        r = r - 1i64
    }
    ret true
}

// GDI's blend of one channel, byte for byte (fitted to 7168 measured pixels of real GDI text, grey on grey, and checked on every
// oracle atlas): the background and the text colour go through an 8-bit gamma table (255 * (i / 255) ^ 1.2, rounded), are mixed
// with the coverage k / 6 as a 16.16 fraction (round(65536 * k / 6), which is why a tie rounds the way it does), rounded to a byte,
// and come back through the inverse table. A channel of coverage 0 in a pixel some other channel covers goes through the tables
// too, so it can come out a level off its background (64 becomes 65); only a pixel no channel covers is left alone.
var gamma_ready: bool = false
var gamma_dec: [256]i64 = zero
var gamma_enc: [256]i64 = zero

fn gamma_init() {
    if gamma_ready { ret }
    var i = 0usize
    while i < 256usize {
        let x = f64(i) / 255.0f64
        gamma_dec[i] = i64(math.floor[f64](255.0f64 * math.pow[f64](x, 1.2f64) + 0.5f64))
        gamma_enc[i] = i64(math.floor[f64](255.0f64 * math.pow[f64](x, 1.0f64 / 1.2f64) + 0.5f64))
        i += 1usize
    }
    gamma_ready = true
}

// The byte a channel gets: `bg` and `fg` bytes, `k` the coverage 0..6 in sixths.
fn blend_byte(bg: i64, fg: i64, k: i64) -> i64 {
    gamma_init()
    let al = (k * 65536i64 + 3i64) / 6i64
    let mixed = (gamma_dec[usize(bg)] * (65536i64 - al) + gamma_dec[usize(fg)] * al + 32768i64) >> 16u32
    ret gamma_enc[usize(mixed)]
}

fn to_byte(v: f32) -> i64 {
    var b = i64(math.floor[f64](f64(v) * 255.0f64 + 0.5f64))
    if b < 0i64 { b = 0i64 }
    if b > 255i64 { b = 255i64 }
    ret b
}

// `blend_byte` on 0..1 channel values, the result again a whole byte over 255.
fn blend(bg: f32, fg: f32, k: i64) -> f32 {
    ret f32(f64(blend_byte(to_byte(bg), to_byte(fg), k)) / 255.0f64)
}

// The same blend for a coverage `a` in 0..1 that is not a whole number of sixths (a clip mask or the brush's alpha scales them): the
// float form of the formula, one level off here and there.
fn blend_a(bg: f32, fg: f32, a: f64) -> f32 {
    if !(a > 0.0f64) { ret bg }
    let b = math.pow[f64](f64(bg), 1.2f64)
    let f = math.pow[f64](f64(fg), 1.2f64)
    let v = math.pow[f64]((1.0f64 - a) * b + a * f, 1.0f64 / 1.2f64)
    ret f32(math.floor[f64](v * 255.0f64 + 0.5f64) / 255.0f64)
}
