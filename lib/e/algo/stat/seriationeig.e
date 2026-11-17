// R seriation, the eigenvector methods: Spectral, Spectral_norm, MDS (cmdscale, k = 1) and MDS_angle (k = 2).
// An order from an eigenvector is only as oriented as the eigenvector is, and LAPACK's dsyevr fixes the sign in its own
// way; e.algo.linalg.lapack_syevr is that routine ported statement for statement, so the orientation is R's.
//
// Dissimilarities are a full symmetric n by n row-major matrix d; an order is a permutation of 0..n-1.

use e.math
use e.mem
use e.algo.linalg.lapack_syevr as lapack

// R's rowSums keeps its running sum in long double (64-bit significand); a double-double running sum rounded once to double
// stands in for it and agrees with it except in about one rounding in two thousand.
fn ld_add(hi: *f64, lo: *f64, x: f64) {
    let h = *hi
    let s = h + x
    let bb = s - h
    let e = ((h - (s - bb)) + (x - bb)) + *lo
    let nh = s + e
    *hi = nh
    *lo = e - (nh - s)
}

// R's order(): ascending, ties by index
fn order_of(v: []const f64, n: usize, out: []usize) {
    var i = 0usize
    while i < n {
        out[i] = i
        i += 1usize
    }
    // insertion sort is stable
    i = 1usize
    while i < n {
        let cur = out[i]
        var j = i
        while j > 0usize && v[out[j - 1usize]] > v[cur] {
            out[j] = out[j - 1usize]
            j -= 1usize
        }
        out[j] = cur
        i += 1usize
    }
}

// eigen(m, symmetric = TRUE) of R: m is a row-major n by n matrix of which LAPACK reads the lower triangle; values come back
// falling, vecs[k * n + i] the i-th entry of the k-th vector, signs exactly as R's dsyevr (e.algo.linalg.lapack_syevr).
fn eigen_lapack(a: *mem.Arena, m: []const f64, n: usize, vals: []f64, vecs: []f64) -> err {
    if n == 1usize {
        vals[0usize] = m[0usize]
        vecs[0usize] = 1.0f64
        ret ok
    }
    let (xc, e1) = mem.alloc[f64](a, n * n)
    let (w, e2) = mem.alloc[f64](a, n)
    let (z, e3) = mem.alloc[f64](a, n * n)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            xc[i + j * n] = m[i * n + j]
            j += 1usize
        }
        i += 1usize
    }
    let er = lapack.dsyevr_all(a, xc, n, w, z)
    if er != ok { ret er }
    var k = 0usize
    while k < n {
        vals[k] = w[n - 1usize - k]
        var q = 0usize
        while q < n {
            vecs[k * n + q] = z[(n - 1usize - k) * n + q]
            q += 1usize
        }
        k += 1usize
    }
    ret ok
}

// seriate(d, "Spectral"): the order of the Fiedler vector of the Laplacian of 1 / (1 + d)
fn spectral_order(a: *mem.Arena, d: []const f64, n: usize, out: []usize) -> err {
    let (l, e1) = mem.alloc[f64](a, n * n)
    let (vals, e2) = mem.alloc[f64](a, n)
    let (vecs, e3) = mem.alloc[f64](a, n * n)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        var hi = 0.0f64
        var lo = 0.0f64
        var j = 0usize
        while j < n {
            ld_add(&hi, &lo, 1.0f64 / (1.0f64 + d[i * n + j]))
            j += 1usize
        }
        let rs = hi
        j = 0usize
        while j < n {
            l[i * n + j] = 0.0f64 - 1.0f64 / (1.0f64 + d[i * n + j])
            j += 1usize
        }
        l[i * n + i] = rs - 1.0f64 / (1.0f64 + d[i * n + i])
        i += 1usize
    }
    if n < 2usize {
        out[0usize] = 0usize
        ret ok
    }
    let er = eigen_lapack(a, l, n, vals, vecs)
    if er != ok { ret er }
    order_of(vecs[(n - 2usize) * n..(n - 1usize) * n], n, out)
    ret ok
}

