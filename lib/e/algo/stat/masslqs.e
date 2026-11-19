// R MASS lqs (lts, lqs, lms and S estimation) and cov.rob (mve, mcd, classical): ports of MASS/src/lqs.c
// (lqs_fitlots, mve_fitlots) and the R code around them. The subsets come from R's unif_rand through the
// package's own sample_noreplace, or from next_set when every subset is tried.
//
// Matrices are column-major.

use e.algo.linalg.decomp as decomp
use e.algo.rand.r as rng
use e.algo.sort
use e.algo.stat.classint as ci
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.math.special as sp
use e.mem

error Singular
error Collinear
error BadInput

fn cmp_up(ctx: *u8, x: f64, y: f64) -> i32 {
    if x < y { ret 0i32 - 1i32 }
    if x > y { ret 1i32 }
    ret 0i32
}

fn sortf(x: []f64) {
    var d = 0u8
    sort.in_place_by[f64, u8](x, &d, cmp_up)
}

// R's rPsort: x[k] becomes the k-th smallest (0-based) and everything left of it is no larger.
fn rpsort(x: []f64, k: usize) {
    if x.len == 0usize { ret }
    var l = 0i64
    var r = i64(x.len) - 1i64
    let kk = i64(k)
    while l < r {
        let v = x[usize(kk)]
        var i = l
        var j = r
        while i <= j {
            while x[usize(i)] < v { i += 1i64 }
            while v < x[usize(j)] { j -= 1i64 }
            if i <= j {
                let w = x[usize(i)]
                x[usize(i)] = x[usize(j)]
                i += 1i64
                x[usize(j)] = w
                j -= 1i64
            }
        }
        if j < kk { l = i }
        if kk < i { r = j }
    }
}

fn sample_noreplace(r: *rng.Rng, ind: []i64, x: []i64, n: usize, k: usize) {
    var i = 0usize
    while i < n {
        ind[i] = i64(i)
        i += 1usize
    }
    var nn = n
    i = 0usize
    while i < k {
        let j = usize(f64(nn) * rng.unif(r))
        x[i] = ind[j]
        nn -= 1usize
        ind[j] = ind[nn]
        i += 1usize
    }
}

fn next_set(x: []i64, n: i64, k: usize) {
    var j = i64(k) - 1i64
    var tmp = x[usize(j)]
    x[usize(j)] = tmp + 1i64
    while j > 0i64 && x[usize(j)] >= n - (i64(k) - 1i64 - j) {
        j -= 1i64
        x[usize(j)] += 1i64
        tmp = x[usize(j)]
    }
    var i = usize(j) + 1usize
    while i < k {
        tmp += 1i64
        x[i] = tmp
        i += 1usize
    }
}

fn lmsadj(x: []const f64, n: usize, qn: usize) -> (f64, f64) {
    let k = qn - 1usize
    var best = x[k] - x[0usize]
    var adj = 0.5f64 * (x[k] + x[0usize])
    var i = 1usize
    while i + k < n {
        let len = x[i + k] - x[i]
        if len < best {
            best = len
            adj = 0.5f64 * (x[i + k] + x[i])
        }
        i += 1usize
    }
    ret (adj, 0.25f64 * best * best)
}

fn ltsadj(x: []const f64, n: usize, qn: usize) -> (f64, f64) {
    let k = qn - 1usize
    var m1 = 0.0f64
    var m2 = 0.0f64
    var i = 0usize
    while i < qn {
        m1 += x[i]
        m2 += x[i] * x[i]
        i += 1usize
    }
    let q = f64(qn)
    var adj = m1 / q
    var best = m2 - m1 * m1 / q
    i = 1usize
    while i + k < n {
        m1 += x[i + k] - x[i - 1usize]
        m2 += x[i + k] * x[i + k] - x[i - 1usize] * x[i - 1usize]
        let ss = m2 - m1 * m1 / q
        if ss < best {
            best = ss
            adj = m1 / q
        }
        i += 1usize
    }
    ret (adj, best)
}

fn chi(x0: f64, a: f64) -> f64 {
    var x = x0 / a
    x *= x
    if x > 1.0f64 { ret 1.0f64 }
    ret x * (3.0f64 + x * (-3.0f64 + x))
}

