// A ClearType rasteriser for hinted glyph outlines (`e.text.tthint`). The model was fitted to the text the Windows GDI
// ClearType renderer draws: every pixel row is sampled by five scanlines (at the tenths 0.1, 0.3, ... 0.9 of the row), each
// scanline by six samples across a pixel (at the twelfths 1/12, 3/12, ...), and the coverage of a pixel's red, green and blue
// subpixels is the number of set samples in the six-sample window centred on the subpixel (columns 2m-2 .. 2m+3 for subpixel m,
// so neighbouring subpixels share four of six), divided by five and rounded half up to 0..6 sixths. Where an edge is slanted
// the scanline takes its crossing at the row's centre (an edge that does not reach the centre is taken at the endpoint nearest
// it), as GDI's does: a diagonal stem is the same width on every scanline of a row.
//
// `blend` composes the 0..6 coverage onto a colour as GDI does, a gamma of 1.2 on each channel:
// out = ((1 - a) * bg^1.2 + a * fg^1.2)^(1/1.2) with a = k / 6, per channel.
//
// `begin` opens a buffer over a window of device pixels and `add_glyph` rasterises hinted outlines into it, taking the larger
// of two glyphs' coverage where they meet, so a run drawn glyph by glyph is the same as the run at once.

use e.math
use e.mem
use e.text.tthint

const MAX_EDGES: usize = 24000usize
const MAX_CROSS: usize = 160usize
const MAX_COLS: usize = 6144usize
const SEGMENTS: usize = 16usize
const MAX_BUFFER: usize = 6291456usize

type Scratch = struct { ex0: []f64, ey0: []f64, ex1: []f64, ey1: []f64, n: usize, counts: []i64, kbuf: []u8, kx0: i64, ky0: i64, kw: usize, kh: usize, cx: [160]f64, cd: [160]i64, over: bool }

fn scratch(a: *mem.Arena) -> (*Scratch, err) {
    let (cells, cells_error) = mem.alloc[Scratch](a, 1usize)
    if cells_error != ok { ret (zero, cells_error) }
    let sc = &cells[0usize]
    var blank: Scratch = zero
    *sc = blank
    let (ex0, e0) = mem.alloc[f64](a, MAX_EDGES)
    if e0 != ok { ret (zero, e0) }
    let (ey0, e1) = mem.alloc[f64](a, MAX_EDGES)
    if e1 != ok { ret (zero, e1) }
    let (ex1, e2) = mem.alloc[f64](a, MAX_EDGES)
    if e2 != ok { ret (zero, e2) }
    let (ey1, e3) = mem.alloc[f64](a, MAX_EDGES)
    if e3 != ok { ret (zero, e3) }
    let (counts, e4) = mem.alloc[i64](a, MAX_COLS + 24usize)
    if e4 != ok { ret (zero, e4) }
    let (kbuf, e5) = mem.alloc[u8](a, MAX_BUFFER)
    if e5 != ok { ret (zero, e5) }
    sc.ex0 = ex0
    sc.ey0 = ey0
    sc.ex1 = ex1
    sc.ey1 = ey1
    sc.counts = counts
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

fn edge(sc: *Scratch, x0: f64, y0: f64, x1: f64, y1: f64) {
    if y0 == y1 { ret }
    if sc.n >= MAX_EDGES {
        sc.over = true
        ret
    }
    sc.ex0[sc.n] = x0
    sc.ey0[sc.n] = y0
    sc.ex1[sc.n] = x1
    sc.ey1[sc.n] = y1
    sc.n += 1usize
}

fn quad(sc: *Scratch, x0: f64, y0: f64, cx: f64, cy: f64, x1: f64, y1: f64) {
    var px = x0
    var py = y0
    var k = 1usize
    while k <= SEGMENTS {
        let t = f64(k) / f64(SEGMENTS)
        let u = 1.0f64 - t
        let x = u * u * x0 + 2.0f64 * t * u * cx + t * t * x1
        let y = u * u * y0 + 2.0f64 * t * u * cy + t * t * y1
        edge(sc, px, py, x, y)
        px = x
        py = y
        k += 1usize
    }
}

// The outline's contours as straight edges in device 26.6 units: the pen is a whole pixel, `baseline` the device row of the baseline.
fn flatten(sc: *Scratch, o: *const tthint.Outline, pen: i64, baseline: i64) {
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
            start = first + count - 1usize
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
                    edge(sc, curx, cury, x, y)
                } else {
                    quad(sc, curx, cury, ctrlx, ctrly, x, y)
                    has_ctrl = false
                }
                curx = x
                cury = y
            } else {
                if has_ctrl {
                    let mx = (ctrlx + x) / 2.0f64
                    let my = (ctrly + y) / 2.0f64
                    quad(sc, curx, cury, ctrlx, ctrly, mx, my)
                    curx = mx
                    cury = my
                }
                ctrlx = x
                ctrly = y
                has_ctrl = true
            }
        }
        if has_ctrl {
            quad(sc, curx, cury, ctrlx, ctrly, firstx, firsty)
        } else if curx != firstx || cury != firsty {
            edge(sc, curx, cury, firstx, firsty)
        }
        first = last + 1usize
    }
}

