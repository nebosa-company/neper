// R ResourceSelection beyond hoslem.test: rsf / rspf (rsf.fit: used-available likelihood by Nelder-Mead, the optim Hessian, the bootstrap of the
// used points), simulateUsedAvail (sample.int with prob: ProbSampleReplace and Walker's alias method), and the numbers behind mep (the binned
// fitted-value summary) and kdepairs (kde2d, lowess and cor of each panel). The plots themselves are not ported.

use e.algo.rand.r as rng
use e.algo.sort
use e.algo.stat.lowesspkg as lw
use e.algo.stat.mass as ms
use e.algo.stat.rnm as nmo
use e.math
use e.math.dist as dist
use e.mem
use e.text.prettyunits as pu

error Singular

fn cmp_up(ctx: *u8, x: f64, y: f64) -> i32 {
    if x < y { ret 0i32 - 1i32 }
    if x > y { ret 1i32 }
    ret 0i32
}

// link codes: 0 logit, 1 cloglog, 2 probit, 3 log (the exponential RSF), 4 identity
fn linkinv(link: usize, eta: f64) -> f64 {
    let eps = 2.220446049250313e-16f64
    if link == 0usize {
        var t = math.exp[f64](eta)
        if eta < 0.0f64 - 30.0f64 { t = eps }
        if eta > 30.0f64 { t = 1.0f64 / eps }
        ret t / (1.0f64 + t)
    }
    if link == 1usize {
        var v = 0.0f64 - dist.expm1(0.0f64 - math.exp[f64](eta))
        if v > 1.0f64 - eps { v = 1.0f64 - eps }
        if v < eps { v = eps }
        ret v
    }
    if link == 2usize { ret dist.pnorm(eta, 0.0f64, 1.0f64, true, false) }
    if link == 4usize { ret eta }
    var w = math.exp[f64](eta)
    if w < eps { w = eps }
    ret w
}

fn linkfun(link: usize, mu: f64) -> f64 {
    if link == 0usize { ret math.log[f64](mu / (1.0f64 - mu)) }
    if link == 1usize { ret math.log[f64](0.0f64 - math.log[f64](1.0f64 - mu)) }
    if link == 2usize { ret dist.qnorm(mu, 0.0f64, 1.0f64, true, false) }
    if link == 3usize { ret math.log[f64](mu) }
    ret mu
}

// sum with a compensation term, standing for R's long double accumulator
fn csum(v: []const f64) -> f64 {
    var total = 0.0f64
    var comp = 0.0f64
    var i = 0usize
    while i < v.len {
        let x = v[i]
        let t = total + x
        if math.abs[f64](total) >= math.abs[f64](x) { comp += (total - t) + x } else { comp += (x - t) + total }
        total = t
        i += 1usize
    }
    ret total + comp
}

// R's mean: the sum over n, then the mean of the residuals added back
fn mean_of(v: []const f64, tmp: []f64) -> f64 {
    let n = f64(v.len)
    let s = csum(v) / n
    var i = 0usize
    while i < v.len {
        tmp[i] = v[i] - s
        i += 1usize
    }
    ret s + csum(tmp[0usize..v.len]) / n
}

type RsfCtx = struct {
    x: []const f64,
    n: usize,
    p: usize,
    used: []const usize,
    avail: []const usize,
    astart: []const usize,
    alist: []const usize,
    matched: bool,
    link: usize,
    boot: []const usize,
    pu: []f64,
    pa: []f64,
    lv: []f64,
    gs: []f64,
}

fn eta_at(c: *const RsfCtx, row: usize, par: []const f64) -> f64 {
    var s = 0.0f64
    var j = 0usize
    while j < c.p {
        s += c.x[j * c.n + row] * par[j]
        j += 1usize
    }
    ret s
}

