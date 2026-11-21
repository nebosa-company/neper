// R partykit lmtree: model-based recursive partitioning of a linear model y ~ x | z. A node is split on the partitioning variable whose parameter-instability test has the smallest p value (supLM for a numeric variable with the tabulated beta approximation, the chi-square of the grouped score sums for an unordered factor, both on the scores r x decorrelated by the inverse outer product), Bonferroni adjusted, and at the cut point or level split that minimises the summed residual sum of squares of the two refitted models.
//
// Not here: catsplit multiway, ordinal = max or L2 for ordered partitioning factors, Gamma and other glm families, zero weights with vcov = info, vcov info or sandwich for a glm.

use e.algo.rand.r as rnd
use e.algo.stat.partykitpkg as pk
use e.algo.stat.strucpkg_tables as tb
use e.math
use e.math.nmath as nm
use e.mem
use e.str

type MOut = struct { vr: []i64, brk: []f64, kid1: []i64, kid2: []i64, nobs: []f64, pval: []f64, objfun: []f64, coef: []f64, lmap: []i64, stat: []f64, adjp: []f64, k: usize, pz: usize, maxlev: usize, count: usize, minsize: usize }

type MCtl = struct { alpha: f64, bonf: bool, maxdepth: usize, trim: f64, center: bool, mtry: usize, bties: bool, rg: *rnd.Rng }

// wt the case weights (empty = all 1), off the offset (empty = none), cl the cluster codes (empty = none), vc the instability weighting: 0 opg, 1 info, 2 sandwich (the last two for the linear model)
type MCtx = struct { xr: []const f64, kx: usize, y: []const f64, n: usize, z: []const f64, pz: usize, nl: []const usize, fam: usize, wt: []const f64, off: []const f64, cl: []const usize, vc: usize }

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

// a partitioning factor coded 1000000 + L is an ordered factor of L levels: its z column holds the level indices 1 .. L, it is tested as a factor (ordinal = chisq) and split like a numeric variable at a level, never between levels
fn nlv(x: usize) -> usize {
    if x >= 1000000usize { ret x - 1000000usize }
    ret x
}

// the sum of the case weights over the rows sub (their count without weights)
fn sumw(c: *const MCtx, sub: []const usize) -> f64 {
    if c.wt.len == 0usize { ret f64(sub.len) }
    var s = 0.0f64
    var i = 0usize
    while i < sub.len {
        s += c.wt[sub[i]]
        i += 1usize
    }
    ret s
}

// the case weight of row r
fn rw(c: *const MCtx, r: usize) -> f64 {
    if c.wt.len == 0usize { ret 1.0f64 }
    ret c.wt[r]
}

fn inf() -> f64 { ret 1.0f64 / 0.0f64 }

// least squares of y on the intercept and the regressors over the rows sub by Householder QR; coef (k) and res (m) are filled, the result is the residual sum of squares (NaN when rank deficient)
fn ols(a: *mem.Arena, c: *const MCtx, sub: []const usize, coef: []f64, res: []f64, sw: []const f64, yv: []const f64) -> (f64, err) {
    let m = sub.len
    let k = c.kx + 1usize
    let (xm, e1) = mem.alloc[f64](a, m * k)
    let (b, e2) = mem.alloc[f64](a, m)
    let (qa, e3) = mem.alloc[f64](a, m * k)
    let (qb, e4) = mem.alloc[f64](a, m)
    let (vv, e5) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (0.0f64, mem.Full) }
    var i = 0usize
    while i < m {
        xm[i] = 1.0f64
        var j = 0usize
        while j < c.kx {
            xm[(j + 1usize) * m + i] = c.xr[j * c.n + sub[i]]
            j += 1usize
        }
        b[i] = yv[i]
        qb[i] = b[i]
        i += 1usize
    }
    i = 0usize
    while i < m * k {
        qa[i] = xm[i]
        if sw.len > 0usize { qa[i] = xm[i] * sw[i % m] }
        i += 1usize
    }
    if sw.len > 0usize {
        i = 0usize
        while i < m {
            qb[i] = b[i] * sw[i]
            i += 1usize
        }
    }
    var j = 0usize
    while j < k {
        var nrm = 0.0f64
        i = j
        while i < m {
            nrm += qa[j * m + i] * qa[j * m + i]
            i += 1usize
        }
        nrm = math.sqrt[f64](nrm)
        if nrm == 0.0f64 { ret (nan(), ok) }
        var alpha = 0.0f64 - nrm
        if qa[j * m + j] < 0.0f64 { alpha = nrm }
        i = j
        var vn = 0.0f64
        while i < m {
            vv[i] = qa[j * m + i]
            if i == j { vv[i] = vv[i] - alpha }
            vn += vv[i] * vv[i]
            i += 1usize
        }
        if vn > 0.0f64 {
            var jj = j
            while jj < k {
                var dot = 0.0f64
                i = j
                while i < m {
                    dot += vv[i] * qa[jj * m + i]
                    i += 1usize
                }
                let f = 2.0f64 * dot / vn
                i = j
                while i < m {
                    qa[jj * m + i] -= f * vv[i]
                    i += 1usize
                }
                jj += 1usize
            }
            var dotb = 0.0f64
            i = j
            while i < m {
                dotb += vv[i] * qb[i]
                i += 1usize
            }
            let fb = 2.0f64 * dotb / vn
            i = j
            while i < m {
                qb[i] -= fb * vv[i]
                i += 1usize
            }
        }
        j += 1usize
    }
    var jb = k
    while jb > 0usize {
        jb -= 1usize
        var s = qb[jb]
        var l = jb + 1usize
        while l < k {
            s -= qa[l * m + jb] * coef[l]
            l += 1usize
        }
        if qa[jb * m + jb] == 0.0f64 { ret (nan(), ok) }
        coef[jb] = s / qa[jb * m + jb]
    }
    var rss = 0.0f64
    i = 0usize
    while i < m {
        var fit = 0.0f64
        j = 0usize
        while j < k {
            fit += xm[j * m + i] * coef[j]
            j += 1usize
        }
        res[i] = b[i] - fit
        if sw.len > 0usize { rss += res[i] * res[i] * (sw[i] * sw[i]) } else { rss += res[i] * res[i] }
        i += 1usize
    }
    ret (rss, ok)
}

fn deveps() -> f64 { ret 2.220446049250313e-16f64 }

