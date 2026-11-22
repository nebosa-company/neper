// R plm pgmm (plm 2.6): the Arellano-Bond difference and the Blundell-Bond system GMM estimators, one and two steps, with the individual or two-way effects, the lagged-y and exogenous-x regressors, the GMM instruments for y and for the first gx exogenous variables (collapsed or not), the exogenous instruments for the others, the Sargan test, the Arellano-Bond m1/m2 tests, the Wald tests and vcovHC.pgmm.
//
// The panel arrives padded: nid individuals by nt periods, y[i * nt + t], x[(i * nt + t) * kx + j], a missing value is NaN. The model is y ~ lag(y, 1:p) + lag(x_j, 0:xq) | lag(y, ya:yb) + lag(x_j, xa:xb) for j < gx, the other x_j (and their lags) serving as their own instruments, as plm does when the formula has two parts.
//
// Not here: the generalised inverse plm falls back to when A1 or A2 is singular (the call fails instead), instrument lags that reach before the first period, lost.ts for the system estimator beyond 2 (plm's own W2 shape stops making sense there), model-frame transformations of the variables.

use e.algo.stat.gparot as gp
use e.math
use e.mem

type Spec = struct { nid: usize, nt: usize, kx: usize, p: usize, xq: usize, gx: usize, ya: usize, yb: usize, xa: usize, xb: usize, collapse: usize, twoways: usize, twosteps: usize, ld: usize, fsm: usize }

// everything the tests and vcovHC need after the fit; the per-individual matrices are stored one after another
type Gmm = struct { nid: usize, nr: usize, nc: usize, kt: usize, kv: usize, tl1: usize, tl2: usize, twosteps: usize, ld: usize, twoways: usize, nt: usize, y: []f64, x: []f64, w: []f64, res: []f64, coef: []f64, coef1: []f64, a1: []f64, a2: []f64, b1: []f64, vc: []f64, wx: []f64, wy: []f64 }

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn zeros(a: *mem.Arena, n: usize) -> ([]f64, err) {
    let (v, e) = mem.alloc[f64](a, n + 1usize)
    if e != ok { ret (v, e) }
    var i = 0usize
    while i < n + 1usize {
        v[i] = 0.0f64
        i += 1usize
    }
    ret (v, ok)
}

// c (m by p) = A (m by n) B (n by p)
fn mul(a: *mem.Arena, x: []const f64, m: usize, n: usize, y: []const f64, p: usize) -> ([]f64, err) {
    let (c, e) = zeros(a, m * p)
    if e != ok { ret (c, e) }
    var i = 0usize
    while i < m {
        var k = 0usize
        while k < n {
            let v = x[i * n + k]
            if v != 0.0f64 {
                var j = 0usize
                while j < p {
                    c[i * p + j] += v * y[k * p + j]
                    j += 1usize
                }
            }
            k += 1usize
        }
        i += 1usize
    }
    ret (c, ok)
}

// c (n by p) = A' B for A (m by n), B (m by p)
fn cross(a: *mem.Arena, x: []const f64, m: usize, n: usize, y: []const f64, p: usize) -> ([]f64, err) {
    let (c, e) = zeros(a, n * p)
    if e != ok { ret (c, e) }
    var k = 0usize
    while k < m {
        var i = 0usize
        while i < n {
            let v = x[k * n + i]
            if v != 0.0f64 {
                var j = 0usize
                while j < p {
                    c[i * p + j] += v * y[k * p + j]
                    j += 1usize
                }
            }
            i += 1usize
        }
        k += 1usize
    }
    ret (c, ok)
}

fn transpose(a: *mem.Arena, x: []const f64, m: usize, n: usize) -> ([]f64, err) {
    let (c, e) = zeros(a, m * n)
    if e != ok { ret (c, e) }
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < n {
            c[j * m + i] = x[i * n + j]
            j += 1usize
        }
        i += 1usize
    }
    ret (c, ok)
}