// -sum(log(pmax(P.used / (P.used + P.avail), eps))[boot])
fn rsf_nll(c: *RsfCtx, par: []const f64) -> f64 {
    let nu = c.used.len
    let na = c.avail.len
    var i = 0usize
    while i < nu {
        c.pu[i] = linkinv(c.link, eta_at(c, c.used[i], par))
        i += 1usize
    }
    i = 0usize
    while i < na {
        c.pa[i] = linkinv(c.link, eta_at(c, c.avail[i], par))
        i += 1usize
    }
    var tot = 0.0f64
    if !c.matched { tot = csum(c.pa[0usize..na]) }
    i = 0usize
    while i < nu {
        var pav = tot
        if c.matched {
            var k = c.astart[i]
            var sum_g = 0.0f64
            var comp = 0.0f64
            while k < c.astart[i + 1usize] {
                let xv = c.pa[c.alist[k]]
                let t = sum_g + xv
                if math.abs[f64](sum_g) >= math.abs[f64](xv) { comp += (sum_g - t) + xv } else { comp += (xv - t) + sum_g }
                sum_g = t
                k += 1usize
            }
            pav = sum_g + comp
        }
        var q = c.pu[i] / (c.pu[i] + pav)
        if q < 2.220446049250313e-16f64 { q = 2.220446049250313e-16f64 }
        c.lv[i] = math.log[f64](q)
        i += 1usize
    }
    var k2 = 0usize
    while k2 < c.boot.len {
        c.gs[k2] = c.lv[c.boot[k2]]
        k2 += 1usize
    }
    ret 0.0f64 - csum(c.gs[0usize..c.boot.len])
}

// Gauss-Jordan with partial pivoting: out = the inverse of the p by p (row-major) m; answers rcond in the 1-norm (0 when singular)
fn inv_pivot(a: *mem.Arena, m: []const f64, p: usize, out: []f64) -> (f64, err) {
    let (w, e) = mem.alloc[f64](a, p * 2usize * p)
    if e != ok { ret (0.0f64, e) }
    var n1 = 0.0f64
    var i = 0usize
    while i < p {
        var cs = 0.0f64
        var j = 0usize
        while j < p {
            w[i * 2usize * p + j] = m[i * p + j]
            w[i * 2usize * p + p + j] = 0.0f64
            cs += math.abs[f64](m[j * p + i])
            j += 1usize
        }
        w[i * 2usize * p + p + i] = 1.0f64
        if cs > n1 { n1 = cs }
        i += 1usize
    }
    var c = 0usize
    while c < p {
        var best = c
        var r = c + 1usize
        while r < p {
            if math.abs[f64](w[r * 2usize * p + c]) > math.abs[f64](w[best * 2usize * p + c]) { best = r }
            r += 1usize
        }
        if w[best * 2usize * p + c] == 0.0f64 { ret (0.0f64, ok) }
        if best != c {
            var j = 0usize
            while j < 2usize * p {
                let t = w[c * 2usize * p + j]
                w[c * 2usize * p + j] = w[best * 2usize * p + j]
                w[best * 2usize * p + j] = t
                j += 1usize
            }
        }
        let pv = w[c * 2usize * p + c]
        var j2 = 0usize
        while j2 < 2usize * p {
            w[c * 2usize * p + j2] = w[c * 2usize * p + j2] / pv
            j2 += 1usize
        }
        r = 0usize
        while r < p {
            if r != c {
                let f = w[r * 2usize * p + c]
                if f != 0.0f64 {
                    var j3 = 0usize
                    while j3 < 2usize * p {
                        w[r * 2usize * p + j3] = w[r * 2usize * p + j3] - f * w[c * 2usize * p + j3]
                        j3 += 1usize
                    }
                }
            }
            r += 1usize
        }
        c += 1usize
    }
    var n2 = 0.0f64
    i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            out[i * p + j] = w[i * 2usize * p + p + j]
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < p {
        var cs = 0.0f64
        var j = 0usize
        while j < p {
            cs += math.abs[f64](out[j * p + i])
            j += 1usize
        }
        if cs > n2 { n2 = cs }
        i += 1usize
    }
    ret (1.0f64 / (n1 * n2), ok)
}

fn ylogy(y: f64, mu: f64) -> f64 {
    if y != 0.0f64 { ret y * math.log[f64](y / mu) }
    ret 0.0f64
}

