// A ClearType rasteriser for hinted glyph outlines (`e.text.tthint`). The model was fitted to the text the Windows GDI ClearType
// renderer draws, and it is a TrueType scan converter of the kind FreeType's monochrome rasteriser implements: the outline is
// converted to profiles (runs of edges that go one way in y), a sweep walks the scan lines and fills the pixels whose centre lies
// between a rising and a falling profile, and drop-out control lights a pixel for a feature that holds no centre. GDI runs it on a
// grid six samples wide to the pixel; a pixel's red, green and blue coverage is the number of set samples in the six-sample
// window centred on the subpixel (columns 2m-2 .. 2m+3 for subpixel m), 0..6.
//
// A glyph whose size was hinted (its programs ran) is rendered on one sample row to the pixel row and its coverage is the count
// itself. A glyph that was not (the size's prep switched hinting off, or the font has none) is rendered on five sample rows to the
// pixel row, weighted 1 2 3 2 1, and the coverage is (sum + 4) / 9. Both rest on the scan converter below: two sweeps (along the
// rows, then along the columns, which finds the drop-outs the first cannot), the pixel a drop-out lights picked by the size's scan
// type (`Outline.scan`) and stubs left out, as the font's SCANTYPE asks.
//
// Curves are the quadratics they are: a profile takes the exact x of the curve at each scan line, to 1/65536 of a sample.
//
// `blend` composes the 0..6 coverage onto a colour as GDI does, byte for byte: a gamma of 1.2 on each channel through 8-bit tables
// (see `blend_byte`).
//
// `begin` opens a buffer over a window of device pixels and `add_glyph` rasterises hinted outlines into it, taking the larger
// of two glyphs' coverage where they meet, so a run drawn glyph by glyph is the same as the run at once.

use e.math
use e.mem
use e.text.tthint

const MAX_PROF: usize = 900usize
const MAX_XPOOL: usize = 600000usize
const MAX_COLS: usize = 6144usize
const MAX_BUFFER: usize = 3145728usize
const MAX_BITMAP: usize = 4000000usize
const MAX_ACTIVE: usize = 128usize
const MAX_ARC: usize = 72usize

const PREC: i64 = 65536i64
const PHALF: i64 = 32768i64
const PSCALE: i64 = 1024i64
const FLOW_UP: i64 = 8i64
const OVER_TOP: i64 = 16i64
const OVER_BOT: i64 = 32i64

type Scratch = struct {
    kbuf: []u8, kx0: i64, ky0: i64, kw: usize, kh: usize,
    bm: []u8, bmw: usize, bmh: usize,
    pfl: []i64, pst: []i64, pht: []i64, pof: []i64, pnx: []i64, prm: []i64, pco: []i64, pxb: []i64, pcx: []i64, pdone: []bool,
    np: usize, xp: []i64, nx: usize,
    lq: []usize, rq: []usize, dl: []i64, dr: []i64,
    lastx: i64, lasty: i64, state: i64, cprof: i64, gprof: i64, miny: i64, maxy: i64, flipped: bool, over: bool,
    mode: i64, shift_smart: bool, has_bb: bool, bb_rlo: i64, bb_rhi: i64, bb_clo: i64, bb_chi: i64,
    ox: i64, oy: i64, vs: i64
}

