// R psych, the closed-form part: Cronbach `alpha` (raw and standardised), `kmo` (overall and per-item measure of
// sampling adequacy), `bartlett` (cortest.bartlett chi-square), `icc` (the six Shrout-Fleiss forms), `kappa`
// (unweighted Cohen kappa of a square table) and `mardia` (skewness and kurtosis statistics).
//
// Not here: omega, fa with its five methods, principal, polychoric, tetrachoric, biserial, fa.parallel, VSS,
// corr.test, describe, describeBy, scoreItems, weighted kappa, kappa confidence limits.

use e.algo.stat.quantreg as qr
use e.math
use e.math.nmath_beta as nbt
use e.math.dist as dst
use e.algo.stat.desctools as dt
use e.mem

error Malformed
use e.algo.stat.gparot as gp
use e.algo.linalg.lapack_syevr as sy
use e.algo.stat.fdrtool as fd
use e.algo.stat.pbivnorm as pbv

// column-major n by p
fn colmean(x: []const f64, n: usize, j: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += x[j * n + i]
        i += 1usize
    }
    ret s / f64(n)
}

fn covar(x: []const f64, n: usize, j: usize, k: usize) -> f64 {
    let mj = colmean(x, n, j)
    let mk = colmean(x, n, k)
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += (x[j * n + i] - mj) * (x[k * n + i] - mk)
        i += 1usize
    }
    ret s / f64(n - 1usize)
}

// alpha(x): (raw_alpha, std_alpha)
fn alpha(x: []const f64, n: usize, k: usize) -> (f64, f64) {
    var sv = 0.0f64
    var tot = 0.0f64
    var rsum = 0.0f64
    var j = 0usize
    while j < k {
        var l = 0usize
        while l < k {
            let c = covar(x, n, j, l)
            tot += c
            if j == l { sv += c } else { rsum += c / math.sqrt[f64](covar(x, n, j, j) * covar(x, n, l, l)) }
            l += 1usize
        }
        j += 1usize
    }
    let kf = f64(k)
    let rbar = rsum / (kf * (kf - 1.0f64))
    ret (kf / (kf - 1.0f64) * (1.0f64 - sv / tot), kf * rbar / (1.0f64 + (kf - 1.0f64) * rbar))
}

// the correlation matrix of x (row-major p by p)
fn corr(a: *mem.Arena, x: []const f64, n: usize, p: usize) -> ([]f64, err) {
    let (r, e) = mem.alloc[f64](a, p * p)
    if e != ok { ret (r, e) }
    var j = 0usize
    while j < p {
        var k = 0usize
        while k < p {
            r[j * p + k] = covar(x, n, j, k) / math.sqrt[f64](covar(x, n, j, j) * covar(x, n, k, k))
            k += 1usize
        }
        j += 1usize
    }
    ret (r, ok)
}

// inverse of a row-major p by p matrix by solving against the unit vectors; false if singular
fn invert(a: *mem.Arena, m: []const f64, p: usize, out: []f64) -> bool {
    let (w, e1) = mem.alloc[f64](a, p * p)
    let (c, e2) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok { ret false }
    var col = 0usize
    while col < p {
        var i = 0usize
        while i < p * p {
            w[i] = m[i]
            i += 1usize
        }
        i = 0usize
        while i < p {
            c[i] = 0.0f64
            i += 1usize
        }
        c[col] = 1.0f64
        if !qr.solve_dense(w, c, p) { ret false }
        i = 0usize
        while i < p {
            out[i * p + col] = c[i]
            i += 1usize
        }
        col += 1usize
    }
    ret true
}

fn logdet(a: *mem.Arena, m: []const f64, p: usize) -> f64 {
    let (w, e) = mem.alloc[f64](a, p * p)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < p * p {
        w[i] = m[i]
        i += 1usize
    }
    var ld = 0.0f64
    var c = 0usize
    while c < p {
        var piv = c
        i = c + 1usize
        while i < p {
            if math.abs[f64](w[i * p + c]) > math.abs[f64](w[piv * p + c]) { piv = i }
            i += 1usize
        }
        if piv != c {
            var k = 0usize
            while k < p {
                let t = w[c * p + k]
                w[c * p + k] = w[piv * p + k]
                w[piv * p + k] = t
                k += 1usize
            }
        }
        ld += math.log[f64](math.abs[f64](w[c * p + c]))
        i = c + 1usize
        while i < p {
            let f = w[i * p + c] / w[c * p + c]
            var k = c
            while k < p {
                w[i * p + k] -= f * w[c * p + k]
                k += 1usize
            }
            i += 1usize
        }
        c += 1usize
    }
    ret ld
}

