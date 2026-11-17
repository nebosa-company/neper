// R metafor rma.uni, the general random-effects and mixed-effects meta-regression (a design matrix with any number of moderators): the between-study variance by the methods
// FE, DL, HE, HS, HSk, SJ, PM, ML, REML, EB, PMM, GENQ, DLIT and SJIT with the package's own algorithms (the Fisher scoring loop of ML, REML and EB with its stopping
// threshold 1e-5 and step halving, uniroot's R_zeroin2 for PM and PMM, the ll0 check at zero), the Wald, t and Knapp-Hartung (knha, adhoc) tests of the coefficients and the omnibus
// test, the Q test, I2 and H2, R2, the fit statistics, and the sandwich variance for user weights or unweighted fits. The result is one vector; the layout is the O_ constants.
//
// Not here: the location-scale models (rma.ls), the selection models, GENQM (see metaformv for rma.mv), and the other r2def and i2def choices.

use e.math
use e.mem
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.algo.stat.pwr as pw

const KMAX: usize = 128usize
const PMAX: usize = 8usize
const OUTLEN: usize = 160usize

const O_TAU2: usize = 0usize
const O_SETAU2: usize = 1usize
const O_I2: usize = 2usize
const O_H2: usize = 3usize
const O_QE: usize = 4usize
const O_QEP: usize = 5usize
const O_QM: usize = 6usize
const O_QMP: usize = 7usize
const O_DDF: usize = 8usize
const O_LLML: usize = 9usize
const O_DEVML: usize = 10usize
const O_AICML: usize = 11usize
const O_BICML: usize = 12usize
const O_AICCML: usize = 13usize
const O_LLREML: usize = 14usize
const O_DEVREML: usize = 15usize
const O_AICREML: usize = 16usize
const O_BICREML: usize = 17usize
const O_AICCREML: usize = 18usize
const O_R2: usize = 19usize
const O_S2W: usize = 20usize
const O_VT: usize = 21usize
const O_RSSF: usize = 22usize
const O_CONV: usize = 23usize
const O_BETA: usize = 24usize
const O_SE: usize = 32usize
const O_Z: usize = 40usize
const O_P: usize = 48usize
const O_CILB: usize = 56usize
const O_CIUB: usize = 64usize
const O_VB: usize = 72usize

// the method codes: 0 FE, 1 DL, 2 HE, 3 HS, 4 HSk, 5 SJ, 6 PM, 7 ML, 8 REML, 9 EB, 10 PMM, 11 GENQ, 12 DLIT, 13 SJIT
// the test codes: 0 z, 1 t, 2 knha, 3 adhoc
type Ctl = struct { method: usize, test: usize, weighted: bool, level: f64, tau2fix: f64, intercept: bool, aw: []const f64, skipr2: bool, tau2min: f64 }

type Ws = struct {
    w: []f64, ymc: []f64, py: []f64, res: []f64, xs: []f64, pm: []f64, s: []f64, aug: []f64, b: []f64, tmp: []f64, wfe: []f64, ya: []f64, xa: []f64, sub: []f64, sub2: []f64, o2: []f64, big: []f64
}

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn new_ws(a: *mem.Arena) -> (Ws, err) {
    var z: Ws = zero
    let (w, e0) = mem.alloc[f64](a, KMAX)
    if e0 != ok { ret (z, e0) }
    let (ymc, e1) = mem.alloc[f64](a, KMAX)
    if e1 != ok { ret (z, e1) }
    let (py, e2) = mem.alloc[f64](a, KMAX)
    if e2 != ok { ret (z, e2) }
    let (res, e3) = mem.alloc[f64](a, KMAX)
    if e3 != ok { ret (z, e3) }
    let (xs, e4) = mem.alloc[f64](a, KMAX * PMAX)
    if e4 != ok { ret (z, e4) }
    let (pm, e5) = mem.alloc[f64](a, KMAX * KMAX)
    if e5 != ok { ret (z, e5) }
    let (s, e6) = mem.alloc[f64](a, PMAX * PMAX)
    if e6 != ok { ret (z, e6) }
    let (aug, e7) = mem.alloc[f64](a, 2usize * PMAX * PMAX)
    if e7 != ok { ret (z, e7) }
    let (b, e8) = mem.alloc[f64](a, PMAX)
    if e8 != ok { ret (z, e8) }
    let (tmp, e9) = mem.alloc[f64](a, PMAX * PMAX)
    if e9 != ok { ret (z, e9) }
    let (wfe, e10) = mem.alloc[f64](a, KMAX)
    if e10 != ok { ret (z, e10) }
    let (ya, e11) = mem.alloc[f64](a, KMAX)
    if e11 != ok { ret (z, e11) }
    let (xa, e12) = mem.alloc[f64](a, KMAX * PMAX)
    if e12 != ok { ret (z, e12) }
    let (sub, e13) = mem.alloc[f64](a, PMAX * PMAX)
    if e13 != ok { ret (z, e13) }
    let (sub2, e14) = mem.alloc[f64](a, PMAX * PMAX)
    if e14 != ok { ret (z, e14) }
    let (o2, e15) = mem.alloc[f64](a, OUTLEN)
    if e15 != ok { ret (z, e15) }
    let (big, e16) = mem.alloc[f64](a, 4usize * KMAX * KMAX)
    if e16 != ok { ret (z, e16) }
    z.o2 = o2
    z.big = big
    z.w = w
    z.ymc = ymc
    z.py = py
    z.res = res
    z.xs = xs
    z.pm = pm
    z.s = s
    z.aug = aug
    z.b = b
    z.tmp = tmp
    z.wfe = wfe
    z.ya = ya
    z.xa = xa
    z.sub = sub
    z.sub2 = sub2
    ret (z, ok)
}