fn scratch(a: *mem.Arena) -> (*Scratch, err) {
    let (cells, cells_error) = mem.alloc[Scratch](a, 1usize)
    if cells_error != ok { ret (zero, cells_error) }
    let sc = &cells[0usize]
    var blank: Scratch = zero
    *sc = blank
    let (kbuf, e0) = mem.alloc[u8](a, MAX_BUFFER)
    if e0 != ok { ret (zero, e0) }
    let (bm, e1) = mem.alloc[u8](a, MAX_BITMAP)
    if e1 != ok { ret (zero, e1) }
    let (xp, e2) = mem.alloc[i64](a, MAX_XPOOL)
    if e2 != ok { ret (zero, e2) }
    let (pfl, e3) = mem.alloc[i64](a, MAX_PROF)
    if e3 != ok { ret (zero, e3) }
    let (pst, e4) = mem.alloc[i64](a, MAX_PROF)
    if e4 != ok { ret (zero, e4) }
    let (pht, e5) = mem.alloc[i64](a, MAX_PROF)
    if e5 != ok { ret (zero, e5) }
    let (pof, e6) = mem.alloc[i64](a, MAX_PROF)
    if e6 != ok { ret (zero, e6) }
    let (pnx, e7) = mem.alloc[i64](a, MAX_PROF)
    if e7 != ok { ret (zero, e7) }
    let (prm, e8) = mem.alloc[i64](a, MAX_PROF)
    if e8 != ok { ret (zero, e8) }
    let (pco, e9) = mem.alloc[i64](a, MAX_PROF)
    if e9 != ok { ret (zero, e9) }
    let (pxb, e10) = mem.alloc[i64](a, MAX_PROF)
    if e10 != ok { ret (zero, e10) }
    let (pcx, e11) = mem.alloc[i64](a, MAX_PROF)
    if e11 != ok { ret (zero, e11) }
    let (pdone, e12) = mem.alloc[bool](a, MAX_PROF)
    if e12 != ok { ret (zero, e12) }
    let (lq, e13) = mem.alloc[usize](a, MAX_ACTIVE)
    if e13 != ok { ret (zero, e13) }
    let (rq, e14) = mem.alloc[usize](a, MAX_ACTIVE)
    if e14 != ok { ret (zero, e14) }
    let (dl, e15) = mem.alloc[i64](a, MAX_ACTIVE)
    if e15 != ok { ret (zero, e15) }
    let (dr, e16) = mem.alloc[i64](a, MAX_ACTIVE)
    if e16 != ok { ret (zero, e16) }
    sc.kbuf = kbuf
    sc.bm = bm
    sc.xp = xp
    sc.pfl = pfl
    sc.pst = pst
    sc.pht = pht
    sc.pof = pof
    sc.pnx = pnx
    sc.prm = prm
    sc.pco = pco
    sc.pxb = pxb
    sc.pcx = pcx
    sc.pdone = pdone
    sc.lq = lq
    sc.rq = rq
    sc.dl = dl
    sc.dr = dr
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

// ---------------------------------------------------------------- the scan converter

fn r_floor(x: i64) -> i64 { ret x & (0i64 - PREC) }
fn r_ceil(x: i64) -> i64 { ret (x + PREC - 1i64) & (0i64 - PREC) }
fn r_trunc(x: i64) -> i64 { ret x >> 16u32 }
fn r_frac(x: i64) -> i64 { ret x & (PREC - 1i64) }

// An overshoot is a profile end that lies in the far half between two scan lines.
fn r_top_over(x: i64) -> bool { ret x - r_floor(x) >= PHALF }
fn r_bot_over(x: i64) -> bool { ret r_ceil(x) - x >= PHALF }

// The scan-line position of point `i` of the outline in raster units (1/65536 of a sample along x, of a sub-row along y), swapped for
// the column sweep. x is pixels * 6 samples, y sub-rows.
fn r_point(sc: *Scratch, o: *const tthint.Outline, i: usize) -> (i64, i64) {
    let x = (o.cur[2usize * i] + sc.ox) * 6i64 * PSCALE - PHALF
    let y = (o.cur[2usize * i + 1usize] + sc.oy) * sc.vs * PSCALE - PHALF
    if sc.flipped { ret (y, x) }
    ret (x, y)
}

fn r_new_profile(sc: *Scratch, st: i64) {
    var p = sc.cprof
    if p < 0i64 || sc.pht[usize(p)] != 0i64 {
        if sc.np >= MAX_PROF {
            sc.over = true
            ret
        }
        p = i64(sc.np)
        sc.np += 1usize
        sc.cprof = p
        sc.pht[usize(p)] = 0i64
        sc.pxb[usize(p)] = i64(sc.nx)
    } else {
        sc.nx = usize(sc.pxb[usize(p)])
    }
    let pi = usize(p)
    sc.pfl[pi] = sc.mode & 7i64
    var e = 0i64
    if st == 1i64 {
        sc.pfl[pi] = sc.pfl[pi] | FLOW_UP
        if r_bot_over(sc.lasty) { sc.pfl[pi] = sc.pfl[pi] | OVER_BOT }
        e = r_ceil(sc.lasty)
    } else {
        if r_top_over(sc.lasty) { sc.pfl[pi] = sc.pfl[pi] | OVER_TOP }
        e = r_floor(sc.lasty)
    }
    if e > sc.maxy { e = sc.maxy }
    if e < sc.miny { e = sc.miny }
    sc.pst[pi] = r_trunc(e)
    if sc.lasty == e {
        if sc.nx >= MAX_XPOOL {
            sc.over = true
            ret
        }
        sc.xp[sc.nx] = sc.lastx
        sc.nx += 1usize
    }
    sc.state = st
}

fn r_end_profile(sc: *Scratch) {
    if sc.cprof < 0i64 { ret }
    let p = usize(sc.cprof)
    let h = i64(sc.nx) - sc.pxb[p]
    if h <= 0i64 { ret }
    sc.pht[p] = h
    if (sc.pfl[p] & FLOW_UP) != 0i64 {
        if r_top_over(sc.lasty) { sc.pfl[p] = sc.pfl[p] | OVER_TOP }
        sc.pof[p] = 0i64
    } else {
        if r_bot_over(sc.lasty) { sc.pfl[p] = sc.pfl[p] | OVER_BOT }
        let top = sc.pst[p] + 1i64
        sc.pst[p] = top - h
        sc.pof[p] = h - 1i64
    }
    if sc.gprof < 0i64 { sc.gprof = i64(p) }
    sc.pnx[p] = sc.gprof
}

// Ascending line: the x at every scan line it crosses (the start excluded, the end included), by FreeType's integer stepping.
fn r_line_up(sc: *Scratch, x1in: i64, y1: i64, x2: i64, y2: i64, miny: i64, maxy: i64) {
    if y2 < miny || y1 > maxy { ret }
    var e2 = r_floor(y2)
    if y2 > maxy { e2 = maxy }
    var e = r_ceil(y1)
    if y1 < miny { e = miny }
    if y1 == e { e += PREC }
    if e2 < e { ret }
    var size = r_trunc(e2 - e) + 1i64
    if sc.nx + usize(size) >= MAX_XPOOL {
        sc.over = true
        ret
    }
    var x1 = x1in
    var dx = x2 - x1
    let dy = y2 - y1
    if dx == 0i64 {
        while size > 0i64 {
            sc.xp[sc.nx] = x1
            sc.nx += 1usize
            size -= 1i64
        }
        ret
    }
    var ix = ((e - y1) * dx) / dy
    x1 += ix
    sc.xp[sc.nx] = x1
    sc.nx += 1usize
    size -= 1i64
    if size > 0i64 {
        var ax = dx * (e - y1) - dy * ix
        ix = (PREC * dx) / dy
        var rx = dx * PREC - dy * ix
        dx = 1i64
        if x2 < x1 {
            ax = 0i64 - ax
            rx = 0i64 - rx
            dx = -1i64
        }
        while size > 0i64 {
            x1 += ix
            ax += rx
            if ax >= dy {
                ax -= dy
                x1 += dx
            }
            sc.xp[sc.nx] = x1
            sc.nx += 1usize
            size -= 1i64
        }
    }
}

fn r_line_down(sc: *Scratch, x1: i64, y1: i64, x2: i64, y2: i64, miny: i64, maxy: i64) {
    r_line_up(sc, x1, 0i64 - y1, x2, 0i64 - y2, 0i64 - maxy, 0i64 - miny)
}

// A quadratic that runs one way in y, from (sx, sy) by (cx, cy) to (ex, ey): the exact x of the curve at each scan line it crosses.
fn r_arc(sc: *Scratch, sx: i64, sy: i64, cx: i64, cy: i64, ex: i64, ey: i64, down: bool) {
    var miny = sc.miny
    var maxy = sc.maxy
    var asy = sy
    var acy = cy
    var aey = ey
    if down {
        asy = 0i64 - sy
        acy = 0i64 - cy
        aey = 0i64 - ey
        miny = 0i64 - sc.maxy
        maxy = 0i64 - sc.miny
    }
    if aey < miny || asy > maxy { ret }
    var e2 = r_floor(aey)
    if aey > maxy { e2 = maxy }
    var e = r_ceil(asy)
    if asy < miny { e = miny }
    if asy == e { e += PREC }
    if e2 < e { ret }
    if sc.nx + usize(r_trunc(e2 - e)) + 1usize >= MAX_XPOOL {
        sc.over = true
        ret
    }
    let fsx = f64(sx)
    let fcx = f64(cx)
    let fex = f64(ex)
    let a = f64(asy - 2i64 * acy + aey)
    let b = 2.0f64 * f64(acy - asy)
    var flat = a
    if flat < 0.0f64 { flat = 0.0f64 - flat }
    while e <= e2 {
        let c = f64(asy - e)
        var t = 0.0f64
        if flat < 0.000000001f64 {
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
        let xv = u * u * fsx + 2.0f64 * t * u * fcx + t * t * fex
        sc.xp[sc.nx] = i64(math.floor[f64](xv + 0.5f64))
        sc.nx += 1usize
        e += PREC
    }
}

fn r_line_to(sc: *Scratch, x: i64, y: i64) {
    if y == sc.lasty {
        sc.lastx = x
        sc.lasty = y
        ret
    }
    var st = 2i64
    if sc.lasty < y { st = 1i64 }
    if sc.state != st {
        if sc.state != 0i64 { r_end_profile(sc) }
        r_new_profile(sc, st)
        if sc.over { ret }
    }
    if st == 1i64 {
        r_line_up(sc, sc.lastx, sc.lasty, x, y, sc.miny, sc.maxy)
    } else {
        r_line_down(sc, sc.lastx, sc.lasty, x, y, sc.miny, sc.maxy)
    }
    sc.lastx = x
    sc.lasty = y
}

// A conic arc: split until each piece is monotone in y, then scanned.
fn r_conic_to(sc: *Scratch, cx: i64, cy: i64, x: i64, y: i64) {
    var ax: [72]i64 = zero
    var ay: [72]i64 = zero
    var a = 0usize
    ax[2usize] = sc.lastx
    ay[2usize] = sc.lasty
    ax[1usize] = cx
    ay[1usize] = cy
    ax[0usize] = x
    ay[0usize] = y
    while !sc.over {
        let y1 = ay[a + 2usize]
        let y2 = ay[a + 1usize]
        let y3 = ay[a]
        let x3 = ax[a]
        var ymin = y1
        var ymax = y3
        if y1 > y3 {
            ymin = y3
            ymax = y1
        }
        if y2 < r_floor(ymin) || y2 > r_ceil(ymax) {
            if a + 5usize >= MAX_ARC {
                sc.over = true
                ret
            }
            // Split_Conic: the arc at `a` becomes two joined arcs at `a` and `a + 2`.
            let p0x = ax[a]
            let p1x = ax[a + 1usize]
            let p2x = ax[a + 2usize]
            let p0y = ay[a]
            let p1y = ay[a + 1usize]
            let p2y = ay[a + 2usize]
            ax[a + 4usize] = p2x
            let xa = p0x + p1x
            let xb = p1x + p2x
            ax[a + 3usize] = xb >> 1u32
            ax[a + 2usize] = (xa + xb) >> 2u32
            ax[a + 1usize] = xa >> 1u32
            ay[a + 4usize] = p2y
            let ya = p0y + p1y
            let yb = p1y + p2y
            ay[a + 3usize] = yb >> 1u32
            ay[a + 2usize] = (ya + yb) >> 2u32
            ay[a + 1usize] = ya >> 1u32
            a += 2usize
            continue
        } else if y1 != y3 {
            var stb = 2i64
            if y1 < y3 { stb = 1i64 }
            if sc.state != stb {
                if sc.state != 0i64 { r_end_profile(sc) }
                r_new_profile(sc, stb)
                if sc.over { ret }
            }
            r_arc(sc, ax[a + 2usize], y1, ax[a + 1usize], y2, ax[a], y3, stb == 2i64)
        }
        sc.lastx = x3
        sc.lasty = y3
        if a == 0usize { break }
        a -= 2usize
    }
}

// One contour of the outline as lines and conics.
fn r_contour(sc: *Scratch, o: *const tthint.Outline, first: usize, last: usize) {
    let (fx, fy) = r_point(sc, o, first)
    let (lx, ly) = r_point(sc, o, last)
    var vsx = fx
    var vsy = fy
    var pt = i64(first)
    var lim = i64(last)
    if (o.tags[first] & 1i64) == 0i64 {
        if (o.tags[last] & 1i64) != 0i64 {
            vsx = lx
            vsy = ly
            lim -= 1i64
        } else {
            vsx = (fx + lx) / 2i64
            vsy = (fy + ly) / 2i64
        }
        pt -= 1i64
    }
    sc.lastx = vsx
    sc.lasty = vsy
    while pt < lim && !sc.over {
        pt += 1i64
        let (x, y) = r_point(sc, o, usize(pt))
        if (o.tags[usize(pt)] & 1i64) != 0i64 {
            r_line_to(sc, x, y)
            continue
        }
        var cx = x
        var cy = y
        while true {
            if pt < lim {
                pt += 1i64
                let (nx, ny) = r_point(sc, o, usize(pt))
                if (o.tags[usize(pt)] & 1i64) != 0i64 {
                    r_conic_to(sc, cx, cy, nx, ny)
                    break
                }
                r_conic_to(sc, cx, cy, (cx + nx) / 2i64, (cy + ny) / 2i64)
                cx = nx
                cy = ny
                continue
            }
            r_conic_to(sc, cx, cy, vsx, vsy)
            ret
        }
    }
    r_line_to(sc, vsx, vsy)
}

// All profiles of the outline for one sweep; `lo_scan..hi_scan` the scan lines of the sweep.
fn r_convert(sc: *Scratch, o: *const tthint.Outline, lo_scan: i64, hi_scan: i64) {
    sc.np = 0usize
    sc.nx = 0usize
    sc.cprof = -1i64
    sc.state = 0i64
    sc.over = false
    sc.miny = lo_scan * PREC
    sc.maxy = hi_scan * PREC
    var first = 0usize
    var c = 0usize
    while c < o.nends && !sc.over {
        let last = o.ends[c]
        c += 1usize
        if last < first || last >= o.n {
            first = last + 1usize
            continue
        }
        sc.state = 0i64
        sc.gprof = -1i64
        r_contour(sc, o, first, last)
        first = last + 1usize
        if sc.gprof < 0i64 { continue }
        if r_frac(sc.lasty) == 0i64 && sc.lasty >= sc.miny && sc.lasty <= sc.maxy && sc.cprof >= 0i64 {
            if (sc.pfl[usize(sc.gprof)] & FLOW_UP) == (sc.pfl[usize(sc.cprof)] & FLOW_UP) && i64(sc.nx) > sc.pxb[usize(sc.cprof)] {
                sc.nx -= 1usize
            }
        }
        r_end_profile(sc)
    }
    // the contour loops: a profile's `next` is the one that follows it in the same contour
    var p = 0usize
    var prev = -1i64
    while p < sc.np {
        if sc.pht[p] > 0i64 {
            if prev >= 0i64 && sc.pnx[usize(prev)] == sc.pnx[p] { sc.pnx[usize(prev)] = i64(p) }
            prev = i64(p)
        }
        p += 1usize
    }
}

fn r_setpix(sc: *Scratch, scan: i64, pos: i64) {
    var row = scan
    var col = pos
    if sc.flipped {
        row = pos
        col = scan
    }
    if row >= 0i64 && row < i64(sc.bmh) && col >= 0i64 && col < i64(sc.bmw) {
        sc.bm[usize(row) * sc.bmw + usize(col)] = 1u8
    }
}

fn r_getpix(sc: *Scratch, scan: i64, pos: i64) -> bool {
    var row = scan
    var col = pos
    if sc.flipped {
        row = pos
        col = scan
    }
    if row >= 0i64 && row < i64(sc.bmh) && col >= 0i64 && col < i64(sc.bmw) {
        ret sc.bm[usize(row) * sc.bmw + usize(col)] != 0u8
    }
    ret false
}

// Insertion sort of the active profiles by their current x.
fn r_sort(sc: *Scratch, q: []usize, n: usize) {
    var i = 1usize
    while i < n {
        let v = q[i]
        var j = i
        while j > 0usize && sc.pcx[q[j - 1usize]] > sc.pcx[v] {
            q[j] = q[j - 1usize]
            j -= 1usize
        }
        q[j] = v
        i += 1usize
    }
}

fn r_smart(sc: *Scratch, p: i64, q: i64) -> i64 {
    var extra = PREC * 63i64 / 64i64
    if sc.shift_smart { extra += PREC }
    ret r_floor((p + q + extra) >> 1u32)
}

// The sweep: `flipped` false walks the rows (the profiles hold x per row), true the columns.
fn r_sweep(sc: *Scratch) {
    var np = 0usize
    var min_y = 2147483647i64
    var max_y = -2147483647i64
    var p = 0usize
    while p < sc.np {
        if sc.pht[p] > 0i64 {
            sc.pdone[p] = false
            sc.prm[p] = sc.pht[p]
            sc.pco[p] = sc.pof[p]
            sc.pcx[p] = sc.xp[usize(sc.pxb[p] + sc.pof[p])]
            if sc.pst[p] < min_y { min_y = sc.pst[p] }
            if sc.pst[p] + sc.pht[p] - 1i64 > max_y { max_y = sc.pst[p] + sc.pht[p] - 1i64 }
            np += 1usize
        } else {
            sc.pdone[p] = true
        }
        p += 1usize
    }
    if np == 0usize { ret }
    var lim_lo = 0i64
    var lim_hi = i64(sc.bmw) - 1i64
    if sc.flipped { lim_hi = i64(sc.bmh) - 1i64 }
    if sc.has_bb {
        if sc.flipped {
            lim_lo = sc.bb_rlo
            lim_hi = sc.bb_rhi
        } else {
            lim_lo = sc.bb_clo
            lim_hi = sc.bb_chi
        }
    }
    var nl = 0usize
    var nr = 0usize
    var y = min_y
    while y <= max_y {
        p = 0usize
        while p < sc.np {
            if !sc.pdone[p] && sc.pht[p] > 0i64 && sc.pst[p] == y {
                sc.pdone[p] = true
                if (sc.pfl[p] & FLOW_UP) != 0i64 {
                    if nl < MAX_ACTIVE {
                        sc.lq[nl] = p
                        nl += 1usize
                    }
                } else if nr < MAX_ACTIVE {
                    sc.rq[nr] = p
                    nr += 1usize
                }
            }
            p += 1usize
        }
        r_sort(sc, sc.lq, nl)
        r_sort(sc, sc.rq, nr)
        var nd = 0usize
        var k = 0usize
        while k < nl && k < nr {
            let pl = sc.lq[k]
            let pr = sc.rq[k]
            k += 1usize
            var x1 = sc.pcx[pl]
            var x2 = sc.pcx[pr]
            if x1 > x2 {
                let xs = x1
                x1 = x2
                x2 = xs
            }
            if r_ceil(x1) <= r_floor(x2) {
                if !sc.flipped {
                    var e1 = r_trunc(r_ceil(x1))
                    var e2 = r_trunc(r_floor(x2))
                    if e1 < 0i64 { e1 = 0i64 }
                    if e2 > i64(sc.bmw) - 1i64 { e2 = i64(sc.bmw) - 1i64 }
                    while e1 <= e2 {
                        r_setpix(sc, y, e1)
                        e1 += 1i64
                    }
                } else {
                    // the column sweep only marks span ends that lie exactly on a pixel centre
                    if x1 == r_ceil(x1) { r_setpix(sc, y, r_trunc(x1)) }
                    if x2 == r_floor(x2) { r_setpix(sc, y, r_trunc(x2)) }
                }
            } else {
                let dmode = sc.pfl[pl] & 7i64
                if (dmode & 2i64) != 0i64 { continue }
                if (dmode & 1i64) != 0i64 {
                    if sc.prm[pl] == 1i64 && sc.pnx[pl] == i64(pr) { continue }
                    if sc.pco[pl] == 0i64 && sc.pnx[pr] == i64(pl) { continue }
                }
                var xx2 = 0i64
                var xx1 = 0i64
                if (dmode & 4i64) != 0i64 {
                    xx2 = r_smart(sc, x1, x2)
                    if x1 > xx2 { xx1 = xx2 + PREC } else { xx1 = xx2 - PREC }
                } else {
                    xx2 = r_floor(x2)
                    xx1 = r_ceil(x1)
                }
                if nd < MAX_ACTIVE {
                    sc.dl[nd] = xx2
                    sc.dr[nd] = xx1
                    nd += 1usize
                }
            }
        }
        var d = 0usize
        while d < nd {
            var e1 = r_trunc(sc.dl[d])
            let e2 = r_trunc(sc.dr[d])
            d += 1usize
            if e1 < lim_lo || e1 > lim_hi {
                e1 = e2
            } else if e2 >= lim_lo && e2 <= lim_hi {
                if r_getpix(sc, y, e2) { continue }
            }
            if e1 >= lim_lo && e1 <= lim_hi { r_setpix(sc, y, e1) }
        }
        // the next scan line: each active profile moves on, an exhausted one leaves
        var kept = 0usize
        k = 0usize
        while k < nl {
            let q = sc.lq[k]
            sc.prm[q] -= 1i64
            if sc.prm[q] > 0i64 {
                sc.pco[q] += 1i64
                sc.pcx[q] = sc.xp[usize(sc.pxb[q] + sc.pco[q])]
                sc.lq[kept] = q
                kept += 1usize
            }
            k += 1usize
        }
        nl = kept
        kept = 0usize
        k = 0usize
        while k < nr {
            let q = sc.rq[k]
            sc.prm[q] -= 1i64
            if sc.prm[q] > 0i64 {
                sc.pco[q] -= 1i64
                sc.pcx[q] = sc.xp[usize(sc.pxb[q] + sc.pco[q])]
                sc.rq[kept] = q
                kept += 1usize
            }
            k += 1usize
        }
        nr = kept
        y += 1i64
    }
}

// Both sweeps of the outline into the bitmap `sc.bm` (`bmw` samples by `bmh` rows, row 0 at the bottom). False when it did not fit.
fn r_render(sc: *Scratch, o: *const tthint.Outline) -> bool {
    sc.flipped = false
    r_convert(sc, o, 0i64, i64(sc.bmh) - 1i64)
    if sc.over { ret false }
    r_sweep(sc)
    if (sc.mode & 2i64) == 0i64 {
        sc.flipped = true
        r_convert(sc, o, 0i64, i64(sc.bmw) - 1i64)
        if sc.over { ret false }
        r_sweep(sc)
    }
    ret true
}

// Rasterises the outline into the buffer (clipped to its window). False when the glyph has too many pieces or is too wide.
fn add_glyph(sc: *Scratch, o: *const tthint.Outline, pen: i64, baseline: i64) -> bool {
    if o.n == 0usize { ret true }
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
    var vs = 1i64
    if !o.hinted || o.smooth { vs = 5i64 }
    let rows = usize(y_hi - y_lo) * usize(vs)
    if cols * rows > MAX_BITMAP { ret false }
    sc.bmw = cols
    sc.bmh = rows
    var z = 0usize
    while z < cols * rows {
        sc.bm[z] = 0u8
        z += 1usize
    }
    sc.ox = pen * 64i64 - o.pp1x - lo * 64i64
    sc.oy = 0i64 - y_lo * 64i64
    sc.vs = vs
    sc.mode = o.scan & 7i64
    sc.shift_smart = (o.scan & 8i64) != 0i64
    sc.has_bb = false
    if vs == 1i64 {
        // drop-out pixels stay inside the glyph's own bitmap: whole pixel rows and columns round the outline's box
        sc.has_bb = true
        let rlo = tthint.fdiv(miny, 64i64) - y_lo
        let rhi = tthint.fdiv(maxy + 63i64, 64i64) - 1i64 - y_lo
        let clo = (tthint.fdiv(minx - o.pp1x, 64i64) + pen - lo) * 6i64
        let chi = (tthint.fdiv(maxx - o.pp1x + 63i64, 64i64) + pen - lo) * 6i64 - 1i64
        sc.bb_rlo = rlo
        sc.bb_rhi = rhi
        sc.bb_clo = clo
        sc.bb_chi = chi
    }
    if !r_render(sc, o) { ret false }
    // the coverage: the samples in the six-sample window of each subpixel
    let subs = usize(hi - lo) * 3usize
    var r = y_hi - 1i64
    while r >= y_lo {
        let row = baseline - 1i64 - r
        if row >= sc.ky0 && row < sc.ky0 + i64(sc.kh) {
            let b0 = usize(r - y_lo) * usize(vs)
            var m = 0usize
            while m < subs {
                var n = 0i64
                var j = 0usize
                while j < usize(vs) {
                    var wgt = 1i64
                    if vs == 5i64 {
                        wgt = 1i64
                        if j == 1usize || j == 3usize { wgt = 2i64 }
                        if j == 2usize { wgt = 3i64 }
                    }
                    var cnt = 0i64
                    var q = 0usize
                    while q < 6usize {
                        let s = i64(2usize * m + q) - 2i64
                        if s >= 0i64 && s < i64(cols) { cnt += i64(sc.bm[(b0 + j) * cols + usize(s)]) }
                        q += 1usize
                    }
                    n += wgt * cnt
                    j += 1usize
                }
                var kv = n
                if vs == 5i64 { kv = (n + 4i64) / 9i64 }
                if kv > 6i64 { kv = 6i64 }
                if kv > 0i64 {
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
