// R caTools running-window statistics with the package's default end rules (the window shrinks at both ends): runmean, runmin, runmax, runsd and runquantile (type 7), for an odd window.
//
// Not here: even windows, the other end rules and alignments, the other quantile types, runmad, colAUC and the other caTools functions.

use e.math
use e.mem

// the statistic of the window of x around position i (0-based) with half-width h, clipped to the data: stat 0 mean, 1 min, 2 max, 3 sd, 4 quantile type 7 at p; tmp holds 2h + 1 values
fn window_stat(x: []const f64, i: usize, h: usize, stat: usize, p: f64, tmp: []f64) -> f64 {
    var lo = 0usize
    if i > h { lo = i - h }
    var hi = i + h
    if hi >= x.len { hi = x.len - 1usize }
    let m = hi - lo + 1usize
    var k = 0usize
    while k < m {
        tmp[k] = x[lo + k]
        k += 1usize
    }
    if stat == 0usize || stat == 3usize {
        var s = 0.0f64
        k = 0usize
        while k < m {
            s += tmp[k]
            k += 1usize
        }
        let mean = s / f64(m)
        if stat == 0usize { ret mean }
        var ss = 0.0f64
        k = 0usize
        while k < m {
            ss += (tmp[k] - mean) * (tmp[k] - mean)
            k += 1usize
        }
        ret math.sqrt[f64](ss / f64(m - 1usize))
    }
    var a = 1usize
    while a < m {
        let t = tmp[a]
        var b = a
        while b > 0usize && tmp[b - 1usize] > t {
            tmp[b] = tmp[b - 1usize]
            b -= 1usize
        }
        tmp[b] = t
        a += 1usize
    }
    if stat == 1usize { ret tmp[0usize] }
    if stat == 2usize { ret tmp[m - 1usize] }
    let fuzz = 4.0f64 * 2.220446049250313e-16f64
    let idx = f64(m - 1usize) * p
    let fl = math.floor[f64](idx + fuzz)
    var fr = idx - fl
    if math.abs[f64](fr) < fuzz { fr = 0.0f64 }
    let l = usize(fl)
    if fr == 0.0f64 || l + 1usize >= m { ret tmp[l] }
    ret (1.0f64 - fr) * tmp[l] + fr * tmp[l + 1usize]
}
