// R arm, the rest of what its functions compute: display and sigma.hat for lm and glm, corrplot's matrix, contr.bayes, discrete.hist, coefplot, mcplot, balance, matching and
// binnedplot's defaults. The plotting itself is not here, only the numbers a plot is drawn from.
//
// Models take a design x (n by k row-major, the first column the intercept) and y; family 0 gaussian, 1 binomial, 2 poisson, 5 quasibinomial, 6 quasipoisson.

use e.algo.stat.arm as ar
use e.algo.stat.armld as ld
use e.algo.linalg.decomp as dc
use e.algo.rand.r as rng
use e.math
use e.math.dist as dist
use e.math.nmath_beta as nb
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

// R's sum() and mean(): the long double accumulation of armld
fn csum(v: []const f64) -> f64 { ret ld.sum_ld(v) }

fn rmean(v: []const f64) -> f64 { ret ld.mean_ld(v) }

// display(lm) and sigma.hat: out = sigma.hat, r.squared, n, k, then coef.est, coef.se, t value and p value (k each); icpt says the first column is an intercept
fn display_lm(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, k: usize, icpt: bool, out: []f64) -> err {
    let (beta, e1) = mem.alloc[f64](a, k)
    let (cov, e2) = mem.alloc[f64](a, k * k)
    let (res, e3) = mem.alloc[f64](a, n)
    let (fit, e4) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    let (rss, e) = ar.lm_summary(a, x, y, n, k, beta, cov, res)
    if e != ok { ret e }
    let rdf = f64(n - k)
    let resvar = rss / rdf
    var i = 0usize
    while i < n {
        fit[i] = y[i] - res[i]
        i += 1usize
    }
    var m = 0.0f64
    if icpt { m = rmean(fit) }
    i = 0usize
    while i < n {
        fit[i] = (fit[i] - m) * (fit[i] - m)
        i += 1usize
    }
    let mss = csum(fit)
    out[0usize] = math.sqrt[f64](resvar)
    out[1usize] = mss / (mss + rss)
    out[2usize] = f64(n)
    out[3usize] = f64(k)
    var j = 0usize
    while j < k {
        let se = math.sqrt[f64](cov[j * k + j] * resvar)
        let t = beta[j] / se
        out[4usize + j] = beta[j]
        out[4usize + k + j] = se
        out[4usize + 2usize * k + j] = t
        out[4usize + 3usize * k + j] = 2.0f64 * nb.pt(math.abs[f64](t), rdf, false, false)
        j += 1usize
    }
    ret ok
}

