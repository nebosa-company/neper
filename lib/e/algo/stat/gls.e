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

type Spec = struct { n: usize, p: usize, x: []const f64, y: []const f64, t: []const f64, gs: []const f64, ng: usize, ck: i64, nv: usize, vk: []const f64, vn: []const f64, vc: []const f64, reml: bool, q: usize, z: []const f64 }

// number of random-effects parameters (lme): the log-Cholesky factor of the relative precision-free covariance, column by column
fn nre(s: *const Spec) -> usize { ret s.q * (s.q + 1usize) / 2usize }

// relative random-effects covariance D = L L' (q by q row-major); L has exp of the first parameter of each column on its diagonal
fn re_cov(q: usize, par: []const f64, d: []f64) {
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
    re_cov(q, par, d[0usize..64usize])
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
    if k == 4i64 { ret 2usize }
    if k == 11i64 {
        let m = maxgs(s)
        ret m * (m - 1usize) / 2usize
    }
    ret 1usize
}

fn nvar1(kind: i64, nstr: usize) -> usize {
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

// x is n by p column-major; out follows out_len: coef, sigma, logLik, AIC, BIC, natural correlation (corSymm: lower triangle by
// columns), natural variance parameters, se, lower and upper 95% limits
fn gls_fit(a: *mem.Arena, s: Spec, out: []f64) -> err {
    let n = s.n
    let p = s.p
    let np = ncor(&s) + nvar(&s)
    let (par, e1) = mem.alloc[f64](a, np + 1usize)
    let (coef, e2) = mem.alloc[f64](a, p)
    let (xi, e3) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok { ret e1 }
    let pv = par[0usize..np]
    start_pars(&s, pv)
    let nr = f64(n) - f64(p) * (if_reml(s.reml))
    let cst = nr * (math.log[f64](nr) - (1.0f64 + math.log[f64](2.0f64 * 3.141592653589793f64))) / 2.0f64
    var c = Ctx { a: a, s: s, cst: cst }
    if np > 0usize {
        var ctl: [2]f64 = zero
        ctl[0usize] = 200.0f64
        ctl[1usize] = 200.0f64
        let r = nlb.nlminb[Ctx](a, &c, obj, nograd, false, pv, ctl[0usize..2usize])
        if r.iterations == 0usize && r.fevals == 0usize { ret Singular }
    }
    let f = core(a, &s, pv, coef, xi)
    if !f.good { ret Singular }
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

error Singular