fn dev_binom(y: []const f64, mu: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < y.len {
        s += 2.0f64 * (ylogy(y[i], mu[i]) + ylogy(1.0f64 - y[i], 1.0f64 - mu[i]))
        i += 1usize
    }
    ret s
}

// glm.fit(X, Y, family = binomial())$coef: IRLS from mustart = (y + 0.5) / 2, at most 25 rounds, deviance change below 1e-8; x is n by p column-major
fn glm_logit(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, coef: []f64) -> err {
    let (eta, e1) = mem.alloc[f64](a, n)
    let (mu, e2) = mem.alloc[f64](a, n)
    let (xtx, e3) = mem.alloc[f64](a, p * p)
    let (inv, e4) = mem.alloc[f64](a, p * p)
    let (xtz, e5) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        mu[i] = (y[i] + 0.5f64) / 2.0f64
        eta[i] = math.log[f64](mu[i] / (1.0f64 - mu[i]))
        mu[i] = linkinv(0usize, eta[i])
        i += 1usize
    }
    var devold = dev_binom(y, mu)
    var iter = 0usize
    while iter < 25usize {
        var r = 0usize
        while r < p * p {
            xtx[r] = 0.0f64
            r += 1usize
        }
        r = 0usize
        while r < p {
            xtz[r] = 0.0f64
            r += 1usize
        }
        i = 0usize
        while i < n {
            let et = eta[i]
            var me = 2.220446049250313e-16f64
            if !(et > 30.0f64 || et < 0.0f64 - 30.0f64) {
                let oe = 1.0f64 + math.exp[f64](et)
                me = math.exp[f64](et) / (oe * oe)
            }
            let vm = mu[i] * (1.0f64 - mu[i])
            let z = et + (y[i] - mu[i]) / me
            let w2 = me * me / vm
            var j = 0usize
            while j < p {
                xtz[j] += x[j * n + i] * w2 * z
                var k = 0usize
                while k < p {
                    xtx[j * p + k] += x[j * n + i] * w2 * x[k * n + i]
                    k += 1usize
                }
                j += 1usize
            }
            i += 1usize
        }
        let (rc, ei) = inv_pivot(a, xtx, p, inv)
        if ei != ok || rc == 0.0f64 { ret Singular }
        var j = 0usize
        while j < p {
            var s = 0.0f64
            var k = 0usize
            while k < p {
                s += inv[j * p + k] * xtz[k]
                k += 1usize
            }
            coef[j] = s
            j += 1usize
        }
        i = 0usize
        while i < n {
            var s = 0.0f64
            j = 0usize
            while j < p {
                s += x[j * n + i] * coef[j]
                j += 1usize
            }
            eta[i] = s
            mu[i] = linkinv(0usize, s)
            i += 1usize
        }
        let dv = dev_binom(y, mu)
        iter += 1usize
        if math.abs[f64](dv - devold) / (math.abs[f64](dv) + 0.1f64) < 1.0e-8f64 { break }
        devold = dv
    }
    ret ok
}

fn grad_num(c: *RsfCtx, par: []const f64, xx: []f64, out: []f64) {
    let eps = 0.001f64
    var i = 0usize
    while i < par.len {
        xx[i] = par[i]
        i += 1usize
    }
    i = 0usize
    while i < par.len {
        xx[i] = par[i] + eps
        let v1 = rsf_nll(c, xx)
        xx[i] = par[i] - eps
        let v2 = rsf_nll(c, xx)
        out[i] = (v1 - v2) / (2.0f64 * eps)
        xx[i] = par[i]
        i += 1usize
    }
}

