// R ggdist's point and interval summaries of a sample: qi (quantile interval), hdi (the highest density interval of a bounded kernel density, falling back to hdci for one interval), hdci (the shortest interval by the type-5 quantile function) and Mode (the maximum of the bounded density), all with the default bandwidth (bandwidth_dpi) and bounder_cdf, no weights.
//
// Not here: weights, the other densities, bandwidths and bounders, adapt, the rvar and distribution methods and the plots.

use e.algo.stat.mass as ms
use e.algo.stat.modeest as me
use e.algo.stat.rdensity as rd
use e.math
use e.mem

fn sorted_of(a: *mem.Arena, x: []const f64) -> ([]f64, err) {
    let (s, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret (s, e) }
    var i = 0usize
    while i < x.len {
        s[i] = x[i]
        i += 1usize
    }
    i = 1usize
    while i < s.len {
        let t = s[i]
        var j = i
        while j > 0usize && s[j - 1usize] > t {
            s[j] = s[j - 1usize]
            j -= 1usize
        }
        s[j] = t
        i += 1usize
    }
    ret (s, ok)
}

// qi(x, .width): the type-7 quantiles at (1 - w) / 2 and (1 + w) / 2 of the sorted x
fn qi(s: []const f64, width: f64) -> (f64, f64) {
    ret (ms.quant7(s, (1.0f64 - width) / 2.0f64), ms.quant7(s, (1.0f64 + width) / 2.0f64))
}

// linear interpolation of (xs, ys) at z, clamped to the end values (approxfun rule = 2)
fn approx_clamp(xs: []const f64, ys: []const f64, z: f64) -> f64 {
    let n = xs.len
    if z <= xs[0usize] { ret ys[0usize] }
    if z >= xs[n - 1usize] { ret ys[n - 1usize] }
    var lo = 0usize
    var hi = n - 1usize
    while hi - lo > 1usize {
        let mid = (lo + hi) / 2usize
        if z < xs[mid] { hi = mid } else { lo = mid }
    }
    if z == xs[hi] { ret ys[hi] }
    ret ys[lo] + (ys[hi] - ys[lo]) * ((z - xs[lo]) / (xs[hi] - xs[lo]))
}

// the type-5 quantile function of the sorted x: x interpolated over p_k = (k - 1/2) / N, clamped
type QFive = struct { s: []const f64, p: []const f64 }

fn q5(c: *const QFive, p: f64) -> f64 { ret approx_clamp(c.p, c.s, p) }

fn hdci_obj(c: *const QFive, p: f64, w: f64) -> f64 { ret q5(c, p + w) - q5(c, p) }

// R's optimize (Brent's fmin) of p -> q(p + w) - q(p) on [0, 1 - w], tol = sqrt(eps)
fn fmin_hdci(c: *const QFive, w: f64) -> f64 {
    let cg = (3.0f64 - math.sqrt[f64](5.0f64)) * 0.5f64
    let eps = math.sqrt[f64](2.220446049250313e-16f64)
    let tol = eps
    var a = 0.0f64
    var b = 1.0f64 - w
    var v = a + cg * (b - a)
    var ww = v
    var x = v
    var d = 0.0f64
    var e = 0.0f64
    var fx = hdci_obj(c, x, w)
    var fv = fx
    var fw = fx
    let tol3 = tol / 3.0f64
    var guard = 0usize
    while guard < 1000usize {
        guard += 1usize
        let xm = (a + b) * 0.5f64
        let tol1 = eps * math.abs[f64](x) + tol3
        let t2 = tol1 * 2.0f64
        if math.abs[f64](x - xm) <= t2 - (b - a) * 0.5f64 { break }
        var p = 0.0f64
        var q = 0.0f64
        var r = 0.0f64
        if math.abs[f64](e) > tol1 {
            r = (x - ww) * (fx - fv)
            q = (x - v) * (fx - fw)
            p = (x - v) * q - (x - ww) * r
            q = (q - r) * 2.0f64
            if q > 0.0f64 { p = 0.0f64 - p } else { q = 0.0f64 - q }
            r = e
            e = d
        }
        var u = 0.0f64
        if math.abs[f64](p) >= math.abs[f64](q * 0.5f64 * r) || p <= q * (a - x) || p >= q * (b - x) {
            if x < xm { e = b - x } else { e = a - x }
            d = cg * e
        } else {
            d = p / q
            u = x + d
            if u - a < t2 || b - u < t2 {
                d = tol1
                if x >= xm { d = 0.0f64 - d }
            }
        }
        if math.abs[f64](d) >= tol1 {
            u = x + d
        } else if d > 0.0f64 {
            u = x + tol1
        } else {
            u = x - tol1
        }
        let fu = hdci_obj(c, u, w)
        if fu <= fx {
            if u < x { b = x } else { a = x }
            v = ww
            ww = x
            x = u
            fv = fw
            fw = fx
            fx = fu
        } else {
            if u < x { a = u } else { b = u }
            if fu <= fw || ww == x {
                v = ww
                fv = fw
                ww = u
                fw = fu
            } else if fu <= fv || v == x || v == ww {
                v = u
                fv = fu
            }
        }
    }
    ret x
}