type Fit = struct { crit: f64, sing: usize, bestone: []i64, bestcoef: []f64 }

// lqs_fitlots. x is n by p; bestone (nwhich) and bestcoef (p) are filled; lts 0 lqs/lms, 1 lts, 2 S.
fn fitlots(a: *mem.Arena, r: *rng.Rng, x: []const f64, y: []const f64, nn: usize, pp: usize, qn: usize, lts: usize, adj: bool, sample: bool, nnew: usize, ntrials: usize, k0: f64, beta: f64, bestone: []i64, bestcoef: []f64) -> (Fit, err) {
    var out = Fit { crit: 0.0f64, sing: 0usize, bestone: bestone, bestcoef: bestcoef }
    let (res, e1) = mem.alloc[f64](a, nn)
    let (ind, e2) = mem.alloc[i64](a, nn)
    let (which, e3) = mem.alloc[i64](a, nnew)
    let (coef, e4) = mem.alloc[f64](a, pp)
    let (yr, e5) = mem.alloc[f64](a, nnew)
    let (xr, e6) = mem.alloc[f64](a, nnew * pp)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (out, BadInput) }
    let tgt = f64(nn - pp) * beta
    var best = 1.7976931348623157e308f64
    var firsttrial = true
    var old = 0.0f64
    var newv = 0.0f64
    var av = 0.0f64
    var i = 0usize
    if !sample {
        while i < nnew {
            which[i] = i64(i)
            i += 1usize
        }
    }
    var trial = 0usize
    while trial < ntrials {
        let mk = mem.mark(a)
        if !sample {
            if trial > 0usize { next_set(which, i64(nn), nnew) }
        } else {
            sample_noreplace(r, ind, which, nn, nnew)
        }
        var j = 0usize
        while j < nnew {
            let pick = usize(which[j])
            yr[j] = y[pick]
            var k = 0usize
            while k < pp {
                xr[j + nnew * k] = x[pick + nn * k]
                k += 1usize
            }
            j += 1usize
        }
        let (f, qe) = decomp.qr(a, xr, nnew, pp, 1.0e-7f64)
        if qe != ok { ret (out, qe) }
        if f.rank < pp {
            out.sing += 1usize
        } else {
            decomp.qr_qty(&f, yr)
            // dqrsl: b = R^-1 Q'y by columns
            j = 0usize
            while j < pp {
                coef[j] = yr[j]
                j += 1usize
            }
            var jj = pp
            while jj > 0usize {
                jj -= 1usize
                coef[jj] = coef[jj] / f.qr[jj * nnew + jj]
                let t = 0.0f64 - coef[jj]
                var q = 0usize
                while q < jj {
                    coef[q] += t * f.qr[jj * nnew + q]
                    q += 1usize
                }
            }
            i = 0usize
            while i < nn {
                var s = y[i]
                j = 0usize
                while j < pp {
                    s -= coef[j] * x[i + nn * j]
                    j += 1usize
                }
                res[i] = s
                i += 1usize
            }
            var thiscrit = 0.0f64
            var skip = false
            if lts < 2usize {
                if adj {
                    sortf(res)
                    if lts == 1usize {
                        let (ad, cr) = ltsadj(res, nn, qn)
                        av = ad
                        thiscrit = cr
                    } else {
                        let (ad, cr) = lmsadj(res, nn, qn)
                        av = ad
                        thiscrit = cr
                    }
                } else {
                    i = 0usize
                    while i < nn {
                        let s = res[i] - av
                        res[i] = s * s
                        i += 1usize
                    }
                    rpsort(res, qn - 1usize)
                    if lts == 0usize {
                        thiscrit = res[qn - 1usize]
                    } else {
                        var s = 0.0f64
                        i = 0usize
                        while i < qn {
                            s += res[i]
                            i += 1usize
                        }
                        thiscrit = s
                    }
                }
            } else {
                if firsttrial {
                    i = 0usize
                    while i < nn {
                        res[i] = math.abs[f64](res[i])
                        i += 1usize
                    }
                    rpsort(res, nn / 2usize)
                    old = res[nn / 2usize] / 0.6745f64
                    firsttrial = false
                } else {
                    var s = 0.0f64
                    i = 0usize
                    while i < nn {
                        s += chi(res[i], k0 * best)
                        i += 1usize
                    }
                    if s > tgt { skip = true } else { old = best }
                }
                if !skip {
                    var iter = 0usize
                    var brk = false
                    while iter < 30usize && !brk {
                        var s = 0.0f64
                        i = 0usize
                        while i < nn {
                            s += chi(res[i], k0 * old)
                            i += 1usize
                        }
                        newv = math.sqrt[f64](s / tgt) * old
                        if math.abs[f64](s / tgt - 1.0f64) < 1.0e-4f64 { brk = true } else { old = newv }
                        iter += 1usize
                    }
                    thiscrit = newv
                }
            }
            if !skip && thiscrit < best {
                best = thiscrit
                i = 0usize
                while i < nnew {
                    bestone[i] = which[i] + 1i64
                    i += 1usize
                }
                i = 0usize
                while i < pp {
                    bestcoef[i] = coef[i]
                    i += 1usize
                }
                bestcoef[0usize] += av
            }
        }
        mem.reset(a, mk)
        trial += 1usize
    }
    out.crit = best
    if best < 0.0f64 { out.crit = 0.0f64 }
    ret (out, ok)
}

