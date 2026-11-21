// R nlme::gls: generalised least squares with a correlation structure and variance functions, REML and ML. Groups are
// contiguous blocks of rows. The correlation parameters and the variance parameters are estimated by nlminb on the
// profile objective, starting from nlme's own start values and in nlme's unconstrained parametrisation, so the optimiser
// follows the path R's gls follows. Outputs (see `gls_fit`): coefficients, sigma, logLik, AIC, BIC, the natural correlation and
// variance parameters, the coefficient standard errors and the 95% t intervals of intervals.gls.
//
// Correlation kinds (ck): 0 none, 1 corAR1, 2 corCompSymm, 3 corCAR1, 4 corARMA(p = 1, q = 1), 6 corExp, 7 corGaus,
// 8 corSpher, 9 corLin, 10 corRatio, 11 corSymm (equal group sizes up to 8). The covariate t is the position (AR1, ARMA,
// Symm) or the coordinate (CAR1 and the spatial kinds) inside a group.
// Variance kinds (vk): 1 varIdent (stratum ids 0.. in order of appearance), 2 varPower, 3 varExp, 4 varConstPower (covariate
// v), 5 varFixed (variance proportional to v); up to three terms multiply (varComb).
//
// Not here: lme, lmList (see nlmelist), corARMA of other orders, fitted-value covariates (varPower(~fitted(.))), nugget.

use e.algo.stat.nlminb as nlb
use e.algo.stat.psych as ps
use e.math
use e.math.nmath_beta as nb
use e.mem

type Spec = struct { n: usize, p: usize, x: []const f64, y: []const f64, t: []const f64, gs: []const f64, ng: usize, ck: i64, nv: usize, vk: []const f64, vn: []const f64, vc: []const f64, reml: bool, q: usize, z: []const f64, pd: i64 }

// number of random-effects parameters (lme): the log-Cholesky factor of the relative precision-free covariance, column by column
// pd selects the pdMat class: 0 pdLogChol (the default, q (q + 1) / 2), 1 pdDiag (q log sds), 2 pdIdent (one log sd), 3 pdCompSymm
// (log sd and nlme's logit-like parameter of the correlation)
fn nre(s: *const Spec) -> usize {
    if s.pd == 1i64 { ret s.q }
    if s.pd == 2i64 { ret 1usize }
    if s.pd == 3i64 { ret 2usize }
    ret s.q * (s.q + 1usize) / 2usize
}

// relative random-effects covariance D = L L' (q by q row-major); L has exp of the first parameter of each column on its diagonal
fn re_cov(q: usize, par: []const f64, d: []f64, pd: i64) {
    if pd != 0i64 {
        var i0 = 0usize
        while i0 < q * q {
            d[i0] = 0.0f64
            i0 += 1usize
        }
        var i1 = 0usize
        while i1 < q {
            var lp = par[0usize]
            if pd == 1i64 { lp = par[i1] }
            d[i1 * q + i1] = math.exp[f64](2.0f64 * lp)
            i1 += 1usize
        }
        if pd == 3i64 {
            let e = math.exp[f64](par[1usize])
            let rho = (e - 1.0f64 / (f64(q) - 1.0f64)) / (e + 1.0f64)
            var a1 = 0usize
            while a1 < q {
                var b1 = 0usize
                while b1 < q {
                    if a1 != b1 { d[a1 * q + b1] = math.exp[f64](2.0f64 * par[0usize]) * rho }
                    b1 += 1usize
                }
                a1 += 1usize
            }
        }
        ret
    }
    var l: [64]f64 = zero
    var k = 0usize
    var j = 0usize
    while j < q {
        l[j * q + j] = math.exp[f64](par[k])
        k += 1usize
        var i = j + 1usize
        while i < q {
            l[i * q + j] = par[k]
            k += 1usize
            i += 1usize
        }
        j += 1usize
    }
    var i = 0usize
    while i < q {
        j = 0usize
        while j < q {
            var v = 0.0f64
            k = 0usize
            while k < q {
                v += l[i * q + k] * l[j * q + k]
                k += 1usize
            }
            d[i * q + j] = v
            j += 1usize
        }
        i += 1usize
    }
}