// hdci(x, .width) of the sorted x
fn hdci(a: *mem.Arena, s: []const f64, width: f64) -> (f64, f64, err) {
    let n = s.len
    let (pk, e) = mem.alloc[f64](a, n)
    if e != ok { ret (0.0f64, 0.0f64, e) }
    var i = 0usize
    while i < n {
        pk[i] = (f64(i + 1usize) - 0.5f64) / f64(n)
        i += 1usize
    }
    var c = QFive{ s: s, p: pk }
    let p = fmin_hdci(&c, width)
    ret (q5(&c, p), q5(&c, p + width), ok)
}

// bandwidth_dpi: bw.SJ(method = "dpi"), bw.nrd0 when that fails
fn bw_dpi(a: *mem.Arena, x: []const f64, s: []const f64) -> f64 {
    let (b, e) = me.bw_sj(a, x, true)
    if e == ok && b == b && b > 0.0f64 { ret b }
    ret rd.bw_nrd0(x, s)
}

// density_bounded(x, n, trim = TRUE) with bandwidth_dpi and bounder_cdf: the grid into gx and the density into gy (n values each); returns the bandwidth
fn density_bounded(a: *mem.Arena, x: []const f64, s: []const f64, n: usize, gx: []f64, gy: []f64) -> (f64, err) {
    let nan = 0.0f64 / 0.0f64
    let len = s.len
    let bw = bw_dpi(a, x, s)
    let ps = math.pow[f64](0.01f64, 1.0f64 / f64(len))
    var b0 = 2.0f64 * s[0usize] - ms.quant7(s, 1.0f64 - ps)
    var b1 = 2.0f64 * s[len - 1usize] - ms.quant7(s, ps)
    let minb = s[0usize] - 3.0f64 * bw
    let maxb = s[len - 1usize] + 3.0f64 * bw
    let lb = minb <= b0
    let rb = b1 <= maxb
    if !lb { b0 = minb }
    if !rb { b1 = maxb }
    var nb = 0usize
    if lb { nb += 1usize }
    if rb { nb += 1usize }
    let nun = n + nb * (n - 1usize)
    let width = b1 - b0
    var from = b0
    var to = b1
    if lb { from = from - width }
    if rb { to = to + width }
    let (dx, e1) = mem.alloc[f64](a, nun)
    let (dy, e2) = mem.alloc[f64](a, nun)
    let (sc, e3) = mem.alloc[f64](a, 5usize * rd.grid_for(nun))
    if e1 != ok { ret (nan, e1) }
    if e2 != ok { ret (nan, e2) }
    if e3 != ok { ret (nan, e3) }
    rd.density_range(x, bw, nun, from, to, dy, sc)
    var q = 0usize
    while q < nun {
        dx[q] = from + (to - from) * f64(q) / f64(nun - 1usize)
        q += 1usize
    }
    var off = 0usize
    if lb { off = n - 1usize }
    q = 0usize
    while q < n {
        gx[q] = dx[off + q]
        gy[q] = dy[off + q]
        if lb { gy[q] += dy[n - 1usize - q] }
        if rb { gy[q] += dy[nun - 1usize - q] }
        q += 1usize
    }
    if b0 < s[0usize] || b1 > s[len - 1usize] {
        let (tx, e4) = mem.alloc[f64](a, n)
        let (ty, e5) = mem.alloc[f64](a, n)
        if e4 != ok { ret (nan, e4) }
        if e5 != ok { ret (nan, e5) }
        q = 0usize
        while q < n {
            tx[q] = s[0usize] + (s[len - 1usize] - s[0usize]) * f64(q) / f64(n - 1usize)
            ty[q] = approx_clamp(gx[0usize..n], gy[0usize..n], tx[q])
            q += 1usize
        }
        q = 0usize
        while q < n {
            gx[q] = tx[q]
            gy[q] = ty[q]
            q += 1usize
        }
    }
    ret (bw, ok)
}

