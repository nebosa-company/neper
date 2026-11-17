// R vars::stability, which fits strucchange::efp to every equation of a VAR: the empirical fluctuation processes OLS-CUSUM, Rec-CUSUM, Rec-MOSUM,
// OLS-MOSUM, RE (the "fluctuation" type), ME, Score-CUSUM and Score-MOSUM of a regression y on the rows of x, the recursive residuals they build on, and
// sctest's statistic under the four functionals max, range, maxL2 and meanL2, with the closed-form p values of the Brownian motion and Brownian bridge
// maxima and of the bridge range.
//
// Not here: the tabulated p values (the MOSUM limits and the maxL2, meanL2 critical values), alternative boundaries, dynamic models, custom lrvar and vcov.
// Rank-deficient subsamples are not handled: every regression is assumed to have full column rank.

use e.algo.stat.vars2 as vr
use e.math
use e.math.dist as dist
use e.mem

// the types of process
const REC_CUSUM: usize = 0usize
const OLS_CUSUM: usize = 1usize
const REC_MOSUM: usize = 2usize
const OLS_MOSUM: usize = 3usize
const RE: usize = 4usize
const ME: usize = 5usize
const SCORE_CUSUM: usize = 6usize
const SCORE_MOSUM: usize = 7usize

fn sd_of(x: []const f64, n: usize) -> f64 {
    var m = 0.0f64
    var i = 0usize
    while i < n {
        m += x[i]
        i += 1usize
    }
    m = m / f64(n)
    var s = 0.0f64
    i = 0usize
    while i < n {
        s += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    ret math.sqrt[f64](s / f64(n - 1usize))
}

// lm.fit of y on all k columns of x (n by k, row-major): coefficients and residuals
fn lm_all(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, k: usize, coef: []f64, resid: []f64) -> err {
    let cols = vr.zeros_usize(a, k)
    var j = 0usize
    while j < k {
        cols[j] = j
        j += 1usize
    }
    ret vr.ols_cols(a, x, n, k, cols, k, y, coef, resid)
}

// the symmetric square root of the k by k positive semidefinite m, by cyclic Jacobi
fn sqrt_sym(a: *mem.Arena, m: []const f64, k: usize, out: []f64) {
    let w = vr.zeros(a, k * k)
    let v = vr.ident(a, k)
    var i = 0usize
    while i < k * k {
        w[i] = m[i]
        i += 1usize
    }
    var sweep = 0usize
    while sweep < 100usize {
        var off = 0.0f64
        var tot = 0.0f64
        i = 0usize
        while i < k {
            var j = 0usize
            while j < k {
                tot += w[i * k + j] * w[i * k + j]
                if i != j { off += w[i * k + j] * w[i * k + j] }
                j += 1usize
            }
            i += 1usize
        }
        if off <= 1.0e-32f64 * tot { sweep = 1000usize } else {
            var p = 0usize
            while p + 1usize < k {
                var q = p + 1usize
                while q < k {
                    let apq = w[p * k + q]
                    if apq != 0.0f64 {
                        let theta = (w[q * k + q] - w[p * k + p]) / (2.0f64 * apq)
                        var t = 1.0f64 / (math.abs[f64](theta) + math.sqrt[f64](theta * theta + 1.0f64))
                        if theta < 0.0f64 { t = 0.0f64 - t }
                        let c = 1.0f64 / math.sqrt[f64](t * t + 1.0f64)
                        let s = t * c
                        var r = 0usize
                        while r < k {
                            let wp = w[r * k + p]
                            let wq = w[r * k + q]
                            w[r * k + p] = c * wp - s * wq
                            w[r * k + q] = s * wp + c * wq
                            r += 1usize
                        }
                        r = 0usize
                        while r < k {
                            let wp = w[p * k + r]
                            let wq = w[q * k + r]
                            w[p * k + r] = c * wp - s * wq
                            w[q * k + r] = s * wp + c * wq
                            r += 1usize
                        }
                        r = 0usize
                        while r < k {
                            let vp = v[r * k + p]
                            let vq = v[r * k + q]
                            v[r * k + p] = c * vp - s * vq
                            v[r * k + q] = s * vp + c * vq
                            r += 1usize
                        }
                    }
                    q += 1usize
                }
                p += 1usize
            }
            sweep += 1usize
        }
    }
    i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            var s = 0.0f64
            var l = 0usize
            while l < k {
                var d = w[l * k + l]
                if d < 0.0f64 { d = 0.0f64 }
                s += v[i * k + l] * math.sqrt[f64](d) * v[j * k + l]
                l += 1usize
            }
            out[i * k + j] = s
            j += 1usize
        }
        i += 1usize
    }
}