// kmo(r): overall MSA, and msa[i] per item (r row-major p by p)
fn kmo(a: *mem.Arena, r: []const f64, p: usize, msa: []f64) -> (f64, err) {
    let (q, e) = mem.alloc[f64](a, p * p)
    if e != ok { ret (0.0f64, e) }
    if !invert(a, r, p, q) { ret (0.0f64, Singular) }
    var r2 = 0.0f64
    var q2 = 0.0f64
    var i = 0usize
    while i < p {
        var ri = 0.0f64
        var qi = 0.0f64
        var j = 0usize
        while j < p {
            if i != j {
                let pc = 0.0f64 - q[i * p + j] / math.sqrt[f64](q[i * p + i] * q[j * p + j])
                ri += r[i * p + j] * r[i * p + j]
                qi += pc * pc
            }
            j += 1usize
        }
        msa[i] = ri / (ri + qi)
        r2 += ri
        q2 += qi
        i += 1usize
    }
    ret (r2 / (r2 + q2), ok)
}

// cortest.bartlett(r, n): (chisq, df)
fn bartlett(a: *mem.Arena, r: []const f64, p: usize, n: f64) -> (f64, f64) {
    let pf = f64(p)
    let chi = (0.0f64 - 1.0f64) * (n - 1.0f64 - (2.0f64 * pf + 5.0f64) / 6.0f64) * logdet(a, r, p)
    ret (chi, pf * (pf - 1.0f64) / 2.0f64)
}

// icc(x): x is n subjects by k raters column-major; answers ICC1, ICC2, ICC3, ICC1k, ICC2k, ICC3k in out[0..6]
fn icc(x: []const f64, n: usize, k: usize, out: []f64) {
    let nf = f64(n)
    let kf = f64(k)
    var gm = 0.0f64
    var i = 0usize
    while i < n * k {
        gm += x[i]
        i += 1usize
    }
    gm = gm / (nf * kf)
    var ssb = 0.0f64
    i = 0usize
    while i < n {
        var m = 0.0f64
        var j = 0usize
        while j < k {
            m += x[j * n + i]
            j += 1usize
        }
        m = m / kf
        ssb += kf * (m - gm) * (m - gm)
        i += 1usize
    }
    var ssj = 0.0f64
    var j = 0usize
    while j < k {
        let m = colmean(x, n, j)
        ssj += nf * (m - gm) * (m - gm)
        j += 1usize
    }
    var sst = 0.0f64
    i = 0usize
    while i < n * k {
        sst += (x[i] - gm) * (x[i] - gm)
        i += 1usize
    }
    let msb = ssb / (nf - 1.0f64)
    let msj = ssj / (kf - 1.0f64)
    let mse = (sst - ssb - ssj) / ((nf - 1.0f64) * (kf - 1.0f64))
    let msw = (sst - ssb) / (nf * (kf - 1.0f64))
    out[0usize] = (msb - msw) / (msb + (kf - 1.0f64) * msw)
    out[1usize] = (msb - mse) / (msb + (kf - 1.0f64) * mse + kf * (msj - mse) / nf)
    out[2usize] = (msb - mse) / (msb + (kf - 1.0f64) * mse)
    out[3usize] = (msb - msw) / msb
    out[4usize] = (msb - mse) / (msb + (msj - mse) / nf)
    out[5usize] = (msb - mse) / msb
    // psych takes the variance components from a mixed model that clamps a negative rater variance at zero, which
    // leaves the pooled within-subject error: forms 2 and 3 become form 1, and 2k and 3k become 1k
    if msj < mse {
        out[1usize] = out[0usize]
        out[2usize] = out[0usize]
        out[4usize] = out[3usize]
        out[5usize] = out[3usize]
    }
}

// kappa of a k by k table of counts (row-major)
fn kappa(t: []const f64, k: usize) -> f64 {
    var n = 0.0f64
    var i = 0usize
    while i < k * k {
        n += t[i]
        i += 1usize
    }
    var po = 0.0f64
    var pe = 0.0f64
    i = 0usize
    while i < k {
        po += t[i * k + i] / n
        var rs = 0.0f64
        var cs = 0.0f64
        var j = 0usize
        while j < k {
            rs += t[i * k + j]
            cs += t[j * k + i]
            j += 1usize
        }
        pe += rs / n * cs / n
        i += 1usize
    }
    ret (po - pe) / (1.0f64 - pe)
}

