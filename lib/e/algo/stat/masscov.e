// R MASS cov.rob (mve, mcd, classical): a port of mve_fitlots in MASS/src/lqs.c and the R code around it. The
// subsets come from the helpers of e.algo.stat.masslqs. Matrices are column-major.

use e.algo.linalg.decomp as decomp
use e.algo.rand.r as rng
use e.algo.stat.classint as ci
use e.algo.stat.masslqs as lq
use e.math
use e.math.nmath as nm
use e.math.special as sp
use e.mem

error Singular
error Collinear
error BadInput

// the squared Mahalanobis distances of every point to the mean of the subset, through the subset's QR; returns singular
fn do_one(a: *mem.Arena, x: []const f64, which: []const i64, n: usize, nnew: usize, p: usize, xr: []f64, means: []f64, tmp: []f64, d2: []f64, det: *f64) -> (bool, err) {
    var j = 0usize
    while j < nnew {
        var k = 0usize
        while k < p {
            xr[j + nnew * k] = x[usize(which[j]) + n * k]
            k += 1usize
        }
        j += 1usize
    }
    var k = 0usize
    while k < p {
        var sum = 0.0f64
        j = 0usize
        while j < nnew {
            sum += xr[j + nnew * k]
            j += 1usize
        }
        sum /= f64(nnew)
        means[k] = sum
        j = 0usize
        while j < nnew {
            xr[j + nnew * k] -= sum
            j += 1usize
        }
        k += 1usize
    }
    let (f, qe) = decomp.qr(a, xr[0usize..nnew * p], nnew, p, 1.0e-7f64)
    if qe != ok { ret (true, qe) }
    if f.rank < p { ret (true, ok) }
    var sum = 0.0f64
    k = 0usize
    while k < p {
        sum += math.log[f64](math.abs[f64](f.qr[k + nnew * k]))
        k += 1usize
    }
    *det = sum
    var i = 0usize
    while i < n {
        var ss = 0.0f64
        j = 0usize
        while j < p {
            var s = x[i + n * j] - means[j]
            var q = 0usize
            while q < j {
                s -= tmp[q] * f.qr[q + nnew * j]
                q += 1usize
            }
            tmp[j] = s / f.qr[j + nnew * j]
            ss += tmp[j] * tmp[j]
            j += 1usize
        }
        d2[i] = ss * f64(nnew - 1usize)
        i += 1usize
    }
    ret (false, ok)
}

// mve_fitlots: returns (crit, sing); bestone[i] is 1 for the points inside the best ellipsoid.
fn mve_fitlots(a: *mem.Arena, r: *rng.Rng, x: []const f64, nn: usize, p: usize, quan: usize, mcd: bool, sample: bool, nnew: usize, ntrials: usize, bestone: []i64) -> (f64, usize, err) {
    var ps = nnew
    if mcd { ps = nn }
    let (xr, e1) = mem.alloc[f64](a, ps * p)
    let (means, e2) = mem.alloc[f64](a, p)
    let (tmp, e3) = mem.alloc[f64](a, p)
    let (d2, e4) = mem.alloc[f64](a, nn)
    let (d2copy, e5) = mem.alloc[f64](a, nn)
    let (ind, e6) = mem.alloc[i64](a, nn)
    let (which, e7) = mem.alloc[i64](a, nnew)
    let (which2, e8) = mem.alloc[i64](a, ps)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret (0.0f64, 0usize, BadInput) }
    var sing = 0usize
    var best = 1.7976931348623157e308f64
    var thiscrit = 0.0f64
    var lim = 0.0f64
    var det = 0.0f64
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
            if trial > 0usize { lq.next_set(which, i64(nn), nnew) }
        } else {
            lq.sample_noreplace(r, ind, which, nn, nnew)
        }
        let (bad, qe) = do_one(a, x, which, nn, nnew, p, xr, means, tmp, d2, &det)
        if qe != ok { ret (0.0f64, sing, qe) }
        if bad {
            sing += 1usize
        } else {
            i = 0usize
            while i < nn {
                d2copy[i] = d2[i]
                i += 1usize
            }
            lq.rpsort(d2copy, quan - 1usize)
            lim = d2copy[quan - 1usize]
            if !mcd {
                thiscrit = f64(p) * math.log[f64](lim) + 2.0f64 * det
            } else {
                var iter = 0usize
                var brk = false
                while iter < 4usize && !brk {
                    if iter > 0usize {
                        i = 0usize
                        while i < nn {
                            d2copy[i] = d2[i]
                            i += 1usize
                        }
                        lq.rpsort(d2copy, quan - 1usize)
                        lim = d2copy[quan - 1usize]
                    }
                    var j = 0usize
                    i = 0usize
                    while i < nn {
                        if d2[i] <= lim {
                            which2[j] = i64(i)
                            j += 1usize
                        }
                        i += 1usize
                    }
                    let (b2, q2) = do_one(a, x, which2, nn, quan, p, xr, means, tmp, d2, &det)
                    if q2 != ok { ret (0.0f64, sing, q2) }
                    let _ = b2
                    if iter > 0usize && 2.0f64 * det >= 0.999f64 * thiscrit {
                        brk = true
                    } else {
                        thiscrit = 2.0f64 * det
                    }
                    iter += 1usize
                }
            }
            if thiscrit < best {
                best = thiscrit
                i = 0usize
                while i < nn {
                    bestone[i] = 0i64
                    if d2[i] <= lim { bestone[i] = 1i64 }
                    i += 1usize
                }
            }
        }
        mem.reset(a, mk)
        trial += 1usize
    }
    ret (best, sing, ok)
}

