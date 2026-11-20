// R topicmodels::CTM(method = "VEM") on a document-term count matrix (docs by terms, row-major): the correlated topic model by variational EM as the package's C code runs it, including GSL's taus generator for the initial
// model, the Fletcher-Reeves conjugate gradient (gsl_multimin_fdfminimizer_conjugate_fr) for lambda, and the Newton steps for nu.
//
// Not here: the shrinkage covariance (the package leaves it off), seeds past one start, files saved while fitting.

use e.algo.stat.topicmodels as tm
use e.math
use e.mem

const NUM_INIT_DOCS: usize = 1usize

// gsl_rng_taus
type Taus = struct { s1: u64, s2: u64, s3: u64 }

// the fitted model and the per-document variational state of the last E-step
type Ctm = struct {
    k: usize, nv: usize, nd: usize, iter: usize, nlog: usize,
    logb: []f64, mu: []f64, cov: []f64, ic: []f64, ldic: f64,
    lambda: []f64, nu: []f64, llh: []f64, logliks: []f64, wa: []usize,
    wl: []f64, wn: []f64, phi: []f64, lphi: []f64, zeta: f64, lhood: f64, niter: i64,
    var_tol: f64, var_max: i64, cg_tol: f64, cg_max: i64, f0: f64,
    sphi: []f64, t0: []f64, t1: []f64, t2: []f64, t3: []f64, tot: f64,
    cx: []f64, cx1: []f64, cdx1: []f64, cx2: []f64, cdx: []f64, cp: []f64, cg0: []f64, cgr: []f64,
    ss_mu: []f64, ss_cov: []f64, ss_beta: []f64, ndata: f64,
    ds: []f64, dn: []f64
}

const MASK: u64 = 4294967295u64

fn taus_get(t: *Taus) -> u64 {
    t.s1 = (((t.s1 & 4294967294u64) << 12u64) & MASK) ^ ((((t.s1 << 13u64) & MASK) ^ t.s1) >> 19u64)
    t.s2 = (((t.s2 & 4294967288u64) << 4u64) & MASK) ^ ((((t.s2 << 2u64) & MASK) ^ t.s2) >> 25u64)
    t.s3 = (((t.s3 & 4294967280u64) << 17u64) & MASK) ^ ((((t.s3 << 3u64) & MASK) ^ t.s3) >> 11u64)
    ret t.s1 ^ t.s2 ^ t.s3
}

fn taus_set(t: *Taus, seed: i64) {
    var s = u64(seed) & MASK
    if s == 0u64 { s = 1u64 }
    t.s1 = (69069u64 * s) & MASK
    if t.s1 < 2u64 { t.s1 += 2u64 }
    t.s2 = (69069u64 * t.s1) & MASK
    if t.s2 < 8u64 { t.s2 += 8u64 }
    t.s3 = (69069u64 * t.s2) & MASK
    if t.s3 < 16u64 { t.s3 += 16u64 }
    var i = 0usize
    while i < 6usize {
        let _ = taus_get(t)
        i += 1usize
    }
}

fn taus_uniform(t: *Taus) -> f64 { ret f64(taus_get(t)) / 4294967296.0f64 }

fn safe_log(x: f64) -> f64 {
    if x == 0.0f64 { ret 0.0f64 - 1000.0f64 }
    ret math.log[f64](x)
}

// LU decomposition with partial pivoting, in place; perm records the row order
fn lu_decomp(m: []f64, n: usize, perm: []usize) {
    var i = 0usize
    while i < n {
        perm[i] = i
        i += 1usize
    }
    var j = 0usize
    while j + 1usize < n {
        var piv = j
        var mx = math.abs[f64](m[j * n + j])
        i = j + 1usize
        while i < n {
            let v = math.abs[f64](m[i * n + j])
            if v > mx {
                mx = v
                piv = i
            }
            i += 1usize
        }
        if piv != j {
            var c = 0usize
            while c < n {
                let t = m[j * n + c]
                m[j * n + c] = m[piv * n + c]
                m[piv * n + c] = t
                c += 1usize
            }
            let tp = perm[j]
            perm[j] = perm[piv]
            perm[piv] = tp
        }
        let ajj = m[j * n + j]
        if ajj != 0.0f64 {
            i = j + 1usize
            while i < n {
                let aij = m[i * n + j] / ajj
                m[i * n + j] = aij
                var c = j + 1usize
                while c < n {
                    m[i * n + c] = m[i * n + c] - aij * m[j * n + c]
                    c += 1usize
                }
                i += 1usize
            }
        }
        j += 1usize
    }
}