// the Hessian of optim(hessian = TRUE) at par: central differences of the central-difference gradient, steps 1e-3, symmetrised; h is p by p row-major
fn rsf_hessian(c: *RsfCtx, par: []const f64, h: []f64, work: []f64) {
    let p = par.len
    let eps = 0.001f64
    let dpar = work[0usize..p]
    let df1 = work[p..2usize * p]
    let df2 = work[2usize * p..3usize * p]
    let xx = work[3usize * p..4usize * p]
    var i = 0usize
    while i < p {
        dpar[i] = par[i]
        i += 1usize
    }
    i = 0usize
    while i < p {
        dpar[i] = dpar[i] + eps
        grad_num(c, dpar, xx, df1)
        dpar[i] = dpar[i] - 2.0f64 * eps
        grad_num(c, dpar, xx, df2)
        var j = 0usize
        while j < p {
            h[i * p + j] = (df1[j] - df2[j]) / (2.0f64 * eps)
            j += 1usize
        }
        dpar[i] = dpar[i] + eps
        i += 1usize
    }
    i = 0usize
    while i < p {
        var j = 0usize
        while j < i {
            let t = 0.5f64 * (h[i * p + j] + h[j * p + i])
            h[i * p + j] = t
            h[j * p + i] = t
            j += 1usize
        }
        i += 1usize
    }
}

// rsf.fit(X, Y, m, link, B, inits): x is n by p column-major, y holds 0 / 1, mvec is one m (0 = every available point counts for every used one;
// m > 0 = used point i owns available points i m ... i m + m - 1) or one id per row. inits has p values or none (then glm.fit supplies them).
// coef, se: p values (se NaN when rcond(H) <= 1e-6); ll: the log likelihood; boot: p values per column, column 0 the fit, then nboot resamples
// of the used points drawn with sample(1:N.used, N.used, TRUE) from r. Answers whether optim converged.
fn rsf_fit(a: *mem.Arena, r: *rng.Rng, x: []const f64, y: []const f64, n: usize, p: usize, mvec: []const f64, link: usize, nboot: usize, inits: []const f64, maxit: usize, coef: []f64, se: []f64, ll: []f64, boot: []f64) -> (bool, err) {
    var nu = 0usize
    var i = 0usize
    while i < n {
        if y[i] == 1.0f64 { nu += 1usize }
        i += 1usize
    }
    let na = n - nu
    let (used, e1) = mem.alloc[usize](a, nu)
    let (avail, e2) = mem.alloc[usize](a, na)
    let (astart, e3) = mem.alloc[usize](a, nu + 1usize)
    let (alist, e4) = mem.alloc[usize](a, na)
    let (pu_v, e5) = mem.alloc[f64](a, nu)
    let (pa_v, e6) = mem.alloc[f64](a, na)
    let (lv, e7) = mem.alloc[f64](a, nu)
    let (gs, e8) = mem.alloc[f64](a, nu)
    let (par0, e9) = mem.alloc[f64](a, p)
    let (hm, e10) = mem.alloc[f64](a, p * p)
    let (hi, e11) = mem.alloc[f64](a, p * p)
    let (work, e12) = mem.alloc[f64](a, 4usize * p)
    let (ident, e14) = mem.alloc[usize](a, nu)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e14 != ok { ret (false, mem.Full) }
    var ku = 0usize
    var ka = 0usize
    i = 0usize
    while i < n {
        if y[i] == 1.0f64 {
            used[ku] = i
            ku += 1usize
        } else {
            avail[ka] = i
            ka += 1usize
        }
        i += 1usize
    }
    var matched = false
    var kk = 0usize
    if mvec.len == 1usize {
        if mvec[0usize] > 0.0f64 {
            matched = true
            let mm = usize(mvec[0usize])
            if mm * nu != na { ret (false, Singular) }
            i = 0usize
            while i < nu {
                astart[i] = i * mm
                i += 1usize
            }
            astart[nu] = na
            i = 0usize
            while i < na {
                alist[i] = i
                i += 1usize
            }
        }
    } else {
        matched = true
        i = 0usize
        while i < nu {
            astart[i] = kk
            var k = 0usize
            while k < na {
                if mvec[avail[k]] == mvec[used[i]] {
                    alist[kk] = k
                    kk += 1usize
                }
                k += 1usize
            }
            i += 1usize
        }
        astart[nu] = kk
    }
    i = 0usize
    while i < nu {
        ident[i] = i
        i += 1usize
    }
    if inits.len == p {
        i = 0usize
        while i < p {
            par0[i] = inits[i]
            i += 1usize
        }
    } else {
        let eg = glm_logit(a, x, y, n, p, par0)
        if eg != ok { ret (false, eg) }
    }
    var cx = RsfCtx { x: x, n: n, p: p, used: used, avail: avail, astart: astart, alist: alist, matched: matched, link: link, boot: ident, pu: pu_v, pa: pa_v, lv: lv, gs: gs }
    let ninf = 0.0f64 - 1.0f64 / 0.0f64
    let (fv, nc, fail) = nmo.nmmin[RsfCtx](a, &cx, rsf_nll, par0, ninf, 1.4901161193847656e-08f64, 1.0f64, 0.5f64, 2.0f64, maxit, 1.0f64, coef)
    ll[0usize] = 0.0f64 - fv
    i = 0usize
    while i < p {
        boot[i] = coef[i]
        i += 1usize
    }
    rsf_hessian(&cx, coef, hm, work)
    let (rc, ei2) = inv_pivot(a, hm, p, hi)
    if ei2 != ok { ret (false, ei2) }
    i = 0usize
    while i < p {
        se[i] = 0.0f64 / 0.0f64
        i += 1usize
    }
    if rc > 1.0e-6f64 {
        i = 0usize
        while i < p {
            let dv = hi[i * p + i]
            if dv >= 0.0f64 { se[i] = math.sqrt[f64](dv) }
            i += 1usize
        }
    }
    // all B resamples are drawn first, then each is optimised from the fit
    let (ids, e15) = mem.alloc[usize](a, nboot * nu)
    if e15 != ok { ret (false, e15) }
    var b = 0usize
    while b < nboot {
        let (s, es) = rng.sample_int(a, r, i64(nu), i64(nu), true)
        if es != ok { ret (false, es) }
        i = 0usize
        while i < nu {
            ids[b * nu + i] = usize(s[i] - 1i64)
            i += 1usize
        }
        b += 1usize
    }
    b = 0usize
    while b < nboot {
        let start = mem.mark(a)
        cx.boot = ids[b * nu..(b + 1usize) * nu]
        let (bx, e16) = mem.alloc[f64](a, p)
        if e16 != ok { ret (false, e16) }
        let (fv2, nc2, fail2) = nmo.nmmin[RsfCtx](a, &cx, rsf_nll, coef, ninf, 1.4901161193847656e-08f64, 1.0f64, 0.5f64, 2.0f64, maxit, 1.0f64, bx)
        i = 0usize
        while i < p {
            boot[(b + 1usize) * p + i] = bx[i]
            i += 1usize
        }
        mem.reset(a, start)
        b += 1usize
    }
    ret (fail == 0usize, ok)
}

