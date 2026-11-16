// R polspline logspline density estimates, evaluated from a fitted model: the log density is the cubic truncated-power
// spline `c0 + c1 x + sum_i k_i ((|x - t_i| + x - t_i) / 2)^3`, linear beyond the outer knots. dlogspline is the
// density (or its log), plogspline the distribution function and qlogspline the quantile function, built as the
// package's own evaluators build them (an integration grid at the knots, refined to four points per knot when the
// mass is not one to five places, 64-point Gauss-Legendre per piece, exact exponential tails, and for the quantile a
// Simpson table of 50 panels per knot interval with linear interpolation); the model (coefficients, knots, bounds)
// comes from `logspline()` in R.
//
// Not here: fitting (the stepwise knot addition and deletion, AIC penalty and the bounds search), oldlogspline,
// random generation, the other polspline models.

use e.math
use e.mem

type LogSpline = struct {
    c0: f64, c1: f64, kc: []const f64, knots: []const f64, lower: bool, lo: f64, upper: bool, hi: f64
}

// the log density at x (minus infinity outside a bound)
fn dlog(m: *const LogSpline, x: f64) -> f64 {
    var y = m.c0 + x * m.c1
    var i = 0usize
    while i < m.knots.len {
        let t = (math.abs[f64](x - m.knots[i]) + x - m.knots[i]) / 2.0f64
        y += m.kc[i] * t * t * t
        i += 1usize
    }
    if m.lower && x < m.lo { ret 0.0f64 - 1.0f64 / 0.0f64 }
    if m.upper && x > m.hi { ret 0.0f64 - 1.0f64 / 0.0f64 }
    ret y
}

fn dlogspline(m: *const LogSpline, x: f64, lg: bool) -> f64 {
    let y = dlog(m, x)
    if lg { ret y }
    ret math.exp[f64](y)
}

fn myexp(x: f64) -> f64 {
    if x > 576.0f64 { ret math.exp[f64](576.0f64) }
    ret math.exp[f64](x)
}

fn mylog(x: f64) -> f64 {
    if x < 1.0e-249f64 { ret 0.0f64 - 575.64627f64 }
    ret math.log[f64](x)
}

// the k-th positive node and weight of the nn-point Gauss-Legendre rule, nodes by Newton's method on the Legendre polynomial
fn gl_node(k: usize, nn: usize) -> (f64, f64) {
    var x = math.cos[f64](3.14159265358979323846f64 * (f64(k) + 0.75f64) / (f64(nn) + 0.5f64))
    var d = 1.0f64
    var it = 0usize
    while it < 100usize {
        var p0 = 1.0f64
        var p1 = x
        var j = 2usize
        while j <= nn {
            let p2 = ((2.0f64 * f64(j) - 1.0f64) * x * p1 - (f64(j) - 1.0f64) * p0) / f64(j)
            p0 = p1
            p1 = p2
            j += 1usize
        }
        d = f64(nn) * (x * p1 - p0) / (x * x - 1.0f64)
        let dx = p1 / d
        x -= dx
        if math.abs[f64](dx) < 1.0e-16f64 { it = 100usize }
        it += 1usize
    }
    ret (x, 2.0f64 / ((1.0f64 - x * x) * d * d))
}

fn poly(c: []const f64, x: f64) -> f64 {
    ret math.exp[f64](c[0usize] + x * (c[1usize] + x * (c[2usize] + x * c[3usize])))
}

// the integral of exp(cubic) over [k1, k2] by 64-point Gauss-Legendre
fn z3int(k1: f64, k2: f64, c: []const f64) -> f64 {
    if k2 == k1 { ret 0.0f64 }
    let r1 = (k2 - k1) / 2.0f64
    let r2 = (k2 + k1) / 2.0f64
    var vv = 0.0f64
    var i = 0usize
    while i < 32usize {
        let (nd, w) = gl_node(i, 64usize)
        let y = nd * r1
        let x1 = r2 - y
        let x2 = r2 + y
        vv += r1 * w * myexp(c[0usize] + x1 * (c[1usize] + x1 * (c[2usize] + x1 * c[3usize])))
        vv += r1 * w * myexp(c[0usize] + x2 * (c[1usize] + x2 * (c[2usize] + x2 * c[3usize])))
        i += 1usize
    }
    ret vv
}