// the inverse of the n by n row-major matrix m by Gauss-Jordan with partial pivoting, into out; false when singular. aug needs 2 n n values
fn invert_into(m: []const f64, n: usize, aug: []f64, out: []f64) -> bool {
    let n2 = 2usize * n
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            aug[i * n2 + j] = m[i * n + j]
            aug[i * n2 + n + j] = 0.0f64
            j += 1usize
        }
        aug[i * n2 + n + i] = 1.0f64
        i += 1usize
    }
    var c = 0usize
    while c < n {
        var piv = c
        var best = math.abs[f64](aug[c * n2 + c])
        var r = c + 1usize
        while r < n {
            let v = math.abs[f64](aug[r * n2 + c])
            if v > best {
                best = v
                piv = r
            }
            r += 1usize
        }
        if best == 0.0f64 { ret false }
        if piv != c {
            var j = 0usize
            while j < n2 {
                let t = aug[c * n2 + j]
                aug[c * n2 + j] = aug[piv * n2 + j]
                aug[piv * n2 + j] = t
                j += 1usize
            }
        }
        let d = aug[c * n2 + c]
        var j = 0usize
        while j < n2 {
            aug[c * n2 + j] = aug[c * n2 + j] / d
            j += 1usize
        }
        r = 0usize
        while r < n {
            if r != c {
                let f = aug[r * n2 + c]
                if f != 0.0f64 {
                    j = 0usize
                    while j < n2 {
                        aug[r * n2 + j] = aug[r * n2 + j] - f * aug[c * n2 + j]
                        j += 1usize
                    }
                }
            }
            r += 1usize
        }
        c += 1usize
    }
    i = 0usize
    while i < n {
        var j2 = 0usize
        while j2 < n {
            out[i * n + j2] = aug[i * n2 + n + j2]
            j2 += 1usize
        }
        i += 1usize
    }
    ret true
}

// log of the absolute determinant by Gaussian elimination with partial pivoting; work is a copy buffer of n n values
fn logdet_of(m: []const f64, n: usize, work: []f64) -> f64 {
    var i = 0usize
    while i < n * n {
        work[i] = m[i]
        i += 1usize
    }
    var ld = 0.0f64
    var c = 0usize
    while c < n {
        var piv = c
        var best = math.abs[f64](work[c * n + c])
        var r = c + 1usize
        while r < n {
            let v = math.abs[f64](work[r * n + c])
            if v > best {
                best = v
                piv = r
            }
            r += 1usize
        }
        if best == 0.0f64 { ret 0.0f64 - 1.0f64 / 0.0f64 }
        if piv != c {
            var j = 0usize
            while j < n {
                let t = work[c * n + j]
                work[c * n + j] = work[piv * n + j]
                work[piv * n + j] = t
                j += 1usize
            }
        }
        ld += math.log[f64](math.abs[f64](work[c * n + c]))
        r = c + 1usize
        while r < n {
            let f = work[r * n + c] / work[c * n + c]
            var j = c
            while j < n {
                work[r * n + j] = work[r * n + j] - f * work[c * n + j]
                j += 1usize
            }
            r += 1usize
        }
        c += 1usize
    }
    ret ld
}