// x'x of the rows (n by k) as k by k
fn gram(a: *mem.Arena, x: []const f64, n: usize, k: usize) -> []f64 { ret vr.mcross(a, x, x, n, k, k) }

// recresid(x, y): the n - k recursive residuals (strucchange's R engine); x is n by k row-major
fn recresid(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, k: usize, out: []f64) -> err {
    let q = k
    let tol = 1.4901161193847656e-8f64 / f64(k)
    let beta = vr.zeros(a, k)
    let res = vr.zeros(a, n)
    let x1 = vr.zeros(a, k * k)
    var e = lm_all(a, x[0usize..q * k], y[0usize..q], q, k, beta, res)
    if e != ok { ret e }
    e = inv_gram(a, x[0usize..q * k], q, k, x1)
    if e != ok { ret e }
    var xr = vr.zeros(a, k)
    var fr = 0.0f64
    var j = 0usize
    while j < k {
        xr[j] = x[q * k + j]
        j += 1usize
    }
    fr = 1.0f64 + quad(x1, xr, k)
    var dot = 0.0f64
    j = 0usize
    while j < k {
        dot += xr[j] * beta[j]
        j += 1usize
    }
    out[0usize] = (y[q] - dot) / math.sqrt[f64](fr)
    var check = true
    var r = q + 2usize
    // r is the 1-based row index q + 2 .. n, i.e. 0-based r - 1
    while r <= n {
        // X1 <- X1 - X1 xr xr' X1 / fr
        let xx = vr.zeros(a, k)
        var i = 0usize
        while i < k {
            var s = 0.0f64
            j = 0usize
            while j < k {
                s += x1[i * k + j] * xr[j]
                j += 1usize
            }
            xx[i] = s
            i += 1usize
        }
        i = 0usize
        while i < k {
            j = 0usize
            while j < k {
                x1[i * k + j] = x1[i * k + j] - xx[i] * xx[j] / fr
                j += 1usize
            }
            i += 1usize
        }
        // betar <- betar + X1 xr * rval[r - q - 1] * sqrt(fr), with the updated X1
        i = 0usize
        while i < k {
            var s = 0.0f64
            j = 0usize
            while j < k {
                s += x1[i * k + j] * xr[j]
                j += 1usize
            }
            beta[i] = beta[i] + s * out[r - q - 2usize] * math.sqrt[f64](fr)
            i += 1usize
        }
        if check {
            let bf = vr.zeros(a, k)
            let rf = vr.zeros(a, n)
            let ee = lm_all(a, x[0usize..(r - 1usize) * k], y[0usize..r - 1usize], r - 1usize, k, bf, rf)
            if ee != ok { ret ee }
            // all.equal(fm$coefficients, betar, tolerance = tol): mean relative difference
            var xy = 0.0f64
            var xn = 0.0f64
            i = 0usize
            while i < k {
                xy += math.abs[f64](bf[i] - beta[i])
                xn += math.abs[f64](bf[i])
                i += 1usize
            }
            xy = xy / f64(k)
            xn = xn / f64(k)
            if xn > tol { xy = xy / xn }
            if xy <= tol { check = false }
            let ie = inv_gram(a, x[0usize..(r - 1usize) * k], r - 1usize, k, x1)
            if ie != ok { ret ie }
            i = 0usize
            while i < k {
                beta[i] = bf[i]
                i += 1usize
            }
        }
        j = 0usize
        while j < k {
            xr[j] = x[(r - 1usize) * k + j]
            j += 1usize
        }
        fr = 1.0f64 + quad(x1, xr, k)
        dot = 0.0f64
        j = 0usize
        while j < k {
            dot += xr[j] * beta[j]
            j += 1usize
        }
        out[r - q - 1usize] = (y[r - 1usize] - dot) / math.sqrt[f64](fr)
        r += 1usize
    }
    ret ok
}

// xr' m xr
fn quad(m: []const f64, xr: []const f64, k: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            s += xr[i] * m[i * k + j] * xr[j]
            j += 1usize
        }
        i += 1usize
    }
    ret s
}

