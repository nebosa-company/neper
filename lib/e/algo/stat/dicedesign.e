// R DiceDesign: the discrepancy criteria of a design in the unit cube (C2, L2, L2star, M2, S2, W2, Mix2) and the distance measures
// mindist, phiP and coverage. The design is n points of dimension d, row-major.
//
// Not here: the design generators (lhsDesign, the simulated-annealing and ESE optimisers, wspDesign, factDesign) and meshRatio.

use e.algo.rand.r as rr
use e.algo.rand.rdist as rd
use e.math
use e.mem

fn at(x: []const f64, d: usize, i: usize, j: usize) -> f64 { ret x[i * d + j] }

fn ab(v: f64) -> f64 { ret math.abs[f64](v) }

fn mx(a: f64, b: f64) -> f64 {
    if a > b { ret a }
    ret b
}

fn mn(a: f64, b: f64) -> f64 {
    if a < b { ret a }
    ret b
}

// kind: 0 C2, 1 L2, 2 L2star, 3 M2, 4 S2, 5 W2, 6 Mix2
fn discrepancy(x: []const f64, n: usize, d: usize, kind: usize) -> f64 {
    let nf = f64(n)
    let df = f64(d)
    var s1 = 0.0f64
    var s2 = 0.0f64
    var i = 0usize
    while i < n {
        var p = 1.0f64
        var j = 0usize
        while j < d {
            let v = at(x, d, i, j)
            if kind == 0usize { p = p * (1.0f64 + 0.5f64 * ab(v - 0.5f64) - 0.5f64 * ab(v - 0.5f64) * ab(v - 0.5f64)) }
            if kind == 1usize { p = p * v * (1.0f64 - v) }
            if kind == 2usize { p = p * (1.0f64 - v) }
            if kind == 3usize { p = p * (3.0f64 - v * v) }
            if kind == 4usize { p = p * (1.0f64 + 2.0f64 * v - 2.0f64 * v * v) }
            if kind == 6usize { p = p * (5.0f64 / 3.0f64 - 0.25f64 * ab(v - 0.5f64) - 0.25f64 * ab(v - 0.5f64) * ab(v - 0.5f64)) }
            j += 1usize
        }
        s1 += p
        var k = 0usize
        while k < n {
            var q = 1.0f64
            j = 0usize
            while j < d {
                let a = at(x, d, i, j)
                let b = at(x, d, k, j)
                if kind == 0usize { q = q * (1.0f64 + 0.5f64 * ab(a - 0.5f64) + 0.5f64 * ab(b - 0.5f64) - 0.5f64 * ab(a - b)) }
                if kind == 1usize { q = q * (1.0f64 - mx(a, b)) * mn(a, b) }
                if kind == 2usize { q = q * (1.0f64 - mx(a, b)) }
                if kind == 3usize { q = q * (2.0f64 - mx(a, b)) }
                if kind == 4usize { q = q * (1.0f64 - ab(a - b)) }
                if kind == 5usize { q = q * (1.5f64 - ab(a - b) * (1.0f64 - ab(a - b))) }
                if kind == 6usize { q = q * (15.0f64 / 8.0f64 - 0.25f64 * ab(a - 0.5f64) - 0.25f64 * ab(b - 0.5f64) - 0.75f64 * ab(a - b) + 0.5f64 * ab(a - b) * ab(a - b)) }
                j += 1usize
            }
            s2 += q
            k += 1usize
        }
        i += 1usize
    }
    if kind == 0usize { ret math.sqrt[f64](math.pow[f64](13.0f64 / 12.0f64, df) - 2.0f64 / nf * s1 + s2 / (nf * nf)) }
    if kind == 1usize { ret math.sqrt[f64](math.pow[f64](12.0f64, 0.0f64 - df) - math.pow[f64](2.0f64, 1.0f64 - df) / nf * s1 + s2 / (nf * nf)) }
    if kind == 2usize {
        // the diagonal pairs use the single-point terms; s1 here is the product of (1 - x) and is rebuilt below
        var t = 0.0f64
        i = 0usize
        while i < n {
            var a1 = 1.0f64
            var a2 = 1.0f64
            var j = 0usize
            while j < d {
                a1 = a1 * (1.0f64 - at(x, d, i, j))
                a2 = a2 * (1.0f64 - at(x, d, i, j) * at(x, d, i, j))
                j += 1usize
            }
            t += a1 / (nf * nf) - math.pow[f64](2.0f64, 1.0f64 - df) / nf * a2
            i += 1usize
        }
        // off-diagonal pairs: the full double sum minus its diagonal
        var off = s2
        i = 0usize
        while i < n {
            var a1 = 1.0f64
            var j = 0usize
            while j < d {
                a1 = a1 * (1.0f64 - at(x, d, i, j))
                j += 1usize
            }
            off -= a1
            i += 1usize
        }
        ret math.sqrt[f64](math.pow[f64](3.0f64, 0.0f64 - df) + off / (nf * nf) + t)
    }
    if kind == 3usize { ret math.sqrt[f64](math.pow[f64](4.0f64 / 3.0f64, df) - math.pow[f64](2.0f64, 1.0f64 - df) / nf * s1 + s2 / (nf * nf)) }
    if kind == 4usize { ret math.sqrt[f64](math.pow[f64](4.0f64 / 3.0f64, df) - 2.0f64 / nf * s1 + math.pow[f64](2.0f64, df) / (nf * nf) * s2) }
    if kind == 5usize { ret math.sqrt[f64](0.0f64 - math.pow[f64](4.0f64 / 3.0f64, df) + s2 / (nf * nf)) }
    ret math.sqrt[f64](math.pow[f64](19.0f64 / 12.0f64, df) - 2.0f64 / nf * s1 + s2 / (nf * nf))
}

