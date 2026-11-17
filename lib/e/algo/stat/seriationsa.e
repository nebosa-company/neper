// R seriation, the annealing methods and the small ones: ARSA (a port of arsa.f, whose RNG is R's through a
// single-precision wrapper), GSA (the generic simulated annealing of seriate, default Gradient_raw with LS_insert),
// Random, Identity, Reverse, and permute / get_order on vectors, dissimilarity matrices and data matrices.
// Streams are R's (e.algo.rand.r), drawn in the order the R and Fortran code draws them, so a seed gives R's order.
//
// Not here: QAP_LS, QAP_2SUM, QAP_BAR and QAP_Inertia (seriate calls qap::qap, whose qaph4 is compiled Fortran that
// is not on disk).
//
// Dissimilarities are a full symmetric n by n row-major matrix; orders are 0-based.

use e.algo.rand.r as rng
use e.algo.stat.seriationcrit as sc
use e.math
use e.mem

// the Fortran wrapper unifrand: (float) unif_rand(), redrawn until it lies in [0, 1)
fn unifrand(r: *rng.Rng) -> f32 {
    var s = f32(rng.unif(r))
    while f64(s) >= 1.0f64 || f64(s) < 0.0f64 { s = f32(rng.unif(r)) }
    ret s
}

// INT(S1 * FLOAT(N) + 1.) clamped to N, 1-based as the Fortran has it
fn pick(r: *rng.Rng, n: usize) -> usize {
    let s1 = unifrand(r)
    let prod = s1 * f32(n)
    let v = prod + 1.0f32
    var i = usize(i64(v))
    if i > n { i = n }
    ret i
}

// ARSA's delta of exchanging the objects at 1-based positions i1 < j1 (the A matrix is a, 1-based entries via the order s)
fn swap_delta(a: []const f64, n: usize, s: []const usize, i1: usize, j1: usize) -> f64 {
    let k = s[i1 - 1usize]
    let m = s[j1 - 1usize]
    var delta = 0.0f64
    var l1 = 1usize
    while l1 <= n {
        if l1 != i1 && l1 != j1 {
            let l = s[l1 - 1usize]
            let di = f64(l1) - f64(i1)
            let dj = f64(l1) - f64(j1)
            delta += (math.abs[f64](di) - math.abs[f64](dj)) * (a[(l - 1usize) * n + m - 1usize] - a[(l - 1usize) * n + k - 1usize])
        }
        l1 += 1usize
    }
    ret delta
}

// the delta of moving the object at position i1 to position j1 (arsa.f's insertion branch)
fn insert_delta(a: []const f64, n: usize, s: []const usize, i1: usize, j1: usize) -> f64 {
    let k = s[i1 - 1usize]
    var delta = 0.0f64
    if j1 > i1 {
        let span = f64(j1 - i1)
        var l = i1 + 1usize
        while l <= j1 {
            let q = s[l - 1usize]
            var i = j1 + 1usize
            while i <= n {
                delta += a[(s[i - 1usize] - 1usize) * n + q - 1usize]
                i += 1usize
            }
            i = 1usize
            while i < i1 {
                delta -= a[(s[i - 1usize] - 1usize) * n + q - 1usize]
                i += 1usize
            }
            l += 1usize
        }
        var i = 1usize
        while i < i1 {
            delta += span * a[(s[i - 1usize] - 1usize) * n + k - 1usize]
            i += 1usize
        }
        i = j1 + 1usize
        while i <= n {
            delta -= span * a[(k - 1usize) * n + s[i - 1usize] - 1usize]
            i += 1usize
        }
        var span2 = span + 1.0f64
        i = i1 + 1usize
        while i <= j1 {
            span2 -= 2.0f64
            delta += span2 * a[(k - 1usize) * n + s[i - 1usize] - 1usize]
            i += 1usize
        }
    } else {
        let span = f64(i1 - j1)
        var l = j1
        while l < i1 {
            let q = s[l - 1usize]
            var i = i1 + 1usize
            while i <= n {
                delta -= a[(s[i - 1usize] - 1usize) * n + q - 1usize]
                i += 1usize
            }
            i = 1usize
            while i < j1 {
                delta += a[(s[i - 1usize] - 1usize) * n + q - 1usize]
                i += 1usize
            }
            l += 1usize
        }
        var i = 1usize
        while i < j1 {
            delta -= span * a[(s[i - 1usize] - 1usize) * n + k - 1usize]
            i += 1usize
        }
        i = i1 + 1usize
        while i <= n {
            delta += span * a[(k - 1usize) * n + s[i - 1usize] - 1usize]
            i += 1usize
        }
        var span2 = span + 1.0f64
        i = j1
        while i < i1 {
            span2 -= 2.0f64
            delta -= span2 * a[(k - 1usize) * n + s[i - 1usize] - 1usize]
            i += 1usize
        }
    }
    ret delta
}

