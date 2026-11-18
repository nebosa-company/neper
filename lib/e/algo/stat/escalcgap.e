// R metafor escalc, the measures that e.algo.stat.escalcmore dispatches here (it owns the small helpers too): the tetrachoric correlation (RTET, ZTET: optimize over rho, optim Nelder-Mead
// over rho and both cuts, the Hessian of optimhess, every probability from mvtnorm's bivariate normal), the matched-pair odds ratio MPORM, the bias-corrected correlation UCOR (metafor's
// .Fcalc is gsl's 2F1, summed as a series here), the partial and semi-partial correlations, ICC, R2 (R2F and ZR2F integrate the non-central F density as metafor does), CLES/AUC,
// the point-biserial-from-normal RBIS and ZBIS, SMCR and the three POMP measures.
//
// measure: 13 RTET 14 ZTET 15 MPORM (ai bi ci di [ri pi])   32 RBIS 33 ZBIS 34 D2ORL (m1i m2i sd1i sd2i n1i n2i)   35 POMPMD (those six, mini maxi)
//   52 UCOR (ri ni)   53 PCOR 54 ZPCOR (ri mi ni)   55 SPCOR 56 ZSPCOR (ri mi ni r2i)   57 ICC 58 ZICC (ri mi ni)   85 POMPMN (mi sdi ni mini maxi)
//   90 R2 91 ZR2 92 R2F 93 ZR2F (r2i mi ni)   94 CLES (ai n1i n2i mi)   95 CLESN (m1i m2i sd1i sd2i n1i n2i)   102 SMCR (m1i m2i sd1i ni ri)   110 POMPMC (m1i m2i sd1i sd2i ni ri mini maxi)
// vtype: 0 LS, 1 UB, 2 AV, 3 H0, 4 HO, 5 LS2, 6 LS3, 7 CS, 8 ST, 9 AVHO, 10 H0a, 11 H0b, 12 AV2, 13 MAX
//
// Not here: the alternative inputs (ti, pi, di, fi) that metafor converts to the main ones.

use e.algo.rand.r as rng
use e.algo.stat.fdrtool as fd
use e.algo.stat.mvt as mvt
use e.algo.stat.rnm as nmm
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.math.special as sp
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn inf() -> f64 { ret 1.0f64 / 0.0f64 }

// R's NA_real_ is a NaN with 1954 in its low word and survives arithmetic; escalc recodes a NaN (is.nan) or an infinity in either of yi and vi to NA in both, but leaves an NA's partner alone
fn na_val() -> f64 { ret mem.bitcast[f64](9221120237041090560u64 + 1954u64) }

fn is_na(x: f64) -> bool { ret x != x && (mem.bitcast[u64](x) & 4294967295u64) == 1954u64 }

// whether escalc recodes this value: an infinity or a NaN that is not NA
fn recode(x: f64) -> bool {
    if x == x { ret x - x != 0.0f64 }
    ret !is_na(x)
}

fn pi_c() -> f64 { ret 3.141592653589793f64 }

// the small-sample correction factor of Hedges (exact gamma form), or 1 when correct is false
fn cmi_of(mi: f64, correct: bool) -> f64 {
    if !correct { ret 1.0f64 }
    if mi <= 1.0f64 { ret na_val() }
    ret math.exp[f64](sp.lgamma(mi / 2.0f64) - math.log[f64](math.sqrt[f64](mi / 2.0f64)) - sp.lgamma((mi - 1.0f64) / 2.0f64))
}

// the weighted mean of x with weights w over the rows where neither is NaN
fn wmean(x: []const f64, w: []const f64, k: usize) -> f64 {
    var sx = 0.0f64
    var sw = 0.0f64
    var i = 0usize
    while i < k {
        if x[i] == x[i] && w[i] == w[i] {
            sx += x[i] * w[i]
            sw += w[i]
        }
        i += 1usize
    }
    ret sx / sw
}

fn at(d: []const f64, ncol: usize, i: usize, j: usize) -> f64 { ret d[i * ncol + j] }

fn rtoz(r: f64) -> f64 { ret 0.5f64 * math.log[f64]((1.0f64 + r) / (1.0f64 - r)) }

// 1 - y^2 with y^2 capped at 1, the divisor of the variance of a z-transformed correlation
fn one_minus_sq(y: f64) -> f64 {
    var y2 = y * y
    if y2 > 1.0f64 { y2 = 1.0f64 }
    ret 1.0f64 - y2
}

// the 2x2 counts of row i after drop00 (a dropped row is NaN throughout)
fn drop_vals(d: []const f64, ncol: usize, i: usize, drop00: bool) -> (f64, f64, f64, f64) {
    var a = at(d, ncol, i, 0usize)
    var b = at(d, ncol, i, 1usize)
    var c = at(d, ncol, i, 2usize)
    var dd = at(d, ncol, i, 3usize)
    if drop00 && ((a == 0.0f64 && c == 0.0f64) || (b == 0.0f64 && dd == 0.0f64)) {
        a = nan()
        b = nan()
        c = nan()
        dd = nan()
    }
    ret (a, b, c, dd)
}

