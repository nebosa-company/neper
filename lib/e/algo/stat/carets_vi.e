// R caret, the rest of preProcess and varImp: preProcess(x, method = "ica", n.comp = e, ...) with predict. The columns are centred and scaled first, then
// fastICA(x, e, ...) runs with its default method = "R" (ica.R.par and ica.R.def of fastICA 1.2-8, parallel or deflation, logcosh or exp, alpha) on
// w.init = rnorm(e^2) from the seeded generator, and new rows are mapped by x K W.

use e.algo.linalg.lapack_gesdd as lapack
use e.algo.rand.r as rng
use e.algo.stat.carets as ct
use e.algo.stat.fastica as fi
use e.algo.stat.rpartfull as rf
use e.algo.stat.randomforest as rfm
use e.algo.stat.bayesmpkg as bz
use e.math.dist as dist
use e.math
use e.mem
use e.js.fdlibm as fdl

// u diag(1 / d) u' x for the e by e matrix x (La.svd of fastICA's symmetric orthogonalisation)
fn ica_orthog(a: *mem.Arena, x: []const f64, e: usize, out: []f64) -> err {
    let (s, e1) = mem.alloc[f64](a, e)
    let (u, e2) = mem.alloc[f64](a, e * e)
    let (vt, e3) = mem.alloc[f64](a, e * e)
    let (t, e4) = mem.alloc[f64](a, e * e)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    let se = lapack.svd_all(a, x, e, e, s, u, vt)
    if se != ok { ret se }
    var j = 0usize
    while j < e {
        var i = 0usize
        while i < e {
            var v = 0.0f64
            var k = 0usize
            while k < e {
                v += u[i + k * e] / s[k] * u[j + k * e]
                k += 1usize
            }
            t[i + j * e] = v
            i += 1usize
        }
        j += 1usize
    }
    fi.fica_mm(t, x, e, e, e, out)
    ret ok
}

// the nonlinearity g(w x) and g'(w x) of one value: logcosh tanh(alpha v) and alpha (1 - tanh^2); exp v exp(-v^2 / 2) and (1 - v^2) exp(-v^2 / 2)
fn ica_g(v: f64, expfun: bool, alpha: f64, dg: *f64) -> f64 {
    if expfun {
        let ex = math.exp[f64](-(v * v) / 2.0f64)
        *dg = (1.0f64 - v * v) * ex
        ret v * ex
    }
    let th = fdl.tanh64(alpha * v)
    *dg = alpha * (1.0f64 - th * th)
    ret th
}

// ica.R.par: the symmetric iteration on the whitened e by n data x1; w (e by e) starts at w.init and ends as the unmixing matrix
fn ica_par(a: *mem.Arena, x1: []const f64, e: usize, n: usize, expfun: bool, alpha: f64, maxit: usize, tol: f64, w: []f64) -> err {
    let (w0, e1) = mem.alloc[f64](a, e * e)
    let (wx, e2) = mem.alloc[f64](a, e * n)
    let (gw, e3) = mem.alloc[f64](a, e * n)
    let (xt, e4) = mem.alloc[f64](a, n * e)
    let (v1, e5) = mem.alloc[f64](a, e * e)
    let (w1, e6) = mem.alloc[f64](a, e * e)
    let (w2, e7) = mem.alloc[f64](a, e * e)
    let (dm, e8) = mem.alloc[f64](a, e)
    let (row, e9) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret mem.Full }
    var q = 0usize
    while q < e * e {
        w0[q] = w[q]
        q += 1usize
    }
    let oe = ica_orthog(a, w0, e, w)
    if oe != ok { ret oe }
    fi.fica_tr(x1, e, n, xt)
    var lim = 1000.0f64
    var it = 1usize
    while lim > tol && it < maxit {
        let start = mem.mark(a)
        fi.fica_mm(w, x1, e, e, n, wx)
        var i = 0usize
        while i < e {
            var j = 0usize
            while j < n {
                var dg = 0.0f64
                gw[i + j * e] = ica_g(wx[i + j * e], expfun, alpha, &dg)
                row[j] = dg
                j += 1usize
            }
            dm[i] = ct.pp_mean(row)
            i += 1usize
        }
        fi.fica_mm(gw, xt, e, n, e, v1)
        i = 0usize
        while i < e {
            var j = 0usize
            while j < e {
                w1[i + j * e] = v1[i + j * e] / f64(n) - dm[i] * w[i + j * e]
                j += 1usize
            }
            i += 1usize
        }
        let pe = ica_orthog(a, w1, e, w2)
        if pe != ok { ret pe }
        // lim = max over i of | |(w2 w')[i, i]| - 1 |
        var mx = 0.0f64
        i = 0usize
        while i < e {
            var d = 0.0f64
            var k = 0usize
            while k < e {
                d += w2[i + k * e] * w[i + k * e]
                k += 1usize
            }
            let dv = math.abs[f64](math.abs[f64](d) - 1.0f64)
            if dv > mx { mx = dv }
            i += 1usize
        }
        lim = mx
        q = 0usize
        while q < e * e {
            w[q] = w2[q]
            q += 1usize
        }
        mem.reset(a, start)
        it += 1usize
    }
    ret ok
}

