// R coda: the autocorrelations of acf, the Yule-Walker autoregression of ar(aic = TRUE) behind spectrum0.ar, and effectiveSize for one chain.
//
// Not here: the multiple-chain diagnostics (gelman.diag, geweke.diag, heidel.diag, raftery.diag), HPDinterval and cramer.test.

use e.math
use e.mem

// the biased autocovariances c_0 .. c_m of the series about its mean (acf's estimator: divided by n)
fn autocov(x: []const f64, m: usize, c: []f64) {
    let n = x.len
    var mean = 0.0f64
    var i = 0usize
    while i < n {
        mean += x[i]
        i += 1usize
    }
    mean = mean / f64(n)
    var k = 0usize
    while k <= m {
        var s = 0.0f64
        i = 0usize
        while i + k < n {
            s += (x[i] - mean) * (x[i + k] - mean)
            i += 1usize
        }
        c[k] = s / f64(n)
        k += 1usize
    }
}

// acf(x, lag.max = m)$acf[k + 1] for k = 0 .. m into out
fn acf(x: []const f64, m: usize, out: []f64) {
    autocov(x, m, out)
    let c0 = out[0usize]
    var k = 0usize
    while k <= m {
        out[k] = out[k] / c0
        k += 1usize
    }
}

// ar(x, aic = TRUE) by Yule-Walker (demeaned): the selected order, the sum of its coefficients and var.pred; returns the order
fn ar_yw(a: *mem.Arena, x: []const f64) -> (usize, f64, f64, err) {
    let n = x.len
    var om = usize(math.floor[f64](10.0f64 * math.log10[f64](f64(n))))
    if om > n - 1usize { om = n - 1usize }
    let (c, e1) = mem.alloc[f64](a, om + 1usize)
    let (vars, e2) = mem.alloc[f64](a, om + 1usize)
    let (phi, e3) = mem.alloc[f64](a, (om + 1usize) * (om + 1usize))
    if e1 != ok { ret (0usize, 0.0f64, 0.0f64, e1) }
    if e2 != ok { ret (0usize, 0.0f64, 0.0f64, e2) }
    if e3 != ok { ret (0usize, 0.0f64, 0.0f64, e3) }
    autocov(x, om, c)
    vars[0usize] = c[0usize]
    var k = 1usize
    while k <= om {
        var num = c[k]
        var j = 1usize
        while j < k {
            num -= phi[(k - 1usize) * (om + 1usize) + j] * c[k - j]
            j += 1usize
        }
        let pk = num / vars[k - 1usize]
        phi[k * (om + 1usize) + k] = pk
        j = 1usize
        while j < k {
            phi[k * (om + 1usize) + j] = phi[(k - 1usize) * (om + 1usize) + j] - pk * phi[(k - 1usize) * (om + 1usize) + k - j]
            j += 1usize
        }
        vars[k] = vars[k - 1usize] * (1.0f64 - pk * pk)
        k += 1usize
    }
    var best = 0usize
    var bv = f64(n) * math.log[f64](vars[0usize])
    k = 1usize
    while k <= om {
        let v = f64(n) * math.log[f64](vars[k]) + 2.0f64 * f64(k)
        if v < bv {
            bv = v
            best = k
        }
        k += 1usize
    }
    var sum = 0.0f64
    var j = 1usize
    while j <= best {
        sum += phi[best * (om + 1usize) + j]
        j += 1usize
    }
    let vp = vars[best] * f64(n) / f64(n - (best + 1usize))
    ret (best, sum, vp, ok)
}

// effectiveSize(x) for one chain: n var(x) / spectrum0.ar(x)$spec, 0 for a series that is a straight line
fn effective_size(a: *mem.Arena, x: []const f64) -> f64 {
    let n = x.len
    var mean = 0.0f64
    var i = 0usize
    while i < n {
        mean += x[i]
        i += 1usize
    }
    mean = mean / f64(n)
    var ss = 0.0f64
    i = 0usize
    while i < n {
        ss += (x[i] - mean) * (x[i] - mean)
        i += 1usize
    }
    let v = ss / f64(n - 1usize)
    let (ord, sm, vp, e) = ar_yw(a, x)
    if e != ok { ret 0.0f64 / 0.0f64 }
    let spec = vp / ((1.0f64 - sm) * (1.0f64 - sm))
    if spec == 0.0f64 { ret 0.0f64 }
    ret f64(n) * v / spec
}