// adds Z D Z' within each group to the n by n matrix r
fn add_re(s: *const Spec, par: []const f64, r: []f64) {
    let q = s.q
    let n = s.n
    var d: [64]f64 = zero
    re_cov(q, par, d[0usize..64usize], s.pd)
    var st = 0usize
    var g = 0usize
    while g < s.ng {
        let m = usize(s.gs[g])
        var a = 0usize
        while a < m {
            var b = 0usize
            while b < m {
                var v = 0.0f64
                var k = 0usize
                while k < q {
                    var l = 0usize
                    while l < q {
                        v += s.z[k * n + st + a] * d[k * q + l] * s.z[l * n + st + b]
                        l += 1usize
                    }
                    k += 1usize
                }
                r[(st + a) * n + st + b] += v
                b += 1usize
            }
            a += 1usize
        }
        st += m
        g += 1usize
    }
}
type Ctx = struct { a: *mem.Arena, s: Spec, cst: f64 }
type Fit = struct { sigma: f64, loglik: f64, good: bool }

fn maxgs(s: *const Spec) -> usize {
    var m = 0usize
    var g = 0usize
    while g < s.ng {
        let v = usize(s.gs[g])
        if v > m { m = v }
        g += 1usize
    }
    ret m
}

fn ncor(s: *const Spec) -> usize {
    let k = s.ck
    if k == 0i64 { ret 0usize }
    if k >= 1000i64 { ret arma_p(k) + arma_q(k) }
    if k == 4i64 { ret 2usize }
    if k == 11i64 {
        let m = maxgs(s)
        ret m * (m - 1usize) / 2usize
    }
    ret 1usize
}

fn nvar1(kind0: i64, nstr: usize) -> usize {
    var kind = kind0
    if kind >= 10i64 { kind -= 10i64 }
    if kind == 1i64 { ret nstr - 1usize }
    if kind == 2i64 || kind == 3i64 { ret 1usize }
    if kind == 4i64 { ret 2usize }
    ret 0usize
}

fn nvar(s: *const Spec) -> usize {
    var c = 0usize
    var k = 0usize
    while k < s.nv {
        c += nvar1(i64(s.vk[k]), usize(s.vn[k]))
        k += 1usize
    }
    ret c
}

fn logistic(x: f64) -> f64 { ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - x)) }

// upper Cholesky-type factor of corSymm: column i holds i angles pi * logistic(x); u[j * m + i]
fn symm_factor(par: []const f64, m: usize, u: []f64) {
    var k = 0usize
    while k < m * m {
        u[k] = 0.0f64
        k += 1usize
    }
    u[0usize] = 1.0f64
    var off = 0usize
    var i = 1usize
    while i < m {
        var sp = 1.0f64
        var j = 0usize
        while j < i {
            let ang = 3.141592653589793f64 * logistic(par[off + j])
            u[j * m + i] = sp * math.cos[f64](ang)
            sp = sp * math.sin[f64](ang)
            j += 1usize
        }
        u[i * m + i] = sp
        off += i
        i += 1usize
    }
}