// (x'x)^-1 of the rows x (n by k row-major)
fn inv_gram(a: *mem.Arena, x: []const f64, n: usize, k: usize, out: []f64) -> err {
    let cm = vr.zeros(a, n * k)
    var t = 0usize
    while t < n {
        var j = 0usize
        while j < k {
            cm[j * n + t] = x[t * k + j]
            j += 1usize
        }
        t += 1usize
    }
    ret vr.xtx_inverse_cm(a, cm, n, k, out)
}

// sdev(x, df): sd(x) * sqrt((length(x) - 1) / df); df of 0 means length(x) - 1
fn sdev(x: []const f64, n: usize, df: usize) -> f64 {
    var d = f64(n - 1usize)
    if df > 0usize { d = f64(df) }
    ret sd_of(x, n) * math.sqrt[f64](f64(n - 1usize) / d)
}

// efp(y ~ -1 + x, type, h, dynamic = FALSE, rescale): the process is written row-major into proc (rows by cols); returns (rows, cols)
fn efp_process(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, k: usize, typ: usize, h: f64, rescale: bool, proc: []f64) -> (usize, usize, err) {
    let beta = vr.zeros(a, k)
    let e = vr.zeros(a, n)
    let e0 = lm_all(a, x, y, n, k, beta, e)
    if e0 != ok { ret (0usize, 0usize, e0) }
    let sq = math.sqrt[f64](f64(n))
    if typ == OLS_CUSUM {
        let sigma = sdev(e, n, n - k)
        var s = 0.0f64
        proc[0usize] = 0.0f64
        var i = 0usize
        while i < n {
            s += e[i]
            proc[i + 1usize] = s / (sigma * sq)
            i += 1usize
        }
        ret (n + 1usize, 1usize, ok)
    }
    if typ == OLS_MOSUM {
        let sigma = sdev(e, n, n - k)
        let nh = usize(math.floor[f64](f64(n) * h))
        let cs = vr.zeros(a, n + 1usize)
        var i = 0usize
        while i < n {
            cs[i + 1usize] = cs[i] + e[i]
            i += 1usize
        }
        i = 0usize
        while i + nh <= n {
            proc[i] = (cs[i + nh] - cs[i]) / (sigma * sq)
            i += 1usize
        }
        ret (n - nh + 1usize, 1usize, ok)
    }
    if typ == REC_CUSUM || typ == REC_MOSUM {
        let nw = n - k
        let w = vr.zeros(a, nw)
        let re = recresid(a, x, y, n, k, w)
        if re != ok { ret (0usize, 0usize, re) }
        if typ == REC_CUSUM {
            let sigma = sdev(w, nw, 0usize)
            var s = 0.0f64
            proc[0usize] = 0.0f64
            var i = 0usize
            while i < nw {
                s += w[i]
                proc[i + 1usize] = s / (sigma * math.sqrt[f64](f64(nw)))
                i += 1usize
            }
            ret (nw + 1usize, 1usize, ok)
        }
        let nh = usize(math.floor[f64](f64(nw) * h))
        let sigma = sdev(w, nw, nw - k)
        var i = 0usize
        while i + nh <= nw {
            var s = 0.0f64
            var j = 0usize
            while j < nh {
                s += w[i + j]
                j += 1usize
            }
            proc[i] = s / (sigma * math.sqrt[f64](f64(nw)))
            i += 1usize
        }
        ret (nw - nh + 1usize, 1usize, ok)
    }
    if typ == RE || typ == ME {
        let sigma = sdev(e, n, n - k)
        let g = gram(a, x, n, k)
        let q12 = vr.zeros(a, k * k)
        sqrt_sym(a, g, k, q12)
        var i = 0usize
        while i < k * k {
            q12[i] = q12[i] / (sigma * sq)
            i += 1usize
        }
        let bi = vr.zeros(a, k)
        let ri = vr.zeros(a, n)
        let qi = vr.zeros(a, k * k)
        let dv = vr.zeros(a, k)
        if typ == RE {
            // columns of the process for the fits on the first i rows, i = k .. n - 1, then a zero column; row 0 is the zero start
            let rows = n - k + 2usize
            i = 0usize
            while i < rows * k {
                proc[i] = 0.0f64
                i += 1usize
            }
            i = k
            while i <= n - 1usize {
                let ee = lm_all(a, x[0usize..i * k], y[0usize..i], i, k, bi, ri)
                if ee != ok { ret (0usize, 0usize, ee) }
                var j = 0usize
                while j < k {
                    dv[j] = bi[j] - beta[j]
                    j += 1usize
                }
                var qm = q12
                if rescale {
                    let gi = gram(a, x[0usize..i * k], i, k)
                    sqrt_sym(a, gi, k, qi)
                    j = 0usize
                    while j < k * k {
                        qi[j] = qi[j] / (sigma * math.sqrt[f64](f64(i)))
                        j += 1usize
                    }
                    qm = qi
                }
                // process[, i - k + 1] times (i) / sqrt(n): row i - k + 1 of the transposed matrix (row 0 is the start) times its weight (k - 1) + (row)
                let row = i - k + 1usize
                j = 0usize
                while j < k {
                    var s = 0.0f64
                    var l = 0usize
                    while l < k {
                        s += qm[j * k + l] * dv[l]
                        l += 1usize
                    }
                    proc[row * k + j] = s * f64(k - 1usize + row) / sq
                    j += 1usize
                }
                i += 1usize
            }
            ret (rows, k, ok)
        }
        let nh = usize(math.floor[f64](f64(n) * h))
        let rows = n - nh + 1usize
        i = 0usize
        while i < rows {
            let xs = x[i * k..(i + nh) * k]
            let ee = lm_all(a, xs, y[i..i + nh], nh, k, bi, ri)
            if ee != ok { ret (0usize, 0usize, ee) }
            var j = 0usize
            while j < k {
                dv[j] = bi[j] - beta[j]
                j += 1usize
            }
            var qm = q12
            if rescale {
                let gi = gram(a, xs, nh, k)
                sqrt_sym(a, gi, k, qi)
                j = 0usize
                while j < k * k {
                    qi[j] = qi[j] / (sigma * math.sqrt[f64](f64(nh)))
                    j += 1usize
                }
                qm = qi
            }
            j = 0usize
            while j < k {
                var s = 0.0f64
                var l = 0usize
                while l < k {
                    s += qm[j * k + l] * dv[l]
                    l += 1usize
                }
                proc[i * k + j] = f64(nh) * s / sq
                j += 1usize
            }
            i += 1usize
        }
        ret (rows, k, ok)
    }
    // the score processes: n by (k + 1) of x e and e^2 - sigma2, scaled by 1 / sqrt(n)
    let kk = k + 1usize
    var s2 = 0.0f64
    var t = 0usize
    while t < n {
        s2 += e[t] * e[t]
        t += 1usize
    }
    s2 = s2 / f64(n)
    let sc = vr.zeros(a, n * kk)
    t = 0usize
    while t < n {
        var j = 0usize
        while j < k {
            sc[t * kk + j] = x[t * k + j] * e[t] / sq
            j += 1usize
        }
        sc[t * kk + k] = (e[t] * e[t] - s2) / sq
        t += 1usize
    }
    let gs = gram(a, sc, n, kk)
    let q12 = vr.zeros(a, kk * kk)
    sqrt_sym(a, gs, kk, q12)
    let qinv = vr.minv(a, q12, kk)
    let cs = vr.zeros(a, (n + 1usize) * kk)
    t = 0usize
    while t < n {
        var j = 0usize
        while j < kk {
            cs[(t + 1usize) * kk + j] = cs[t * kk + j] + sc[t * kk + j]
            j += 1usize
        }
        t += 1usize
    }
    var rows = n + 1usize
    var nh = 0usize
    if typ == SCORE_MOSUM {
        nh = usize(math.floor[f64](f64(n) * h))
        rows = n - nh + 1usize
    }
    let raw = vr.zeros(a, kk)
    var r = 0usize
    while r < rows {
        var j = 0usize
        while j < kk {
            if typ == SCORE_MOSUM { raw[j] = cs[(r + nh) * kk + j] - cs[r * kk + j] } else { raw[j] = cs[r * kk + j] }
            j += 1usize
        }
        j = 0usize
        while j < kk {
            var s = 0.0f64
            var l = 0usize
            while l < kk {
                s += qinv[j * kk + l] * raw[l]
                l += 1usize
            }
            proc[r * kk + j] = s
            j += 1usize
        }
        r += 1usize
    }
    ret (rows, kk, ok)
}