fn move_to(s: []usize, i1: usize, j1: usize) {
    let k = s[i1 - 1usize]
    if j1 > i1 {
        var l = i1
        while l < j1 {
            s[l - 1usize] = s[l]
            l += 1usize
        }
        s[j1 - 1usize] = k
    } else {
        var l = i1
        while l > j1 {
            s[l - 1usize] = s[l - 2usize]
            l -= 1usize
        }
        s[j1 - 1usize] = k
    }
}

// seriate(d, "ARSA"): cool, tmin, rule (the swap-to-inversion probability) and trymult as the control defaults 0.5, 1e-4, 0.5, 100; out is the 0-based order
fn arsa_order(a: *mem.Arena, r: *rng.Rng, d: []const f64, n: usize, cool: f64, tmin: f64, rule: f64, trymult: f64, out: []usize) -> err {
    if n < 3usize {
        var q = 0usize
        while q < n {
            out[q] = q
            q += 1usize
        }
        ret ok
    }
    let (u, e1) = mem.alloc[usize](a, n)
    let (s, e2) = mem.alloc[usize](a, n)
    let (sb, e3) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        u[i] = i + 1usize
        i += 1usize
    }
    var unsel = n
    i = 0usize
    while i < n {
        var iset = pick(r, unsel)
        s[i] = u[iset - 1usize]
        var j = iset
        while j < unsel {
            u[j - 1usize] = u[j]
            j += 1usize
        }
        unsel -= 1usize
        i += 1usize
    }
    var z = 0.0f64
    i = 1usize
    while i < n {
        var j = i + 1usize
        while j <= n {
            z += (f64(j) - f64(i)) * d[(s[i - 1usize] - 1usize) * n + s[j - 1usize] - 1usize]
            j += 1usize
        }
        i += 1usize
    }
    var zbest = z
    var tmax = 0.0f64
    var ll = 0usize
    while ll < n * 10usize {
        var i1 = pick(r, n)
        var j1 = pick(r, n)
        while i1 == j1 { j1 = pick(r, n) }
        if i1 > j1 {
            let jd = j1
            j1 = i1
            i1 = jd
        }
        let delta = swap_delta(d, n, s, i1, j1)
        if delta < 0.0f64 {
            if math.abs[f64](delta) > tmax { tmax = math.abs[f64](delta) }
        }
        ll += 1usize
    }
    let iloop = usize(i64(trymult * f64(n)))
    let nl = (math.log[f64](tmin) - math.log[f64](tmax)) / math.log[f64](cool)
    var nloop = 0usize
    if nl > 0.0f64 && nl < 2.0e9f64 { nloop = usize(i64(nl)) }
    var temp = tmax
    i = 0usize
    while i < n {
        sb[i] = s[i]
        i += 1usize
    }
    let eps = 1.0e-8f64
    var ijk = 0usize
    while ijk < nloop {
        var kkk = 0usize
        while kkk < iloop {
            let s1 = unifrand(r)
            if f64(s1) <= rule {
                var i1 = pick(r, n)
                var j1 = pick(r, n)
                while i1 == j1 { j1 = pick(r, n) }
                if i1 > j1 {
                    let jd = j1
                    j1 = i1
                    i1 = jd
                }
                let delta = swap_delta(d, n, s, i1, j1)
                var take = false
                if delta > 0.0f64 - eps {
                    take = true
                } else {
                    let s2 = unifrand(r)
                    let rcrit = f32(math.exp[f64](delta / temp))
                    if s2 <= rcrit { take = true }
                }
                if take {
                    let k = s[i1 - 1usize]
                    s[i1 - 1usize] = s[j1 - 1usize]
                    s[j1 - 1usize] = k
                    z += delta
                    if delta > 0.0f64 - eps && z > zbest {
                        zbest = z
                        i = 0usize
                        while i < n {
                            sb[i] = s[i]
                            i += 1usize
                        }
                    }
                }
            } else {
                let i1 = pick(r, n)
                var j1 = pick(r, n)
                while i1 == j1 { j1 = pick(r, n) }
                let delta = insert_delta(d, n, s, i1, j1)
                var take = false
                if delta > 0.0f64 - eps {
                    take = true
                } else {
                    let s2 = unifrand(r)
                    let rcrit = f32(math.exp[f64](delta / temp))
                    if s2 <= rcrit { take = true }
                }
                if take {
                    z += delta
                    move_to(s, i1, j1)
                    if delta > 0.0f64 - eps && z > zbest {
                        zbest = z
                        i = 0usize
                        while i < n {
                            sb[i] = s[i]
                            i += 1usize
                        }
                    }
                }
            }
            kkk += 1usize
        }
        temp = temp * cool
        ijk += 1usize
    }
    if zbest > 0.0f64 {
        i = 0usize
        while i < n {
            out[i] = sb[i] - 1usize
            i += 1usize
        }
    } else {
        i = 0usize
        while i < n {
            out[i] = i
            i += 1usize
        }
    }
    ret ok
}

