// R hetGP, homoskedastic part: mleHomGP (Gaussian, Matern5_2 and Matern3_2 kernels, replicated designs, profiled constant mean
// and variance, the L-BFGS-B hyperparameter search of optim with hetGP's analytic gradient, auto_bounds, known theta / g / beta0),
// predict.homGP (mean, latent variance sd2, nugget variance nugs, cross covariance), update.homGP, crit_EI and crit_logEI.
//
// Heteroskedastic part (het_fit, het_predict, het_update0, het_eval): mleHetGP with joint thetas (theta_g = k_theta_g * theta), logN,
// the residual initialisation, the Delta penalty and checkHom, known theta / g / k_theta_g / beta0 / Delta, predict.hetGP (with the
// noise-process variance sd2var) and update.hetGP at maxit = 0. hetGP's Matern3_2 d/dk_theta_g has the wrong sign and is reproduced.
//
// Not here: the LOO criterion, isotropic scalar theta over several columns, SiNK, pseudo-inputs, separate theta_g (linkThetas
// FALSE or constr), logN = FALSE, update with a refit (maxit > 0), derivative predictions and the sequential design criteria other
// than the two expected improvements.

use e.algo.stat.lbfgsb as lb
use e.math
use e.math.dist as dist
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

type HomOpt = struct {
    ctype: usize, auto_lo: bool, auto_up: bool, lower: []const f64, upper: []const f64,
    has_init_theta: bool, init_theta: []const f64, has_init_g: bool, init_g: f64,
    has_theta: bool, theta: []const f64, has_g: bool, g: f64, has_beta0: bool, beta0: f64,
    gmin: f64, gmax: f64, maxit: usize, factr: f64, eps: f64
}

type HomFit = struct {
    n: usize, d: usize, nn: usize, ctype: usize, eps: f64, sk: bool, g: f64, nu: f64, ll: f64, beta0: f64,
    theta: []f64, lower: []f64, upper: []f64, x0: []const f64, z0: []const f64, z: []const f64, mult: []const f64, ki: []f64, opt: HomOpt
}

// ---- kernels (row-major designs) ----

fn cov_pt(ctype: usize, xa: []const f64, ia: usize, xb: []const f64, ib: usize, d: usize, th: []const f64) -> f64 {
    var s = 0.0f64
    var p = 1.0f64
    var c = 0usize
    while c < d {
        let dx = xa[ia * d + c] - xb[ib * d + c]
        if ctype == 0usize {
            s += dx * dx / th[c]
        } else {
            let t = math.abs[f64](dx) / th[c]
            if ctype == 1usize {
                let u = math.sqrt[f64](5.0f64) * t
                p *= 1.0f64 + u + u * u / 3.0f64
                s += u
            } else {
                let u = math.sqrt[f64](3.0f64) * t
                p *= 1.0f64 + u
                s += u
            }
        }
        c += 1usize
    }
    if ctype == 0usize { ret math.exp[f64](0.0f64 - s) }
    ret p * math.exp[f64](0.0f64 - s)
}

// d log k / d theta_k for one coordinate difference
fn dlnk(ctype: usize, dx: f64, th: f64) -> f64 {
    if ctype == 0usize { ret dx * dx / (th * th) }
    let t = math.abs[f64](dx) / th
    if ctype == 1usize {
        let s5 = math.sqrt[f64](5.0f64)
        ret (5.0f64 / 3.0f64 * t + 5.0f64 * s5 / 3.0f64 * t * t) / (1.0f64 + s5 * t + 5.0f64 / 3.0f64 * t * t) * t / th
    }
    ret 3.0f64 * t / (1.0f64 + math.sqrt[f64](3.0f64) * t) * t / th
}

fn cov_mat(xa: []const f64, na: usize, xb: []const f64, nb: usize, d: usize, th: []const f64, ctype: usize, out: []f64) {
    var i = 0usize
    while i < na {
        var j = 0usize
        while j < nb {
            out[i * nb + j] = cov_pt(ctype, xa, i, xb, j, d, th)
            j += 1usize
        }
        i += 1usize
    }
}

// ---- dense helpers ----

fn chol(k: []const f64, n: usize, l: []f64) -> bool {
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            l[i * n + j] = 0.0f64
            j += 1usize
        }
        j = 0usize
        while j <= i {
            var s = k[i * n + j]
            var q = 0usize
            while q < j {
                s -= l[i * n + q] * l[j * n + q]
                q += 1usize
            }
            if i == j {
                if !(s > 0.0f64) { ret false }
                l[i * n + i] = math.sqrt[f64](s)
            } else {
                l[i * n + j] = s / l[j * n + j]
            }
            j += 1usize
        }
        i += 1usize
    }
    ret true
}

// ki = (L L')^-1 from the lower factor; li is scratch
fn chol_inv(l: []const f64, n: usize, li: []f64, ki: []f64) {
    var j = 0usize
    while j < n {
        var i = 0usize
        while i < n {
            li[i * n + j] = 0.0f64
            i += 1usize
        }
        i = j
        while i < n {
            var s = 0.0f64
            if i == j { s = 1.0f64 }
            var q = j
            while q < i {
                s -= l[i * n + q] * li[q * n + j]
                q += 1usize
            }
            li[i * n + j] = s / l[i * n + i]
            i += 1usize
        }
        j += 1usize
    }
    var i = 0usize
    while i < n {
        j = 0usize
        while j <= i {
            var s = 0.0f64
            var q = i
            while q < n {
                s += li[q * n + i] * li[q * n + j]
                q += 1usize
            }
            ki[i * n + j] = s
            ki[j * n + i] = s
            j += 1usize
        }
        i += 1usize
    }
}

fn sort_f64(v: []f64, n: usize) {
    var gap = n / 2usize
    while gap > 0usize {
        var i = gap
        while i < n {
            let t = v[i]
            var j = i
            while j >= gap && v[j - gap] > t {
                v[j] = v[j - gap]
                j -= gap
            }
            v[j] = t
            i += 1usize
        }
        gap = gap / 2usize
    }
}

// ---- find_reps ----

// unique rows in order of first appearance, their mean, multiplicity, and Z sorted by group; returns the number of unique rows
fn find_reps(a: *mem.Arena, x: []const f64, z: []const f64, nn: usize, d: usize, x0: []f64, z0: []f64, mult: []f64, zs: []f64) -> (usize, err) {
    let (grp, e1) = mem.alloc[usize](a, nn)
    if e1 != ok { ret (0usize, e1) }
    var n = 0usize
    var i = 0usize
    while i < nn {
        var found = false
        var u = 0usize
        while u < n && !found {
            var same = true
            var c = 0usize
            while c < d {
                if x[i * d + c] != x0[u * d + c] { same = false }
                c += 1usize
            }
            if same {
                found = true
                grp[i] = u
            }
            u += 1usize
        }
        if !found {
            var c = 0usize
            while c < d {
                x0[n * d + c] = x[i * d + c]
                c += 1usize
            }
            grp[i] = n
            n += 1usize
        }
        i += 1usize
    }
    var u = 0usize
    while u < n {
        mult[u] = 0.0f64
        z0[u] = 0.0f64
        u += 1usize
    }
    i = 0usize
    while i < nn {
        mult[grp[i]] += 1.0f64
        i += 1usize
    }
    var pos = 0usize
    u = 0usize
    while u < n {
        var s = 0.0f64
        i = 0usize
        while i < nn {
            if grp[i] == u {
                zs[pos] = z[i]
                pos += 1usize
                s += z[i]
            }
            i += 1usize
        }
        z0[u] = s / mult[u]
        u += 1usize
    }
    ret (n, ok)
}

// ---- auto_bounds ----

fn matern_gap(ctype: usize, rd: f64, d: usize, theta: f64, value: f64) -> f64 {
    let x = math.sqrt[f64](rd / f64(d)) / theta
    var s = 0.0f64
    var p = 1.0f64
    var c = 0usize
    while c < d {
        if ctype == 1usize {
            let u = math.sqrt[f64](5.0f64) * x
            p *= 1.0f64 + u + u * u / 3.0f64
            s += u
        } else {
            let u = math.sqrt[f64](3.0f64) * x
            p *= 1.0f64 + u
            s += u
        }
        c += 1usize
    }
    ret p * math.exp[f64](0.0f64 - s) - value
}

// R's uniroot (R_zeroin2) of matern_gap on [sqrt(eps), 100], tol sqrt(eps); the flag is false when the end values share a sign
fn root_gap(ctype: usize, rd: f64, d: usize, value: f64) -> (f64, bool) {
    let epsm = 2.220446049250313e-16f64
    let tol = 1.4901161193847656e-8f64
    var a0 = 1.4901161193847656e-8f64
    var b0 = 100.0f64
    var fa = matern_gap(ctype, rd, d, a0, value)
    var fb = matern_gap(ctype, rd, d, b0, value)
    if fa != fa || fb != fb { ret (0.0f64, false) }
    if (fa > 0.0f64 && fb > 0.0f64) || (fa < 0.0f64 && fb < 0.0f64) { ret (0.0f64, false) }
    if fa == 0.0f64 { ret (a0, true) }
    if fb == 0.0f64 { ret (b0, true) }
    var c0 = a0
    var fc = fa
    var it = 0usize
    while it < 1001usize {
        let prev = b0 - a0
        if math.abs[f64](fc) < math.abs[f64](fb) {
            a0 = b0
            b0 = c0
            c0 = a0
            fa = fb
            fb = fc
            fc = fa
        }
        let tol_act = 2.0f64 * epsm * math.abs[f64](b0) + tol / 2.0f64
        var step = (c0 - b0) / 2.0f64
        if math.abs[f64](step) <= tol_act || fb == 0.0f64 { ret (b0, true) }
        if math.abs[f64](prev) >= tol_act && math.abs[f64](fa) > math.abs[f64](fb) {
            let cb = c0 - b0
            var p = 0.0f64
            var q = 0.0f64
            if a0 == c0 {
                let t1 = fb / fa
                p = cb * t1
                q = 1.0f64 - t1
            } else {
                q = fa / fc
                let t1 = fb / fc
                let t2 = fb / fa
                p = t2 * (cb * q * (q - t1) - (b0 - a0) * (t1 - 1.0f64))
                q = (q - 1.0f64) * (t1 - 1.0f64) * (t2 - 1.0f64)
            }
            if p > 0.0f64 { q = 0.0f64 - q } else { p = 0.0f64 - p }
            if p < (0.75f64 * cb * q - math.abs[f64](tol_act * q) / 2.0f64) && p < math.abs[f64](prev * q / 2.0f64) { step = p / q }
        }
        if math.abs[f64](step) < tol_act {
            if step > 0.0f64 { step = tol_act } else { step = 0.0f64 - tol_act }
        }
        a0 = b0
        fa = fb
        b0 += step
        fb = matern_gap(ctype, rd, d, b0, value)
        if (fb > 0.0f64 && fc > 0.0f64) || (fb < 0.0f64 && fc < 0.0f64) {
            c0 = a0
            fc = fa
        }
        it += 1usize
    }
    ret (b0, true)
}