// mardia(x): (b1p, b2p) with the unbiased covariance, as psych computes them
fn mardia(a: *mem.Arena, x: []const f64, n: usize, p: usize) -> (f64, f64, err) {
    let (s, e1) = mem.alloc[f64](a, p * p)
    let (si, e2) = mem.alloc[f64](a, p * p)
    let (xc, e3) = mem.alloc[f64](a, n * p)
    if e1 != ok || e2 != ok || e3 != ok { ret (0.0f64, 0.0f64, e1) }
    var j = 0usize
    while j < p {
        var k = 0usize
        while k < p {
            s[j * p + k] = covar(x, n, j, k)
            k += 1usize
        }
        let m = colmean(x, n, j)
        var i = 0usize
        while i < n {
            xc[j * n + i] = x[j * n + i] - m
            i += 1usize
        }
        j += 1usize
    }
    if !invert(a, s, p, si) { ret (0.0f64, 0.0f64, Singular) }
    var b1 = 0.0f64
    var b2 = 0.0f64
    var i = 0usize
    while i < n {
        var l = 0usize
        while l < n {
            var d = 0.0f64
            var j1 = 0usize
            while j1 < p {
                var j2 = 0usize
                while j2 < p {
                    d += xc[j1 * n + i] * si[j1 * p + j2] * xc[j2 * n + l]
                    j2 += 1usize
                }
                j1 += 1usize
            }
            b1 += d * d * d
            if i == l { b2 += d * d }
            l += 1usize
        }
        i += 1usize
    }
    ret (b1 / f64(n * n), b2 / f64(n), ok)
}

error Singular

// describe(x) of one numeric column: which 0 n, 1 mean, 2 sd, 3 median, 4 trimmed (10%), 5 mad, 6 min, 7 max, 8 range, 9 skew (type 3), 10 kurtosis (type 3), 11 se
fn describe(a: *mem.Arena, x: []const f64, which: usize) -> f64 {
    let n = x.len
    let (t, e) = dt.sorted_copy(a, x)
    if e != ok { ret 0.0f64 / 0.0f64 }
    let nf = f64(n)
    if which == 0usize { ret nf }
    if which == 1usize { ret dt.mean_of(x) }
    if which == 2usize { ret dt.sd_of(x) }
    var med = t[n / 2usize]
    if n % 2usize == 0usize { med = (t[n / 2usize - 1usize] + t[n / 2usize]) / 2.0f64 }
    if which == 3usize { ret med }
    if which == 4usize {
        let lo = usize(math.floor[f64](nf * 0.1f64)) + 1usize
        let hi = n + 1usize - lo
        var sm = 0.0f64
        var i = lo
        while i <= hi {
            sm += t[i - 1usize]
            i += 1usize
        }
        ret sm / f64(hi - lo + 1usize)
    }
    if which == 5usize { ret dt.mad_dt(a, x, 1.4826f64, false, false) }
    if which == 6usize { ret t[0usize] }
    if which == 7usize { ret t[n - 1usize] }
    if which == 8usize { ret t[n - 1usize] - t[0usize] }
    if which == 9usize { ret dt.skew(x, 3usize) }
    if which == 10usize { ret dt.kurt(x, 3usize) }
    ret dt.sd_of(x) / math.sqrt[f64](nf)
}

// corr.test of the columns i and j of x (n by p, column-major): which 0 r, 1 t, 2 two-sided p, 3 lower and 4 upper of the Fisher-z 95% interval, 5 the Holm-adjusted p over all column pairs
fn corr_test(a: *mem.Arena, x: []const f64, n: usize, p: usize, i: usize, j: usize, which: usize) -> f64 {
    let (r, re) = corr(a, x, n, p)
    if re != ok { ret 0.0f64 / 0.0f64 }
    let rij = r[i * p + j]
    let df = f64(n) - 2.0f64
    let tt = rij * math.sqrt[f64](df / (1.0f64 - rij * rij))
    let pv = 2.0f64 * nbt.pt(0.0f64 - math.abs[f64](tt), df, true, false)
    if which == 0usize { ret rij }
    if which == 1usize { ret tt }
    if which == 2usize { ret pv }
    if which <= 4usize {
        let z = 0.5f64 * math.log[f64]((1.0f64 + rij) / (1.0f64 - rij))
        let se = 1.0f64 / math.sqrt[f64](f64(n) - 3.0f64)
        let q = dst.qnorm(0.975f64, 0.0f64, 1.0f64, true, false)
        var zz = z - q * se
        if which == 4usize { zz = z + q * se }
        let e2 = math.exp[f64](2.0f64 * zz)
        ret (e2 - 1.0f64) / (e2 + 1.0f64)
    }
    // Holm over the p(p - 1)/2 pairs: sort the p values, adjusted_k = max over m <= k of min(1, (m_total - m + 1) p_(m))
    let pairs = p * (p - 1usize) / 2usize
    let (ps, pe) = mem.alloc[f64](a, pairs)
    if pe != ok { ret 0.0f64 / 0.0f64 }
    var idx = 0usize
    var u = 0usize
    while u < p {
        var v = u + 1usize
        while v < p {
            let rr = r[u * p + v]
            let t2 = rr * math.sqrt[f64](df / (1.0f64 - rr * rr))
            ps[idx] = 2.0f64 * nbt.pt(0.0f64 - math.abs[f64](t2), df, true, false)
            idx += 1usize
            v += 1usize
        }
        u += 1usize
    }
    // rank of my p among the pairs and the running maximum in increasing order
    var mine = pv
    var below = 0usize
    var q2 = 0usize
    while q2 < pairs {
        if ps[q2] < mine { below += 1usize }
        q2 += 1usize
    }
    // the adjusted value is the maximum over the pairs with p <= mine of (pairs - rank) * p
    var best = 0.0f64
    q2 = 0usize
    while q2 < pairs {
        if ps[q2] <= mine {
            var rk = 0usize
            var w = 0usize
            while w < pairs {
                if ps[w] < ps[q2] { rk += 1usize }
                w += 1usize
            }
            var cand = f64(pairs - rk) * ps[q2]
            if cand > 1.0f64 { cand = 1.0f64 }
            if cand > best { best = cand }
        }
        q2 += 1usize
    }
    ret best
}