fn maxu(x: usize, y: usize) -> usize {
    if x > y { ret x }
    ret y
}

fn minu(x: usize, y: usize) -> usize {
    if x < y { ret x }
    ret y
}

// the value of main column j at 1-based period t for individual i: lag(y, j + 1) for j < p, then the lags of each x
fn lev(s: *const Spec, y: []const f64, x: []const f64, i: usize, j: usize, t: usize) -> f64 {
    var lag = j + 1usize
    var xv = 0usize
    var isy = 1usize
    if j >= s.p {
        let q = j - s.p
        xv = q / (s.xq + 1usize)
        lag = q % (s.xq + 1usize)
        isy = 0usize
    }
    if t <= lag { ret nan() }
    let tt = t - lag
    if isy == 1usize { ret y[i * s.nt + tt - 1usize] }
    ret x[(i * s.nt + tt - 1usize) * s.kx + xv]
}

fn series(s: *const Spec, y: []const f64, x: []const f64, i: usize, v: usize, t: usize) -> f64 {
    if v == 0usize { ret y[i * s.nt + t - 1usize] }
    ret x[(i * s.nt + t - 1usize) * s.kx + v - 1usize]
}

// the instrument columns of one gmm variable (non collapsed: the ragged blocks of makegmm; collapsed: the most recent first)
fn gmm_cols(s: *const Spec, v: usize, tl1: usize) -> usize {
    var lo = s.ya
    var hi = s.yb
    if v > 0usize {
        lo = s.xa
        hi = s.xb
    }
    let nt = s.nt
    if s.collapse == 1usize { ret minu(nt - lo, hi + 1usize - lo) }
    var tot = 0usize
    var t = tl1 + 1usize
    while t <= nt {
        let top = t - lo
        let bot = maxu(1usize, t - minu(t - 1usize, hi))
        tot += top - bot + 1usize
        t += 1usize
    }
    ret tot
}