// the Brownian bridge maximum p value 1 - (1 + 2 sum_i (-1)^i exp(-2 i^2 x^2))^k, and 1 below x = 0.1
fn p_bridge_max(x: f64, k: usize) -> f64 {
    if x < 0.1f64 { ret 1.0f64 }
    var s = 0.0f64
    var i = 1usize
    while i <= 100usize {
        var sg = 1.0f64
        if i % 2usize == 1usize { sg = 0.0f64 - 1.0f64 }
        s += math.exp[f64](0.0f64 - 2.0f64 * f64(i * i) * x * x) * sg
        i += 1usize
    }
    ret 1.0f64 - math.pow[f64](1.0f64 + 2.0f64 * s, f64(k))
}

// the Brownian motion maximum p value of the Rec-CUSUM test
fn p_motion_max(x: f64, k: usize) -> f64 {
    var p = 0.0f64
    if x < 0.3f64 {
        p = 1.0f64 - 0.1465f64 * x
    } else {
        let pn3 = dist.pnorm(3.0f64 * x, 0.0f64, 1.0f64, true, false)
        let pn1 = dist.pnorm(x, 0.0f64, 1.0f64, true, false)
        let pn5 = dist.pnorm(5.0f64 * x, 0.0f64, 1.0f64, true, false)
        p = 2.0f64 * (1.0f64 - pn3 + math.exp[f64](0.0f64 - 4.0f64 * x * x) * (pn1 + pn5 - 1.0f64) - math.exp[f64](0.0f64 - 16.0f64 * x * x) * (1.0f64 - pn1))
    }
    ret 1.0f64 - math.pow[f64](1.0f64 - p, f64(k))
}

