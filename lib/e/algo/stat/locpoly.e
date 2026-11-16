// R KernSmooth::locpoly with a scalar bandwidth and the normal kernel: the data are linearly binned onto an equally
// spaced grid (rlbin) and a local polynomial of the given degree is fitted at every grid point by weighted least
// squares on the binned counts within 4 bandwidths; the answer is `drv!` times the drv-th coefficient.
//
// Not here: a variable bandwidth (the array form), the other kernels, binned input, dpill and the other selectors.

use e.algo.stat.quantreg as qr
use e.math
use e.mem

// rlbin(x, y, gpoints, truncate = TRUE): linear binning of the counts and of y
fn rlbin(x: []const f64, y: []const f64, a: f64, b: f64, m: usize, truncate: bool, xc: []f64, yc: []f64) {
    var k = 0usize
    while k < m {
        xc[k] = 0.0f64
        yc[k] = 0.0f64
        k += 1usize
    }
    let delta = (b - a) / f64(m - 1usize)
    var i = 0usize
    while i < x.len {
        let lxi = (x[i] - a) / delta + 1.0f64
        let li = i64(math.floor[f64](lxi))
        let rem = lxi - f64(li)
        if li >= 1i64 && li < i64(m) {
            xc[usize(li) - 1usize] += 1.0f64 - rem
            xc[usize(li)] += rem
            yc[usize(li) - 1usize] += (1.0f64 - rem) * y[i]
            yc[usize(li)] += rem * y[i]
        } else if li == i64(m) && rem == 0.0f64 {
            xc[m - 1usize] += 1.0f64
            yc[m - 1usize] += y[i]
        } else if li < 1i64 && !truncate {
            xc[0usize] += 1.0f64
            yc[0usize] += y[i]
        } else if li >= i64(m) && !truncate {
            xc[m - 1usize] += 1.0f64
            yc[m - 1usize] += y[i]
        }
        i += 1usize
    }
}

// locpoly(x, y, drv, degree, bandwidth, gridsize = m, range.x = c(a, b)); out receives the m fitted values
fn locpoly(a: *mem.Arena, x: []const f64, y: []const f64, drv: usize, degree: usize, h: f64, m: usize, lo: f64, hi: f64, out: []f64) -> err {
    let (xc, e1) = mem.alloc[f64](a, m)
    let (yc, e2) = mem.alloc[f64](a, m)
    let pp = degree + 1usize
    let ppp = 2usize * degree + 1usize
    let (ss, e3) = mem.alloc[f64](a, ppp)
    let (tt, e4) = mem.alloc[f64](a, pp)
    let (sm, e5) = mem.alloc[f64](a, pp * pp)
    let (tv, e6) = mem.alloc[f64](a, pp)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret e1 }
    rlbin(x, y, lo, hi, m, true, xc, yc)
    let delta = (hi - lo) / f64(m - 1usize)
    let ll = i64(math.floor[f64](4.0f64 * h / delta))
    if ll == 0i64 { ret Singular }
    var fact = 1.0f64
    var q = 2usize
    while q <= drv {
        fact *= f64(q)
        q += 1usize
    }
    var i = 0usize
    while i < m {
        var k = 0usize
        while k < ppp {
            ss[k] = 0.0f64
            k += 1usize
        }
        k = 0usize
        while k < pp {
            tt[k] = 0.0f64
            k += 1usize
        }
        var j = 0i64 - ll
        while j <= ll {
            let idx = i64(i) + j
            if idx >= 0i64 && idx < i64(m) {
                let c = xc[usize(idx)]
                let yv = yc[usize(idx)]
                if c != 0.0f64 || yv != 0.0f64 {
                    let u = delta * f64(j)
                    let fac0 = math.exp[f64](0.0f64 - 0.5f64 * (u / h) * (u / h))
                    var fac = fac0
                    ss[0usize] += c * fac
                    var kk = 1usize
                    while kk < ppp {
                        fac = fac * u
                        ss[kk] += c * fac
                        kk += 1usize
                    }
                    fac = fac0
                    tt[0usize] += yv * fac
                    kk = 1usize
                    while kk < pp {
                        fac = fac * u
                        tt[kk] += yv * fac
                        kk += 1usize
                    }
                }
            }
            j += 1i64
        }
        var r = 0usize
        while r < pp {
            var s = 0usize
            while s < pp {
                sm[r * pp + s] = ss[r + s]
                s += 1usize
            }
            tv[r] = tt[r]
            r += 1usize
        }
        if !qr.solve_dense(sm, tv, pp) { ret Singular }
        out[i] = fact * tv[drv]
        i += 1usize
    }
    ret ok
}

error Singular
