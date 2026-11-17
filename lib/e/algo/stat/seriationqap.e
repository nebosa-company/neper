// R seriation, the QAP methods QAP_LS, QAP_2SUM, QAP_BAR and QAP_Inertia: seriate builds a distance matrix A of
// positions and calls qap::qap(A, B) with B the dissimilarities (1 / (1 + d) for 2SUM). qap 0.2-0 has two solvers,
// both ported from its source: the simulated annealing qaph4 of qapsim.f (the default) and Taillard's robust tabu
// search of rots.c. Both draw from R's stream, so under the same seed they give R's order.
//
// Dissimilarities are a full symmetric n by n row-major matrix; orders are 0-based.

use e.algo.rand.r as rng
use e.math
use e.mem

// the position matrix A of a QAP method: 1 LS, 2 2SUM, 3 BAR, 4 Inertia (BAR with the default bandwidth max(1, floor(0.2 n)))
fn position_matrix(kind: usize, n: usize, am: []f64) {
    var b = usize(i64(0.2f64 * f64(n)))
    if b < 1usize { b = 1usize }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            var dd = f64(i) - f64(j)
            if j > i { dd = f64(j) - f64(i) }
            let sq = dd * dd
            var v = 0.0f64
            if kind == 1usize { v = f64(n) - dd }
            if kind == 2usize { v = sq }
            if kind == 3usize {
                v = f64(b) + 1.0f64 - dd
                if v < 0.0f64 { v = 0.0f64 }
            }
            if kind == 4usize { v = f64(n) * f64(n) - sq }
            am[i * n + j] = v
            j += 1usize
        }
        i += 1usize
    }
}

fn unifrand(r: *rng.Rng) -> f64 {
    var x = rng.unif(r)
    while x >= 1.0f64 || x < 0.0f64 { x = rng.unif(r) }
    ret x
}

fn objective(a: []const f64, b: []const f64, n: usize, p: []const usize) -> f64 {
    var c = 0.0f64
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            c += a[i * n + j] * b[p[i] * n + p[j]]
            j += 1usize
        }
        i += 1usize
    }
    ret c
}

// qaph4 of qapsim.f on the 0-based permutation perm (changed in place); ope receives the best one, the value is its objective (ibest)
fn qaph4(r: *rng.Rng, a: []const f64, b: []const f64, n: usize, miter: usize, fiter: f64, ft: f64, maxsteps: usize, ope: []usize, perm: []usize) -> f64 {
    var ia = 0.0f64
    var ib = 0.0f64
    var i = 0usize
    while i < n * n {
        ia += a[i]
        ib += b[i]
        i += 1usize
    }
    var t = ia / f64(n * n - n)
    t = t * ib
    var ibest = t
    var t1 = t
    var m1 = miter
    var ol = objective(a, b, n, perm)
    var step = 0usize
    var more = true
    while more {
        var mn = ol
        var mx = -1.797693e308f64
        var it = 0usize
        while it < m1 {
            it += 1usize
            var x = unifrand(r)
            var i1 = i64(x * f64(n) + 0.5f64)
            if i1 < 1i64 { i1 = 1i64 }
            let p1 = usize(i1) - 1usize
            let ibild = perm[p1]
            x = unifrand(r)
            var i2 = i64(x * f64(n) + 0.5f64)
            if i2 < 1i64 { i2 = 1i64 }
            let p2 = usize(i2) - 1usize
            var skip = false
            if p1 != p2 {
                let jbild = perm[p2]
                var delta = 0.0f64
                var j1 = 0usize
                while j1 < n {
                    if j1 != p1 && j1 != p2 {
                        let kbild = perm[j1]
                        delta = delta - (a[p1 * n + j1] - a[p2 * n + j1]) * (b[ibild * n + kbild] - b[jbild * n + kbild])
                    }
                    j1 += 1usize
                }
                delta = 2.0f64 * delta - (a[p1 * n + p1] - a[p2 * n + p2]) * (b[ibild * n + ibild] - b[jbild * n + jbild])
                var take = delta <= 0.0f64
                if !take {
                    var pr = 0.0f64
                    if !(delta / t1 > 10.0f64) { pr = math.exp[f64](0.0f64 - delta / t1) }
                    x = unifrand(r)
                    if !(x > pr) { take = true } else { skip = true }
                }
                if take {
                    perm[p1] = jbild
                    perm[p2] = ibild
                    ol = ol + delta
                }
            }
            if !skip {
                if ol < mn { mn = ol }
                if ol > mx { mx = ol }
                if !(ibest < ol) {
                    ibest = ol
                    var q = 0usize
                    while q < n {
                        ope[q] = perm[q]
                        q += 1usize
                    }
                }
            }
        }
        t1 = t1 * ft
        m1 = usize(i64(f64(m1) * fiter))
        step += 1usize
        more = mx > mn && step < maxsteps
    }
    ret ibest
}