fn quantile7(v: []const f64, m: usize, p: f64) -> f64 {
    let index = 1.0f64 + f64(m - 1usize) * p
    let lo = math.floor[f64](index)
    let hi = math.ceil[f64](index)
    var qs = v[usize(lo) - 1usize]
    let xh = v[usize(hi) - 1usize]
    if index > lo && xh != qs {
        let h = index - lo
        qs = (1.0f64 - h) * qs + h * xh
    }
    ret qs
}

// hetGP auto_bounds(X, min_cor = 0.01, max_cor = 0.5, p = 0.05) on the unique designs x0 (n >= 2)
fn auto_bounds(a: *mem.Arena, x0: []const f64, n: usize, d: usize, ctype: usize, lo: []f64, up: []f64) -> err {
    let (xs, e1) = mem.alloc[f64](a, n * d)
    let (rg, e2) = mem.alloc[f64](a, d)
    let m = n * (n - 1usize) / 2usize
    let (dv, e3) = mem.alloc[f64](a, m)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    var c = 0usize
    while c < d {
        var mn = x0[c]
        var mx = x0[c]
        var i = 1usize
        while i < n {
            if x0[i * d + c] < mn { mn = x0[i * d + c] }
            if x0[i * d + c] > mx { mx = x0[i * d + c] }
            i += 1usize
        }
        rg[c] = mx - mn
        i = 0usize
        while i < n {
            xs[i * d + c] = (x0[i * d + c] - mn) * (1.0f64 / (mx - mn))
            i += 1usize
        }
        c += 1usize
    }
    var k = 0usize
    var i = 1usize
    while i < n {
        var j = 0usize
        while j < i {
            var s = 0.0f64
            c = 0usize
            while c < d {
                let dd = xs[i * d + c] - xs[j * d + c]
                s += dd * dd
                c += 1usize
            }
            dv[k] = s
            k += 1usize
            j += 1usize
        }
        i += 1usize
    }
    sort_f64(dv, m)
    let low = quantile7(dv, m, 0.05f64)
    let lar = quantile7(dv, m, 0.95f64)
    var tmin = 0.0f64
    var tmax = 0.0f64
    if ctype == 0usize {
        tmin = 0.0f64 - low / math.log[f64](0.01f64)
        tmax = 0.0f64 - lar / math.log[f64](0.5f64)
        c = 0usize
        while c < d {
            lo[c] = tmin * rg[c] * rg[c]
            up[c] = tmax * rg[c] * rg[c]
            c += 1usize
        }
        ret ok
    }
    let (r1, g1) = root_gap(ctype, low, d, 0.01f64)
    tmin = r1
    if !g1 { tmin = 0.01f64 }
    let (r2, g2) = root_gap(ctype, lar, d, 0.5f64)
    tmax = r2
    if !g2 { tmax = 5.0f64 }
    if tmax < 1.0f64 { tmax = 1.0f64 }
    c = 0usize
    while c < d {
        lo[c] = tmin * rg[c]
        up[c] = tmax * rg[c]
        c += 1usize
    }
    ret ok
}

// ---- likelihood ----

type HomC = struct {
    n: usize, d: usize, nn: usize, ctype: usize, eps: f64, x0: []const f64, z0: []const f64, z: []const f64, mult: []const f64,
    has_b0: bool, b0: f64, has_theta: bool, has_g: bool, th: []f64, g0: f64,
    cm: []f64, km: []f64, lm: []f64, li: []f64, ki: []f64, kz: []f64, res: []f64,
    beta: f64, psi0: f64, q: f64, psi: f64, ldet: f64, bestll: f64, best: []f64, nbest: usize
}