// psych::Yule(x) of a 2 by 2 table (column-major a, c, b, d): Q, or Y when y is true
fn yule(t: []const f64, y: bool) -> f64 {
    let a = t[0usize]
    let c = t[1usize]
    let b = t[2usize]
    let d = t[3usize]
    if y { ret (math.sqrt[f64](a * d) - math.sqrt[f64](b * c)) / (math.sqrt[f64](a * d) + math.sqrt[f64](b * c)) }
    ret (a * d - b * c) / (a * d + b * c)
}

// psych::phi(t, digits = 12) of a 2 by 2 table: (a / N - c1 r1) / sqrt(r1 r2 c1 c2) with the margins as proportions
fn phi(t: []const f64) -> f64 {
    let tot = t[0usize] + t[1usize] + t[2usize] + t[3usize]
    let r1 = (t[0usize] + t[2usize]) / tot
    let r2 = (t[1usize] + t[3usize]) / tot
    let c1 = (t[0usize] + t[1usize]) / tot
    let c2 = (t[2usize] + t[3usize]) / tot
    ret (t[0usize] / tot - c1 * r1) / math.sqrt[f64](r1 * r2 * c1 * c2)
}

// psych::biserial(x, y) with y coded 0 / 1: (mean x in 1 - mean x in 0) p q / (dnorm(qnorm(p)) sd x), p the share of ones, clipped to +-1 as psych does
fn biserial(x: []const f64, y: []const f64) -> f64 {
    let n = f64(x.len)
    var n1 = 0.0f64
    var s1 = 0.0f64
    var s0 = 0.0f64
    var sx = 0.0f64
    var i = 0usize
    while i < x.len {
        sx += x[i]
        if y[i] > 0.5f64 {
            n1 += 1.0f64
            s1 += x[i]
        } else {
            s0 += x[i]
        }
        i += 1usize
    }
    let mx = sx / n
    var ss = 0.0f64
    i = 0usize
    while i < x.len {
        ss += (x[i] - mx) * (x[i] - mx)
        i += 1usize
    }
    let sd = math.sqrt[f64](ss / (n - 1.0f64))
    let p = n1 / n
    let zp = dst.dnorm(dst.qnorm(p, 0.0f64, 1.0f64, true, false), 0.0f64, 1.0f64, false)
    var r = (s1 / n1 - s0 / (n - n1)) * (p * (1.0f64 - p)) / (zp * sd)
    if r > 1.0f64 { r = 1.0f64 }
    if r < 0.0f64 - 1.0f64 { r = 0.0f64 - 1.0f64 }
    ret r
}

type TetCtx = struct { tab: [4]f64, rc: f64, cc: f64 }

fn tetra_f(c: *TetCtx, rho: f64) -> f64 {
    let p11 = pbv.pbivnorm(c.rc, c.cc, rho)
    let p21 = dst.pnorm(c.rc, 0.0f64, 1.0f64, true, false) - p11
    let p12 = dst.pnorm(c.cc, 0.0f64, 1.0f64, true, false) - p11
    let p22 = 1.0f64 - dst.pnorm(c.rc, 0.0f64, 1.0f64, true, false) - p12
    ret 0.0f64 - (c.tab[0usize] * math.log[f64](p11) + c.tab[1usize] * math.log[f64](p21) + c.tab[2usize] * math.log[f64](p12) + c.tab[3usize] * math.log[f64](p22))
}