// whether any retained row has a zero cell (metafor computes id0 after drop00 has set the dropped rows to NA)
fn any0_2x2(d: []const f64, ncol: usize, k: usize, drop00: bool) -> bool {
    var i = 0usize
    while i < k {
        let (a, b, c, dd) = drop_vals(d, ncol, i, drop00)
        if a == 0.0f64 || b == 0.0f64 || c == 0.0f64 || dd == 0.0f64 { ret true }
        i += 1usize
    }
    ret false
}

// the same for a pair of counts (the incidence-rate pair x1i x2i, with dropped rows dropped)
fn any0_pair(d: []const f64, ncol: usize, k: usize, drop00: bool) -> bool {
    var i = 0usize
    while i < k {
        let x1 = at(d, ncol, i, 0usize)
        let x2 = at(d, ncol, i, 1usize)
        let dropped = drop00 && x1 == 0.0f64 && x2 == 0.0f64
        if !dropped && (x1 == 0.0f64 || x2 == 0.0f64) { ret true }
        i += 1usize
    }
    ret false
}

// the continuity correction applied to one 2x2 row; to is 0 none, 1 all, 2 only0, 3 if0all
fn adj4(a: f64, b: f64, c: f64, dd: f64, to: usize, add: f64, any0: bool) -> (f64, f64, f64, f64) {
    let z = a == 0.0f64 || b == 0.0f64 || c == 0.0f64 || dd == 0.0f64
    var on = false
    if to == 1usize { on = true }
    if to == 2usize && z { on = true }
    if to == 3usize && any0 { on = true }
    if on { ret (a + add, b + add, c + add, dd + add) }
    ret (a, b, c, dd)
}

// R's round: halves go to the even neighbour
fn round_even(x: f64) -> f64 {
    let f = math.floor[f64](x)
    let r = x - f
    if r < 0.5f64 { ret f }
    if r > 0.5f64 { ret f + 1.0f64 }
    let h = f - 2.0f64 * math.floor[f64](f / 2.0f64)
    if h == 0.0f64 { ret f }
    ret f + 1.0f64
}

// metafor's .Fcalc: gsl's hyperg_2F1(a, b, g, x) for x in [0, 1], NaN unless g > a + b
fn fcalc(a: f64, b: f64, g: f64, x: f64) -> f64 {
    if g != g || x != x { ret na_val() }
    if g <= a + b { ret na_val() }
    if x >= 1.0f64 { ret math.exp[f64](sp.lgamma(g) + sp.lgamma(g - a - b) - sp.lgamma(g - a) - sp.lgamma(g - b)) }
    var t = 1.0f64
    var s = 1.0f64
    var j = 0usize
    while j < 20000000usize {
        t = t * (a + f64(j)) * (b + f64(j)) * x / ((g + f64(j)) * f64(j + 1usize))
        s += t
        if math.abs[f64](t) < 1.0e-18f64 * math.abs[f64](s) { break }
        j += 1usize
    }
    ret s
}

// ---- the tetrachoric correlation: metafor's .rtet ----

type Rt = struct { a: f64, b: f64, c: f64, dd: f64, ni: f64, maxcor: f64, fixcut: bool, ar: *mem.Arena, g: *rng.Rng, lat: *mvt.Lat }

// pmvnorm(lower, upper, corr = [1 rho; rho 1]) of mvtnorm (Genz-Bretz, which is exact in two dimensions)
fn pm2(c: *Rt, lo0: f64, lo1: f64, up0: f64, up1: f64, rho: f64) -> f64 {
    var lo: [2]f64 = zero
    var up: [2]f64 = zero
    var mean: [2]f64 = zero
    var sg: [4]f64 = zero
    lo[0usize] = lo0
    lo[1usize] = lo1
    up[0usize] = up0
    up[1usize] = up1
    sg[0usize] = 1.0f64
    sg[1usize] = rho
    sg[2usize] = rho
    sg[3usize] = 1.0f64
    let st = mem.mark(c.ar)
    let (res, e) = mvt.pmvnorm_sigma(c.ar, c.g, c.lat, 2usize, lo[..], up[..], mean[..], sg[..], 25000i64, 0.001f64, 0.0f64)
    mem.reset(c.ar, st)
    if e != ok { ret nan() }
    ret res.value
}

// the negative log likelihood of .rtet's inner function
fn rt_nll(c: *Rt, rho0: f64, cr: f64, cc: f64) -> f64 {
    var rho = rho0
    if math.abs[f64](rho) > c.maxcor { rho = math.copysign[f64](c.maxcor, rho) }
    var cut_row = cr
    var cut_col = cc
    if c.fixcut {
        cut_row = dist.qnorm((c.a + c.b) / c.ni, 0.0f64, 1.0f64, true, false)
        cut_col = dist.qnorm((c.a + c.c) / c.ni, 0.0f64, 1.0f64, true, false)
    }
    let ninf = 0.0f64 - inf()
    let pinf = inf()
    let pa = pm2(c, ninf, ninf, cut_col, cut_row, rho)
    let pb = pm2(c, cut_col, ninf, pinf, cut_row, rho)
    let pc = pm2(c, ninf, cut_row, cut_col, pinf, rho)
    let pd = pm2(c, cut_col, cut_row, pinf, pinf, rho)
    if pa <= 0.0f64 || pb <= 0.0f64 || pc <= 0.0f64 || pd <= 0.0f64 { ret inf() }
    ret 0.0f64 - (c.a * math.log[f64](pa) + c.b * math.log[f64](pb) + c.c * math.log[f64](pc) + c.dd * math.log[f64](pd))
}