fn dist2(x: []const f64, d: usize, i: usize, k: usize) -> f64 {
    var s = 0.0f64
    var j = 0usize
    while j < d {
        let v = at(x, d, i, j) - at(x, d, k, j)
        s += v * v
        j += 1usize
    }
    ret math.sqrt[f64](s)
}

fn mindist(x: []const f64, n: usize, d: usize) -> f64 {
    var m = 1.0e30f64
    var i = 0usize
    while i < n {
        var k = i + 1usize
        while k < n {
            let v = dist2(x, d, i, k)
            if v < m { m = v }
            k += 1usize
        }
        i += 1usize
    }
    ret m
}

fn phi_p(x: []const f64, n: usize, d: usize, p: f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        var k = i + 1usize
        while k < n {
            s += math.pow[f64](dist2(x, d, i, k), 0.0f64 - p)
            k += 1usize
        }
        i += 1usize
    }
    ret math.pow[f64](s, 1.0f64 / p)
}

fn coverage(x: []const f64, n: usize, d: usize) -> f64 {
    var sum = 0.0f64
    var sq = 0.0f64
    var i = 0usize
    while i < n {
        var m = 10000.0f64
        var k = 0usize
        while k < n {
            if k != i {
                let v = dist2(x, d, i, k)
                if v < m { m = v }
            }
            k += 1usize
        }
        sum += m
        i += 1usize
    }
    let gbar = sum / f64(n)
    i = 0usize
    while i < n {
        var m = 10000.0f64
        var k = 0usize
        while k < n {
            if k != i {
                let v = dist2(x, d, i, k)
                if v < m { m = v }
            }
            k += 1usize
        }
        sq += (m - gbar) * (m - gbar)
        i += 1usize
    }
    ret 1.0f64 / gbar * math.sqrt[f64](sq / f64(n))
}