// inverse and log |det| of a square matrix through the LU decomposition (a is not changed)
fn invert(a: *mem.Arena, m: []const f64, n: usize, inv: []f64) -> (f64, err) {
    let (lu, e1) = tm.zeros(a, n * n)
    let (pm, e2) = tm.zeros_u(a, n)
    let (b, e3) = tm.zeros(a, n)
    if e1 != ok { ret (0.0f64, e1) }
    if e2 != ok { ret (0.0f64, e2) }
    if e3 != ok { ret (0.0f64, e3) }
    var i = 0usize
    while i < n * n {
        lu[i] = m[i]
        i += 1usize
    }
    lu_decomp(lu, n, pm)
    var c = 0usize
    while c < n {
        i = 0usize
        while i < n {
            b[i] = 0.0f64
            if pm[i] == c { b[i] = 1.0f64 }
            i += 1usize
        }
        i = 1usize
        while i < n {
            var s = b[i]
            var j = 0usize
            while j < i {
                s -= lu[i * n + j] * b[j]
                j += 1usize
            }
            b[i] = s
            i += 1usize
        }
        i = n
        while i > 0usize {
            i -= 1usize
            var s = b[i]
            var j = i + 1usize
            while j < n {
                s -= lu[i * n + j] * b[j]
                j += 1usize
            }
            b[i] = s / lu[i * n + i]
        }
        i = 0usize
        while i < n {
            inv[i * n + c] = b[i]
            i += 1usize
        }
        c += 1usize
    }
    var ld = 0.0f64
    i = 0usize
    while i < n {
        ld += math.log[f64](math.abs[f64](lu[i * n + i]))
        i += 1usize
    }
    ret (ld, ok)
}

fn ddot(x: []const f64, y: []const f64, n: usize) -> f64 {
    var r = 0.0f64
    var i = 0usize
    while i < n {
        r += x[i] * y[i]
        i += 1usize
    }
    ret r
}

fn dnrm2(x: []const f64, n: usize) -> f64 {
    if n == 0usize { ret 0.0f64 }
    if n == 1usize { ret math.abs[f64](x[0usize]) }
    var scale = 0.0f64
    var ssq = 1.0f64
    var i = 0usize
    while i < n {
        let v = x[i]
        if v != 0.0f64 {
            let ax = math.abs[f64](v)
            if scale < ax {
                ssq = 1.0f64 + ssq * (scale / ax) * (scale / ax)
                scale = ax
            } else {
                ssq += (ax / scale) * (ax / scale)
            }
        }
        i += 1usize
    }
    ret scale * math.sqrt[f64](ssq)
}

// y = A x for a symmetric A of which only the upper (upper true) or lower triangle is read, as cblas_dsymv does it row-major with alpha 1 and beta 0
fn dsymv(m: []const f64, x: []const f64, y: []f64, n: usize, upper: bool) {
    var i = 0usize
    while i < n {
        y[i] = 0.0f64
        i += 1usize
    }
    if upper {
        i = 0usize
        while i < n {
            let t1 = x[i]
            var t2 = 0.0f64
            y[i] += t1 * m[i * n + i]
            var j = i + 1usize
            while j < n {
                y[j] += t1 * m[i * n + j]
                t2 += x[j] * m[i * n + j]
                j += 1usize
            }
            y[i] += t2
            i += 1usize
        }
    } else {
        i = n
        while i > 0usize {
            i -= 1usize
            let t1 = x[i]
            var t2 = 0.0f64
            y[i] += t1 * m[i * n + i]
            var j = 0usize
            while j < i {
                y[j] += t1 * m[i * n + j]
                t2 += x[j] * m[i * n + j]
                j += 1usize
            }
            y[i] += t2
        }
    }
}

// the objective of lambda (negated bound) and its gradient, for the current document
fn f_lambda(r: *Ctm, p: []const f64) -> f64 {
    let n = r.k - 1usize
    let term1 = ddot(p, r.sphi, n)
    var i = 0usize
    while i < n {
        r.t1[i] = p[i] + (0.0f64 - 1.0f64) * r.mu[i]
        i += 1usize
    }
    dsymv(r.ic, r.t1, r.t2, n, true)
    var term2 = ddot(r.t2, r.t1, n)
    term2 = 0.0f64 - 0.5f64 * term2
    var term3 = 0.0f64
    i = 0usize
    while i < n {
        term3 += math.exp[f64](p[i] + 0.5f64 * r.wn[i])
        i += 1usize
    }
    term3 = 0.0f64 - ((1.0f64 / r.zeta) * term3 - 1.0f64 + math.log[f64](r.zeta)) * r.tot
    ret 0.0f64 - (term1 + term2 + term3)
}