fn corr_val(ck: i64, md: f64, par: []const f64, d: f64, a: usize, b: usize, ma: usize, u: []const f64) -> f64 {
    if a == b { ret 1.0f64 }
    if ck == 0i64 { ret 0.0f64 }
    if ck == 1i64 {
        let e = math.exp[f64](par[0usize])
        ret math.pow[f64]((e - 1.0f64) / (e + 1.0f64), d)
    }
    if ck == 2i64 {
        let e = math.exp[f64](par[0usize])
        ret (e - 1.0f64 / (f64(ma) - 1.0f64)) / (e + 1.0f64)
    }
    if ck == 3i64 { ret math.pow[f64](logistic(par[0usize]), d) }
    if ck >= 1000i64 { ret u[usize(d + 0.5f64)] }
    if ck == 4i64 {
        let ph = th2(par[0usize])
        let th = th2(par[1usize])
        ret math.pow[f64](ph, d - 1.0f64) * (ph + th) * (1.0f64 + ph * th) / (1.0f64 + 2.0f64 * ph * th + th * th)
    }
    if ck == 11i64 {
        var v = 0.0f64
        var k = 0usize
        while k < ma {
            v += u[k * ma + a] * u[k * ma + b]
            k += 1usize
        }
        ret v
    }
    var r = math.exp[f64](par[0usize])
    if ck == 8i64 || ck == 9i64 { r += md }
    let q = d / r
    if ck == 6i64 { ret math.exp[f64](0.0f64 - q) }
    if ck == 7i64 { ret math.exp[f64](0.0f64 - q * q) }
    if ck == 10i64 { ret 1.0f64 / (1.0f64 + q * q) }
    if d >= r { ret 0.0f64 }
    if ck == 8i64 { ret 1.0f64 - 1.5f64 * q + 0.5f64 * q * q * q }
    ret 1.0f64 - q
}

// block-diagonal correlation matrix (n by n) for the correlation parameters par
fn fill_corr(s: *const Spec, par: []const f64, r: []f64) {
    let n = s.n
    var i = 0usize
    while i < n * n {
        r[i] = 0.0f64
        i += 1usize
    }
    let ma = maxgs(s)
    let md = mind(s)
    var u: [64]f64 = zero
    if s.ck == 11i64 { symm_factor(par, ma, u[0usize..64usize]) }
    if s.ck >= 1000i64 {
        var cp: [8]f64 = zero
        let ap = arma_p(s.ck)
        let aq = arma_q(s.ck)
        arma_const(ap, aq, par, cp[0usize..8usize])
        arma_corr(ap, aq, ma, cp[0usize..8usize], u[0usize..64usize])
    }
    var st = 0usize
    var g = 0usize
    while g < s.ng {
        let m = usize(s.gs[g])
        var a = 0usize
        while a < m {
            var b = 0usize
            while b < m {
                let d = math.abs[f64](s.t[st + a] - s.t[st + b])
                r[(st + a) * n + st + b] = corr_val(s.ck, md, par, d, a, b, ma, u[0usize..64usize])
                b += 1usize
            }
            a += 1usize
        }
        st += m
        g += 1usize
    }
}

// sd multipliers of the variance terms (1 for none); par is the variance part of the parameter vector
fn fill_sd(s: *const Spec, par: []const f64, sd: []f64) {
    let n = s.n
    var i = 0usize
    while i < n {
        sd[i] = 1.0f64
        i += 1usize
    }
    var off = 0usize
    var k = 0usize
    while k < s.nv {
        let kind = i64(s.vk[k])
        i = 0usize
        while i < n {
            let v = s.vc[k * n + i]
            var m = 1.0f64
            if kind == 1i64 {
                let st = usize(v)
                if st > 0usize { m = math.exp[f64](par[off + st - 1usize]) }
            } else if kind == 2i64 {
                m = math.pow[f64](math.abs[f64](v), par[off])
            } else if kind == 3i64 {
                m = math.exp[f64](par[off] * v)
            } else if kind == 4i64 {
                m = math.exp[f64](par[off]) + math.pow[f64](math.abs[f64](v), par[off + 1usize])
            } else {
                m = math.sqrt[f64](math.abs[f64](v))
            }
            sd[i] = sd[i] * m
            i += 1usize
        }
        off += nvar1(kind, usize(s.vn[k]))
        k += 1usize
    }
}

