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

// the integral over a box whose ends may be infinite (an end at or beyond 1e99 in magnitude counts as infinite): each dimension is mapped from s in (0, 1) the way cubature
// does (finite: linear; one infinite end: a + s / (1 - s) or b - (1 - s) / s; both: u / (1 - u^2) with u = 2 s - 1), then `cells` sub-intervals with a 12-point rule each
fn integral_inf(a: *mem.Arena, id: usize, d: usize, lo: []const f64, hi: []const f64, cells: usize) -> f64 {
    let q = 12usize
    let (gx, e1) = mem.alloc[f64](a, q)
    let (gw, e2) = mem.alloc[f64](a, q)
    let (pt, e3) = mem.alloc[f64](a, d)
    let (cell, e4) = mem.alloc[usize](a, d)
    let (node, e5) = mem.alloc[usize](a, d)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret 0.0f64 / 0.0f64 }
    gauss_legendre(q, gx, gw)
    var total = 0.0f64
    var ncell = 1usize
    var nnode = 1usize
    var k = 0usize
    while k < d {
        ncell *= cells
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
                let h = 1.0f64 / f64(cells)
                let s = h * f64(cell[k]) + h * (gx[node[k]] + 1.0f64) / 2.0f64
                wt = wt * gw[node[k]] * h / 2.0f64
                let lin = lo[k] > -1.0e99f64
                let hin = hi[k] < 1.0e99f64
                if lin && hin {
                    pt[k] = lo[k] + (hi[k] - lo[k]) * s
                    wt = wt * (hi[k] - lo[k])
                } else if lin {
                    pt[k] = lo[k] + s / (1.0f64 - s)
                    wt = wt / ((1.0f64 - s) * (1.0f64 - s))
                } else if hin {
                    pt[k] = hi[k] - (1.0f64 - s) / s
                    wt = wt / (s * s)
                } else {
                    let u = 2.0f64 * s - 1.0f64
                    pt[k] = u / (1.0f64 - u * u)
                    wt = wt * 2.0f64 * (1.0f64 + u * u) / ((1.0f64 - u * u) * (1.0f64 - u * u))
                }
                k += 1usize
            }
            total += wt * integrand(id, d, pt)
            nd += 1usize
        }
        c += 1usize
    }
    ret total
}

// One Genz-Malik degree 7 / 5 rule on the box c +- hw (dimension d >= 2) as the C of cubature's hcubature applies it: val is the degree 7 estimate, err its distance to the degree 5 one and
// split the dimension of the largest fourth difference (the ratio is (lambda4 / lambda2)^2, as the package has it). Writes (val, err, split) to out.
fn gm_rule(id: usize, d: usize, c: []const f64, hw: []const f64, out: []f64) {
    let l2 = 0.3585685828003180919906451539079374954541f64
    let l4 = 0.9486832980505137995996680633298155601160f64
    let l5 = 0.6882472016116852977216287342936235251269f64
    let nf = f64(d)
    var twopn = 1.0f64
    var q = 0usize
    while q < d {
        twopn *= 2.0f64
        q += 1usize
    }
    let w1 = (12824.0f64 - 9120.0f64 * nf + 400.0f64 * nf * nf) / 19683.0f64
    let w2 = 980.0f64 / 6561.0f64
    let w3 = (1820.0f64 - 400.0f64 * nf) / 19683.0f64
    let w4 = 200.0f64 / 19683.0f64
    let w5 = 6859.0f64 / 19683.0f64 / twopn
    let we1 = (729.0f64 - 950.0f64 * nf + 50.0f64 * nf * nf) / 729.0f64
    let we2 = 245.0f64 / 486.0f64
    let we3 = (265.0f64 - 100.0f64 * nf) / 1458.0f64
    let we4 = 25.0f64 / 729.0f64
    let ratio = (l4 / l2) * (l4 / l2)
    var p: [8]f64 = zero
    var i = 0usize
    while i < d {
        p[i] = c[i]
        i += 1usize
    }
    let f0 = integrand(id, d, p[0usize..d])
    var s2 = 0.0f64
    var s3 = 0.0f64
    var best = 0.0f64 - 1.0f64
    var bi = 0usize
    i = 0usize
    while i < d {
        p[i] = c[i] + l2 * hw[i]
        let u2 = integrand(id, d, p[0usize..d])
        p[i] = c[i] - l2 * hw[i]
        let v2 = integrand(id, d, p[0usize..d])
        p[i] = c[i] + l4 * hw[i]
        let u3 = integrand(id, d, p[0usize..d])
        p[i] = c[i] - l4 * hw[i]
        let v3 = integrand(id, d, p[0usize..d])
        p[i] = c[i]
        s2 += u2 + v2
        s3 += u3 + v3
        let df = math.abs[f64](u3 + v3 - 2.0f64 * f0 - ratio * (u2 + v2 - 2.0f64 * f0))
        if df > best {
            best = df
            bi = i
        }
        i += 1usize
    }
    var s4 = 0.0f64
    i = 0usize
    while i + 1usize < d {
        var j = i + 1usize
        while j < d {
            var si = 0usize
            while si < 2usize {
                var sj = 0usize
                while sj < 2usize {
                    if si == 0usize { p[i] = c[i] - l4 * hw[i] } else { p[i] = c[i] + l4 * hw[i] }
                    if sj == 0usize { p[j] = c[j] - l4 * hw[j] } else { p[j] = c[j] + l4 * hw[j] }
                    s4 += integrand(id, d, p[0usize..d])
                    sj += 1usize
                }
                si += 1usize
            }
            p[i] = c[i]
            p[j] = c[j]
            j += 1usize
        }
        i += 1usize
    }
    var s5 = 0.0f64
    var k = 0usize
    while f64(k) < twopn {
        i = 0usize
        while i < d {
            if (k / (1usize << i)) % 2usize == 1usize { p[i] = c[i] + l5 * hw[i] } else { p[i] = c[i] - l5 * hw[i] }
            i += 1usize
        }
        s5 += integrand(id, d, p[0usize..d])
        k += 1usize
    }
    var vol = 1.0f64
    i = 0usize
    while i < d {
        vol *= 2.0f64 * hw[i]
        i += 1usize
    }
    let res = vol * (w1 * f0 + w2 * s2 + w3 * s3 + w4 * s4 + w5 * s5)
    let res5 = vol * (we1 * f0 + we2 * s2 + we3 * s3 + we4 * s4)
    out[0usize] = res
    out[1usize] = math.abs[f64](res5 - res)
    out[2usize] = f64(bi)
}

