// R FNN, the exact-search part: the Euclidean k-nearest-neighbour distances (`knn_dist`, brute force, a point
// never its own neighbour), the Kozachenko-Leonenko `entropy` for k = 1 .. K, `kl_divergence` and
// `mutinfo` (the Kraskov max-norm counting estimator, and the entropy difference).
//
// Not here: the kd-tree, cover-tree and ANN searches themselves (a brute-force search gives the same answers),
// knn.reg's test-set form, the correlation distance, knn.index tie order.

use e.algo.sort
use e.math
use e.math.nmath as nm
use e.mem

fn cmp_up(ctx: *u8, x: f64, y: f64) -> i32 {
    if x < y { ret 0i32 - 1i32 }
    if x > y { ret 1i32 }
    ret 0i32
}

// digamma at a positive integer: -gamma + sum_{j < n} 1 / j
fn digamma_int(n: usize) -> f64 {
    var s = 0.0f64 - 0.5772156649015329f64
    var j = 1usize
    while j < n {
        s += 1.0f64 / f64(j)
        j += 1usize
    }
    ret s
}

// data x is n by p column-major, queries q m by p column-major; out receives m by k column-major distances ascending
// (self excluded when `same`: query i is data row i)
fn knn_dist(a: *mem.Arena, x: []const f64, n: usize, q: []const f64, m: usize, p: usize, k: usize, same: bool, out: []f64) -> err {
    let (d, e) = mem.alloc[f64](a, n)
    if e != ok { ret e }
    var i = 0usize
    while i < m {
        var cnt = 0usize
        var j = 0usize
        while j < n {
            if !(same && j == i) {
                var s = 0.0f64
                var c = 0usize
                while c < p {
                    let t = q[c * m + i] - x[c * n + j]
                    s += t * t
                    c += 1usize
                }
                d[cnt] = math.sqrt[f64](s)
                cnt += 1usize
            }
            j += 1usize
        }
        var ctx = 0u8
        sort.in_place_by[f64, u8](d[0usize..cnt], &ctx, cmp_up)
        var r = 0usize
        while r < k {
            out[r * m + i] = d[r]
            r += 1usize
        }
        i += 1usize
    }
    ret ok
}

// entropy(X, k = K): the K estimates for k = 1 .. K
fn entropy(a: *mem.Arena, x: []const f64, n: usize, p: usize, kmax: usize, out: []f64) -> err {
    let (dd, e) = mem.alloc[f64](a, n * kmax)
    if e != ok { ret e }
    let ke = knn_dist(a, x, n, x, n, p, kmax, true, dd)
    if ke != ok { ret ke }
    let pf = f64(p)
    var j = 0usize
    while j < kmax {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += math.log[f64](dd[j * n + i])
            i += 1usize
        }
        let mld = s / f64(n)
        out[j] = digamma_int(n) - digamma_int(j + 1usize) + pf / 2.0f64 * math.log[f64](3.141592653589793f64) - nm.lgammafn(pf / 2.0f64 + 1.0f64) + pf * mld
        j += 1usize
    }
    ret ok
}

// KL.divergence(X, Y, k = K): the K estimates; X is n by p, Y is m by p
fn kl_divergence(a: *mem.Arena, x: []const f64, n: usize, y: []const f64, m: usize, p: usize, kmax: usize, out: []f64) -> err {
    let (dx, e1) = mem.alloc[f64](a, n * kmax)
    let (dy, e2) = mem.alloc[f64](a, n * kmax)
    if e1 != ok || e2 != ok { ret e1 }
    let a1 = knn_dist(a, x, n, x, n, p, kmax, true, dx)
    if a1 != ok { ret a1 }
    let a2 = knn_dist(a, y, m, x, n, p, kmax, false, dy)
    if a2 != ok { ret a2 }
    var j = 0usize
    while j < kmax {
        var sy = 0.0f64
        var sx = 0.0f64
        var i = 0usize
        while i < n {
            sy += math.log[f64](dy[j * n + i])
            sx += math.log[f64](dx[j * n + i])
            i += 1usize
        }
        out[j] = math.log[f64](f64(m) / f64(n)) + f64(p) * (sy / f64(n) - sx / f64(n))
        j += 1usize
    }
    ret ok
}