// ws.s = (X'WX)^-1 for the diagonal weights w; false when singular
fn xwx_inv(ws: *Ws, x: []const f64, w: []const f64, k: usize, p: usize) -> bool {
    var a = 0usize
    while a < p {
        var c = 0usize
        while c < p {
            var t = 0.0f64
            var i = 0usize
            while i < k {
                t += x[i * p + a] * w[i] * x[i * p + c]
                i += 1usize
            }
            ws.tmp[a * p + c] = t
            c += 1usize
        }
        a += 1usize
    }
    ret invert_into(ws.tmp, p, ws.aug, ws.s)
}

// ws.b = (X'WX)^-1 X'W y (ws.s must hold the inverse)
fn beta_of(ws: *Ws, x: []const f64, w: []const f64, y: []const f64, k: usize, p: usize) {
    var a = 0usize
    while a < p {
        var t = 0.0f64
        var i = 0usize
        while i < k {
            t += x[i * p + a] * w[i] * y[i]
            i += 1usize
        }
        ws.tmp[a] = t
        a += 1usize
    }
    a = 0usize
    while a < p {
        var t = 0.0f64
        var c = 0usize
        while c < p {
            t += ws.s[a * p + c] * ws.tmp[c]
            c += 1usize
        }
        ws.b[a] = t
        a += 1usize
    }
}

// ws.pm = W - W X (X'WX)^-1 X' W; false when X'WX is singular
fn pbuild(ws: *Ws, x: []const f64, w: []const f64, k: usize, p: usize) -> bool {
    if !xwx_inv(ws, x, w, k, p) { ret false }
    var i = 0usize
    while i < k {
        var a = 0usize
        while a < p {
            var t = 0.0f64
            var c = 0usize
            while c < p {
                t += x[i * p + c] * ws.s[c * p + a]
                c += 1usize
            }
            ws.xs[i * p + a] = t
            a += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            var h = 0.0f64
            var a = 0usize
            while a < p {
                h += ws.xs[i * p + a] * x[j * p + a]
                a += 1usize
            }
            var v = 0.0f64 - w[i] * w[j] * h
            if i == j { v += w[i] }
            ws.pm[i * k + j] = v
            j += 1usize
        }
        i += 1usize
    }
    ret true
}

// y' P y with ws.py = P y
fn pquad(ws: *Ws, y: []const f64, k: usize) -> f64 {
    var q = 0.0f64
    var i = 0usize
    while i < k {
        var t = 0.0f64
        var j = 0usize
        while j < k {
            t += ws.pm[i * k + j] * y[j]
            j += 1usize
        }
        ws.py[i] = t
        q += y[i] * t
        i += 1usize
    }
    ret q
}

fn ptrace(ws: *Ws, k: usize) -> f64 {
    var t = 0.0f64
    var i = 0usize
    while i < k {
        t += ws.pm[i * k + i]
        i += 1usize
    }
    ret t
}

fn ptrace_v(ws: *Ws, v: []const f64, k: usize) -> f64 {
    var t = 0.0f64
    var i = 0usize
    while i < k {
        t += ws.pm[i * k + i] * v[i]
        i += 1usize
    }
    ret t
}

fn psum2(ws: *Ws, k: usize) -> f64 {
    var t = 0.0f64
    var i = 0usize
    while i < k * k {
        t += ws.pm[i] * ws.pm[i]
        i += 1usize
    }
    ret t
}

// sum(PV * t(PV)) with PV = P diag(v)
fn psum_pvtpv(ws: *Ws, v: []const f64, k: usize) -> f64 {
    var t = 0.0f64
    var i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            t += ws.pm[i * k + j] * ws.pm[i * k + j] * v[i] * v[j]
            j += 1usize
        }
        i += 1usize
    }
    ret t
}

// sum(PV * P)
fn psum_pvp(ws: *Ws, v: []const f64, k: usize) -> f64 {
    var t = 0.0f64
    var i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            t += ws.pm[i * k + j] * ws.pm[i * k + j] * v[j]
            j += 1usize
        }
        i += 1usize
    }
    ret t
}

fn weights_of(ws: *Ws, v: []const f64, tau2: f64, k: usize) {
    var i = 0usize
    while i < k {
        ws.w[i] = 1.0f64 / (v[i] + tau2)
        i += 1usize
    }
}

fn sorted_copy(src: []const f64, n: usize, dst: []f64) {
    var i = 0usize
    while i < n {
        let t = src[i]
        var j = i
        while j > 0usize && dst[j - 1usize] > t {
            dst[j] = dst[j - 1usize]
            j -= 1usize
        }
        dst[j] = t
        i += 1usize
    }
}

// R's median of the first n values of src, using dst as scratch
fn median_of(src: []const f64, n: usize, dst: []f64) -> f64 {
    sorted_copy(src, n, dst)
    if n % 2usize == 1usize { ret dst[n / 2usize] }
    ret 0.5f64 * (dst[n / 2usize - 1usize] + dst[n / 2usize])
}