// hcubature for the fixed integrand `id` over the box lo..hi (2 to 7 dimensions): the box is split along the dimension of the largest fourth difference of the region with the largest error,
// until the summed error is within tol * |integral| or max_eval evaluations are spent; out = (integral, error, evaluations)
fn hcubature_gm(a: *mem.Arena, id: usize, d: usize, lo: []const f64, hi: []const f64, tol: f64, max_eval: usize, out: []f64) -> err {
    var npts = 1usize + 4usize * d + 2usize * d * (d - 1usize)
    npts += 1usize << d
    let cap = 2usize + max_eval / npts
    let (cc, e1) = mem.alloc[f64](a, cap * d)
    let (hh, e2) = mem.alloc[f64](a, cap * d)
    let (vv, e3) = mem.alloc[f64](a, cap)
    let (er, e4) = mem.alloc[f64](a, cap)
    let (sd, e5) = mem.alloc[usize](a, cap)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret e1 }
    var r: [3]f64 = zero
    var i = 0usize
    while i < d {
        cc[i] = (lo[i] + hi[i]) / 2.0f64
        hh[i] = (hi[i] - lo[i]) / 2.0f64
        i += 1usize
    }
    gm_rule(id, d, cc[0usize..d], hh[0usize..d], r[0usize..3usize])
    vv[0usize] = r[0usize]
    er[0usize] = r[1usize]
    sd[0usize] = usize(r[2usize])
    var n = 1usize
    var neval = npts
    while true {
        var tv = 0.0f64
        var te = 0.0f64
        i = 0usize
        while i < n {
            tv += vv[i]
            te += er[i]
            i += 1usize
        }
        if te <= tol * math.abs[f64](tv) || te <= 0.0f64 { break }
        if neval >= max_eval || n + 1usize >= cap { break }
        var k = 0usize
        i = 1usize
        while i < n {
            if er[i] > er[k] { k = i }
            i += 1usize
        }
        let dim = sd[k]
        var ch: [8]f64 = zero
        var hw2: [8]f64 = zero
        i = 0usize
        while i < d {
            hw2[i] = hh[k * d + i]
            ch[i] = cc[k * d + i]
            i += 1usize
        }
        hw2[dim] = hw2[dim] / 2.0f64
        i = 0usize
        while i < d {
            cc[k * d + i] = ch[i]
            hh[k * d + i] = hw2[i]
            cc[n * d + i] = ch[i]
            hh[n * d + i] = hw2[i]
            i += 1usize
        }
        cc[k * d + dim] = ch[dim] - hw2[dim]
        cc[n * d + dim] = ch[dim] + hw2[dim]
        gm_rule(id, d, cc[k * d..k * d + d], hh[k * d..k * d + d], r[0usize..3usize])
        vv[k] = r[0usize]
        er[k] = r[1usize]
        sd[k] = usize(r[2usize])
        gm_rule(id, d, cc[n * d..n * d + d], hh[n * d..n * d + d], r[0usize..3usize])
        vv[n] = r[0usize]
        er[n] = r[1usize]
        sd[n] = usize(r[2usize])
        n += 1usize
        neval += 2usize * npts
    }
    var tv = 0.0f64
    var te = 0.0f64
    i = 0usize
    while i < n {
        tv += vv[i]
        te += er[i]
        i += 1usize
    }
    out[0usize] = tv
    out[1usize] = te
    out[2usize] = f64(neval)
    ret ok
}