// psych::tetrachoric of a 2 by 2 table of counts (column-major) with correct = 0.5: out[0] rho from R's optimize on (-1, 1), out[1] the row threshold, out[2] the column threshold
fn tetrachoric(t: []const f64, correct: f64, out: []f64) {
    var c = TetCtx { tab: zero, rc: 0.0f64, cc: 0.0f64 }
    var mn = t[0usize]
    var tot = 0.0f64
    var i = 0usize
    while i < 4usize {
        c.tab[i] = t[i]
        if t[i] < mn { mn = t[i] }
        tot += t[i]
        i += 1usize
    }
    if tot > 1.0f64 && mn == 0.0f64 && correct > 0.0f64 {
        i = 0usize
        while i < 4usize {
            if c.tab[i] == 0.0f64 { c.tab[i] = correct }
            i += 1usize
        }
    }
    var s = 0.0f64
    i = 0usize
    while i < 4usize {
        s += c.tab[i]
        i += 1usize
    }
    i = 0usize
    while i < 4usize {
        c.tab[i] = c.tab[i] / s
        i += 1usize
    }
    c.rc = dst.qnorm(c.tab[0usize] + c.tab[1usize], 0.0f64, 1.0f64, true, false)
    c.cc = dst.qnorm(c.tab[0usize] + c.tab[2usize], 0.0f64, 1.0f64, true, false)
    out[0usize] = fd.brent_min[TetCtx](&c, tetra_f, 0.0f64 - 1.0f64, 1.0f64)
    out[1usize] = c.cc
    out[2usize] = c.rc
}

// psych::tetrachoric(X, smooth = FALSE) for one pair of 0 / 1 columns without missing values (global = TRUE): the thresholds are -qnorm of the column means, the table of counts has zero cells
// replaced by `correct`, and rho minimises sum(tab log P) on (-1, 1) with psych's cell order, in which the first threshold belongs to the second variable
fn tetrachoric_pair(x: []const f64, y: []const f64, correct: f64) -> f64 {
    var c = TetCtx { tab: zero, rc: 0.0f64, cc: 0.0f64 }
    var sx = 0.0f64
    var sq0 = 0.0f64
    var i = 0usize
    while i < x.len {
        sx += x[i]
        sq0 += y[i]
        var cell = 0usize
        if x[i] > 0.5f64 { cell += 1usize }
        if y[i] > 0.5f64 { cell += 2usize }
        c.tab[cell] += 1.0f64
        i += 1usize
    }
    let nn = f64(x.len)
    var mn = c.tab[0usize]
    i = 1usize
    while i < 4usize {
        if c.tab[i] < mn { mn = c.tab[i] }
        i += 1usize
    }
    if nn > 1.0f64 && mn == 0.0f64 && correct > 0.0f64 {
        i = 0usize
        while i < 4usize {
            if c.tab[i] == 0.0f64 { c.tab[i] = correct }
            i += 1usize
        }
    }
    c.cc = 0.0f64 - dst.qnorm(sx / nn, 0.0f64, 1.0f64, true, false)
    c.rc = 0.0f64 - dst.qnorm(sq0 / nn, 0.0f64, 1.0f64, true, false)
    ret fd.brent_min[TetCtx](&c, tetra_f, 0.0f64 - 1.0f64, 1.0f64)
}

type PolyCtx = struct { tab: [64]f64, rc: [8]f64, cc: [8]f64, k: usize }

fn bvn_cut(a: f64, b: f64, rho: f64) -> f64 {
    var x = a
    var y = b
    if x > 10.0f64 { x = 10.0f64 }
    if y > 10.0f64 { y = 10.0f64 }
    if x < 0.0f64 - 10.0f64 { ret 0.0f64 }
    if y < 0.0f64 - 10.0f64 { ret 0.0f64 }
    ret pbv.pbivnorm(x, y, rho)
}

fn poly_f(c: *PolyCtx, rho: f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < c.k {
        var lo_r = 0.0f64 - 12.0f64
        var hi_r = 12.0f64
        if i > 0usize { lo_r = c.rc[i - 1usize] }
        if i + 1usize < c.k { hi_r = c.rc[i] }
        var j = 0usize
        while j < c.k {
            var lo_c = 0.0f64 - 12.0f64
            var hi_c = 12.0f64
            if j > 0usize { lo_c = c.cc[j - 1usize] }
            if j + 1usize < c.k { hi_c = c.cc[j] }
            let p = bvn_cut(hi_r, hi_c, rho) - bvn_cut(lo_r, hi_c, rho) - bvn_cut(hi_r, lo_c, rho) + bvn_cut(lo_r, lo_c, rho)
            if p > 0.0f64 { s += c.tab[i * 8usize + j] * math.log[f64](p) }
            j += 1usize
        }
        i += 1usize
    }
    ret 0.0f64 - s
}