// R's sample(n): a random permutation of 0..n-1
fn random_order(a: *mem.Arena, r: *rng.Rng, n: usize, out: []usize) -> err {
    let (p, e) = rng.sample_int(a, r, i64(n), i64(n), false)
    if e != ok { ret e }
    var i = 0usize
    while i < n {
        out[i] = usize(p[i]) - 1usize
        i += 1usize
    }
    ret ok
}

fn identity_order(n: usize, out: []usize) {
    var i = 0usize
    while i < n {
        out[i] = i
        i += 1usize
    }
}

fn reverse_order(n: usize, out: []usize) {
    var i = 0usize
    while i < n {
        out[i] = n - 1usize - i
        i += 1usize
    }
}

// the local searches of seriation (LS_swap 1, LS_insert 2, LS_reverse 3, LS_mixed 4): a copy of o with one move at two drawn positions
fn local_search(a: *mem.Arena, r: *rng.Rng, kind: usize, o: []const usize, n: usize, out: []usize) -> err {
    var which = kind
    if kind == 4usize { which = usize(rng.unif_index(r, 3.0f64)) + 1usize }
    let (pp, e) = rng.sample_int(a, r, i64(n), 2i64, false)
    if e != ok { ret e }
    let p1 = usize(pp[0usize]) - 1usize
    let p2 = usize(pp[1usize]) - 1usize
    var i = 0usize
    while i < n {
        out[i] = o[i]
        i += 1usize
    }
    if which == 1usize {
        out[p1] = o[p2]
        out[p2] = o[p1]
    }
    if which == 2usize {
        // append(o[-p1], o[p1], after = p2 - 1): the element lands at index p2
        var w = 0usize
        var k = 0usize
        while k < n {
            if k != p1 {
                if w == p2 { w += 1usize }
                out[w] = o[k]
                w += 1usize
            }
            k += 1usize
        }
        out[p2] = o[p1]
    }
    if which == 3usize {
        var lo = p1
        var hi = p2
        if lo > hi {
            lo = p2
            hi = p1
        }
        var k = lo
        while k <= hi {
            out[k] = o[lo + hi - k]
            k += 1usize
        }
    }
    ret ok
}

