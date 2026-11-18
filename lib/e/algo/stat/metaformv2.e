// R metafor rma.mv, the second half (lib/e/algo/stat/metaformv.e is the first): everything the first leaves out except nlminb's iterates.
//
//   * the Hessian based variance-covariance matrix of the variance components, vvc, as rma.mv computes it for cvvc = TRUE (the natural scale), "transf" (the optimiser's scale) and "varcov" (the
//     covariances of a UN or GEN structure): numDeriv's Richardson hessian with r = 8 of the same .ll.rma.mv, the all-zero rows dropped, chol2inv of the rest;
//   * the structures UN and GEN (the Cholesky parametrisation, with the optimiser's start taken from the Cholesky factor of the initial G), CAR, SPEXP, SPGAU, SPLIN, SPRAT and SPSPH (the distance
//     matrix built from the coordinates of the inner variable, or given), GDIAG, together with CS HCS DIAG ID AR HAR;
//   * the second random term (~ inner2 | outer2, the H matrix with gamma2 and phi) with every structure;
//   * user weights A (the sandwich vb), the tests z, t, knha and adhoc, dfs residual, numeric and contain, a full V;
//   * sigma2, tau2, rho, gamma2 and phi fixed, as rma.mv's arguments (a fixed value is not estimated but its slot stays in optim's parameter vector, as in R);
//   * fit.stats: ll, dev, AIC, BIC and AICc for ML and REML, and parms.
//
// The optimisation is R's optim over sigma2s + tau2s + rhos + gamma2s + phis values (an absent term keeps one unused slot), Nelder-Mead (nmmin) or BFGS (vmmin, central differences, ndeps 1e-3),
// step for step. Not here: nlminb (the default optimiser; optimizer 2 is the tight BFGS stand-in the first half uses), UNR (metafor 5.2.1 does not accept it), PHY structures, R, vccon, sparse.
//
// The case: args =
//   [reml, test (0 z, 1 t, 2 knha, 3 adhoc), optimizer (0 Nelder-Mead, 1 BFGS, 2 tight BFGS), k, p, ns, gk, hk (structure codes, 0 none), vmode (0 vi, 1 full V), hasa, maxit (0 default),
//    cvvc (0 none, 1 natural scale, 2 transf, 3 varcov), dfs (0 residual, 1 numeric, 2 contain), dfsval, dist method G, dist method H (0 euclidean, 1 maximum, 2 manhattan, 3 the matrix itself),
//    y (k), X (k p, row-major), V (k or k k), A (k k, when hasa), ids (ns k), sigma2 fixed (max(ns, 1)),
//    then for the G term and then the H term when present: outer (k), the spatial structures' [ncoord, coordinates (k ncoord)] or (dist method 3) the k k matrix, the others' [nz, Z (k nz), values (nz)],
//    tau2 fixed (tau2s), rho fixed (rhos)]
// a fixed value stands where the argument was given, 99 where it is free. The structure codes: 1 CS, 2 HCS, 3 DIAG, 4 ID, 5 AR, 6 HAR, 7 UN, 8 CAR, 9 SPEXP, 10 SPGAU, 11 SPLIN, 12 SPRAT, 13 SPSPH,
// 14 GEN, 15 GDIAG.
// out: 0 sigma2 (8), 8 tau2 (8), 16 rho (8), 24 gamma2 (8), 32 phi (8), 40 beta, 48 se, 56 zval, 64 pval, 72 ci.lb, 80 ci.ub, 88 vb (4 x 4, row-major), 104 QE, 105 QEp, 106 QM, 107 QMp, 108 ll ML,
// 109 ll REML, 110 dev ML, 111 AIC ML, 112 BIC ML, 113 AICc ML, 114 dev REML, 115 AIC REML, 116 BIC REML, 117 AICc REML, 118 parms, 119 k, 120 p, 121 s2w, 122 QM df2, 123 evaluations, 124 the order
// of vvc, 125 vvc (row-major, up to 12 x 12), 270 ddf (4)

use e.math
use e.mem
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.math.scale as sc
use e.math.numderiv as nd
use e.algo.stat.rnm as nmd
use e.algo.stat.rbfgs as bf
use e.algo.stat.metaformv as m1

const K_CS: usize = 1usize
const K_HCS: usize = 2usize
const K_DIAG: usize = 3usize
const K_ID: usize = 4usize
const K_AR: usize = 5usize
const K_HAR: usize = 6usize
const K_UN: usize = 7usize
const K_CAR: usize = 8usize
const K_SPEXP: usize = 9usize
const K_SPGAU: usize = 10usize
const K_SPLIN: usize = 11usize
const K_SPRAT: usize = 12usize
const K_SPSPH: usize = 13usize
const K_GEN: usize = 14usize
const K_GDIAG: usize = 15usize

type Term = struct {
    kind: usize, on: bool, nz: usize, ntau: usize, nrho: usize, chol: bool, k: usize,
    z: []f64, outer: []f64, vals: []f64, d: []f64, vfix: []f64, rfix: []f64,
    e: []f64, ls: []f64, sp: []f64, tau: []f64, rho: []f64, tinit: []f64, rinit: []f64
}

type Mv2 = struct {
    a: *mem.Arena, k: usize, p: usize, ns: usize, sslots: usize, reml: bool, hasa: bool, bad: bool,
    y: []f64, x: []f64, v: []f64, aw: []f64, sid: []f64, sfix: []f64,
    g: Term, h: Term,
    m: []f64, w: []f64, l: []f64, aug: []f64, xtwx: []f64, sinv: []f64, paug: []f64, beta: []f64, vb: []f64, res: []f64, tmpv: []f64, ev: []f64, ax: []f64, bx: []f64, sig: []f64, gbuf: []f64, xm: []f64,
    llml: f64, llreml: f64, ldxx: f64, ldv: f64, rss: f64, qe: f64, step: f64, count: usize, hmode: usize
}

fn is_fixed(x: f64) -> bool { ret x < 98.0f64 }

fn nan2() -> f64 { ret 0.0f64 / 0.0f64 }

fn al(c: *Mv2, n: usize) -> []f64 {
    let (s, e) = mem.alloc[f64](c.a, n + 1usize)
    if e != ok { c.bad = true }
    var i = 0usize
    if e == ok {
        while i < n {
            s[i] = 0.0f64
            i += 1usize
        }
    }
    ret s
}

fn is_sp(kind: usize) -> bool { ret kind >= K_SPEXP && kind <= K_SPSPH }

fn is_chol(kind: usize) -> bool { ret kind == K_UN || kind == K_GEN }

fn ntau_of2(kind: usize, nz: usize) -> usize {
    if kind == K_CS || kind == K_ID || kind == K_AR || kind == K_CAR || is_sp(kind) { ret 1usize }
    ret nz
}

fn nrho_of2(kind: usize, nz: usize) -> usize {
    if is_chol(kind) && nz > 1usize { ret nz * (nz - 1usize) / 2usize }
    ret 1usize
}

fn plogis(x: f64) -> f64 { ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - x)) }