// R's revsort: heapsort a into descending order, ib alongside (not stable); the C code is 1-based
fn revsort(a: []f64, ib: []usize) {
    let n = a.len
    if n <= 1usize { ret }
    var l = (n >> 1usize) + 1usize
    var ir = n
    while true {
        var ra = 0.0f64
        var ii = 0usize
        if l > 1usize {
            l -= 1usize
            ra = a[l - 1usize]
            ii = ib[l - 1usize]
        } else {
            ra = a[ir - 1usize]
            ii = ib[ir - 1usize]
            a[ir - 1usize] = a[0usize]
            ib[ir - 1usize] = ib[0usize]
            ir -= 1usize
            if ir == 1usize {
                a[0usize] = ra
                ib[0usize] = ii
                ret
            }
        }
        var i = l
        var j = l << 1usize
        while j <= ir {
            if j < ir && a[j - 1usize] > a[j] { j += 1usize }
            if ra > a[j - 1usize] {
                a[i - 1usize] = a[j - 1usize]
                ib[i - 1usize] = ib[j - 1usize]
                i = j
                j += i
            } else {
                j = ir + 1usize
            }
        }
        a[i - 1usize] = ra
        ib[i - 1usize] = ii
    }
}

// sample.int(n, size, replace = TRUE, prob): 1-based draws; prob is rescaled to sum one first
fn sample_prob(a: *mem.Arena, r: *rng.Rng, prob: []const f64, size: usize, out: []usize) -> err {
    let n = prob.len
    let (pr, e1) = mem.alloc[f64](a, n)
    let (perm, e2) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok { ret mem.Full }
    var sum_p = 0.0f64
    var i = 0usize
    while i < n {
        sum_p += prob[i]
        i += 1usize
    }
    var nc = 0usize
    i = 0usize
    while i < n {
        pr[i] = prob[i] / sum_p
        perm[i] = i + 1usize
        if f64(n) * pr[i] > 0.1f64 { nc += 1usize }
        i += 1usize
    }
    if nc > 200usize {
        // Walker's alias method
        let (q, e3) = mem.alloc[f64](a, n)
        let (hl, e4) = mem.alloc[usize](a, n)
        let (al, e5) = mem.alloc[usize](a, n)
        if e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
        var h = 0usize
        var lo = n
        i = 0usize
        while i < n {
            al[i] = 0usize
            q[i] = pr[i] * f64(n)
            if q[i] < 1.0f64 {
                hl[h] = i
                h += 1usize
            } else {
                lo -= 1usize
                hl[lo] = i
            }
            i += 1usize
        }
        if h > 0usize && lo < n {
            var k = 0usize
            while k + 1usize < n {
                let ii = hl[k]
                let jj = hl[lo]
                al[ii] = jj
                q[jj] += q[ii] - 1.0f64
                if q[jj] < 1.0f64 { lo += 1usize }
                if lo >= n { break }
                k += 1usize
            }
        }
        i = 0usize
        while i < size {
            let k = usize(rng.unif_index(r, f64(n)))
            let ru = rng.unif(r)
            if ru < q[k] { out[i] = k + 1usize } else { out[i] = al[k] + 1usize }
            i += 1usize
        }
        ret ok
    }
    revsort(pr, perm)
    i = 1usize
    while i < n {
        pr[i] += pr[i - 1usize]
        i += 1usize
    }
    i = 0usize
    while i < size {
        let ru = rng.unif(r)
        var j = 0usize
        while j + 1usize < n {
            if ru <= pr[j] { break }
            j += 1usize
        }
        out[i] = perm[j]
        i += 1usize
    }
    ret ok
}

