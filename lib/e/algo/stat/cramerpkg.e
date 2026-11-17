// R cramer (Baringhaus and Franz): the Cramer two-sample statistic over the kernels phiCramer, phiBahr, phiLog, phiFracA and phiFracB, its ordinary and permutation Monte-Carlo critical values (boot's index arrays over R's sample.int) and the eigenvalue method (Gurland's inversion by a fast Fourier transform).
//
// data is (m + n) rows of d columns, row-major; kernel 0 .. 4.

use e.algo.rand.r as rng
use e.math
use e.math.fft as fft
use e.mem

fn phi(kernel: usize, z: f64) -> f64 {
    if kernel == 0usize { ret math.sqrt[f64](z) / 2.0f64 }
    if kernel == 1usize { ret 1.0f64 - math.exp[f64](0.0f64 - z / 2.0f64) }
    if kernel == 2usize { ret math.log[f64](1.0f64 + z) }
    if kernel == 3usize { ret 1.0f64 - 1.0f64 / (1.0f64 + z) }
    ret 1.0f64 - 1.0f64 / ((1.0f64 + z) * (1.0f64 + z))
}

// the kernel of the squared distances between every pair of rows, an N by N matrix
fn lookup(a: *mem.Arena, data: []const f64, nn: usize, d: usize, kernel: usize) -> ([]f64, err) {
    let (l, e) = mem.alloc[f64](a, nn * nn)
    if e != ok { ret (l, e) }
    var i = 0usize
    while i < nn {
        var j = 0usize
        while j < nn {
            var s = 0.0f64
            var k = 0usize
            while k < d {
                let df = data[i * d + k] - data[j * d + k]
                s += df * df
                k += 1usize
            }
            l[i * nn + j] = phi(kernel, s)
            j += 1usize
        }
        i += 1usize
    }
    ret (l, ok)
}

// .cramer.statistic for the row indices idx (0-based; the first m are the x sample)
fn statistic(l: []const f64, nn: usize, idx: []const usize, m: usize, n: usize) -> f64 {
    var sxy = 0.0f64
    var sxx = 0.0f64
    var syy = 0.0f64
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < n {
            sxy += l[idx[i] * nn + idx[m + j]]
            j += 1usize
        }
        j = 0usize
        while j < m {
            sxx += l[idx[i] * nn + idx[j]]
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            syy += l[idx[m + i] * nn + idx[m + j]]
            j += 1usize
        }
        i += 1usize
    }
    let mf = f64(m)
    let nf = f64(n)
    ret mf * nf / (mf + nf) * (2.0f64 * sxy / (mf * nf) - sxx / (mf * mf) - syy / (nf * nf))
}

// cramer.test(sim = "ordinary" (perm false) or "permutation", replicates r) after set.seed(seed): (statistic, p.value, crit.value at conf.level)
fn bootstrap(a: *mem.Arena, data: []const f64, m: usize, n: usize, d: usize, kernel: usize, reps: usize, seed: i64, perm: bool, conf: f64) -> (f64, f64, f64, err) {
    let nan = 0.0f64 / 0.0f64
    let nn = m + n
    let (l, e0) = lookup(a, data, nn, d, kernel)
    if e0 != ok { ret (nan, nan, nan, e0) }
    let (idx, e1) = mem.alloc[usize](a, nn)
    let (ts, e2) = mem.alloc[f64](a, reps)
    if e1 != ok { ret (nan, nan, nan, e1) }
    if e2 != ok { ret (nan, nan, nan, e2) }
    var i = 0usize
    while i < nn {
        idx[i] = i
        i += 1usize
    }
    let t0 = statistic(l, nn, idx, m, n)
    var g: rng.Rng = zero
    rng.seed(&g, seed)
    var all: []i64 = zero
    if !perm {
        let (s, es) = rng.sample_int(a, &g, i64(nn), i64(nn * reps), true)
        if es != ok { ret (nan, nan, nan, es) }
        all = s
    }
    var r = 0usize
    while r < reps {
        if perm {
            let (s, es) = rng.sample_int(a, &g, i64(nn), i64(nn), false)
            if es != ok { ret (nan, nan, nan, es) }
            i = 0usize
            while i < nn {
                idx[i] = usize(s[i]) - 1usize
                i += 1usize
            }
        } else {
            i = 0usize
            while i < nn {
                idx[i] = usize(all[i * reps + r]) - 1usize
                i += 1usize
            }
        }
        ts[r] = statistic(l, nn, idx, m, n)
        r += 1usize
    }
    var less = 0usize
    var eq = 0usize
    r = 0usize
    while r < reps {
        if ts[r] < t0 { less += 1usize }
        if ts[r] == t0 { eq += 1usize }
        r += 1usize
    }
    let rank = f64(less) + f64(eq + 1usize + 1usize) / 2.0f64 - 0.5f64 * 0.0f64
    // average rank of t0 among the reps + 1 values: less + (eq + 1 + 1) / 2
    let pv = 1.0f64 - rank / f64(reps + 1usize)
    // sort ts ascending, take element round(conf * reps)
    i = 1usize
    while i < reps {
        let v = ts[i]
        var j = i
        while j > 0usize && ts[j - 1usize] > v {
            ts[j] = ts[j - 1usize]
            j -= 1usize
        }
        ts[j] = v
        i += 1usize
    }
    let cr = conf * f64(reps)
    var k = math.floor[f64](cr + 0.5f64)
    if cr + 0.5f64 == k && k - 2.0f64 * math.floor[f64](k / 2.0f64) != 0.0f64 { k = k - 1.0f64 }
    ret (t0, pv, ts[usize(k) - 1usize], ok)
}