// the Brownian bridge range p value 1 - (1 - 2 sum_{i <= 10} (4 i^2 x^2 - 1) exp(-2 i^2 x^2))^k, and 1 below x = 0.4
fn p_bridge_range(x: f64, k: usize) -> f64 {
    if x < 0.4f64 { ret 1.0f64 }
    var s = 0.0f64
    var i = 1usize
    while i <= 10usize {
        let q = f64(i * i)
        s += (4.0f64 * q * x * x - 1.0f64) * math.exp[f64](0.0f64 - 2.0f64 * q * x * x)
        i += 1usize
    }
    ret 1.0f64 - math.pow[f64](1.0f64 - 2.0f64 * s, f64(k))
}

// sctest(efp, functional): the statistic, from a process (rows by cols, row-major); the Brownian motion and bridge limits drop the first row, and the
// Brownian motion divides by 1 + 2 j / n. fun 0 max, 1 range, 2 maxL2, 3 meanL2
fn sctest_stat(a: *mem.Arena, proc: []const f64, rows: usize, cols: usize, typ: usize, fun: usize) -> f64 {
    var first = 0usize
    if typ == REC_CUSUM || typ == OLS_CUSUM || typ == RE || typ == SCORE_CUSUM { first = 1usize }
    let n = rows - first
    let x = vr.zeros(a, n * cols)
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < cols {
            var v = proc[(i + first) * cols + j]
            if typ == REC_CUSUM { v = v / (1.0f64 + 2.0f64 * f64(i + 1usize) / f64(n)) }
            x[i * cols + j] = v
            j += 1usize
        }
        i += 1usize
    }
    if fun == 0usize {
        var m = 0.0f64
        i = 0usize
        while i < n * cols {
            if math.abs[f64](x[i]) > m { m = math.abs[f64](x[i]) }
            i += 1usize
        }
        ret m
    }
    if fun == 1usize {
        var best = 0.0f64
        var j = 0usize
        while j < cols {
            var lo = x[j]
            var hi = x[j]
            i = 1usize
            while i < n {
                if x[i * cols + j] < lo { lo = x[i * cols + j] }
                if x[i * cols + j] > hi { hi = x[i * cols + j] }
                i += 1usize
            }
            if hi - lo > best { best = hi - lo }
            j += 1usize
        }
        ret best
    }
    var mx = 0.0f64
    var sm = 0.0f64
    i = 0usize
    while i < n {
        var rs = 0.0f64
        var j = 0usize
        while j < cols {
            rs += x[i * cols + j] * x[i * cols + j]
            j += 1usize
        }
        if i == 0usize || rs > mx { mx = rs }
        sm += rs
        i += 1usize
    }
    if fun == 2usize { ret mx }
    ret sm / f64(n)
}

// the closed-form p value of the max functional for the CUSUM, RE and score-CUSUM limits; NaN where the package tabulates
fn sctest_p(stat: f64, typ: usize, cols: usize) -> f64 {
    if typ == REC_CUSUM { ret p_motion_max(stat, cols) }
    if typ == OLS_CUSUM || typ == RE || typ == SCORE_CUSUM { ret p_bridge_max(stat, cols) }
    ret 0.0f64 / 0.0f64
}