fn absf(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

// the strict lower triangle of an n by n matrix in column-major order: the position of (i, j), i > j
fn lower_pos(n: usize, i: usize, j: usize) -> usize {
    var s = 0usize
    var c = 0usize
    while c < j {
        s += n - 1usize - c
        c += 1usize
    }
    ret s + (i - j - 1usize)
}

// the E matrix (and the per-term variance and correlation vectors) of a term for the parameters pv (variances) and pr (correlations)
fn term_eval(t: *Term, pv: []const f64, pr: []const f64, transf: bool, chol: bool, vccov: bool) {
    let n = t.nz
    let kd = t.kind
    var j = 0usize
    if chol {
        var i = 0usize
        while i < n * n {
            t.ls[i] = 0.0f64
            i += 1usize
        }
        j = 0usize
        while j < n {
            t.ls[j * n + j] = pv[j]
            j += 1usize
        }
        j = 0usize
        while j < n {
            i = j + 1usize
            while i < n {
                t.ls[i * n + j] = pr[lower_pos(n, i, j)]
                i += 1usize
            }
            j += 1usize
        }
        i = 0usize
        while i < n {
            j = 0usize
            while j < n {
                var s = 0.0f64
                var q = 0usize
                while q < n {
                    s += t.ls[i * n + q] * t.ls[j * n + q]
                    q += 1usize
                }
                t.e[i * n + j] = s
                j += 1usize
            }
            i += 1usize
        }
        j = 0usize
        while j < n {
            t.tau[j] = t.e[j * n + j]
            j += 1usize
        }
        j = 0usize
        while j < n {
            i = j + 1usize
            while i < n {
                let isi = 1.0f64 / math.sqrt[f64](t.e[i * n + i])
                let isj = 1.0f64 / math.sqrt[f64](t.e[j * n + j])
                t.rho[lower_pos(n, i, j)] = (isi * t.e[i * n + j]) * isj
                i += 1usize
            }
            j += 1usize
        }
        j = 0usize
        while j < t.ntau {
            if is_fixed(t.vfix[j]) { t.tau[j] = t.vfix[j] }
            j += 1usize
        }
        j = 0usize
        while j < t.nrho {
            if is_fixed(t.rfix[j]) { t.rho[j] = t.rfix[j] }
            j += 1usize
        }
    } else {
        j = 0usize
        while j < t.ntau {
            var v = 0.0f64
            if is_fixed(t.vfix[j]) {
                v = t.vfix[j]
            } else {
                if transf { v = math.exp[f64](pv[j]) } else { v = pv[j] }
            }
            if !transf && v < 0.0f64 { v = 0.0f64 }
            t.tau[j] = v
            j += 1usize
        }
        j = 0usize
        while j < t.nrho {
            var r = 0.0f64
            if is_fixed(t.rfix[j]) {
                r = t.rfix[j]
            } else {
                if transf {
                    if kd == K_CAR {
                        r = plogis(pr[j])
                    } else {
                        if is_sp(kd) { r = math.exp[f64](pr[j]) } else { r = sc.tanh(pr[j]) }
                    }
                } else {
                    r = pr[j]
                }
            }
            if !transf {
                if kd == K_CAR {
                    if r < 0.0f64 { r = 0.0f64 }
                    if r > 1.0f64 { r = 1.0f64 }
                } else {
                    if is_sp(kd) {
                        if r < 0.0f64 { r = 0.0f64 }
                    } else {
                        if !vccov {
                            if r < -1.0f64 { r = -1.0f64 }
                            if r > 1.0f64 { r = 1.0f64 }
                        }
                    }
                }
            }
            t.rho[j] = r
            j += 1usize
        }
        j = 0usize
        while j < t.ntau {
            if t.tau[j] <= m1.eps10() { t.tau[j] = 0.0f64 }
            j += 1usize
        }
    }
    if is_sp(kd) { ret }
    var i = 0usize
    while i < n {
        j = 0usize
        while j < n {
            var v = 0.0f64
            var vi = 0.0f64
            var vj = 0.0f64
            if t.ntau == n {
                vi = math.sqrt[f64](t.tau[i])
                vj = math.sqrt[f64](t.tau[j])
            } else {
                vi = math.sqrt[f64](t.tau[0usize])
                vj = vi
            }
            if kd == K_CS {
                if i == j { v = t.tau[0usize] } else { v = t.rho[0usize] * t.tau[0usize] }
            }
            if kd == K_HCS {
                if i == j { v = t.tau[i] } else { v = (vi * t.rho[0usize]) * vj }
            }
            if kd == K_DIAG || kd == K_GDIAG {
                if i == j { v = t.tau[i] }
            }
            if kd == K_ID {
                if i == j { v = t.tau[0usize] }
            }
            if kd == K_UN || kd == K_GEN {
                if i == j {
                    v = t.tau[i]
                } else {
                    var cr = 0.0f64
                    if i > j { cr = t.rho[lower_pos(n, i, j)] } else { cr = t.rho[lower_pos(n, j, i)] }
                    if vccov { v = cr } else { v = (vi * cr) * vj }
                }
            }
            if kd == K_AR || kd == K_HAR || kd == K_CAR {
                var dd = 0.0f64
                if kd == K_CAR { dd = absf(t.vals[i] - t.vals[j]) } else { dd = f64(if_absdiff(i, j)) }
                let r = math.pow[f64](t.rho[0usize], dd)
                if i == j {
                    v = t.tau[i_or0(kd, i)]
                } else {
                    v = (vi * r) * vj
                }
            }
            t.e[i * n + j] = v
            j += 1usize
        }
        i += 1usize
    }
}

fn if_absdiff(a: usize, b: usize) -> usize {
    if a > b { ret a - b }
    ret b - a
}

fn i_or0(kd: usize, i: usize) -> usize {
    if kd == K_HAR { ret i }
    ret 0usize
}

// the spatial matrix of a term: v f(D / r) where the outer variable agrees
fn sp_eval(t: *Term) {
    let k = t.k
    let v = t.tau[0usize]
    let r = t.rho[0usize]
    var i = 0usize
    while i < k {
        var q = 0usize
        while q < k {
            var s = 0.0f64
            if t.outer[i] == t.outer[q] {
                let dd = t.d[i * k + q]
                var f = 0.0f64
                if t.kind == K_SPEXP { f = math.exp[f64](0.0f64 - dd / r) }
                if t.kind == K_SPGAU { f = math.exp[f64](0.0f64 - (dd * dd) / (r * r)) }
                if t.kind == K_SPLIN {
                    if dd < r { f = 1.0f64 - dd / r }
                }
                if t.kind == K_SPRAT {
                    let u = (dd / r) * (dd / r)
                    f = 1.0f64 - u / (1.0f64 + u)
                }
                if t.kind == K_SPSPH {
                    if dd < r { f = 1.0f64 - 1.5f64 * dd / r + 0.5f64 * (dd / r) * (dd / r) * (dd / r) }
                }
                s = v * f
            }
            t.sp[i * k + q] = s
            q += 1usize
        }
        i += 1usize
    }
}

// M += (Z E Z') * (same outer)
fn add_term(c: *Mv2, t: *Term) {
    let k = c.k
    var i = 0usize
    if is_sp(t.kind) {
        while i < k * k {
            c.m[i] += t.sp[i]
            i += 1usize
        }
        ret
    }
    let n = t.nz
    while i < k {
        var q = 0usize
        while q < k {
            if t.outer[i] == t.outer[q] {
                var s = 0.0f64
                var a1 = 0usize
                while a1 < n {
                    let zi = t.z[i * n + a1]
                    if zi != 0.0f64 {
                        var b1 = 0usize
                        while b1 < n {
                            s += zi * t.e[a1 * n + b1] * t.z[q * n + b1]
                            b1 += 1usize
                        }
                    }
                    a1 += 1usize
                }
                c.m[i * k + q] += s
            }
            q += 1usize
        }
        i += 1usize
    }
}

fn slot_t2(c: *Mv2) -> usize {
    if c.g.on { ret c.g.ntau }
    ret 1usize
}

fn slot_r2(c: *Mv2) -> usize {
    if c.g.on { ret c.g.nrho }
    ret 1usize
}

fn slot_g2(c: *Mv2) -> usize {
    if c.h.on { ret c.h.ntau }
    ret 1usize
}

fn slot_p2(c: *Mv2) -> usize {
    if c.h.on { ret c.h.nrho }
    ret 1usize
}

fn nslots(c: *Mv2) -> usize { ret c.sslots + slot_t2(c) + slot_r2(c) + slot_g2(c) + slot_p2(c) }

// M for the parameters par: mode 0 the optimiser's scale (log variances, tanh correlations, the Cholesky factors of UN and GEN), 2 the natural scale, 3 the natural scale with covariances
fn build_m(c: *Mv2, par: []const f64, mode: usize) {
    let k = c.k
    let transf = mode == 0usize
    let vccov = mode == 3usize
    var i = 0usize
    while i < k * k {
        c.m[i] = c.v[i]
        i += 1usize
    }
    var j = 0usize
    while j < c.ns {
        var s2 = 0.0f64
        if is_fixed(c.sfix[j]) {
            s2 = c.sfix[j]
        } else {
            if transf { s2 = math.exp[f64](par[j]) } else { s2 = par[j] }
        }
        if !transf && s2 < 0.0f64 { s2 = 0.0f64 }
        if s2 <= m1.eps10() { s2 = 0.0f64 }
        c.sig[j] = s2
        i = 0usize
        while i < k {
            var q = 0usize
            while q < k {
                if c.sid[j * k + i] == c.sid[j * k + q] { c.m[i * k + q] += s2 }
                q += 1usize
            }
            i += 1usize
        }
        j += 1usize
    }
    let ot = c.sslots
    let orr = ot + slot_t2(c)
    let og = orr + slot_r2(c)
    let op = og + slot_g2(c)
    if c.g.on {
        term_eval(&c.g, par[ot..orr], par[orr..og], transf, transf && c.g.chol, vccov)
        if is_sp(c.g.kind) { sp_eval(&c.g) }
        add_term(c, &c.g)
    }
    if c.h.on {
        term_eval(&c.h, par[og..op], par[op..op + slot_p2(c)], transf, transf && c.h.chol, vccov)
        if is_sp(c.h.kind) { sp_eval(&c.h) }
        add_term(c, &c.h)
    }
}

// R's .ll.rma.mv: -1 times the log-likelihood chosen by reml; with dofit the fitted beta (with the user weights when given), vb, RSS and both log-likelihoods
fn mv_ll(c: *Mv2, par: []const f64, mode: usize, dofit: bool) -> f64 {
    let k = c.k
    let p = c.p
    build_m(c, par, mode)
    if !m1.chol_of(c.m, k, c.l) {
        c.llml = 0.0f64 - 1.0f64 / 0.0f64
        c.llreml = c.llml
        ret 1.0f64 / 0.0f64
    }
    let ldm = m1.chol_inv(c.l, k, c.w, c.aug)
    var a1 = 0usize
    while a1 < p {
        var b1 = 0usize
        while b1 < p {
            var s = 0.0f64
            var i = 0usize
            while i < k {
                var q = 0usize
                while q < k {
                    s += c.x[i * p + a1] * c.w[i * k + q] * c.x[q * p + b1]
                    q += 1usize
                }
                i += 1usize
            }
            c.xtwx[a1 * p + b1] = s
            b1 += 1usize
        }
        a1 += 1usize
    }
    if !m1.chol_of(c.xtwx, p, c.paug) {
        c.llml = 0.0f64 - 1.0f64 / 0.0f64
        c.llreml = c.llml
        ret 1.0f64 / 0.0f64
    }
    let ldxwx = m1.chol_inv(c.paug, p, c.sinv, c.ev)
    if dofit && c.hasa {
        // beta = (X'AX)^-1 X'A y, vb = (X'AX)^-1 X'A M A X (X'AX)^-1
        a1 = 0usize
        while a1 < k {
            var b1 = 0usize
            while b1 < p {
                var s = 0.0f64
                var q = 0usize
                while q < k {
                    s += c.aw[a1 * k + q] * c.x[q * p + b1]
                    q += 1usize
                }
                c.ax[a1 * p + b1] = s
                b1 += 1usize
            }
            a1 += 1usize
        }
        a1 = 0usize
        while a1 < p {
            var b1 = 0usize
            while b1 < p {
                var s = 0.0f64
                var i = 0usize
                while i < k {
                    s += c.x[i * p + a1] * c.ax[i * p + b1]
                    i += 1usize
                }
                c.xtwx[a1 * p + b1] = s
                b1 += 1usize
            }
            a1 += 1usize
        }
        if !m1.chol_of(c.xtwx, p, c.paug) { ret 1.0f64 / 0.0f64 }
        let _ = m1.chol_inv(c.paug, p, c.xm, c.ev)
        // tmpv = X'A y
        a1 = 0usize
        while a1 < p {
            var s = 0.0f64
            var i = 0usize
            while i < k {
                var q = 0usize
                while q < k {
                    s += c.x[i * p + a1] * c.aw[i * k + q] * c.y[q]
                    q += 1usize
                }
                i += 1usize
            }
            c.tmpv[a1] = s
            a1 += 1usize
        }
        a1 = 0usize
        while a1 < p {
            var s = 0.0f64
            var b1 = 0usize
            while b1 < p {
                s += c.xm[a1 * p + b1] * c.tmpv[b1]
                b1 += 1usize
            }
            c.beta[a1] = s
            a1 += 1usize
        }
        // bx = M (A X)
        var i = 0usize
        while i < k {
            var b1 = 0usize
            while b1 < p {
                var s = 0.0f64
                var q = 0usize
                while q < k {
                    s += c.m[i * k + q] * c.ax[q * p + b1]
                    q += 1usize
                }
                c.bx[i * p + b1] = s
                b1 += 1usize
            }
            i += 1usize
        }
        // tmp = (AX)' bx
        a1 = 0usize
        while a1 < p {
            var b1 = 0usize
            while b1 < p {
                var s = 0.0f64
                i = 0usize
                while i < k {
                    s += c.ax[i * p + a1] * c.bx[i * p + b1]
                    i += 1usize
                }
                c.xtwx[a1 * p + b1] = s
                b1 += 1usize
            }
            a1 += 1usize
        }
        // vb = xm tmp xm
        a1 = 0usize
        while a1 < p {
            var b1 = 0usize
            while b1 < p {
                var s = 0.0f64
                var q = 0usize
                while q < p {
                    var t2 = 0.0f64
                    var r2 = 0usize
                    while r2 < p {
                        t2 += c.xtwx[q * p + r2] * c.xm[r2 * p + b1]
                        r2 += 1usize
                    }
                    s += c.xm[a1 * p + q] * t2
                    q += 1usize
                }
                c.vb[a1 * p + b1] = s
                b1 += 1usize
            }
            a1 += 1usize
        }
    } else {
        a1 = 0usize
        while a1 < p {
            var s = 0.0f64
            var i = 0usize
            while i < k {
                var q = 0usize
                while q < k {
                    s += c.x[i * p + a1] * c.w[i * k + q] * c.y[q]
                    q += 1usize
                }
                i += 1usize
            }
            c.tmpv[a1] = s
            a1 += 1usize
        }
        a1 = 0usize
        while a1 < p {
            var s = 0.0f64
            var b1 = 0usize
            while b1 < p {
                s += c.sinv[a1 * p + b1] * c.tmpv[b1]
                c.vb[a1 * p + b1] = c.sinv[a1 * p + b1]
                b1 += 1usize
            }
            c.beta[a1] = s
            a1 += 1usize
        }
    }
    var i = 0usize
    while i < k {
        var f = 0.0f64
        a1 = 0usize
        while a1 < p {
            f += c.x[i * p + a1] * c.beta[a1]
            a1 += 1usize
        }
        c.res[i] = c.y[i] - f
        i += 1usize
    }
    var rss = 0.0f64
    i = 0usize
    while i < k {
        var q = 0usize
        while q < k {
            rss += c.res[i] * c.w[i * k + q] * c.res[q]
            q += 1usize
        }
        i += 1usize
    }
    c.rss = rss
    let kf = f64(k)
    let pf = f64(p)
    let pi2 = 2.0f64 * 3.141592653589793f64
    c.llml = 0.0f64 - 0.5f64 * kf * math.log[f64](pi2) - 0.5f64 * ldm - 0.5f64 * rss
    c.llreml = 0.0f64 - 0.5f64 * (kf - pf) * math.log[f64](pi2) + 0.5f64 * c.ldxx - 0.5f64 * ldm - 0.5f64 * ldxwx - 0.5f64 * rss
    c.count += 1usize
    if c.reml { ret 0.0f64 - c.llreml }
    ret 0.0f64 - c.llml
}

fn mv_f2(c: *Mv2, par: []const f64) -> f64 { ret mv_ll(c, par, 0usize, false) }

fn mv_g2(c: *Mv2, par: []const f64, g: []f64) {
    let n = par.len
    var i = 0usize
    while i < n {
        let hold = par[i]
        var j = 0usize
        while j < n {
            c.gbuf[j] = par[j]
            j += 1usize
        }
        c.gbuf[i] = hold + c.step
        let v1 = mv_ll(c, c.gbuf, 0usize, false)
        c.gbuf[i] = hold - c.step
        let v2 = mv_ll(c, c.gbuf, 0usize, false)
        g[i] = (v1 - v2) / (2.0f64 * c.step)
        i += 1usize
    }
}

fn hess_f(c: *Mv2, x: []const f64, out: []f64) { out[0usize] = mv_ll(c, x, c.hmode, false) }

// quantile type 7 of the sorted-in-place x
fn quant7(x: []f64, n: usize, pr: f64) -> f64 {
    var i = 1usize
    while i < n {
        let key = x[i]
        var j = i
        while j > 0usize && x[j - 1usize] > key {
            x[j] = x[j - 1usize]
            j -= 1usize
        }
        x[j] = key
        i += 1usize
    }
    let index = f64(n - 1usize) * pr
    let lo = usize(math.floor[f64](index))
    var hi = lo
    if f64(lo) < index { hi = lo + 1usize }
    let h = index - f64(lo)
    if h > 0.0f64 && x[hi] != x[lo] { ret (1.0f64 - h) * x[lo] + h * x[hi] }
    ret x[lo]
}

// the start of the parameters of a term at slot offsets: log variances, the correlation starts, the Cholesky factor of the initial G for UN and GEN
fn term_init(c: *Mv2, t: *Term, init: f64, par: []f64) {
    let ntau = t.ntau
    let nrho = t.nrho
    let n = t.nz
    if t.chol {
        let sv = math.sqrt[f64](init)
        var i = 0usize
        while i < n {
            var j = 0usize
            while j < n {
                if i == j { t.e[i * n + j] = init } else { t.e[i * n + j] = (sv * 0.5f64) * sv }
                j += 1usize
            }
            i += 1usize
        }
        if !m1.chol_of(t.e, n, t.ls) { c.bad = true }
        i = 0usize
        while i < n {
            par[i] = t.ls[i * n + i]
            i += 1usize
        }
        var j = 0usize
        while j < nrho {
            par[ntau + j] = 0.0f64
            j += 1usize
        }
        j = 0usize
        while j < n {
            i = j + 1usize
            while i < n {
                par[ntau + lower_pos(n, i, j)] = t.ls[i * n + j]
                i += 1usize
            }
            j += 1usize
        }
        ret
    }
    var j = 0usize
    while j < ntau {
        par[j] = math.log[f64](init)
        j += 1usize
    }
    var r0 = sc.atanh(0.5f64)
    if t.kind == K_CAR { r0 = 0.0f64 }
    if is_sp(t.kind) {
        let k = c.k
        let (q, e1) = mem.alloc[f64](c.a, k * k)
        if e1 != ok {
            c.bad = true
            ret
        }
        var cnt = 0usize
        var i = 0usize
        while i < k {
            j = 0usize
            while j < i {
                q[cnt] = t.d[i * k + j]
                cnt += 1usize
                j += 1usize
            }
            i += 1usize
        }
        r0 = math.log[f64](quant7(q, cnt, 0.25f64))
    }
    j = 0usize
    while j < nrho {
        par[ntau + j] = r0
        j += 1usize
    }
}

// the total R starts the variances from; also the QE of V alone and log |V|
fn start_total2(c: *Mv2, ncomp: usize) -> f64 {
    let k = c.k
    let p = c.p
    let kf = f64(k)
    if !m1.chol_of(c.v, k, c.l) { ret nan2() }
    c.ldv = m1.chol_inv(c.l, k, c.w, c.aug)
    var a1 = 0usize
    while a1 < p {
        var b1 = 0usize
        while b1 < p {
            var s = 0.0f64
            var i = 0usize
            while i < k {
                var q = 0usize
                while q < k {
                    s += c.x[i * p + a1] * c.w[i * k + q] * c.x[q * p + b1]
                    q += 1usize
                }
                i += 1usize
            }
            c.xtwx[a1 * p + b1] = s
            b1 += 1usize
        }
        a1 += 1usize
    }
    if !m1.chol_of(c.xtwx, p, c.paug) { ret nan2() }
    let _ = m1.chol_inv(c.paug, p, c.sinv, c.ev)
    a1 = 0usize
    while a1 < p {
        var s = 0.0f64
        var i = 0usize
        while i < k {
            var q = 0usize
            while q < k {
                s += c.x[i * p + a1] * c.w[i * k + q] * c.y[q]
                q += 1usize
            }
            i += 1usize
        }
        c.tmpv[a1] = s
        a1 += 1usize
    }
    var i = 0usize
    var mean = 0.0f64
    while i < k {
        var f = 0.0f64
        a1 = 0usize
        while a1 < p {
            var s = 0.0f64
            var b1 = 0usize
            while b1 < p {
                s += c.sinv[a1 * p + b1] * c.tmpv[b1]
                b1 += 1usize
            }
            f += c.x[i * p + a1] * s
            a1 += 1usize
        }
        c.res[i] = c.y[i] - f
        mean += c.res[i]
        i += 1usize
    }
    mean = mean / kf
    var vr = 0.0f64
    var mi = 0.0f64
    var qe = 0.0f64
    i = 0usize
    while i < k {
        vr += (c.res[i] - mean) * (c.res[i] - mean)
        mi += 1.0f64 / c.v[i * k + i]
        var q = 0usize
        while q < k {
            qe += c.res[i] * c.w[i * k + q] * c.res[q]
            q += 1usize
        }
        i += 1usize
    }
    c.qe = qe
    vr = vr / (kf - 1.0f64)
    mi = mi / kf
    var tot = vr - 1.0f64 / mi
    let lo = 0.001f64 * f64(ncomp)
    if tot < lo { tot = lo }
    ret tot
}

// fixed parameters: true when nothing is left for the optimiser
fn any_free(c: *Mv2) -> bool {
    var j = 0usize
    while j < c.ns {
        if !is_fixed(c.sfix[j]) { ret true }
        j += 1usize
    }
    if c.g.on {
        j = 0usize
        while j < c.g.ntau {
            if !is_fixed(c.g.vfix[j]) { ret true }
            j += 1usize
        }
        j = 0usize
        while j < c.g.nrho {
            if !is_fixed(c.g.rfix[j]) { ret true }
            j += 1usize
        }
    }
    if c.h.on {
        j = 0usize
        while j < c.h.ntau {
            if !is_fixed(c.h.vfix[j]) { ret true }
            j += 1usize
        }
        j = 0usize
        while j < c.h.nrho {
            if !is_fixed(c.h.rfix[j]) { ret true }
            j += 1usize
        }
    }
    ret false
}

fn free_count(c: *Mv2) -> usize {
    var n = 0usize
    var j = 0usize
    while j < c.ns {
        if !is_fixed(c.sfix[j]) { n += 1usize }
        j += 1usize
    }
    if c.g.on {
        j = 0usize
        while j < c.g.ntau {
            if !is_fixed(c.g.vfix[j]) { n += 1usize }
            j += 1usize
        }
        j = 0usize
        while j < c.g.nrho {
            if !is_fixed(c.g.rfix[j]) { n += 1usize }
            j += 1usize
        }
    }
    if c.h.on {
        j = 0usize
        while j < c.h.ntau {
            if !is_fixed(c.h.vfix[j]) { n += 1usize }
            j += 1usize
        }
        j = 0usize
        while j < c.h.nrho {
            if !is_fixed(c.h.rfix[j]) { n += 1usize }
            j += 1usize
        }
    }
    ret n
}

// the identity of the row i in a factor: the first row with the same key (Z row or coordinates row)
fn row_key(z: []const f64, w: usize, outer: []const f64, i: usize) -> usize {
    var q = 0usize
    while q < i {
        var same = outer[q] == outer[i]
        var j = 0usize
        while j < w {
            if z[q * w + j] != z[i * w + j] { same = false }
            j += 1usize
        }
        if same { ret q }
        q += 1usize
    }
    ret i
}

// the number of distinct values of the codes (codes are first-row identities, so the distinct ones are the rows that are their own code)
fn n_distinct(code: []const f64, k: usize) -> usize {
    var n = 0usize
    var i = 0usize
    while i < k {
        if usize(code[i]) == i { n += 1usize }
        i += 1usize
    }
    ret n
}

fn codes_of(ids: []const f64, k: usize, out: []f64) {
    var i = 0usize
    while i < k {
        var f = i
        var q = 0usize
        var found = false
        while q < i && !found {
            if ids[q] == ids[i] {
                f = q
                found = true
            }
            q += 1usize
        }
        out[i] = f64(f)
        i += 1usize
    }
}

// R's .ddf.calc(dfs = "contain") for the column j of X given the factors (each one a vector of codes) and their level counts, k when none applies
fn contain_ddf(c: *Mv2, j: usize, codes: []const f64, nf: usize, nlev: []const f64) -> f64 {
    let k = c.k
    let p = c.p
    var best = f64(k)
    var f = 0usize
    while f < nf {
        // every level of the factor carries one value of X[, j]
        var ok1 = true
        var i = 0usize
        while i < k {
            var q = 0usize
            while q < i {
                if codes[f * k + q] == codes[f * k + i] && c.x[q * p + j] != c.x[i * p + j] { ok1 = false }
                q += 1usize
            }
            i += 1usize
        }
        if ok1 && nlev[f] < best { best = nlev[f] }
        f += 1usize
    }
    ret best
}

// out: the Hessian based vvc (row-major) into out at 125 with its order at 124
fn compute_vvc(c: *Mv2, cvvc: usize, par: []const f64, out: []f64) {
    let np = nslots(c)
    let a = c.a
    let ot = c.sslots
    let orr = ot + slot_t2(c)
    let og = orr + slot_r2(c)
    let op = og + slot_g2(c)
    let (x, e1) = mem.alloc[f64](a, np)
    if e1 != ok { ret }
    var i = 0usize
    if cvvc == 2usize {
        c.hmode = 0usize
        i = 0usize
        while i < np {
            x[i] = par[i]
            i += 1usize
        }
    } else {
        i = 0usize
        while i < np {
            x[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < c.ns {
            x[i] = c.sig[i]
            i += 1usize
        }
        if c.g.on {
            i = 0usize
            while i < c.g.ntau {
                x[ot + i] = c.g.tau[i]
                i += 1usize
            }
            if cvvc == 3usize {
                // covariances: the strict lower triangle of G in column-major order
                let n = c.g.nz
                var jj = 0usize
                while jj < n {
                    var ii = jj + 1usize
                    while ii < n {
                        x[orr + lower_pos(n, ii, jj)] = c.g.e[ii * n + jj]
                        ii += 1usize
                    }
                    jj += 1usize
                }
            } else {
                i = 0usize
                while i < c.g.nrho {
                    x[orr + i] = c.g.rho[i]
                    i += 1usize
                }
            }
        }
        if c.h.on {
            i = 0usize
            while i < c.h.ntau {
                x[og + i] = c.h.tau[i]
                i += 1usize
            }
            if cvvc == 3usize {
                let n = c.h.nz
                var jj = 0usize
                while jj < n {
                    var ii = jj + 1usize
                    while ii < n {
                        x[op + lower_pos(n, ii, jj)] = c.h.e[ii * n + jj]
                        ii += 1usize
                    }
                    jj += 1usize
                }
            } else {
                i = 0usize
                while i < c.h.nrho {
                    x[op + i] = c.h.rho[i]
                    i += 1usize
                }
            }
        }
        c.hmode = 2usize
        if cvvc == 3usize { c.hmode = 3usize }
    }
    var o = nd.hessian_defaults()
    o.r = 8usize
    let (hm, he) = nd.hessian_richardson[Mv2](a, c, hess_f, x, &o)
    if he != ok { ret }
    // the slots kept: the terms present, in R's order
    let (keep, e2) = mem.alloc[usize](a, np)
    if e2 != ok { ret }
    var nk = 0usize
    let withs = c.ns > 0usize
    let withg = c.g.on
    let withh = c.h.on
    i = 0usize
    while i < np {
        var inc = true
        if !withs && i < c.sslots { inc = false }
        if !withg && i >= ot && i < og { inc = false }
        if !withh && i >= og { inc = false }
        if inc {
            keep[nk] = i
            nk += 1usize
        }
        i += 1usize
    }
    if nk == 0usize { ret }
    if cvvc == 3usize && withg {
        // reorder: sigma2s, then G as the lower triangle (diagonal and covariance interleaved, column-major), then H likewise
        let (ord, e3) = mem.alloc[usize](a, np)
        if e3 != ok { ret }
        var no = 0usize
        i = 0usize
        while i < c.ns {
            ord[no] = i
            no += 1usize
            i += 1usize
        }
        var jj = 0usize
        let n = c.g.nz
        while jj < n {
            var ii = jj
            while ii < n {
                if ii == jj { ord[no] = ot + jj } else { ord[no] = orr + lower_pos(n, ii, jj) }
                no += 1usize
                ii += 1usize
            }
            jj += 1usize
        }
        if withh {
            let n2 = c.h.nz
            jj = 0usize
            while jj < n2 {
                var ii = jj
                while ii < n2 {
                    if ii == jj { ord[no] = og + jj } else { ord[no] = op + lower_pos(n2, ii, jj) }
                    no += 1usize
                    ii += 1usize
                }
                jj += 1usize
            }
        }
        i = 0usize
        while i < no {
            keep[i] = ord[i]
            i += 1usize
        }
        nk = no
    }
    // drop the rows that are all zero (hesstol)
    let tol = 1.4901161193847656e-08f64
    let (sel, e4) = mem.alloc[usize](a, nk)
    if e4 != ok { ret }
    var ns2 = 0usize
    i = 0usize
    while i < nk {
        var allz = true
        var j = 0usize
        while j < nk {
            if absf(hm[keep[i] * np + keep[j]]) > tol { allz = false }
            j += 1usize
        }
        if !allz {
            sel[ns2] = keep[i]
            ns2 += 1usize
        }
        i += 1usize
    }
    if ns2 == 0usize { ret }
    let (sub, e5) = mem.alloc[f64](a, ns2 * ns2)
    let (lf, e6) = mem.alloc[f64](a, ns2 * ns2)
    let (inv, e7) = mem.alloc[f64](a, ns2 * ns2)
    let (tmp, e8) = mem.alloc[f64](a, ns2 * ns2)
    if e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret }
    i = 0usize
    while i < ns2 {
        var j = 0usize
        while j < ns2 {
            sub[i * ns2 + j] = hm[sel[i] * np + sel[j]]
            j += 1usize
        }
        i += 1usize
    }
    out[124usize] = f64(ns2)
    if !m1.chol_of(sub, ns2, lf) { ret }
    let _ = m1.chol_inv(lf, ns2, inv, tmp)
    i = 0usize
    while i < ns2 * ns2 {
        if i < 144usize { out[125usize + i] = inv[i] }
        i += 1usize
    }
}

fn fit_mv2(c: *Mv2, optimizer: usize, maxit: usize, test: usize, cvvc: usize, dfsmode: usize, dfsval: f64, out: []f64) {
    let a = c.a
    let k = c.k
    let p = c.p
    var i = 0usize
    while i < out.len {
        out[i] = nan2()
        i += 1usize
    }
    let np = nslots(c)
    var s2s = c.ns
    if s2s == 0usize { s2s = 1usize }
    let tau2s = slot_t2(c)
    let gam2s = slot_g2(c)
    let ncomp = s2s + tau2s + gam2s
    let total = start_total2(c, ncomp)
    if total != total { ret }
    let init = total / f64(ncomp)
    let (par, e1) = mem.alloc[f64](a, np)
    if e1 != ok { ret }
    i = 0usize
    while i < np {
        par[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < c.ns {
        par[i] = math.log[f64](init)
        i += 1usize
    }
    let ot = c.sslots
    let orr = ot + slot_t2(c)
    let og = orr + slot_r2(c)
    let op = og + slot_g2(c)
    if c.g.on { term_init(c, &c.g, init, par[ot..og]) }
    if c.h.on { term_init(c, &c.h, init, par[og..np]) }
    if c.bad { ret }
    c.count = 0usize
    c.step = 0.001f64
    if any_free(c) {
        if optimizer == 0usize {
            var mx = 500usize
            if maxit > 0usize { mx = maxit }
            let (best, e2) = mem.alloc[f64](a, np)
            if e2 != ok { ret }
            let (fm, fc, fail) = nmd.nmmin[Mv2](a, c, mv_f2, par, 0.0f64 - 1.0f64 / 0.0f64, 1.490116119384766e-08f64, 1.0f64, 0.5f64, 2.0f64, mx, 1.0f64, best)
            let _ = fm
            let _ = fc
            if fail != 0usize { ret }
            i = 0usize
            while i < np {
                par[i] = best[i]
                i += 1usize
            }
        } else {
            if optimizer == 2usize { c.step = 1.0e-7f64 }
            var rt = 1.490116119384766e-08f64
            var mx = 100usize
            if maxit > 0usize { mx = maxit }
            if optimizer == 2usize {
                rt = 1.0e-15f64
                mx = 2000usize
            }
            let _ = bf.vmmin[Mv2](a, c, mv_f2, mv_g2, par, rt, mx)
        }
    }
    let nfn = c.count
    let _ = mv_ll(c, par, 0usize, true)
    if c.llml == 0.0f64 - 1.0f64 / 0.0f64 { ret }
    i = 0usize
    while i < c.ns {
        out[i] = c.sig[i]
        i += 1usize
    }
    if c.g.on {
        i = 0usize
        while i < c.g.ntau {
            out[8usize + i] = c.g.tau[i]
            i += 1usize
        }
        i = 0usize
        while i < c.g.nrho {
            out[16usize + i] = c.g.rho[i]
            i += 1usize
        }
    }
    if c.h.on {
        i = 0usize
        while i < c.h.ntau {
            out[24usize + i] = c.h.tau[i]
            i += 1usize
        }
        i = 0usize
        while i < c.h.nrho {
            out[32usize + i] = c.h.rho[i]
            i += 1usize
        }
    }
    // the tests
    var s2w = 1.0f64
    if test >= 2usize {
        if c.rss <= 2.220446049250313e-16f64 { s2w = 0.0f64 } else { s2w = c.rss / f64(k - p) }
    }
    if test == 3usize {
        if s2w < 1.0f64 { s2w = 1.0f64 }
    }
    var a2 = 0usize
    while a2 < p {
        var b2 = 0usize
        while b2 < p {
            c.vb[a2 * p + b2] = s2w * c.vb[a2 * p + b2]
            b2 += 1usize
        }
        a2 += 1usize
    }
    // ddf
    let (ddf, e3) = mem.alloc[f64](a, p + 1usize)
    if e3 != ok { ret }
    if test >= 1usize {
        if dfsmode == 0usize {
            a2 = 0usize
            while a2 < p {
                ddf[a2] = f64(k - p)
                a2 += 1usize
            }
        }
        if dfsmode == 1usize {
            a2 = 0usize
            while a2 < p {
                ddf[a2] = dfsval
                a2 += 1usize
            }
        }
        if dfsmode == 2usize {
            let (codes, e4) = mem.alloc[f64](a, 5usize * k + 5usize)
            let (nlev, e5) = mem.alloc[f64](a, 8usize)
            let (tmpc, e6) = mem.alloc[f64](a, 2usize * k + 2usize)
            if e4 != ok || e5 != ok || e6 != ok { ret }
            // s factors, g inner and outer, h inner and outer
            var sbest = f64(k)
            var gbest = f64(k)
            var hbest = f64(k)
            a2 = 0usize
            while a2 < p {
                sbest = f64(k)
                gbest = f64(k)
                hbest = f64(k)
                var si = 0usize
                while si < c.ns {
                    var q = 0usize
                    while q < k {
                        tmpc[q] = c.sid[si * k + q]
                        q += 1usize
                    }
                    codes_of(tmpc, k, codes)
                    nlev[0usize] = f64(n_distinct(codes[0usize..k], k))
                    let r1 = contain_ddf(c, a2, codes, 1usize, nlev)
                    if r1 < sbest { sbest = r1 }
                    si += 1usize
                }
                if c.g.on {
                    var q = 0usize
                    if is_sp(c.g.kind) {
                        // the inner term is the coordinates (or the matrix row)
                        q = 0usize
                        while q < k {
                            tmpc[q] = f64(row_key(c.g.d, k, c.g.outer, q))
                            q += 1usize
                        }
                    } else {
                        q = 0usize
                        while q < k {
                            tmpc[q] = f64(row_key(c.g.z, c.g.nz, c.g.outer, q))
                            q += 1usize
                        }
                    }
                    q = 0usize
                    while q < k {
                        codes[q] = tmpc[q]
                        q += 1usize
                    }
                    nlev[0usize] = f64(n_distinct(codes[0usize..k], k))
                    codes_of(c.g.outer, k, codes[k..2usize * k])
                    nlev[1usize] = f64(n_distinct(codes[k..2usize * k], k))
                    let r2 = contain_ddf(c, a2, codes, 2usize, nlev)
                    if r2 < gbest { gbest = r2 }
                }
                if c.h.on {
                    var q = 0usize
                    if is_sp(c.h.kind) {
                        q = 0usize
                        while q < k {
                            tmpc[q] = f64(row_key(c.h.d, k, c.h.outer, q))
                            q += 1usize
                        }
                    } else {
                        q = 0usize
                        while q < k {
                            tmpc[q] = f64(row_key(c.h.z, c.h.nz, c.h.outer, q))
                            q += 1usize
                        }
                    }
                    q = 0usize
                    while q < k {
                        codes[q] = tmpc[q]
                        q += 1usize
                    }
                    nlev[0usize] = f64(n_distinct(codes[0usize..k], k))
                    codes_of(c.h.outer, k, codes[k..2usize * k])
                    nlev[1usize] = f64(n_distinct(codes[k..2usize * k], k))
                    let r3 = contain_ddf(c, a2, codes, 2usize, nlev)
                    if r3 < hbest { hbest = r3 }
                }
                var best = sbest
                if gbest < best { best = gbest }
                if hbest < best { best = hbest }
                ddf[a2] = best - f64(p)
                a2 += 1usize
            }
        }
        a2 = 0usize
        while a2 < p {
            if ddf[a2] < 1.0f64 { ddf[a2] = 1.0f64 }
            out[270usize + a2] = ddf[a2]
            a2 += 1usize
        }
    }
    let alpha = 0.05f64
    a2 = 0usize
    while a2 < p {
        let se = math.sqrt[f64](c.vb[a2 * p + a2])
        let z = c.beta[a2] / se
        var pv = 0.0f64
        var crit = 0.0f64
        if test >= 1usize {
            pv = 2.0f64 * nb.pt(math.abs[f64](z), ddf[a2], false, false)
            crit = nb.qt(alpha / 2.0f64, ddf[a2], false, false)
        } else {
            pv = 2.0f64 * dist.pnorm(math.abs[f64](z), 0.0f64, 1.0f64, false, false)
            crit = dist.qnorm(alpha / 2.0f64, 0.0f64, 1.0f64, false, false)
        }
        out[40usize + a2] = c.beta[a2]
        out[48usize + a2] = se
        out[56usize + a2] = z
        out[64usize + a2] = pv
        out[72usize + a2] = c.beta[a2] - crit * se
        out[80usize + a2] = c.beta[a2] + crit * se
        var b2 = 0usize
        while b2 < p {
            if p <= 4usize { out[88usize + a2 * p + b2] = c.vb[a2 * p + b2] }
            b2 += 1usize
        }
        a2 += 1usize
    }
    out[104usize] = c.qe
    if k > p { out[105usize] = nm.pchisq(c.qe, f64(k - p), false, false) }
    var btt0 = 0usize
    if p > 1usize { btt0 = 1usize }
    let m = p - btt0
    var qm = nan2()
    let (sub, e8) = mem.alloc[f64](a, m * m + 1usize)
    let (inv, e9) = mem.alloc[f64](a, m * m + 1usize)
    let (ag, e10) = mem.alloc[f64](a, 2usize * m * m + 2usize)
    if e8 == ok && e9 == ok && e10 == ok {
        var r1 = 0usize
        while r1 < m {
            var c1 = 0usize
            while c1 < m {
                sub[r1 * m + c1] = c.vb[(r1 + btt0) * p + c1 + btt0]
                c1 += 1usize
            }
            r1 += 1usize
        }
        if m1.chol_of(sub, m, ag) {
            let _ = m1.chol_inv(ag, m, inv, ag[m * m..2usize * m * m])
            qm = 0.0f64
            r1 = 0usize
            while r1 < m {
                var c1 = 0usize
                while c1 < m {
                    qm += c.beta[r1 + btt0] * inv[r1 * m + c1] * c.beta[c1 + btt0]
                    c1 += 1usize
                }
                r1 += 1usize
            }
        }
    }
    if test >= 1usize {
        qm = qm / f64(m)
        var d2 = ddf[btt0]
        a2 = btt0
        while a2 < p {
            if ddf[a2] < d2 { d2 = ddf[a2] }
            a2 += 1usize
        }
        out[106usize] = qm
        out[107usize] = nb.pf(qm, f64(m), d2, false, false)
        out[122usize] = d2
    } else {
        out[106usize] = qm
        out[107usize] = nm.pchisq(qm, f64(m), false, false)
    }
    // fit statistics
    let parms = f64(p + free_count(c))
    let kf = f64(k)
    let pi2 = 2.0f64 * 3.141592653589793f64
    let llqe = 0.0f64 - 0.5f64 * kf * math.log[f64](pi2) - 0.5f64 * c.ldv
    let llml = c.llml
    let llreml = c.llreml
    out[108usize] = llml
    out[109usize] = llreml
    out[110usize] = 0.0f64 - 2.0f64 * (llml - llqe)
    out[111usize] = 0.0f64 - 2.0f64 * llml + 2.0f64 * parms
    out[112usize] = 0.0f64 - 2.0f64 * llml + parms * math.log[f64](kf)
    var mxk = kf
    if parms + 2.0f64 > mxk { mxk = parms + 2.0f64 }
    out[113usize] = 0.0f64 - 2.0f64 * llml + 2.0f64 * parms * mxk / (mxk - parms - 1.0f64)
    out[114usize] = 0.0f64 - 2.0f64 * llreml
    out[115usize] = 0.0f64 - 2.0f64 * llreml + 2.0f64 * parms
    let kp = kf - f64(p)
    out[116usize] = 0.0f64 - 2.0f64 * llreml + parms * math.log[f64](kp)
    var mxp = kp
    if parms + 2.0f64 > mxp { mxp = parms + 2.0f64 }
    out[117usize] = 0.0f64 - 2.0f64 * llreml + 2.0f64 * parms * mxp / (mxp - parms - 1.0f64)
    out[118usize] = parms
    out[119usize] = kf
    out[120usize] = f64(p)
    out[121usize] = s2w
    out[123usize] = f64(nfn)
    if cvvc > 0usize && any_free(c) && (c.ns > 0usize || c.g.on) { compute_vvc(c, cvvc, par, out) }
}

fn read_term(c: *Mv2, t: *Term, kind: usize, dmethod: usize, args: []const f64, start: usize) -> usize {
    let k = c.k
    var at = start
    t.kind = kind
    t.on = true
    t.k = k
    t.outer = al(c, k)
    var i = 0usize
    while i < k {
        t.outer[i] = args[at + i]
        i += 1usize
    }
    at += k
    if is_sp(kind) {
        t.nz = 0usize
        t.d = al(c, k * k)
        if dmethod == 3usize {
            i = 0usize
            while i < k * k {
                t.d[i] = args[at + i]
                i += 1usize
            }
            at += k * k
        } else {
            let nc = usize(args[at])
            at += 1usize
            var r1 = 0usize
            while r1 < k {
                var r2 = 0usize
                while r2 < k {
                    var dd = 0.0f64
                    var cc = 0usize
                    while cc < nc {
                        let dv = args[at + r1 * nc + cc] - args[at + r2 * nc + cc]
                        if dmethod == 0usize { dd += dv * dv }
                        if dmethod == 1usize {
                            if absf(dv) > dd { dd = absf(dv) }
                        }
                        if dmethod == 2usize { dd += absf(dv) }
                        cc += 1usize
                    }
                    if dmethod == 0usize { dd = math.sqrt[f64](dd) }
                    t.d[r1 * k + r2] = dd
                    r2 += 1usize
                }
                r1 += 1usize
            }
            at += k * nc
        }
        t.ntau = 1usize
        t.nrho = 1usize
        t.chol = false
    } else {
        let nz = usize(args[at])
        at += 1usize
        t.nz = nz
        t.z = al(c, k * nz)
        i = 0usize
        while i < k * nz {
            t.z[i] = args[at + i]
            i += 1usize
        }
        at += k * nz
        t.vals = al(c, nz)
        i = 0usize
        while i < nz {
            t.vals[i] = args[at + i]
            i += 1usize
        }
        at += nz
        t.ntau = ntau_of2(kind, nz)
        t.nrho = nrho_of2(kind, nz)
        t.chol = is_chol(kind)
        t.e = al(c, nz * nz)
        t.ls = al(c, nz * nz)
    }
    t.vfix = al(c, t.ntau)
    t.rfix = al(c, t.nrho)
    i = 0usize
    while i < t.ntau {
        t.vfix[i] = args[at + i]
        i += 1usize
    }
    at += t.ntau
    i = 0usize
    while i < t.nrho {
        t.rfix[i] = args[at + i]
        i += 1usize
    }
    at += t.nrho
    t.tau = al(c, t.ntau)
    t.rho = al(c, t.nrho)
    t.sp = al(c, k * k)
    ret at
}

fn mv2_run(a: *mem.Arena, args: []const f64, out: []f64) -> bool {
    var c: Mv2 = zero
    c.a = a
    c.reml = args[0usize] != 0.0f64
    let test = usize(args[1usize])
    let optimizer = usize(args[2usize])
    let k = usize(args[3usize])
    let p = usize(args[4usize])
    c.k = k
    c.p = p
    c.ns = usize(args[5usize])
    let gk = usize(args[6usize])
    let hk = usize(args[7usize])
    let vmode = usize(args[8usize])
    c.hasa = args[9usize] != 0.0f64
    let maxit = usize(args[10usize])
    let cvvc = usize(args[11usize])
    let dfsmode = usize(args[12usize])
    let dfsval = args[13usize]
    let dmg = usize(args[14usize])
    let dmh = usize(args[15usize])
    var at = 16usize
    c.sslots = c.ns
    if c.sslots == 0usize { c.sslots = 1usize }
    c.y = al(&c, k)
    var i = 0usize
    while i < k {
        c.y[i] = args[at + i]
        i += 1usize
    }
    at += k
    c.x = al(&c, k * p)
    i = 0usize
    while i < k * p {
        c.x[i] = args[at + i]
        i += 1usize
    }
    at += k * p
    c.v = al(&c, k * k)
    if vmode == 0usize {
        i = 0usize
        while i < k {
            c.v[i * k + i] = args[at + i]
            i += 1usize
        }
        at += k
    } else {
        i = 0usize
        while i < k * k {
            c.v[i] = args[at + i]
            i += 1usize
        }
        at += k * k
    }
    c.aw = al(&c, k * k)
    if c.hasa {
        i = 0usize
        while i < k * k {
            c.aw[i] = args[at + i]
            i += 1usize
        }
        at += k * k
    }
    c.sid = al(&c, c.ns * k)
    i = 0usize
    while i < c.ns * k {
        c.sid[i] = args[at + i]
        i += 1usize
    }
    at += c.ns * k
    c.sfix = al(&c, c.sslots)
    i = 0usize
    while i < c.sslots {
        c.sfix[i] = args[at + i]
        i += 1usize
    }
    at += c.sslots
    if gk > 0usize { at = read_term(&c, &c.g, gk, dmg, args, at) }
    if hk > 0usize { at = read_term(&c, &c.h, hk, dmh, args, at) }
    c.m = al(&c, k * k)
    c.w = al(&c, k * k)
    c.l = al(&c, k * k)
    c.aug = al(&c, 2usize * k * k)
    c.xtwx = al(&c, p * p)
    c.sinv = al(&c, p * p)
    c.paug = al(&c, 2usize * p * p)
    c.xm = al(&c, p * p)
    c.beta = al(&c, p)
    c.vb = al(&c, p * p)
    c.res = al(&c, k)
    c.tmpv = al(&c, k + p)
    c.ev = al(&c, p * p + k)
    c.ax = al(&c, k * p)
    c.bx = al(&c, k * p)
    c.sig = al(&c, c.ns + 1usize)
    c.gbuf = al(&c, nslots(&c) + 1usize)
    if c.bad { ret false }
    // log |X'X|
    var a1 = 0usize
    while a1 < p {
        var b1 = 0usize
        while b1 < p {
            var s = 0.0f64
            i = 0usize
            while i < k {
                s += c.x[i * p + a1] * c.x[i * p + b1]
                i += 1usize
            }
            c.xtwx[a1 * p + b1] = s
            b1 += 1usize
        }
        a1 += 1usize
    }
    c.ldxx = m1.logdet_spd(c.xtwx, p, c.paug)
    fit_mv2(&c, optimizer, maxit, test, cvvc, dfsmode, dfsval, out)
    ret true
}