// smallest within-group distance (nlme's minD)
fn mind(s: *const Spec) -> f64 {
    var md = 1.0e300f64
    var st = 0usize
    var g = 0usize
    while g < s.ng {
        let m = usize(s.gs[g])
        var a = 0usize
        while a < m {
            var b = a + 1usize
            while b < m {
                let d = math.abs[f64](s.t[st + a] - s.t[st + b])
                if d < md { md = d }
                b += 1usize
            }
            a += 1usize
        }
        st += m
        g += 1usize
    }
    ret md
}

fn start_pars(s: *const Spec, par: []f64) {
    let nc = ncor(s)
    var i = 0usize
    while i < par.len {
        par[i] = 0.0f64
        i += 1usize
    }
    if s.ck == 2i64 { par[0usize] = math.log[f64](1.0f64 / (f64(maxgs(s)) - 1.0f64)) }
    if s.ck == 3i64 { par[0usize] = math.log[f64](0.2f64 / 0.8f64) }
    if s.ck >= 6i64 && s.ck <= 10i64 {
        if s.ck == 8i64 || s.ck == 9i64 {
            par[0usize] = math.log[f64](0.1f64 * mind(s))
        } else {
            par[0usize] = math.log[f64](0.9f64 * mind(s))
        }
    }
    var off = nc
    var k = 0usize
    while k < s.nv {
        let kind = i64(s.vk[k])
        if kind == 4i64 { par[off] = math.log[f64](0.1f64) }
        off += nvar1(kind, usize(s.vn[k]))
        k += 1usize
    }
}