fn rots_delta(a: []const f64, b: []const f64, n: usize, p: []const usize, i: usize, j: usize) -> f64 {
    var d = (a[i * n + i] - a[j * n + j]) * (b[p[j] * n + p[j]] - b[p[i] * n + p[i]]) + (a[i * n + j] - a[j * n + i]) * (b[p[j] * n + p[i]] - b[p[i] * n + p[j]])
    var k = 0usize
    while k < n {
        if k != i && k != j {
            d += (a[k * n + i] - a[k * n + j]) * (b[p[k] * n + p[j]] - b[p[k] * n + p[i]]) + (a[i * n + k] - a[j * n + k]) * (b[p[j] * n + p[k]] - b[p[i] * n + p[k]])
        }
        k += 1usize
    }
    ret d
}

fn rots_update(a: []const f64, b: []const f64, n: usize, p: []const usize, old: f64, rr: usize, s: usize, u: usize, v: usize) -> f64 {
    ret old + (a[rr * n + u] - a[rr * n + v] + a[s * n + v] - a[s * n + u]) * (b[p[s] * n + p[u]] - b[p[s] * n + p[v]] + b[p[rr] * n + p[v]] - b[p[rr] * n + p[u]]) + (a[u * n + rr] - a[v * n + rr] + a[v * n + s] - a[u * n + s]) * (b[p[u] * n + p[s]] - b[p[v] * n + p[s]] + b[p[v] * n + p[rr]] - b[p[u] * n + p[rr]])
}