// optimize()'s objective: a non-finite value becomes the largest double
fn rt_fix(c: *Rt, x: f64) -> f64 {
    let v = rt_nll(c, x, 0.0f64, 0.0f64)
    if v != v || v - v != 0.0f64 { ret 1.7976931348623157e308f64 }
    ret v
}

fn rt_free(c: *Rt, par: []const f64) -> f64 { ret rt_nll(c, par[0usize], par[1usize], par[2usize]) }

// optim's numerical gradient (central differences of step 1e-3)
fn rt_grad(c: *Rt, p: []const f64, df: []f64) {
    var x: [3]f64 = zero
    var i = 0usize
    while i < 3usize {
        x[i] = p[i]
        i += 1usize
    }
    i = 0usize
    while i < 3usize {
        let eps = 0.001f64
        x[i] = p[i] + eps
        let v1 = rt_free(c, x[..])
        x[i] = p[i] - eps
        let v2 = rt_free(c, x[..])
        df[i] = (v1 - v2) / (2.0f64 * eps)
        x[i] = p[i]
        i += 1usize
    }
}

// optimhess at par: central differences of the gradient, symmetrised; h is 3 x 3 row-major
fn rt_hess(c: *Rt, par: []const f64, h: []f64) {
    var dpar: [3]f64 = zero
    var df1: [3]f64 = zero
    var df2: [3]f64 = zero
    var i = 0usize
    while i < 3usize {
        dpar[i] = par[i]
        i += 1usize
    }
    i = 0usize
    while i < 3usize {
        let eps = 0.001f64
        dpar[i] = dpar[i] + eps
        rt_grad(c, dpar[..], df1[..])
        dpar[i] = dpar[i] - eps - eps
        rt_grad(c, dpar[..], df2[..])
        var j = 0usize
        while j < 3usize {
            h[i * 3usize + j] = (df1[j] - df2[j]) / (2.0f64 * eps)
            j += 1usize
        }
        dpar[i] = dpar[i] + eps
        i += 1usize
    }
    i = 0usize
    while i < 3usize {
        var j = 0usize
        while j < i {
            let tmp = 0.5f64 * (h[i * 3usize + j] + h[j * 3usize + i])
            h[i * 3usize + j] = tmp
            h[j * 3usize + i] = tmp
            j += 1usize
        }
        i += 1usize
    }
}

// chol2inv(chol(h))[1, 1] for a symmetric 3 x 3, NaN when h is not positive definite
fn inv00(h: []const f64) -> f64 {
    if !(h[0usize] > 0.0f64) { ret na_val() }
    let u00 = math.sqrt[f64](h[0usize])
    let u01 = h[1usize] / u00
    let u02 = h[2usize] / u00
    let q11 = h[4usize] - u01 * u01
    if !(q11 > 0.0f64) { ret na_val() }
    let u11 = math.sqrt[f64](q11)
    let u12 = (h[5usize] - u01 * u02) / u11
    let q22 = h[8usize] - u02 * u02 - u12 * u12
    if !(q22 > 0.0f64) { ret na_val() }
    let u22 = math.sqrt[f64](q22)
    let x00 = 1.0f64 / u00
    let x01 = 0.0f64 - u01 / (u00 * u11)
    let x02 = (u01 * u12 / u11 - u02) / (u00 * u22)
    ret x00 * x00 + x01 * x01 + x02 * x02
}

// .rtet(ai, bi, ci, di, maxcor = 0.9999): (yi, vi)
fn rtet(c: *Rt) -> (f64, f64) {
    let a = c.a
    let b = c.b
    let cc = c.c
    let dd = c.dd
    if (a + b) == 0.0f64 || (cc + dd) == 0.0f64 || (a + cc) == 0.0f64 || (b + dd) == 0.0f64 { ret (0.0f64, inf()) }
    if b == 0.0f64 && cc == 0.0f64 { ret (1.0f64, 0.0f64) }
    if a == 0.0f64 && dd == 0.0f64 { ret (0.0f64 - 1.0f64, 0.0f64) }
    c.fixcut = true
    let rho0 = fd.brent_min[Rt](c, rt_fix, 0.0f64 - 1.0f64, 1.0f64)
    c.fixcut = false
    var start: [3]f64 = zero
    start[0usize] = rho0
    start[1usize] = dist.qnorm((a + b) / c.ni, 0.0f64, 1.0f64, true, false)
    start[2usize] = dist.qnorm((a + cc) / c.ni, 0.0f64, 1.0f64, true, false)
    var xb: [3]f64 = zero
    let (fmin, count, fail) = nmm.nmmin[Rt](c.ar, c, rt_free, start[..], 0.0f64 - inf(), 1.490116119384766e-08f64, 1.0f64, 0.5f64, 2.0f64, 500usize, 1.0f64, xb[..])
    let _ = fmin
    let _ = count
    let _ = fail
    var h: [9]f64 = zero
    rt_hess(c, xb[..], h[..])
    let vi = inv00(h[..])
    var yi = xb[0usize]
    if b == 0.0f64 || cc == 0.0f64 { yi = 1.0f64 }
    if a == 0.0f64 || dd == 0.0f64 { yi = 0.0f64 - 1.0f64 }
    ret (yi, vi)
}