// ica.R.def: one component at a time, each orthogonalised against the earlier rows of w
fn ica_def(a: *mem.Arena, x1: []const f64, e: usize, n: usize, expfun: bool, alpha: f64, maxit: usize, tol: f64, winit: []const f64, w: []f64) -> err {
    let (cur, e1) = mem.alloc[f64](a, e)
    let (nxt, e2) = mem.alloc[f64](a, e)
    let (v1, e3) = mem.alloc[f64](a, e)
    let (col, e4) = mem.alloc[f64](a, n)
    let (dcol, e5) = mem.alloc[f64](a, n)
    let (row, e6) = mem.alloc[f64](a, n)
    let (ks, e7) = mem.alloc[f64](a, e)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret mem.Full }
    var i = 0usize
    while i < e {
        var j = 0usize
        while j < e {
            cur[j] = winit[i + j * e]
            j += 1usize
        }
        ica_deflate(cur, w, e, i, ks)
        ica_unit(cur, e)
        var lim = 1000.0f64
        var it = 1usize
        while lim > tol && it < maxit {
            var k = 0usize
            while k < n {
                var s = 0.0f64
                j = 0usize
                while j < e {
                    s += cur[j] * x1[j + k * e]
                    j += 1usize
                }
                var dg = 0.0f64
                col[k] = ica_g(s, expfun, alpha, &dg)
                dcol[k] = dg
                k += 1usize
            }
            j = 0usize
            while j < e {
                k = 0usize
                while k < n {
                    row[k] = x1[j + k * e] * col[k]
                    k += 1usize
                }
                v1[j] = ct.pp_mean(row)
                j += 1usize
            }
            let m2 = ct.pp_mean(dcol)
            j = 0usize
            while j < e {
                nxt[j] = v1[j] - m2 * cur[j]
                j += 1usize
            }
            it += 1usize
            ica_deflate(nxt, w, e, i, ks)
            ica_unit(nxt, e)
            var dot = 0.0f64
            j = 0usize
            while j < e {
                dot += nxt[j] * cur[j]
                j += 1usize
            }
            lim = math.abs[f64](math.abs[f64](dot) - 1.0f64)
            j = 0usize
            while j < e {
                cur[j] = nxt[j]
                j += 1usize
            }
        }
        j = 0usize
        while j < e {
            w[i + j * e] = cur[j]
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// v - sum over the earlier rows u < i of (v . w[u, ]) w[u, ], every dot taken from the incoming v (ks is scratch of length e)
fn ica_deflate(v: []f64, w: []const f64, e: usize, i: usize, ks: []f64) {
    var u = 0usize
    while u < i {
        var k = 0.0f64
        var q = 0usize
        while q < e {
            k += v[q] * w[u + q * e]
            q += 1usize
        }
        ks[u] = k
        u += 1usize
    }
    var j = 0usize
    while j < e {
        var t = 0.0f64
        u = 0usize
        while u < i {
            t += ks[u] * w[u + j * e]
            u += 1usize
        }
        v[j] = v[j] - t
        j += 1usize
    }
}

fn ica_unit(v: []f64, e: usize) {
    var s = 0.0f64
    var j = 0usize
    while j < e {
        s += v[j] * v[j]
        j += 1usize
    }
    let r = math.sqrt[f64](s)
    j = 0usize
    while j < e {
        v[j] = v[j] / r
        j += 1usize
    }
}

// x is n by p column-major, newx nx by p, the rows to transform. kout (p by e) and wout (e by e) are fastICA's K and W, scores (nx by e) = scaled(newx) K W.
// The generator is seeded by the caller (set.seed in R). deflate and expfun are alg.typ = "deflation" and fun = "exp"; tol (default 1e-4) and maxit (default 200) as in R.
fn pre_process_ica(a: *mem.Arena, r: *rng.Rng, x: []const f64, n: usize, p: usize, e: usize, deflate: bool, expfun: bool, alpha: f64, maxit: usize, tol: f64, newx: []const f64, nx: usize, kout: []f64, wout: []f64, scores: []f64) -> err {
    let (xs, e1) = mem.alloc[f64](a, n * p)
    let (ns, e2) = mem.alloc[f64](a, nx * p)
    let (wi, e3) = mem.alloc[f64](a, e * e)
    let (xt, e4) = mem.alloc[f64](a, p * n)
    let (cov, e5) = mem.alloc[f64](a, p * p)
    let (sv, e6) = mem.alloc[f64](a, p)
    let (uu, e7) = mem.alloc[f64](a, p * p)
    let (vv, e8) = mem.alloc[f64](a, p * p)
    let (k1, e9) = mem.alloc[f64](a, e * p)
    let (x1, e10) = mem.alloc[f64](a, e * n)
    let (xc, e11) = mem.alloc[f64](a, n * p)
    let (wa, e12) = mem.alloc[f64](a, e * e)
    let (xk, e13) = mem.alloc[f64](a, nx * e)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok { ret mem.Full }
    // caret: centre and scale each column (training moments for both sets)
    var c = 0usize
    while c < p {
        let col = x[c * n..c * n + n]
        let m = ct.pp_mean(col)
        let sd = ct.pp_sd(col)
        var i = 0usize
        while i < n {
            xs[c * n + i] = (col[i] - m) / sd
            i += 1usize
        }
        i = 0usize
        while i < nx {
            ns[c * nx + i] = (newx[c * nx + i] - m) / sd
            i += 1usize
        }
        c += 1usize
    }
    // fastICA, method "R": centre again, whiten with the first e left singular vectors of the p by p covariance
    c = 0usize
    while c < p {
        let m = ct.pp_mean(xs[c * n..c * n + n])
        var i = 0usize
        while i < n {
            xc[c * n + i] = xs[c * n + i] - m
            i += 1usize
        }
        c += 1usize
    }
    fi.fica_tr(xc, n, p, xt)
    fi.fica_mm(xt, xc, p, n, p, cov)
    var q = 0usize
    while q < p * p {
        cov[q] = cov[q] / f64(n)
        q += 1usize
    }
    let se = lapack.svd_all(a, cov, p, p, sv, uu, vv)
    if se != ok { ret se }
    var i2 = 0usize
    while i2 < e {
        let sc = 1.0f64 / math.sqrt[f64](sv[i2])
        var j = 0usize
        while j < p {
            k1[i2 + j * e] = sc * uu[j + i2 * p]
            j += 1usize
        }
        i2 += 1usize
    }
    fi.fica_mm(k1, xt, e, p, n, x1)
    q = 0usize
    while q < e * e {
        wi[q] = rng.norm(r)
        q += 1usize
    }
    if deflate {
        let de = ica_def(a, x1, e, n, expfun, alpha, maxit, tol, wi, wa)
        if de != ok { ret de }
    } else {
        q = 0usize
        while q < e * e {
            wa[q] = wi[q]
            q += 1usize
        }
        let pe = ica_par(a, x1, e, n, expfun, alpha, maxit, tol, wa)
        if pe != ok { ret pe }
    }
    fi.fica_tr(k1, e, p, kout)
    fi.fica_tr(wa, e, e, wout)
    fi.fica_mm(ns, kout, nx, p, e, xk)
    fi.fica_mm(xk, wout, nx, e, e, scores)
    ret ok
}

// ---- varImp(randomForest) of a forest grown with importance = TRUE: importance(object) with its scale = TRUE (a permutation column divided by its standard error,
// left alone when that is below the machine epsilon). Regression answers the scaled %IncMSE (out has p slots); classification answers the scaled per-class columns (p by kc,
// column-major), and for two classes both columns become their mean. ----
fn rf_scaled(v: f64, sd: f64) -> f64 {
    if sd < 2.220446049250313e-16f64 { ret v }
    ret v / sd
}

fn var_imp_rf_reg(f: *const rfm.Fit, p: usize, out: []f64) {
    var m = 0usize
    while m < p {
        out[m] = rf_scaled(f.imp[m], f.impsd[m])
        m += 1usize
    }
}

fn var_imp_rf_class(f: *const rfm.Fit, p: usize, kc: usize, out: []f64) {
    var c = 0usize
    while c < kc {
        var m = 0usize
        while m < p {
            out[c * p + m] = rf_scaled(f.cimp[c * p + m], f.impsd[c * p + m])
            m += 1usize
        }
        c += 1usize
    }
    if kc == 2usize {
        var m = 0usize
        while m < p {
            let mean = (out[m] + out[p + m]) / 2.0f64
            out[m] = mean
            out[p + m] = mean
            m += 1usize
        }
    }
}

// ---- varImp(multinom): the absolute coefficients summed over the nk - 1 class rows, intercept dropped. coef is nnet.multinom's (nk - 1) by p row-major matrix with the
// intercept in column 0; out has p - 1 slots. ----
fn var_imp_multinom(coef: []const f64, nk: usize, p: usize, out: []f64) {
    var j = 1usize
    while j < p {
        var s = 0.0f64
        var k = 0usize
        while k + 1usize < nk {
            s += math.abs[f64](coef[k * p + j])
            k += 1usize
        }
        out[j - 1usize] = s
        j += 1usize
    }
}

// ---- varImp(rpart): the sum of the improve column of object$splits per variable, over the primary splits, the competing ones unless competes = FALSE and the
// surrogate ones when surrogates = TRUE (a variable no split uses gets 0). out has one slot per predictor, in column order. ----
fn var_imp_rpart(v: *const rf.View, surrogates: bool, competes: bool, out: []f64) {
    var j = 0usize
    while j < v.p {
        out[j] = 0.0f64
        j += 1usize
    }
    var r = 0usize
    var s = 0usize
    while r < v.nfr {
        if v.fvar[r] != 0usize {
            out[v.sp_var[s] - 1usize] += v.sp_imp[s]
            s += 1usize
            var q = 0usize
            while q < v.fncomp[r] {
                if competes { out[v.sp_var[s] - 1usize] += v.sp_imp[s] }
                s += 1usize
                q += 1usize
            }
            q = 0usize
            while q < v.fnsur[r] {
                if surrogates { out[v.sp_var[s] - 1usize] += v.sp_imp[s] }
                s += 1usize
                q += 1usize
            }
        }
        r += 1usize
    }
}

// ---- varImp(nnet): caret's GarsonWeights on the weight vector of nnet(size = h) with p inputs and k outputs (the unit-by-unit layout of nnet_fit). Each output's importance is
// the share (in percent) of the input in the sum over hidden units of |input to hidden| * |hidden to output| normalised per hidden unit; one output answers one column
// (Overall), several answer Overall = the row mean first and then one column per output. out is p by (1 or k + 1), column-major. ----
fn var_imp_nnet(a: *mem.Arena, wts: []const f64, p: usize, h: usize, k: usize, skip: bool, out: []f64) -> err {
    let (q, e1) = mem.alloc[f64](a, h * p)
    let (sj, e2) = mem.alloc[f64](a, p)
    let (row, e3) = mem.alloc[f64](a, k)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var per = 1usize + h
    if skip { per += p }
    var off = 0usize
    if k > 1usize { off = p }
    var o = 0usize
    while o < k {
        let base = h * (p + 1usize) + o * per
        var u = 0usize
        while u < h {
            let ho = math.abs[f64](wts[base + 1usize + u])
            var tot = 0.0f64
            var i = 0usize
            while i < p {
                let pij = math.abs[f64](wts[u * (p + 1usize) + 1usize + i]) * ho
                q[u * p + i] = pij
                tot += pij
                i += 1usize
            }
            i = 0usize
            while i < p {
                q[u * p + i] = q[u * p + i] / tot
                i += 1usize
            }
            u += 1usize
        }
        var all = 0.0f64
        var i = 0usize
        while i < p {
            var s = 0.0f64
            var u2 = 0usize
            while u2 < h {
                s += q[u2 * p + i]
                u2 += 1usize
            }
            sj[i] = s
            all += s
            i += 1usize
        }
        i = 0usize
        while i < p {
            out[off + o * p + i] = sj[i] / all * 100.0f64
            i += 1usize
        }
        o += 1usize
    }
    if k > 1usize {
        var i = 0usize
        while i < p {
            var c = 0usize
            while c < k {
                row[c] = out[p + c * p + i]
                c += 1usize
            }
            out[i] = ct.pp_mean(row)
            i += 1usize
        }
    }
    ret ok
}

// ---- varImp(glm(family = f(link = l))): glm.fit's IRLS, then the absolute z or t value of each non-intercept coefficient ----
// family 0 binomial, 1 poisson, 2 gaussian, 3 Gamma, 4 inverse.gaussian; link 0 logit, 1 probit, 2 cauchit, 3 cloglog, 4 log, 5 identity, 6 inverse, 7 sqrt, 8 1/mu^2

fn glm_eps() -> f64 { ret 2.220446049250313e-16f64 }

fn glm_linkfun(link: usize, mu: f64) -> f64 {
    if link == 0usize { ret math.log[f64](mu / (1.0f64 - mu)) }
    if link == 1usize { ret dist.qnorm(mu, 0.0f64, 1.0f64, true, false) }
    if link == 2usize { ret dist.qcauchy(mu, 0.0f64, 1.0f64, true, false) }
    if link == 3usize { ret math.log[f64](0.0f64 - math.log[f64](1.0f64 - mu)) }
    if link == 4usize { ret math.log[f64](mu) }
    if link == 5usize { ret mu }
    if link == 6usize { ret 1.0f64 / mu }
    if link == 7usize { ret math.sqrt[f64](mu) }
    ret 1.0f64 / (mu * mu)
}

fn glm_linkinv(link: usize, eta: f64) -> f64 {
    let eps = glm_eps()
    if link == 0usize {
        var t = 0.0f64
        if eta < -30.0f64 { t = eps } else if eta > 30.0f64 { t = 1.0f64 / eps } else { t = math.exp[f64](eta) }
        ret t / (1.0f64 + t)
    }
    if link == 1usize {
        let th = 0.0f64 - dist.qnorm(eps, 0.0f64, 1.0f64, true, false)
        var v = eta
        if v < 0.0f64 - th { v = 0.0f64 - th }
        if v > th { v = th }
        ret dist.pnorm(v, 0.0f64, 1.0f64, true, false)
    }
    if link == 2usize {
        let th = 0.0f64 - dist.qcauchy(eps, 0.0f64, 1.0f64, true, false)
        var v = eta
        if v < 0.0f64 - th { v = 0.0f64 - th }
        if v > th { v = th }
        ret dist.pcauchy(v, 0.0f64, 1.0f64, true, false)
    }
    if link == 3usize {
        var v = 0.0f64 - dist.expm1(0.0f64 - math.exp[f64](eta))
        if v > 1.0f64 - eps { v = 1.0f64 - eps }
        if v < eps { v = eps }
        ret v
    }
    if link == 4usize {
        let v = math.exp[f64](eta)
        if v < eps { ret eps }
        ret v
    }
    if link == 5usize { ret eta }
    if link == 6usize { ret 1.0f64 / eta }
    if link == 7usize { ret eta * eta }
    ret 1.0f64 / math.sqrt[f64](eta)
}

fn glm_mu_eta(link: usize, eta: f64) -> f64 {
    let eps = glm_eps()
    if link == 0usize {
        if eta > 30.0f64 || eta < -30.0f64 { ret eps }
        let op = 1.0f64 + math.exp[f64](eta)
        ret math.exp[f64](eta) / (op * op)
    }
    if link == 1usize {
        let d = dist.dnorm(eta, 0.0f64, 1.0f64, false)
        if d < eps { ret eps }
        ret d
    }
    if link == 2usize {
        let d = dist.dcauchy(eta, 0.0f64, 1.0f64, false)
        if d < eps { ret eps }
        ret d
    }
    if link == 3usize {
        var v = eta
        if v > 700.0f64 { v = 700.0f64 }
        let d = math.exp[f64](v) * math.exp[f64](0.0f64 - math.exp[f64](v))
        if d < eps { ret eps }
        ret d
    }
    if link == 4usize {
        let v = math.exp[f64](eta)
        if v < eps { ret eps }
        ret v
    }
    if link == 5usize { ret 1.0f64 }
    if link == 6usize { ret 0.0f64 - 1.0f64 / (eta * eta) }
    if link == 7usize { ret 2.0f64 * eta }
    ret 0.0f64 - 1.0f64 / (2.0f64 * eta * math.sqrt[f64](eta))
}

fn glm_variance(fam: usize, mu: f64) -> f64 {
    if fam == 0usize { ret mu * (1.0f64 - mu) }
    if fam == 1usize { ret mu }
    if fam == 2usize { ret 1.0f64 }
    if fam == 3usize { ret mu * mu }
    ret mu * mu * mu
}

fn glm_dev_resid(fam: usize, y: f64, mu: f64) -> f64 {
    if fam == 0usize {
        var d = 0.0f64
        if y > 0.0f64 { d += y * math.log[f64](y / mu) }
        if y < 1.0f64 { d += (1.0f64 - y) * math.log[f64]((1.0f64 - y) / (1.0f64 - mu)) }
        ret 2.0f64 * d
    }
    if fam == 1usize {
        var d = 0.0f64
        if y > 0.0f64 { d = y * math.log[f64](y / mu) }
        ret 2.0f64 * (d - (y - mu))
    }
    if fam == 2usize { ret (y - mu) * (y - mu) }
    if fam == 3usize { ret 0.0f64 - 2.0f64 * (math.log[f64](y / mu) - (y - mu) / mu) }
    ret (y - mu) * (y - mu) / (y * mu * mu)
}

fn glm_mustart(fam: usize, y: f64) -> f64 {
    if fam == 0usize { ret (y + 0.5f64) / 2.0f64 }
    if fam == 1usize { ret y + 0.1f64 }
    ret y
}

fn var_imp_glm(a: *mem.Arena, x: []const f64, n: usize, p: usize, y: []const f64, fam: usize, link: usize, out: []f64) -> err {
    let (beta, e1) = mem.alloc[f64](a, p)
    let (xtwx, e2) = mem.alloc[f64](a, p * p)
    let (u, e3) = mem.alloc[f64](a, p * p)
    let (iu, e4) = mem.alloc[f64](a, p * p)
    let (g, e5) = mem.alloc[f64](a, p)
    let (eta, e6) = mem.alloc[f64](a, n)
    let (wl, e7) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret mem.Full }
    var i = 0usize
    var devold = 0.0f64
    while i < n {
        eta[i] = glm_linkfun(link, glm_mustart(fam, y[i]))
        devold += glm_dev_resid(fam, y[i], glm_linkinv(link, eta[i]))
        i += 1usize
    }
    var it = 0usize
    while it < 25usize {
        var j = 0usize
        while j < p {
            g[j] = 0.0f64
            var k = 0usize
            while k < p {
                xtwx[k * p + j] = 0.0f64
                k += 1usize
            }
            j += 1usize
        }
        i = 0usize
        while i < n {
            let mu = glm_linkinv(link, eta[i])
            let me = glm_mu_eta(link, eta[i])
            let w = me * me / glm_variance(fam, mu)
            wl[i] = w
            let z = eta[i] + (y[i] - mu) / me
            j = 0usize
            while j < p {
                g[j] += w * x[j * n + i] * z
                var k = 0usize
                while k < p {
                    xtwx[k * p + j] += w * x[j * n + i] * x[k * n + i]
                    k += 1usize
                }
                j += 1usize
            }
            i += 1usize
        }
        if !bz.chol_upper(xtwx, p, u) { ret mem.Full }
        bz.inv_upper(u, p, iu)
        j = 0usize
        while j < p {
            var t = 0.0f64
            var q = j
            while q < p {
                var s2 = 0.0f64
                var r = 0usize
                while r <= q {
                    s2 += iu[q * p + r] * g[r]
                    r += 1usize
                }
                t += iu[q * p + j] * s2
                q += 1usize
            }
            beta[j] = t
            j += 1usize
        }
        var dev = 0.0f64
        i = 0usize
        while i < n {
            var e = 0.0f64
            j = 0usize
            while j < p {
                e += x[j * n + i] * beta[j]
                j += 1usize
            }
            eta[i] = e
            dev += glm_dev_resid(fam, y[i], glm_linkinv(link, e))
            i += 1usize
        }
        it += 1usize
        if math.abs[f64](dev - devold) / (math.abs[f64](dev) + 0.1f64) < 1.0e-8f64 { break }
        devold = dev
    }
    // the dispersion: 1 for binomial and poisson, else the Pearson sum of the last working weights times the final working residuals squared over n - p
    var disp = 1.0f64
    if fam >= 2usize {
        var s = 0.0f64
        i = 0usize
        while i < n {
            let r = (y[i] - glm_linkinv(link, eta[i])) / glm_mu_eta(link, eta[i])
            s += wl[i] * r * r
            i += 1usize
        }
        disp = s / f64(n - p)
    }
    var j = 1usize
    while j < p {
        var v = 0.0f64
        var q = j
        while q < p {
            v += iu[q * p + j] * iu[q * p + j]
            q += 1usize
        }
        out[j - 1usize] = math.abs[f64](beta[j] / math.sqrt[f64](disp * v))
        j += 1usize
    }
    ret ok
}