fn median_of(v: []f64, count: usize) -> f64 {
    var i = 1usize
    while i < count {
        let cur = v[i]
        var j = i
        while j > 0usize && v[j - 1usize] > cur {
            v[j] = v[j - 1usize]
            j -= 1usize
        }
        v[j] = cur
        i += 1usize
    }
    if count % 2usize == 1usize { ret v[count / 2usize] }
    ret (v[count / 2usize - 1usize] + v[count / 2usize]) / 2.0f64
}

// seriate(d, "GSA") with criterion Gradient_raw (a loss as its negative), warmstart Random and the given local search; cool, t_min, try_multiplier, p_initial_accept as the defaults 0.5, 1e-7, 5, 0.01
fn gsa_order(a: *mem.Arena, r: *rng.Rng, d: []const f64, n: usize, kind: usize, cool: f64, tmin: f64, trymult: usize, paccept: f64, out: []usize) -> err {
    let (cur, e1) = mem.alloc[usize](a, n)
    let (nw, e2) = mem.alloc[usize](a, n)
    let (rnd, e3) = mem.alloc[usize](a, n)
    let (dl, e4) = mem.alloc[f64](a, trymult * n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    var e = random_order(a, r, n, cur)
    if e != ok { ret e }
    var z = 0.0f64 - sc.gradient(d, n, cur, 1usize)
    let iloop = trymult * n
    e = random_order(a, r, n, rnd)
    if e != ok { ret e }
    let zr = 0.0f64 - sc.gradient(d, n, rnd, 1usize)
    var cnt = 0usize
    var i = 0usize
    while i < iloop {
        e = local_search(a, r, kind, rnd, n, nw)
        if e != ok { ret e }
        let dz = zr - (0.0f64 - sc.gradient(d, n, nw, 1usize))
        if !(dz > 0.0f64) {
            dl[cnt] = dz
            cnt += 1usize
        }
        i += 1usize
    }
    if cnt == 0usize { ret mem.Full }
    let avg = median_of(dl, cnt)
    var t0 = avg / math.log[f64](paccept)
    var nloop = 1usize
    if t0 <= 0.0f64 {
        t0 = 0.0f64
    } else {
        let nlf = (math.log[f64](tmin) - math.log[f64](t0)) / math.log[f64](cool)
        nloop = 0usize
        if nlf > 0.0f64 && nlf < 2.0e9f64 { nloop = usize(i64(nlf)) }
    }
    var temp = t0
    var it = 0usize
    while it < nloop {
        var j = 0usize
        while j < iloop {
            e = local_search(a, r, kind, cur, n, nw)
            if e != ok { ret e }
            let zn = 0.0f64 - sc.gradient(d, n, nw, 1usize)
            let delta = z - zn
            var take = delta > 0.0f64
            if !take && temp > 0.0f64 {
                if rng.unif(r) < math.exp[f64](delta / temp) { take = true }
            }
            if take {
                var q = 0usize
                while q < n {
                    cur[q] = nw[q]
                    q += 1usize
                }
                z = zn
            }
            j += 1usize
        }
        temp = temp * cool
        it += 1usize
    }
    i = 0usize
    while i < n {
        out[i] = cur[i]
        i += 1usize
    }
    ret ok
}

// permute(x, order) of a dissimilarity matrix: out[i][j] = d[o[i]][o[j]]
fn permute_dist(d: []const f64, n: usize, o: []const usize, out: []f64) {
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            out[i * n + j] = d[o[i] * n + o[j]]
            j += 1usize
        }
        i += 1usize
    }
}

// permute(x, ser_permutation(row, col)) of an nr by nc matrix
fn permute_matrix(x: []const f64, nr: usize, nc: usize, ro: []const usize, co: []const usize, out: []f64) {
    var i = 0usize
    while i < nr {
        var j = 0usize
        while j < nc {
            out[i * nc + j] = x[ro[i] * nc + co[j]]
            j += 1usize
        }
        i += 1usize
    }
}
