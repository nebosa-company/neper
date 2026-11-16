// R cubature: the integral of a fixed set of smooth integrands over a box in one to three dimensions, by a tensor Gauss-Legendre rule on a grid of sub-boxes.
// It reaches the same value hcubature and pcubature reach, to their tolerance; it is not the Genz-Malik or Clenshaw-Curtis recursion of the package.
//
// Not here: the adaptive subdivision, vector-valued integrands, the error estimate, infinite limits and user functions.

use e.math
use e.mem

// the n-point Gauss-Legendre nodes and weights on [-1, 1] by Newton's method on the Legendre polynomial
fn gauss_legendre(n: usize, x: []f64, w: []f64) {
    var i = 0usize
    while i < n {
        var z = math.cos[f64](3.141592653589793238462643383279f64 * (f64(i) + 0.75f64) / (f64(n) + 0.5f64))
        var pp = 1.0f64
        var it = 0usize
        while it < 100usize {
            var p1 = 1.0f64
            var p2 = 0.0f64
            var j = 0usize
            while j < n {
                let p3 = p2
                p2 = p1
                p1 = ((2.0f64 * f64(j) + 1.0f64) * z * p2 - f64(j) * p3) / f64(j + 1usize)
                j += 1usize
            }
            pp = f64(n) * (z * p1 - p2) / (z * z - 1.0f64)
            let z1 = z
            z = z1 - p1 / pp
            if math.abs[f64](z - z1) < 1.0e-15f64 { break }
            it += 1usize
        }
        x[i] = z
        w[i] = 2.0f64 / ((1.0f64 - z * z) * pp * pp)
        i += 1usize
    }
}

// the integrand `id` at the point p of dimension d: 0 exp(-sum x^2), 1 prod cos(x), 2 1 / (1 + sum x), 3 (sum x)^2 exp(-prod x)
fn integrand(id: usize, d: usize, p: []const f64) -> f64 {
    var s = 0.0f64
    var s2 = 0.0f64
    var pr = 1.0f64
    var c = 1.0f64
    var i = 0usize
    while i < d {
        s += p[i]
        s2 += p[i] * p[i]
        pr = pr * p[i]
        c = c * math.cos[f64](p[i])
        i += 1usize
    }
    if id == 0usize { ret math.exp[f64](0.0f64 - s2) }
    if id == 1usize { ret c }
    if id == 2usize { ret 1.0f64 / (1.0f64 + s) }
    ret s * s * math.exp[f64](0.0f64 - pr)
}

// the integral over the box lo..hi: `cells` sub-intervals per dimension and a 12-point rule in each
fn integral_box(a: *mem.Arena, id: usize, d: usize, lo: []const f64, hi: []const f64, cells: usize) -> f64 {
    let q = 12usize
    let (gx, e1) = mem.alloc[f64](a, q)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let (gw, e2) = mem.alloc[f64](a, q)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    gauss_legendre(q, gx, gw)
    let (pt, e3) = mem.alloc[f64](a, d)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    let (cell, e4) = mem.alloc[usize](a, d)
    if e4 != ok { ret 0.0f64 / 0.0f64 }
    let (node, e5) = mem.alloc[usize](a, d)
    if e5 != ok { ret 0.0f64 / 0.0f64 }
    var total = 0.0f64
    var ncell = 1usize
    var k = 0usize
    while k < d {
        ncell *= cells
        k += 1usize
    }
    var nnode = 1usize
    k = 0usize
    while k < d {
        nnode *= q
        k += 1usize
    }
    var c = 0usize
    while c < ncell {
        var rem = c
        k = 0usize
        while k < d {
            cell[k] = rem % cells
            rem = rem / cells
            k += 1usize
        }
        var nd = 0usize
        while nd < nnode {
            var r2 = nd
            var wt = 1.0f64
            k = 0usize
            while k < d {
                node[k] = r2 % q
                r2 = r2 / q
                let h = (hi[k] - lo[k]) / f64(cells)
                let a0 = lo[k] + h * f64(cell[k])
                pt[k] = a0 + h * (gx[node[k]] + 1.0f64) / 2.0f64
                wt = wt * gw[node[k]] * h / 2.0f64
                k += 1usize
            }
            total += wt * integrand(id, d, pt)
            nd += 1usize
        }
        c += 1usize
    }
    ret total
}