// the integral of exp(c0 + c1 x) from -inf to t1 (j = 1) or t1 to inf (j = -1)
fn z1int(t1: f64, c: []const f64, j0: f64) -> f64 {
    var j = j0
    if c[1usize] < 0.0f64 { j = 0.0f64 - j }
    var f1 = mylog(math.abs[f64](1.0f64 / c[1usize])) + c[1usize] * t1 + c[0usize]
    if f1 > 600.0f64 { f1 = 600.0f64 }
    ret j * myexp(f1)
}

// the integral of exp(c0 + c1 x) over [t1, t2]
fn z2int(t1: f64, t2: f64, c: []const f64) -> f64 {
    if t2 == t1 { ret 0.0f64 }
    if c[1usize] != 0.0f64 {
        var i1 = 1.0f64
        if c[1usize] < 0.0f64 { i1 = 0.0f64 - 1.0f64 }
        var f1 = mylog(math.abs[f64](1.0f64 / c[1usize])) + c[1usize] * t1 + c[0usize]
        var f2 = f1 + c[1usize] * (t2 - t1)
        if f1 > 600.0f64 { f1 = 600.0f64 }
        if f2 > 600.0f64 { f2 = 600.0f64 }
        ret i1 * myexp(f2) - i1 * myexp(f1)
    }
    ret (t2 - t1) * myexp(c[0usize])
}

// polspline's integration grid: points kpl[0..nk], the cubic of each piece cpl[4 i..4 i + 3] and the cumulative mass ppl[i]
type Grid = struct { nk: usize, kpl: []f64, cpl: []f64, ppl: []f64 }

fn build_grid(a: *mem.Arena, m: *const LogSpline, refine: bool) -> (Grid, err) {
    var g: Grid = zero
    let lk = m.knots.len
    var nk = lk + 1usize
    if refine { nk = 4usize * lk - 2usize }
    let (kpl, e1) = mem.alloc[f64](a, nk + 1usize)
    let (cpl, e2) = mem.alloc[f64](a, 4usize * (nk + 1usize))
    let (ppl, e3) = mem.alloc[f64](a, nk + 1usize)
    if e1 != ok || e2 != ok || e3 != ok { ret (g, mem.Full) }
    var i = 0usize
    while i <= nk {
        kpl[i] = 0.0f64
        ppl[i] = 0.0f64
        if i < nk && i > 0usize {
            if refine {
                let j = (i - 1usize) / 4usize
                let r = f64(i) / 4.0f64 - f64(j) - 0.25f64
                if r > 0.01f64 { kpl[i] = (1.0f64 - r) * m.knots[j] + r * m.knots[j + 1usize] } else { kpl[i] = (1.0f64 - r) * m.knots[j] }
            } else {
                kpl[i] = m.knots[i - 1usize]
            }
        }
        if i == 0usize {
            kpl[0usize] = m.knots[0usize] - 1.0f64
            if m.lower { kpl[0usize] = m.lo }
        }
        if i == nk {
            kpl[nk] = m.knots[lk - 1usize] + 1.0f64
            if m.upper { kpl[nk] = m.hi }
        }
        cpl[4usize * i] = m.c0
        cpl[4usize * i + 1usize] = m.c1
        cpl[4usize * i + 2usize] = 0.0f64
        cpl[4usize * i + 3usize] = 0.0f64
        var j = 0usize
        while j < lk {
            var inc = i > j
            if refine { inc = i > 4usize * j }
            if !inc { j = lk } else {
                let kj = m.knots[j]
                cpl[4usize * i + 3usize] += m.kc[j]
                cpl[4usize * i + 2usize] -= 3.0f64 * m.kc[j] * kj
                cpl[4usize * i + 1usize] += 3.0f64 * m.kc[j] * kj * kj
                cpl[4usize * i] -= m.kc[j] * kj * kj * kj
                j += 1usize
            }
        }
        if i + 1usize >= nk {
            cpl[4usize * i + 3usize] = 0.0f64
            cpl[4usize * i + 2usize] = 0.0f64
        }
        i += 1usize
    }
    if m.lower { ppl[1usize] = z2int(kpl[0usize], kpl[1usize], cpl[0usize..4usize]) } else { ppl[1usize] = z1int(kpl[1usize], cpl[0usize..4usize], 1.0f64) }
    i = 1usize
    while i + 1usize < nk {
        ppl[i + 1usize] = z3int(kpl[i], kpl[i + 1usize], cpl[4usize * i..4usize * i + 4usize]) + ppl[i]
        i += 1usize
    }
    let lc = cpl[4usize * (nk - 1usize)..4usize * (nk - 1usize) + 4usize]
    if m.upper { ppl[nk] = z2int(kpl[nk - 1usize], kpl[nk], lc) + ppl[nk - 1usize] } else { ppl[nk] = z1int(kpl[nk - 1usize], lc, 0.0f64 - 1.0f64) + ppl[nk - 1usize] }
    g.nk = nk
    g.kpl = kpl
    g.cpl = cpl
    g.ppl = ppl
    ret (g, ok)
}