// simulateUsedAvail(data, parms, n.used, m, link): x is the n by p column-major model matrix (intercept first); id1 the n.used site rows drawn with
// probability linkinv(X parms), id2 the n.used * m available rows drawn uniformly, both 1-based, id1 first
fn simulate_used_avail(a: *mem.Arena, r: *rng.Rng, x: []const f64, n: usize, p: usize, parms: []const f64, n_used: usize, m: usize, link: usize, id1: []usize, id2: []usize) -> err {
    let (pv, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < p {
            s += x[j * n + i] * parms[j]
            j += 1usize
        }
        pv[i] = linkinv(link, s)
        i += 1usize
    }
    let es = sample_prob(a, r, pv, n_used, id1)
    if es != ok { ret es }
    let (s2, e2) = rng.sample_int(a, r, i64(n), i64(n_used * m), true)
    if e2 != ok { ret e2 }
    i = 0usize
    while i < n_used * m {
        id2[i] = usize(s2[i])
        i += 1usize
    }
    ret ok
}

fn sort_quant(v: []f64, alpha: f64, out: []f64) {
    var ctx = 0u8
    sort.in_place_by[f64, u8](v, &ctx, cmp_up)
    out[0usize] = ms.quant7(v, 0.5f64)
    out[1usize] = ms.quant7(v, alpha)
    out[2usize] = ms.quant7(v, 1.0f64 - alpha)
}