// lhsDesign(n, dimension, randomized, seed): the points row-major n by dimension; set.seed(seed), then n * dimension uniforms for the jitter
// and one random permutation per dimension, exactly as the package draws them
fn lhs_design(a: *mem.Arena, n: usize, dimension: usize, randomized: bool, seed: i64, out: []f64) -> err {
    var g: rr.Rng = zero
    rr.seed(&g, seed)
    let (ran, e1) = mem.alloc[f64](a, n * dimension)
    if e1 != ok { ret e1 }
    var k = 0usize
    while k < n * dimension {
        if randomized { ran[k] = rr.unif(&g) } else { ran[k] = 0.5f64 }
        k += 1usize
    }
    // matrix(runif(...), n, dimension) fills by column: element (i, j) is ran[j * n + i]
    var j = 0usize
    while j < dimension {
        let (idx, e2) = rr.sample_int(a, &g, i64(n), i64(n), false)
        if e2 != ok { ret e2 }
        var i = 0usize
        while i < n {
            out[i * dimension + j] = (f64(idx[i]) - ran[j * n + i]) / f64(n)
            i += 1usize
        }
        j += 1usize
    }
    ret ok
}

// factDesign(dimension, levels): the full factorial grid on [0, 1], the first factor varying slowest; levels has one entry per dimension
fn fact_design(levels: []const usize, out: []f64) {
    let d = levels.len
    var total = 1usize
    var i = 0usize
    while i < d {
        total = total * levels[i]
        i += 1usize
    }
    var r = 0usize
    while r < total {
        var rem = r
        var j = d
        while j > 0usize {
            j -= 1usize
            let lv = levels[j]
            let pos = rem % lv
            rem = rem / lv
            var v = 0.0f64
            if lv > 1usize { v = f64(pos) / f64(lv - 1usize) }
            out[r * d + j] = v
        }
        r += 1usize
    }
}