type Rob = struct { center: []f64, cov: []f64, crit: f64, best: []i64, nbest: usize, sing: usize }

fn col_var(x: []const f64, n: usize, p: usize, rows: []const i64, m: usize, means: []f64, v: []f64) {
    var k = 0usize
    while k < p {
        var s = 0.0f64
        var i = 0usize
        while i < m {
            s += x[usize(rows[i]) + n * k]
            i += 1usize
        }
        means[k] = s / f64(m)
        k += 1usize
    }
    var j = 0usize
    while j < p {
        k = 0usize
        while k < p {
            var s = 0.0f64
            var i = 0usize
            while i < m {
                s += (x[usize(rows[i]) + n * j] - means[j]) * (x[usize(rows[i]) + n * k] - means[k])
                i += 1usize
            }
            v[j + p * k] = s / f64(m - 1usize)
            k += 1usize
        }
        j += 1usize
    }
}

// the inverse of a p by p matrix by Gauss-Jordan with partial pivoting
fn inverse(a: *mem.Arena, m: []const f64, p: usize) -> ([]f64, err) {
    let (w, e1) = mem.alloc[f64](a, p * p)
    let (inv, e2) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok { ret (inv, BadInput) }
    var i = 0usize
    while i < p * p {
        w[i] = m[i]
        inv[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < p {
        inv[i + p * i] = 1.0f64
        i += 1usize
    }
    var c = 0usize
    while c < p {
        var piv = c
        var r = c + 1usize
        while r < p {
            if math.abs[f64](w[r + p * c]) > math.abs[f64](w[piv + p * c]) { piv = r }
            r += 1usize
        }
        if w[piv + p * c] == 0.0f64 { ret (inv, Singular) }
        var k = 0usize
        if piv != c {
            while k < p {
                let t = w[c + p * k]
                w[c + p * k] = w[piv + p * k]
                w[piv + p * k] = t
                let t2 = inv[c + p * k]
                inv[c + p * k] = inv[piv + p * k]
                inv[piv + p * k] = t2
                k += 1usize
            }
        }
        let d = w[c + p * c]
        k = 0usize
        while k < p {
            w[c + p * k] = w[c + p * k] / d
            inv[c + p * k] = inv[c + p * k] / d
            k += 1usize
        }
        r = 0usize
        while r < p {
            if r != c {
                let f = w[r + p * c]
                k = 0usize
                while k < p {
                    w[r + p * k] -= f * w[c + p * k]
                    inv[r + p * k] -= f * inv[c + p * k]
                    k += 1usize
                }
            }
            r += 1usize
        }
        c += 1usize
    }
    ret (inv, ok)
}

fn mahal(x: []const f64, n: usize, p: usize, center: []const f64, cinv: []const f64, out: []f64) {
    var i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < p {
            var t = 0.0f64
            var k = 0usize
            while k < p {
                t += (x[i + n * k] - center[k]) * cinv[k + p * j]
                k += 1usize
            }
            s += t * (x[i + n * j] - center[j])
            j += 1usize
        }
        out[i] = s
        i += 1usize
    }
}

// cov.rob. method 0 mve, 1 mcd, 2 classical; qn_in < 0 for floor((n+p+1)/2); nsamp -1 "best", -2 "exact", -3 "sample", else the count.
fn cov_rob(a: *mem.Arena, r: *rng.Rng, x0: []const f64, n: usize, p: usize, method: usize, qn_in: f64, nsamp_in: f64) -> (Rob, err) {
    var out: Rob = zero
    let (center, e1) = mem.alloc[f64](a, p)
    let (cv, e2) = mem.alloc[f64](a, p * p)
    let (rows, e3) = mem.alloc[i64](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret (out, BadInput) }
    var i = 0usize
    while i < n {
        rows[i] = i64(i)
        i += 1usize
    }
    if method == 2usize {
        col_var(x0, n, p, rows, n, center, cv)
        out = Rob { center: center, cov: cv, crit: 0.0f64, best: rows, nbest: n, sing: 0usize }
        ret (out, ok)
    }
    let nf = f64(n)
    let pf = f64(p)
    var qf = qn_in
    if qf < 0.0f64 { qf = math.floor[f64]((nf + pf + 1.0f64) / 2.0f64) }
    if qf < pf + 1.0f64 || qf > nf - 1.0f64 { ret (out, BadInput) }
    let qn = usize(qf)
    let (x, e4) = mem.alloc[f64](a, n * p)
    let (divisor, e5) = mem.alloc[f64](a, p)
    let (col, e6) = mem.alloc[f64](a, n)
    if e4 != ok || e5 != ok || e6 != ok { ret (out, BadInput) }
    var k = 0usize
    while k < p {
        i = 0usize
        while i < n {
            col[i] = x0[i + n * k]
            i += 1usize
        }
        lq.sortf(col)
        divisor[k] = ci.quantile_r(col, 0.75f64, 7u8) - ci.quantile_r(col, 0.25f64, 7u8)
        if divisor[k] == 0.0f64 { ret (out, BadInput) }
        k += 1usize
    }
    k = 0usize
    while k < p {
        i = 0usize
        while i < n {
            x[i + n * k] = x0[i + n * k] / divisor[k]
            i += 1usize
        }
        k += 1usize
    }
    let ps = p + 1usize
    let nexact = sp.choose(nf, f64(ps))
    var nsamp = nsamp_in
    if nsamp == -1.0f64 {
        if nexact < 5000.0f64 { nsamp = -2.0f64 } else { nsamp = -3.0f64 }
    }
    if nsamp > nexact { nsamp = -2.0f64 }
    var samp = true
    if nsamp == -2.0f64 { samp = false }
    if samp {
        if nsamp == -3.0f64 {
            nsamp = 500.0f64 * f64(ps)
            if nsamp > 3000.0f64 { nsamp = 3000.0f64 }
        }
    } else { nsamp = nexact }
    let (bestone, e7) = mem.alloc[i64](a, n)
    if e7 != ok { ret (out, BadInput) }
    i = 0usize
    while i < n {
        bestone[i] = 0i64
        i += 1usize
    }
    let (zc, sing, ze) = mve_fitlots(a, r, x, n, p, qn, method == 1usize, samp, ps, usize(nsamp), bestone)
    if ze != ok { ret (out, ze) }
    var crit = zc
    k = 0usize
    while k < p {
        crit += 2.0f64 * math.log[f64](divisor[k])
        k += 1usize
    }
    if method == 1usize { crit -= pf * math.log[f64](f64(qn) - 1.0f64) }
    let (best, e8) = mem.alloc[i64](a, n)
    if e8 != ok { ret (out, BadInput) }
    var nb = 0usize
    i = 0usize
    while i < n {
        if bestone[i] != 0i64 {
            best[nb] = i64(i)
            nb += 1usize
        }
        i += 1usize
    }
    if nb == 0usize { ret (out, Collinear) }
    let (means, e9) = mem.alloc[f64](a, p)
    let (d, e10) = mem.alloc[f64](a, n)
    if e9 != ok || e10 != ok { ret (out, BadInput) }
    col_var(x, n, p, best, nb, means, cv)
    let infl = (1.0f64 + 15.0f64 / (nf - pf)) * (1.0f64 + 15.0f64 / (nf - pf))
    i = 0usize
    while i < p * p {
        cv[i] = cv[i] * infl
        i += 1usize
    }
    let (cinv, ie) = inverse(a, cv, p)
    if ie != ok { ret (out, ie) }
    mahal(x, n, p, means, cinv, d)
    i = 0usize
    while i < n {
        col[i] = d[i]
        i += 1usize
    }
    lq.sortf(col)
    let cut = nm.qchisq(0.975f64, pf, true, false) * ci.quantile_r(col, f64(qn) / nf, 7u8) / nm.qchisq(f64(qn) / nf, pf, true, false)
    var m = 0usize
    i = 0usize
    while i < n {
        if d[i] < cut {
            rows[m] = i64(i)
            m += 1usize
        }
        i += 1usize
    }
    col_var(x, n, p, rows, m, means, cv)
    var j = 0usize
    while j < p {
        k = 0usize
        while k < p {
            cv[j + p * k] = divisor[j] * cv[j + p * k] * divisor[k]
            k += 1usize
        }
        center[j] = means[j] * divisor[j]
        j += 1usize
    }
    out = Rob { center: center, cov: cv, crit: crit, best: best, nbest: nb, sing: sing }
    ret (out, ok)
}