fn fit(a: *mem.Arena, s: *const Spec, y: []const f64, x: []const f64, g: *Gmm) -> err {
    let nid = s.nid
    let nt = s.nt
    let kx = s.kx
    let p = s.p
    let xq = s.xq
    let ngv = 1usize + s.gx
    let kk = p + kx * (xq + 1usize)
    var maxlag = p
    if xq > maxlag && kx > 0usize { maxlag = xq }
    var gmin = s.ya
    if s.gx > 0usize && s.xa < gmin { gmin = s.xa }
    if gmin == 0usize { ret gp.Singular }
    let tl1 = maxu(maxlag + 1usize, gmin)
    let tl2 = maxu(maxlag, gmin - 1usize)
    let ld = s.ld
    if ld == 1usize && tl2 > 2usize { ret gp.Singular }
    if tl1 + 1usize > nt { ret gp.Singular }
    if tl1 + 1usize <= s.ya { ret gp.Singular }
    if s.gx > 0usize && tl1 + 1usize <= s.xa { ret gp.Singular }
    let nr1 = nt - tl1
    var nr2 = 0usize
    if ld == 1usize { nr2 = nt - tl2 }
    let nr = nr1 + nr2
    var kv = 0usize
    if s.twoways == 1usize {
        if ld == 1usize {
            kv = nr2
        } else {
            kv = nr1
        }
    }
    let kt = kk + kv
    let nz = (kx - s.gx) * (xq + 1usize)
    var nc1g = 0usize
    var v = 0usize
    while v < ngv {
        nc1g += gmm_cols(s, v, tl1)
        v += 1usize
    }
    var w2c = 0usize
    if ld == 1usize {
        if s.collapse == 1usize {
            w2c = ngv
        } else {
            w2c = ngv * (nt - 2usize)
        }
        if s.twoways == 1usize { w2c += nr2 }
    }
    var nc = nc1g + nz
    if ld == 1usize {
        nc = nc1g + w2c + 2usize * nz
    } else {
        if s.twoways == 1usize { nc += nr1 }
    }
    let (yv, e1) = zeros(a, nid * nr)
    let (xv, e2) = zeros(a, nid * nr * kt)
    let (wv, e3) = zeros(a, nid * nr * nc)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    // the time dummies: V1 (rows of the differenced equations) and V2 (the level equations)
    let (v1, e4) = zeros(a, nr1 * kv)
    let (v2, e5) = zeros(a, nr2 * kv)
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if s.twoways == 1usize {
        if ld == 0usize {
            var r = 0usize
            while r < nr1 {
                v1[r * kv + r] = 1.0f64
                if r > 0usize { v1[r * kv + r - 1usize] = -1.0f64 }
                r += 1usize
            }
        } else {
            var r = 0usize
            while r < nr2 {
                v2[r * kv] = 1.0f64
                if r > 0usize { v2[r * kv + r] = 1.0f64 }
                r += 1usize
            }
            r = 0usize
            while r < nr1 {
                var c = 0usize
                while c < kv {
                    v1[r * kv + c] = v2[(r + 1usize) * kv + c] - v2[r * kv + c]
                    c += 1usize
                }
                r += 1usize
            }
        }
    }
    var i = 0usize
    while i < nid {
        let yo = i * nr
        let xo = i * nr * kt
        let wo = i * nr * nc
        // the differenced equations
        var r = 0usize
        while r < nr1 {
            let t = tl1 + 1usize + r
            yv[yo + r] = y[i * nt + t - 1usize] - y[i * nt + t - 2usize]
            var j = 0usize
            while j < kk {
                xv[xo + r * kt + j] = lev(s, y, x, i, j, t) - lev(s, y, x, i, j, t - 1usize)
                j += 1usize
            }
            var c = 0usize
            while c < kv {
                xv[xo + r * kt + kk + c] = v1[r * kv + c]
                c += 1usize
            }
            r += 1usize
        }
        // the level equations
        r = 0usize
        while r < nr2 {
            let t = tl2 + 1usize + r
            yv[yo + nr1 + r] = y[i * nt + t - 1usize]
            var j = 0usize
            while j < kk {
                xv[xo + (nr1 + r) * kt + j] = lev(s, y, x, i, j, t)
                j += 1usize
            }
            var c = 0usize
            while c < kv {
                xv[xo + (nr1 + r) * kt + kk + c] = v2[r * kv + c]
                c += 1usize
            }
            r += 1usize
        }
        // gmm instruments of the differenced equations
        var col = 0usize
        v = 0usize
        while v < ngv {
            var lo = s.ya
            var hi = s.yb
            if v > 0usize {
                lo = s.xa
                hi = s.xb
            }
            let ncv = gmm_cols(s, v, tl1)
            var before = 0usize
            r = 0usize
            while r < nr1 {
                let t = tl1 + 1usize + r
                if t <= lo { ret gp.Singular }
                let top = t - lo
                let bot = maxu(1usize, t - minu(t - 1usize, hi))
                var q = bot
                while q <= top {
                    if s.collapse == 1usize {
                        wv[wo + r * nc + col + (top - q)] = series(s, y, x, i, v, q)
                    } else {
                        wv[wo + r * nc + col + before + (q - bot)] = series(s, y, x, i, v, q)
                    }
                    q += 1usize
                }
                before += top - bot + 1usize
                r += 1usize
            }
            col += ncv
            v += 1usize
        }
        if ld == 0usize && s.twoways == 1usize {
            r = 0usize
            while r < nr1 {
                var c = 0usize
                while c < kv {
                    wv[wo + r * nc + col + c] = v1[r * kv + c]
                    c += 1usize
                }
                r += 1usize
            }
            col += kv
        }
        // the gmm instruments of the level equations: the lagged differences
        if ld == 1usize {
            v = 0usize
            while v < ngv {
                var rho = 0usize
                while rho + 2usize < nt {
                    var rw = rho
                    if tl2 == 1usize { rw = rho + 1usize }
                    let d = series(s, y, x, i, v, rho + 2usize) - series(s, y, x, i, v, rho + 1usize)
                    var cc = col
                    if s.collapse == 1usize {
                        cc = col + v
                    } else {
                        cc = col + v * (nt - 2usize) + rho
                    }
                    wv[wo + (nr1 + rw) * nc + cc] = d
                    rho += 1usize
                }
                v += 1usize
            }
            if s.collapse == 1usize {
                col += ngv
            } else {
                col += ngv * (nt - 2usize)
            }
            if s.twoways == 1usize {
                r = 0usize
                while r < nr2 {
                    var c = 0usize
                    while c < kv {
                        wv[wo + (nr1 + r) * nc + col + c] = v2[r * kv + c]
                        c += 1usize
                    }
                    r += 1usize
                }
                col += kv
            }
        }
        // the exogenous instruments: the main columns of the x that are not gmm instruments
        if nz > 0usize {
            r = 0usize
            while r < nr1 {
                var m = 0usize
                while m < nz {
                    wv[wo + r * nc + col + m] = xv[xo + r * kt + p + s.gx * (xq + 1usize) + m]
                    m += 1usize
                }
                r += 1usize
            }
            col += nz
            if ld == 1usize {
                r = 0usize
                while r < nr2 {
                    var m = 0usize
                    while m < nz {
                        wv[wo + (nr1 + r) * nc + col + m] = xv[xo + (nr1 + r) * kt + p + s.gx * (xq + 1usize) + m]
                        m += 1usize
                    }
                    r += 1usize
                }
                col += nz
            }
        }
        // rows with a missing value anywhere in y or the regressors are dropped, the other missing values are zeros
        r = 0usize
        while r < nr {
            var bad = yv[yo + r] != yv[yo + r]
            var j = 0usize
            while j < kk {
                let z = xv[xo + r * kt + j]
                if z != z { bad = true }
                j += 1usize
            }
            if bad {
                yv[yo + r] = 0.0f64
                j = 0usize
                while j < kt {
                    xv[xo + r * kt + j] = 0.0f64
                    j += 1usize
                }
            }
            j = 0usize
            while j < nc {
                let z = wv[wo + r * nc + j]
                if bad || z != z { wv[wo + r * nc + j] = 0.0f64 }
                j += 1usize
            }
            // the exogenous instrument columns read NaN from xv before the row was zeroed; they were copied as NaN and are zero now
            r += 1usize
        }
        i += 1usize
    }
    // the first-step weights
    let (hm, e6) = zeros(a, nr * nr)
    if e6 != ok { ret e6 }
    if ld == 0usize {
        var r = 0usize
        while r < nr {
            if s.fsm == 1usize {
                hm[r * nr + r] = 2.0f64
                if r + 1usize < nr {
                    hm[r * nr + r + 1usize] = -1.0f64
                    hm[(r + 1usize) * nr + r] = -1.0f64
                }
            } else {
                hm[r * nr + r] = 1.0f64
            }
            r += 1usize
        }
    } else {
        var r = 0usize
        while r < nr1 {
            hm[r * nr + r] = 2.0f64
            if r + 1usize < nr1 {
                hm[r * nr + r + 1usize] = -1.0f64
                hm[(r + 1usize) * nr + r] = -1.0f64
            }
            r += 1usize
        }
        r = 0usize
        while r < nr2 {
            hm[(nr1 + r) * nr + nr1 + r] = 1.0f64
            r += 1usize
        }
        if s.fsm == 3usize {
            r = 0usize
            while r < nr1 {
                hm[r * nr + nr1 + r] = -1.0f64
                hm[r * nr + nr1 + r + 1usize] = 1.0f64
                hm[(nr1 + r) * nr + r] = -1.0f64
                hm[(nr1 + r + 1usize) * nr + r] = 1.0f64
                r += 1usize
            }
        }
    }
    let (a1r, e7) = zeros(a, nc * nc)
    let (wx, e8) = zeros(a, nc * kt)
    let (wy, e9) = zeros(a, nc)
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    i = 0usize
    while i < nid {
        let wi = wv[i * nr * nc..(i + 1usize) * nr * nc]
        let xi = xv[i * nr * kt..(i + 1usize) * nr * kt]
        let yi = yv[i * nr..(i + 1usize) * nr]
        let (hw, e10) = mul(a, hm, nr, nr, wi, nc)
        if e10 != ok { ret e10 }
        let (aa, e11) = cross(a, wi, nr, nc, hw, nc)
        if e11 != ok { ret e11 }
        let (wxi, e12) = cross(a, wi, nr, nc, xi, kt)
        if e12 != ok { ret e12 }
        let (wyi, e13) = cross(a, wi, nr, nc, yi, 1usize)
        if e13 != ok { ret e13 }
        var q = 0usize
        while q < nc * nc {
            a1r[q] += aa[q]
            q += 1usize
        }
        q = 0usize
        while q < nc * kt {
            wx[q] += wxi[q]
            q += 1usize
        }
        q = 0usize
        while q < nc {
            wy[q] += wyi[q]
            q += 1usize
        }
        i += 1usize
    }
    let (a1i, e14) = gp.invert(a, a1r, nc)
    if e14 != ok { ret e14 }
    var q = 0usize
    while q < nc * nc {
        a1i[q] = a1i[q] * f64(nid)
        q += 1usize
    }
    let (a1wx, e15) = mul(a, a1i, nc, nc, wx, kt)
    if e15 != ok { ret e15 }
    let (wxa, e16) = cross(a, wx, nc, kt, a1wx, kt)
    if e16 != ok { ret e16 }
    let (b1, e17) = gp.invert(a, wxa, kt)
    if e17 != ok { ret e17 }
    let (a1wy, e18) = mul(a, a1i, nc, nc, wy, 1usize)
    if e18 != ok { ret e18 }
    let (y1, e19) = cross(a, wx, nc, kt, a1wy, 1usize)
    if e19 != ok { ret e19 }
    let (cf, e20) = mul(a, b1, kt, kt, y1, 1usize)
    if e20 != ok { ret e20 }
    let (res, e21) = zeros(a, nid * nr)
    if e21 != ok { ret e21 }
    residuals(xv, yv, cf, nid, nr, kt, res)
    // second-step weights from the first-step residuals
    let (a2r, e22) = zeros(a, nc * nc)
    if e22 != ok { ret e22 }
    i = 0usize
    while i < nid {
        let wi = wv[i * nr * nc..(i + 1usize) * nr * nc]
        let (we, e23) = cross(a, wi, nr, nc, res[i * nr..(i + 1usize) * nr], 1usize)
        if e23 != ok { ret e23 }
        var r1 = 0usize
        while r1 < nc {
            var r2 = 0usize
            while r2 < nc {
                a2r[r1 * nc + r2] += we[r1] * we[r2]
                r2 += 1usize
            }
            r1 += 1usize
        }
        i += 1usize
    }
    let (a2i, e24) = gp.invert(a, a2r, nc)
    if e24 != ok { ret e24 }
    g.coef1 = cf
    g.coef = cf
    g.vc = b1
    if s.twosteps == 1usize {
        let (a2wx, e25) = mul(a, a2i, nc, nc, wx, kt)
        if e25 != ok { ret e25 }
        let (wxa2, e26) = cross(a, wx, nc, kt, a2wx, kt)
        if e26 != ok { ret e26 }
        let (vc2, e27) = gp.invert(a, wxa2, kt)
        if e27 != ok { ret e27 }
        let (a2wy, e28) = mul(a, a2i, nc, nc, wy, 1usize)
        if e28 != ok { ret e28 }
        let (y2, e29) = cross(a, wx, nc, kt, a2wy, 1usize)
        if e29 != ok { ret e29 }
        let (c2, e30) = mul(a, vc2, kt, kt, y2, 1usize)
        if e30 != ok { ret e30 }
        g.coef = c2
        g.vc = vc2
        residuals(xv, yv, c2, nid, nr, kt, res)
    }
    g.nid = nid
    g.nr = nr
    g.nc = nc
    g.kt = kt
    g.kv = kv
    g.tl1 = tl1
    g.tl2 = tl2
    g.twosteps = s.twosteps
    g.ld = ld
    g.twoways = s.twoways
    g.nt = nt
    g.y = yv
    g.x = xv
    g.w = wv
    g.res = res
    g.a1 = a1i
    g.a2 = a2i
    g.b1 = b1
    g.wx = wx
    g.wy = wy
    ret ok
}