// the grid, refined when the mass is not one to five places, and normalised to total one
fn grid(a: *mem.Arena, m: *const LogSpline) -> (Grid, err) {
    var (g, e) = build_grid(a, m, false)
    if e != ok { ret (g, e) }
    if g.ppl[g.nk] < 0.99999f64 || g.ppl[g.nk] > 1.00001f64 {
        let (g2, e2) = build_grid(a, m, true)
        if e2 != ok { ret (g2, e2) }
        g = g2
    }
    let tot = g.ppl[g.nk]
    var i = 0usize
    while i <= g.nk {
        g.cpl[4usize * i] += math.log[f64](1.0f64 / tot)
        g.ppl[i] = g.ppl[i] / tot
        i += 1usize
    }
    ret (g, ok)
}

fn plogspline(a: *mem.Arena, m: *const LogSpline, q: f64) -> (f64, err) {
    if m.lower && q < m.lo { ret (0.0f64, ok) }
    if m.upper && q > m.hi { ret (1.0f64, ok) }
    let (g, e) = grid(a, m)
    if e != ok { ret (0.0f64, e) }
    let nk = g.nk
    if m.lower && q <= g.kpl[0usize] { ret (0.0f64, ok) }
    if q <= g.kpl[1usize] {
        if m.lower { ret (z2int(g.kpl[0usize], q, g.cpl[0usize..4usize]), ok) }
        ret (z1int(q, g.cpl[0usize..4usize], 1.0f64), ok)
    }
    var i = 1usize
    while i + 1usize < nk {
        if q <= g.kpl[i + 1usize] {
            let c = g.cpl[4usize * i..4usize * i + 4usize]
            let r = (g.ppl[i + 1usize] - g.ppl[i]) / z3int(g.kpl[i], g.kpl[i + 1usize], c)
            ret (g.ppl[i] + z3int(g.kpl[i], q, c) * r, ok)
        }
        i += 1usize
    }
    if !m.upper || q < g.kpl[nk] {
        let lc = g.cpl[4usize * (nk - 1usize)..4usize * (nk - 1usize) + 4usize]
        if m.upper { ret (1.0f64 - z2int(q, g.kpl[nk], lc), ok) }
        ret (1.0f64 - z1int(q, lc, 0.0f64 - 1.0f64), ok)
    }
    ret (1.0f64, ok)
}