// RTET and ZTET over the rows (ai bi ci di)
fn rtet_rows(measure: usize, to: usize, add: f64, drop00: bool, k: usize, ncol: usize, d: []const f64, yi: []f64, vi: []f64) {
    var lat: mvt.Lat = zero
    mvt.load_lattice(&lat)
    var g: rng.Rng = zero
    rng.seed(&g, 12345i64)
    var buf: [16384]u8 = zero
    var ar = mem.arena_from(buf[..])
    let any0 = any0_2x2(d, ncol, k, drop00)
    var i = 0usize
    while i < k {
        let (au, bu, cu, du) = drop_vals(d, ncol, i, drop00)
        let (a, b, c, dd) = adj4(au, bu, cu, du, to, add, any0)
        yi[i] = nan()
        vi[i] = nan()
        if a == a && b == b && c == c && dd == dd {
            var ctx = Rt { a: a, b: b, c: c, dd: dd, ni: a + b + c + dd, maxcor: 0.9999f64, fixcut: false, ar: &ar, g: &g, lat: &lat }
            let st = mem.mark(&ar)
            let (y, v) = rtet(&ctx)
            mem.reset(&ar, st)
            yi[i] = y
            vi[i] = v
            if measure == 14usize {
                if !is_na(v) { vi[i] = v / (one_minus_sq(y) * one_minus_sq(y)) }
                yi[i] = rtoz(y)
            }
        }
        i += 1usize
    }
}

// ---- the non-central F density (R's dnbeta and dnf) and the R2F variance ----

fn dnbeta(x: f64, a: f64, b: f64, ncp: f64) -> f64 {
    if ncp < 0.0f64 || a <= 0.0f64 || b <= 0.0f64 { ret nan() }
    if x < 0.0f64 || x > 1.0f64 { ret 0.0f64 }
    if ncp == 0.0f64 { ret nb.dbeta(x, a, b, false) }
    let eps = 1.0e-15f64
    let ncp2 = ncp * 0.5f64
    let dx2 = ncp2 * x
    let dh = (dx2 - a - 1.0f64) * 0.5f64
    var dq = dh * dh + dx2 * (a + b) - a
    var kmax = 0.0f64
    if dq > 0.0f64 {
        dq = math.ceil[f64](dh + math.sqrt[f64](dq))
        if dq > 0.0f64 { kmax = dq }
    }
    var term = nb.dbeta(x, a + kmax, b, true)
    var pk = nm.dpois_raw(kmax, ncp2, true)
    let fin_t = term - term == 0.0f64
    let fin_p = pk - pk == 0.0f64
    if x == 0.0f64 || !fin_t || !fin_p { ret math.exp[f64](pk + term) }
    pk = pk + term
    var sum = 1.0f64
    term = 1.0f64
    var kk = kmax
    while kk > 0.0f64 && term > sum * eps {
        kk = kk - 1.0f64
        let q = (kk + 1.0f64) * (kk + a) / (kk + a + b) / dx2
        term = term * q
        sum = sum + term
    }
    term = 1.0f64
    kk = kmax
    var more = true
    while more {
        let q = dx2 * (kk + a + b) / (kk + a) / (kk + 1.0f64)
        kk = kk + 1.0f64
        term = term * q
        sum = sum + term
        more = term > sum * eps
    }
    ret math.exp[f64](pk + math.log[f64](sum))
}

fn dnf(x: f64, df1: f64, df2: f64, ncp: f64) -> f64 {
    if df1 <= 0.0f64 || df2 <= 0.0f64 || ncp < 0.0f64 { ret nan() }
    if x < 0.0f64 { ret 0.0f64 }
    let y = (df1 / df2) * x
    let z = dnbeta(y / (1.0f64 + y), df1 / 2.0f64, df2 / 2.0f64, ncp)
    ret z * (df1 / df2) / (1.0f64 + y) / (1.0f64 + y)
}

// the variance of metafor's R2F: the density of R^2 on a grid of 1e5 points between 1e-4 and 0.9999, normalised by the trapezoid rule
fn r2f_var(r2: f64, m: f64, n: f64) -> f64 {
    let np = 100000usize
    let lo = 0.0001f64
    let hi = 0.9999f64
    let by = (hi - lo) / f64(np - 1usize)
    let fval = (n - m - 1.0f64) / m * r2 / (1.0f64 - r2)
    var trap = 0.0f64
    var s1 = 0.0f64
    var s2 = 0.0f64
    var prev_x = 0.0f64
    var prev_d = 0.0f64
    var j = 0usize
    while j < np {
        var x = lo + f64(j) * by
        if j == np - 1usize { x = hi }
        let ncp = n * x / (1.0f64 - x)
        let den = dnf(fval, m, n - m - 1.0f64, ncp)
        if j > 0usize { trap += (x - prev_x) * (den + prev_d) }
        s1 += by * x * den
        s2 += by * x * x * den
        prev_x = x
        prev_d = den
        j += 1usize
    }
    trap = trap / 2.0f64
    let e1 = s1 / trap
    ret s2 / trap - e1 * e1
}