// profile fit at the parameter vector par: coef (p), xtxi (p by p) receive the estimates
fn core(a: *mem.Arena, s: *const Spec, par: []const f64, coef: []f64, xtxi: []f64) -> Fit {
    let n = s.n
    let p = s.p
    let x = s.x
    let y = s.y
    var bad: Fit = zero
    let (r, e1) = mem.alloc[f64](a, n * n)
    let (si, e2) = mem.alloc[f64](a, n * n)
    let (xtx, e3) = mem.alloc[f64](a, p * p)
    let (xty, e5) = mem.alloc[f64](a, p)
    let (sx, e6) = mem.alloc[f64](a, n * p)
    let (sd, e7) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e5 != ok || e6 != ok || e7 != ok { ret bad }
    let nc = ncor(s)
    let nr = nre(s)
    fill_corr(s, par[nr..nr + nc], r)
    fill_sd(s, par[nr + nc..par.len], sd)
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            r[i * n + j] = r[i * n + j] * sd[i] * sd[j]
            j += 1usize
        }
        i += 1usize
    }
    if s.q > 0usize { add_re(s, par[0usize..nr], r) }
    if !ps.invert(a, r, n, si) { ret bad }
    var j = 0usize
    while j < p {
        i = 0usize
        while i < n {
            var v = 0.0f64
            var k = 0usize
            while k < n {
                v += si[i * n + k] * x[j * n + k]
                k += 1usize
            }
            sx[j * n + i] = v
            i += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < p {
        var k = 0usize
        while k < p {
            var v = 0.0f64
            i = 0usize
            while i < n {
                v += x[j * n + i] * sx[k * n + i]
                i += 1usize
            }
            xtx[j * p + k] = v
            k += 1usize
        }
        var v = 0.0f64
        i = 0usize
        while i < n {
            v += sx[j * n + i] * y[i]
            i += 1usize
        }
        xty[j] = v
        j += 1usize
    }
    if !ps.invert(a, xtx, p, xtxi) { ret bad }
    j = 0usize
    while j < p {
        var v = 0.0f64
        var k = 0usize
        while k < p {
            v += xtxi[j * p + k] * xty[k]
            k += 1usize
        }
        coef[j] = v
        j += 1usize
    }
    // rss = r' S^-1 r
    var rss = 0.0f64
    i = 0usize
    while i < n {
        var ri = y[i]
        j = 0usize
        while j < p {
            ri -= x[j * n + i] * coef[j]
            j += 1usize
        }
        var k = 0usize
        while k < n {
            var rk = y[k]
            j = 0usize
            while j < p {
                rk -= x[j * n + k] * coef[j]
                j += 1usize
            }
            rss += ri * si[i * n + k] * rk
            k += 1usize
        }
        i += 1usize
    }
    let nf = f64(n)
    let pf = f64(p)
    let ldet = ps.logdet(a, r, n)
    let two_pi = 2.0f64 * 3.141592653589793f64
    if s.reml {
        let s2 = rss / (nf - pf)
        let ll = 0.0f64 - (nf - pf) / 2.0f64 * math.log[f64](two_pi * s2) - 0.5f64 * ldet - 0.5f64 * ps.logdet(a, xtx, p) - (nf - pf) / 2.0f64
        ret Fit { sigma: math.sqrt[f64](s2), loglik: ll, good: true }
    }
    let s2 = rss / nf
    ret Fit { sigma: math.sqrt[f64](s2), loglik: 0.0f64 - nf / 2.0f64 * math.log[f64](two_pi * s2) - 0.5f64 * ldet - nf / 2.0f64, good: true }
}

// nlme minimises minus the log-likelihood without its constant N (log N - (1 + log 2 pi)) / 2
fn obj(c: *Ctx, par: []const f64) -> f64 {
    let st = mem.mark(c.a)
    let (coef, e1) = mem.alloc[f64](c.a, c.s.p)
    let (xi, e2) = mem.alloc[f64](c.a, c.s.p * c.s.p)
    var v = 1.0e300f64
    if e1 == ok && e2 == ok {
        let f = core(c.a, &c.s, par, coef, xi)
        if f.good { v = c.cst - f.loglik }
    }
    mem.reset(c.a, st)
    ret v
}

fn nograd(c: *Ctx, par: []const f64, g: []f64) {}

fn nvnat(s: *const Spec) -> usize { ret nvar(s) }

fn ncnat(s: *const Spec) -> usize {
    if s.ck == 11i64 { ret ncor(s) }
    ret ncor(s)
}

// length of the output vector of gls_fit
fn out_len(s: *const Spec) -> usize { ret 4usize + 4usize * s.p + ncnat(s) + nvnat(s) }

// writes X beta into the covariate of every variance term of kind >= 10
fn set_fitted(s: *const Spec, vc: []f64, beta: []const f64) {
    let n = s.n
    var k = 0usize
    while k < s.nv {
        if s.vk[k] >= 10.0f64 {
            var i = 0usize
            while i < n {
                var v = 0.0f64
                var j = 0usize
                while j < s.p {
                    v += s.x[j * n + i] * beta[j]
                    j += 1usize
                }
                vc[k * n + i] = v
                i += 1usize
            }
        }
        k += 1usize
    }
}

// x is n by p column-major; out follows out_len: coef, sigma, logLik, AIC, BIC, natural correlation (corSymm: lower triangle by
// columns), natural variance parameters, se, lower and upper 95% limits
fn gls_fit(a: *mem.Arena, s0: Spec, out: []f64) -> err {
    var s = s0
    let n = s.n
    let p = s.p
    let np = ncor(&s) + nvar(&s)
    let (par, e1) = mem.alloc[f64](a, np + 1usize)
    let (coef, e2) = mem.alloc[f64](a, p)
    let (xi, e3) = mem.alloc[f64](a, p * p)
    let (oldp, e4) = mem.alloc[f64](a, p + np + 1usize)
    let (vk2, e5) = mem.alloc[f64](a, s.nv + 1usize)
    let (vc2, e6) = mem.alloc[f64](a, s.nv * n + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret e1 }
    // variance covariates ~ fitted(.) are kinds 12, 13, 14 (kind + 10): the covariate is the fitted value of the previous pass
    var nfit = 0usize
    var kk = 0usize
    while kk < s.nv {
        var kd = s0.vk[kk]
        var cv = 0.0f64
        if kd >= 10.0f64 {
            kd -= 10.0f64
            nfit += 1usize
            cv = 1.0f64
        }
        vk2[kk] = kd
        var ii = 0usize
        while ii < n {
            if cv != 0.0f64 { vc2[kk * n + ii] = cv } else { vc2[kk * n + ii] = s0.vc[kk * n + ii] }
            ii += 1usize
        }
        kk += 1usize
    }
    s.vk = vk2[0usize..s.nv]
    s.vc = vc2[0usize..s.nv * n]
    let pv = par[0usize..np]
    start_pars(&s, pv)
    let nr = f64(n) - f64(p) * (if_reml(s.reml))
    let cst = nr * (math.log[f64](nr) - (1.0f64 + math.log[f64](2.0f64 * 3.141592653589793f64))) / 2.0f64
    var c = Ctx { a: a, s: s, cst: cst }
    if nfit > 0usize {
        let f0 = core(a, &s, pv, coef, xi)
        if !f0.good { ret Singular }
        var j0 = 0usize
        while j0 < p {
            oldp[j0] = coef[j0]
            j0 += 1usize
        }
        j0 = 0usize
        while j0 < np {
            oldp[p + j0] = pv[j0]
            j0 += 1usize
        }
        set_fitted(&s0, vc2, coef)
    }
    var f = Fit { sigma: 0.0f64, loglik: 0.0f64, good: false }
    var pass = 0usize
    while true {
        if np > 0usize {
            var ctl: [2]f64 = zero
            ctl[0usize] = 200.0f64
            ctl[1usize] = 200.0f64
            let r = nlb.nlminb[Ctx](a, &c, obj, nograd, false, pv, ctl[0usize..2usize])
            if r.iterations == 0usize && r.fevals == 0usize { ret Singular }
        }
        f = core(a, &s, pv, coef, xi)
        if !f.good { ret Singular }
        if nfit == 0usize { break }
        // nlme's convergence rule: relative change of the coefficients and the parameters, tolerance 1e-6, at most 50 passes
        var cmax = 0.0f64
        var j1 = 0usize
        while j1 < p + np {
            var nw = pv[0usize]
            if j1 < p { nw = coef[j1] } else { nw = pv[j1 - p] }
            var dn = nw
            if dn == 0.0f64 { dn = 1.0f64 }
            let dv = math.abs[f64]((oldp[j1] - nw) / dn)
            if dv > cmax { cmax = dv }
            oldp[j1] = nw
            j1 += 1usize
        }
        set_fitted(&s0, vc2, coef)
        if cmax <= 1.0e-6f64 { break }
        pass += 1usize
        if pass > 50usize { ret Singular }
    }
    var j = 0usize
    while j < p {
        out[j] = coef[j]
        j += 1usize
    }
    out[p] = f.sigma
    out[p + 1usize] = f.loglik
    let npar = f64(p + np + 1usize)
    out[p + 2usize] = 0.0f64 - 2.0f64 * f.loglik + 2.0f64 * npar
    out[p + 3usize] = 0.0f64 - 2.0f64 * f.loglik + npar * math.log[f64](nr)
    var o = p + 4usize
    o += natural(&s, pv, out[o..out.len])
    // standard errors and the t intervals of intervals.gls
    let tq = nb.qt(0.975f64, f64(n) - f64(p), true, false)
    let s2 = f.sigma * f.sigma * nr / (f64(n) - f64(p))
    j = 0usize
    while j < p {
        let se = math.sqrt[f64](s2 * xi[j * p + j])
        out[o + j] = se
        out[o + p + j] = coef[j] - tq * se
        out[o + 2usize * p + j] = coef[j] + tq * se
        j += 1usize
    }
    ret ok
}

// natural correlation (corSymm: lower triangle by columns) and variance parameters from the correlation and variance part of
// the parameter vector (no random-effects parameters); returns how many were written
fn natural(s: *const Spec, pv: []const f64, out: []f64) -> usize {
    let nc = ncor(s)
    var o = 0usize
    if s.ck == 1i64 {
        let e = math.exp[f64](pv[0usize])
        out[o] = (e - 1.0f64) / (e + 1.0f64)
    } else if s.ck == 2i64 {
        let e = math.exp[f64](pv[0usize])
        out[o] = (e - 1.0f64 / (f64(maxgs(s)) - 1.0f64)) / (e + 1.0f64)
    } else if s.ck == 3i64 {
        out[o] = logistic(pv[0usize])
    } else if s.ck >= 1000i64 {
        arma_const(arma_p(s.ck), arma_q(s.ck), pv, out[o..o + nc])
    } else if s.ck == 4i64 {
        out[o] = th2(pv[0usize])
        out[o + 1usize] = th2(pv[1usize])
    } else if s.ck == 11i64 {
        let m = maxgs(s)
        var u: [64]f64 = zero
        symm_factor(pv[0usize..nc], m, u[0usize..64usize])
        var q = 0usize
        var cl = 0usize
        while cl < m {
            var rw = cl + 1usize
            while rw < m {
                out[o + q] = corr_val(11i64, 0.0f64, pv, 1.0f64, cl, rw, m, u[0usize..64usize])
                q += 1usize
                rw += 1usize
            }
            cl += 1usize
        }
    } else if s.ck != 0i64 {
        out[o] = math.exp[f64](pv[0usize])
        if s.ck == 8i64 || s.ck == 9i64 { out[o] += mind(s) }
    }
    o += nc
    var off = nc
    var k = 0usize
    while k < s.nv {
        let kind = i64(s.vk[k])
        let cnt = nvar1(kind, usize(s.vn[k]))
        var q = 0usize
        while q < cnt {
            var v = pv[off + q]
            if kind == 1i64 || (kind == 4i64 && q == 0usize) { v = math.exp[f64](v) }
            out[o + q] = v
            q += 1usize
        }
        o += cnt
        off += cnt
        k += 1usize
    }
    ret o
}

fn if_reml(r: bool) -> f64 {
    if r { ret 1.0f64 }
    ret 0.0f64
}

fn th2(x: f64) -> f64 {
    let e = math.exp[f64](x)
    ret (e - 1.0f64) / (e + 1.0f64)
}

// corARMA(p, q) other than (1, 1) is ck = 1000 + 10 p + q: nlme's ARMA_constCoef / ARMA_cross / ARMA_corr in order, including the
// theta index of the `i = p + 1 .. q` tail of ARMA_corr, which is as in the C source
fn arma_p(ck: i64) -> usize {
    if ck == 4i64 { ret 1usize }
    ret usize((ck - 1000i64) / 10i64)
}

fn arma_q(ck: i64) -> usize {
    if ck == 4i64 { ret 1usize }
    ret usize(ck % 10i64)
}

// unconstrained to constrained coefficients in place; nn is p or q, sgn -1 for phi, +1 for theta
fn arma_untrans(nn: usize, sgn: f64, pars: []f64) {
    var aux: [8]f64 = zero
    var i = 0usize
    while i < nn {
        let e = math.exp[f64](0.0f64 - pars[i])
        let v = (1.0f64 - e) / (1.0f64 + e)
        pars[i] = v
        aux[i] = v
        if i > 0usize {
            var j = 0usize
            while j < i {
                pars[j] = aux[j] + sgn * v * aux[i - j - 1usize]
                j += 1usize
            }
            j = 0usize
            while j < i {
                aux[j] = pars[j]
                j += 1usize
            }
        }
        i += 1usize
    }
}

fn arma_const(p: usize, q: usize, un: []const f64, out: []f64) {
    var i = 0usize
    while i < p + q {
        out[i] = un[i]
        i += 1usize
    }
    arma_untrans(p, 0.0f64 - 1.0f64, out[0usize..p])
    arma_untrans(q, 1.0f64, out[p..p + q])
}

// autocorrelations crr[0 ..= maxlag] of the ARMA(p, q) process with constrained coefficients pars (phi then theta)
fn arma_corr(p: usize, q: usize, maxlag: usize, pars: []const f64, crr: []f64) {
    var psi: [8]f64 = zero
    var mm = q + 1usize
    if p > mm { mm = p }
    psi[0usize] = 1.0f64
    var i = 1usize
    while i < mm {
        if q >= i { psi[i] = pars[p + i - 1usize] }
        var pm = p
        if i < pm { pm = i }
        var j = 0usize
        while j < pm {
            psi[i] += pars[j] * psi[i - j - 1usize]
            j += 1usize
        }
        i += 1usize
    }
    var ml = maxlag
    if q > ml { ml = q }
    if p > ml { ml = p }
    ml += 1usize
    i = 0usize
    while i < ml {
        crr[i] = 0.0f64
        i += 1usize
    }
    crr[0usize] = 1.0f64
    i = 1usize
    while i <= q {
        crr[0usize] += pars[p + i - 1usize] * psi[i]
        i += 1usize
    }
    let pp = p + 1usize
    if p > 0usize {
        var mpq = p
        if q < mpq { mpq = q }
        i = 1usize
        while i <= mpq {
            var j = i
            while j <= q {
                crr[i] += pars[p - 1usize + j] * psi[j - i]
                j += 1usize
            }
            i += 1usize
        }
        // solve coef x = crr[0 .. pp), coef[r][c] = [r == c] - sum of phi_j over |r - j - 1| == c, by Gauss with pivoting
        var m: [36]f64 = zero
        var b: [6]f64 = zero
        var r = 0usize
        while r < pp {
            m[r * pp + r] = 1.0f64
            var j = 0usize
            while j < p {
                var k = 0usize
                if r > j + 1usize { k = r - j - 1usize } else { k = j + 1usize - r }
                m[r * pp + k] -= pars[j]
                j += 1usize
            }
            b[r] = crr[r]
            r += 1usize
        }
        var c = 0usize
        while c < pp {
            var pv = c
            var r2 = c + 1usize
            while r2 < pp {
                if math.abs[f64](m[r2 * pp + c]) > math.abs[f64](m[pv * pp + c]) { pv = r2 }
                r2 += 1usize
            }
            var k = 0usize
            while k < pp {
                let tmp = m[c * pp + k]
                m[c * pp + k] = m[pv * pp + k]
                m[pv * pp + k] = tmp
                k += 1usize
            }
            let tb = b[c]
            b[c] = b[pv]
            b[pv] = tb
            r2 = c + 1usize
            while r2 < pp {
                let f = m[r2 * pp + c] / m[c * pp + c]
                k = c
                while k < pp {
                    m[r2 * pp + k] -= f * m[c * pp + k]
                    k += 1usize
                }
                b[r2] -= f * b[c]
                r2 += 1usize
            }
            c += 1usize
        }
        r = pp
        while r > 0usize {
            r -= 1usize
            var sv = b[r]
            var k = r + 1usize
            while k < pp {
                sv -= m[r * pp + k] * b[k]
                k += 1usize
            }
            b[r] = sv / m[r * pp + r]
        }
        i = 0usize
        while i < ml {
            crr[i] = 0.0f64
            if i < pp { crr[i] = b[i] }
            i += 1usize
        }
    }
    i = pp
    while i <= q {
        var j = 0usize
        while j < p {
            crr[i] += pars[j] * crr[i - j - 1usize]
            j += 1usize
        }
        j = i
        while j <= q {
            crr[i] += pars[j - 1usize] * psi[j - i]
            j += 1usize
        }
        i += 1usize
    }
    var mx = p
    if q > mx { mx = q }
    i = mx + 1usize
    while i < ml {
        var j = 0usize
        while j < p {
            crr[i] += pars[j] * crr[i - j - 1usize]
            j += 1usize
        }
        i += 1usize
    }
    i = 1usize
    while i < ml {
        crr[i] = crr[i] / crr[0usize]
        i += 1usize
    }
    crr[0usize] = 1.0f64
}

error Singular
