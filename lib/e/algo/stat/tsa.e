// R TSA: the raw periodogram of a series as TSA::periodogram gives it: the mean is removed, the series is padded with zeros to the next
// length N that has only the factors 2, 3 and 5 (stats::nextn, as spec.pgram does), and the value at the frequency j / N, j = 1 .. floor(N / 2),
// is 2 |F_j|^2 / n for the original length n, halved at the Nyquist frequency 1/2.
//
// Not here: armasubsets, McLeod.Li.test, detectAO and detectIO, arimax, the cumulative periodogram, eacf and the diagnostics.

use e.math
use e.math.nmath as nm
use e.mem

// the smallest N >= n whose prime factors are only 2, 3 and 5
fn nextn(n: usize) -> usize {
    var m = n
    while true {
        var r = m
        while r % 2usize == 0usize { r = r / 2usize }
        while r % 3usize == 0usize { r = r / 3usize }
        while r % 5usize == 0usize { r = r / 5usize }
        if r == 1usize { ret m }
        m += 1usize
    }
    ret m
}

// out needs floor(nextn(n) / 2) entries; the count written is returned
fn periodogram(y: []const f64, out: []f64) -> usize {
    let n = y.len
    let big = nextn(n)
    var m = 0.0f64
    var i = 0usize
    while i < n {
        m += y[i]
        i += 1usize
    }
    m = m / f64(n)
    let h = big / 2usize
    var j = 1usize
    while j <= h {
        var re = 0.0f64
        var im = 0.0f64
        i = 0usize
        while i < n {
            let ang = 2.0f64 * 3.141592653589793238462643383279f64 * f64(j) * f64(i) / f64(big)
            re += (y[i] - m) * math.cos[f64](ang)
            im -= (y[i] - m) * math.sin[f64](ang)
            i += 1usize
        }
        var v = 2.0f64 * (re * re + im * im) / f64(n)
        // the package halves the entry whose frequency equals 0.5 exactly; the frequency is built as seq.int(1 / N, by = 1 / N)
        let freq = 1.0f64 / f64(big) + f64(j - 1usize) * (1.0f64 / f64(big))
        if freq == 0.5f64 { v = v / 2.0f64 }
        out[j - 1usize] = v
        j += 1usize
    }
    ret h
}

// the autocorrelation of x at lags 0 .. lag (R's acf: the mean removed, divided by n at every lag)
fn acf_upto(x: []const f64, lag: usize, out: []f64) {
    let n = x.len
    var m = 0.0f64
    var i = 0usize
    while i < n {
        m += x[i]
        i += 1usize
    }
    m = m / f64(n)
    var k = 0usize
    while k <= lag {
        var s = 0.0f64
        i = 0usize
        while i + k < n {
            s += (x[i + k] - m) * (x[i] - m)
            i += 1usize
        }
        out[k] = s / f64(n)
        k += 1usize
    }
    k = 1usize
    while k <= lag {
        out[k] = out[k] / out[0usize]
        k += 1usize
    }
    out[0usize] = 1.0f64
}

// McLeod.Li.test(y = x): the Ljung-Box p value of the squared series at lags 1 .. gof, from the autocorrelations at lags 1 .. lag (TSA masks acf with
// a version that drops lag 0), each divided by n - k
fn mcleod_li(a: *mem.Arena, x: []const f64, gof: usize, out: []f64) -> err {
    let n = x.len
    let (sq, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < n {
        sq[i] = x[i] * x[i]
        i += 1usize
    }
    let (r, e2) = mem.alloc[f64](a, gof + 1usize)
    if e2 != ok { ret e2 }
    var lag = 1usize
    while lag <= gof {
        acf_upto(sq, lag, r)
        var s = 0.0f64
        var k = 1usize
        while k <= lag {
            s += r[k] * r[k] / (f64(n) - f64(k))
            k += 1usize
        }
        let stat = f64(n) * (f64(n) + 2.0f64) * s
        out[lag - 1usize] = 1.0f64 - nm.pchisq(stat, f64(lag), true, false)
        lag += 1usize
    }
    ret ok
}