// all eigenvalues of the symmetric p by p matrix m (cyclic Jacobi, m destroyed) into vals, descending
fn eigenvalues(m: []f64, p: usize, vals: []f64) {
    var sweep = 0usize
    while sweep < 100usize {
        var off = 0.0f64
        var i = 0usize
        while i < p {
            var j = i + 1usize
            while j < p {
                off += m[i * p + j] * m[i * p + j]
                j += 1usize
            }
            i += 1usize
        }
        if off < 1.0e-30f64 { break }
        i = 0usize
        while i < p {
            var j = i + 1usize
            while j < p {
                let apq = m[i * p + j]
                if apq != 0.0f64 {
                    let th = (m[j * p + j] - m[i * p + i]) / (2.0f64 * apq)
                    var t = 1.0f64 / (math.abs[f64](th) + math.sqrt[f64](th * th + 1.0f64))
                    if th < 0.0f64 { t = 0.0f64 - t }
                    let cs = 1.0f64 / math.sqrt[f64](t * t + 1.0f64)
                    let sn = t * cs
                    var k = 0usize
                    while k < p {
                        let akp = m[k * p + i]
                        let akq = m[k * p + j]
                        m[k * p + i] = cs * akp - sn * akq
                        m[k * p + j] = sn * akp + cs * akq
                        k += 1usize
                    }
                    k = 0usize
                    while k < p {
                        let apk = m[i * p + k]
                        let aqk = m[j * p + k]
                        m[i * p + k] = cs * apk - sn * aqk
                        m[j * p + k] = sn * apk + cs * aqk
                        k += 1usize
                    }
                }
                j += 1usize
            }
            i += 1usize
        }
        sweep += 1usize
    }
    var i2 = 0usize
    while i2 < p {
        vals[i2] = m[i2 * p + i2]
        i2 += 1usize
    }
    i2 = 1usize
    while i2 < p {
        let v = vals[i2]
        var j = i2
        while j > 0usize && vals[j - 1usize] < v {
            vals[j] = vals[j - 1usize]
            j -= 1usize
        }
        vals[j] = v
        i2 += 1usize
    }
}

