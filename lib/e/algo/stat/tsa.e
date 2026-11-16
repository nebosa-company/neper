// R TSA: the raw periodogram of a series as TSA::periodogram gives it: the mean is removed, the series is padded with zeros to the next
// length N that has only the factors 2, 3 and 5 (stats::nextn, as spec.pgram does), and the value at the frequency j / N, j = 1 .. floor(N / 2),
// is 2 |F_j|^2 / n for the original length n, halved at the Nyquist frequency 1/2.
//
// Not here: armasubsets, McLeod.Li.test, detectAO and detectIO, arimax, the cumulative periodogram, eacf and the diagnostics.

use e.math

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