// escalc for the measures of this file: true when the measure is one of them
fn handles(measure: usize) -> bool {
    if measure >= 13usize && measure <= 15usize { ret true }
    if measure >= 32usize && measure <= 35usize { ret true }
    if measure >= 52usize && measure <= 58usize { ret true }
    if measure == 85usize || measure == 102usize || measure == 110usize { ret true }
    ret measure >= 90usize && measure <= 95usize
}

// d is k rows of ncol columns; yi and vi receive the effects and variances; scratch needs 6 k values
fn compute(measure: usize, vtype: usize, add: f64, to: usize, drop00: bool, correct: bool, k: usize, ncol: usize, d: []const f64, yi: []f64, vi: []f64, scratch: []f64) {
    var i = 0usize
    if measure == 13usize || measure == 14usize {
        rtet_rows(measure, to, add, drop00, k, ncol, d, yi, vi)
        ret
    }
    if measure == 15usize {
        // MPORM: the odds ratio of the margins of a matched-pair table, its variance reduced by the correlation of the pairs
        let any0 = any0_2x2(d, ncol, k, drop00)
        let p1s = scratch[0usize..k]
        let n1s = scratch[k..2usize * k]
        let p2s = scratch[2usize * k..3usize * k]
        let n2s = scratch[3usize * k..4usize * k]
        i = 0usize
        while i < k {
            let (au, bu, cu, du) = drop_vals(d, ncol, i, drop00)
            let (a, b, c, dd) = adj4(au, bu, cu, du, to, add, any0)
            p1s[i] = a / (a + b)
            n1s[i] = a + b
            p2s[i] = c / (c + dd)
            n2s[i] = c + dd
            i += 1usize
        }
        let m1 = wmean(p1s, n1s, k)
        let m2 = wmean(p2s, n2s, k)
        i = 0usize
        while i < k {
            let (au, bu, cu, du) = drop_vals(d, ncol, i, drop00)
            let (a, b, c, dd) = adj4(au, bu, cu, du, to, add, any0)
            let n1 = a + b
            let n2 = c + dd
            let ni = round_even((n1 + n2) / 2.0f64)
            let p1 = a / n1
            let p2 = c / n2
            yi[i] = math.log[f64](p1 / (1.0f64 - p1)) - math.log[f64](p2 / (1.0f64 - p2))
            var v = nan()
            if vtype == 0usize { v = 1.0f64 / a + 1.0f64 / b + 1.0f64 / c + 1.0f64 / dd }
            if vtype == 2usize { v = 1.0f64 / (m1 * (1.0f64 - m1) * n1) + 1.0f64 / (m2 * (1.0f64 - m2) * n2) }
            if vtype == 3usize {
                let pp = (a + c) / (n1 + n2)
                v = 1.0f64 / (pp * (1.0f64 - pp)) * (1.0f64 / n1 + 1.0f64 / n2)
            }
            // the correlation: ri, else the one the proportion pi implies; out of range or missing it is NA, which makes vi NA but leaves yi alone
            var r = at(d, ncol, i, 4usize)
            var r_na = false
            if r != r {
                let pr = at(d, ncol, i, 5usize)
                r_na = au == au && pr != pr
                if pr == pr {
                    let ap = pr * (au + bu)
                    let bp = au - ap
                    let cp = cu - ap
                    let dp = bu - cu + ap
                    r = (ap * dp - bp * cp) / math.sqrt[f64]((ap + bp) * (cp + dp) * (ap + cp) * (bp + dp))
                    if r < 0.0f64 - 1.0f64 || r > 1.0f64 { r_na = true }
                }
            }
            let si = (r * math.sqrt[f64](a * b * c * dd) + a * b) / ni
            let delta = ni * ni * (ni * si - a * b) / (a * b * c * dd)
            vi[i] = v - 2.0f64 * delta / ni
            if r_na { vi[i] = na_val() }
            i += 1usize
        }
        ret
    }
    if measure >= 32usize && measure <= 35usize {
        i = 0usize
        while i < k {
            var m1 = at(d, ncol, i, 0usize)
            var m2 = at(d, ncol, i, 1usize)
            var s1 = at(d, ncol, i, 2usize)
            var s2 = at(d, ncol, i, 3usize)
            let n1 = at(d, ncol, i, 4usize)
            let n2 = at(d, ncol, i, 5usize)
            if measure == 35usize {
                let lo = at(d, ncol, i, 6usize)
                let hi = at(d, ncol, i, 7usize)
                m1 = 100.0f64 * (m1 - lo) / (hi - lo)
                m2 = 100.0f64 * (m2 - lo) / (hi - lo)
                s1 = 100.0f64 * s1 / (hi - lo)
                s2 = 100.0f64 * s2 / (hi - lo)
            }
            let ni = n1 + n2
            let mi = ni - 2.0f64
            let sdp = math.sqrt[f64](((n1 - 1.0f64) * s1 * s1 + (n2 - 1.0f64) * s2 * s2) / mi)
            let dv = (m1 - m2) / sdp
            if measure == 35usize {
                yi[i] = m1 - m2
                if vtype == 4usize { vi[i] = sdp * sdp * (1.0f64 / n1 + 1.0f64 / n2) } else { vi[i] = s1 * s1 / n1 + s2 * s2 / n2 }
            }
            if measure == 32usize || measure == 33usize {
                let hi = mi / n1 + mi / n2
                var y = dv / math.sqrt[f64](dv * dv + hi)
                let p1 = n1 / ni
                let p2 = n2 / ni
                let zi = dist.qnorm(p1, 0.0f64, 1.0f64, false, false)
                let fzi = dist.dnorm(zi, 0.0f64, 1.0f64, false)
                y = math.sqrt[f64](p1 * p2) / fzi * y
                var yt = y
                if math.abs[f64](y) > 1.0f64 { yt = math.copysign[f64](1.0f64, y) }
                var v = 1.0f64 / (ni - 1.0f64) * (p1 * p2 / (fzi * fzi) - (1.5f64 + (1.0f64 - p1 * zi / fzi) * (1.0f64 + p2 * zi / fzi)) * yt * yt + yt * yt * yt * yt)
                if measure == 33usize {
                    v = v / (one_minus_sq(y) * one_minus_sq(y))
                    y = rtoz(y)
                }
                yi[i] = y
                vi[i] = v
            }
            if measure == 34usize {
                yi[i] = pi_c() / math.sqrt[f64](3.0f64) * dv
                vi[i] = pi_c() * pi_c() / 3.0f64 * (1.0f64 / n1 + 1.0f64 / n2 + dv * dv / (2.0f64 * ni))
            }
            i += 1usize
        }
        ret
    }
    if measure == 52usize {
        let ys = scratch[0usize..k]
        let ns = scratch[k..2usize * k]
        i = 0usize
        while i < k {
            let r = at(d, ncol, i, 0usize)
            let n = at(d, ncol, i, 1usize)
            let fr = fcalc(0.5f64, 0.5f64, (n - 2.0f64) / 2.0f64, 1.0f64 - r * r)
            ys[i] = r * fr
            if is_na(fr) { ys[i] = na_val() }
            ns[i] = n
            i += 1usize
        }
        let mnw = wmean(ys, ns, k)
        i = 0usize
        while i < k {
            let r = at(d, ncol, i, 0usize)
            let n = at(d, ncol, i, 1usize)
            let y = ys[i]
            yi[i] = y
            if vtype == 0usize { vi[i] = (1.0f64 - y * y) * (1.0f64 - y * y) / (n - 1.0f64) }
            if vtype == 1usize { vi[i] = y * y - (1.0f64 - (n - 3.0f64) / (n - 2.0f64) * (1.0f64 - r * r) * fcalc(1.0f64, 1.0f64, n / 2.0f64, 1.0f64 - r * r)) }
            if vtype == 2usize { vi[i] = (1.0f64 - mnw * mnw) * (1.0f64 - mnw * mnw) / (n - 1.0f64) }
            if n <= 3.0f64 { vi[i] = na_val() }
            i += 1usize
        }
        ret
    }
    if measure >= 53usize && measure <= 58usize {
        // (ri mi ni) and, for the semi-partial correlations, r2i
        let ys = scratch[0usize..k]
        let ns = scratch[k..2usize * k]
        i = 0usize
        while i < k {
            ys[i] = at(d, ncol, i, 0usize)
            ns[i] = at(d, ncol, i, 2usize)
            i += 1usize
        }
        let mnw = wmean(ys, ns, k)
        i = 0usize
        while i < k {
            let r = at(d, ncol, i, 0usize)
            let m = at(d, ncol, i, 1usize)
            let n = at(d, ncol, i, 2usize)
            if measure == 53usize {
                yi[i] = r
                if vtype == 0usize { vi[i] = (1.0f64 - r * r) * (1.0f64 - r * r) / (n - m) }
                if vtype == 2usize { vi[i] = (1.0f64 - mnw * mnw) * (1.0f64 - mnw * mnw) / (n - m) }
            }
            if measure == 54usize {
                yi[i] = rtoz(r)
                vi[i] = 1.0f64 / (n - m - 2.0f64)
            }
            if measure == 55usize || measure == 56usize {
                let r2 = at(d, ncol, i, 3usize)
                var v = nan()
                if vtype == 0usize { v = (r2 * r2 - 2.0f64 * r2 + (r2 - r * r) + 1.0f64 - (r2 - r * r) * (r2 - r * r)) / n }
                if vtype == 2usize { v = (r2 * r2 - 2.0f64 * r2 + (r2 - mnw * mnw) + 1.0f64 - (r2 - mnw * mnw) * (r2 - mnw * mnw)) / n }
                yi[i] = r
                vi[i] = v
                if measure == 56usize {
                    vi[i] = v / (one_minus_sq(r) * one_minus_sq(r))
                    yi[i] = rtoz(r)
                }
            }
            if measure == 57usize {
                yi[i] = r
                vi[i] = 2.0f64 * (1.0f64 - r) * (1.0f64 - r) * (1.0f64 + (m - 1.0f64) * r) * (1.0f64 + (m - 1.0f64) * r) / (m * (m - 1.0f64) * n)
            }
            if measure == 58usize {
                yi[i] = 0.5f64 * math.log[f64]((1.0f64 + (m - 1.0f64) * r) / (1.0f64 - r))
                vi[i] = m / (2.0f64 * (m - 1.0f64) * n)
            }
            i += 1usize
        }
        ret
    }
    if measure >= 90usize && measure <= 93usize {
        let ys = scratch[0usize..k]
        let ns = scratch[k..2usize * k]
        i = 0usize
        while i < k {
            ys[i] = at(d, ncol, i, 0usize)
            ns[i] = at(d, ncol, i, 2usize)
            i += 1usize
        }
        let mnw = wmean(ys, ns, k)
        i = 0usize
        while i < k {
            let r2 = at(d, ncol, i, 0usize)
            let m = at(d, ncol, i, 1usize)
            let n = at(d, ncol, i, 2usize)
            if measure == 90usize {
                yi[i] = r2
                if vtype == 0usize { vi[i] = 4.0f64 * r2 * (1.0f64 - r2) * (1.0f64 - r2) / n }
                if vtype == 2usize { vi[i] = 4.0f64 * mnw * (1.0f64 - mnw) * (1.0f64 - mnw) / n }
                if vtype == 5usize { vi[i] = 4.0f64 * r2 * (1.0f64 - r2) * (1.0f64 - r2) * (n - m - 1.0f64) * (n - m - 1.0f64) / ((n * n - 1.0f64) * (n + 3.0f64)) }
                if vtype == 12usize { vi[i] = 4.0f64 * mnw * (1.0f64 - mnw) * (1.0f64 - mnw) * (n - m - 1.0f64) * (n - m - 1.0f64) / ((n * n - 1.0f64) * (n + 3.0f64)) }
            }
            if measure == 91usize {
                yi[i] = rtoz(math.sqrt[f64](r2))
                vi[i] = 1.0f64 / n
            }
            if measure == 92usize || measure == 93usize {
                yi[i] = r2
                vi[i] = r2f_var(r2, m, n)
                if measure == 93usize {
                    vi[i] = vi[i] / ((1.0f64 - r2 * r2) * (1.0f64 - r2 * r2))
                    yi[i] = rtoz(math.sqrt[f64](r2))
                }
            }
            i += 1usize
        }
        ret
    }
    if measure == 94usize {
        i = 0usize
        while i < k {
            let a = at(d, ncol, i, 0usize)
            let n1 = at(d, ncol, i, 1usize)
            let n2 = at(d, ncol, i, 2usize)
            var m = at(d, ncol, i, 3usize)
            if m != m { m = 0.0f64 }
            let navg = (n1 + n2) / 2.0f64
            let q0 = a * (1.0f64 - a)
            let q1 = a / (2.0f64 - a)
            let q2 = 2.0f64 * a * a / (1.0f64 + a)
            yi[i] = a
            if vtype == 0usize { vi[i] = q0 / ((n1 - 1.0f64) * (n2 - 1.0f64)) * (2.0f64 * navg - 1.0f64 - (3.0f64 * navg - 3.0f64) / ((2.0f64 - a) * (1.0f64 + a))) }
            if vtype == 5usize { vi[i] = (q0 - m / 4.0f64 + (n1 - 1.0f64) * (q1 - a * a) + (n2 - 1.0f64) * (q2 - a * a)) / ((n1 - 1.0f64) * (n2 - 1.0f64)) }
            if vtype == 3usize { vi[i] = (n1 + n2 + 1.0f64) / (12.0f64 * n1 * n2) }
            if vtype == 13usize { vi[i] = q0 / (math.min[f64](n1, n2) - 1.0f64) }
            i += 1usize
        }
        ret
    }
    if measure == 95usize {
        i = 0usize
        while i < k {
            let m1 = at(d, ncol, i, 0usize)
            let m2 = at(d, ncol, i, 1usize)
            let s1 = at(d, ncol, i, 2usize)
            let s2 = at(d, ncol, i, 3usize)
            let n1 = at(d, ncol, i, 4usize)
            let n2 = at(d, ncol, i, 5usize)
            var sdp = math.sqrt[f64]((s1 * s1 + s2 * s2) / 2.0f64)
            if vtype == 4usize { sdp = math.sqrt[f64](((n1 - 1.0f64) * s1 * s1 + (n2 - 1.0f64) * s2 * s2) / (n1 + n2 - 2.0f64)) }
            let dv = (m1 - m2) / sdp
            yi[i] = dist.pnorm(dv / math.sqrt[f64](2.0f64), 0.0f64, 1.0f64, true, false)
            let vr = s1 * s1 / (s1 * s1 + s2 * s2)
            let ex = math.exp[f64](0.0f64 - dv * dv / 2.0f64)
            if vtype == 0usize { vi[i] = ex / (8.0f64 * pi_c()) * (dv * dv * vr * vr / (n1 - 1.0f64) + dv * dv * (1.0f64 - vr) * (1.0f64 - vr) / (n2 - 1.0f64) + 4.0f64 * vr / (n1 - 1.0f64) + 4.0f64 * (1.0f64 - vr) / (n2 - 1.0f64)) }
            if vtype == 5usize { vi[i] = ex / (8.0f64 * pi_c()) * (dv * dv * vr * vr / n1 + dv * dv * (1.0f64 - vr) * (1.0f64 - vr) / n2 + 4.0f64 * vr / n1 + 4.0f64 * (1.0f64 - vr) / n2) }
            if vtype == 6usize { vi[i] = ex / (8.0f64 * pi_c()) * (dv * dv * vr * vr / (n1 - 1.0f64) + dv * dv * (1.0f64 - vr) * (1.0f64 - vr) / (n2 - 1.0f64) + 4.0f64 * vr / n1 + 4.0f64 * (1.0f64 - vr) / n2) }
            if vtype == 4usize { vi[i] = ex / (4.0f64 * pi_c()) * (1.0f64 / n1 + 1.0f64 / n2 + dv * dv / (2.0f64 * (n1 + n2))) }
            if vtype == 3usize { vi[i] = 1.0f64 / (8.0f64 * pi_c()) * (4.0f64 * vr / (n1 - 1.0f64) + 4.0f64 * (1.0f64 - vr) / (n2 - 1.0f64)) }
            i += 1usize
        }
        ret
    }
    if measure == 85usize {
        // POMPMN: the single mean on the 0 to 100 scale
        let vs = scratch[0usize..k]
        let ws = scratch[k..2usize * k]
        i = 0usize
        while i < k {
            let sd = at(d, ncol, i, 1usize)
            let lo = at(d, ncol, i, 3usize)
            let hi = at(d, ncol, i, 4usize)
            let s = 100.0f64 * sd / (hi - lo)
            vs[i] = s * s
            ws[i] = at(d, ncol, i, 2usize) - 1.0f64
            i += 1usize
        }
        let sdp2 = wmean(vs, ws, k)
        i = 0usize
        while i < k {
            let m = at(d, ncol, i, 0usize)
            let n = at(d, ncol, i, 2usize)
            let lo = at(d, ncol, i, 3usize)
            let hi = at(d, ncol, i, 4usize)
            yi[i] = 100.0f64 * (m - lo) / (hi - lo)
            if vtype == 4usize { vi[i] = sdp2 / n } else { vi[i] = vs[i] / n }
            i += 1usize
        }
        ret
    }
    if measure == 102usize {
        // SMCR (m1i m2i sd1i ni ri)
        i = 0usize
        while i < k {
            let m1 = at(d, ncol, i, 0usize)
            let m2 = at(d, ncol, i, 1usize)
            let s1 = at(d, ncol, i, 2usize)
            let n = at(d, ncol, i, 3usize)
            let r = at(d, ncol, i, 4usize)
            let mi = n - 1.0f64
            let cm = cmi_of(mi, correct)
            let dv = (m1 - m2) / s1
            let y = cm * dv
            yi[i] = y
            let fr = fcalc(0.5f64, 0.5f64, (n - 2.0f64) / 2.0f64, 1.0f64 - r * r)
            let rui = r * fr
            if vtype == 0usize { vi[i] = 2.0f64 * (1.0f64 - r) / n + y * y / (2.0f64 * n) }
            if vtype == 5usize { vi[i] = cm * cm * (2.0f64 * (1.0f64 - r) / n + dv * dv / (2.0f64 * n)) }
            if vtype == 1usize { vi[i] = 2.0f64 * (1.0f64 - rui) / n + (1.0f64 - (mi - 2.0f64) / (mi * cm * cm)) * y * y }
            if vtype == 3usize {
                vi[i] = na_val()
                if mi > 2.0f64 { vi[i] = cm * cm * 2.0f64 * (1.0f64 - rui) / n * mi / (mi - 2.0f64) }
            }
            if is_na(fr) && (vtype == 1usize || vtype == 3usize) { vi[i] = na_val() }
            i += 1usize
        }
        ret
    }
    if measure == 110usize {
        // POMPMC (m1i m2i sd1i sd2i ni ri mini maxi)
        i = 0usize
        while i < k {
            let lo = at(d, ncol, i, 6usize)
            let hi = at(d, ncol, i, 7usize)
            let m1 = 100.0f64 * (at(d, ncol, i, 0usize) - lo) / (hi - lo)
            let m2 = 100.0f64 * (at(d, ncol, i, 1usize) - lo) / (hi - lo)
            let s1 = 100.0f64 * at(d, ncol, i, 2usize) / (hi - lo)
            let s2 = 100.0f64 * at(d, ncol, i, 3usize) / (hi - lo)
            let n = at(d, ncol, i, 4usize)
            let r = at(d, ncol, i, 5usize)
            yi[i] = m1 - m2
            vi[i] = (s1 * s1 + s2 * s2 - 2.0f64 * r * s1 * s2) / n
            i += 1usize
        }
    }
}