fn residuals(xv: []const f64, yv: []const f64, cf: []const f64, nid: usize, nr: usize, kt: usize, res: []f64) {
    var i = 0usize
    while i < nid {
        var r = 0usize
        while r < nr {
            var f = 0.0f64
            var j = 0usize
            while j < kt {
                f += xv[(i * nr + r) * kt + j] * cf[j]
                j += 1usize
            }
            res[i * nr + r] = yv[i * nr + r] - f
            r += 1usize
        }
        i += 1usize
    }
}

// vcovHC.pgmm: the robust covariance of the final coefficients (kt by kt) into out
fn vcov_hc(a: *mem.Arena, g: *const Gmm, out: []f64) -> err {
    let nc = g.nc
    let kt = g.kt
    let nr = g.nr
    let (sa2, e1) = gp.invert(a, g.a2, nc)
    if e1 != ok { ret e1 }
    let (t1, e2) = mul(a, g.a1, nc, nc, g.wx, kt)
    if e2 != ok { ret e2 }
    let (t2, e3) = mul(a, sa2, nc, nc, t1, kt)
    if e3 != ok { ret e3 }
    let (t3, e4) = mul(a, g.a1, nc, nc, t2, kt)
    if e4 != ok { ret e4 }
    let (t4, e5) = cross(a, g.wx, nc, kt, t3, kt)
    if e5 != ok { ret e5 }
    let (t5, e6) = mul(a, g.b1, kt, kt, t4, kt)
    if e6 != ok { ret e6 }
    let (r1, e7) = mul(a, t5, kt, kt, g.b1, kt)
    if e7 != ok { ret e7 }
    if g.twosteps == 0usize {
        var q = 0usize
        while q < kt * kt {
            out[q] = r1[q]
            q += 1usize
        }
        ret ok
    }
    // res1s: first-step residuals
    let (res1, e8) = zeros(a, g.nid * nr)
    if e8 != ok { ret e8 }
    residuals(g.x, g.y, g.coef1, g.nid, nr, kt, res1)
    let (we, e9) = zeros(a, nc)
    if e9 != ok { ret e9 }
    var i = 0usize
    while i < g.nid {
        let (wei, e10) = cross(a, g.w[i * nr * nc..(i + 1usize) * nr * nc], nr, nc, g.res[i * nr..(i + 1usize) * nr], 1usize)
        if e10 != ok { ret e10 }
        var q = 0usize
        while q < nc {
            we[q] += wei[q]
            q += 1usize
        }
        i += 1usize
    }
    // pre = -B2 WX' A2 (kt by nc)
    let (pre0, e12) = cross(a, g.wx, nc, kt, g.a2, nc)
    if e12 != ok { ret e12 }
    let (pre1, e13) = mul(a, g.vc, kt, kt, pre0, nc)
    if e13 != ok { ret e13 }
    let (a2we, e14) = mul(a, g.a2, nc, nc, we, 1usize)
    if e14 != ok { ret e14 }
    let (dm, e15) = zeros(a, kt * kt)
    if e15 != ok { ret e15 }
    var k = 0usize
    while k < kt {
        let (wexkw, e16) = zeros(a, nc * nc)
        if e16 != ok { ret e16 }
        i = 0usize
        while i < g.nid {
            let wi = g.w[i * nr * nc..(i + 1usize) * nr * nc]
            // exk = -(xk e') - (xk e')'
            let (ex, e17) = zeros(a, nr * nr)
            if e17 != ok { ret e17 }
            var r = 0usize
            while r < nr {
                var c = 0usize
                while c < nr {
                    let z = g.x[(i * nr + r) * kt + k] * res1[i * nr + c]
                    let zt = g.x[(i * nr + c) * kt + k] * res1[i * nr + r]
                    ex[r * nr + c] = -z - zt
                    c += 1usize
                }
                r += 1usize
            }
            let (m1, e18) = mul(a, ex, nr, nr, wi, nc)
            if e18 != ok { ret e18 }
            let (m2, e19) = cross(a, wi, nr, nc, m1, nc)
            if e19 != ok { ret e19 }
            var q = 0usize
            while q < nc * nc {
                wexkw[q] += m2[q]
                q += 1usize
            }
            i += 1usize
        }
        let (m3, e20) = mul(a, wexkw, nc, nc, a2we, 1usize)
        if e20 != ok { ret e20 }
        // Dk = -B2 WX' A2 wexkw A2 We; pre1 is B2 WX' A2 and m3 is wexkw A2 We
        let (m5, e22) = mul(a, pre1, kt, nc, m3, 1usize)
        if e22 != ok { ret e22 }
        var r2 = 0usize
        while r2 < kt {
            dm[r2 * kt + k] = -m5[r2]
            r2 += 1usize
        }
        k += 1usize
    }
    let (db, e23) = mul(a, dm, kt, kt, g.vc, kt)
    if e23 != ok { ret e23 }
    let (dv, e24) = mul(a, dm, kt, kt, r1, kt)
    if e24 != ok { ret e24 }
    let (dt, e25) = transpose(a, dm, kt, kt)
    if e25 != ok { ret e25 }
    let (dvd, e26) = mul(a, dv, kt, kt, dt, kt)
    if e26 != ok { ret e26 }
    var r3 = 0usize
    while r3 < kt {
        var c3 = 0usize
        while c3 < kt {
            out[r3 * kt + c3] = g.vc[r3 * kt + c3] + db[r3 * kt + c3] + db[c3 * kt + r3] + dvd[r3 * kt + c3]
            c3 += 1usize
        }
        r3 += 1usize
    }
    ret ok
}