// mep(fit)'s per-variable summary: type 0 numeric (equal-width cut into nbin classes, adjusted to minbucket), 1 unique (x rounded to digits),
// 2 factor (x holds the level codes); link_in < 0 picks identity / log / logit from the range of y. Fills xv (mean of x per level; the code for a
// factor) and yq (three columns per level: median, lower and upper quantile of linkfun(y)); answers (levels, link, type)
fn mep(a: *mem.Arena, x: []const f64, y: []const f64, level: f64, link_in: i64, type_in: usize, nbin: usize, minbucket: usize, digits: usize, xv: []f64, yq: []f64) -> (usize, usize, usize, err) {
    let n = x.len
    var link = 4usize
    if link_in >= 0i64 { link = usize(link_in) }
    if link_in < 0i64 {
        var ge0 = true
        var le1 = true
        var i = 0usize
        while i < n {
            if y[i] < 0.0f64 { ge0 = false }
            if y[i] > 1.0f64 { le1 = false }
            i += 1usize
        }
        if ge0 {
            link = 3usize
            if le1 { link = 0usize }
        }
    }
    let (grp, e1) = mem.alloc[f64](a, n)
    let (ly, e2) = mem.alloc[f64](a, n)
    let (buf, e3) = mem.alloc[f64](a, n)
    let (xs, e4) = mem.alloc[f64](a, n)
    let (tmp, e5) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (0usize, link, type_in, mem.Full) }
    var i = 0usize
    while i < n {
        ly[i] = linkfun(link, y[i])
        i += 1usize
    }
    var ty = type_in
    var nb = nbin
    if ty == 0usize {
        let bs = n / nb
        if bs < minbucket { nb = n / minbucket }
        var lo = x[0usize]
        var hi = x[0usize]
        i = 0usize
        while i < n {
            if x[i] < lo { lo = x[i] }
            if x[i] > hi { hi = x[i] }
            i += 1usize
        }
        var dx = hi - lo
        if dx == 0.0f64 {
            dx = math.abs[f64](lo)
            if lo == 0.0f64 { dx = 1.0f64 }
        }
        let b0 = lo - dx / 1000.0f64
        let b1 = hi + dx / 1000.0f64
        let by = (hi - lo) / f64(nb)
        let (cnt, e6) = mem.alloc[usize](a, nb)
        if e6 != ok { ret (0usize, link, ty, e6) }
        i = 0usize
        while i < nb {
            cnt[i] = 0usize
            i += 1usize
        }
        i = 0usize
        while i < n {
            var k = 0usize
            while k < nb {
                var up = lo + f64(k + 1usize) * by
                if k + 1usize == nb { up = b1 }
                var dn = lo + f64(k) * by
                if k == 0usize { dn = b0 }
                if x[i] > dn && x[i] <= up { break }
                k += 1usize
            }
            grp[i] = f64(k)
            if k < nb { cnt[k] += 1usize }
            i += 1usize
        }
        var nl = 0usize
        i = 0usize
        while i < nb {
            if cnt[i] > 0usize { nl += 1usize }
            i += 1usize
        }
        if nl < 3usize { ty = 1usize }
        var nuq = 0usize
        i = 0usize
        while i < n {
            var dup = false
            var k = 0usize
            while k < i {
                if x[k] == x[i] { dup = true }
                k += 1usize
            }
            if !dup { nuq += 1usize }
            i += 1usize
        }
        if nuq < nb { ty = 1usize }
    }
    let alpha = (1.0f64 - level) / 2.0f64
    var nlev = 0usize
    if ty == 0usize {
        var b = 0usize
        while b < nb {
            var cnt2 = 0usize
            i = 0usize
            while i < n {
                if grp[i] == f64(b) {
                    buf[cnt2] = ly[i]
                    xs[cnt2] = x[i]
                    cnt2 += 1usize
                }
                i += 1usize
            }
            if cnt2 > 0usize {
                xv[nlev] = mean_of(xs[0usize..cnt2], tmp)
                sort_quant(buf[0usize..cnt2], alpha, yq[nlev * 3usize..nlev * 3usize + 3usize])
                nlev += 1usize
            }
            b += 1usize
        }
        ret (nlev, link, ty, ok)
    }
    let (xp, e7) = mem.alloc[f64](a, n)
    if e7 != ok { ret (0usize, link, ty, e7) }
    i = 0usize
    while i < n {
        if ty == 1usize { xp[i] = pu.fround(x[i], digits) } else { xp[i] = x[i] }
        i += 1usize
    }
    var last = 0.0f64
    var first = true
    while true {
        var found = false
        var cand = 0.0f64
        i = 0usize
        while i < n {
            if (first || xp[i] > last) && (!found || xp[i] < cand) {
                cand = xp[i]
                found = true
            }
            i += 1usize
        }
        if !found { break }
        var cnt3 = 0usize
        i = 0usize
        while i < n {
            if xp[i] == cand {
                buf[cnt3] = ly[i]
                xs[cnt3] = x[i]
                cnt3 += 1usize
            }
            i += 1usize
        }
        xv[nlev] = mean_of(xs[0usize..cnt3], tmp)
        if ty == 2usize { xv[nlev] = cand }
        sort_quant(buf[0usize..cnt3], alpha, yq[nlev * 3usize..nlev * 3usize + 3usize])
        nlev += 1usize
        last = cand
        first = false
    }
    ret (nlev, link, ty, ok)
}