// qap_rots of rots.c: p is the 0-based start, best receives the best permutation; the value is its objective
fn rots(a2: *mem.Arena, r: *rng.Rng, a: []const f64, b: []const f64, n: usize, iter_max: usize, tenure: usize, aspiration: i64, p: []usize, best: []usize) -> f64 {
    var tmin = usize(i64(math.ceil[f64](0.9f64 * f64(tenure))))
    var tmax = usize(i64(math.floor[f64](1.1f64 * f64(tenure))))
    if tmin < 1usize { tmin = 1usize }
    if tmax < tmin { tmax = tmin }
    let (delta, e1) = mem.alloc[f64](a2, n * n)
    let (tabu, e2) = mem.alloc[i64](a2, n * n)
    if e1 != ok || e2 != ok { ret -1.0f64 }
    var i = 0usize
    while i < n {
        best[i] = p[i]
        i += 1usize
    }
    i = 0usize
    while i < n * n {
        tabu[i] = 0i64
        delta[i] = 0.0f64
        i += 1usize
    }
    var cur = objective(a, b, n, p)
    var best_cost = cur
    i = 0usize
    while i + 1usize < n {
        var j = i + 1usize
        while j < n {
            delta[i * n + j] = rots_delta(a, b, n, p, i, j)
            j += 1usize
        }
        i += 1usize
    }
    var it = 1usize
    while it <= iter_max {
        var ri = n
        var rj = n
        var rd = 1.0e308f64 * 10.0f64
        var already = false
        let iti = i64(it)
        i = 0usize
        while i + 1usize < n {
            var j = i + 1usize
            while j < n {
                let d = delta[i * n + j]
                let ti = tabu[i * n + p[j]]
                let tj = tabu[j * n + p[i]]
                let allowed = ti < iti || tj < iti
                let aspired = ti < iti - aspiration || tj < iti - aspiration || cur + d < best_cost
                if (aspired && !already) || (aspired && already && d < rd) || (!aspired && !already && allowed && d < rd) {
                    ri = i
                    rj = j
                    rd = d
                    if aspired { already = true }
                }
                j += 1usize
            }
            i += 1usize
        }
        if ri == n {
            ri = usize(i64(rng.unif(r) * f64(n)))
            if ri >= n { ri = n - 1usize }
            var go = true
            while go {
                rj = usize(i64(rng.unif(r) * f64(n)))
                if rj >= n { rj = n - 1usize }
                go = rj == ri
            }
            if ri > rj {
                let tt = ri
                ri = rj
                rj = tt
            }
            rd = delta[ri * n + rj]
        }
        tabu[ri * n + p[ri]] = iti + i64(tmin) + i64(rng.unif(r) * f64(tmax - tmin + 1usize))
        tabu[rj * n + p[rj]] = iti + i64(tmin) + i64(rng.unif(r) * f64(tmax - tmin + 1usize))
        let sw = p[ri]
        p[ri] = p[rj]
        p[rj] = sw
        cur += rd
        if cur < best_cost {
            best_cost = cur
            i = 0usize
            while i < n {
                best[i] = p[i]
                i += 1usize
            }
        }
        i = 0usize
        while i + 1usize < n {
            var j = i + 1usize
            while j < n {
                if i != ri && i != rj && j != ri && j != rj {
                    delta[i * n + j] = rots_update(a, b, n, p, delta[i * n + j], ri, rj, i, j)
                } else {
                    delta[i * n + j] = rots_delta(a, b, n, p, i, j)
                }
                j += 1usize
            }
            i += 1usize
        }
        it += 1usize
    }
    ret objective(a, b, n, best)
}

// seriate(d, "QAP_*"): kind 1 LS, 2 2SUM, 3 BAR, 4 Inertia; method 0 SA (qapSA defaults, rep restarts), 1 RoTS (defaults iter 100 n, tenure n, aspiration 5 n^2)
fn qap_order(a: *mem.Arena, r: *rng.Rng, d: []const f64, n: usize, kind: usize, method: usize, rep: usize, out: []usize) -> err {
    if n < 2usize {
        out[0usize] = 0usize
        ret ok
    }
    let (am, e1) = mem.alloc[f64](a, n * n)
    let (bm, e2) = mem.alloc[f64](a, n * n)
    let (best, e3) = mem.alloc[usize](a, n)
    let (cur, e4) = mem.alloc[usize](a, n)
    let (ope, e5) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    position_matrix(kind, n, am)
    var i = 0usize
    while i < n * n {
        bm[i] = d[i]
        if kind == 2usize { bm[i] = 1.0f64 / (1.0f64 + d[i]) }
        i += 1usize
    }
    var best_obj = 1.0e308f64 * 10.0f64
    var k = 0usize
    while k < rep {
        let (perm, pe) = rng.sample_int(a, r, i64(n), i64(n), false)
        if pe != ok { ret pe }
        i = 0usize
        while i < n {
            cur[i] = usize(perm[i]) - 1usize
            ope[i] = 0usize
            i += 1usize
        }
        var ol = 0.0f64
        if method == 0usize {
            ol = qaph4(r, am, bm, n, 2usize * n, 1.1f64, 0.5f64, 50usize, ope, cur)
        } else {
            ol = rots(a, r, am, bm, n, 100usize * n, n, i64(5usize * n * n), cur, ope)
        }
        if ol < best_obj {
            best_obj = ol
            i = 0usize
            while i < n {
                best[i] = ope[i]
                i += 1usize
            }
        }
        k += 1usize
    }
    i = 0usize
    while i < n {
        out[i] = best[i]
        i += 1usize
    }
    ret ok
}