// Mode(x, n = 2001): the grid point of the largest bounded density, the most frequent value (the first on ties) for whole numbers
fn mode_of(a: *mem.Arena, x: []const f64, s: []const f64) -> (f64, err) {
    var whole = true
    var i = 0usize
    while i < x.len {
        if x[i] != math.round[f64](x[i]) { whole = false }
        i += 1usize
    }
    if whole {
        var best = x[0usize]
        var bc = 0usize
        i = 0usize
        while i < x.len {
            var seen = false
            var j = 0usize
            while j < i {
                if x[j] == x[i] { seen = true }
                j += 1usize
            }
            if !seen {
                var c = 0usize
                j = 0usize
                while j < x.len {
                    if x[j] == x[i] { c += 1usize }
                    j += 1usize
                }
                if c > bc {
                    bc = c
                    best = x[i]
                }
            }
            i += 1usize
        }
        ret (best, ok)
    }
    let n = 2001usize
    let (gx, e1) = mem.alloc[f64](a, n)
    let (gy, e2) = mem.alloc[f64](a, n)
    if e1 != ok { ret (0.0f64, e1) }
    if e2 != ok { ret (0.0f64, e2) }
    let (bw, e3) = density_bounded(a, x, s, n, gx, gy)
    if e3 != ok { ret (0.0f64, e3) }
    var bi = 0usize
    i = 1usize
    while i < n {
        if gy[i] > gy[bi] { bi = i }
        i += 1usize
    }
    ret (gx[bi], ok)
}

// hdi(x, .width) with n = 4096: the intervals (lo, hi pairs) into out, returns how many (at most out.len / 2)
fn hdi(a: *mem.Arena, x: []const f64, s: []const f64, width: f64, out: []f64) -> (usize, err) {
    let len = s.len
    if width == 1.0f64 {
        out[0usize] = s[0usize]
        out[1usize] = s[len - 1usize]
        ret (1usize, ok)
    }
    let n = 4096usize
    let (dxs, e0) = mem.alloc[f64](a, n)
    var m = 0usize
    if e0 != ok { ret (0usize, e0) }
    var i = 0usize
    while i < n {
        let v = ms.quant7(s, (f64(i + 1usize) - 0.5f64) / f64(n))
        if m == 0usize || v != dxs[m - 1usize] {
            dxs[m] = v
            m += 1usize
        }
        i += 1usize
    }
    if m == 1usize {
        out[0usize] = dxs[0usize]
        out[1usize] = dxs[0usize]
        ret (1usize, ok)
    }
    let (gx, e1) = mem.alloc[f64](a, n)
    let (gy, e2) = mem.alloc[f64](a, n)
    let (dy, e3) = mem.alloc[f64](a, m)
    let (sy, e4) = mem.alloc[f64](a, m)
    if e1 != ok { ret (0usize, e1) }
    if e2 != ok { ret (0usize, e2) }
    if e3 != ok { ret (0usize, e3) }
    if e4 != ok { ret (0usize, e4) }
    let (bw, e5) = density_bounded(a, x, s, n, gx, gy)
    if e5 != ok { ret (0usize, e5) }
    i = 0usize
    while i < m {
        dy[i] = approx_clamp(gx, gy, dxs[i])
        sy[i] = dy[i]
        i += 1usize
    }
    // sy sorted for the quantile
    i = 1usize
    while i < m {
        let t = sy[i]
        var j = i
        while j > 0usize && sy[j - 1usize] > t {
            sy[j] = sy[j - 1usize]
            j -= 1usize
        }
        sy[j] = t
        i += 1usize
    }
    let alpha = ms.quant7(sy, 1.0f64 - width)
    var cnt = 0usize
    var tmp: [64]f64 = zero
    if dy[0usize] > alpha {
        tmp[cnt] = dxs[0usize]
        cnt += 1usize
    }
    let base = cnt
    var k = 0usize
    while k + 1usize < m {
        let ya = dy[k] - alpha
        let yb = dy[k + 1usize] - alpha
        if yb * ya <= 0.0f64 {
            let h = dxs[k + 1usize] - (dxs[k + 1usize] - dxs[k]) / (yb - ya) * yb
            var dup = false
            var z = base
            while z < cnt {
                if tmp[z] == h { dup = true }
                z += 1usize
            }
            if !dup && cnt < 62usize {
                tmp[cnt] = h
                cnt += 1usize
            }
        }
        k += 1usize
    }
    if dy[m - 1usize] > alpha {
        tmp[cnt] = dxs[m - 1usize]
        cnt += 1usize
    }
    let ni = cnt / 2usize
    if ni == 1usize {
        let (lo, hi, he) = hdci(a, s, width)
        out[0usize] = lo
        out[1usize] = hi
        ret (1usize, he)
    }
    var t = 0usize
    while t < ni * 2usize && t < out.len {
        out[t] = tmp[t]
        t += 1usize
    }
    ret (ni, ok)
}
