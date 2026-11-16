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
fn maximin_sa(a: *mem.Arena, g: *rr.Rng, m: []f64, n: usize, d: usize, t0: f64, cc: f64, it: usize, p: f64, profile: usize) -> f64 {
    let (gm, e1) = mem.alloc[f64](a, n * d)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    var temp = t0
    var i = 0usize
    var fi = phi_p(m, n, d, p)
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
        let fn2 = phi_p(gm, n, d, p)
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
