// R's e1071 helpers that are plain arithmetic: `skewness` and `kurtosis` (types 1 to 3, as moments.type
// of the package defines them) and `countpattern` (the counts of the 2^nvar 0/1 patterns of the columns).
//
// Also rwiener and cmeans (euclidean, given centres, on the R stream). Not here: cshell, the random centre choice,
// ufcl, the manhattan distance, bclust (see classint) and matchClasses.

use e.algo.rand.r as rr
use e.math
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn centred_sums(x: []const f64) -> (f64, f64, f64, f64) {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += x[i]
        i += 1usize
    }
    let m = s / f64(x.len)
    var m2 = 0.0f64
    var m3 = 0.0f64
    var m4 = 0.0f64
    i = 0usize
    while i < x.len {
        let d = x[i] - m
        m2 += d * d
        m3 += d * d * d
        m4 += d * d * d * d
        i += 1usize
    }
    ret (m, m2, m3, m4)
}

// skewness type 1, 2 or 3; NaN where R stops (type 2 below three observations)
fn skewness(x: []const f64, qtype: u8) -> f64 {
    let n = f64(x.len)
    let (m, m2, m3, m4) = centred_sums(x)
    var y = math.sqrt[f64](n) * m3 / math.pow[f64](m2, 1.5f64)
    if qtype == 2u8 {
        if x.len < 3usize { ret nan() }
        y = y * math.sqrt[f64](n * (n - 1.0f64)) / (n - 2.0f64)
    } else if qtype == 3u8 {
        y = y * math.pow[f64](1.0f64 - 1.0f64 / n, 1.5f64)
    }
    ret y
}

fn kurtosis(x: []const f64, qtype: u8) -> f64 {
    let n = f64(x.len)
    let (m, m2, m3, m4) = centred_sums(x)
    let r = n * m4 / (m2 * m2)
    if qtype == 1u8 { ret r - 3.0f64 }
    if qtype == 2u8 {
        if x.len < 4usize { ret nan() }
        ret ((n + 1.0f64) * (r - 3.0f64) + 6.0f64) * (n - 1.0f64) / ((n - 2.0f64) * (n - 3.0f64))
    }
    let f = 1.0f64 - 1.0f64 / n
    ret r * f * f - 3.0f64
}

// countpattern for a 0/1 matrix given row-wise: counts[k] is the number of rows whose bits, first
// column most significant, read k.
fn count_pattern(a: *mem.Arena, rows: []const f64, nrow: usize, nvar: usize) -> ([]f64, err) {
    var size = 1usize
    var v = 0usize
    while v < nvar {
        size *= 2usize
        v += 1usize
    }
    let (out, e) = mem.alloc[f64](a, size)
    if e != ok { ret (out, e) }
    var k = 0usize
    while k < size {
        out[k] = 0.0f64
        k += 1usize
    }
    var r = 0usize
    while r < nrow {
        var code = 0usize
        var c = 0usize
        while c < nvar {
            code = code * 2usize
            if rows[r * nvar + c] != 0.0f64 { code += 1usize }
            c += 1usize
        }
        out[code] += 1.0f64
        r += 1usize
    }
    ret (out, ok)
}

// e1071::rwiener(end, frequency): the cumulative sum of n(0, 1) / sqrt(frequency) draws
fn rwiener(g: *rr.Rng, n: usize, frequency: f64, out: []f64) {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += rr.rnorm(g, 0.0f64, 1.0f64) / math.sqrt[f64](frequency)
        out[i] = s
        i += 1usize
    }
}