fn ylogy(y: f64, mu: f64) -> f64 {
    if y != 0.0f64 { ret y * math.log[f64](y / mu) }
    ret 0.0f64
}

// R's family functions for binomial (logit, fam 1) and poisson (log, fam 2): inverse link, d mu / d eta, variance, deviance residual
fn linkinv(fam: usize, eta: f64) -> f64 {
    if fam == 1usize {
        var t = 0.0f64
        if eta < 0.0f64 - 30.0f64 {
            t = deveps()
        } else if eta > 30.0f64 {
            t = 1.0f64 / deveps()
        } else {
            t = math.exp[f64](eta)
        }
        ret t / (1.0f64 + t)
    }
    var e = math.exp[f64](eta)
    if e < deveps() { e = deveps() }
    ret e
}

fn mueta(fam: usize, eta: f64) -> f64 {
    if fam == 1usize {
        let op = 1.0f64 + math.exp[f64](eta)
        if eta > 30.0f64 || eta < 0.0f64 - 30.0f64 { ret deveps() }
        ret math.exp[f64](eta) / (op * op)
    }
    var e = math.exp[f64](eta)
    if e < deveps() { e = deveps() }
    ret e
}

fn varfun(fam: usize, mu: f64) -> f64 {
    if fam == 1usize { ret mu * (1.0f64 - mu) }
    ret mu
}

fn devres(fam: usize, y: f64, mu: f64) -> f64 {
    if fam == 1usize { ret 2.0f64 * (ylogy(y, mu) + ylogy(1.0f64 - y, 1.0f64 - mu)) }
    if y > 0.0f64 { ret 2.0f64 * (y * math.log[f64](y / mu) - (y - mu)) }
    ret 2.0f64 * mu
}

// R's glm.fit IRLS for a 0/1 or count response (fam 1 binomial, 2 poisson), partykit's glmfit: the coefficients, the working-residual scores wres = (y - mu) / mu.eta * w^2 with the weights of the last iteration's start, and the negative log-likelihood
fn glmfit(a: *mem.Arena, c: *const MCtx, sub: []const usize, coef: []f64, wres: []f64) -> (f64, err) {
    let m = sub.len
    let k = c.kx + 1usize
    var fam = c.fam
    if fam == 4usize { fam = 1usize }
    if fam == 5usize { fam = 2usize }
    let (eta, e1) = mem.alloc[f64](a, m)
    let (mu, e2) = mem.alloc[f64](a, m)
    let (zz, e3) = mem.alloc[f64](a, m)
    let (ww, e4) = mem.alloc[f64](a, m)
    let (w2, e5) = mem.alloc[f64](a, m)
    let (rb, e6) = mem.alloc[f64](a, m)
    let (yy, e7) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret (0.0f64, mem.Full) }
    var i = 0usize
    while i < m {
        yy[i] = c.y[sub[i]]
        if fam == 1usize {
            let wi0 = rw(c, sub[i])
            let ms = (wi0 * yy[i] + 0.5f64) / (wi0 + 1.0f64)
            eta[i] = math.log[f64](ms / (1.0f64 - ms))
        } else {
            eta[i] = math.log[f64](yy[i] + 0.1f64)
        }
        mu[i] = linkinv(fam, eta[i])
        i += 1usize
    }
    var devold = 0.0f64
    i = 0usize
    while i < m {
        devold += rw(c, sub[i]) * devres(fam, yy[i], mu[i])
        i += 1usize
    }
    var iter = 0usize
    var done = false
    while iter < 25usize && !done {
        i = 0usize
        while i < m {
            let me = mueta(fam, eta[i])
            var of0 = 0.0f64
            if c.off.len > 0usize { of0 = c.off[sub[i]] }
            zz[i] = (eta[i] - of0) + (yy[i] - mu[i]) / me
            ww[i] = math.sqrt[f64](rw(c, sub[i]) * me * me / varfun(fam, mu[i]))
            w2[i] = ww[i] * ww[i]
            i += 1usize
        }
        let (rr, ef) = ols(a, c, sub, coef, rb, ww, zz)
        if ef != ok { ret (0.0f64, ef) }
        if !(rr == rr) { ret (rr, ok) }
        var dev = 0.0f64
        i = 0usize
        while i < m {
            var s = coef[0usize]
            var j = 0usize
            while j < c.kx {
                s += c.xr[j * c.n + sub[i]] * coef[j + 1usize]
                j += 1usize
            }
            if c.off.len > 0usize { s += c.off[sub[i]] }
            eta[i] = s
            mu[i] = linkinv(fam, s)
            dev += rw(c, sub[i]) * devres(fam, yy[i], mu[i])
            i += 1usize
        }
        var dd = dev - devold
        if dd < 0.0f64 { dd = 0.0f64 - dd }
        var ad = dev
        if ad < 0.0f64 { ad = 0.0f64 - ad }
        if dd / (ad + 0.1f64) < 0.00000001f64 { done = true } else { devold = dev }
        iter += 1usize
    }
    var ll = 0.0f64
    var dv = 0.0f64
    i = 0usize
    while i < m {
        let wi = rw(c, sub[i])
        wres[i] = (yy[i] - mu[i]) / mueta(fam, eta[i]) * w2[i]
        dv += wi * devres(fam, yy[i], mu[i])
        if fam == 1usize {
            // dbinom(round(w y), round(w), mu, log = TRUE)
            let nn = math.round[f64](wi)
            let xx = math.round[f64](wi * yy[i])
            ll += nm.lgammafn(nn + 1.0f64) - nm.lgammafn(xx + 1.0f64) - nm.lgammafn(nn - xx + 1.0f64) + xx * math.log[f64](mu[i]) + (nn - xx) * math.log[f64](1.0f64 - mu[i])
        } else {
            ll += wi * (0.0f64 - mu[i] + yy[i] * math.log[f64](mu[i]) - nm.lgammafn(yy[i] + 1.0f64))
        }
        i += 1usize
    }
    // the quasi families score the deviance, the others the negative log-likelihood
    if c.fam == 4usize || c.fam == 5usize { ret (dv, ok) }
    ret (0.0f64 - ll, ok)
}