// runif.faure(n, dimension): the Faure sequence, row-major n by dimension
fn faure(a: *mem.Arena, n: usize, dimension: usize, out: []f64) -> err {
    var base = 2usize
    var found = false
    while !found {
        var isp = base >= 2usize
        var q = 2usize
        while q * q <= base {
            if base % q == 0usize { isp = false }
            q += 1usize
        }
        if isp && base >= dimension { found = true } else { base += 1usize }
    }
    let r = f64(base)
    var m = 1usize
    var pw = r
    while pw < f64(n) {
        pw = pw * r
        m += 1usize
    }
    let (c, e1) = mem.alloc[f64](a, m * m)
    if e1 != ok { ret e1 }
    var t = 0usize
    while t < m * m {
        c[t] = 0.0f64
        t += 1usize
    }
    var jj = 0usize
    while jj < m {
        c[jj] = 1.0f64
        jj += 1usize
    }
    jj = 1usize
    while jj < m {
        c[jj * m + jj] = 1.0f64
        if jj >= 2usize {
            var ii = 1usize
            while ii < jj {
                c[ii * m + jj] = c[ii * m + jj - 1usize] + c[(ii - 1usize) * m + jj - 1usize]
                ii += 1usize
            }
        }
        jj += 1usize
    }
    t = 0usize
    while t < m * m {
        c[t] = c[t] - r * math.floor[f64](c[t] / r)
        t += 1usize
    }
    let (nr, e2) = mem.alloc[f64](a, m)
    if e2 != ok { ret e2 }
    let (nr2, e3) = mem.alloc[f64](a, m)
    if e3 != ok { ret e3 }
    var i = 1usize
    while i <= n {
        var number = f64(i)
        var k = 0usize
        while k < m {
            let quo = math.floor[f64](number / r)
            nr[k] = number - quo * r
            number = quo
            k += 1usize
        }
        var s = 0.0f64
        var dg = 1.0f64
        k = 0usize
        while k < m {
            dg = dg / r
            s += dg * nr[k]
            k += 1usize
        }
        out[(i - 1usize) * dimension] = s
        var j = 1usize
        while j < dimension {
            k = 0usize
            while k < m {
                var acc = 0.0f64
                var l = 0usize
                while l < m {
                    acc += c[k * m + l] * nr[l]
                    l += 1usize
                }
                nr2[k] = acc - r * math.floor[f64](acc / r)
                k += 1usize
            }
            k = 0usize
            s = 0.0f64
            dg = 1.0f64
            while k < m {
                nr[k] = nr2[k]
                dg = dg / r
                s += dg * nr[k]
                k += 1usize
            }
            out[(i - 1usize) * dimension + j] = s
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// lhsDesign drawing from a generator already in use (the package seeds it once, then goes on to optimise with the same stream)
fn lhs_from(a: *mem.Arena, g: *rr.Rng, n: usize, dimension: usize, out: []f64) -> err {
    let (ran, e1) = mem.alloc[f64](a, n * dimension)
    if e1 != ok { ret e1 }
    var k = 0usize
    while k < n * dimension {
        ran[k] = rr.unif(g)
        k += 1usize
    }
    var j = 0usize
    while j < dimension {
        let (idx, e2) = rr.sample_int(a, g, i64(n), i64(n), false)
        if e2 != ok { ret e2 }
        var i = 0usize
        while i < n {
            out[i * dimension + j] = (f64(idx[i]) - ran[j * n + i]) / f64(n)
            i += 1usize
        }
        j += 1usize
    }
    ret ok
}

// maximinSA_LHS with the GEOM (profile 0) or LINEAR (profile 1) temperature: simulated annealing of an LHS by element exchange on phiP,
// accepting a worse design with probability exp((phiP - phiP') / T) through rbinom(1, 1, .) exactly as the package draws it.
// m is the working design (n by d row-major) and holds the answer; the final phiP is returned
fn maximin_sa(a: *mem.Arena, g: *rr.Rng, m: []f64, n: usize, d: usize, t0: f64, cc: f64, it: usize, p: f64, profile: usize) -> f64 { ret anneal(a, g, m, n, d, t0, cc, it, p, profile, 100usize) }

// the same annealing on any score: ck 100 is phiP at p, ck 0..6 a discrepancy criterion of discrepancy()
fn score(x: []const f64, n: usize, d: usize, p: f64, ck: usize) -> f64 {
    if ck == 100usize { ret phi_p(x, n, d, p) }
    if ck == 0usize { ret c2_exact(x, n, d) }
    ret discrepancy(x, n, d, ck)
}

fn anneal(a: *mem.Arena, g: *rr.Rng, m: []f64, n: usize, d: usize, t0: f64, cc: f64, it: usize, p: f64, profile: usize, ck: usize) -> f64 {
    let (gm, e1) = mem.alloc[f64](a, n * d)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    var temp = t0
    var i = 0usize
    var fi = score(m, n, d, p, ck)
    while temp > 0.0f64 && i < it {
        var k = 0usize
        while k < n * d {
            gm[k] = m[k]
            k += 1usize
        }
        // lhs_EP: two rows and a column, each trunc(runif(.., 0, n)) + 1
        let r1 = usize(math.floor[f64](rr.runif(g, 0.0f64, f64(n))))
        let r2 = usize(math.floor[f64](rr.runif(g, 0.0f64, f64(n))))
        let col = usize(math.floor[f64](rr.runif(g, 0.0f64, f64(d))))
        let x = gm[r1 * d + col]
        gm[r1 * d + col] = gm[r2 * d + col]
        gm[r2 * d + col] = x
        var fn2 = score(gm, n, d, p, ck)
        if ck == 0usize { fn2 = math.sqrt[f64](c2_ep(m, n, d, r1, r2, col, fi * fi)) }
        var diff = math.exp[f64]((fi - fn2) / temp)
        if diff > 1.0f64 { diff = 1.0f64 }
        var accept = false
        if diff == 1.0f64 {
            accept = true
        } else {
            let b = rd.rbinom(g, 1.0f64, diff)
            if b == 1.0f64 { accept = true }
        }
        if accept {
            k = 0usize
            while k < n * d {
                m[k] = gm[k]
                k += 1usize
            }
            fi = fn2
        }
        i += 1usize
        if profile == 0usize { temp = math.pow[f64](cc, f64(i)) * t0 } else { temp = t0 * (1.0f64 - f64(i) / f64(it)) }
    }
    ret fi
}

fn c2_g(m: []const f64, d: usize, i: usize) -> f64 {
    var t: [16]f64 = zero
    var j = 0usize
    while j < d {
        t[j] = 1.0f64 + ab(m[i * d + j] - 0.5f64)
        j += 1usize
    }
    ret prod_ld(t[0usize..d])
}

fn c2_h(m: []const f64, d: usize, i: usize) -> f64 {
    var t: [16]f64 = zero
    var j = 0usize
    while j < d {
        let x = m[i * d + j] - 0.5f64
        t[j] = (1.0f64 + ab(x) / 2.0f64) - 0.5f64 * (x * x)
        j += 1usize
    }
    ret prod_ld(t[0usize..d])
}

fn c2_cc(m: []const f64, n: usize, d: usize, i: usize, j: usize) -> f64 {
    let nf = f64(n)
    if i == j { ret c2_g(m, d, i) / (nf * nf) - 2.0f64 * c2_h(m, d, i) / nf }
    var t: [16]f64 = zero
    var k = 0usize
    while k < d {
        let xi = m[i * d + k] - 0.5f64
        let xj = m[j * d + k] - 0.5f64
        t[k] = 0.5f64 * (((2.0f64 + ab(xi)) + ab(xj)) - ab(xi - xj))
        k += 1usize
    }
    ret prod_ld(t[0usize..d]) / (nf * nf)
}

// discrepancyC2_EP: the squared C2 discrepancy after exchanging entries (i1, k) and (i2, k) of m, from the squared discrepancy p of m. This is
// the package's update formula (rows i1 == i2 included, where it does not return the unchanged value)
fn c2_ep(m: []const f64, n: usize, d: usize, i1: usize, i2: usize, k: usize, p: f64) -> f64 {
    let nf = f64(n)
    let x1 = m[i1 * d + k] - 0.5f64
    let x2 = m[i2 * d + k] - 0.5f64
    let alpha = (1.0f64 + ab(x2)) / (1.0f64 + ab(x1))
    let beta = (2.0f64 - ab(x2)) / (2.0f64 - ab(x1))
    var v = p + c2_g(m, d, i1) * alpha / (nf * nf) - 2.0f64 * alpha * beta * c2_h(m, d, i1) / nf
    v = v - c2_cc(m, n, d, i1, i1) - c2_cc(m, n, d, i2, i2)
    v = v + c2_g(m, d, i2) / (nf * nf * alpha) - 2.0f64 * c2_h(m, d, i2) / (nf * alpha * beta)
    var xs: [64]f64 = zero
    var w = 0usize
    var j = 0usize
    while j < n {
        if j != i1 && j != i2 {
            let xj = m[j * d + k] - 0.5f64
            let gm = (((2.0f64 + ab(x2)) + ab(xj)) - ab(x2 - xj)) / (((2.0f64 + ab(x1)) + ab(xj)) - ab(x1 - xj))
            let c1 = c2_cc(m, n, d, i1, j)
            let c2 = c2_cc(m, n, d, i2, j)
            xs[w] = ((gm * c1 - c1) + c2 / gm) - c2
            w += 1usize
        }
        j += 1usize
    }
    ret v + 2.0f64 * sum_ld(xs[0usize..w])
}

// R's prod() and sum() accumulate in extended precision and round once to double; double-double arithmetic gives the same rounded
// result, which keeps the incremental C2 update bit-compatible where a value that is mathematically unchanged is compared with itself
fn two_sum(a: f64, b: f64) -> (f64, f64) {
    let s = a + b
    let bb = s - a
    ret (s, (a - (s - bb)) + (b - bb))
}

fn split(a: f64) -> (f64, f64) {
    let t = 134217729.0f64 * a
    let hi = t - (t - a)
    ret (hi, a - hi)
}

fn two_prod(a: f64, b: f64) -> (f64, f64) {
    let p = a * b
    let (ah, al) = split(a)
    let (bh, bl) = split(b)
    ret (p, ((ah * bh - p) + ah * bl + al * bh) + al * bl)
}

fn prod_ld(v: []const f64) -> f64 {
    var hi = 1.0f64
    var lo = 0.0f64
    var i = 0usize
    while i < v.len {
        let (p, e) = two_prod(hi, v[i])
        let nlo = e + hi * 0.0f64 + lo * v[i]
        let (s, t) = two_sum(p, nlo)
        hi = s
        lo = t
        i += 1usize
    }
    ret hi + lo
}


fn sum_ld(v: []const f64) -> f64 {
    var hi = 0.0f64
    var lo = 0.0f64
    var i = 0usize
    while i < v.len {
        let (s, e) = two_sum(hi, v[i])
        hi = s
        lo = lo + e
        i += 1usize
    }
    ret hi + lo
}

// the C2 discrepancy with R's operation order and its extended-precision products, for the annealing's starting value
fn c2_exact(x: []const f64, n: usize, d: usize) -> f64 {
    let nf = f64(n)
    var s1 = 0.0f64
    var s2 = 0.0f64
    var t: [16]f64 = zero
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < d {
            let a = ab(x[i * d + j] - 0.5f64)
            t[j] = (1.0f64 + 0.5f64 * a) - 0.5f64 * (a * a)
            j += 1usize
        }
        s1 = s1 + prod_ld(t[0usize..d])
        var k = 0usize
        while k < n {
            j = 0usize
            while j < d {
                t[j] = ((1.0f64 + 0.5f64 * ab(x[i * d + j] - 0.5f64)) + 0.5f64 * ab(x[k * d + j] - 0.5f64)) - 0.5f64 * ab(x[i * d + j] - x[k * d + j])
                j += 1usize
            }
            s2 = s2 + prod_ld(t[0usize..d])
            k += 1usize
        }
        i += 1usize
    }
    ret math.sqrt[f64](math.pow[f64](13.0f64 / 12.0f64, f64(d)) - (2.0f64 / nf) * s1 + (1.0f64 / (nf * nf)) * s2)
}

// wspDesign (init "center"): the indices (1-based) of the selected rows, in the package's order; the count is returned, x needs room for n
fn wsp(a: *mem.Arena, m: []const f64, n: usize, d: usize, dmin: f64, x: []usize) -> usize {
    let inf = 1.0e308f64 * 10.0f64
    let (dm, e1) = mem.alloc[f64](a, n * n)
    if e1 != ok { ret 0usize }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            if i == j { dm[i * n + j] = inf } else { dm[i * n + j] = dist2(m, d, i, j) }
            j += 1usize
        }
        i += 1usize
    }
    // the centre point's distance to every row picks the base
    var base = 0usize
    var best = inf
    i = 0usize
    while i < n {
        var s = 0.0f64
        var k = 0usize
        while k < d {
            let v = m[i * d + k] - 0.5f64
            s += v * v
            k += 1usize
        }
        let dc = math.sqrt[f64](s)
        if dc < best {
            best = dc
            base = i
        }
        i += 1usize
    }
    var npoints = 1usize
    var cnt = 1usize
    x[0usize] = base + 1usize
    while npoints < n {
        var j = 0usize
        var added = 0usize
        let (co, e2) = mem.alloc[usize](a, n)
        if e2 != ok { ret cnt }
        while j < n {
            if dm[base * n + j] < dmin {
                co[added] = j
                added += 1usize
            }
            j += 1usize
        }
        if added > 0usize {
            var q = 0usize
            while q < added {
                var r = 0usize
                while r < n {
                    dm[r * n + co[q]] = inf
                    dm[co[q] * n + r] = inf
                    r += 1usize
                }
                q += 1usize
            }
            npoints += added
        }
        var nb = 0usize
        var mv = dm[base * n]
        j = 1usize
        while j < n {
            if dm[base * n + j] < mv {
                mv = dm[base * n + j]
                nb = j
            }
            j += 1usize
        }
        npoints += 1usize
        j = 0usize
        while j < n {
            dm[base * n + j] = inf
            dm[j * n + base] = inf
            j += 1usize
        }
        base = nb
        if cnt < n {
            x[cnt] = base + 1usize
            cnt += 1usize
        }
    }
    ret cnt
}