// psych::polychoric(X, smooth = FALSE) for one pair of columns coded 1 .. k (k <= 8, every category observed, no missing values), global = TRUE: thresholds from the cumulative column proportions,
// rho by R's optimize on (-1, 1) of the multinomial log-likelihood with bivariate normal cell probabilities (psych's sadmvn is only accurate to 1e-6, so the two agree to about that)
fn polychoric_pair(x: []const f64, y: []const f64, k: usize) -> f64 {
    var c = PolyCtx { tab: zero, rc: zero, cc: zero, k: k }
    let nn = f64(x.len)
    var fx: [8]f64 = zero
    var fy: [8]f64 = zero
    var i = 0usize
    while i < x.len {
        let a = usize(x[i]) - 1usize
        let b = usize(y[i]) - 1usize
        c.tab[a * 8usize + b] += 1.0f64 / nn
        fx[a] += 1.0f64 / nn
        fy[b] += 1.0f64 / nn
        i += 1usize
    }
    var cx = 0.0f64
    var cy = 0.0f64
    i = 0usize
    while i + 1usize < k {
        cx += fx[i]
        cy += fy[i]
        c.rc[i] = dst.qnorm(cx, 0.0f64, 1.0f64, true, false)
        c.cc[i] = dst.qnorm(cy, 0.0f64, 1.0f64, true, false)
        i += 1usize
    }
    ret fd.brent_min[PolyCtx](&c, poly_f, 0.0f64 - 1.0f64, 1.0f64)
}

// psych::principal(r, nfactors = nf, rotate = "none") of a correlation matrix r (p by p, column-major): out[0 .. p nf] the loadings (item i, component k at i + k p) with each column signed so its sum is
// positive, then the p eigenvalues (descending), then the p communalities
fn principal(a: *mem.Arena, r: []const f64, p: usize, nf: usize, out: []f64) -> err {
    let (w, e1) = mem.alloc[f64](a, p)
    let (z, e2) = mem.alloc[f64](a, p * p)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    let e3 = sy.dsyevr_all(a, r, p, w, z)
    if e3 != ok { ret e3 }
    var k = 0usize
    while k < p {
        out[p * nf + k] = w[p - 1usize - k]
        k += 1usize
    }
    var h = 0usize
    while h < p {
        out[p * nf + p + h] = 0.0f64
        h += 1usize
    }
    k = 0usize
    while k < nf {
        var ev = w[p - 1usize - k]
        if ev < 2.220446049250313e-16f64 { ev = 2.220446049250313e-16f64 }
        let sq = math.sqrt[f64](ev)
        let col = p - 1usize - k
        var sum = 0.0f64
        var i = 0usize
        while i < p {
            out[i + k * p] = z[col * p + i] * sq
            sum += out[i + k * p]
            i += 1usize
        }
        var sg = 1.0f64
        if sum < 0.0f64 { sg = 0.0f64 - 1.0f64 }
        i = 0usize
        while i < p {
            out[i + k * p] = out[i + k * p] * sg
            out[p * nf + p + i] += out[i + k * p] * out[i + k * p]
            i += 1usize
        }
        k += 1usize
    }
    ret ok
}

