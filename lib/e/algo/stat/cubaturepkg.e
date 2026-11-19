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

// the 15-point Gauss-Kronrod rule (7 point Gauss inside) on c +- hw as cubature's one-dimensional hcubature applies it, with QUADPACK's error: the distance of the two estimates, sharpened by
// resasc * min(1, (200 err / resasc)^1.5) and kept above 50 eps resabs. Writes (val, err, 0) to out.
fn gk15_rule(id: usize, c: []const f64, hw: []const f64, out: []f64) {
    var xgk: [8]f64 = zero
    var wgk: [8]f64 = zero
    var wg: [4]f64 = zero
    xgk[0usize] = 0.991455371120812639206854697526329f64
    xgk[1usize] = 0.949107912342758524526189684047851f64
    xgk[2usize] = 0.864864423359769072789712788640926f64
    xgk[3usize] = 0.741531185599394439863864773280788f64
    xgk[4usize] = 0.586087235467691130294144838258730f64
    xgk[5usize] = 0.405845151377397166906606412076961f64
    xgk[6usize] = 0.207784955007898467600689403773245f64
    wgk[0usize] = 0.022935322010529224963732008058970f64
    wgk[1usize] = 0.063092092629978553290700663189204f64
    wgk[2usize] = 0.104790010322250183839876322541518f64
    wgk[3usize] = 0.140653259715525918745189590510238f64
    wgk[4usize] = 0.169004726639267902826583426598550f64
    wgk[5usize] = 0.190350578064785409913256402421014f64
    wgk[6usize] = 0.204432940075298892414161999234649f64
    wgk[7usize] = 0.209482141084727828012999174891714f64
    wg[0usize] = 0.129484966168869693270611432679082f64
    wg[1usize] = 0.279705391489276667901467771423780f64
    wg[2usize] = 0.381830050505118944950369775488975f64
    wg[3usize] = 0.417959183673469387755102040816327f64
    var p: [1]f64 = zero
    var fv: [15]f64 = zero
    p[0usize] = c[0usize]
    let fc = integrand(id, 1usize, p[0usize..1usize])
    fv[7usize] = fc
    var rk = wgk[7usize] * fc
    var rg = wg[3usize] * fc
    var ra = wgk[7usize] * math.abs[f64](fc)
    var j = 0usize
    while j < 7usize {
        p[0usize] = c[0usize] - hw[0usize] * xgk[j]
        let u = integrand(id, 1usize, p[0usize..1usize])
        p[0usize] = c[0usize] + hw[0usize] * xgk[j]
        let v = integrand(id, 1usize, p[0usize..1usize])
        fv[j] = u
        fv[14usize - j] = v
        rk += wgk[j] * (u + v)
        ra += wgk[j] * (math.abs[f64](u) + math.abs[f64](v))
        if j % 2usize == 1usize { rg += wg[j / 2usize] * (u + v) }
        j += 1usize
    }
    let rmean = rk / 2.0f64
    var ras = wgk[7usize] * math.abs[f64](fc - rmean)
    j = 0usize
    while j < 7usize {
        ras += wgk[j] * (math.abs[f64](fv[j] - rmean) + math.abs[f64](fv[14usize - j] - rmean))
        j += 1usize
    }
    let ahw = math.abs[f64](hw[0usize])
    var er = math.abs[f64]((rk - rg) * hw[0usize])
    ras *= ahw
    ra *= ahw
    if ras != 0.0f64 && er != 0.0f64 {
        var t = math.pow[f64](200.0f64 * er / ras, 1.5f64)
        if t > 1.0f64 { t = 1.0f64 }
        er = ras * t
    }
    let eps = 2.220446049250313e-16f64
    if ra > 2.2250738585072014e-308f64 / (50.0f64 * eps) {
        let lo = eps * 50.0f64 * ra
        if lo > er { er = lo }
    }
    out[0usize] = rk * hw[0usize]
    out[1usize] = er
    out[2usize] = 0.0f64
}

fn rule_eval(id: usize, d: usize, c: []const f64, hw: []const f64, out: []f64) {
    if d == 1usize {
        gk15_rule(id, c, hw, out)
        ret
    }
    gm_rule(id, d, c, hw, out)
}

// hcubature for the fixed integrand `id` over the box lo..hi (1 to 7 dimensions; one dimension uses the Gauss-Kronrod 7-15 rule, QUADPACK's error formula): the box is split along the dimension of the largest fourth difference of the region with the largest error,
// until the summed error is within tol * |integral| or max_eval evaluations are spent; out = (integral, error, evaluations)
fn hcubature_gm(a: *mem.Arena, id: usize, d: usize, lo: []const f64, hi: []const f64, tol: f64, max_eval: usize, out: []f64) -> err {
    var npts = 1usize + 4usize * d + 2usize * d * (d - 1usize)
    npts += 1usize << d
    if d == 1usize { npts = 15usize }
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
    rule_eval(id, d, cc[0usize..d], hh[0usize..d], r[0usize..3usize])
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
        rule_eval(id, d, cc[k * d..k * d + d], hh[k * d..k * d + d], r[0usize..3usize])
        vv[k] = r[0usize]
        er[k] = r[1usize]
        sd[k] = usize(r[2usize])
        rule_eval(id, d, cc[n * d..n * d + d], hh[n * d..n * d + d], r[0usize..3usize])
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

// the Clenshaw-Curtis estimate of the fixed integrand id over lo..hi with n = 2^k + 1 points (the nodes cos(pi j / (n - 1)))
fn cc_estimate(id: usize, lo: f64, hi: f64, n: usize) -> f64 {
    let nn = n - 1usize
    let pi = 3.141592653589793f64
    var total = 0.0f64
    var j = 0usize
    while j <= nn {
        let th = pi * f64(j) / f64(nn)
        var s = 0.0f64
        var k = 0usize
        while k <= nn / 2usize {
            var b0 = 2.0f64
            if k == 0usize || k == nn / 2usize { b0 = 1.0f64 }
            s += b0 / (1.0f64 - 4.0f64 * f64(k) * f64(k)) * math.cos[f64](2.0f64 * f64(k) * th)
            k += 1usize
        }
        var wj = 2.0f64 * s / f64(nn)
        if j == 0usize || j == nn { wj = s / f64(nn) }
        var p: [1]f64 = zero
        p[0usize] = (lo + hi) / 2.0f64 + (hi - lo) / 2.0f64 * math.cos[f64](th)
        total += wj * integrand(id, 1usize, p[0usize..1usize])
        j += 1usize
    }
    ret total * (hi - lo) / 2.0f64
}

// pcubature in one dimension: Clenshaw-Curtis rules of 5, 9, 17, ... points (nested, so the evaluations are the points of the last rule), the error the distance to the previous rule, stopping
// when it is within tol * |integral| or the next rule would pass max_eval; out = (integral, error, evaluations)
fn pcubature_1d(id: usize, lo: f64, hi: f64, tol: f64, max_eval: usize, out: []f64) {
    var prev = cc_estimate(id, lo, hi, 3usize)
    var n = 5usize
    var cur = cc_estimate(id, lo, hi, n)
    var er = math.abs[f64](cur - prev)
    while er > tol * math.abs[f64](cur) && n * 2usize - 1usize <= max_eval && n < 4097usize {
        prev = cur
        n = n * 2usize - 1usize
        cur = cc_estimate(id, lo, hi, n)
        er = math.abs[f64](cur - prev)
    }
    out[0usize] = cur
    out[1usize] = er
    out[2usize] = f64(n)
}