// One scanline's spans into the column counts: the winding rule over the edges crossing `yc`, an edge's x taken at `yrow`.
fn scanline(sc: *Scratch, yc: f64, yrow: f64, xlo64: f64, cols: usize) {
    var m = 0usize
    var e = 0usize
    while e < sc.n {
        let y0 = sc.ey0[e]
        let y1 = sc.ey1[e]
        if (y0 <= yc) != (y1 <= yc) {
            var yy = yrow
            if (y0 <= yrow) == (y1 <= yrow) {
                var d0 = y0 - yrow
                var d1 = y1 - yrow
                if d0 < 0.0f64 { d0 = 0.0f64 - d0 }
                if d1 < 0.0f64 { d1 = 0.0f64 - d1 }
                if d0 < d1 { yy = y0 } else { yy = y1 }
            }
            let t = (yy - y0) / (y1 - y0)
            let x = sc.ex0[e] + t * (sc.ex1[e] - sc.ex0[e])
            var dir = -1i64
            if y1 > y0 { dir = 1i64 }
            if m < MAX_CROSS {
                // Insertion by (x, direction).
                var at = m
                while at > 0usize && (sc.cx[at - 1usize] > x || (sc.cx[at - 1usize] == x && sc.cd[at - 1usize] > dir)) {
                    sc.cx[at] = sc.cx[at - 1usize]
                    sc.cd[at] = sc.cd[at - 1usize]
                    at = at - 1usize
                }
                sc.cx[at] = x
                sc.cd[at] = dir
                m += 1usize
            }
        }
        e += 1usize
    }
    var w = 0i64
    var i = 0usize
    while i + 1usize < m {
        w = w + sc.cd[i]
        if w != 0i64 {
            let xa = sc.cx[i]
            let xb = sc.cx[i + 1usize]
            var ka = i64(math.ceil[f64]((xa - xlo64) * 6.0f64 / 64.0f64 - 0.5f64 - 0.000000001f64))
            var kb = i64(math.floor[f64]((xb - xlo64) * 6.0f64 / 64.0f64 - 0.5f64 + 0.000000001f64))
            if ka < 0i64 { ka = 0i64 }
            if kb > i64(cols) - 1i64 { kb = i64(cols) - 1i64 }
            var k = ka
            while k <= kb {
                sc.counts[usize(k) + 12usize] = sc.counts[usize(k) + 12usize] + 1i64
                k += 1i64
            }
        }
        i += 1usize
    }
}

// Rasterises the outline into the buffer (clipped to its window). False when the glyph has too many edges or is too wide.
fn add_glyph(sc: *Scratch, o: *const tthint.Outline, pen: i64, baseline: i64) -> bool {
    if o.n == 0usize { ret true }
    flatten(sc, o, pen, baseline)
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
    let subs = usize(hi - lo) * 3usize
    var r = y_hi - 1i64
    while r >= y_lo {
        let row = baseline - 1i64 - r
        if row >= sc.ky0 && row < sc.ky0 + i64(sc.kh) {
            var z = 0usize
            while z < cols + 24usize {
                sc.counts[z] = 0i64
                z += 1usize
            }
            var j = 0usize
            while j < 5usize {
                let yc = f64(r * 64i64) + (f64(j) + 0.5f64) * 64.0f64 / 5.0f64
                scanline(sc, yc, f64(r * 64i64) + 32.0f64, xlo64, cols)
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

// GDI's gamma-1.2 blend of one channel: `bg` and `fg` in 0..1, `k` the coverage in sixths, and the result in 0..1.
fn blend(bg: f32, fg: f32, k: i64) -> f32 {
    if k <= 0i64 { ret bg }
    let a = f64(k) / 6.0f64
    let b = math.pow[f64](f64(bg), 1.2f64)
    let f = math.pow[f64](f64(fg), 1.2f64)
    let v = math.pow[f64]((1.0f64 - a) * b + a * f, 1.0f64 / 1.2f64)
    ret f32(math.floor[f64](v * 255.0f64 + 0.5f64) / 255.0f64)
}