// psych::principal(r, nfactors = nf, rotate = "varimax"): the unrotated loadings of `principal` rotated by stats::varimax (normalize, eps 1e-5), the columns ordered by decreasing sum of squares and each
// signed to a positive sum. out[0 .. p nf] the loadings (item i, component k at i + k p), then the rotation matrix (nf by nf column-major: element (r, c) at p nf + r + c nf)
fn principal_varimax(a: *mem.Arena, r: []const f64, p: usize, nf: usize, out: []f64) -> err {
    let (pc, e1) = mem.alloc[f64](a, p * nf + 2usize * p)
    if e1 != ok { ret e1 }
    let e2 = principal(a, r, p, nf, pc)
    if e2 != ok { ret e2 }
    let (xr, e3) = mem.alloc[f64](a, p * nf)
    if e3 != ok { ret e3 }
    var i = 0usize
    while i < p {
        var k = 0usize
        while k < nf {
            xr[i * nf + k] = pc[i + k * p]
            k += 1usize
        }
        i += 1usize
    }
    let (rot, rm, e4) = gp.varimax_stats(a, xr, p, nf, true, 1.0e-5f64)
    if e4 != ok { ret e4 }
    // order the rotated columns by sum of squares, then fix signs
    let (ss, e5) = mem.alloc[f64](a, nf)
    let (ord, e6) = mem.alloc[usize](a, nf)
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    var k = 0usize
    while k < nf {
        ss[k] = 0.0f64
        i = 0usize
        while i < p {
            ss[k] += rot[i * nf + k] * rot[i * nf + k]
            i += 1usize
        }
        ord[k] = k
        k += 1usize
    }
    // insertion sort, decreasing; ties keep their order as R's order() does
    k = 1usize
    while k < nf {
        let cur = ord[k]
        var j = k
        while j > 0usize && ss[ord[j - 1usize]] < ss[cur] {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = cur
        k += 1usize
    }
    k = 0usize
    while k < nf {
        let src = ord[k]
        var sum = 0.0f64
        i = 0usize
        while i < p {
            sum += rot[i * nf + src]
            i += 1usize
        }
        var sg = 1.0f64
        if sum < 0.0f64 { sg = 0.0f64 - 1.0f64 }
        i = 0usize
        while i < p {
            out[i + k * p] = rot[i * nf + src] * sg
            i += 1usize
        }
        var rr = 0usize
        while rr < nf {
            out[p * nf + rr + k * nf] = rm[rr * nf + src]
            rr += 1usize
        }
        k += 1usize
    }
    ret ok
}

// psych::fa(r, nfactors = nf, fm = "pa", rotate = "none") of a correlation matrix r (p by p, symmetric): principal-axis factoring from the squared multiple correlations until the sum of communalities changes
// by at most min.err = 0.001 (at most 50 rounds). out[0 .. p nf] the loadings (item i, factor k at i + k p, each column signed to a positive sum), then the p communalities
fn fa_pa(a: *mem.Arena, r: []const f64, p: usize, nf: usize, out: []f64) -> err {
    let (inv, e1) = mem.alloc[f64](a, p * p)
    let (rm, e2) = mem.alloc[f64](a, p * p)
    let (w, e3) = mem.alloc[f64](a, p)
    let (z, e4) = mem.alloc[f64](a, p * p)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if !invert(a, r, p, inv) { ret Malformed }
    var i = 0usize
    while i < p * p {
        rm[i] = r[i]
        i += 1usize
    }
    var comm = 0.0f64
    i = 0usize
    while i < p {
        rm[i * p + i] = 1.0f64 - 1.0f64 / inv[i * p + i]
        comm += rm[i * p + i]
        i += 1usize
    }
    var err0 = comm
    var iter = 1usize
    while err0 > 0.001f64 {
        let e5 = sy.dsyevr_all(a, rm, p, w, z)
        if e5 != ok { ret e5 }
        var comm1 = 0.0f64
        var j = 0usize
        while j < p {
            var h = 0.0f64
            var k = 0usize
            while k < nf {
                let col = p - 1usize - k
                let ld = z[col * p + j] * math.sqrt[f64](w[col])
                h += ld * ld
                k += 1usize
            }
            out[p * nf + j] = h
            comm1 += h
            j += 1usize
        }
        j = 0usize
        while j < p {
            rm[j * p + j] = out[p * nf + j]
            j += 1usize
        }
        err0 = math.abs[f64](comm - comm1)
        comm = comm1
        iter += 1usize
        if iter > 50usize { err0 = 0.0f64 }
    }
    // the loadings of the last decomposition
    var k = 0usize
    while k < nf {
        let col = p - 1usize - k
        var sum = 0.0f64
        var j = 0usize
        while j < p {
            out[j + k * p] = z[col * p + j] * math.sqrt[f64](w[col])
            sum += out[j + k * p]
            j += 1usize
        }
        if sum < 0.0f64 {
            j = 0usize
            while j < p {
                out[j + k * p] = 0.0f64 - out[j + k * p]
                j += 1usize
            }
        }
        k += 1usize
    }
    ret ok
}

// psych::scoreItems(keys, x, totals = FALSE, min, max, impute = "none") for complete data: x is n by p column-major, keys p by S column-major with entries -1, 0, 1 (negative keys are reversed as max + min - x).
// out[0 .. n S] the scale scores (the mean of the keyed items; scale s, case i at i + s n), then S alpha, S average r, S Guttman lambda 6, then the S by S correlations of the scores (column-major)
fn score_items(a: *mem.Arena, x: []const f64, n: usize, p: usize, keys: []const f64, ns: usize, minv: f64, maxv: f64, out: []f64) -> err {
    let nn = f64(n)
    let (xr, ex1) = mem.alloc[f64](a, n * p)
    let (fc, ex2) = mem.alloc[f64](a, p * p)
    let (fi, ex3) = mem.alloc[f64](a, p * p)
    if ex1 != ok { ret ex1 }
    if ex2 != ok { ret ex2 }
    if ex3 != ok { ret ex3 }
    var fj = 0usize
    while fj < p {
        var neg = false
        var fs = 0usize
        while fs < ns {
            if keys[fj + fs * p] < 0.0f64 { neg = true }
            fs += 1usize
        }
        var fr = 0usize
        while fr < n {
            xr[fr + fj * n] = x[fr + fj * n]
            if neg { xr[fr + fj * n] = maxv + minv - x[fr + fj * n] }
            fr += 1usize
        }
        fj += 1usize
    }
    fj = 0usize
    while fj < p {
        var fl = 0usize
        while fl < p {
            var m1 = 0.0f64
            var m2 = 0.0f64
            var fr = 0usize
            while fr < n {
                m1 += xr[fr + fj * n]
                m2 += xr[fr + fl * n]
                fr += 1usize
            }
            m1 = m1 / nn
            m2 = m2 / nn
            var cxy = 0.0f64
            fr = 0usize
            while fr < n {
                cxy += (xr[fr + fj * n] - m1) * (xr[fr + fl * n] - m2)
                fr += 1usize
            }
            fc[fj * p + fl] = cxy / (nn - 1.0f64)
            fl += 1usize
        }
        fj += 1usize
    }
    var sc = 0usize
    while sc < ns {
        var k = 0usize
        var i = 0usize
        while i < p {
            if keys[i + sc * p] != 0.0f64 { k += 1usize }
            i += 1usize
        }
        let (it, e1) = mem.alloc[f64](a, n * k)
        let (cv, e2) = mem.alloc[f64](a, k * k)
        let (iv, e3) = mem.alloc[f64](a, k * k)
        if e1 != ok { ret e1 }
        if e2 != ok { ret e2 }
        if e3 != ok { ret e3 }
        var c = 0usize
        i = 0usize
        while i < p {
            let ky = keys[i + sc * p]
            if ky != 0.0f64 {
                var r = 0usize
                while r < n {
                    var v = x[r + i * n]
                    if ky < 0.0f64 { v = maxv + minv - v }
                    it[r + c * n] = v
                    r += 1usize
                }
                c += 1usize
            }
            i += 1usize
        }
        var r = 0usize
        while r < n {
            var t = 0.0f64
            c = 0usize
            while c < k {
                t += it[r + c * n]
                c += 1usize
            }
            out[r + sc * n] = t / f64(k)
            r += 1usize
        }
        var j = 0usize
        while j < k {
            var mj = 0.0f64
            r = 0usize
            while r < n {
                mj += it[r + j * n]
                r += 1usize
            }
            mj = mj / nn
            var l = 0usize
            while l < k {
                var ml = 0.0f64
                r = 0usize
                while r < n {
                    ml += it[r + l * n]
                    r += 1usize
                }
                ml = ml / nn
                var sxy = 0.0f64
                r = 0usize
                while r < n {
                    sxy += (it[r + j * n] - mj) * (it[r + l * n] - ml)
                    r += 1usize
                }
                cv[j * k + l] = sxy / (nn - 1.0f64)
                l += 1usize
            }
            j += 1usize
        }
        var tot = 0.0f64
        var dg = 0.0f64
        j = 0usize
        while j < k * k {
            tot += cv[j]
            j += 1usize
        }
        j = 0usize
        while j < k {
            dg += cv[j * k + j]
            j += 1usize
        }
        let al = (f64(k) / (f64(k) - 1.0f64)) * (1.0f64 - dg / tot)
        out[n * ns + sc] = al
        out[n * ns + ns + sc] = al / (f64(k) - (f64(k) - 1.0f64) * al)
        var g6 = 0.0f64 / 0.0f64
        if invert(a, fc, p, fi) {
            var vs = 0.0f64
            var sis = 0.0f64
            var ssm = 0.0f64
            var ia = 0usize
            while ia < p {
                if keys[ia + sc * p] != 0.0f64 {
                    sis += fc[ia * p + ia]
                    ssm += fc[ia * p + ia] - 1.0f64 / fi[ia * p + ia]
                    var ib = 0usize
                    while ib < p {
                        if keys[ib + sc * p] != 0.0f64 { vs += fc[ia * p + ib] }
                        ib += 1usize
                    }
                }
                ia += 1usize
            }
            g6 = (vs - sis + ssm) / vs
        }
        out[n * ns + 2usize * ns + sc] = g6
        sc += 1usize
    }
    var u = 0usize
    while u < ns {
        var v = 0usize
        while v < ns {
            var mu = 0.0f64
            var mv = 0.0f64
            var r = 0usize
            while r < n {
                mu += out[r + u * n]
                mv += out[r + v * n]
                r += 1usize
            }
            mu = mu / nn
            mv = mv / nn
            var suv = 0.0f64
            var suu = 0.0f64
            var svv = 0.0f64
            r = 0usize
            while r < n {
                suv += (out[r + u * n] - mu) * (out[r + v * n] - mv)
                suu += (out[r + u * n] - mu) * (out[r + u * n] - mu)
                svv += (out[r + v * n] - mv) * (out[r + v * n] - mv)
                r += 1usize
            }
            out[n * ns + 3usize * ns + u + v * ns] = suv / math.sqrt[f64](suu * svv)
            v += 1usize
        }
        u += 1usize
    }
    ret ok
}