// cramer.test(sim = "eigenvalue", maxM = 2^14, K = 160): (statistic, p.value, crit.value)
fn eigen_test(a: *mem.Arena, data: []const f64, m: usize, n: usize, d: usize, kernel: usize, conf: f64) -> (f64, f64, f64, err) {
    let nan = 0.0f64 / 0.0f64
    let nn = m + n
    let nf = f64(nn)
    let (l, e0) = lookup(a, data, nn, d, kernel)
    if e0 != ok { ret (nan, nan, nan, e0) }
    let (idx, e1) = mem.alloc[usize](a, nn)
    let (bm, e2) = mem.alloc[f64](a, nn * nn)
    let (c1, e3) = mem.alloc[f64](a, nn)
    let (lam, e4) = mem.alloc[f64](a, nn)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (nan, nan, nan, e1) }
    var i = 0usize
    while i < nn {
        idx[i] = i
        i += 1usize
    }
    let stat = statistic(l, nn, idx, m, n)
    var c2 = 0.0f64
    i = 0usize
    while i < nn {
        var s = 0.0f64
        var j = 0usize
        while j < nn {
            s += l[i * nn + j]
            j += 1usize
        }
        c1[i] = s / nf
        c2 += s
        i += 1usize
    }
    c2 = c2 / (nf * nf)
    i = 0usize
    while i < nn {
        var j = 0usize
        while j < nn {
            bm[i * nn + j] = (c1[i] + c1[j] - c2 - l[i * nn + j]) / nf
            j += 1usize
        }
        i += 1usize
    }
    eigenvalues(bm, nn, lam)
    var sl = 0.0f64
    i = 0usize
    while i < nn {
        sl += lam[i]
        i += 1usize
    }
    let pi = 3.141592653589793238462643383279f64
    let kk = 160.0f64
    var mm = 2048usize
    while 150.0f64 * pi * f64(mm) / (kk * kk) < 2.0f64 * sl + lam[0usize] { mm = mm * 2usize }
    if mm > 16384usize { mm = 16384usize }
    let mf = f64(mm)
    let (re, e5) = mem.alloc[f64](a, mm)
    let (im, e6) = mem.alloc[f64](a, mm)
    let (xs, e7) = mem.alloc[f64](a, mm)
    if e5 != ok || e6 != ok || e7 != ok { ret (nan, nan, nan, e5) }
    var j = 0usize
    while j < mm {
        var t = f64(j) * kk / mf
        if j == 0usize { t = 1.0f64 }
        xs[j] = f64(j) * 2.0f64 * pi / kk
        var sre = 0.0f64
        var sim = 0.0f64
        i = 0usize
        while i < nn {
            let z = 2.0f64 * lam[i] * t
            sre = sre - 0.25f64 * math.log[f64](1.0f64 + z * z)
            sim = sim + 0.5f64 * math.atan[f64](z)
            i += 1usize
        }
        let mag = math.exp[f64](sre)
        re[j] = mag * math.cos[f64](sim) / t
        im[j] = mag * math.sin[f64](sim) / t
        if j == 0usize {
            re[0usize] = 0.0f64
            im[0usize] = sl
        }
        j += 1usize
    }
    if fft.fft(re, im) != ok { ret (nan, nan, nan, ok) }
    let (fx, e8) = mem.alloc[f64](a, mm)
    if e8 != ok { ret (nan, nan, nan, e8) }
    j = 0usize
    while j < mm {
        fx[j] = 0.5f64 - kk / (mf * pi) * im[j] + kk / (2.0f64 * mf * pi) * (sl + xs[j])
        j += 1usize
    }
    var xi = 0usize
    var bd = math.abs[f64](fx[0usize] - conf)
    j = 1usize
    while j < mm / 2usize {
        let df = math.abs[f64](fx[j] - conf)
        if df < bd {
            bd = df
            xi = j
        }
        j += 1usize
    }
    if fx[xi] > conf && xi > 0usize { xi = xi - 1usize }
    let crit = xs[xi] + (conf - fx[xi]) * (xs[xi + 1usize] - xs[xi]) / (fx[xi + 1usize] - fx[xi])
    var wi = 0usize
    var wd = math.abs[f64](xs[0usize] - stat)
    j = 1usize
    while j < 3usize * mm / 4usize {
        let df = math.abs[f64](xs[j] - stat)
        if df < wd {
            wd = df
            wi = j
        }
        j += 1usize
    }
    ret (stat, 1.0f64 - fx[wi], crit, ok)
}

// just the statistic of the data as given (x rows then y rows)
fn stat_only(a: *mem.Arena, data: []const f64, m: usize, n: usize, d: usize, kernel: usize) -> (f64, err) {
    let nn = m + n
    let (l, e0) = lookup(a, data, nn, d, kernel)
    if e0 != ok { ret (0.0f64 / 0.0f64, e0) }
    let (idx, e1) = mem.alloc[usize](a, nn)
    if e1 != ok { ret (0.0f64 / 0.0f64, e1) }
    var i = 0usize
    while i < nn {
        idx[i] = i
        i += 1usize
    }
    ret (statistic(l, nn, idx, m, n), ok)
}
