// R psych, the closed-form part: Cronbach `alpha` (raw and standardised), `kmo` (overall and per-item measure of
// sampling adequacy), `bartlett` (cortest.bartlett chi-square), `icc` (the six Shrout-Fleiss forms), `kappa`
// (unweighted Cohen kappa of a square table) and `mardia` (skewness and kurtosis statistics).
//
// Not here: omega, fa with its five methods, principal, polychoric, tetrachoric, biserial, fa.parallel, VSS,
// corr.test, describe, describeBy, scoreItems, weighted kappa, kappa confidence limits.

use e.algo.stat.quantreg as qr
use e.math
use e.algo.stat.desctools as dt
use e.mem

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