// meshRatio: the largest over the smallest nearest-neighbour distance, taken over the first n - 1 points as the package does
fn mesh_ratio(x: []const f64, n: usize, d: usize) -> f64 {
    var dmax = 0.0f64 - 1.0e30f64
    var dmn = 1.0e30f64
    var i = 0usize
    while i + 1usize < n {
        var lo = 1.0e30f64
        var k = 0usize
        while k < n {
            if k != i {
                var s = 0.0f64
                var j = 0usize
                while j < d {
                    s += (x[i * d + j] - x[k * d + j]) * (x[i * d + j] - x[k * d + j])
                    j += 1usize
                }
                if s < lo { lo = s }
            }
            k += 1usize
        }
        if dmax < lo { dmax = lo }
        if dmn > lo { dmn = lo }
        i += 1usize
    }
    ret math.sqrt[f64](dmax / dmn)
}

// maximinESE_LHS(design, T0, inner_it, J, it, p): the enhanced stochastic evolutionary search for a maximin Latin hypercube. m is the working design (n by d row-major) and receives
// the best design found; the best phiP is returned. Each inner step draws J candidate swaps in column count %% d (two rows each, trunc(runif(2, 0, n)) + 1) and keeps the best
// candidate if its phiP exceeds the current by no more than T * runif(1); T is then raised or lowered by the package's rules.
fn maximin_ese(a: *mem.Arena, g: *rr.Rng, m: []f64, n: usize, d: usize, t0: f64, inner_it: usize, jj: usize, it: usize, p: f64) -> f64 {
    let (cur, e1) = mem.alloc[f64](a, n * d)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let (cand, e2) = mem.alloc[f64](a, n * d)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    let (bestd, e3) = mem.alloc[f64](a, n * d)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    let (bold, e4) = mem.alloc[f64](a, n * d)
    if e4 != ok { ret 0.0f64 / 0.0f64 }
    let (trial, e5) = mem.alloc[f64](a, n * d)
    if e5 != ok { ret 0.0f64 / 0.0f64 }
    var k = 0usize
    while k < n * d {
        cur[k] = m[k]
        bestd[k] = m[k]
        k += 1usize
    }
    var temp = t0
    var fi = phi_p(cur, n, d, p)
    var best = fi
    var q = 0usize
    while q < it {
        let bold_val = best
        k = 0usize
        while k < n * d {
            bold[k] = bestd[k]
            k += 1usize
        }
        var ni = 0.0f64
        var na = 0.0f64
        var count = 0usize
        while count <= inner_it {
            count += 1usize
            let col = count % d
            var bv = 0.0f64
            var have = false
            var jx = 0usize
            while jx < jj {
                k = 0usize
                while k < n * d {
                    trial[k] = cur[k]
                    k += 1usize
                }
                let r1 = usize(math.floor[f64](rr.runif(g, 0.0f64, f64(n))))
                let r2 = usize(math.floor[f64](rr.runif(g, 0.0f64, f64(n))))
                let x = trial[r1 * d + col]
                trial[r1 * d + col] = trial[r2 * d + col]
                trial[r2 * d + col] = x
                let v = phi_p(trial, n, d, p)
                if !have || v < bv {
                    bv = v
                    have = true
                    k = 0usize
                    while k < n * d {
                        cand[k] = trial[k]
                        k += 1usize
                    }
                }
                jx += 1usize
            }
            let delta = bv - fi
            if delta <= temp * rr.runif(g, 0.0f64, 1.0f64) {
                k = 0usize
                while k < n * d {
                    cur[k] = cand[k]
                    k += 1usize
                }
                fi = bv
                na += 1.0f64
                if bv <= best {
                    k = 0usize
                    while k < n * d {
                        bestd[k] = cand[k]
                        k += 1usize
                    }
                    best = bv
                    ni += 1.0f64
                }
            }
        }
        let v1 = na / f64(inner_it)
        let v2 = ni / f64(inner_it)
        if best - bold_val < 0.0f64 {
            if v1 >= 0.1f64 && v2 <= v1 {
                temp = 0.8f64 * temp
            } else if v1 >= 0.1f64 && v2 == v1 {
                temp = temp
            } else {
                temp = temp / 0.8f64
            }
        } else {
            if v1 <= 0.1f64 { temp = temp / 0.7f64 } else { temp = temp * 0.9f64 }
        }
        q += 1usize
    }
    k = 0usize
    while k < n * d {
        m[k] = bestd[k]
        k += 1usize
    }
    ret best
}