// seriate(d, "Spectral_norm"): the order of the second eigenvector of the normalised matrix, scaled by the row weights
fn spectral_norm_order(a: *mem.Arena, d: []const f64, n: usize, out: []usize) -> err {
    let (l, e1) = mem.alloc[f64](a, n * n)
    let (vals, e2) = mem.alloc[f64](a, n)
    let (vecs, e3) = mem.alloc[f64](a, n * n)
    let (ds, e4) = mem.alloc[f64](a, n)
    let (key, e5) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        var hi = 0.0f64
        var lo = 0.0f64
        var j = 0usize
        while j < n {
            let wv = 1.0f64 / (1.0f64 + d[i * n + j])
            ld_add(&hi, &lo, 1.0f64 / math.sqrt[f64](wv))
            j += 1usize
        }
        ds[i] = hi
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            let wv = 1.0f64 / (1.0f64 + d[i * n + j])
            l[i * n + j] = (ds[i] * wv) * ds[j]
            j += 1usize
        }
        i += 1usize
    }
    // LAPACK reads the lower triangle
    i = 0usize
    while i < n {
        var j = i + 1usize
        while j < n {
            l[i * n + j] = l[j * n + i]
            j += 1usize
        }
        i += 1usize
    }
    if n < 2usize {
        out[0usize] = 0usize
        ret ok
    }
    let er = eigen_lapack(a, l, n, vals, vecs)
    if er != ok { ret er }
    i = 0usize
    while i < n {
        key[i] = ds[i] * vecs[n + i]
        i += 1usize
    }
    order_of(key, n, out)
    ret ok
}

// stats::cmdscale(d, k, eig = TRUE): coords n by k row-major
fn cmdscale_k(a: *mem.Arena, d: []const f64, n: usize, k: usize, coords: []f64) -> err {
    let (b, e1) = mem.alloc[f64](a, n * n)
    let (vals, e2) = mem.alloc[f64](a, n)
    let (vecs, e3) = mem.alloc[f64](a, n * n)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var i = 0usize
    while i < n * n {
        b[i] = d[i] * d[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < n {
            s += b[i * n + j]
            j += 1usize
        }
        let mu = s / f64(n)
        j = 0usize
        while j < n {
            b[i * n + j] -= mu
            j += 1usize
        }
        i += 1usize
    }
    var j = 0usize
    while j < n {
        var s = 0.0f64
        i = 0usize
        while i < n {
            s += b[i * n + j]
            i += 1usize
        }
        let mu = s / f64(n)
        i = 0usize
        while i < n {
            b[i * n + j] -= mu
            i += 1usize
        }
        j += 1usize
    }
    i = 0usize
    while i < n * n {
        b[i] = (0.0f64 - b[i]) / 2.0f64
        i += 1usize
    }
    let er = eigen_lapack(a, b, n, vals, vecs)
    if er != ok { ret er }
    var c = 0usize
    while c < k {
        var s = 0.0f64
        if vals[c] > 0.0f64 { s = math.sqrt[f64](vals[c]) }
        i = 0usize
        while i < n {
            coords[i * k + c] = vecs[c * n + i] * s
            i += 1usize
        }
        c += 1usize
    }
    ret ok
}

// seriate(d, "MDS"): the order of the first cmdscale coordinate
fn mds_order(a: *mem.Arena, d: []const f64, n: usize, out: []usize) -> err {
    let (pt, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    if n < 2usize {
        out[0usize] = 0usize
        ret ok
    }
    let er = cmdscale_k(a, d, n, 1usize, pt)
    if er != ok { ret er }
    order_of(pt, n, out)
    ret ok
}

// seriate(d, "MDS_angle"): the order of the angle in the plane of the first two cmdscale coordinates, cut at the largest gap
fn mds_angle_order(a: *mem.Arena, d: []const f64, n: usize, out: []usize) -> err {
    let (pt, e1) = mem.alloc[f64](a, 2usize * n)
    let (al, e2) = mem.alloc[f64](a, n)
    let (o2, e3) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    if n < 3usize {
        mds_order_small(n, out)
        ret ok
    }
    let er = cmdscale_k(a, d, n, 2usize, pt)
    if er != ok { ret er }
    var i = 0usize
    while i < n {
        al[i] = math.atan2[f64](pt[i * 2usize], pt[i * 2usize + 1usize])
        i += 1usize
    }
    order_of(al, n, o2)
    var cut = 0usize
    var best = -1.0f64
    i = 0usize
    while i < n {
        var nxt = al[o2[0usize]] + 2.0f64 * 3.141592653589793f64
        if i + 1usize < n { nxt = al[o2[i + 1usize]] }
        let g = math.abs[f64](nxt - al[o2[i]])
        if g > best {
            best = g
            cut = i + 1usize
        }
        i += 1usize
    }
    // cut is 1-based as R's which.max; rotate when cut < n
    i = 0usize
    while i < n {
        out[i] = o2[i]
        i += 1usize
    }
    if cut < n {
        var p = 0usize
        while p < n - cut {
            out[p] = o2[cut + p]
            p += 1usize
        }
        p = 0usize
        while p < cut {
            out[n - cut + p] = o2[p]
            p += 1usize
        }
    }
    ret ok
}

fn mds_order_small(n: usize, out: []usize) {
    var i = 0usize
    while i < n {
        out[i] = i
        i += 1usize
    }
}