// the node model: objfun (rss for fam 0, the negative log-likelihood otherwise) with coef and the score residuals res
fn fit_sub(a: *mem.Arena, c: *const MCtx, sub: []const usize, coef: []f64, res: []f64) -> (f64, err) {
    if c.fam != 0usize && c.fam != 3usize {
        let (g, eg) = glmfit(a, c, sub, coef, res)
        ret (g, eg)
    }
    let (yv, e1) = mem.alloc[f64](a, sub.len)
    if e1 != ok { ret (0.0f64, e1) }
    var i = 0usize
    while i < sub.len {
        yv[i] = c.y[sub[i]]
        if c.off.len > 0usize { yv[i] = yv[i] - c.off[sub[i]] }
        i += 1usize
    }
    var nw: []const f64 = zero
    if c.wt.len > 0usize {
        let (sq, e3) = mem.alloc[f64](a, sub.len)
        if e3 != ok { ret (0.0f64, e3) }
        i = 0usize
        while i < sub.len {
            sq[i] = math.sqrt[f64](c.wt[sub[i]])
            i += 1usize
        }
        nw = sq
    }
    let (r, e2) = ols(a, c, sub, coef, res, nw, yv)
    if e2 != ok { ret (r, e2) }
    if c.fam == 3usize {
        // glm(family = gaussian): -logLik is aic / 2 less its parameters, nobs / 2 * (log(2 pi dev / nobs) + 1) - sum(log w)
        let nobs = f64(sub.len)
        var slw = 0.0f64
        i = 0usize
        while i < sub.len {
            slw += math.log[f64](rw(c, sub[i]))
            i += 1usize
        }
        ret (nobs / 2.0f64 * (math.log[f64](r / nobs * 2.0f64 * 3.141592653589793f64) + 1.0f64) - slw / 2.0f64, ok)
    }
    ret (r, ok)
}

// the score weight of row r: the working residuals of a glm already carry the case weight, a linear model's do not
fn rws(c: *const MCtx, r: usize) -> f64 {
    if c.fam == 0usize || c.fam == 3usize { ret rw(c, r) }
    ret 1.0f64
}

// inverse of the symmetric positive definite k by k matrix s by Cholesky; false when it is not positive definite
fn chol_inv(s: []const f64, k: usize, inv: []f64, a: *mem.Arena) -> (bool, err) {
    let (l, e1) = mem.alloc[f64](a, k * k)
    if e1 != ok { ret (false, e1) }
    var i = 0usize
    while i < k * k {
        l[i] = 0.0f64
        i += 1usize
    }
    var j = 0usize
    while j < k {
        var d = s[j * k + j]
        var q = 0usize
        while q < j {
            d -= l[q * k + j] * l[q * k + j]
            q += 1usize
        }
        if !(d > 0.0f64) { ret (false, ok) }
        l[j * k + j] = math.sqrt[f64](d)
        i = j + 1usize
        while i < k {
            var v = s[j * k + i]
            q = 0usize
            while q < j {
                v -= l[q * k + i] * l[q * k + j]
                q += 1usize
            }
            l[j * k + i] = v / l[j * k + j]
            i += 1usize
        }
        j += 1usize
    }
    // solve L L' X = I column by column
    var col = 0usize
    while col < k {
        var w = 0usize
        while w < k {
            var v = 0.0f64
            if w == col { v = 1.0f64 }
            var q = 0usize
            while q < w {
                v -= l[q * k + w] * inv[col * k + q]
                q += 1usize
            }
            inv[col * k + w] = v / l[w * k + w]
            w += 1usize
        }
        w = k
        while w > 0usize {
            w -= 1usize
            var v = inv[col * k + w]
            var q = w + 1usize
            while q < k {
                v -= l[w * k + q] * inv[col * k + q]
                q += 1usize
            }
            inv[col * k + w] = v / l[w * k + w]
        }
        col += 1usize
    }
    ret (true, ok)
}

// the 25 rows (3 numbers each) of strucchange's beta.sup table for k regressors
fn beta_rows(k: usize, out: []f64) {
    let t = tb.sc_sup()
    let first = (k - 1usize) * 25usize * 3usize
    let last = first + 75usize
    var idx = 0usize
    var start = 0usize
    var i = 0usize
    while i <= t.len {
        if i == t.len || t[i] == 59u8 {
            if idx >= first && idx < last {
                let (v, e) = str.parse_f64(t[start..i])
                out[idx - first] = v
                if e != ok { out[idx - first] = nan() }
            }
            idx += 1usize
            start = i + 1usize
            if idx >= last { ret }
        }
        i += 1usize
    }
}

fn finite(x: f64) -> bool { ret x == x && x < inf() && x > 0.0f64 - inf() }

// log p of the supLM statistic x for k parameters and lambda, partykit's logp.supLM
fn logp_suplm(x: f64, k: usize, lambda: f64) -> f64 {
    let kf = f64(k)
    if k > 40usize {
        let k15 = 1.5f64 * kf
        var xe = x
        var scale = 0.0f64
        if x <= k15 {
            xe = k15
            scale = math.pow[f64](x / k15, math.sqrt[f64](kf))
        }
        let lg = 0.0f64 - nm.lgammafn(kf / 2.0f64) + kf / 2.0f64 * math.log[f64](xe / 2.0f64) - xe / 2.0f64 + math.log[f64](math.abs[f64](math.log[f64](lambda) * (1.0f64 - kf / xe) + 2.0f64 / xe))
        if x <= k15 { ret scale * lg }
        ret lg
    }
    var tau = lambda
    if !(lambda < 1.0f64) { tau = 1.0f64 / (1.0f64 + math.sqrt[f64](lambda)) }
    var tab: [75]f64 = zero
    beta_rows(k, tab[0usize..75usize])
    var pp: [25]f64 = zero
    var r = 0usize
    while r < 25usize {
        var d = tab[r * 3usize] + tab[r * 3usize + 1usize] * x
        if !(d > 0.0f64) { d = 0.0f64 }
        pp[r] = nm.pchisq(d, tab[r * 3usize + 2usize], false, true)
        r += 1usize
    }
    let pk0 = nm.pchisq(x, kf, false, true)
    if tau == 0.5f64 { ret pk0 }
    if tau <= 0.01f64 { ret pp[24usize] }
    if tau >= 0.49f64 {
        let p = math.log[f64]((math.exp[f64](math.log[f64](0.5f64 - tau) + pp[0usize]) + math.exp[f64](math.log[f64](tau - 0.49f64) + pk0)) * 100.0f64)
        if !finite(p) { ret (pp[0usize] + pk0) / 2.0f64 }
        ret p
    }
    let taua = (0.51f64 - tau) * 50.0f64
    let tau1 = math.floor[f64](taua)
    let i1 = usize(tau1)
    let p2 = math.log[f64](math.exp[f64](math.log[f64](tau1 + 1.0f64 - taua) + pp[i1 - 1usize]) + math.exp[f64](math.log[f64](taua - tau1) + pp[i1]))
    if !finite(p2) { ret (pp[i1 - 1usize] + pp[i1]) / 2.0f64 }
    ret p2
}