type Lqs = struct { coef: []f64, residuals: []f64, bestone: []i64, crit: f64, sing: usize, nsamp: usize, scale: f64, scale2: f64 }

// lqs.default. x is n by p0 without the intercept column. method 0 lqs, 1 lts, 2 lms, 3 S; quantile < 0 for the default;
// psamp 0 for p; nsamp -1 "best", -2 "exact", -3 "sample", else the count; adjust is control$adjust.
fn lqs(a: *mem.Arena, r: *rng.Rng, x0: []const f64, n: usize, p0: usize, y: []const f64, intercept: bool, method: usize, quantile: f64, psamp: usize, nsamp_in: f64, adjust: bool, k0: f64) -> (Lqs, err) {
    var out: Lqs = zero
    var p = p0
    if intercept { p += 1usize }
    let (x, ex) = mem.alloc[f64](a, n * p)
    if ex != ok { ret (out, ex) }
    var i = 0usize
    var off = 0usize
    if intercept {
        while i < n {
            x[i] = 1.0f64
            i += 1usize
        }
        off = n
    }
    i = 0usize
    while i < n * p0 {
        x[off + i] = x0[i]
        i += 1usize
    }
    var lts = 0usize
    var beta = 0.0f64
    var q = quantile
    let nf = f64(n)
    let pf = f64(p)
    if method == 0usize && q < 0.0f64 { q = math.floor[f64]((nf + pf + 1.0f64) / 2.0f64) }
    if method == 2usize { q = math.floor[f64]((nf + 1.0f64) / 2.0f64) }
    if method == 1usize {
        lts = 1usize
        if q < 0.0f64 { q = math.floor[f64](nf / 2.0f64) + math.floor[f64]((pf + 1.0f64) / 2.0f64) }
    }
    if method == 3usize {
        lts = 2usize
        beta = 0.5f64
        q = math.ceil[f64](nf / 2.0f64)
    }
    if q > nf - 1.0f64 { ret (out, BadInput) }
    let qn = usize(q)
    var ps = psamp
    if ps == 0usize { ps = p }
    if ps < p { ps = p }
    let doadj = adjust && intercept
    let nexact = sp.choose(nf, f64(ps))
    var nsamp = nsamp_in
    var samp = true
    if nsamp == -1.0f64 {
        if nexact < 5000.0f64 { nsamp = -2.0f64 } else { nsamp = -3.0f64 }
    } else if nsamp > nexact { nsamp = -2.0f64 }
    if nsamp == -2.0f64 { samp = false }
    if samp {
        if nsamp == -3.0f64 {
            nsamp = 500.0f64 * f64(ps)
            if nsamp > 3000.0f64 { nsamp = 3000.0f64 }
        }
    } else { nsamp = nexact }
    let (bestone, e1) = mem.alloc[i64](a, ps)
    let (bestcoef, e2) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok { ret (out, BadInput) }
    let (fit, fe) = fitlots(a, r, x, y, n, p, qn, lts, doadj, samp, ps, usize(nsamp), k0, beta, bestone, bestcoef)
    if fe != ok { ret (out, fe) }
    if fit.sing == usize(nsamp) { ret (out, Singular) }
    // sort(bestone)
    i = 1usize
    while i < ps {
        let v = bestone[i]
        var j = i
        while j > 0usize && bestone[j - 1usize] > v {
            bestone[j] = bestone[j - 1usize]
            j -= 1usize
        }
        bestone[j] = v
        i += 1usize
    }
    let (resid, e3) = mem.alloc[f64](a, n)
    if e3 != ok { ret (out, BadInput) }
    i = 0usize
    while i < n {
        var fv = 0.0f64
        var j = 0usize
        while j < p {
            fv += x[i + n * j] * bestcoef[j]
            j += 1usize
        }
        resid[i] = y[i] - fv
        i += 1usize
    }
    let c1 = 1.0f64 / dist.qnorm((nf + q) / (2.0f64 * nf), 0.0f64, 1.0f64, true, false)
    var s = 0.0f64
    if lts == 1usize {
        s = math.sqrt[f64](fit.crit / q) / math.sqrt[f64](1.0f64 - 2.0f64 * nf * dist.dnorm(1.0f64 / c1, 0.0f64, 1.0f64, false) / (q * c1))
    } else if lts == 0usize {
        s = math.sqrt[f64](fit.crit) * c1
    } else { s = fit.crit }
    var ss = 0.0f64
    var cnt = 0usize
    i = 0usize
    while i < n {
        if math.abs[f64](resid[i]) <= 2.5f64 * s {
            ss += resid[i] * resid[i]
            cnt += 1usize
        }
        i += 1usize
    }
    var scale = s
    let scale2 = math.sqrt[f64](ss / f64(cnt - p))
    var rs = resid
    if method == 3usize {
        let (rr, e4) = mem.alloc[f64](a, n)
        if e4 != ok { ret (out, BadInput) }
        i = 0usize
        while i < n {
            rr[i] = resid[i]
            i += 1usize
        }
        var it = 0usize
        var brk = false
        while it < 30usize && !brk {
            let (xw, e5) = mem.alloc[f64](a, n * p)
            let (yw, e6) = mem.alloc[f64](a, n)
            if e5 != ok || e6 != ok { ret (out, BadInput) }
            var m = 0usize
            var row = 0usize
            while row < n {
                let u = math.abs[f64](rr[row] / scale / k0)
                var um = u
                if um > 1.0f64 { um = 1.0f64 }
                let w = (1.0f64 - um * um) * (1.0f64 - um * um)
                if w > 0.0f64 {
                    let sw = math.sqrt[f64](w)
                    var c = 0usize
                    while c < p {
                        xw[m + n * c] = x[row + n * c] * sw
                        c += 1usize
                    }
                    yw[m] = y[row] * sw
                    m += 1usize
                }
                row += 1usize
            }
            // compact the m rows to a column-major m by p
            let (xc, e7) = mem.alloc[f64](a, m * p)
            if e7 != ok { ret (out, BadInput) }
            var c = 0usize
            while c < p {
                var rrw = 0usize
                while rrw < m {
                    xc[rrw + m * c] = xw[rrw + n * c]
                    rrw += 1usize
                }
                c += 1usize
            }
            let (lf, le) = decomp.lm_fit(a, xc, m, p, yw[0usize..m], 1.0e-7f64)
            if le != ok { ret (out, le) }
            i = 0usize
            while i < n {
                var fv = 0.0f64
                var j = 0usize
                while j < p {
                    if lf.coef[j] == lf.coef[j] { fv += x[i + n * j] * lf.coef[j] }
                    j += 1usize
                }
                rr[i] = y[i] - fv
                i += 1usize
            }
            var sc = 0.0f64
            i = 0usize
            while i < n {
                sc += chi(rr[i] / scale, k0)
                i += 1usize
            }
            let s2 = scale * math.sqrt[f64](sc / (f64(n - p) * beta))
            if math.abs[f64](s2 / scale - 1.0f64) < 1.0e-5f64 { brk = true } else { scale = s2 }
            it += 1usize
        }
        rs = rr
    }
    out = Lqs { coef: bestcoef, residuals: rs, bestone: bestone, crit: fit.crit, sing: fit.sing, nsamp: usize(nsamp), scale: scale, scale2: scale2 }
    ret (out, ok)
}
