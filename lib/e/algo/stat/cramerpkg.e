// R cramer's cramer.test: the Cramer two-sample statistic with the five built-in kernels, the critical value and p-value by ordinary and permutation bootstrap (boot's index arrays under R's generator) and by the eigenvalue method (the spectrum of the centred kernel matrix and a Gurland inversion by FFT).
//
// Not here: user-defined kernels, the hypothesis distribution and eigenvectors, the print method.

use e.algo.linalg.lapack_syevr as lapack
use e.algo.rand.r as rng
use e.math
use e.math.fft as fft
use e.mem

// the kernel of cramer's phiCramer (0), phiBahr (1), phiLog (2), phiFracA (3), phiFracB (4)
fn kernel(k: usize, z: f64) -> f64 {
    if k == 0usize { ret math.sqrt[f64](z) / 2.0f64 }
    if k == 1usize { ret 1.0f64 - math.exp[f64](0.0f64 - z / 2.0f64) }
    if k == 2usize { ret math.log[f64](1.0f64 + z) }
    if k == 3usize { ret 1.0f64 - 1.0f64 / (1.0f64 + z) }
    ret 1.0f64 - 1.0f64 / ((1.0f64 + z) * (1.0f64 + z))
}

// the N by N matrix (column-major, symmetric) of kernel(squared distance) between the N = m + n observations (row-major, d columns)
fn lookup(data: []const f64, nn: usize, d: usize, k: usize, out: []f64) {
    var i = 0usize
    while i < nn {
        var j = 0usize
        while j < nn {
            var s = 0.0f64
            var c = 0usize
            while c < d {
                let df = data[i * d + c] - data[j * d + c]
                s += df * df
                c += 1usize
            }
            out[j * nn + i] = kernel(k, s)
            j += 1usize
        }
        i += 1usize
    }
}