// discrepESE_LHS(design, T0, inner_it, J, it, criterion = "C2"): the same enhanced stochastic evolutionary search as maximin_ese, on the centred L2 discrepancy through its
// element-exchange update c2_ep; returns the best discrepancy and leaves the best design in m
fn discrep_ese_c2(a: *mem.Arena, g: *rr.Rng, m: []f64, n: usize, d: usize, t0: f64, inner_it: usize, jj: usize, it: usize) -> f64 {
    let (cur, e1) = mem.alloc[f64](a, n * d)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let (bestd, e3) = mem.alloc[f64](a, n * d)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    var k = 0usize
    while k < n * d {
        cur[k] = m[k]
        bestd[k] = m[k]
        k += 1usize
    }
    var temp = t0
    var fi = c2_exact(cur, n, d)
    var best = fi
    var q = 0usize
    while q < it {
        let bold_val = best
        var ni = 0.0f64
        var na = 0.0f64
        var count = 0usize
        while count <= inner_it {
            count += 1usize
            let col = count % d
            var bv = 0.0f64
            var br1 = 0usize
            var br2 = 0usize
            var have = false
            var jx = 0usize
            while jx < jj {
                let r1 = usize(math.floor[f64](rr.runif(g, 0.0f64, f64(n))))
                let r2 = usize(math.floor[f64](rr.runif(g, 0.0f64, f64(n))))
                let v = math.sqrt[f64](c2_ep(cur, n, d, r1, r2, col, fi * fi))
                if !have || v < bv {
                    bv = v
                    br1 = r1
                    br2 = r2
                    have = true
                }
                jx += 1usize
            }
            let delta = bv - fi
            if delta <= temp * rr.runif(g, 0.0f64, 1.0f64) {
                let x = cur[br1 * d + col]
                cur[br1 * d + col] = cur[br2 * d + col]
                cur[br2 * d + col] = x
                fi = bv
                na += 1.0f64
                if bv <= best {
                    k = 0usize
                    while k < n * d {
                        bestd[k] = cur[k]
                        k += 1usize
                    }
                    best = bv
                    ni += 1.0f64
                }
            }
        }
        let v1 = na / f64(inner_it)
        let v2 = ni / f64(inner_it)
        if best - bold_val < 0.0f64 {
            if v1 >= 0.1f64 && v2 <= v1 {
                temp = 0.8f64 * temp
            } else if v1 >= 0.1f64 && v2 == v1 {
                temp = temp
            } else {
                temp = temp / 0.8f64
            }
        } else {
            if v1 <= 0.1f64 { temp = temp / 0.7f64 } else { temp = temp * 0.9f64 }
        }
        q += 1usize
    }
    k = 0usize
    while k < n * d {
        m[k] = bestd[k]
        k += 1usize
    }
    ret best
}