fn quadj(g: []const f64, j: []const f64, k: usize) -> f64 {
    var s = 0.0f64
    var p = 0usize
    while p < k {
        var q = 0usize
        while q < k {
            s += g[p] * j[q * k + p] * g[q]
            q += 1usize
        }
        p += 1usize
    }
    ret s
}

fn grow(a: *mem.Arena, c: *const MCtx, ctl: *const MCtl, o: *MOut, sub: []usize, id: usize, depth: usize) -> (usize, err) {
    let k = c.kx + 1usize
    let nd = id - 1usize
    let m = sub.len
    let mf = sumw(c, sub)
    if id > o.count { o.count = id }
    o.vr[nd] = 0i64
    o.pval[nd] = nan()
    o.nobs[nd] = mf
    let (coef, e1) = mem.alloc[f64](a, k)
    let (res, e2) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok { ret (id, mem.Full) }
    let (rss, e3) = fit_sub(a, c, sub, coef, res)
    if e3 != ok { ret (id, e3) }
    o.objfun[nd] = rss
    var q = 0usize
    while q < k {
        o.coef[nd * k + q] = coef[q]
        q += 1usize
    }
    q = 0usize
    while q < c.pz {
        o.stat[nd * c.pz + q] = nan()
        o.adjp[nd * c.pz + q] = nan()
        q += 1usize
    }
    if o.minsize == 0usize { o.minsize = usize(math.ceil[f64](10.0f64 * f64(k))) }
    let minsize = o.minsize
    if mf < f64(2usize * minsize) { ret (id, ok) }
    if depth >= ctl.maxdepth { ret (id, ok) }
    // mtry: the partitioning variables tested at this node are sort(sample(1:m, mtry)), drawn before anything else of the test
    let (usev, eu) = mem.alloc[bool](a, c.pz)
    if eu != ok { ret (id, mem.Full) }
    var uj = 0usize
    while uj < c.pz {
        usev[uj] = true
        uj += 1usize
    }
    if ctl.mtry > 0usize && c.pz > ctl.mtry {
        uj = 0usize
        while uj < c.pz {
            usev[uj] = false
            uj += 1usize
        }
        let (pick, ep) = rnd.sample_int(a, ctl.rg, i64(c.pz), i64(ctl.mtry), false)
        if ep != ok { ret (id, ep) }
        uj = 0usize
        while uj < ctl.mtry {
            usev[usize(pick[uj]) - 1usize] = true
            uj += 1usize
        }
    }
    // partykit's mob_grow_fluctests drops the zero-weight rows from the scores but divides them by the unfiltered weights (recycled): a zero weight reached makes the outer product non-finite and chol fails, and with clusters tapply meets scores and clusters of different length; the node stays a leaf. vcov = info never forms that product (a zero weight there is not supported)
    var nzero = 0usize
    var zi = 0usize
    while zi < m {
        if rw(c, sub[zi]) == 0.0f64 { nzero += 1usize }
        zi += 1usize
    }
    if nzero > 0usize && c.vc != 1usize && (c.cl.len > 0usize || k * (m - nzero) >= m) { ret (id, ok) }
    // parameter instability tests
    let (pr, e4) = mem.alloc[f64](a, c.n * k)
    let (meat, e5) = mem.alloc[f64](a, k * k)
    let (jinv, e6) = mem.alloc[f64](a, k * k)
    if e4 != ok || e5 != ok || e6 != ok { ret (id, mem.Full) }
    var i = 0usize
    while i < m {
        q = 0usize
        while q < k {
            var xv = 1.0f64
            if q > 0usize { xv = c.xr[(q - 1usize) * c.n + sub[i]] }
            pr[q * c.n + sub[i]] = res[i] * xv * rws(c, sub[i]) / math.sqrt[f64](mf)
            q += 1usize
        }
        i += 1usize
    }
    var p1 = 0usize
    while p1 < k {
        var p2 = 0usize
        while p2 < k {
            var s = 0.0f64
            if c.cl.len == 0usize {
                i = 0usize
                while i < m {
                    s += (pr[p1 * c.n + sub[i]] * pr[p2 * c.n + sub[i]]) / rw(c, sub[i])
                    i += 1usize
                }
            }
            meat[p2 * k + p1] = s
            p2 += 1usize
        }
        p1 += 1usize
    }
    if c.cl.len > 0usize {
        // the meat of clustered scores: the weight-scaled scores summed within each cluster, then crossed
        var ncl = 0usize
        i = 0usize
        while i < m {
            if c.cl[sub[i]] + 1usize > ncl { ncl = c.cl[sub[i]] + 1usize }
            i += 1usize
        }
        let (csm, e5b) = mem.alloc[f64](a, ncl * k)
        if e5b != ok { ret (id, mem.Full) }
        i = 0usize
        while i < ncl * k {
            csm[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < m {
            q = 0usize
            while q < k {
                csm[c.cl[sub[i]] * k + q] += pr[q * c.n + sub[i]] / math.sqrt[f64](rw(c, sub[i]))
                q += 1usize
            }
            i += 1usize
        }
        p1 = 0usize
        while p1 < k {
            var p2 = 0usize
            while p2 < k {
                var s = 0.0f64
                var g = 0usize
                while g < ncl {
                    s += csm[g * k + p1] * csm[g * k + p2]
                    g += 1usize
                }
                meat[p2 * k + p1] = s
                p2 += 1usize
            }
            p1 += 1usize
        }
    }
    if c.vc == 0usize {
        let (pd, e7) = chol_inv(meat, k, jinv, a)
        if e7 != ok { ret (id, e7) }
        if !pd { ret (id, ok) }
    } else {
        // bread = vcov(lm) * nobs, vcov = sigma^2 (X'WX)^-1 with sigma^2 = rss / (rows - coefficients); info uses it alone, sandwich bread meat bread
        if m <= k { ret (id, ok) }
        let (xtx, e5c) = mem.alloc[f64](a, k * k)
        let (xin, e5d) = mem.alloc[f64](a, k * k)
        let (brd, e5e) = mem.alloc[f64](a, k * k)
        if e5c != ok || e5d != ok || e5e != ok { ret (id, mem.Full) }
        p1 = 0usize
        while p1 < k {
            var p2 = 0usize
            while p2 < k {
                var s = 0.0f64
                i = 0usize
                while i < m {
                    var xa = 1.0f64
                    if p1 > 0usize { xa = c.xr[(p1 - 1usize) * c.n + sub[i]] }
                    var xb = 1.0f64
                    if p2 > 0usize { xb = c.xr[(p2 - 1usize) * c.n + sub[i]] }
                    s += (xa * xb) * rw(c, sub[i])
                    i += 1usize
                }
                xtx[p2 * k + p1] = s
                p2 += 1usize
            }
            p1 += 1usize
        }
        let (pd2, e7b) = chol_inv(xtx, k, xin, a)
        if e7b != ok { ret (id, e7b) }
        if !pd2 { ret (id, ok) }
        let scale = rss / f64(m - k) * mf
        p1 = 0usize
        while p1 < k * k {
            brd[p1] = xin[p1] * scale
            p1 += 1usize
        }
        if c.vc == 1usize {
            p1 = 0usize
            while p1 < k * k {
                jinv[p1] = brd[p1]
                p1 += 1usize
            }
        } else {
            let (bm, e5f) = mem.alloc[f64](a, k * k)
            if e5f != ok { ret (id, mem.Full) }
            p1 = 0usize
            while p1 < k {
                var p2 = 0usize
                while p2 < k {
                    var s = 0.0f64
                    var l = 0usize
                    while l < k {
                        s += brd[l * k + p1] * meat[p2 * k + l]
                        l += 1usize
                    }
                    bm[p2 * k + p1] = s
                    p2 += 1usize
                }
                p1 += 1usize
            }
            p1 = 0usize
            while p1 < k {
                var p2 = 0usize
                while p2 < k {
                    var s = 0.0f64
                    var l = 0usize
                    while l < k {
                        s += bm[l * k + p1] * brd[p2 * k + l]
                        l += 1usize
                    }
                    jinv[p2 * k + p1] = s
                    p2 += 1usize
                }
                p1 += 1usize
            }
        }
    }
    var from = math.ceil[f64](mf * ctl.trim)
    if from < f64(minsize) { from = f64(minsize) }
    let to = mf - from
    let lambda = (mf - from) * to / (from * (mf - to))
    let (lp, e8) = mem.alloc[f64](a, c.pz)
    let (okv, e9) = mem.alloc[bool](a, c.pz)
    let (cs, e10) = mem.alloc[f64](a, k)
    let (srt, e11) = mem.alloc[usize](a, m)
    if e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret (id, mem.Full) }
    var j = 0usize
    while j < c.pz {
        okv[j] = false
        o.stat[nd * c.pz + j] = 0.0f64
        var lv = c.nl[j]
        var gofs = 0usize
        if lv >= 1000000usize {
            lv -= 1000000usize
            gofs = 1usize
        }
        i = 0usize
        while i < m {
            srt[i] = sub[i]
            i += 1usize
        }
        pk.sort_by(srt, c.z, j, c.n)
        var distinct = false
        i = 1usize
        while i < m {
            if c.z[j * c.n + srt[i]] != c.z[j * c.n + srt[0usize]] { distinct = true }
            i += 1usize
        }
        if distinct && usev[j] {
            if lv == 0usize {
                if ctl.bties {
                    // breakties: the order is that of z plus uniform noise within a tenth of the smallest gap
                    var mm = 1.0f64
                    var gotg = false
                    i = 1usize
                    while i < m {
                        let dz = c.z[j * c.n + srt[i]] - c.z[j * c.n + srt[i - 1usize]]
                        if dz > 0.0f64 && (!gotg || dz / 10.0f64 < mm) {
                            mm = dz / 10.0f64
                            gotg = true
                        }
                        i += 1usize
                    }
                    let (ky, ek) = mem.alloc[f64](a, m)
                    let (oi2, eo2) = mem.alloc[usize](a, m)
                    if ek != ok || eo2 != ok { ret (id, mem.Full) }
                    i = 0usize
                    while i < m {
                        ky[i] = c.z[j * c.n + sub[i]] + rnd.runif(ctl.rg, 0.0f64 - mm, mm)
                        oi2[i] = i
                        i += 1usize
                    }
                    i = 1usize
                    while i < m {
                        let v2 = oi2[i]
                        var jj2 = i
                        while jj2 > 0usize && ky[oi2[jj2 - 1usize]] > ky[v2] {
                            oi2[jj2] = oi2[jj2 - 1usize]
                            jj2 -= 1usize
                        }
                        oi2[jj2] = v2
                        i += 1usize
                    }
                    i = 0usize
                    while i < m {
                        srt[i] = sub[oi2[i]]
                        i += 1usize
                    }
                }
                q = 0usize
                while q < k {
                    cs[q] = 0.0f64
                    q += 1usize
                }
                var best = 0.0f64
                var any = false
                var tcum = 0.0f64
                i = 0usize
                while i < m {
                    q = 0usize
                    while q < k {
                        cs[q] += pr[q * c.n + srt[i]]
                        q += 1usize
                    }
                    tcum += rw(c, srt[i])
                    let t0 = tcum
                    if t0 >= from && t0 <= to {
                        let tt = t0 / mf
                        let v = quadj(cs, jinv, k) / (tt * (1.0f64 - tt))
                        if !any || v > best { best = v }
                        any = true
                    }
                    i += 1usize
                }
                if any {
                    o.stat[nd * c.pz + j] = best
                    lp[j] = logp_suplm(best, k, lambda)
                    okv[j] = true
                }
            } else {
                // unordered factor: grouped score sums over the levels present
                let (gs, e12) = mem.alloc[f64](a, lv * k)
                let (gc, e13) = mem.alloc[f64](a, lv)
                if e12 != ok || e13 != ok { ret (id, mem.Full) }
                var l = 0usize
                while l < lv {
                    gc[l] = 0.0f64
                    q = 0usize
                    while q < k {
                        gs[l * k + q] = 0.0f64
                        q += 1usize
                    }
                    l += 1usize
                }
                i = 0usize
                while i < m {
                    let g = usize(c.z[j * c.n + sub[i]]) - gofs
                    gc[g] += rw(c, sub[i])
                    q = 0usize
                    while q < k {
                        gs[g * k + q] += pr[q * c.n + sub[i]]
                        q += 1usize
                    }
                    i += 1usize
                }
                var st = 0.0f64
                var nlev = 0usize
                l = 0usize
                while l < lv {
                    if gc[l] > 0.0f64 {
                        nlev += 1usize
                        st += quadj(gs[l * k..l * k + k], jinv, k) / (gc[l] / mf)
                    }
                    l += 1usize
                }
                o.stat[nd * c.pz + j] = st
                lp[j] = nm.pchisq(st, f64(k * (nlev - 1usize)), false, true)
                okv[j] = true
            }
        }
        j += 1usize
    }
    var nvalid = 0usize
    var best = c.pz
    j = 0usize
    while j < c.pz {
        if okv[j] {
            nvalid += 1usize
            if best == c.pz || lp[j] < lp[best] { best = j }
        }
        j += 1usize
    }
    if nvalid == 0usize { ret (id, ok) }
    j = 0usize
    while j < c.pz {
        if okv[j] {
            let p = math.exp[f64](lp[j])
            var adj = p
            if ctl.bonf {
                let nv = f64(nvalid)
                var pa = nv * p
                if pa > 1.0f64 { pa = 1.0f64 }
                let pb = 1.0f64 - math.exp[f64](nv * math.log[f64](1.0f64 - p))
                if p > 0.001f64 { adj = pb } else { adj = pa }
            }
            o.adjp[nd * c.pz + j] = adj
        }
        j += 1usize
    }
    o.pval[nd] = o.adjp[nd * c.pz + best]
    if o.pval[nd] > ctl.alpha { ret (id, ok) }
    // split search on the chosen variable
    var lv = c.nl[best]
    var ordb = false
    if lv >= 1000000usize {
        ordb = true
        lv = 0usize
    }
    var brk = 0.0f64
    var found = false
    let (dir, e14) = mem.alloc[i64](a, o.maxlev + 1usize)
    if e14 != ok { ret (id, mem.Full) }
    let (ls, e15) = mem.alloc[usize](a, m)
    let (rs, e16) = mem.alloc[usize](a, m)
    let (cf2, e17) = mem.alloc[f64](a, k)
    let (rs2, e18) = mem.alloc[f64](a, m)
    if e15 != ok || e16 != ok || e17 != ok || e18 != ok { ret (id, mem.Full) }
    if lv == 0usize {
        let (uz, e19) = mem.alloc[f64](a, m)
        if e19 != ok { ret (id, e19) }
        var nu = 0usize
        i = 0usize
        while i < m {
            srt[i] = sub[i]
            i += 1usize
        }
        pk.sort_by(srt, c.z, best, c.n)
        i = 0usize
        while i < m {
            let zv = c.z[best * c.n + srt[i]]
            if nu == 0usize || zv != uz[nu - 1usize] {
                uz[nu] = zv
                nu += 1usize
            }
            i += 1usize
        }
        var bestdev = inf()
        var u = 0usize
        while u < nu {
            var nl2 = 0usize
            var nr2 = 0usize
            i = 0usize
            while i < m {
                if c.z[best * c.n + sub[i]] <= uz[u] {
                    ls[nl2] = sub[i]
                    nl2 += 1usize
                } else {
                    rs[nr2] = sub[i]
                    nr2 += 1usize
                }
                i += 1usize
            }
            var dev = inf()
            if sumw(c, ls[0usize..nl2]) >= f64(minsize) && sumw(c, rs[0usize..nr2]) >= f64(minsize) {
                let start = mem.mark(a)
                let (r1, e20) = fit_sub(a, c, ls[0usize..nl2], cf2, rs2)
                let (r2, e21) = fit_sub(a, c, rs[0usize..nr2], cf2, rs2)
                mem.reset(a, start)
                if e20 != ok || e21 != ok { ret (id, mem.Full) }
                dev = r1 + r2
            }
            if dev < bestdev {
                bestdev = dev
                brk = uz[u]
                if ctl.center && !ordb && u + 1usize < nu { brk = (uz[u] + uz[u + 1usize]) / 2.0f64 }
                found = true
            }
            u += 1usize
        }
        if !found && nu > 0usize { found = false }
    } else {
        let (pres, e19) = mem.alloc[usize](a, lv)
        let (gc, e20) = mem.alloc[f64](a, lv)
        if e19 != ok || e20 != ok { ret (id, mem.Full) }
        var l = 0usize
        while l < lv {
            gc[l] = 0.0f64
            dir[l] = 0i64 - 1i64
            l += 1usize
        }
        i = 0usize
        while i < m {
            gc[usize(c.z[best * c.n + sub[i]])] += 1.0f64
            i += 1usize
        }
        var npz = 0usize
        l = 0usize
        while l < lv {
            if gc[l] > 0.0f64 {
                pres[npz] = l
                npz += 1usize
            }
            l += 1usize
        }
        var nrow = 1usize
        l = 1usize
        while l < npz {
            nrow *= 2usize
            l += 1usize
        }
        nrow -= 1usize
        var bestdev = inf()
        var row = 1usize
        while row <= nrow {
            // level p (0-based among the present ones) is in the left group when bit p of the row is set
            var nl2 = 0usize
            var nr2 = 0usize
            i = 0usize
            while i < m {
                let lvl = usize(c.z[best * c.n + sub[i]])
                var pos = 0usize
                while pres[pos] != lvl { pos += 1usize }
                var bit = row
                var w = 0usize
                while w < pos {
                    bit /= 2usize
                    w += 1usize
                }
                if bit % 2usize == 1usize {
                    ls[nl2] = sub[i]
                    nl2 += 1usize
                } else {
                    rs[nr2] = sub[i]
                    nr2 += 1usize
                }
                i += 1usize
            }
            var dev = inf()
            if sumw(c, ls[0usize..nl2]) >= f64(minsize) && sumw(c, rs[0usize..nr2]) >= f64(minsize) {
                if nrow == 1usize {
                    dev = 1.0f64
                } else {
                    let start = mem.mark(a)
                    let (r1, e21) = fit_sub(a, c, ls[0usize..nl2], cf2, rs2)
                    let (r2, e22) = fit_sub(a, c, rs[0usize..nr2], cf2, rs2)
                    mem.reset(a, start)
                    if e21 != ok || e22 != ok { ret (id, mem.Full) }
                    dev = r1 + r2
                }
            }
            if dev < bestdev {
                bestdev = dev
                found = true
                var pp = 0usize
                while pp < npz {
                    var b2 = row
                    var w2 = 0usize
                    while w2 < pp {
                        b2 /= 2usize
                        w2 += 1usize
                    }
                    dir[pres[pp]] = 1i64
                    if b2 % 2usize == 1usize { dir[pres[pp]] = 0i64 }
                    pp += 1usize
                }
            }
            row += 1usize
        }
    }
    if !found { ret (id, ok) }
    o.vr[nd] = i64(best + 1usize)
    o.brk[nd] = brk
    var n1 = 0usize
    var n2 = 0usize
    i = 0usize
    while i < m {
        let zv = c.z[best * c.n + sub[i]]
        var left = false
        if lv == 0usize { left = zv <= brk } else { left = dir[usize(zv)] == 0i64 }
        if left { n1 += 1usize } else { n2 += 1usize }
        i += 1usize
    }
    let (s1, e23) = mem.alloc[usize](a, n1)
    let (s2, e24) = mem.alloc[usize](a, n2)
    if e23 != ok || e24 != ok { ret (id, mem.Full) }
    n1 = 0usize
    n2 = 0usize
    i = 0usize
    while i < m {
        let zv = c.z[best * c.n + sub[i]]
        var left = false
        if lv == 0usize { left = zv <= brk } else { left = dir[usize(zv)] == 0i64 }
        if left {
            s1[n1] = sub[i]
            n1 += 1usize
        } else {
            s2[n2] = sub[i]
            n2 += 1usize
        }
        i += 1usize
    }
    var lq = 0usize
    while lq < o.maxlev {
        o.lmap[nd * o.maxlev + lq] = 0i64 - 1i64
        if lv > 0usize && lq < lv { o.lmap[nd * o.maxlev + lq] = dir[lq] }
        lq += 1usize
    }
    o.kid1[nd] = i64(id + 1usize)
    let (mx1, e25) = grow(a, c, ctl, o, s1, id + 1usize, depth + 1usize)
    if e25 != ok { ret (mx1, e25) }
    o.kid2[nd] = i64(mx1 + 1usize)
    let (mx2, e26) = grow(a, c, ctl, o, s2, mx1 + 1usize, depth + 1usize)
    ret (mx2, e26)
}

// wt the positive case weights, off the offset, cl cluster codes 0 .. C - 1, vc 0 opg, 1 info, 2 sandwich: empty / 0 for none (a zero weight is not supported: partykit indexes the weights of the retained rows with positions of the filtered ones)
// lmtree(y ~ x | z): xr holds the regressors (n by kx, without the intercept), z the partitioning variables (n by pz), nl[j] = 0 numeric or the level count of a factor (codes 0 .. nl - 1);
// minsize 0 takes partykit's default ceiling(10 * number of coefficients)
fn lmtree(a: *mem.Arena, xr: []const f64, kx: usize, y: []const f64, n: usize, z: []const f64, pz: usize, nl: []const usize, fam: usize, alpha: f64, bonf: bool, minsize: usize, maxdepth: usize, trim: f64, center: bool, prune: usize, wt: []const f64, off: []const f64, cl: []const usize, vc: usize) -> (MOut, err) {
    let (o, e) = lmtree_x(a, xr, kx, y, n, z, pz, nl, fam, alpha, bonf, minsize, maxdepth, trim, center, prune, wt, off, cl, vc, 0usize, false, 1i64)
    ret (o, e)
}

// lmtree with mtry partitioning variables drawn per node (0 = all), breakties and R's set.seed(seed) in force
fn lmtree_x(a: *mem.Arena, xr: []const f64, kx: usize, y: []const f64, n: usize, z: []const f64, pz: usize, nl: []const usize, fam: usize, alpha: f64, bonf: bool, minsize: usize, maxdepth: usize, trim: f64, center: bool, prune: usize, wt: []const f64, off: []const f64, cl: []const usize, vc: usize, mtry: usize, bties: bool, seed: i64) -> (MOut, err) {
    var rg: rnd.Rng = zero
    rnd.seed(&rg, seed)
    var o: MOut = zero
    let k = kx + 1usize
    var ml = 1usize
    var j = 0usize
    while j < pz {
        if nlv(nl[j]) > ml { ml = nlv(nl[j]) }
        j += 1usize
    }
    let cap = 2usize * n + 2usize
    let (vr, e1) = mem.alloc[i64](a, cap)
    let (brk, e2) = mem.alloc[f64](a, cap)
    let (k1, e3) = mem.alloc[i64](a, cap)
    let (k2, e4) = mem.alloc[i64](a, cap)
    let (nb, e5) = mem.alloc[f64](a, cap)
    let (pv, e6) = mem.alloc[f64](a, cap)
    let (of, e7) = mem.alloc[f64](a, cap)
    let (cf, e8) = mem.alloc[f64](a, cap * k)
    let (lm, e9) = mem.alloc[i64](a, cap * ml)
    let (st, e10) = mem.alloc[f64](a, cap * pz)
    let (ap, e11) = mem.alloc[f64](a, cap * pz)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret (o, mem.Full) }
    var i = 0usize
    while i < cap {
        k1[i] = 0i64
        k2[i] = 0i64
        brk[i] = 0.0f64
        i += 1usize
    }
    o.vr = vr
    o.brk = brk
    o.kid1 = k1
    o.kid2 = k2
    o.nobs = nb
    o.pval = pv
    o.objfun = of
    o.coef = cf
    o.lmap = lm
    o.stat = st
    o.adjp = ap
    o.k = k
    o.pz = pz
    o.maxlev = ml
    o.count = 0usize
    o.minsize = minsize
    let c = MCtx { xr: xr, kx: kx, y: y, n: n, z: z, pz: pz, nl: nl, fam: fam, wt: wt, off: off, cl: cl, vc: vc }
    let ctl = MCtl { alpha: alpha, bonf: bonf, maxdepth: maxdepth, trim: trim, center: center, mtry: mtry, bties: bties, rg: &rg }
    let (sub, e12) = mem.alloc[usize](a, n)
    if e12 != ok { ret (o, e12) }
    i = 0usize
    while i < n {
        sub[i] = i
        i += 1usize
    }
    let (mx, eg) = grow(a, &c, &ctl, &o, sub, 1usize, 1usize)
    if eg != ok { ret (o, eg) }
    if prune > 0usize {
        let ep = prune_tree(a, &o, n, fam, prune)
        ret (o, ep)
    }
    ret (o, ok)
}

