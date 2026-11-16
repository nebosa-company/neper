// R DiceDesign: the discrepancy criteria of a design in the unit cube (C2, L2, L2star, M2, S2, W2, Mix2) and the distance measures
// mindist, phiP and coverage. The design is n points of dimension d, row-major.
//
// Not here: the design generators (lhsDesign, the simulated-annealing and ESE optimisers, wspDesign, factDesign) and meshRatio.

use e.math

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
