// R spdep moran.test and geary.test for a dense weights matrix (n by n, row-major, not necessarily symmetric): the statistics, their expectations and the variances under normality and randomisation.
//
// Not here: neighbour construction, listw objects, Monte Carlo and Moran-I on residuals, local indicators, Getis-Ord, spatial regression.

use e.math

// out: Moran I, E[I], var normality, var randomisation, Geary C, E[C] (1), var normality, var randomisation
fn autocorr(x: []const f64, w: []const f64, n: usize, out: []f64) {
    let nf = f64(n)
    var mean = 0.0f64
    var i = 0usize
    while i < n {
        mean += x[i]
        i += 1usize
    }
    mean = mean / nf
    var s2 = 0.0f64
    var s4 = 0.0f64
    i = 0usize
    while i < n {
        let z = x[i] - mean
        s2 += z * z
        s4 += z * z * z * z
        i += 1usize
    }
    var s0 = 0.0f64
    var s1 = 0.0f64
    var s2w = 0.0f64
    var cross = 0.0f64
    var diff = 0.0f64
    i = 0usize
    while i < n {
        var ri = 0.0f64
        var ci = 0.0f64
        var j = 0usize
        while j < n {
            let wij = w[i * n + j]
            let wji = w[j * n + i]
            s0 += wij
            s1 += (wij + wji) * (wij + wji) / 2.0f64
            ri += wij
            ci += wji
            cross += wij * (x[i] - mean) * (x[j] - mean)
            diff += wij * (x[i] - x[j]) * (x[i] - x[j])
            j += 1usize
        }
        s2w += (ri + ci) * (ri + ci)
        i += 1usize
    }
    let k = nf * s4 / (s2 * s2)
    let e = 0.0f64 - 1.0f64 / (nf - 1.0f64)
    out[0usize] = nf / s0 * cross / s2
    out[1usize] = e
    out[2usize] = (nf * nf * s1 - nf * s2w + 3.0f64 * s0 * s0) / (s0 * s0 * (nf * nf - 1.0f64)) - e * e
    let num = nf * ((nf * nf - 3.0f64 * nf + 3.0f64) * s1 - nf * s2w + 3.0f64 * s0 * s0) - k * (nf * (nf - 1.0f64) * s1 - 2.0f64 * nf * s2w + 6.0f64 * s0 * s0)
    out[3usize] = num / ((nf - 1.0f64) * (nf - 2.0f64) * (nf - 3.0f64) * s0 * s0) - e * e
    out[4usize] = (nf - 1.0f64) * diff / (2.0f64 * s0 * s2)
    out[5usize] = 1.0f64
    out[6usize] = ((2.0f64 * s1 + s2w) * (nf - 1.0f64) - 4.0f64 * s0 * s0) / (2.0f64 * (nf + 1.0f64) * s0 * s0)
    let gn = (nf - 1.0f64) * s1 * (nf * nf - 3.0f64 * nf + 3.0f64 - (nf - 1.0f64) * k) - 0.25f64 * (nf - 1.0f64) * s2w * (nf * nf + 3.0f64 * nf - 6.0f64 - (nf * nf - nf + 2.0f64) * k) + s0 * s0 * (nf * nf - 3.0f64 - (nf - 1.0f64) * (nf - 1.0f64) * k)
    out[7usize] = gn / (nf * (nf - 2.0f64) * (nf - 3.0f64) * s0 * s0)
}