// the numbers of one kdepairs panel pair: the lower panel's MASS::kde2d(x1, x2, n) on the n by n grid (z[i + n j]), the upper panel's lowess(x1, x2)
// in x order (lx, ly), and cor(x1, x2)
fn kdepair(a: *mem.Arena, x1: []const f64, x2: []const f64, n: usize, z: []f64, lx: []f64, ly: []f64) -> (f64, err) {
    let m = x1.len
    var lims: [4]f64 = zero
    lims[0usize] = x1[0usize]
    lims[1usize] = x1[0usize]
    lims[2usize] = x2[0usize]
    lims[3usize] = x2[0usize]
    var i = 1usize
    while i < m {
        if x1[i] < lims[0usize] { lims[0usize] = x1[i] }
        if x1[i] > lims[1usize] { lims[1usize] = x1[i] }
        if x2[i] < lims[2usize] { lims[2usize] = x2[i] }
        if x2[i] > lims[3usize] { lims[3usize] = x2[i] }
        i += 1usize
    }
    let ek = ms.kde2d(a, x1, x2, 0.0f64, 0.0f64, n, n, lims[0usize..4usize], z)
    if ek != ok { ret (0.0f64, ek) }
    let (ox, e1) = mem.alloc[f64](a, m + 1usize)
    let (oy, e2) = mem.alloc[f64](a, m + 1usize)
    let (ys, e3) = mem.alloc[f64](a, m + 1usize)
    let (w, e4) = mem.alloc[f64](a, m + 1usize)
    let (rw, e5) = mem.alloc[f64](a, m + 1usize)
    let (res, e6) = mem.alloc[f64](a, m + 1usize)
    let (srt, e7) = mem.alloc[f64](a, m)
    let (taken, e8) = mem.alloc[bool](a, m)
    let (tmp, e9) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret (0.0f64, mem.Full) }
    i = 0usize
    while i < m {
        taken[i] = false
        i += 1usize
    }
    var k = 0usize
    while k < m {
        var best = m
        i = 0usize
        while i < m {
            if !taken[i] && (best == m || x1[i] < x1[best]) { best = i }
            i += 1usize
        }
        taken[best] = true
        ox[k + 1usize] = x1[best]
        oy[k + 1usize] = x2[best]
        lx[k] = x1[best]
        k += 1usize
    }
    let delta = 0.01f64 * (lims[1usize] - lims[0usize])
    lw.clowess(ox, oy, m, 2.0f64 / 3.0f64, 3usize, delta, ys, w, rw, res, srt)
    i = 0usize
    while i < m {
        ly[i] = ys[i + 1usize]
        i += 1usize
    }
    let m1 = mean_of(x1, tmp)
    let m2 = mean_of(x2, tmp)
    var sxy = 0.0f64
    var sxx = 0.0f64
    var syy = 0.0f64
    i = 0usize
    while i < m {
        sxy += (x1[i] - m1) * (x2[i] - m2)
        sxx += (x1[i] - m1) * (x1[i] - m1)
        syy += (x2[i] - m2) * (x2[i] - m2)
        i += 1usize
    }
    ret (sxy / (math.sqrt[f64](sxx) * math.sqrt[f64](syy)), ok)
}