// post-pruning as mob does it: inner nodes whose children are all leaves go when the information criterion prefers the node's own model (prune 1 AIC, 2 BIC; lmtree's own
// criterion on n log(rss) for fam 0, 2 objfun + penalty otherwise), all accepted in one round, then the next round; the surviving nodes are renumbered in pre-order
fn prune_tree(a: *mem.Arena, o: *MOut, n: usize, fam: usize, prune: usize) -> err {
    let cnt = o.count
    let k = o.k
    let (lf, e1) = mem.alloc[bool](a, cnt)
    let (acc, e2) = mem.alloc[bool](a, cnt)
    if e1 != ok || e2 != ok { ret mem.Full }
    var i = 0usize
    while i < cnt {
        lf[i] = o.vr[i] == 0i64
        i += 1usize
    }
    var changed = true
    while changed {
        changed = false
        i = 0usize
        while i < cnt {
            acc[i] = false
            if !lf[i] {
                let k1 = usize(o.kid1[i]) - 1usize
                let k2 = usize(o.kid2[i]) - 1usize
                if lf[k1] && lf[k2] {
                    let obj1 = o.objfun[i]
                    let obj2 = o.objfun[k1] + o.objfun[k2]
                    let df1 = f64(k)
                    let df2 = 2.0f64 * f64(k) + 1.0f64
                    var pen = 2.0f64
                    if prune == 2usize { pen = math.log[f64](f64(n)) }
                    var lhs = 0.0f64
                    var rhs = 0.0f64
                    if fam == 0usize {
                        lhs = o.nobs[i] * math.log[f64](obj1) + pen * df1
                        rhs = o.nobs[i] * math.log[f64](obj2) + pen * df2
                    } else {
                        lhs = 2.0f64 * obj1 + pen * df1
                        rhs = 2.0f64 * obj2 + pen * df2
                    }
                    if lhs < rhs { acc[i] = true }
                }
            }
            i += 1usize
        }
        i = 0usize
        while i < cnt {
            if acc[i] {
                lf[i] = true
                changed = true
            }
            i += 1usize
        }
    }
    // pre-order renumbering
    let (ord, e3) = mem.alloc[usize](a, cnt)
    let (stk, e4) = mem.alloc[usize](a, cnt + 1usize)
    let (nid, e5) = mem.alloc[usize](a, cnt)
    if e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    var sp = 1usize
    stk[0usize] = 0usize
    var m = 0usize
    while sp > 0usize {
        sp -= 1usize
        let id = stk[sp]
        ord[m] = id
        nid[id] = m
        m += 1usize
        if !lf[id] {
            stk[sp] = usize(o.kid2[id]) - 1usize
            stk[sp + 1usize] = usize(o.kid1[id]) - 1usize
            sp += 2usize
        }
    }
    let ml = o.maxlev
    let pz = o.pz
    let (vr2, f1) = mem.alloc[i64](a, m)
    let (bk2, f2) = mem.alloc[f64](a, m)
    let (a1, f3) = mem.alloc[i64](a, m)
    let (a2, f4) = mem.alloc[i64](a, m)
    let (nb2, f5) = mem.alloc[f64](a, m)
    let (pv2, f6) = mem.alloc[f64](a, m)
    let (of2, f7) = mem.alloc[f64](a, m)
    let (cf2, f8) = mem.alloc[f64](a, m * k)
    let (lm2, f9) = mem.alloc[i64](a, m * ml)
    let (st2, f10) = mem.alloc[f64](a, m * pz)
    let (ap2, f11) = mem.alloc[f64](a, m * pz)
    if f1 != ok || f2 != ok || f3 != ok || f4 != ok || f5 != ok || f6 != ok || f7 != ok || f8 != ok || f9 != ok || f10 != ok || f11 != ok { ret mem.Full }
    i = 0usize
    while i < m {
        let old = ord[i]
        vr2[i] = o.vr[old]
        a1[i] = 0i64
        a2[i] = 0i64
        if lf[old] { vr2[i] = 0i64 }
        if !lf[old] {
            a1[i] = i64(nid[usize(o.kid1[old]) - 1usize] + 1usize)
            a2[i] = i64(nid[usize(o.kid2[old]) - 1usize] + 1usize)
        }
        bk2[i] = o.brk[old]
        nb2[i] = o.nobs[old]
        pv2[i] = o.pval[old]
        of2[i] = o.objfun[old]
        var q = 0usize
        while q < k {
            cf2[i * k + q] = o.coef[old * k + q]
            q += 1usize
        }
        q = 0usize
        while q < ml {
            lm2[i * ml + q] = o.lmap[old * ml + q]
            q += 1usize
        }
        q = 0usize
        while q < pz {
            st2[i * pz + q] = o.stat[old * pz + q]
            ap2[i * pz + q] = o.adjp[old * pz + q]
            q += 1usize
        }
        i += 1usize
    }
    o.vr = vr2
    o.brk = bk2
    o.kid1 = a1
    o.kid2 = a2
    o.nobs = nb2
    o.pval = pv2
    o.objfun = of2
    o.coef = cf2
    o.lmap = lm2
    o.stat = st2
    o.adjp = ap2
    o.count = m
    ret ok
}

// the node id (1-based) of observation i of z (nr rows)
fn predict_node(o: *const MOut, nl: []const usize, z: []const f64, nr: usize, i: usize) -> usize {
    var id = 1usize
    while o.vr[id - 1usize] != 0i64 {
        let k = id - 1usize
        let j = usize(o.vr[k] - 1i64)
        let zv = z[j * nr + i]
        var left = false
        if nl[j] == 0usize || nl[j] >= 1000000usize {
            left = zv <= o.brk[k]
        } else {
            left = o.lmap[k * o.maxlev + usize(zv)] == 0i64
        }
        if left { id = usize(o.kid1[k]) } else { id = usize(o.kid2[k]) }
    }
    ret id
}