// corrplot's matrix: cor(data, data, use = "pairwise.complete.obs"), absolute values when use_abs; x is n by p row-major with NaN for NA, out is p by p (NaN where fewer than two complete pairs or no spread)
fn cor_pairwise(a: *mem.Arena, x: []const f64, n: usize, p: usize, use_abs: bool, out: []f64) -> err {
    let (u, e1) = mem.alloc[f64](a, n)
    let (v, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret mem.Full }
    var i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            var m = 0usize
            var k = 0usize
            while k < n {
                let xv = x[k * p + i]
                let yv = x[k * p + j]
                if xv == xv && yv == yv {
                    u[m] = xv
                    v[m] = yv
                    m += 1usize
                }
                k += 1usize
            }
            var r = nan()
            if m >= 2usize {
                let xm = csum(u[0usize..m]) / f64(m)
                let ym = csum(v[0usize..m]) / f64(m)
                var sxx = 0.0f64
                var syy = 0.0f64
                var sxy = 0.0f64
                var cx = 0.0f64
                var cy = 0.0f64
                var cxy = 0.0f64
                k = 0usize
                while k < m {
                    let dx = u[k] - xm
                    let dy = v[k] - ym
                    let t1 = sxx + dx * dx
                    if math.abs[f64](sxx) >= math.abs[f64](dx * dx) { cx += (sxx - t1) + dx * dx } else { cx += (dx * dx - t1) + sxx }
                    sxx = t1
                    let t2 = syy + dy * dy
                    if math.abs[f64](syy) >= math.abs[f64](dy * dy) { cy += (syy - t2) + dy * dy } else { cy += (dy * dy - t2) + syy }
                    syy = t2
                    let t3 = sxy + dx * dy
                    if math.abs[f64](sxy) >= math.abs[f64](dx * dy) { cxy += (sxy - t3) + dx * dy } else { cxy += (dx * dy - t3) + sxy }
                    sxy = t3
                    k += 1usize
                }
                sxx += cx
                syy += cy
                sxy += cxy
                if sxx != 0.0f64 && syy != 0.0f64 {
                    let n1 = f64(m - 1usize)
                    r = (sxy / n1) / (math.sqrt[f64](sxx / n1) * math.sqrt[f64](syy / n1))
                    if r > 1.0f64 { r = 1.0f64 }
                    if r < 0.0f64 - 1.0f64 { r = 0.0f64 - 1.0f64 }
                }
            }
            if use_abs && r == r { r = math.abs[f64](r) }
            out[i * p + j] = r
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// contr.bayes.unordered(n): the identity, a column for every level
fn contr_unordered(n: usize, out: []f64) {
    var i = 0usize
    while i < n * n {
        out[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        out[i * n + i] = 1.0f64
        i += 1usize
    }
}

// contr.bayes.ordered(n, scores, contrasts): the orthonormal polynomial columns of the centred scores with the constant kept, n by n row-major. Fails where qr would pivot (a rank-deficient
// Vandermonde matrix, from about a dozen levels on)
fn contr_ordered(a: *mem.Arena, n: usize, scores: []const f64, contrasts: bool, out: []f64) -> err {
    let (xm, e1) = mem.alloc[f64](a, n * n)
    if e1 != ok { ret e1 }
    let m = rmean(scores)
    var j = 0usize
    while j < n {
        var i = 0usize
        while i < n {
            let yv = scores[i] - m
            if j == 0usize {
                xm[j * n + i] = 1.0f64
            } else if j == 2usize {
                xm[j * n + i] = yv * yv
            } else {
                xm[j * n + i] = math.pow[f64](yv, f64(j))
            }
            i += 1usize
        }
        j += 1usize
    }
    let (f, e2) = dc.qr(a, xm, n, n, 0.0000001f64)
    if e2 != ok { ret e2 }
    if f.rank < n { ret dc.Singular }
    let (col, e3) = mem.alloc[f64](a, n)
    if e3 != ok { ret e3 }
    j = 0usize
    while j < n {
        var i = 0usize
        while i < n {
            col[i] = 0.0f64
            i += 1usize
        }
        col[j] = f.qr[j * n + j]
        dc.qr_qy(&f, col)
        var ss = 0.0f64
        i = 0usize
        while i < n {
            ss += col[i] * col[i]
            i += 1usize
        }
        let nr = math.sqrt[f64](ss)
        i = 0usize
        while i < n {
            out[i * n + j] = col[i] / nr
            if !contrasts && j == 0usize { out[i * n + j] = 1.0f64 }
            i += 1usize
        }
        j += 1usize
    }
    ret ok
}

// discrete.hist's numbers: bar.width (bw0 is NaN for the default), the plot's x range and top, the three bar offsets and the normalised heights. xs holds m positions (numeric) or is ignored
// (positions 1..m); prob, prob2, prob3 are m long, prob2 and prob3 only when has2 / has3. out = bar.width, xlo, xhi, ymax, offset 1..3, then per bar nine numbers: the heights prob, prob2,
// prob3 and the left and right edge of each of the three polygons
fn discrete_hist(a: *mem.Arena, xs: []const f64, m: usize, numeric: bool, prob: []const f64, has2: bool, prob2: []const f64, has3: bool, prob3: []const f64, freq: bool, bw0: f64, out: []f64) -> err {
    let (p1, e1) = mem.alloc[f64](a, m)
    let (p2, e2) = mem.alloc[f64](a, m)
    let (p3, e3) = mem.alloc[f64](a, m)
    let (xv, e4) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    var i = 0usize
    var s1 = 0.0f64
    var s2 = 0.0f64
    var s3 = 0.0f64
    while i < m {
        s1 += prob[i]
        if has2 { s2 += prob2[i] }
        if has3 { s3 += prob3[i] }
        i += 1usize
    }
    var top = 0.0f64
    i = 0usize
    while i < m {
        p1[i] = prob[i]
        p2[i] = 0.0f64
        p3[i] = 0.0f64
        if has2 { p2[i] = prob2[i] }
        if has3 { p3[i] = prob3[i] }
        if !freq {
            p1[i] = prob[i] / s1
            if has2 { p2[i] = prob2[i] / s2 }
            if has3 { p3[i] = prob3[i] / s3 }
        }
        if p1[i] > top { top = p1[i] }
        if has2 && p2[i] > top { top = p2[i] }
        if has3 && p3[i] > top { top = p3[i] }
        xv[i] = xs[i]
        if !numeric { xv[i] = f64(i + 1usize) }
        i += 1usize
    }
    var bw = bw0
    var lo = xv[0usize]
    var hi = xv[0usize]
    i = 1usize
    while i < m {
        if xv[i] < lo { lo = xv[i] }
        if xv[i] > hi { hi = xv[i] }
        i += 1usize
    }
    if bw != bw {
        bw = 0.2f64
        if numeric {
            // sorted unique positions: the smallest gap
            var gap = 1.0e308f64
            i = 0usize
            while i < m {
                var j = 0usize
                while j < m {
                    let d = xv[j] - xv[i]
                    if d > 0.0f64 && d < gap { gap = d }
                    j += 1usize
                }
                i += 1usize
            }
            bw = gap * 0.2f64
        }
    }
    out[0usize] = bw
    out[1usize] = lo - 2.0f64 * bw
    out[2usize] = hi + 2.0f64 * bw
    out[3usize] = top
    out[4usize] = 0.0f64
    out[5usize] = 0.0f64
    out[6usize] = 0.0f64
    if has2 && has3 {
        out[4usize] = 0.0f64 - bw
        out[6usize] = bw
    }
    if has2 && !has3 {
        out[4usize] = 0.0f64 - bw / 2.0f64
        out[5usize] = bw / 2.0f64
    }
    i = 0usize
    while i < m {
        let b = 7usize + 9usize * i
        out[b] = p1[i]
        out[b + 1usize] = p2[i]
        out[b + 2usize] = p3[i]
        var s = 0usize
        while s < 3usize {
            out[b + 3usize + 2usize * s] = xv[i] - bw / 2.0f64 + out[4usize + s]
            out[b + 4usize + 2usize * s] = xv[i] + bw / 2.0f64 + out[4usize + s]
            s += 1usize
        }
        i += 1usize
    }
    ret ok
}

// binnedplot's numbers: the x range and y range of its plot (range(xbar), range(ybar, 2se, -2se) without NaN) and the number of bins, from its default class count; out = xmin, xmax,
// ymin, ymax, bins
fn binnedplot_numbers(a: *mem.Arena, x: []const f64, y: []const f64, out: []f64) -> err {
    let nc = binnedplot_nclass(x.len)
    let (t, e) = mem.alloc[f64](a, (nc + 1usize) * 6usize)
    if e != ok { ret e }
    let bins = ar.binned_resids(a, x, y, nc, t)
    var xlo = 1.0e308f64
    var xhi = 0.0f64 - 1.0e308f64
    var ylo = 1.0e308f64
    var yhi = 0.0f64 - 1.0e308f64
    var b = 0usize
    while b < bins {
        let xb = t[b * 6usize]
        let yb = t[b * 6usize + 1usize]
        let se = t[b * 6usize + 5usize]
        if xb < xlo { xlo = xb }
        if xb > xhi { xhi = xb }
        if yb == yb {
            if yb < ylo { ylo = yb }
            if yb > yhi { yhi = yb }
        }
        if se == se {
            if se > yhi { yhi = se }
            if 0.0f64 - se < ylo { ylo = 0.0f64 - se }
            if 0.0f64 - se > yhi { yhi = 0.0f64 - se }
            if se < ylo { ylo = se }
        }
        b += 1usize
    }
    out[0usize] = xlo
    out[1usize] = xhi
    out[2usize] = ylo
    out[3usize] = yhi
    out[4usize] = f64(bins)
    ret ok
}

// coefplot's numbers for m coefficients with standard errors: out = coefs + CI sd, coefs - CI sd, est1 lower, est1 upper, est2 lower, est2 upper (m each) and the CI actually used last;
// lower and upper are the supplied confidence bounds when has_lo / has_up
fn coefplot_numbers(coefs: []const f64, sds: []const f64, m: usize, ci: f64, has_lo: bool, lower: []const f64, has_up: bool, upper: []const f64, out: []f64) {
    var cic = ci
    if has_lo || has_up { cic = 1.0f64 }
    var i = 0usize
    while i < m {
        out[i] = coefs[i] + ci * sds[i]
        out[m + i] = coefs[i] - ci * sds[i]
        out[2usize * m + i] = coefs[i] - sds[i]
        out[3usize * m + i] = coefs[i] + sds[i]
        if has_lo { out[2usize * m + i] = lower[i] }
        if has_up { out[3usize * m + i] = upper[i] }
        out[4usize * m + i] = coefs[i] - 2.0f64 * sds[i]
        out[5usize * m + i] = coefs[i] + 2.0f64 * sds[i]
        i += 1usize
    }
    out[6usize * m] = cic
}

// mcplot (multicomp.plot): bayes.pvalue[i, j] = mean((sign(object[, j] - object[, i]) + 1) / 2) and the significance matrix 0 + (p > 1 - alpha) - (p < alpha) with a zero diagonal, both
// with the columns reversed as the function returns them; object is nr by ind row-major, the results ind by ind row-major
fn mcplot_matrices(object: []const f64, nr: usize, ind: usize, alpha: f64, pv: []f64, sg: []f64) {
    var i = 0usize
    while i < ind {
        var j = 0usize
        while j < ind {
            var s = 0.0f64
            var k = 0usize
            while k < nr {
                let d = object[k * ind + j] - object[k * ind + i]
                var sgn = 0.0f64
                if d > 0.0f64 { sgn = 1.0f64 }
                if d < 0.0f64 { sgn = 0.0f64 - 1.0f64 }
                s += (sgn + 1.0f64) / 2.0f64
                k += 1usize
            }
            let p = s / f64(nr)
            var sig = 0.0f64
            if p > 1.0f64 - alpha { sig = sig + 1.0f64 }
            if p < alpha { sig = sig - 1.0f64 }
            if i == j { sig = 0.0f64 }
            pv[i * ind + (ind - 1usize - j)] = p
            sg[i * ind + (ind - 1usize - j)] = sig
            j += 1usize
        }
        i += 1usize
    }
}

// matching(z, score, replace = FALSE): match.ind (n), cnts (n) and pairs (n, NaN for NA), each treated unit in order taking the nearest unused control (ties by position)
fn matching_norep(a: *mem.Arena, z: []const f64, score: []const f64, n: usize, match_ind: []f64, cnts: []f64, pairs: []f64) {
    var i = 0usize
    while i < n {
        match_ind[i] = 0.0f64
        cnts[i] = 0.0f64
        if z[i] == 1.0f64 { cnts[i] = 1.0f64 }
        pairs[i] = nan()
        i += 1usize
    }
    var tally = 0.0f64
    i = 0usize
    while i < n {
        if z[i] == 1.0f64 {
            var best = n
            var bd = 0.0f64
            var j = 0usize
            while j < n {
                if z[j] == 0.0f64 && match_ind[j] == 0.0f64 {
                    let d = math.abs[f64](score[j] - score[i])
                    if best == n || d < bd {
                        best = j
                        bd = d
                    }
                }
                j += 1usize
            }
            if best < n {
                cnts[best] = 1.0f64
                match_ind[i] = f64(best + 1usize)
                match_ind[best] = f64(i + 1usize)
                tally += 1.0f64
                pairs[i] = tally
                pairs[best] = tally
            }
        }
        i += 1usize
    }
}

// matching(z, score, replace = TRUE): matches is nt by nc row-major (1 where the control is the nearest of the treated unit, ties broken by sample() in R's order), cnts has the length n and
// ind_cm the nt control indices matches %*% ind.c; the stream g is the one set.seed gave
fn matching_rep(a: *mem.Arena, g: *rng.Rng, z: []const f64, score: []const f64, n: usize, nt: usize, nc: usize, matches: []f64, cnts: []f64, ind_cm: []f64) -> err {
    let (indt, e1) = mem.alloc[usize](a, nt)
    let (indc, e2) = mem.alloc[usize](a, nc)
    if e1 != ok || e2 != ok { ret mem.Full }
    var it = 0usize
    var ic = 0usize
    var i = 0usize
    while i < n {
        cnts[i] = 0.0f64
        if z[i] == 1.0f64 {
            indt[it] = i
            it += 1usize
            cnts[i] = 1.0f64
        } else {
            indc[ic] = i
            ic += 1usize
        }
        i += 1usize
    }
    var tot = 0.0f64
    i = 0usize
    while i < nt {
        var mn = 1.0e308f64
        var j = 0usize
        while j < nc {
            let d = math.abs[f64](score[indt[i]] - score[indc[j]])
            if d < mn { mn = d }
            j += 1usize
        }
        j = 0usize
        while j < nc {
            let d = math.abs[f64](score[indt[i]] - score[indc[j]])
            matches[i * nc + j] = 0.0f64
            if d - mn == 0.0f64 { matches[i * nc + j] = 1.0f64 }
            tot += matches[i * nc + j]
            j += 1usize
        }
        i += 1usize
    }
    if tot > f64(nt) {
        i = 0usize
        while i < nt {
            var rs = 0.0f64
            var j = 0usize
            while j < nc {
                rs += matches[i * nc + j]
                j += 1usize
            }
            if rs > 1.0f64 {
                let nmi = usize(rs)
                let (idx, e3) = rng.sample_int(a, g, i64(nmi), i64(nmi), false)
                if e3 != ok { ret e3 }
                var pos = 0usize
                j = 0usize
                while j < nc {
                    if matches[i * nc + j] == 1.0f64 {
                        matches[i * nc + j] = 0.0f64
                        if idx[pos] == 1i64 { matches[i * nc + j] = 1.0f64 }
                        pos += 1usize
                    }
                    j += 1usize
                }
            }
            i += 1usize
        }
    }
    i = 0usize
    while i < nt {
        var s = 0.0f64
        var j = 0usize
        while j < nc {
            s += matches[i * nc + j] * f64(indc[j] + 1usize)
            j += 1usize
        }
        ind_cm[i] = s
        i += 1usize
    }
    var j = 0usize
    while j < nc {
        var s = 0.0f64
        i = 0usize
        while i < nt {
            s += matches[i * nc + j]
            i += 1usize
        }
        cnts[indc[j]] = s
        j += 1usize
    }
    ret ok
}

// binnedplot's default number of classes for n points
fn binnedplot_nclass(n: usize) -> usize {
    var nc = 0usize
    if n >= 100usize {
        nc = usize(math.floor[f64](math.sqrt[f64](f64(n))))
    }
    if n > 10usize && n < 100usize { nc = 10usize }
    if n <= 10usize { nc = n / 2usize }
    ret nc
}

// balance(rawdata, treat, matched, estimand): raw and matched are K by 5 row-major (treat mean, control mean, difference, absolute standardised difference, variance ratio or NaN), binary is K
// long; estimand 0 ATT, 1 ATC, 2 ATE; x is n by K row-major
fn balance_numbers(a: *mem.Arena, x: []const f64, treat: []const f64, matched: []const f64, n: usize, kk: usize, estimand: usize, raw: []f64, mat: []f64, binary: []f64) -> err {
    let (xt, e1) = mem.alloc[f64](a, n)
    let (xc, e2) = mem.alloc[f64](a, n)
    let (wc, e3) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var nt = 0usize
    var nc = 0usize
    var i = 0usize
    while i < n {
        if treat[i] == 1.0f64 { nt += 1usize }
        if treat[i] == 0.0f64 { nc += 1usize }
        i += 1usize
    }
    var c = 0usize
    while c < kk {
        var it = 0usize
        var ic = 0usize
        i = 0usize
        while i < n {
            if treat[i] == 1.0f64 {
                xt[it] = x[i * kk + c]
                it += 1usize
            }
            if treat[i] == 0.0f64 {
                xc[ic] = x[i * kk + c]
                wc[ic] = matched[i]
                ic += 1usize
            }
            i += 1usize
        }
        let mt = rmean(xt[0usize..nt])
        let mc = rmean(xc[0usize..nc])
        var st = 0.0f64
        var sc = 0.0f64
        i = 0usize
        while i < nt {
            st += (xt[i] - mt) * (xt[i] - mt)
            i += 1usize
        }
        i = 0usize
        while i < nc {
            sc += (xc[i] - mc) * (xc[i] - mc)
            i += 1usize
        }
        let vt = st / f64(nt - 1usize)
        let vc = sc / f64(nc - 1usize)
        var den = math.sqrt[f64](vt)
        if estimand == 1usize { den = math.sqrt[f64](vc) }
        if estimand == 2usize { den = math.sqrt[f64]((vt + vc) / 2.0f64) }
        raw[c * 5usize] = mt
        raw[c * 5usize + 1usize] = mc
        raw[c * 5usize + 2usize] = mt - mc
        raw[c * 5usize + 3usize] = math.abs[f64]((mt - mc) / den)
        raw[c * 5usize + 4usize] = nan()
        // the number of distinct values decides binary
        var distinct = 0usize
        i = 0usize
        while i < n {
            var seen = false
            var j = 0usize
            while j < i {
                if x[j * kk + c] == x[i * kk + c] { seen = true }
                j += 1usize
            }
            if !seen { distinct += 1usize }
            i += 1usize
        }
        binary[c] = 1.0f64
        if distinct > 2usize { binary[c] = 0.0f64 }
        // weighted mean and cov.wt(unbiased) of the controls
        var sw = 0.0f64
        i = 0usize
        while i < nc {
            sw += wc[i]
            i += 1usize
        }
        var wm = 0.0f64
        i = 0usize
        while i < nc {
            wm += xc[i] * wc[i]
            i += 1usize
        }
        wm = wm / sw
        var ctr = 0.0f64
        var w2 = 0.0f64
        i = 0usize
        while i < nc {
            ctr += (wc[i] / sw) * xc[i]
            w2 += (wc[i] / sw) * (wc[i] / sw)
            i += 1usize
        }
        var cv = 0.0f64
        i = 0usize
        while i < nc {
            let d = math.sqrt[f64](wc[i] / sw) * (xc[i] - ctr)
            cv += d * d
            i += 1usize
        }
        cv = cv / (1.0f64 - w2)
        mat[c * 5usize] = mt
        mat[c * 5usize + 1usize] = wm
        mat[c * 5usize + 2usize] = mt - wm
        mat[c * 5usize + 3usize] = math.abs[f64](mt - wm) / den
        mat[c * 5usize + 4usize] = nan()
        if distinct > 2usize { mat[c * 5usize + 4usize] = math.sqrt[f64](cv / vt) }
        c += 1usize
    }
    ret ok
}