// e1071::cmeans(x, centers = <matrix>, method = "cmeans", dist = "euclidean", m): fuzzy c-means of the n by nc
// column-major x from the given k by nc column-major centres, on the rows permuted by sample(n) as the R code does
// (so the floating-point summation order is R's); centres receives the final prototypes, u the n by k memberships in
// the original row order; answers the iteration count (R's iter) and the within error
fn cmeans(a: *mem.Arena, g: *rr.Rng, x0: []const f64, n: usize, nc: usize, centers: []f64, k: usize, w0: []const f64, m: f64, itermax: usize, reltol: f64, u_out: []f64) -> (usize, f64, err) {
    let (perm, pe) = rr.sample_int(a, g, i64(n), i64(n), false)
    if pe != ok { ret (0usize, 0.0f64, pe) }
    let (x, e1) = mem.alloc[f64](a, n * nc)
    let (w, e2) = mem.alloc[f64](a, n)
    let (u, e3) = mem.alloc[f64](a, n * k)
    let (d, e4) = mem.alloc[f64](a, n * k)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (0usize, 0.0f64, e1) }
    var sw = 0.0f64
    var i = 0usize
    while i < n {
        sw += w0[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        let src = usize(perm[i]) - 1usize
        w[i] = w0[src] / sw
        var j = 0usize
        while j < nc {
            x[i + n * j] = x0[src + n * j]
            j += 1usize
        }
        i += 1usize
    }
    let expo = 1.0f64 / (m - 1.0f64)
    cm_dist(x, centers, n, nc, k, d)
    cm_memb(d, n, k, expo, u)
    var old_value = cm_err(u, d, w, n, k, m)
    var new_value = old_value
    var iter = 0usize
    while iter < itermax {
        iter += 1usize
        // prototypes: weighted means of the rows with weights w u^m
        var ip = 0usize
        while ip < k {
            var j = 0usize
            while j < nc {
                centers[ip + k * j] = 0.0f64
                j += 1usize
            }
            var sum = 0.0f64
            var ix = 0usize
            while ix < n {
                let v = w[ix] * math.pow[f64](u[ix + n * ip], m)
                sum += v
                j = 0usize
                while j < nc {
                    centers[ip + k * j] += v * x[ix + n * j]
                    j += 1usize
                }
                ix += 1usize
            }
            j = 0usize
            while j < nc {
                centers[ip + k * j] = centers[ip + k * j] / sum
                j += 1usize
            }
            ip += 1usize
        }
        cm_dist(x, centers, n, nc, k, d)
        cm_memb(d, n, k, expo, u)
        new_value = cm_err(u, d, w, n, k, m)
        if math.abs[f64](old_value - new_value) < reltol * (old_value + reltol) { break }
        old_value = new_value
    }
    // back to the original row order
    i = 0usize
    while i < n {
        let src = usize(perm[i]) - 1usize
        var ip = 0usize
        while ip < k {
            u_out[src + n * ip] = u[i + n * ip]
            ip += 1usize
        }
        i += 1usize
    }
    ret (iter - 1usize, new_value, ok)
}

fn cm_dist(x: []const f64, p: []const f64, n: usize, nc: usize, k: usize, d: []f64) {
    var ix = 0usize
    while ix < n {
        var ip = 0usize
        while ip < k {
            var s = 0.0f64
            var j = 0usize
            while j < nc {
                let v = x[ix + n * j] - p[ip + k * j]
                s += v * v
                j += 1usize
            }
            d[ix + n * ip] = s
            ip += 1usize
        }
        ix += 1usize
    }
}

fn cm_memb(d: []const f64, n: usize, k: usize, expo: f64, u: []f64) {
    var ix = 0usize
    while ix < n {
        var zeros = 0usize
        var ip = 0usize
        while ip < k {
            if d[ix + n * ip] == 0.0f64 { zeros += 1usize }
            ip += 1usize
        }
        if zeros > 0usize {
            // the C code computes 1 / n_of_zeroes in integers
            var v = 0.0f64
            if zeros == 1usize { v = 1.0f64 }
            ip = 0usize
            while ip < k {
                if d[ix + n * ip] == 0.0f64 { u[ix + n * ip] = v } else { u[ix + n * ip] = 0.0f64 }
                ip += 1usize
            }
        } else {
            var sum = 0.0f64
            ip = 0usize
            while ip < k {
                let v = 1.0f64 / math.pow[f64](d[ix + n * ip], expo)
                sum += v
                u[ix + n * ip] = v
                ip += 1usize
            }
            ip = 0usize
            while ip < k {
                u[ix + n * ip] = u[ix + n * ip] / sum
                ip += 1usize
            }
        }
        ix += 1usize
    }
}

fn cm_err(u: []const f64, d: []const f64, w: []const f64, n: usize, k: usize, m: f64) -> f64 {
    var s = 0.0f64
    var ix = 0usize
    while ix < n {
        var ip = 0usize
        while ip < k {
            s += w[ix] * math.pow[f64](u[ix + n * ip], m) * d[ix + n * ip]
            ip += 1usize
        }
        ix += 1usize
    }
    ret s
}