fn df_lambda(r: *Ctm, p: []const f64, df: []f64) {
    let n = r.k - 1usize
    var i = 0usize
    while i < n {
        r.t0[i] = 0.0f64
        r.t1[i] = r.mu[i] - p[i]
        i += 1usize
    }
    dsymv(r.ic, r.t1, r.t0, n, false)
    i = 0usize
    while i < n {
        r.t3[i] = 0.0f64 - (r.tot / r.zeta) * math.exp[f64](p[i] + 0.5f64 * r.wn[i])
        i += 1usize
    }
    i = 0usize
    while i < n {
        df[i] = 0.0f64
        df[i] = df[i] - r.t0[i]
        df[i] = df[i] - r.sphi[i]
        df[i] = df[i] - r.t3[i]
        i += 1usize
    }
}

fn take_step(x: []const f64, p: []const f64, step: f64, lambda: f64, x1: []f64, dx: []f64, n: usize) {
    var i = 0usize
    while i < n {
        dx[i] = 0.0f64 + (0.0f64 - step * lambda) * p[i]
        x1[i] = x[i]
        x1[i] = x1[i] + dx[i]
        i += 1usize
    }
}

fn same(a: []const f64, b: []const f64, n: usize) -> bool {
    var i = 0usize
    while i < n {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn copy(dst: []f64, src: []const f64, n: usize) {
    var i = 0usize
    while i < n {
        dst[i] = src[i]
        i += 1usize
    }
}

// the Fletcher-Reeves state that outlives one iteration
type CgState = struct { iter: usize, step: f64, tol: f64, pnorm: f64, g0norm: f64, f: f64 }

// gsl's intermediate_point: returns (stepb, fb)
fn cg_intermediate(r: *Ctm, lambda: f64, pg: f64, stepa: f64, stepc0: f64, fa: f64, fc0: f64) -> (f64, f64) {
    let n = r.k - 1usize
    var stepc = stepc0
    var fc = fc0
    var stepb = 0.0f64
    var fb = 0.0f64
    var go = true
    while go {
        let u = math.abs[f64](pg * lambda * stepc)
        stepb = 0.5f64 * stepc * u / ((fc - fa) + u)
        take_step(r.cx, r.cp, stepb, lambda, r.cx1, r.cdx1, n)
        if same(r.cx, r.cx1, n) {
            df_lambda(r, r.cx1, r.cgr)
            ret (0.0f64, fa)
        }
        fb = f_lambda(r, r.cx1)
        if fb >= fa && stepb > 0.0f64 {
            fc = fb
            stepc = stepb
        } else {
            go = false
        }
    }
    df_lambda(r, r.cx1, r.cgr)
    ret (stepb, fb)
}

// gsl's minimize: Brent-style bracketing along p; returns (step, f, gnorm) and leaves the point in cx2 / cdx
fn cg_minimize(r: *Ctm, lambda: f64, stepa0: f64, stepb0: f64, stepc0: f64, fa0: f64, fb0: f64, fc0: f64, tol: f64, step_in: f64, f_in: f64, g_in: f64) -> (f64, f64, f64) {
    let n = r.k - 1usize
    var stepa = stepa0
    var stepb = stepb0
    var stepc = stepc0
    var fa = fa0
    var fb = fb0
    var fc = fc0
    var u = stepb
    var v = stepa
    var w = stepc
    var fu = fb
    var fv = fa
    var fw = fc
    var old2 = math.abs[f64](w - v)
    var old1 = math.abs[f64](v - u)
    var ostep = step_in
    var of = f_in
    var og = g_in
    copy(r.cx2, r.cx1, n)
    copy(r.cdx, r.cdx1, n)
    var it = 0i64
    var go = true
    while go {
        it += 1i64
        if it > 10i64 {
            go = false
        } else {
            let dw = w - u
            let dv = v - u
            var du = 0.0f64
            let e1 = (fv - fu) * dw * dw + (fu - fw) * dv * dv
            let e2 = 2.0f64 * ((fv - fu) * dw + (fu - fw) * dv)
            if e2 != 0.0f64 { du = e1 / e2 }
            var stepm = 0.0f64
            if du > 0.0f64 && du < (stepc - stepb) && math.abs[f64](du) < 0.5f64 * old2 {
                stepm = u + du
            } else if du < 0.0f64 && du > (stepa - stepb) && math.abs[f64](du) < 0.5f64 * old2 {
                stepm = u + du
            } else if (stepc - stepb) > (stepb - stepa) {
                stepm = 0.38f64 * (stepc - stepb) + stepb
            } else {
                stepm = stepb - 0.38f64 * (stepb - stepa)
            }
            take_step(r.cx, r.cp, stepm, lambda, r.cx1, r.cdx1, n)
            let fm = f_lambda(r, r.cx1)
            if fm > fb {
                if fm < fv {
                    w = v
                    v = stepm
                    fw = fv
                    fv = fm
                } else if fm < fw {
                    w = stepm
                    fw = fm
                }
                if stepm < stepb {
                    stepa = stepm
                    fa = fm
                } else {
                    stepc = stepm
                    fc = fm
                }
            } else {
                old2 = old1
                old1 = math.abs[f64](u - stepm)
                w = v
                v = u
                u = stepm
                fw = fv
                fv = fu
                fu = fm
                copy(r.cx2, r.cx1, n)
                copy(r.cdx, r.cdx1, n)
                df_lambda(r, r.cx1, r.cgr)
                let pg = ddot(r.cp, r.cgr, n)
                let gnorm1 = dnrm2(r.cgr, n)
                of = fm
                ostep = stepm
                og = gnorm1
                if math.abs[f64](pg * lambda / gnorm1) < tol {
                    go = false
                } else {
                    if stepm < stepb {
                        stepc = stepb
                        fc = fb
                        stepb = stepm
                        fb = fm
                    } else {
                        stepa = stepb
                        fa = fb
                        stepb = stepm
                        fb = fm
                    }
                }
            }
        }
    }
    ret (ostep, of, og)
}

// one conjugate_fr_iterate; returns 0 on success and 1 when no progress is possible. x is r.cx, the gradient r.cgr.
fn cg_iterate(r: *Ctm, st: *CgState) -> i64 {
    let n = r.k - 1usize
    let fa = st.f
    if st.pnorm == 0.0f64 || st.g0norm == 0.0f64 {
        var i = 0usize
        while i < n {
            r.cdx[i] = 0.0f64
            i += 1usize
        }
        ret 1i64
    }
    let pg = ddot(r.cp, r.cgr, n)
    var dir = 0.0f64 - 1.0f64
    if pg >= 0.0f64 { dir = 1.0f64 }
    let lam = dir / st.pnorm
    let stepc = st.step
    take_step(r.cx, r.cp, stepc, lam, r.cx1, r.cdx, n)
    let fc = f_lambda(r, r.cx1)
    if fc < fa {
        st.step = stepc * 2.0f64
        copy(r.cx, r.cx1, n)
        df_lambda(r, r.cx1, r.cgr)
        st.f = fc
        ret 0i64
    }
    let (stepb, fb) = cg_intermediate(r, lam, pg, 0.0f64, stepc, fa, fc)
    st.step = stepb
    st.f = fb
    if stepb == 0.0f64 { ret 1i64 }
    let (ns, nf, ng) = cg_minimize(r, lam, 0.0f64, stepb, stepc, fa, fb, fc, st.tol, st.step, st.f, st.g0norm)
    st.step = ns
    st.f = nf
    copy(r.cx, r.cx2, n)
    st.iter = (st.iter + 1usize) % n
    if st.iter == 0usize {
        copy(r.cp, r.cgr, n)
        st.pnorm = ng
    } else {
        let g0 = st.g0norm
        let beta = 0.0f64 - (ng / g0) * (ng / g0)
        var i = 0usize
        while i < n {
            r.cp[i] = r.cp[i] * (0.0f64 - beta)
            r.cp[i] = r.cp[i] + 1.0f64 * r.cgr[i]
            i += 1usize
        }
        st.pnorm = dnrm2(r.cp, n)
    }
    st.g0norm = ng
    copy(r.cg0, r.cgr, n)
    ret 0i64
}

fn opt_lambda(r: *Ctm, co: *const tm.Corpus, d: usize) {
    let n = r.k - 1usize
    let o = co.off[d]
    var j = 0usize
    while j < n {
        r.sphi[j] = 0.0f64
        var i = 0usize
        while i < co.off[d + 1usize] - o {
            r.sphi[j] = r.sphi[j] + co.c[o + i] * r.phi[(o + i) * r.k + j]
            i += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < n {
        r.cx[j] = r.wl[j]
        r.cp[j] = 0.0f64
        j += 1usize
    }
    var st: CgState = zero
    st.iter = 0usize
    st.step = 0.01f64
    st.tol = 0.001f64
    st.f = f_lambda(r, r.cx)
    df_lambda(r, r.cx, r.cgr)
    copy(r.cp, r.cgr, n)
    copy(r.cg0, r.cgr, n)
    let g = dnrm2(r.cgr, n)
    st.pnorm = g
    st.g0norm = g
    var iter = 0i64
    var go = true
    while go {
        iter += 1i64
        let status = cg_iterate(r, &st)
        if status != 0i64 {
            go = false
        } else {
            let gn = dnrm2(r.cgr, n)
            var cont = true
            if gn < r.cg_tol { cont = false }
            go = cont && (r.cg_max < 0i64 || iter < r.cg_max)
        }
    }
    j = 0usize
    while j < n {
        r.wl[j] = r.cx[j]
        j += 1usize
    }
    r.wl[n] = 0.0f64
}

fn opt_zeta(r: *Ctm) {
    r.zeta = 1.0f64
    var i = 0usize
    while i < r.k - 1usize {
        r.zeta += math.exp[f64](r.wl[i] + 0.5f64 * r.wn[i])
        i += 1usize
    }
}

fn opt_phi(r: *Ctm, co: *const tm.Corpus, d: usize) {
    let o = co.off[d]
    var n = 0usize
    while n < co.off[d + 1usize] - o {
        var ls = 0.0f64
        var i = 0usize
        while i < r.k {
            r.lphi[(o + n) * r.k + i] = r.wl[i] + r.logb[i * r.nv + co.w[o + n]]
            if i == 0usize {
                ls = r.lphi[(o + n) * r.k + i]
            } else {
                ls = tm.log_sum(ls, r.lphi[(o + n) * r.k + i])
            }
            i += 1usize
        }
        i = 0usize
        while i < r.k {
            r.lphi[(o + n) * r.k + i] = r.lphi[(o + n) * r.k + i] - ls
            r.phi[(o + n) * r.k + i] = math.exp[f64](r.lphi[(o + n) * r.k + i])
            i += 1usize
        }
        n += 1usize
    }
}

fn opt_nu(r: *Ctm) {
    var i = 0usize
    while i < r.k - 1usize {
        var init_nu = 10.0f64
        var log_nu = math.log[f64](init_nu)
        var df = 0.0f64
        var go = true
        while go {
            var nu_i = math.exp[f64](log_nu)
            if nu_i != nu_i {
                init_nu = init_nu * 2.0f64
                log_nu = math.log[f64](init_nu)
                nu_i = init_nu
            }
            let ex = math.exp[f64](r.wl[i] + nu_i / 2.0f64)
            df = 0.0f64 - (r.ic[i * (r.k - 1usize) + i] * 0.5f64) - (0.5f64 * (r.tot / r.zeta) * ex) + (0.5f64 * (1.0f64 / nu_i))
            let d2f = 0.0f64 - (0.25f64 * (r.tot / r.zeta) * ex) - (0.5f64 * (1.0f64 / (nu_i * nu_i)))
            log_nu = log_nu - (df * nu_i) / (d2f * nu_i * nu_i + df * nu_i)
            go = math.abs[f64](df) > 0.0000000001f64
        }
        r.wn[i] = math.exp[f64](log_nu)
        i += 1usize
    }
}

fn lhood_bnd(r: *Ctm, co: *const tm.Corpus, d: usize) {
    let k = r.k
    let n = k - 1usize
    var lh = 0.5f64 * r.ldic + 0.5f64 * f64(n)
    var i = 0usize
    while i < n {
        var v = 0.0f64 - 0.5f64 * r.wn[i] * r.ic[i * n + i]
        var j = 0usize
        while j < n {
            v -= 0.5f64 * (r.wl[i] - r.mu[i]) * r.ic[i * n + j] * (r.wl[j] - r.mu[j])
            j += 1usize
        }
        v += 0.5f64 * math.log[f64](r.wn[i])
        lh += v
        i += 1usize
    }
    var se = 0.0f64
    i = 0usize
    while i < k {
        se += math.exp[f64](r.wl[i] + 0.5f64 * r.wn[i])
        i += 1usize
    }
    lh -= ((1.0f64 / r.zeta) * se - 1.0f64 + math.log[f64](r.zeta)) * r.tot
    let o = co.off[d]
    i = 0usize
    while i < co.off[d + 1usize] - o {
        var j = 0usize
        while j < k {
            let ph = r.phi[(o + i) * k + j]
            let lp = r.lphi[(o + i) * k + j]
            if ph > 0.0f64 {
                lh += co.c[o + i] * ph * (r.wl[j] + r.logb[j * r.nv + co.w[o + i]] - lp)
            }
            j += 1usize
        }
        i += 1usize
    }
    r.lhood = lh
}

fn var_inference(r: *Ctm, co: *const tm.Corpus, d: usize) -> f64 {
    lhood_bnd(r, co, d)
    var conv = 0.0f64
    var go = true
    while go {
        r.niter += 1i64
        opt_zeta(r)
        opt_lambda(r, co, d)
        opt_zeta(r)
        opt_nu(r)
        opt_zeta(r)
        opt_phi(r, co, d)
        let old = r.lhood
        lhood_bnd(r, co, d)
        conv = math.abs[f64]((old - r.lhood) / old)
        go = conv > r.var_tol && (r.var_max < 0i64 || r.niter < r.var_max)
    }
    ret r.lhood
}

// E-step over every document: reset starts from the uniform state, otherwise from the stored lambda and nu
fn expectation(r: *Ctm, co: *const tm.Corpus, reset: bool) -> f64 {
    let k = r.k
    var total = 0.0f64
    var d = 0usize
    while d < r.nd {
        let o = co.off[d]
        r.tot = co.tot[d]
        var i = 0usize
        if reset {
            i = 0usize
            while i < (co.off[d + 1usize] - o) * k {
                r.phi[o * k + i] = 1.0f64 / f64(k)
                r.lphi[o * k + i] = 0.0f64 - math.log[f64](f64(k))
                i += 1usize
            }
            r.zeta = 10.0f64
            i = 0usize
            while i < k - 1usize {
                r.wn[i] = 10.0f64
                r.wl[i] = 0.0f64
                i += 1usize
            }
            r.wn[k - 1usize] = 0.0f64
            r.wl[k - 1usize] = 0.0f64
            r.niter = 0i64
            r.lhood = 0.0f64
        } else {
            i = 0usize
            while i < k {
                r.wl[i] = r.lambda[d * k + i]
                r.wn[i] = r.nu[d * k + i]
                i += 1usize
            }
            opt_zeta(r)
            opt_phi(r, co, d)
            r.niter = 0i64
        }
        r.llh[d] = var_inference(r, co, d)
        // sufficient statistics
        i = 0usize
        while i < k - 1usize {
            r.ss_mu[i] += r.wl[i]
            var j = 0usize
            while j < k - 1usize {
                let lilj = r.wl[i] * r.wl[j]
                if i == j {
                    r.ss_cov[i * (k - 1usize) + j] = r.ss_cov[i * (k - 1usize) + j] + r.wn[i] + lilj
                } else {
                    r.ss_cov[i * (k - 1usize) + j] = r.ss_cov[i * (k - 1usize) + j] + lilj
                }
                j += 1usize
            }
            i += 1usize
        }
        i = 0usize
        while i < co.off[d + 1usize] - o {
            var j = 0usize
            while j < k {
                let w = co.w[o + i]
                r.ss_beta[j * r.nv + w] = r.ss_beta[j * r.nv + w] + co.c[o + i] * r.phi[(o + i) * k + j]
                j += 1usize
            }
            i += 1usize
        }
        r.ndata += 1.0f64
        total += r.llh[d]
        i = 0usize
        while i < k {
            r.lambda[d * k + i] = r.wl[i]
            r.nu[d * k + i] = r.wn[i]
            i += 1usize
        }
        d += 1usize
    }
    ret total
}

fn reset_ss(r: *Ctm) {
    var i = 0usize
    while i < r.k * r.nv {
        r.ss_beta[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < (r.k - 1usize) * (r.k - 1usize) {
        r.ss_cov[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < r.k - 1usize {
        r.ss_mu[i] = 0.0f64
        i += 1usize
    }
    r.ndata = 0.0f64
}

fn maximization(a: *mem.Arena, r: *Ctm) -> err {
    let n = r.k - 1usize
    var i = 0usize
    while i < n {
        r.mu[i] = r.ss_mu[i] / r.ndata
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            r.cov[i * n + j] = (1.0f64 / r.ndata) * (r.ss_cov[i * n + j] + r.ndata * r.mu[i] * r.mu[j] - r.ss_mu[i] * r.mu[j] - r.ss_mu[j] * r.mu[i])
            j += 1usize
        }
        i += 1usize
    }
    let (ld, e) = invert(a, r.cov, n, r.ic)
    if e != ok { ret e }
    let (ld2, e2) = invert(a, r.ic, n, r.t3)
    if e2 != ok { ret e2 }
    r.ldic = ld2
    i = 0usize
    while i < r.k {
        var sum = 0.0f64
        var j = 0usize
        while j < r.nv {
            sum += r.ss_beta[i * r.nv + j]
            j += 1usize
        }
        if sum == 0.0f64 {
            sum = safe_log(sum) * f64(r.nv)
        } else {
            sum = safe_log(sum)
        }
        j = 0usize
        while j < r.nv {
            r.logb[i * r.nv + j] = safe_log(r.ss_beta[i * r.nv + j]) - sum
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// CTM(x, k, method = "VEM"). init: 0 random, 1 seeded, 2 the model in (beta, mu, sigma). em_max < 0 only runs the E-step (a new-data fit). f0 is unused (the minimizer's first f is the objective at the start point).
fn ctm_vem(a: *mem.Arena, m: []const f64, nd: usize, nv: usize, k: usize, init: usize, seed: i64, var_max: i64, var_tol: f64, em_max: i64, em_tol: f64, cg_max: i64, cg_tol: f64, keep: usize, f0: f64, init_beta: []const f64, init_mu: []const f64, init_sigma: []const f64, out: *Ctm) -> err {
    let (co, ec) = tm.corpus_of(a, m, nd, nv)
    if ec != ok { ret ec }
    var r: Ctm = zero
    r.k = k
    r.nv = nv
    r.nd = nd
    r.var_tol = var_tol
    r.var_max = var_max
    r.cg_tol = cg_tol
    r.cg_max = cg_max
    r.f0 = f0
    let n = k - 1usize
    let (logb, e1) = tm.zeros(a, k * nv)
    let (mu, e2) = tm.zeros(a, n)
    let (cov, e3) = tm.zeros(a, n * n)
    let (ic, e4) = tm.zeros(a, n * n)
    let (lambda, e5) = tm.zeros(a, nd * k)
    let (nu, e6) = tm.zeros(a, nd * k)
    let (llh, e7) = tm.zeros(a, nd)
    let (lls, e8) = tm.zeros(a, usize(em_max + 1i64) + 1usize)
    let (wa, e9) = tm.zeros_u(a, co.nz)
    let (wl, e10) = tm.zeros(a, k)
    let (wn, e11) = tm.zeros(a, k)
    let (phi, e12) = tm.zeros(a, co.nz * k)
    let (lphi, e13) = tm.zeros(a, co.nz * k)
    let (sphi, e14) = tm.zeros(a, k)
    let (t0, e15) = tm.zeros(a, k)
    let (t1, e16) = tm.zeros(a, k)
    let (t2, e17) = tm.zeros(a, k)
    let (t3, e18) = tm.zeros(a, k * k)
    let (cx, e19) = tm.zeros(a, k * 8usize)
    let (ssm, e20) = tm.zeros(a, n)
    let (ssc, e21) = tm.zeros(a, n * n)
    let (ssb, e22) = tm.zeros(a, k * nv)
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
    if e12 != ok { ret e12 }
    if e13 != ok { ret e13 }
    if e14 != ok { ret e14 }
    if e15 != ok { ret e15 }
    if e16 != ok { ret e16 }
    if e17 != ok { ret e17 }
    if e18 != ok { ret e18 }
    if e19 != ok { ret e19 }
    if e20 != ok { ret e20 }
    if e21 != ok { ret e21 }
    if e22 != ok { ret e22 }
    r.logb = logb
    r.mu = mu
    r.cov = cov
    r.ic = ic
    r.lambda = lambda
    r.nu = nu
    r.llh = llh
    r.logliks = lls
    r.wa = wa
    r.wl = wl
    r.wn = wn
    r.phi = phi
    r.lphi = lphi
    r.sphi = sphi
    r.t0 = t0
    r.t1 = t1
    r.t2 = t2
    r.t3 = t3
    r.cx = cx[0usize..k]
    r.cx1 = cx[k..2usize * k]
    r.cdx1 = cx[2usize * k..3usize * k]
    r.cx2 = cx[3usize * k..4usize * k]
    r.cdx = cx[4usize * k..5usize * k]
    r.cp = cx[5usize * k..6usize * k]
    r.cg0 = cx[6usize * k..7usize * k]
    r.cgr = cx[7usize * k..8usize * k]
    r.ss_mu = ssm
    r.ss_cov = ssc
    r.ss_beta = ssb
    var tg: Taus = zero
    taus_set(&tg, seed)
    var i = 0usize
    if init == 2usize {
        i = 0usize
        while i < n {
            mu[i] = init_mu[i]
            i += 1usize
        }
        i = 0usize
        while i < n * n {
            cov[i] = init_sigma[i]
            i += 1usize
        }
        i = 0usize
        while i < k * nv {
            logb[i] = init_beta[i]
            i += 1usize
        }
    } else {
        i = 0usize
        while i < n {
            mu[i] = 0.0f64
            cov[i * n + i] = 1.0f64
            i += 1usize
        }
        if init == 0usize {
            i = 0usize
            while i < k {
                var sum = 0.0f64
                var j = 0usize
                while j < nv {
                    let val = taus_uniform(&tg) + 1.0f64 / 100.0f64
                    sum += val
                    logb[i * nv + j] = val
                    j += 1usize
                }
                j = 0usize
                while j < nv {
                    logb[i * nv + j] = math.log[f64](logb[i * nv + j] / sum)
                    j += 1usize
                }
                i += 1usize
            }
        } else {
            i = 0usize
            while i < k {
                var sum = 0.0f64
                var q = 0usize
                while q < NUM_INIT_DOCS {
                    let d = usize(math.floor[f64](taus_uniform(&tg) * f64(nd)))
                    var t = co.off[d]
                    while t < co.off[d + 1usize] {
                        logb[i * nv + co.w[t]] = logb[i * nv + co.w[t]] + co.c[t]
                        t += 1usize
                    }
                    q += 1usize
                }
                var j = 0usize
                while j < nv {
                    logb[i * nv + j] = logb[i * nv + j] + (1.0f64 + taus_uniform(&tg))
                    sum += logb[i * nv + j]
                    j += 1usize
                }
                sum = safe_log(sum)
                j = 0usize
                while j < nv {
                    logb[i * nv + j] = safe_log(logb[i * nv + j]) - sum
                    j += 1usize
                }
                i += 1usize
            }
        }
    }
    let (ld0, ei) = invert(a, cov, n, ic)
    if ei != ok { ret ei }
    r.ldic = 0.0f64
    let (ldi, ei2) = invert(a, ic, n, t3)
    if ei2 != ok { ret ei2 }
    r.ldic = ldi
    var iteration = 0i64
    var nlog = 0usize
    var conv = 1.0f64
    var lhood = 0.0f64
    var lhood_old = 0.0f64
    var reset = true
    while iteration < em_max && (conv > em_tol || conv < 0.0f64) {
        lhood = expectation(&r, &co, reset)
        conv = (lhood_old - lhood) / lhood_old
        if conv < 0.0f64 {
            reset = false
            if r.var_max > 0i64 {
                r.var_max += 10i64
            } else {
                r.var_tol = r.var_tol / 10.0f64
            }
        } else {
            if keep > 0usize && em_max > 0i64 {
                lls[nlog] = lhood
                nlog += 1usize
            }
            let em = maximization(a, &r)
            if em != ok { ret em }
            lhood_old = lhood
            reset = true
            iteration += 1i64
        }
        reset_ss(&r)
    }
    if em_max < 0i64 {
        lhood = expectation(&r, &co, reset)
    }
    var d = 0usize
    while d < nd {
        var n2 = co.off[d]
        while n2 < co.off[d + 1usize] {
            var best = 0usize
            var mx = phi[n2 * k]
            var q = 1usize
            while q < k {
                if phi[n2 * k + q] > mx {
                    mx = phi[n2 * k + q]
                    best = q
                }
                q += 1usize
            }
            wa[n2] = best
            n2 += 1usize
        }
        d += 1usize
    }
    r.iter = usize(iteration)
    r.nlog = nlog
    r.wa = wa
    *out = r
    ret ok
}

// the gamma slot: exp(lambda) with a final column of ones, over its row sums
fn gamma_of(g: []f64, lambda: []const f64, nd: usize, k: usize) {
    var d = 0usize
    while d < nd {
        var s = 0.0f64
        var i = 0usize
        while i < k - 1usize {
            g[d * k + i] = math.exp[f64](lambda[d * k + i])
            s += g[d * k + i]
            i += 1usize
        }
        g[d * k + k - 1usize] = 1.0f64
        s += 1.0f64
        i = 0usize
        while i < k {
            g[d * k + i] = g[d * k + i] / s
            i += 1usize
        }
        d += 1usize
    }
}