// mad(y) = 1.4826 * median(|y - median(y)|)
fn mad_of(ws: *Ws, y: []const f64, k: usize) -> f64 {
    let m = median_of(y, k, ws.py)
    var i = 0usize
    while i < k {
        ws.res[i] = math.abs[f64](y[i] - m)
        i += 1usize
    }
    ret 1.4826f64 * median_of(ws.res, k, ws.py)
}

type QeCtx = struct { ws: *Ws, ymc: []const f64, v: []const f64, x: []const f64, k: usize, p: usize, tgt: f64 }

fn qe_cb(c: *QeCtx, tau2: f64) -> f64 {
    weights_of(c.ws, c.v, tau2, c.k)
    if !pbuild(c.ws, c.x, c.ws.w, c.k, c.p) { ret nan() }
    ret pquad(c.ws, c.ymc, c.k) - c.tgt
}

fn uniroot_tol() -> f64 { ret math.pow[f64](2.220446049250313e-16f64, 0.25f64) }

// the largest value of tau2 the root search looks at: max(100, 10 mad(yi)^2)
fn tau2_max(ws: *Ws, y: []const f64, k: usize) -> f64 {
    let m = mad_of(ws, y, k)
    var t = 10.0f64 * m * m
    if t < 100.0f64 { t = 100.0f64 }
    ret t
}

// the Q(tau2) of the weighted least squares fit on the centered effects, minus tgt: the root of PM and PMM; the first value is the tau2, the second 1 when found
fn pm_root(ws: *Ws, ymc: []const f64, v: []const f64, x: []const f64, k: usize, p: usize, tgt: f64, tau2min: f64, tmax: f64) -> (f64, bool) {
    var c: QeCtx = zero
    c.ws = ws
    c.ymc = ymc
    c.v = v
    c.x = x
    c.k = k
    c.p = p
    c.tgt = tgt
    let flo = qe_cb(&c, tau2min)
    if flo < 0.0f64 { ret (tau2min, true) }
    let fhi = qe_cb(&c, tmax)
    if fhi > 0.0f64 { ret (nan(), false) }
    let r = pw.zeroin[QeCtx](&c, qe_cb, tau2min, tmax, uniroot_tol(), 100i64)
    ret (r, true)
}

fn sum_of(w: []const f64, k: usize) -> f64 {
    var t = 0.0f64
    var i = 0usize
    while i < k {
        t += w[i]
        i += 1usize
    }
    ret t
}

// sum w (y - X b)^2 over the k rows, the residuals left in ws.res
fn rss_of(ws: *Ws, y: []const f64, x: []const f64, w: []const f64, b: []const f64, k: usize, p: usize) -> f64 {
    var t = 0.0f64
    var i = 0usize
    while i < k {
        var f = 0.0f64
        var a = 0usize
        while a < p {
            f += x[i * p + a] * b[a]
            a += 1usize
        }
        ws.res[i] = y[i] - f
        t += w[i] * ws.res[i] * ws.res[i]
        i += 1usize
    }
    ret t
}

// the (restricted) log-likelihood the ll0 check of ML and REML compares at the marginal weights w
fn ll_check(ws: *Ws, ymc: []const f64, x: []const f64, w: []const f64, sumlog: f64, k: usize, p: usize, reml: bool) -> f64 {
    let kf = f64(k)
    let pf = f64(p)
    if !xwx_inv(ws, x, w, k, p) { ret nan() }
    beta_of(ws, x, w, ymc, k, p)
    let rss = rss_of(ws, ymc, x, w, ws.b, k, p)
    let pi2 = 2.0f64 * 3.141592653589793f64
    if !reml { ret 0.0f64 - 0.5f64 * kf * math.log[f64](pi2) - 0.5f64 * sumlog - 0.5f64 * rss }
    let ld = 0.0f64 - logdet_of(ws.s, p, ws.sub)
    ret 0.0f64 - 0.5f64 * (kf - pf) * math.log[f64](pi2) - 0.5f64 * sumlog - 0.5f64 * ld - 0.5f64 * rss
}

fn sum_log(v: []const f64, tau2: f64, k: usize) -> f64 {
    var t = 0.0f64
    var i = 0usize
    while i < k {
        t += math.log[f64](v[i] + tau2)
        i += 1usize
    }
    ret t
}

fn fill_nan(out: []f64) {
    var i = 0usize
    while i < out.len {
        out[i] = nan()
        i += 1usize
    }
}

fn max0(x: f64) -> f64 {
    if x > 0.0f64 { ret x }
    ret 0.0f64
}