// .cramer.statistic for the index vector idx (the first m are the x sample, the next n the y sample, 1-based as R)
fn statistic(lk: []const f64, nn: usize, idx: []const usize, m: usize, n: usize) -> f64 {
    var xy = 0.0f64
    var xx = 0.0f64
    var yy = 0.0f64
    var j = 0usize
    while j < n {
        var i = 0usize
        while i < m {
            xy += lk[(idx[m + j] - 1usize) * nn + idx[i] - 1usize]
            i += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < m {
        var i = 0usize
        while i < m {
            xx += lk[(idx[j] - 1usize) * nn + idx[i] - 1usize]
            i += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < n {
        var i = 0usize
        while i < n {
            yy += lk[(idx[m + j] - 1usize) * nn + idx[m + i] - 1usize]
            i += 1usize
        }
        j += 1usize
    }
    let mf = f64(m)
    let nf = f64(n)
    ret mf * nf / (mf + nf) * (2.0f64 * xy / (mf * nf) - xx / (mf * mf) - yy / (nf * nf))
}

// cramer.test(sim = "ordinary" or "permutation", replicates = reps) after set.seed(seed): out gets (statistic, crit.value, p.value)
fn bootstrap(a: *mem.Arena, lk: []const f64, nn: usize, m: usize, n: usize, conf: f64, reps: usize, perm: bool, seed: i64, out: []f64) -> err {
    var rg: rng.Rng = zero
    rng.seed(&rg, seed)
    let (idx, e1) = mem.alloc[usize](a, nn)
    let (ts, e2) = mem.alloc[f64](a, reps)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    var i = 0usize
    while i < nn {
        idx[i] = i + 1usize
        i += 1usize
    }
    let t0 = statistic(lk, nn, idx, m, n)
    if !perm {
        // sample.int(n, n * R, replace = TRUE) filled column-major into an R by n matrix: replicate r takes elements r, r + R, ...
        let (draw, e3) = rng.sample_int(a, &rg, i64(nn), i64(nn * reps), true)
        if e3 != ok { ret e3 }
        var r = 0usize
        while r < reps {
            i = 0usize
            while i < nn {
                idx[i] = usize(draw[i * reps + r])
                i += 1usize
            }
            ts[r] = statistic(lk, nn, idx, m, n)
            r += 1usize
        }
    } else {
        var r = 0usize
        while r < reps {
            let (p, e4) = rng.sample_int(a, &rg, i64(nn), i64(nn), false)
            if e4 != ok { ret e4 }
            i = 0usize
            while i < nn {
                idx[i] = usize(p[i])
                i += 1usize
            }
            ts[r] = statistic(lk, nn, idx, m, n)
            r += 1usize
        }
    }
    // rank(c(t0, t))[1] with average ties
    var below = 0.0f64
    var tie = 0.0f64
    i = 0usize
    while i < reps {
        if ts[i] < t0 { below += 1.0f64 }
        if ts[i] == t0 { tie += 1.0f64 }
        i += 1usize
    }
    let rank1 = below + (tie + 1.0f64 + 1.0f64) / 2.0f64
    i = 1usize
    while i < reps {
        let t = ts[i]
        var j = i
        while j > 0usize && ts[j - 1usize] > t {
            ts[j] = ts[j - 1usize]
            j -= 1usize
        }
        ts[j] = t
        i += 1usize
    }
    // round half to even of conf * R, then the 1-based order statistic
    let cr = conf * f64(reps)
    var rr = math.floor[f64](cr + 0.5f64)
    if cr + 0.5f64 == rr && rr - 2.0f64 * math.floor[f64](rr / 2.0f64) != 0.0f64 { rr = rr - 1.0f64 }
    out[0usize] = t0
    out[1usize] = ts[usize(rr) - 1usize]
    out[2usize] = 1.0f64 - rank1 / f64(reps + 1usize)
    ret ok
}

// cramer.test(sim = "eigenvalue", maxM = 2^14, K = 160): out gets (statistic, crit.value, p.value)
fn eigenvalue(a: *mem.Arena, lk: []const f64, nn: usize, m: usize, n: usize, conf: f64, out: []f64) -> err {
    let pi = 3.141592653589793238462643383279f64
    let kk = 160.0f64
    let (idx, e1) = mem.alloc[usize](a, nn)
    let (c1, e2) = mem.alloc[f64](a, nn)
    let (bm, e3) = mem.alloc[f64](a, nn * nn)
    let (w, e4) = mem.alloc[f64](a, nn)
    let (z, e5) = mem.alloc[f64](a, nn * nn)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    var i = 0usize
    while i < nn {
        idx[i] = i + 1usize
        i += 1usize
    }
    out[0usize] = statistic(lk, nn, idx, m, n)
    var c2 = 0.0f64
    i = 0usize
    while i < nn {
        var s = 0.0f64
        var j = 0usize
        while j < nn {
            s += lk[j * nn + i]
            j += 1usize
        }
        c1[i] = s
        i += 1usize
    }
    i = 0usize
    while i < nn {
        c2 += c1[i]
        c1[i] = c1[i] / f64(nn)
        i += 1usize
    }
    c2 = c2 / (f64(nn) * f64(nn))
    i = 0usize
    while i < nn {
        var j = 0usize
        while j < nn {
            bm[j * nn + i] = (c1[i] + c1[j] - c2 - lk[j * nn + i]) / f64(nn)
            j += 1usize
        }
        i += 1usize
    }
    let le = lapack.dsyevr_all(a, bm, nn, w, z)
    if le != ok { ret le }
    // w ascending: the R order is descending, so lambda1 is the last
    var sum = 0.0f64
    i = 0usize
    while i < nn {
        sum += w[i]
        i += 1usize
    }
    let lam1 = w[nn - 1usize]
    var mm = 2048usize
    while 150.0f64 * pi * f64(mm) / (kk * kk) < 2.0f64 * sum + lam1 { mm *= 2usize }
    if mm > 16384usize { mm = 16384usize }
    let (hr, e6) = mem.alloc[f64](a, mm)
    let (hi, e7) = mem.alloc[f64](a, mm)
    let (xs, e8) = mem.alloc[f64](a, mm)
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    var q = 0usize
    while q < mm {
        var t = f64(q) * kk / f64(mm)
        if q == 0usize { t = 1.0f64 }
        xs[q] = f64(q) * 2.0f64 * pi / kk
        var re = 0.0f64
        var im = 0.0f64
        var l = 0usize
        while l < nn {
            let u = 2.0f64 * w[l] * t
            re += 0.0f64 - 0.25f64 * math.log[f64](1.0f64 + u * u)
            im += 0.5f64 * math.atan[f64](u)
            l += 1usize
        }
        let mag = math.exp[f64](re) / t
        hr[q] = mag * math.cos[f64](im)
        hi[q] = mag * math.sin[f64](im)
        q += 1usize
    }
    hr[0usize] = 0.0f64
    hi[0usize] = sum
    let fe = fft.fft(hr, hi)
    if fe != ok { ret fe }
    let (fx, e9) = mem.alloc[f64](a, mm)
    if e9 != ok { ret e9 }
    q = 0usize
    while q < mm {
        fx[q] = 0.5f64 - kk / (f64(mm) * pi) * hi[q] + kk / (2.0f64 * f64(mm) * pi) * (sum + xs[q])
        q += 1usize
    }
    var xi = 0usize
    var best = math.abs[f64](fx[0usize] - conf)
    q = 1usize
    while q < mm / 2usize {
        let dv = math.abs[f64](fx[q] - conf)
        if dv < best {
            best = dv
            xi = q
        }
        q += 1usize
    }
    if fx[xi] > conf && xi > 0usize { xi = xi - 1usize }
    out[1usize] = xs[xi] + (conf - fx[xi]) * (xs[xi + 1usize] - xs[xi]) / (fx[xi + 1usize] - fx[xi])
    var pi2 = 0usize
    var pb = math.abs[f64](xs[0usize] - out[0usize])
    q = 1usize
    while q < 3usize * mm / 4usize {
        let dv = math.abs[f64](xs[q] - out[0usize])
        if dv < pb {
            pb = dv
            pi2 = q
        }
        q += 1usize
    }
    out[2usize] = 1.0f64 - fx[pi2]
    ret ok
}