// mutinfo(X, Y, k, direct = TRUE): Kraskov's counting estimator with the max norm over both blocks
fn mutinfo_direct(a: *mem.Arena, x: []const f64, p1: usize, y: []const f64, p2: usize, n: usize, k: usize) -> (f64, err) {
    let (d, e) = mem.alloc[f64](a, n)
    if e != ok { ret (0.0f64, e) }
    var tot = 0.0f64
    var i = 0usize
    while i < n {
        var cnt = 0usize
        var j = 0usize
        while j < n {
            if j != i {
                var dist = 0.0f64
                var c = 0usize
                while c < p1 {
                    let t = math.abs[f64](x[c * n + i] - x[c * n + j])
                    if t > dist { dist = t }
                    c += 1usize
                }
                c = 0usize
                while c < p2 {
                    let t = math.abs[f64](y[c * n + i] - y[c * n + j])
                    if t > dist { dist = t }
                    c += 1usize
                }
                d[cnt] = dist
                cnt += 1usize
            }
            j += 1usize
        }
        var ctx = 0u8
        sort.in_place_by[f64, u8](d[0usize..cnt], &ctx, cmp_up)
        let eps = d[k - 1usize]
        var nx = 0usize
        var ny = 0usize
        j = 0usize
        while j < n {
            var dx = 0.0f64
            var c = 0usize
            while c < p1 {
                let t = math.abs[f64](x[c * n + i] - x[c * n + j])
                if t > dx { dx = t }
                c += 1usize
            }
            var dy = 0.0f64
            c = 0usize
            while c < p2 {
                let t = math.abs[f64](y[c * n + i] - y[c * n + j])
                if t > dy { dy = t }
                c += 1usize
            }
            if dx < eps { nx += 1usize }
            if dy < eps { ny += 1usize }
            j += 1usize
        }
        tot += digamma_int(nx) + digamma_int(ny)
        i += 1usize
    }
    ret (digamma_int(n) + digamma_int(k) - tot / f64(n), ok)
}

// the k nearest rows of x (n by p, column-major) to each query row of q (m by p, column-major): 1-based indices and distances,
// m by k column-major, ascending distance, ties by row index; `same` leaves query i's own row out (get.knn)
fn knn_index(a: *mem.Arena, x: []const f64, n: usize, q: []const f64, m: usize, p: usize, k: usize, same: bool, idx: []i64, dist: []f64) -> err {
    let (d, e) = mem.alloc[f64](a, n)
    let (o, oe) = mem.alloc[usize](a, n)
    if e != ok { ret e }
    if oe != ok { ret oe }
    var i = 0usize
    while i < m {
        var cnt = 0usize
        var j = 0usize
        while j < n {
            if !(same && j == i) {
                var s = 0.0f64
                var c = 0usize
                while c < p {
                    let t = q[c * m + i] - x[c * n + j]
                    s += t * t
                    c += 1usize
                }
                d[cnt] = math.sqrt[f64](s)
                o[cnt] = j
                cnt += 1usize
            }
            j += 1usize
        }
        // insertion of the k smallest, stable by index
        var r = 0usize
        while r < k && r < cnt {
            var best = r
            var t = r + 1usize
            while t < cnt {
                if d[t] < d[best] { best = t }
                t += 1usize
            }
            let dv = d[best]
            let ov = o[best]
            d[best] = d[r]
            o[best] = o[r]
            d[r] = dv
            o[r] = ov
            idx[r * m + i] = i64(ov + 1usize)
            dist[r * m + i] = dv
            r += 1usize
        }
        i += 1usize
    }
    ret ok
}

// knn.reg predictions: the mean of y over the k nearest rows (R's rowMeans, a long double sum divided by k)
fn knn_reg(a: *mem.Arena, x: []const f64, n: usize, q: []const f64, m: usize, p: usize, y: []const f64, k: usize, same: bool, pred: []f64) -> err {
    let (idx, e1) = mem.alloc[i64](a, m * k)
    let (dist, e2) = mem.alloc[f64](a, m * k)
    let (v, e3) = mem.alloc[f64](a, k)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    let ke = knn_index(a, x, n, q, m, p, k, same, idx, dist)
    if ke != ok { ret ke }
    var i = 0usize
    while i < m {
        var r = 0usize
        while r < k {
            v[r] = y[usize(idx[r * m + i]) - 1usize]
            r += 1usize
        }
        pred[i] = lsum_k(v) / f64(k)
        i += 1usize
    }
    ret ok
}

fn lsum_k(v: []const f64) -> f64 {
    var hi = 0.0f64
    var lo = 0.0f64
    var i = 0usize
    while i < v.len {
        let xv = v[i]
        let t = hi + xv
        var e = 0.0f64
        if math.abs[f64](hi) >= math.abs[f64](xv) { e = (hi - t) + xv } else { e = (xv - t) + hi }
        hi = t
        lo += e
        i += 1usize
    }
    ret hi + lo
}