// the Sargan statistic (out[0]) and its degrees of freedom (out[1]); weights 0 is the second-step matrix, 1 the first
fn sargan(a: *mem.Arena, g: *const Gmm, weights: usize, out: []f64) -> err {
    let nc = g.nc
    let nr = g.nr
    let (z, e1) = zeros(a, nc)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < g.nid {
        let (zi, e2) = cross(a, g.w[i * nr * nc..(i + 1usize) * nr * nc], nr, nc, g.res[i * nr..(i + 1usize) * nr], 1usize)
        if e2 != ok { ret e2 }
        var q = 0usize
        while q < nc {
            z[q] += zi[q]
            q += 1usize
        }
        i += 1usize
    }
    var am = g.a2
    if weights == 1usize { am = g.a1 }
    let (az, e3) = mul(a, am, nc, nc, z, 1usize)
    if e3 != ok { ret e3 }
    var st = 0.0f64
    var q2 = 0usize
    while q2 < nc {
        st += z[q2] * az[q2]
        q2 += 1usize
    }
    out[0usize] = st
    out[1usize] = f64(nc) - f64(g.kt)
    ret ok
}

// Arellano-Bond m_order with the covariance vv (kt by kt)
fn mtest(a: *mem.Arena, g: *const Gmm, order: usize, vv: []const f64) -> f64 {
    let nc = g.nc
    let nr = g.nr
    let kt = g.kt
    let kdim = g.nt - g.tl2
    if order >= nr { ret nan() }
    if g.ld == 1usize && order + 1usize > kdim { ret nan() }
    let (rs, e1) = zeros(a, nr)
    let (rl, e2) = zeros(a, nr)
    let (ex, e3) = zeros(a, kt)
    let (xz, e4) = zeros(a, nc * kt)
    let (zve, e5) = zeros(a, nc)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret nan() }
    var num = 0.0f64
    var eve = 0.0f64
    var i = 0usize
    while i < g.nid {
        let ri = g.res[i * nr..(i + 1usize) * nr]
        var r = 0usize
        while r < nr {
            rs[r] = 0.0f64
            rl[r] = 0.0f64
            r += 1usize
        }
        if g.ld == 0usize {
            r = 0usize
            while r < nr {
                rs[r] = ri[r]
                if r >= order { rl[r] = ri[r - order] }
                r += 1usize
            }
        } else {
            // resid keeps the first kdim - 1 equations; residl is lagged inside them, both end in zeros
            r = 0usize
            while r + 1usize < kdim {
                rs[r] = ri[r]
                if r >= order { rl[r] = ri[r - order] }
                r += 1usize
            }
        }
        var dot = 0.0f64
        r = 0usize
        while r < nr {
            dot += rs[r] * rl[r]
            r += 1usize
        }
        num += dot
        eve += dot * dot
        let wi = g.w[i * nr * nc..(i + 1usize) * nr * nc]
        let xi = g.x[i * nr * kt..(i + 1usize) * nr * kt]
        let (exi, e6) = cross(a, rl, nr, 1usize, xi, kt)
        let (xzi, e7) = cross(a, wi, nr, nc, xi, kt)
        let (wr, e8) = cross(a, wi, nr, nc, rs, 1usize)
        if e6 != ok || e7 != ok || e8 != ok { ret nan() }
        var q = 0usize
        while q < kt {
            ex[q] += exi[q]
            q += 1usize
        }
        q = 0usize
        while q < nc * kt {
            xz[q] += xzi[q]
            q += 1usize
        }
        q = 0usize
        while q < nc {
            zve[q] += wr[q] * dot
            q += 1usize
        }
        i += 1usize
    }
    var am = g.a2
    if g.twosteps == 0usize { am = g.a1 }
    // EX B t(XZ) A ZVE
    let (t1, e9) = mul(a, g.vc, kt, kt, ex, 1usize)
    let (t2, e10) = mul(a, xz, nc, kt, t1, 1usize)
    let (t3, e11) = mul(a, am, nc, nc, zve, 1usize)
    let (t4, e12) = mul(a, vv, kt, kt, ex, 1usize)
    if e9 != ok || e10 != ok || e11 != ok || e12 != ok { ret nan() }
    var mid = 0.0f64
    var q3 = 0usize
    while q3 < nc {
        mid += t2[q3] * t3[q3]
        q3 += 1usize
    }
    var last = 0.0f64
    q3 = 0usize
    while q3 < kt {
        last += ex[q3] * t4[q3]
        q3 += 1usize
    }
    let den = eve - 2.0f64 * mid + last
    ret num / math.sqrt[f64](den)
}

// Wald statistic of a block of coefficients [from, to) under vv; df into out[1]
fn wald(a: *mem.Arena, g: *const Gmm, from: usize, to: usize, vv: []const f64, out: []f64) -> err {
    let m = to - from
    let kt = g.kt
    let (sub, e1) = zeros(a, m * m)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < m {
            sub[i * m + j] = vv[(from + i) * kt + from + j]
            j += 1usize
        }
        i += 1usize
    }
    let (inv, e2) = gp.invert(a, sub, m)
    if e2 != ok { ret e2 }
    var st = 0.0f64
    i = 0usize
    while i < m {
        var j = 0usize
        while j < m {
            st += g.coef[from + i] * inv[i * m + j] * g.coef[from + j]
            j += 1usize
        }
        i += 1usize
    }
    out[0usize] = st
    out[1usize] = f64(m)
    ret ok
}