// 1: -inf to x, 2: t to x, 3: x to inf, 4: x to t
fn pqexpi(version: usize, t0: f64, p0: f64, cf: []const f64) -> f64 {
    var t = t0
    var p = p0
    if cf[1usize] != 0.0f64 || version == 1usize || version == 3usize {
        p = p * cf[1usize]
        if version == 1usize && p < 0.0f64 { ret myexp(600.0f64) }
        if version == 3usize && p > 0.0f64 { ret 0.0f64 - myexp(600.0f64) }
        if version == 2usize || version == 4usize { t = myexp(t * cf[1usize] + cf[0usize]) }
        if version == 2usize && t + p < 0.0f64 { ret myexp(600.0f64) }
        if version == 4usize && t - p < 0.0f64 { ret 0.0f64 - myexp(600.0f64) }
        if version == 1usize { ret (mylog(p) - cf[0usize]) / cf[1usize] }
        if version == 2usize { ret (mylog(t + p) - cf[0usize]) / cf[1usize] }
        if version == 3usize { ret (mylog(0.0f64 - p) - cf[0usize]) / cf[1usize] }
        ret (mylog(t - p) - cf[0usize]) / cf[1usize]
    }
    if version == 2usize { ret t + p / myexp(cf[0usize]) }
    ret t - p / myexp(cf[0usize])
}

// polspline's quantile: exact inversion in the exponential tails, and inside a knot interval linear interpolation on a Simpson table of 50 panels
fn qlogspline(a: *mem.Arena, m: *const LogSpline, p: f64) -> (f64, err) {
    let nan = 0.0f64 / 0.0f64
    if p < 0.0f64 || p > 1.0f64 || p != p { ret (nan, ok) }
    let (g, e) = grid(a, m)
    if e != ok { ret (nan, e) }
    let nk = g.nk
    if p <= g.ppl[0usize] {
        if m.lower { ret (g.kpl[0usize], ok) }
        ret (0.0f64 - 1.0e100f64, ok)
    }
    if p <= g.ppl[1usize] {
        if m.lower { ret (pqexpi(2usize, g.kpl[0usize], p, g.cpl[0usize..4usize]), ok) }
        ret (pqexpi(1usize, g.kpl[0usize], p, g.cpl[0usize..4usize]), ok)
    }
    var i = 1usize
    while i + 1usize < nk {
        if p <= g.ppl[i + 1usize] {
            let c = g.cpl[4usize * i..4usize * i + 4usize]
            let k0 = g.kpl[i]
            let k1 = g.kpl[i + 1usize]
            let r = (k1 - k0) / 100.0f64
            let (f1, e1) = mem.alloc[f64](a, 101usize)
            let (y, e2) = mem.alloc[f64](a, 51usize)
            if e1 != ok || e2 != ok { ret (nan, mem.Full) }
            var s = 0usize
            while s < 101usize {
                f1[s] = poly(c, k0 + r * f64(s))
                s += 1usize
            }
            y[0usize] = 0.0f64
            s = 1usize
            while s <= 50usize {
                y[s] = y[s - 1usize] + r * (f1[2usize * (s - 1usize)] + 4.0f64 * f1[2usize * s - 1usize] + f1[2usize * s]) / 3.0f64
                s += 1usize
            }
            let sc = (g.ppl[i + 1usize] - g.ppl[i]) / y[50usize]
            s = 0usize
            while s <= 50usize {
                y[s] = g.ppl[i] + y[s] * sc
                s += 1usize
            }
            y[0usize] = g.ppl[i]
            y[50usize] = g.ppl[i + 1usize]
            var q = k0 - 1.0f64
            var si = 0usize
            while q < k0 && si < 50usize {
                if p >= y[si] && p <= y[si + 1usize] {
                    q = k0 + 2.0f64 * r * f64(si) + 2.0f64 * r * (p - y[si]) / (y[si + 1usize] - y[si])
                } else {
                    si += 1usize
                }
            }
            ret (q, ok)
        }
        i += 1usize
    }
    if p < g.ppl[nk] {
        let lc = g.cpl[4usize * (nk - 1usize)..4usize * (nk - 1usize) + 4usize]
        if m.upper { ret (pqexpi(4usize, g.kpl[nk], 1.0f64 - p, lc), ok) }
        ret (pqexpi(3usize, g.kpl[nk], 1.0f64 - p, lc), ok)
    }
    if m.upper { ret (g.kpl[nk], ok) }
    ret (1.0e100f64, ok)
}