fn hom_core(c: *HomC, theta: []const f64, g: f64) -> (f64, bool) {
    let n = c.n
    cov_mat(c.x0, n, c.x0, n, c.d, theta, c.ctype, c.cm)
    var i = 0usize
    while i < n * n {
        c.km[i] = c.cm[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        c.km[i * n + i] += c.eps + g / c.mult[i]
        i += 1usize
    }
    if !chol(c.km, n, c.lm) { ret (nan(), false) }
    var ldet = 0.0f64
    i = 0usize
    while i < n {
        ldet -= 2.0f64 * math.log[f64](c.lm[i * n + i])
        i += 1usize
    }
    chol_inv(c.lm, n, c.li, c.ki)
    var beta = c.b0
    if !c.has_b0 {
        var s1 = 0.0f64
        var sz = 0.0f64
        i = 0usize
        while i < n {
            var cs = 0.0f64
            var j = 0usize
            while j < n {
                cs += c.ki[j * n + i]
                j += 1usize
            }
            s1 += cs
            sz += cs * c.z0[i]
            i += 1usize
        }
        beta = sz / s1
    }
    var psi0 = 0.0f64
    i = 0usize
    while i < n {
        var r = 0.0f64
        var j = 0usize
        while j < n {
            r += c.ki[i * n + j] * (c.z0[j] - beta)
            j += 1usize
        }
        c.kz[i] = r
        psi0 += (c.z0[i] - beta) * r
        i += 1usize
    }
    var sq = 0.0f64
    i = 0usize
    while i < c.nn {
        sq += (c.z[i] - beta) * (c.z[i] - beta)
        i += 1usize
    }
    var sm = 0.0f64
    var slm = 0.0f64
    i = 0usize
    while i < n {
        sm += (c.z0[i] - beta) * c.mult[i] * (c.z0[i] - beta)
        slm += math.log[f64](c.mult[i])
        i += 1usize
    }
    let nf = f64(c.nn)
    let q = sq - sm
    let psi = 1.0f64 / nf * (q / g + psi0)
    c.beta = beta
    c.psi0 = psi0
    c.q = q
    c.psi = psi
    c.ldet = ldet
    let ll = 0.0f64 - nf / 2.0f64 * math.log[f64](2.0f64 * 3.141592653589793f64) - nf / 2.0f64 * math.log[f64](psi) + 0.5f64 * ldet - (nf - f64(n)) / 2.0f64 * math.log[f64](g) - 0.5f64 * slm - nf / 2.0f64
    ret (ll, true)
}

fn hom_unpack(c: *HomC, p: []const f64) -> f64 {
    var idx = 0usize
    if !c.has_theta {
        var k = 0usize
        while k < c.d {
            c.th[k] = p[k]
            k += 1usize
        }
        idx = c.d
    }
    if c.has_g { ret c.g0 }
    ret p[idx]
}

fn hom_fn(c: *HomC, p: []const f64) -> f64 {
    let g = hom_unpack(c, p)
    let (ll, good) = hom_core(c, c.th, g)
    if !good { ret nan() }
    if c.nbest == 0usize || ll > c.bestll {
        c.bestll = ll
        c.nbest = p.len
        var k = 0usize
        while k < p.len {
            c.best[k] = p[k]
            k += 1usize
        }
    }
    ret 0.0f64 - ll
}

fn hom_gr(c: *HomC, p: []const f64, out: []f64) {
    let g = hom_unpack(c, p)
    let (ll, good) = hom_core(c, c.th, g)
    let n = c.n
    var idx = 0usize
    let nf = f64(c.nn)
    let denom = c.q / g + c.psi0
    if !good {
        var k = 0usize
        while k < out.len {
            out[k] = nan()
            k += 1usize
        }
        ret
    }
    if !c.has_theta {
        var k = 0usize
        while k < c.d {
            var s1 = 0.0f64
            var tr = 0.0f64
            var i = 0usize
            while i < n {
                var j = 0usize
                while j < n {
                    let dc = dlnk(c.ctype, c.x0[i * c.d + k] - c.x0[j * c.d + k], c.th[k]) * c.cm[i * n + j]
                    s1 += c.kz[i] * dc * c.kz[j]
                    tr += c.ki[i * n + j] * dc
                    j += 1usize
                }
                i += 1usize
            }
            out[k] = 0.0f64 - (nf / 2.0f64 * s1 / denom - 0.5f64 * tr)
            k += 1usize
        }
        idx = c.d
    }
    if !c.has_g {
        var s2 = 0.0f64
        var tr = 0.0f64
        var i = 0usize
        while i < n {
            s2 += c.kz[i] * c.kz[i] / c.mult[i]
            tr += c.ki[i * n + i] / c.mult[i]
            i += 1usize
        }
        out[idx] = 0.0f64 - (nf / 2.0f64 * (c.q / (g * g) + s2) / denom - (nf - f64(n)) / (2.0f64 * g) - 0.5f64 * tr)
    }
}

// the model of mleHomGP(list(X0, Z0, mult), Z) under the settings in o
fn hom_fit(a: *mem.Arena, x0: []const f64, z0: []const f64, z: []const f64, mult: []const f64, n: usize, d: usize, nn: usize, o: *HomOpt, f: *HomFit) -> err {
    var c: HomC = zero
    c.n = n
    c.d = d
    c.nn = nn
    c.ctype = o.ctype
    c.eps = o.eps
    c.x0 = x0
    c.z0 = z0
    c.z = z
    c.mult = mult
    c.has_b0 = o.has_beta0
    c.b0 = o.beta0
    c.has_theta = o.has_theta
    c.has_g = o.has_g
    c.g0 = o.g
    let (th, e1) = mem.alloc[f64](a, d)
    let (cm, e2) = mem.alloc[f64](a, n * n)
    let (km, e3) = mem.alloc[f64](a, n * n)
    let (lm, e4) = mem.alloc[f64](a, n * n)
    let (li, e5) = mem.alloc[f64](a, n * n)
    let (ki, e6) = mem.alloc[f64](a, n * n)
    let (kz, e7) = mem.alloc[f64](a, n)
    let (best, e8) = mem.alloc[f64](a, d + 1usize)
    let (lower, e9) = mem.alloc[f64](a, d)
    let (upper, e10) = mem.alloc[f64](a, d)
    let (theta_out, e11) = mem.alloc[f64](a, d)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    if e11 != ok { ret e11 }
    c.th = th
    c.cm = cm
    c.km = km
    c.lm = lm
    c.li = li
    c.ki = ki
    c.kz = kz
    c.best = best
    var k = 0usize
    while k < d {
        lower[k] = o.lower[k]
        upper[k] = o.upper[k]
        k += 1usize
    }
    if (o.auto_lo || o.auto_up) && !o.has_theta {
        let (alo, e12) = mem.alloc[f64](a, d)
        let (aup, e13) = mem.alloc[f64](a, d)
        if e12 != ok { ret e12 }
        if e13 != ok { ret e13 }
        let ea = auto_bounds(a, x0, n, d, o.ctype, alo, aup)
        if ea != ok { ret ea }
        k = 0usize
        while k < d {
            if o.auto_lo { lower[k] = alo[k] }
            if o.auto_up { upper[k] = aup[k] }
            k += 1usize
        }
    }
    var gfit = o.g
    var ll = 0.0f64
    if o.has_theta {
        k = 0usize
        while k < d {
            theta_out[k] = o.theta[k]
            c.th[k] = o.theta[k]
            k += 1usize
        }
    }
    if o.has_theta && o.has_g {
        let (v, good) = hom_core(&c, theta_out, o.g)
        if !good { ret mem.Exhausted }
        ll = v
    } else {
        var cnt = 0usize
        if !o.has_theta { cnt += d }
        if !o.has_g { cnt += 1usize }
        let (par, e14) = mem.alloc[f64](a, cnt)
        let (plo, e15) = mem.alloc[f64](a, cnt)
        let (pup, e16) = mem.alloc[f64](a, cnt)
        if e14 != ok { ret e14 }
        if e15 != ok { ret e15 }
        if e16 != ok { ret e16 }
        var pos = 0usize
        if !o.has_theta {
            k = 0usize
            while k < d {
                if o.has_init_theta {
                    par[pos] = o.init_theta[k]
                } else {
                    if o.auto_lo || o.auto_up {
                        par[pos] = math.sqrt[f64](upper[k] * lower[k])
                    } else {
                        par[pos] = 0.9f64 * lower[k] + 0.1f64 * upper[k]
                    }
                }
                plo[pos] = lower[k]
                pup[pos] = upper[k]
                pos += 1usize
                k += 1usize
            }
        }
        if !o.has_g {
            var ginit = 0.1f64
            if o.has_init_g {
                ginit = o.init_g
            } else {
                var anyrep = false
                var sg = 0.0f64
                var cg = 0.0f64
                var i = 0usize
                var zpos = 0usize
                while i < n {
                    if mult[i] > 2.0f64 {
                        anyrep = true
                        var ss = 0.0f64
                        var r = 0usize
                        while r < usize(mult[i]) {
                            let dz = z[zpos + r] - z0[i]
                            ss += dz * dz
                            r += 1usize
                        }
                        sg += ss / mult[i]
                        cg += 1.0f64
                    }
                    zpos += usize(mult[i])
                    i += 1usize
                }
                if anyrep {
                    var mz = 0.0f64
                    i = 0usize
                    while i < n {
                        mz += z0[i]
                        i += 1usize
                    }
                    mz = mz / f64(n)
                    var vz = 0.0f64
                    i = 0usize
                    while i < n {
                        vz += (z0[i] - mz) * (z0[i] - mz)
                        i += 1usize
                    }
                    vz = vz / f64(n - 1usize)
                    ginit = sg / cg / vz
                }
            }
            par[pos] = ginit
            plo[pos] = o.gmin
            pup[pos] = o.gmax
        }
        let (fv, code) = lb.lbfgsb[HomC](a, &c, hom_fn, hom_gr, par, plo, pup, o.factr, 0.0f64, 5usize, o.maxit)
        var fin = par
        ll = 0.0f64 - fv
        if code == 52i64 {
            fin = c.best[0usize..cnt]
            ll = c.bestll
        }
        var q = 0usize
        if !o.has_theta {
            k = 0usize
            while k < d {
                theta_out[k] = fin[k]
                k += 1usize
            }
            q = d
        }
        if !o.has_g { gfit = fin[q] }
    }
    let (ll2, good2) = hom_core(&c, theta_out, gfit)
    if !good2 { ret mem.Exhausted }
    f.n = n
    f.d = d
    f.nn = nn
    f.ctype = o.ctype
    f.eps = o.eps
    f.sk = o.has_beta0
    f.g = gfit
    f.nu = c.psi
    f.ll = ll
    f.beta0 = c.beta
    f.theta = theta_out
    f.lower = lower
    f.upper = upper
    f.x0 = x0
    f.z0 = z0
    f.z = z
    f.mult = mult
    f.ki = ki
    f.opt = *o
    ret ok
}

// ---- prediction ----

// mean, sd2, nugs at the m rows of xt; cov (m by mp) only when mp > 0 against the rows of xp
fn hom_predict(a: *mem.Arena, f: *HomFit, xt: []const f64, m: usize, xp: []const f64, mp: usize, mean: []f64, sd2: []f64, nugs: []f64, cv: []f64) -> err {
    let n = f.n
    let d = f.d
    let (kv, e1) = mem.alloc[f64](a, n)
    let (kk, e2) = mem.alloc[f64](a, n)
    let (rs, e3) = mem.alloc[f64](a, n)
    let (kiz, e4) = mem.alloc[f64](a, n)
    let (kq, e5) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    var ski = 0.0f64
    var i = 0usize
    while i < n {
        var r = 0.0f64
        var s = 0.0f64
        var j = 0usize
        while j < n {
            r += f.ki[i * n + j]
            s += f.ki[i * n + j] * (f.z0[j] - f.beta0)
            j += 1usize
        }
        rs[i] = r
        kiz[i] = s
        ski += r
        i += 1usize
    }
    var t = 0usize
    while t < m {
        i = 0usize
        while i < n {
            kv[i] = cov_pt(f.ctype, xt, t, f.x0, i, d, f.theta)
            i += 1usize
        }
        var mu = f.beta0
        var q = 0.0f64
        var ak = 0.0f64
        i = 0usize
        while i < n {
            var r = 0.0f64
            var j = 0usize
            while j < n {
                r += f.ki[i * n + j] * kv[j]
                j += 1usize
            }
            kk[i] = r
            mu += kv[i] * kiz[i]
            q += kv[i] * r
            ak += rs[i] * kv[i]
            i += 1usize
        }
        mean[t] = mu
        var v = f.nu * (1.0f64 - q)
        if !f.sk { v += f.nu * (1.0f64 - ak) * (1.0f64 - ak) / ski }
        if v < 0.0f64 { v = 0.0f64 }
        sd2[t] = v
        nugs[t] = f.nu * f.g
        var u = 0usize
        while u < mp {
            var kxp = 0.0f64
            var axp = 0.0f64
            var cross = 0.0f64
            i = 0usize
            while i < n {
                kq[i] = cov_pt(f.ctype, xp, u, f.x0, i, d, f.theta)
                cross += kq[i] * kk[i]
                axp += rs[i] * kq[i]
                i += 1usize
            }
            kxp = cov_pt(f.ctype, xt, t, xp, u, d, f.theta)
            var cc = f.nu * kxp - f.nu * cross
            if !f.sk { cc += f.nu * (1.0f64 - ak) * (1.0f64 - axp) / ski }
            cv[t * mp + u] = cc
            u += 1usize
        }
        t += 1usize
    }
    ret ok
}

fn log1mexp(x: f64) -> f64 {
    if x <= math.log[f64](2.0f64) { ret math.log[f64](0.0f64 - dist.expm1(0.0f64 - x)) }
    ret dist.log1p(0.0f64 - math.exp[f64](0.0f64 - x))
}

fn erfcx(x: f64) -> f64 { ret math.exp[f64](x * x) * 2.0f64 * dist.pnorm(x * math.sqrt[f64](2.0f64), 0.0f64, 1.0f64, false, false) }

// hetGP log_h (Ament et al. 2024)
fn log_h(z: f64) -> f64 {
    let pi = 3.141592653589793f64
    let c1 = math.log[f64](2.0f64 * pi) / 2.0f64
    let c2 = math.log[f64](pi / 2.0f64) / 2.0f64
    if z > 0.0f64 - 1.0f64 { ret math.log[f64](dist.dnorm(z, 0.0f64, 1.0f64, false) + z * dist.pnorm(z, 0.0f64, 1.0f64, true, false)) }
    if z < 0.0f64 - 1.0f64 / math.sqrt[f64](2.220446049250313e-16f64) { ret 0.0f64 - z * z / 2.0f64 - c1 - 2.0f64 * math.log[f64](math.abs[f64](z)) }
    let arg = 0.0f64 - (math.log[f64](erfcx(0.0f64 - z / math.sqrt[f64](2.0f64)) * math.abs[f64](z)) + c2)
    if !(arg >= 0.0f64) { ret 0.0f64 - 750.0f64 }
    let res = 0.0f64 - z * z / 2.0f64 - c1 + log1mexp(arg)
    if res != res { ret 0.0f64 - 750.0f64 }
    ret res
}

// crit_EI (cst given) or with cst = min of the predicted means at the designs; res is zero where sd2 < sqrt(eps) or EI < 1e-12
fn hom_ei(a: *mem.Arena, f: *HomFit, xt: []const f64, m: usize, has_cst: bool, cst0: f64, log_ei: bool, out: []f64) -> err {
    var cst = cst0
    let (mean, e1) = mem.alloc[f64](a, m)
    let (sd2, e2) = mem.alloc[f64](a, m)
    let (nugs, e3) = mem.alloc[f64](a, m)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if !has_cst {
        let (m0, e4) = mem.alloc[f64](a, f.n)
        let (s0, e5) = mem.alloc[f64](a, f.n)
        let (g0, e6) = mem.alloc[f64](a, f.n)
        if e4 != ok { ret e4 }
        if e5 != ok { ret e5 }
        if e6 != ok { ret e6 }
        let ep = hom_predict(a, f, f.x0, f.n, f.x0, 0usize, m0, s0, g0, g0)
        if ep != ok { ret ep }
        cst = m0[0usize]
        var i = 1usize
        while i < f.n {
            if m0[i] < cst { cst = m0[i] }
            i += 1usize
        }
    }
    let ep2 = hom_predict(a, f, xt, m, xt, 0usize, mean, sd2, nugs, nugs)
    if ep2 != ok { ret ep2 }
    var t = 0usize
    while t < m {
        let s = math.sqrt[f64](sd2[t])
        let xcr = (cst - mean[t]) / s
        if log_ei {
            var lv = log_h(xcr) + math.log[f64](s)
            if sd2[t] == 0.0f64 { lv = 0.0f64 - 800.0f64 }
            out[t] = lv
            t += 1usize
            continue
        }
        var res = (cst - mean[t]) * dist.pnorm(xcr, 0.0f64, 1.0f64, true, false) + s * dist.dnorm(xcr, 0.0f64, 1.0f64, false)
        if sd2[t] < 1.4901161193847656e-8f64 || res < 1.0e-12f64 { res = 0.0f64 }
        out[t] = res
        t += 1usize
    }
    ret ok
}

// ---- update ----

// update.homGP(maxit = 0): new designs are appended, a repeated design merges into its row, Ki is the inverse of the new
// covariance, and beta0, nu_hat and ll stay those of the old fit (as hetGP leaves them)
fn hom_update0(a: *mem.Arena, f: *HomFit, xn: []const f64, zn: []const f64, nnew: usize, g: *HomFit) -> err {
    let d = f.d
    let total = f.n + nnew
    let (x0, e1) = mem.alloc[f64](a, total * d)
    let (z0, e2) = mem.alloc[f64](a, total)
    let (mult, e3) = mem.alloc[f64](a, total)
    let (zall, e4) = mem.alloc[f64](a, f.nn + nnew)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    let (nx0, e5) = mem.alloc[f64](a, nnew * d)
    let (nz0, e6) = mem.alloc[f64](a, nnew)
    let (nmu, e7) = mem.alloc[f64](a, nnew)
    let (nzs, e8) = mem.alloc[f64](a, nnew)
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    let (nu_new, e9) = find_reps(a, xn, zn, nnew, d, nx0, nz0, nmu, nzs)
    if e9 != ok { ret e9 }
    var i = 0usize
    while i < f.n * d {
        x0[i] = f.x0[i]
        i += 1usize
    }
    i = 0usize
    while i < f.n {
        z0[i] = f.z0[i]
        mult[i] = f.mult[i]
        i += 1usize
    }
    i = 0usize
    while i < f.nn {
        zall[i] = f.z[i]
        i += 1usize
    }
    var n = f.n
    var nz = f.nn
    var zp = 0usize
    var u = 0usize
    while u < nu_new {
        var hit = n
        var r = 0usize
        while r < f.n {
            var same = true
            var c = 0usize
            while c < d {
                if nx0[u * d + c] != f.x0[r * d + c] { same = false }
                c += 1usize
            }
            if same { hit = r }
            r += 1usize
        }
        let cnt = usize(nmu[u])
        if hit < f.n {
            z0[hit] = (mult[hit] * z0[hit] + nz0[u] * nmu[u]) / (mult[hit] + nmu[u])
            mult[hit] += nmu[u]
        } else {
            var c = 0usize
            while c < d {
                x0[n * d + c] = nx0[u * d + c]
                c += 1usize
            }
            z0[n] = nz0[u]
            mult[n] = nmu[u]
            n += 1usize
        }
        r = 0usize
        while r < cnt {
            zall[nz + r] = nzs[zp + r]
            r += 1usize
        }
        nz += cnt
        zp += cnt
        u += 1usize
    }
    let (cm, e10) = mem.alloc[f64](a, n * n)
    let (lm, e11) = mem.alloc[f64](a, n * n)
    let (li, e12) = mem.alloc[f64](a, n * n)
    let (ki, e13) = mem.alloc[f64](a, n * n)
    if e10 != ok { ret e10 }
    if e11 != ok { ret e11 }
    if e12 != ok { ret e12 }
    if e13 != ok { ret e13 }
    cov_mat(x0, n, x0, n, d, f.theta, f.ctype, cm)
    i = 0usize
    while i < n {
        cm[i * n + i] += f.eps + f.g / mult[i]
        i += 1usize
    }
    if !chol(cm, n, lm) { ret mem.Exhausted }
    chol_inv(lm, n, li, ki)
    *g = *f
    g.n = n
    g.nn = nz
    g.x0 = x0
    g.z0 = z0
    g.z = zall
    g.mult = mult
    g.ki = ki
    ret ok
}

// update.homGP(maxit > 0): the merged data are refitted from the old hyperparameters under the stored bounds and known values
fn hom_update_fit(a: *mem.Arena, f: *HomFit, xn: []const f64, zn: []const f64, nnew: usize, maxit: usize, g: *HomFit) -> err {
    let e0 = hom_update0(a, f, xn, zn, nnew, g)
    if e0 != ok { ret e0 }
    var o = f.opt
    o.auto_lo = false
    o.auto_up = false
    o.lower = f.lower
    o.upper = f.upper
    o.maxit = maxit
    o.has_init_theta = false
    o.has_init_g = false
    if !o.has_theta {
        o.has_init_theta = true
        o.init_theta = f.theta
    }
    if !o.has_g {
        o.has_init_g = true
        o.init_g = f.g
    }
    let nx = g.n
    let nzz = g.nn
    ret hom_fit(a, g.x0, g.z0, g.z, g.mult, nx, g.d, nzz, &o, g)
}

// ---- heteroskedastic model: mleHetGP (joint thetas, logN, residual initialisation, penalty, checkHom) ----

type HetOpt = struct {
    ctype: usize, auto_lo: bool, auto_up: bool, lower: []const f64, upper: []const f64,
    has_th: bool, th: []const f64, has_g: bool, g: f64, has_kt: bool, kt: f64, has_b0: bool, b0: f64, has_dl: bool, dl: []const f64,
    maxit: usize, factr: f64, eps: f64, penalty: bool, check_hom: bool
}

type HetFit = struct {
    is_hom: bool, hom: HomFit, hv: HomFit, n: usize, d: usize, nn: usize, ctype: usize, eps: f64, nu: f64, beta0: f64, kt: f64, g: f64,
    nmean: f64, nuvar: f64, skgi: f64, ll: f64, ll_np: f64, sk: bool,
    theta: []f64, thg: []f64, dl: []f64, lam: []f64, kgi: []f64, ki: []f64, rs: []f64, lower: []f64, upper: []f64,
    x0: []const f64, z0: []const f64, z: []const f64, mult: []const f64, opt: HetOpt
}

type HetC = struct {
    n: usize, d: usize, nn: usize, ctype: usize, eps: f64, x0: []const f64, z0: []const f64, z: []const f64, mult: []const f64,
    has_b0: bool, b0: f64, has_th: bool, has_g: bool, has_kt: bool, th0: []const f64, g0: f64, kt0: f64, hom_ll: f64, use_pen: bool,
    th: []f64, thg: []f64, dl: []f64, kt: f64, g: f64,
    cm: []f64, cg: []f64, km: []f64, lm: []f64, li: []f64, ki: []f64, kgi: []f64, mm: []f64, dm: []f64,
    rs: []f64, kd: []f64, kgd: []f64, kgdl: []f64, lam: []f64, kz: []f64, sg: []f64, vv: []f64, gg: []f64, tt: []f64, rsm: []f64, tmp: []f64,
    nmean: f64, skgi: f64, ldet: f64, sldkg: f64, beta: f64, psi: f64, psi0: f64, nuvar: f64, rsd: f64, ll: f64, pen: f64, penact: bool,
    bestll: f64, best: []f64, nbest: usize
}

fn het_unpack(c: *HetC, p: []const f64) {
    var idx = 0usize
    var k = 0usize
    while k < c.d {
        if c.has_th {
            c.th[k] = c.th0[k]
        } else {
            c.th[k] = p[k]
        }
        k += 1usize
    }
    if !c.has_th { idx = c.d }
    k = 0usize
    while k < c.n {
        c.dl[k] = p[idx + k]
        k += 1usize
    }
    idx += c.n
    if c.has_kt {
        c.kt = c.kt0
    } else {
        c.kt = p[idx]
        idx += 1usize
    }
    if c.has_g {
        c.g = c.g0
    } else {
        c.g = p[idx]
    }
}

// logLikH at (th, dl, kt, g); grad selects the smoothing matrix route dlogLikHet takes for Lambda. Fills every matrix the gradient needs.
fn het_core(c: *HetC, grad: bool, pen_allowed: bool) -> bool {
    let n = c.n
    let d = c.d
    var k = 0usize
    while k < d {
        c.thg[k] = c.kt * c.th[k]
        k += 1usize
    }
    cov_mat(c.x0, n, c.x0, n, d, c.thg, c.ctype, c.cg)
    var i = 0usize
    while i < n * n {
        c.km[i] = c.cg[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        c.km[i * n + i] += c.eps + c.g / c.mult[i]
        i += 1usize
    }
    if !chol(c.km, n, c.lm) { ret false }
    var sl = 0.0f64
    i = 0usize
    while i < n {
        sl += math.log[f64](c.lm[i * n + i])
        i += 1usize
    }
    c.sldkg = sl
    chol_inv(c.lm, n, c.li, c.kgi)
    var sk = 0.0f64
    var sd = 0.0f64
    i = 0usize
    while i < n {
        var r = 0.0f64
        var j = 0usize
        while j < n {
            r += c.kgi[i * n + j]
            j += 1usize
        }
        c.rs[i] = r
        sk += r
        sd += r * c.dl[i]
        i += 1usize
    }
    c.skgi = sk
    c.rsd = sd
    c.nmean = sd / sk
    i = 0usize
    while i < n {
        c.kd[i] = c.dl[i] - c.nmean
        i += 1usize
    }
    i = 0usize
    while i < n {
        var s1 = 0.0f64
        var s2 = 0.0f64
        var j = 0usize
        while j < n {
            s1 += c.kgi[i * n + j] * c.kd[j]
            s2 += c.kgi[i * n + j] * c.dl[j]
            j += 1usize
        }
        c.kgd[i] = s1
        c.kgdl[i] = s2
        i += 1usize
    }
    var qd = 0.0f64
    i = 0usize
    while i < n {
        qd += c.kd[i] * c.kgd[i]
        i += 1usize
    }
    c.nuvar = qd / f64(n)
    i = 0usize
    while i < n {
        var rr = 0.0f64
        var j = 0usize
        while j < n {
            var mv = 0.0f64 - (c.eps + c.g / c.mult[i]) * c.kgi[i * n + j]
            if i == j { mv += 1.0f64 }
            c.mm[i * n + j] = mv
            rr += mv
            j += 1usize
        }
        c.rsm[i] = rr
        i += 1usize
    }
    i = 0usize
    while i < n {
        var sm = 0.0f64
        var j = 0usize
        while j < n {
            if grad {
                sm += c.mm[i * n + j] * c.kd[j]
            } else {
                sm += c.cg[i * n + j] * c.kgd[j]
            }
            j += 1usize
        }
        c.lam[i] = math.exp[f64](c.nmean + sm)
        i += 1usize
    }
    cov_mat(c.x0, n, c.x0, n, d, c.th, c.ctype, c.cm)
    i = 0usize
    while i < n * n {
        c.km[i] = c.cm[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        c.km[i * n + i] += c.lam[i] / c.mult[i] + c.eps
        i += 1usize
    }
    if !chol(c.km, n, c.lm) { ret false }
    var ldet = 0.0f64
    i = 0usize
    while i < n {
        ldet -= 2.0f64 * math.log[f64](c.lm[i * n + i])
        i += 1usize
    }
    c.ldet = ldet
    chol_inv(c.lm, n, c.li, c.ki)
    var beta = c.b0
    if !c.has_b0 {
        var s1 = 0.0f64
        var sz = 0.0f64
        i = 0usize
        while i < n {
            var cs = 0.0f64
            var j = 0usize
            while j < n {
                cs += c.ki[j * n + i]
                j += 1usize
            }
            s1 += cs
            sz += cs * c.z0[i]
            i += 1usize
        }
        beta = sz / s1
    }
    c.beta = beta
    var psi0 = 0.0f64
    i = 0usize
    while i < n {
        var r = 0.0f64
        var j = 0usize
        while j < n {
            r += c.ki[i * n + j] * (c.z0[j] - beta)
            j += 1usize
        }
        c.kz[i] = r
        psi0 += (c.z0[i] - beta) * r
        i += 1usize
    }
    c.psi0 = psi0
    var psi = psi0
    var pos = 0usize
    var sml = 0.0f64
    i = 0usize
    while i < n {
        var ss = 0.0f64
        var r = 0usize
        let mi = usize(c.mult[i])
        while r < mi {
            ss += (c.z[pos + r] - beta) * (c.z[pos + r] - beta)
            r += 1usize
        }
        pos += mi
        c.sg[i] = ss
        psi += ss / c.lam[i] - c.mult[i] * (c.z0[i] - beta) * (c.z0[i] - beta) / c.lam[i]
        sml += (c.mult[i] - 1.0f64) * math.log[f64](c.lam[i]) + math.log[f64](c.mult[i])
        i += 1usize
    }
    c.psi = psi
    let nf = f64(c.nn)
    let ll = 0.0f64 - nf / 2.0f64 * math.log[f64](2.0f64 * 3.141592653589793f64) - nf / 2.0f64 * math.log[f64](psi / nf) + 0.5f64 * ldet - 0.5f64 * sml - nf / 2.0f64
    c.ll = ll
    c.pen = 0.0f64
    c.penact = false
    if pen_allowed && !(c.nuvar < c.eps) {
        let nd = f64(n)
        let pen = 0.0f64 - nd / 2.0f64 * math.log[f64](c.nuvar) - sl - nd / 2.0f64 * math.log[f64](2.0f64 * 3.141592653589793f64) - nd / 2.0f64
        c.pen = pen
        if !(ll < c.hom_ll && pen > 0.0f64) { c.penact = true }
    }
    ret true
}

fn het_fn(c: *HetC, p: []const f64) -> f64 {
    het_unpack(c, p)
    if !het_core(c, false, c.use_pen) { ret nan() }
    var tot = c.ll
    if c.penact { tot += c.pen }
    if c.nbest == 0usize || tot > c.bestll {
        c.bestll = tot
        c.nbest = p.len
        var k = 0usize
        while k < p.len {
            c.best[k] = p[k]
            k += 1usize
        }
    }
    ret 0.0f64 - tot
}

// smoothing direction T = (I - M) dm kgd - (1 - rowsum M) s, the part of dlogLikHet shared by theta, k_theta_g and g; leaves dm kgd in tmp
fn het_dir(c: *HetC) {
    let n = c.n
    var a1 = 0.0f64
    var b1 = 0.0f64
    var i = 0usize
    while i < n {
        var u = 0.0f64
        var pa = 0.0f64
        var pb = 0.0f64
        var j = 0usize
        while j < n {
            let v = c.dm[i * n + j]
            u += v * c.kgd[j]
            pa += v * c.kgdl[j]
            pb += v * c.rs[j]
            j += 1usize
        }
        c.tmp[i] = u
        a1 += c.rs[i] * pa
        b1 += c.rs[i] * pb
        i += 1usize
    }
    let sc = (a1 * c.skgi - c.rsd * b1) / (c.skgi * c.skgi)
    i = 0usize
    while i < n {
        var w = 0.0f64
        var j = 0usize
        while j < n {
            w += c.mm[i * n + j] * c.tmp[j]
            j += 1usize
        }
        c.tt[i] = c.tmp[i] - w - (1.0f64 - c.rsm[i]) * sc
        i += 1usize
    }
}

fn het_gr(c: *HetC, p: []const f64, out: []f64) {
    het_unpack(c, p)
    let n = c.n
    let d = c.d
    if !het_core(c, true, c.use_pen) {
        var q = 0usize
        while q < out.len {
            out[q] = nan()
            q += 1usize
        }
        ret
    }
    let nf = f64(c.nn)
    let pen = c.penact
    let nv = c.nuvar
    var i = 0usize
    var sv = 0.0f64
    while i < n {
        let l = c.lam[i]
        let b2 = c.mult[i] * (c.z0[i] - c.beta) * (c.z0[i] - c.beta)
        c.gg[i] = (c.sg[i] - b2) / (l * l)
        var v = nf / 2.0f64 * (c.gg[i] + c.kz[i] * c.kz[i] / c.mult[i]) / c.psi - (c.mult[i] - 1.0f64) / (2.0f64 * l) - c.ki[i * n + i] / (2.0f64 * c.mult[i])
        v = v * l
        c.vv[i] = v
        sv += v
        i += 1usize
    }
    var idx = 0usize
    if !c.has_th {
        var k = 0usize
        while k < d {
            var i2 = 0usize
            var kzc = 0.0f64
            var trk = 0.0f64
            while i2 < n {
                var j = 0usize
                while j < n {
                    let dx = c.x0[i2 * d + k] - c.x0[j * d + k]
                    let dc = dlnk(c.ctype, dx, c.th[k]) * c.cm[i2 * n + j]
                    kzc += c.kz[i2] * dc * c.kz[j]
                    trk += c.ki[i2 * n + j] * dc
                    if !c.has_kt { c.dm[i2 * n + j] = dlnk(c.ctype, dx, c.thg[k]) * c.kt * c.cg[i2 * n + j] }
                    j += 1usize
                }
                i2 += 1usize
            }
            var val = 0.0f64
            if c.has_kt {
                val = nf / 2.0f64 * kzc / c.psi - 0.5f64 * trk
            } else {
                het_dir(c)
                var s1 = 0.0f64
                var s2 = 0.0f64
                var s3 = 0.0f64
                var s4 = 0.0f64
                i2 = 0usize
                while i2 < n {
                    let tl = c.tt[i2] * c.lam[i2]
                    s1 += tl * c.gg[i2]
                    s2 += c.kz[i2] * c.kz[i2] * tl / c.mult[i2]
                    s3 += c.ki[i2 * n + i2] * tl / c.mult[i2]
                    s4 += (c.mult[i2] - 1.0f64) * tl / c.lam[i2]
                    i2 += 1usize
                }
                val = nf / 2.0f64 * (s1 + kzc + s2) / c.psi - 0.5f64 * (trk + s3) - 0.5f64 * s4
                if pen {
                    var qd = 0.0f64
                    var tg = 0.0f64
                    i2 = 0usize
                    while i2 < n {
                        qd += c.kgd[i2] * c.tmp[i2]
                        var j = 0usize
                        while j < n {
                            tg += c.kgi[i2 * n + j] * c.dm[i2 * n + j]
                            j += 1usize
                        }
                        i2 += 1usize
                    }
                    val += 0.5f64 * qd / nv - 0.5f64 * tg
                }
            }
            out[k] = 0.0f64 - val
            k += 1usize
        }
        idx = d
    }
    var smv = 0.0f64
    var j = 0usize
    while j < n {
        var s = 0.0f64
        i = 0usize
        while i < n {
            s += c.mm[i * n + j] * c.vv[i]
            i += 1usize
        }
        c.tmp[j] = s
        smv += s
        j += 1usize
    }
    j = 0usize
    while j < n {
        var gd = c.tmp[j] + c.rs[j] / c.skgi * sv - c.rs[j] / c.skgi * smv
        if pen { gd -= c.kgd[j] / nv }
        out[idx + j] = 0.0f64 - gd
        j += 1usize
    }
    idx += n
    if !c.has_kt {
        var i3 = 0usize
        while i3 < n {
            var j3 = 0usize
            while j3 < n {
                var sdk = 0.0f64
                var k = 0usize
                while k < d {
                    let dx = c.x0[i3 * d + k] - c.x0[j3 * d + k]
                    // hetGP's d_matern3_2_1args_kthetag subtracts (-=) where the other kernels add: its Matern3_2 gradient in k_theta_g
                    // has the wrong sign, and the optimiser follows it, so it is reproduced
                    var sg = 1.0f64
                    if c.ctype == 2usize { sg = 0.0f64 - 1.0f64 }
                    sdk += sg * c.th[k] * dlnk(c.ctype, dx, c.thg[k])
                    k += 1usize
                }
                c.dm[i3 * n + j3] = sdk * c.cg[i3 * n + j3]
                j3 += 1usize
            }
            i3 += 1usize
        }
        het_dir(c)
        var dk = 0.0f64
        i = 0usize
        while i < n {
            dk += c.tt[i] * c.vv[i]
            i += 1usize
        }
        if pen {
            var qd = 0.0f64
            var tg = 0.0f64
            i = 0usize
            while i < n {
                qd += c.kgd[i] * c.tmp[i]
                j = 0usize
                while j < n {
                    tg += c.kgi[i * n + j] * c.dm[i * n + j]
                    j += 1usize
                }
                i += 1usize
            }
            dk += 0.5f64 * qd / nv - 0.5f64 * tg
        }
        out[idx] = 0.0f64 - dk
        idx += 1usize
    }
    if !c.has_g {
        var srm = 0.0f64
        var sd1 = 0.0f64
        i = 0usize
        while i < n {
            srm += c.rs[i] * c.rs[i] / c.mult[i]
            var w = 0.0f64
            j = 0usize
            while j < n {
                w += c.kgi[i * n + j] * c.rs[j] / c.mult[j]
                j += 1usize
            }
            sd1 += c.dl[i] * w
            i += 1usize
        }
        let sc = (sd1 * c.skgi - c.rsd * srm) / (c.skgi * c.skgi)
        var dg = 0.0f64
        i = 0usize
        while i < n {
            var w = 0.0f64
            j = 0usize
            while j < n {
                w += c.mm[i * n + j] * c.kgd[j] / c.mult[j]
                j += 1usize
            }
            dg += (0.0f64 - w - (1.0f64 - c.rsm[i]) * sc) * c.vv[i]
            i += 1usize
        }
        if pen {
            var q1 = 0.0f64
            var q2 = 0.0f64
            i = 0usize
            while i < n {
                q1 += c.kgd[i] / c.mult[i] * c.kgd[i]
                q2 += c.kgi[i * n + i] / c.mult[i]
                i += 1usize
            }
            dg += 0.5f64 * q1 / nv - 0.5f64 * q2
        }
        out[idx] = 0.0f64 - dg
    }
}

fn svar(v: []const f64, n: usize) -> f64 {
    var m = 0.0f64
    var i = 0usize
    while i < n {
        m += v[i]
        i += 1usize
    }
    m = m / f64(n)
    var s = 0.0f64
    i = 0usize
    while i < n {
        s += (v[i] - m) * (v[i] - m)
        i += 1usize
    }
    ret s / f64(n - 1usize)
}

// mleHetGP(list(X0, Z0, mult), Z) with the default noiseControl and settings (linkThetas joint, logN, residuals, penalty, checkHom)
fn het_fit(a: *mem.Arena, x0: []const f64, z0: []const f64, z: []const f64, mult: []const f64, n: usize, d: usize, nn: usize, o: *HetOpt, f: *HetFit) -> err {
    let (lower, e1) = mem.alloc[f64](a, d)
    let (upper, e2) = mem.alloc[f64](a, d)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    var k = 0usize
    while k < d {
        lower[k] = o.lower[k]
        upper[k] = o.upper[k]
        k += 1usize
    }
    if o.auto_lo || o.auto_up {
        let (alo, e3) = mem.alloc[f64](a, d)
        let (aup, e4) = mem.alloc[f64](a, d)
        if e3 != ok { ret e3 }
        if e4 != ok { ret e4 }
        let ea = auto_bounds(a, x0, n, d, o.ctype, alo, aup)
        if ea != ok { ret ea }
        k = 0usize
        while k < d {
            if o.auto_lo { lower[k] = alo[k] }
            if o.auto_up { upper[k] = aup[k] }
            k += 1usize
        }
    }
    var ini: HetInit = zero
    if o.has_dl && o.has_th && o.has_kt && o.has_g {
        ini.th = o.th
        ini.kt = o.kt
        ini.gn = o.g
        ini.nl0 = o.dl
    } else {
        let ei = het_init(a, x0, z0, z, mult, n, d, nn, o, lower, upper, &ini)
        if ei != ok { ret ei }
    }
    ret het_run(a, x0, z0, z, mult, n, d, nn, o, lower, upper, &ini, f)
}

type HetInit = struct { hf: HomFit, th: []const f64, kt: f64, gn: f64, nl0: []const f64 }

// the homoskedastic fit of the mean, the residual start of Delta and the noise-process fit that give mleHetGP its starting point
fn het_init(a: *mem.Arena, x0: []const f64, z0: []const f64, z: []const f64, mult: []const f64, n: usize, d: usize, nn: usize, o: *HetOpt, lower: []f64, upper: []f64, ri: *HetInit) -> err {
    var k = 0usize
    var ginit = 0.1f64
    var rep5 = false
    var sg5 = 0.0f64
    var c5 = 0.0f64
    var i = 0usize
    var zpos = 0usize
    while i < n {
        let mi = usize(mult[i])
        if mult[i] > 5.0f64 {
            rep5 = true
            var ss = 0.0f64
            var r = 0usize
            while r < mi {
                ss += (z[zpos + r] - z0[i]) * (z[zpos + r] - z0[i])
                r += 1usize
            }
            sg5 += ss / mult[i]
            c5 += 1.0f64
        }
        zpos += mi
        i += 1usize
    }
    if rep5 { ginit = sg5 / c5 / svar(z0, n) }
    var h: HomOpt = zero
    h.ctype = o.ctype
    h.auto_lo = false
    h.auto_up = false
    h.lower = lower
    h.upper = upper
    h.has_theta = o.has_th
    h.theta = o.th
    h.has_init_g = true
    h.init_g = ginit
    h.has_beta0 = o.has_b0
    h.beta0 = o.b0
    h.gmin = o.eps
    h.gmax = 100.0f64
    h.maxit = o.maxit
    h.factr = 10000000.0f64
    h.eps = o.eps
    var hf: HomFit = zero
    let eh = hom_fit(a, x0, z0, z, mult, n, d, nn, &h, &hf)
    if eh != ok { ret eh }
    let (mh, e5) = mem.alloc[f64](a, n)
    let (sh, e6) = mem.alloc[f64](a, n)
    let (gh, e7) = mem.alloc[f64](a, n)
    let (ch, e8) = mem.alloc[f64](a, 1usize)
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    let epr = hom_predict(a, &hf, x0, n, x0, 0usize, mh, sh, gh, ch)
    if epr != ok { ret epr }
    let (ne, e9) = mem.alloc[f64](a, nn)
    let (ne0, e10) = mem.alloc[f64](a, n)
    let (nl0, e11) = mem.alloc[f64](a, n)
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    if e11 != ok { ret e11 }
    zpos = 0usize
    i = 0usize
    while i < n {
        let mi = usize(mult[i])
        var s = 0.0f64
        var r = 0usize
        while r < mi {
            let dz = z[zpos + r] - mh[i]
            ne[zpos + r] = dz * dz / hf.nu
            s += ne[zpos + r]
            r += 1usize
        }
        ne0[i] = s / mult[i]
        zpos += mi
        i += 1usize
    }
    i = 0usize
    while i < nn {
        if ne[i] < 2.220446049250313e-16f64 { ne[i] = 2.220446049250313e-16f64 }
        ne[i] = math.log[f64](ne[i])
        i += 1usize
    }
    var m00 = 0.0f64
    var ml0 = 0.0f64
    zpos = 0usize
    i = 0usize
    while i < n {
        let mi = usize(mult[i])
        var s = 0.0f64
        var r = 0usize
        while r < mi {
            s += ne[zpos + r]
            r += 1usize
        }
        m00 += s / mult[i]
        ml0 += math.log[f64](ne0[i])
        zpos += mi
        i += 1usize
    }
    m00 = m00 / f64(n)
    ml0 = ml0 / f64(n)
    i = 0usize
    while i < nn {
        ne[i] = ne[i] - m00 + ml0
        i += 1usize
    }
    zpos = 0usize
    i = 0usize
    while i < n {
        let mi = usize(mult[i])
        var s = 0.0f64
        var r = 0usize
        while r < mi {
            s += ne[zpos + r]
            r += 1usize
        }
        nl0[i] = s / mult[i]
        zpos += mi
        i += 1usize
    }
    // theta of the mean process, then the noise process
    let (th, e12) = mem.alloc[f64](a, d)
    let (thg, e13) = mem.alloc[f64](a, d)
    if e12 != ok { ret e12 }
    if e13 != ok { ret e13 }
    k = 0usize
    while k < d {
        th[k] = hf.theta[k]
        k += 1usize
    }
    var kt = 1.0f64
    if o.has_kt { kt = o.kt }
    var gn = 0.0f64
    if o.has_g { gn = o.g }
    if !(o.has_kt && o.has_g) {
        if !o.has_g {
            var sv = 0.0f64
            zpos = 0usize
            i = 0usize
            while i < n {
                let mi = usize(mult[i])
                var s = 0.0f64
                var r = 0usize
                while r < mi {
                    s += (ne[zpos + r] - nl0[i]) * (ne[zpos + r] - nl0[i])
                    r += 1usize
                }
                sv += s / mult[i]
                zpos += mi
                i += 1usize
            }
            gn = sv / f64(n) / svar(nl0, n)
        }
        let (tlo, e14) = mem.alloc[f64](a, d)
        let (tup, e15) = mem.alloc[f64](a, d)
        let (tin, e16) = mem.alloc[f64](a, d)
        if e14 != ok { ret e14 }
        if e15 != ok { ret e15 }
        if e16 != ok { ret e16 }
        k = 0usize
        while k < d {
            tin[k] = kt * th[k]
            tlo[k] = tin[k] - o.eps
            tup[k] = tin[k] + o.eps
            k += 1usize
        }
        var hn: HomOpt = zero
        hn.ctype = o.ctype
        hn.lower = tlo
        hn.upper = tup
        hn.has_init_theta = true
        hn.init_theta = tin
        hn.has_init_g = true
        hn.init_g = gn
        hn.gmin = 0.000001f64
        hn.gmax = 1.0f64
        hn.maxit = o.maxit
        hn.factr = 10000000.0f64
        hn.eps = o.eps
        var nf2: HomFit = zero
        let en = hom_fit(a, x0, nl0, ne, mult, n, d, nn, &hn, &nf2)
        if en != ok { ret en }
        if !o.has_g { gn = nf2.g }
    }
    ri.hf = hf
    ri.th = th
    ri.kt = kt
    ri.gn = gn
    ri.nl0 = nl0
    ret ok
}

fn het_run(a: *mem.Arena, x0: []const f64, z0: []const f64, z: []const f64, mult: []const f64, n: usize, d: usize, nn: usize, o: *HetOpt, lower: []f64, upper: []f64, ini: *HetInit, f: *HetFit) -> err {
    let fk = o.has_dl && o.has_th && o.has_kt && o.has_g
    let hf = ini.hf
    let th = ini.th
    let kt = ini.kt
    let gn = ini.gn
    let nl0 = ini.nl0
    var k = 0usize
    var i = 0usize
    // joint optimisation
    var np = n
    if !o.has_th { np += d }
    if !o.has_kt { np += 1usize }
    if !o.has_g { np += 1usize }
    let tot = 9usize * n * n + 14usize * n + 3usize * d + np + 16usize
    let (buf, e17) = mem.alloc[f64](a, tot)
    let (par, e18) = mem.alloc[f64](a, np)
    let (plo, e19) = mem.alloc[f64](a, np)
    let (pup, e20) = mem.alloc[f64](a, np)
    if e17 != ok { ret e17 }
    if e18 != ok { ret e18 }
    if e19 != ok { ret e19 }
    if e20 != ok { ret e20 }
    var c: HetC = zero
    het_ctx(&c, buf, x0, z0, z, mult, n, d, nn, o, np)
    c.hom_ll = hf.ll
    var pos = 0usize
    if !o.has_th {
        k = 0usize
        while k < d {
            par[pos] = th[k]
            plo[pos] = lower[k]
            pup[pos] = upper[k]
            pos += 1usize
            k += 1usize
        }
    }
    i = 0usize
    while i < n {
        par[pos] = nl0[i]
        plo[pos] = math.log[f64](o.eps)
        pup[pos] = math.log[f64](100.0f64)
        pos += 1usize
        i += 1usize
    }
    if !o.has_kt {
        par[pos] = kt
        plo[pos] = 1.0f64
        pup[pos] = 100.0f64
        pos += 1usize
    }
    if !o.has_g {
        par[pos] = gn
        plo[pos] = 0.000001f64
        pup[pos] = 1.0f64
        pos += 1usize
    }
    var fin = par
    var llv = 0.0f64
    if !fk {
        let (fv, code) = lb.lbfgsb[HetC](a, &c, het_fn, het_gr, par, plo, pup, o.factr, 0.0f64, 5usize, o.maxit)
        llv = 0.0f64 - fv
        if code == 52i64 {
            fin = c.best[0usize..np]
            llv = c.bestll
        }
    }
    het_unpack(&c, fin)
    var llnp = llv
    if o.penalty {
        if !het_core(&c, false, false) { ret mem.Exhausted }
        llnp = c.ll
    }
    f.is_hom = false
    f.ll_np = llnp
    if o.check_hom && !fk && hf.ll >= llnp {
        f.is_hom = true
        f.hom = hf
        ret ok
    }
    if !het_core(&c, false, false) { ret mem.Exhausted }
    f.n = n
    f.d = d
    f.nn = nn
    f.ctype = o.ctype
    f.eps = o.eps
    f.nu = c.psi / f64(nn)
    f.beta0 = c.beta
    f.kt = c.kt
    f.g = c.g
    f.nmean = c.nmean
    f.nuvar = c.nuvar
    if f.nuvar < o.eps { f.nuvar = o.eps }
    f.skgi = c.skgi
    f.ll = llv
    f.sk = o.has_b0
    f.theta = c.th
    f.thg = c.thg
    f.dl = c.dl
    f.lam = c.lam
    f.kgi = c.kgi
    f.ki = c.ki
    f.rs = c.rs
    f.lower = lower
    f.upper = upper
    f.x0 = x0
    f.z0 = z0
    f.z = z
    f.mult = mult
    f.opt = *o
    f.hv.n = n
    f.hv.d = d
    f.hv.nn = nn
    f.hv.ctype = o.ctype
    f.hv.eps = o.eps
    f.hv.sk = o.has_b0
    f.hv.g = 0.0f64
    f.hv.nu = f.nu
    f.hv.ll = llv
    f.hv.beta0 = c.beta
    f.hv.theta = c.th
    f.hv.x0 = x0
    f.hv.z0 = z0
    f.hv.z = z
    f.hv.mult = mult
    f.hv.ki = c.ki
    ret ok
}

// predict.hetGP: mean, sd2, nugs (the latent noise), sd2var (variance of the noise predictor), cov
fn het_predict(a: *mem.Arena, f: *HetFit, xt: []const f64, m: usize, xp: []const f64, mp: usize, mean: []f64, sd2: []f64, nugs: []f64, sd2v: []f64, cv: []f64) -> err {
    if f.is_hom {
        var t0 = 0usize
        while t0 < m {
            sd2v[t0] = 0.0f64
            t0 += 1usize
        }
        ret hom_predict(a, &f.hom, xt, m, xp, mp, mean, sd2, nugs, cv)
    }
    let e0 = hom_predict(a, &f.hv, xt, m, xp, mp, mean, sd2, nugs, cv)
    if e0 != ok { ret e0 }
    let n = f.n
    let d = f.d
    let (kg, e1) = mem.alloc[f64](a, n)
    let (kd, e3) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    if e3 != ok { ret e3 }
    var i = 0usize
    while i < n {
        kd[i] = f.dl[i] - f.nmean
        i += 1usize
    }
    var t = 0usize
    while t < m {
        i = 0usize
        while i < n {
            kg[i] = cov_pt(f.ctype, xt, t, f.x0, i, d, f.thg)
            i += 1usize
        }
        var mu = f.nmean
        var q = 0.0f64
        var ak = 0.0f64
        i = 0usize
        while i < n {
            var r = 0.0f64
            var s = 0.0f64
            var j = 0usize
            while j < n {
                r += f.kgi[i * n + j] * kg[j]
                s += f.kgi[i * n + j] * kd[j]
                j += 1usize
            }
            mu += kg[i] * s
            q += kg[i] * r
            ak += f.rs[i] * kg[i]
            i += 1usize
        }
        nugs[t] = f.nu * math.exp[f64](mu)
        sd2v[t] = f.nu * f.nuvar * (1.0f64 - q + (1.0f64 - ak) * (1.0f64 - ak) / f.skgi)
        t += 1usize
    }
    ret ok
}

fn het_ctx(c: *HetC, buf: []f64, x0: []const f64, z0: []const f64, z: []const f64, mult: []const f64, n: usize, d: usize, nn: usize, o: *HetOpt, np: usize) {
    c.n = n
    c.d = d
    c.nn = nn
    c.ctype = o.ctype
    c.eps = o.eps
    c.x0 = x0
    c.z0 = z0
    c.z = z
    c.mult = mult
    c.has_b0 = o.has_b0
    c.b0 = o.b0
    c.has_th = o.has_th
    c.has_g = o.has_g
    c.has_kt = o.has_kt
    c.th0 = o.th
    c.g0 = o.g
    c.kt0 = o.kt
    c.use_pen = o.penalty
    var q = 0usize
    c.th = buf[q..q + d]
    q += d
    c.thg = buf[q..q + d]
    q += d
    c.dl = buf[q..q + n]
    q += n
    c.cm = buf[q..q + n * n]
    q += n * n
    c.cg = buf[q..q + n * n]
    q += n * n
    c.km = buf[q..q + n * n]
    q += n * n
    c.lm = buf[q..q + n * n]
    q += n * n
    c.li = buf[q..q + n * n]
    q += n * n
    c.ki = buf[q..q + n * n]
    q += n * n
    c.kgi = buf[q..q + n * n]
    q += n * n
    c.mm = buf[q..q + n * n]
    q += n * n
    c.dm = buf[q..q + n * n]
    q += n * n
    c.rs = buf[q..q + n]
    q += n
    c.kd = buf[q..q + n]
    q += n
    c.kgd = buf[q..q + n]
    q += n
    c.kgdl = buf[q..q + n]
    q += n
    c.lam = buf[q..q + n]
    q += n
    c.kz = buf[q..q + n]
    q += n
    c.sg = buf[q..q + n]
    q += n
    c.vv = buf[q..q + n]
    q += n
    c.gg = buf[q..q + n]
    q += n
    c.tt = buf[q..q + n]
    q += n
    c.rsm = buf[q..q + n]
    q += n
    c.tmp = buf[q..q + n]
    q += n
    c.best = buf[q..q + np]
}

// logLikHet (value, penalised when pen) and dlogLikHet (grad written to gr in the order theta, Delta, k_theta_g, g) at given parameters;
// R's sign (the log-likelihood and its gradient). hom_ll is the reference homoskedastic log-likelihood of the penalty switch.
fn het_eval(a: *mem.Arena, x0: []const f64, z0: []const f64, z: []const f64, mult: []const f64, n: usize, d: usize, nn: usize, o: *HetOpt, th: []const f64, dl: []const f64, kt: f64, g: f64, hom_ll: f64, pen: bool, gr: []f64) -> (f64, err) {
    let np = d + n + 2usize
    let tot = 9usize * n * n + 14usize * n + 3usize * d + np + 16usize
    let (buf, e1) = mem.alloc[f64](a, tot)
    let (par, e2) = mem.alloc[f64](a, np)
    if e1 != ok { ret (0.0f64, e1) }
    if e2 != ok { ret (0.0f64, e2) }
    var oo = *o
    oo.has_th = false
    oo.has_kt = false
    oo.has_g = false
    var c: HetC = zero
    het_ctx(&c, buf, x0, z0, z, mult, n, d, nn, &oo, np)
    c.hom_ll = hom_ll
    c.use_pen = pen
    var k = 0usize
    while k < d {
        par[k] = th[k]
        k += 1usize
    }
    k = 0usize
    while k < n {
        par[d + k] = dl[k]
        k += 1usize
    }
    par[d + n] = kt
    par[d + n + 1usize] = g
    let fv = het_fn(&c, par)
    het_gr(&c, par, gr)
    k = 0usize
    while k < np {
        gr[k] = 0.0f64 - gr[k]
        k += 1usize
    }
    ret (0.0f64 - fv, ok)
}

// ---- update.hetGP (maxit = 0, method quick) ----

// dst (stride s + 1) is src (stride s) bordered by the new point whose cross covariances with the s old rows are kn and whose
// Schur complement is vn, exactly the block update of hetGP's update_Ki and update_Kgi
fn het_border(src: []const f64, s: usize, kn: []const f64, vn: f64, dst: []f64, gn: []f64) {
    var i = 0usize
    while i < s {
        var r = 0.0f64
        var j = 0usize
        while j < s {
            r += src[i * s + j] * kn[j]
            j += 1usize
        }
        gn[i] = 0.0f64 - r / vn
        i += 1usize
    }
    let t = s + 1usize
    i = 0usize
    while i < s {
        var j = 0usize
        while j < s {
            dst[i * t + j] = src[i * s + j] + gn[i] * gn[j] * vn
            j += 1usize
        }
        dst[i * t + s] = gn[i]
        dst[s * t + i] = gn[i]
        i += 1usize
    }
    dst[s * t + s] = 1.0f64 / vn
}

// update_Ki_rep / update_Kgi_rep: row id of the inverse gets nr more replicates; tmp is Lambda[id] (or g), m the old multiplicity
fn het_rep(km: []f64, s: usize, id: usize, m: f64, nr: f64, tmp: f64, row: []f64) {
    let den = m * (m + nr) / (nr * tmp) - km[id * s + id]
    var k = 0usize
    while k < s {
        row[k] = km[id * s + k]
        k += 1usize
    }
    var i = 0usize
    while i < s {
        var j = 0usize
        while j < s {
            km[i * s + j] = km[i * s + j] + row[i] * row[j] / den
            j += 1usize
        }
        i += 1usize
    }
}

// the model update(object, Xnew, Znew, maxit = 0) leaves: Ki and Kgi follow the rank-one formulas of hetGP, Delta and Lambda of a new
// design come from the noise predictor, and nu_hat, beta0, nmean and nu_hat_var stay those of the old fit. update_Kgi adds g / nrep^2
// (not g / nrep) for a new design with nrep replicates; that is reproduced.
fn het_update0(a: *mem.Arena, f: *HetFit, xn: []const f64, zn: []const f64, nnew: usize, g: *HetFit) -> err {
    if f.is_hom {
        g.is_hom = true
        ret hom_update0(a, &f.hom, xn, zn, nnew, &g.hom)
    }
    let d = f.d
    let n = f.n
    let (nx0, e1) = mem.alloc[f64](a, nnew * d)
    let (nz0, e2) = mem.alloc[f64](a, nnew)
    let (nmu, e3) = mem.alloc[f64](a, nnew)
    let (nzs, e4) = mem.alloc[f64](a, nnew)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    let (nu_new, e5) = find_reps(a, xn, zn, nnew, d, nx0, nz0, nmu, nzs)
    if e5 != ok { ret e5 }
    let cap = n + nu_new
    let (x0t, e6) = mem.alloc[f64](a, cap * d)
    let (z0t, e7) = mem.alloc[f64](a, cap)
    let (mt, e8) = mem.alloc[f64](a, cap)
    let (dlt, e9) = mem.alloc[f64](a, cap)
    let (lamt, e10) = mem.alloc[f64](a, cap)
    let (zt, e11) = mem.alloc[f64](a, f.nn + nnew)
    let (ka, e12) = mem.alloc[f64](a, cap * cap)
    let (kb, e13) = mem.alloc[f64](a, cap * cap)
    let (ga, e14) = mem.alloc[f64](a, cap * cap)
    let (gb, e15) = mem.alloc[f64](a, cap * cap)
    let (kn, e16) = mem.alloc[f64](a, cap)
    let (gv, e17) = mem.alloc[f64](a, cap)
    let (kd, e18) = mem.alloc[f64](a, n)
    let (own, e19) = mem.alloc[f64](a, nu_new)
    let (off, e20) = mem.alloc[f64](a, nu_new)
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    if e11 != ok { ret e11 }
    if e12 != ok { ret e12 }
    if e13 != ok { ret e13 }
    if e14 != ok { ret e14 }
    if e15 != ok { ret e15 }
    if e16 != ok { ret e16 }
    if e17 != ok { ret e17 }
    if e18 != ok { ret e18 }
    if e19 != ok { ret e19 }
    if e20 != ok { ret e20 }
    var i = 0usize
    while i < n * d {
        x0t[i] = f.x0[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        z0t[i] = f.z0[i]
        mt[i] = f.mult[i]
        dlt[i] = f.dl[i]
        lamt[i] = f.lam[i]
        kd[i] = f.dl[i] - f.nmean
        i += 1usize
    }
    i = 0usize
    while i < n * n {
        ka[i] = f.ki[i]
        ga[i] = f.kgi[i]
        i += 1usize
    }
    // which old design each new unique design repeats (own = n when none) and where its values start in nzs
    var o = 0.0f64
    i = 0usize
    while i < nu_new {
        off[i] = o
        o += nmu[i]
        own[i] = f64(n)
        var u = 0usize
        while u < n {
            var same = true
            var c = 0usize
            while c < d {
                if nx0[i * d + c] != f.x0[u * d + c] { same = false }
                c += 1usize
            }
            if same { own[i] = f64(u) }
            u += 1usize
        }
        i += 1usize
    }
    var nt = n
    i = 0usize
    while i < nu_new {
        if own[i] >= f64(n) { nt += 1usize }
        i += 1usize
    }
    var s = n
    i = 0usize
    while i < nu_new {
        let nr = nmu[i]
        if own[i] < f64(n) {
            let id = usize(own[i])
            z0t[id] = (mt[id] * z0t[id] + nz0[i] * nr) / (mt[id] + nr)
            het_rep(ka, s, id, mt[id], nr, f.lam[id], gv)
            het_rep(ga, s, id, mt[id], nr, f.g, gv)
            mt[id] = mt[id] + nr
        }
        i += 1usize
    }
    i = 0usize
    while i < nu_new {
        let nr = nmu[i]
        if own[i] >= f64(n) {
            // Delta of the new design from the old noise predictor
            var mu = f.nmean
            var j = 0usize
            while j < n {
                var r = 0.0f64
                var q = 0usize
                while q < n {
                    r += f.kgi[j * n + q] * kd[q]
                    q += 1usize
                }
                mu += cov_pt(f.ctype, nx0, i, f.x0, j, d, f.thg) * r
                j += 1usize
            }
            let ln = math.exp[f64](mu)
            // main process
            j = 0usize
            while j < s {
                kn[j] = cov_pt(f.ctype, nx0, i, x0t, j, d, f.theta)
                j += 1usize
            }
            var qf = 0.0f64
            j = 0usize
            while j < s {
                var r = 0.0f64
                var q = 0usize
                while q < s {
                    r += ka[j * s + q] * kn[q]
                    q += 1usize
                }
                qf += kn[j] * r
                j += 1usize
            }
            het_border(ka, s, kn, 1.0f64 - qf + ln / nr + f.eps, kb, gv)
            // noise process
            j = 0usize
            while j < s {
                kn[j] = cov_pt(f.ctype, nx0, i, x0t, j, d, f.thg)
                j += 1usize
            }
            qf = 0.0f64
            j = 0usize
            while j < s {
                var r = 0.0f64
                var q = 0usize
                while q < s {
                    r += ga[j * s + q] * kn[q]
                    q += 1usize
                }
                qf += kn[j] * r
                j += 1usize
            }
            het_border(ga, s, kn, 1.0f64 - qf + f.g / nr / nr + f.eps, gb, gv)
            let t = s + 1usize
            j = 0usize
            while j < t * t {
                ka[j] = kb[j]
                ga[j] = gb[j]
                j += 1usize
            }
            var c = 0usize
            while c < d {
                x0t[s * d + c] = nx0[i * d + c]
                c += 1usize
            }
            z0t[s] = nz0[i]
            mt[s] = nr
            dlt[s] = mu
            lamt[s] = ln
            s += 1usize
        }
        i += 1usize
    }
    // observations grouped by design: old values then the replicates added to it, new designs last
    var pos = 0usize
    var op = 0usize
    var gi = 0usize
    while gi < n {
        let mo = usize(f.mult[gi])
        var r = 0usize
        while r < mo {
            zt[pos] = f.z[op + r]
            pos += 1usize
            r += 1usize
        }
        op += mo
        var q = 0usize
        while q < nu_new {
            if own[q] == f64(gi) {
                var r2 = 0usize
                while r2 < usize(nmu[q]) {
                    zt[pos] = nzs[usize(off[q]) + r2]
                    pos += 1usize
                    r2 += 1usize
                }
            }
            q += 1usize
        }
        gi += 1usize
    }
    var q2 = 0usize
    while q2 < nu_new {
        if own[q2] >= f64(n) {
            var r3 = 0usize
            while r3 < usize(nmu[q2]) {
                zt[pos] = nzs[usize(off[q2]) + r3]
                pos += 1usize
                r3 += 1usize
            }
        }
        q2 += 1usize
    }
    // rowSums and the sum of the new Kgi
    let (rs, e21) = mem.alloc[f64](a, nt)
    if e21 != ok { ret e21 }
    var sk = 0.0f64
    i = 0usize
    while i < nt {
        var r = 0.0f64
        var j = 0usize
        while j < nt {
            r += ga[i * nt + j]
            j += 1usize
        }
        rs[i] = r
        sk += r
        i += 1usize
    }
    *g = *f
    g.n = nt
    g.nn = f.nn + nnew
    g.x0 = x0t
    g.z0 = z0t
    g.z = zt
    g.mult = mt
    g.dl = dlt
    g.lam = lamt
    g.ki = ka
    g.kgi = ga
    g.rs = rs
    g.skgi = sk
    g.hv.n = nt
    g.hv.nn = g.nn
    g.hv.x0 = x0t
    g.hv.z0 = z0t
    g.hv.z = zt
    g.hv.mult = mt
    g.hv.ki = ka
    ret ok
}
