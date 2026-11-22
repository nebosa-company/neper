// R kernlab sigest: the 90%, 50% and 10% quantiles of the squared distances of frac * m random pairs of rows (R's sample with replacement, two draws of n indices),
// srange = 1 / those quantiles, and the sigma ksvm takes for an rbf or Laplace kernel without one, mean(srange[c(1, 3)]). x is row-major, m by nf; with scaled the columns are
// first scaled by R's scale(), as sigest does, and ksvm itself passes scaled = FALSE on its own (already scaled) data.

use e.algo.rand.r as rr
use e.algo.stat.armld as ld
use e.algo.stat.kernlabclass as cl
use e.math
use e.mem

error Fail

// type 7 quantile of the sorted values v (count c) at probability p, R's (1 - h) * x[lo] + h * x[hi]
fn quant7(v: []const f64, c: usize, p: f64) -> f64 {
    let idx = 1.0f64 + f64(c - 1usize) * p
    let lo = math.floor[f64](idx)
    let hi = math.ceil[f64](idx)
    let xl = v[usize(lo) - 1usize]
    let xh = v[usize(hi) - 1usize]
    if idx > lo && xh != xl {
        let h = idx - lo
        ret (1.0f64 - h) * xl + h * xh
    }
    ret xl
}

// srange gets the three values 1 / q90, 1 / q50, 1 / q10
fn sigest(a: *mem.Arena, g: *rr.Rng, x: []const f64, m: usize, nf: usize, frac: f64, scaled: bool, srange: []f64) -> err {
    let (xs, e1) = mem.alloc[f64](a, m * nf)
    let (cen, e2) = mem.alloc[f64](a, nf)
    let (scl, e3) = mem.alloc[f64](a, nf)
    if e1 != ok || e2 != ok || e3 != ok { ret Fail }
    var i = 0usize
    while i < m * nf {
        xs[i] = x[i]
        i += 1usize
    }
    if scaled {
        let e = cl.scale_cols(a, xs, m, nf, cen, scl)
        if e != ok { ret e }
    }
    let nn = usize(math.floor[f64](frac * f64(m)))
    let (ix1, e4) = rr.sample_int(a, g, i64(m), i64(nn), true)
    let (ix2, e5) = rr.sample_int(a, g, i64(m), i64(nn), true)
    let (dist, e6) = mem.alloc[f64](a, nn)
    let (sq, e7) = mem.alloc[f64](a, nf)
    if e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret Fail }
    var c = 0usize
    i = 0usize
    while i < nn {
        var k = 0usize
        while k < nf {
            let d = xs[(usize(ix1[i]) - 1usize) * nf + k] - xs[(usize(ix2[i]) - 1usize) * nf + k]
            sq[k] = d * d
            k += 1usize
        }
        let s = ld.sum_ld(sq[0usize..nf])
        if s != 0.0f64 {
            dist[c] = s
            c += 1usize
        }
        i += 1usize
    }
    if c == 0usize { ret Fail }
    // insertion sort of the nonzero distances
    i = 1usize
    while i < c {
        let v = dist[i]
        var j = i
        while j > 0usize && dist[j - 1usize] > v {
            dist[j] = dist[j - 1usize]
            j -= 1usize
        }
        dist[j] = v
        i += 1usize
    }
    srange[0usize] = 1.0f64 / quant7(dist, c, 0.9f64)
    srange[1usize] = 1.0f64 / quant7(dist, c, 0.5f64)
    srange[2usize] = 1.0f64 / quant7(dist, c, 0.1f64)
    ret ok
}

// the sigma of ksvm(x, y, kernel = "rbfdot") on data x that ksvm has already scaled: mean(sigest(x, scaled = FALSE)[c(1, 3)])
fn auto_sigma(a: *mem.Arena, g: *rr.Rng, x: []const f64, m: usize, nf: usize) -> (f64, err) {
    var sr: [3]f64 = zero
    let e = sigest(a, g, x, m, nf, 0.5f64, false, sr[0usize..3usize])
    if e != ok { ret (0.0f64, e) }
    ret ((sr[0usize] + sr[2usize]) / 2.0f64, ok)
}
