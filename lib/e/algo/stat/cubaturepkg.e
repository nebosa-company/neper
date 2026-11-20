// R cubature: the integral of a fixed set of smooth integrands over a box in one to three dimensions, by a tensor Gauss-Legendre rule on a grid of sub-boxes.
// It reaches the same value hcubature and pcubature reach, to their tolerance; it is not the Genz-Malik or Clenshaw-Curtis recursion of the package.
//
// Not here: the adaptive subdivision, vector-valued integrands, the error estimate, infinite limits and user functions.

use e.math
use e.mem
use e.algo.stat.cubaturepkg_korobov as kt

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
    if id >= 100usize {
        // an infinite box seen through R's map x = tan(t): the integrand over atan(lo) .. atan(hi) is f(tan t) / prod(cos t)^2
        var pt: [8]f64 = zero
        var cp = 1.0f64
        var k = 0usize
        while k < d {
            pt[k] = math.tan[f64](p[k])
            cp = cp * math.cos[f64](p[k])
            k += 1usize
        }
        ret integrand(id - 100usize, d, pt[0usize..d]) / (cp * cp)
    }
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
    if id == 4usize { ret s * s * math.exp[f64](0.0f64 - s2) }
    if id >= 5usize && id <= 9usize {
        // the stress integrands: 5 a narrow peak exp(-50 sum (x - 0.5)^2), 6 a kink sum |x - 0.6|, 7 sin(8 sum x), 8 a step 1 (sum x < 1), 9 sqrt(sum x)
        // R sums in long double, so the terms are added in double-double and rounded once
        var terms: [8]f64 = zero
        var j = 0usize
        while j < d {
            terms[j] = p[j]
            if id == 5usize { terms[j] = (p[j] - 0.5f64) * (p[j] - 0.5f64) }
            if id == 6usize { terms[j] = math.abs[f64](p[j] - 0.6f64) }
            j += 1usize
        }
        var shi = 0.0f64
        var slo = 0.0f64
        j = 0usize
        while j < d {
            let t = shi + terms[j]
            let bb = t - shi
            slo += (shi - (t - bb)) + (terms[j] - bb)
            shi = t
            j += 1usize
        }
        let q = shi + slo
        if id == 7usize { ret math.sin[f64](8.0f64 * q) }
        if id == 9usize { ret math.sqrt[f64](q) }
        if id == 8usize {
            var step = 0.0f64
            if q < 1.0f64 { step = 1.0f64 }
            ret step
        }
        if id == 5usize { ret math.exp[f64](0.0f64 - 50.0f64 * q) }
        ret q
    }
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

// One Genz-Malik degree 7 / 5 rule on the box c +- hw (dimension d >= 2) as the C of cubature's hcubature applies it: val is the degree 7 estimate, err its distance to the degree 5 one and
// split the dimension of the largest fourth difference (the ratio is (lambda2 / lambda4)^2, as the package has it). Writes (val, err, split) to out.
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
    let ratio = (l2 * l2) / (l4 * l4)
    var p: [8]f64 = zero
    var i = 0usize
    while i < d {
        p[i] = c[i]
        i += 1usize
    }
    let f0 = integrand(id, d, p[0usize..d])
    var s2 = 0.0f64
    var s3 = 0.0f64
    var dif: [8]f64 = zero
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
        let df = math.abs[f64](u2 + v2 - 2.0f64 * f0 - ratio * (u3 + v3 - 2.0f64 * f0))
        dif[i] = df
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
    // Genz-Malik's split choice as the package makes it: the dimension of the largest fourth difference, unless another is within df = (sum of the errors) / (vol 10^dim) of the best so far, then the wider one
    var df0 = out[1usize]
    df0 = df0 / (vol * math.pow[f64](10.0f64, f64(d)))
    var maxdiff = 0.0f64
    var bi = 0usize
    i = 0usize
    while i < d {
        let delta = dif[i] - maxdiff
        if delta > df0 {
            maxdiff = dif[i]
            bi = i
        } else {
            if math.abs[f64](delta) <= df0 && hw[i] > hw[bi] { bi = i }
        }
        i += 1usize
    }
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

// cubature's binary max-heap of regions (hcubature.c heap_push, heap_pop; KEY the region's largest component error): ties between regions resolve as they do there
fn hp_push(hp: []usize, hn: usize, ky: []const f64, id: usize) -> usize {
    var ins = hn
    while ins > 0usize {
        let parent = (ins - 1usize) / 2usize
        if ky[id] <= ky[hp[parent]] { break }
        hp[ins] = hp[parent]
        ins = parent
    }
    hp[ins] = id
    ret hn + 1usize
}

fn hp_pop(hp: []usize, hn: usize, ky: []const f64) -> usize {
    let top = hp[0usize]
    let n = hn - 1usize
    hp[0usize] = hp[n]
    var i = 0usize
    while true {
        var child = i * 2usize + 1usize
        if child >= n { break }
        var largest = child
        if ky[hp[child]] <= ky[hp[i]] { largest = i }
        child += 1usize
        if child < n && ky[hp[largest]] < ky[hp[child]] { largest = child }
        if largest == i { break }
        let sw = hp[i]
        hp[i] = hp[largest]
        hp[largest] = sw
        i = largest
    }
    ret top
}

fn hv_key(er: []const f64, nc: usize, i: usize) -> f64 {
    var m = 0.0f64
    var k = 0usize
    while k < nc {
        if er[i * nc + k] > m { m = er[i * nc + k] }
        k += 1usize
    }
    ret m
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
    let (hp, e6) = mem.alloc[usize](a, cap)
    let (ky, e7) = mem.alloc[f64](a, cap)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret e1 }
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
    ky[0usize] = er[0usize]
    hp[0usize] = 0usize
    var hn = 1usize
    var tv = vv[0usize]
    var te = er[0usize]
    while true {
        if te <= tol * math.abs[f64](tv) || te <= 0.0f64 { break }
        if neval >= max_eval || n + 1usize >= cap { break }
        let k = hp_pop(hp, hn, ky)
        hn = hn - 1usize
        tv = tv - vv[k]
        te = te - er[k]
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
        ky[k] = er[k]
        hn = hp_push(hp, hn, ky, k)
        ky[n - 1usize] = er[n - 1usize]
        hn = hp_push(hp, hn, ky, n - 1usize)
        tv = tv + vv[k]
        te = te + er[k]
        tv = tv + vv[n - 1usize]
        te = te + er[n - 1usize]
        neval += 2usize * npts
    }
    tv = 0.0f64
    te = 0.0f64
    i = 0usize
    while i < hn {
        tv += vv[hp[i]]
        te += er[hp[i]]
        i += 1usize
    }
    out[0usize] = tv
    out[1usize] = te
    out[2usize] = f64(neval)
    out[3usize] = 0.0f64
    ret ok
}

// the Clenshaw-Curtis node cos(pi j / nn) as cubature tabulates it: symmetric about the middle node, which is exactly zero
fn cc_node(j: usize, nn: usize) -> f64 {
    if 2usize * j == nn { ret 0.0f64 }
    if 2usize * j > nn { ret 0.0f64 - cc_node(nn - j, nn) }
    ret math.cos[f64](3.141592653589793f64 * f64(j) / f64(nn))
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
        p[0usize] = (lo + hi) / 2.0f64 + (hi - lo) / 2.0f64 * cc_node(j, nn)
        total += wj * integrand(id, 1usize, p[0usize..1usize])
        j += 1usize
    }
    ret total * (hi - lo) / 2.0f64
}

// pcubature in one dimension: Clenshaw-Curtis rules of 3, 5, 9, 17, ... points (nested, so the evaluations are the points of the last rule), the error the distance to the previous rule (the
// 3 point rule to the midpoint rule); a rule is refined while the error is above tol * |integral| and its points beyond the first 3 do not pass max_eval; out = (integral, error, evaluations)
fn pcubature_1d(id: usize, lo: f64, hi: f64, tol: f64, max_eval: usize, out: []f64) {
    var n = 3usize
    var p1: [1]f64 = zero
    p1[0usize] = (lo + hi) / 2.0f64
    var prev = (hi - lo) * integrand(id, 1usize, p1[0usize..1usize])
    var cur = cc_estimate(id, lo, hi, n)
    var er = math.abs[f64](cur - prev)
    while er > tol * math.abs[f64](cur) && n - 3usize <= max_eval && n < 4097usize {
        prev = cur
        n = n * 2usize - 1usize
        cur = cc_estimate(id, lo, hi, n)
        er = math.abs[f64](cur - prev)
    }
    out[0usize] = cur
    out[1usize] = er
    out[2usize] = f64(n)
    out[3usize] = 0.0f64
    if er > tol * math.abs[f64](cur) && n - 3usize <= max_eval { out[3usize] = 1.0f64 }
}


// a vector integrand of nc components: id 0 (exp(-sum x^2), prod cos x), id 1 (1 / (1 + sum x), (sum x)^2 exp(-prod x), exp(-sum x^2)); answers the number of components
fn integrand_vec(id: usize, d: usize, p: []const f64, out: []f64) -> usize {
    if id >= 100usize {
        var pt: [8]f64 = zero
        var cp = 1.0f64
        var k = 0usize
        while k < d {
            pt[k] = math.tan[f64](p[k])
            cp = cp * math.cos[f64](p[k])
            k += 1usize
        }
        let nv = integrand_vec(id - 100usize, d, pt[0usize..d], out)
        k = 0usize
        while k < nv {
            out[k] = out[k] / (cp * cp)
            k += 1usize
        }
        ret nv
    }
    if id == 0usize {
        out[0usize] = integrand(0usize, d, p)
        out[1usize] = integrand(1usize, d, p)
        ret 2usize
    }
    if id == 2usize {
        // decaying components for infinite limits: exp(-sum x^2), (sum x)^2 exp(-sum x^2), exp(-sum x^2) prod cos x
        out[0usize] = integrand(0usize, d, p)
        out[1usize] = integrand(4usize, d, p)
        out[2usize] = integrand(0usize, d, p) * integrand(1usize, d, p)
        ret 3usize
    }
    out[0usize] = integrand(2usize, d, p)
    out[1usize] = integrand(3usize, d, p)
    out[2usize] = integrand(0usize, d, p)
    ret 3usize
}

// gk15_rule for a vector integrand of nc components: the values into out[0 .. nc), the errors into out[nc .. 2 nc), the split dimension 0 into out[2 nc]
fn gk15_rule_v(id: usize, nc: usize, c: []const f64, hw: []const f64, out: []f64) {
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
    var fv: [60]f64 = zero
    var p: [1]f64 = zero
    var tmp: [4]f64 = zero
    p[0usize] = c[0usize]
    let _a = integrand_vec(id, 1usize, p[0usize..1usize], tmp[0usize..4usize])
    var k = 0usize
    while k < nc {
        fv[7usize * nc + k] = tmp[k]
        k += 1usize
    }
    var j = 0usize
    while j < 7usize {
        p[0usize] = c[0usize] - hw[0usize] * xgk[j]
        let _b = integrand_vec(id, 1usize, p[0usize..1usize], tmp[0usize..4usize])
        k = 0usize
        while k < nc {
            fv[j * nc + k] = tmp[k]
            k += 1usize
        }
        p[0usize] = c[0usize] + hw[0usize] * xgk[j]
        let _c = integrand_vec(id, 1usize, p[0usize..1usize], tmp[0usize..4usize])
        k = 0usize
        while k < nc {
            fv[(14usize - j) * nc + k] = tmp[k]
            k += 1usize
        }
        j += 1usize
    }
    let eps = 2.220446049250313e-16f64
    k = 0usize
    while k < nc {
        let fc = fv[7usize * nc + k]
        var rk = wgk[7usize] * fc
        var rg = wg[3usize] * fc
        var ra = wgk[7usize] * math.abs[f64](fc)
        j = 0usize
        while j < 7usize {
            let u = fv[j * nc + k]
            let v = fv[(14usize - j) * nc + k]
            rk += wgk[j] * (u + v)
            ra += wgk[j] * (math.abs[f64](u) + math.abs[f64](v))
            if j % 2usize == 1usize { rg += wg[j / 2usize] * (u + v) }
            j += 1usize
        }
        let rmean = rk / 2.0f64
        var ras = wgk[7usize] * math.abs[f64](fc - rmean)
        j = 0usize
        while j < 7usize {
            ras += wgk[j] * (math.abs[f64](fv[j * nc + k] - rmean) + math.abs[f64](fv[(14usize - j) * nc + k] - rmean))
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
        if ra > 2.2250738585072014e-308f64 / (50.0f64 * eps) {
            let lw = eps * 50.0f64 * ra
            if lw > er { er = lw }
        }
        out[k] = rk * hw[0usize]
        out[nc + k] = er
        k += 1usize
    }
    out[2usize * nc] = 0.0f64
}

// gm_rule for a vector integrand: val and err of the nc components into out (2 nc entries), the split dimension (the largest sum over the components of the fourth differences) into split
fn gm_rule_v(id: usize, nc: usize, d: usize, c: []const f64, hw: []const f64, out: []f64) {
    if d == 1usize {
        gk15_rule_v(id, nc, c, hw, out)
        ret
    }
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
    let ratio = (l2 * l2) / (l4 * l4)
    var p: [8]f64 = zero
    var f0: [4]f64 = zero
    var u2: [4]f64 = zero
    var v2: [4]f64 = zero
    var u3: [4]f64 = zero
    var v3: [4]f64 = zero
    var s2: [4]f64 = zero
    var s3: [4]f64 = zero
    var s4: [4]f64 = zero
    var s5: [4]f64 = zero
    var tmp: [4]f64 = zero
    var i = 0usize
    while i < d {
        p[i] = c[i]
        i += 1usize
    }
    let _n0 = integrand_vec(id, d, p[0usize..d], f0[0usize..4usize])
    var dif: [8]f64 = zero
    i = 0usize
    while i < d {
        p[i] = c[i] + l2 * hw[i]
        let _a = integrand_vec(id, d, p[0usize..d], u2[0usize..4usize])
        p[i] = c[i] - l2 * hw[i]
        let _b = integrand_vec(id, d, p[0usize..d], v2[0usize..4usize])
        p[i] = c[i] + l4 * hw[i]
        let _c = integrand_vec(id, d, p[0usize..d], u3[0usize..4usize])
        p[i] = c[i] - l4 * hw[i]
        let _e = integrand_vec(id, d, p[0usize..d], v3[0usize..4usize])
        p[i] = c[i]
        var df = 0.0f64
        var k = 0usize
        while k < nc {
            s2[k] += u2[k] + v2[k]
            s3[k] += u3[k] + v3[k]
            df += math.abs[f64](u2[k] + v2[k] - 2.0f64 * f0[k] - ratio * (u3[k] + v3[k] - 2.0f64 * f0[k]))
            k += 1usize
        }
        dif[i] = df
        i += 1usize
    }
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
                    let _f = integrand_vec(id, d, p[0usize..d], tmp[0usize..4usize])
                    var k = 0usize
                    while k < nc {
                        s4[k] += tmp[k]
                        k += 1usize
                    }
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
    var kk = 0usize
    while f64(kk) < twopn {
        i = 0usize
        while i < d {
            if (kk / (1usize << i)) % 2usize == 1usize { p[i] = c[i] + l5 * hw[i] } else { p[i] = c[i] - l5 * hw[i] }
            i += 1usize
        }
        let _g = integrand_vec(id, d, p[0usize..d], tmp[0usize..4usize])
        var k = 0usize
        while k < nc {
            s5[k] += tmp[k]
            k += 1usize
        }
        kk += 1usize
    }
    var vol = 1.0f64
    i = 0usize
    while i < d {
        vol *= 2.0f64 * hw[i]
        i += 1usize
    }
    var dsum = 0.0f64
    var k = 0usize
    while k < nc {
        let res = vol * (w1 * f0[k] + w2 * s2[k] + w3 * s3[k] + w4 * s4[k] + w5 * s5[k])
        let res5 = vol * (we1 * f0[k] + we2 * s2[k] + we3 * s3[k] + we4 * s4[k])
        out[k] = res
        out[nc + k] = math.abs[f64](res5 - res)
        dsum += out[nc + k]
        k += 1usize
    }
    // Genz-Malik's split choice as the package makes it: the dimension of the largest fourth difference, unless another is within df = (sum of the errors) / (vol 10^dim) of the best so far, then the wider one
    var df0 = dsum
    df0 = df0 / (vol * math.pow[f64](10.0f64, f64(d)))
    var maxdiff = 0.0f64
    var bi = 0usize
    i = 0usize
    while i < d {
        let delta = dif[i] - maxdiff
        if delta > df0 {
            maxdiff = dif[i]
            bi = i
        } else {
            if math.abs[f64](delta) <= df0 && hw[i] > hw[bi] { bi = i }
        }
        i += 1usize
    }
    out[2usize * nc] = f64(bi)
}

// hcubature for the vector integrand id (2 to 7 dimensions): a region is ranked by its largest component error and the run stops when every component is within tol * |its integral|;
// out = (the nc integrals, the nc errors, the evaluations)
fn hcubature_gm_v(a: *mem.Arena, id: usize, d: usize, lo: []const f64, hi: []const f64, tol: f64, max_eval: usize, out: []f64) -> err {
    var pp: [8]f64 = zero
    var probe: [4]f64 = zero
    let nc = integrand_vec(id, d, pp[0usize..d], probe[0usize..4usize])
    var npts = 1usize + 4usize * d + 2usize * d * (d - 1usize)
    npts += 1usize << d
    if d == 1usize { npts = 15usize }
    let cap = 2usize + max_eval / npts
    let (cc, e1) = mem.alloc[f64](a, cap * d)
    let (hh, e2) = mem.alloc[f64](a, cap * d)
    let (vv, e3) = mem.alloc[f64](a, cap * nc)
    let (er, e4) = mem.alloc[f64](a, cap * nc)
    let (sd, e5) = mem.alloc[usize](a, cap)
    let (hp, e6) = mem.alloc[usize](a, cap)
    let (ky, e7) = mem.alloc[f64](a, cap)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret e1 }
    var r: [8]f64 = zero
    var i = 0usize
    while i < d {
        cc[i] = (lo[i] + hi[i]) / 2.0f64
        hh[i] = (hi[i] - lo[i]) / 2.0f64
        i += 1usize
    }
    gm_rule_v(id, nc, d, cc[0usize..d], hh[0usize..d], r[0usize..8usize])
    var k = 0usize
    while k < nc {
        vv[k] = r[k]
        er[k] = r[nc + k]
        k += 1usize
    }
    sd[0usize] = usize(r[2usize * nc])
    var n = 1usize
    var neval = npts
    ky[0usize] = hv_key(er, nc, 0usize)
    hp[0usize] = 0usize
    var hn = 1usize
    var tv: [4]f64 = zero
    var te: [4]f64 = zero
    k = 0usize
    while k < nc {
        tv[k] = vv[k]
        te[k] = er[k]
        k += 1usize
    }
    while true {
        var conv = true
        k = 0usize
        while k < nc {
            if !(te[k] <= tol * math.abs[f64](tv[k])) { conv = false }
            k += 1usize
        }
        if conv || neval >= max_eval || n + 1usize >= cap { break }
        let kb = hp_pop(hp, hn, ky)
        hn = hn - 1usize
        k = 0usize
        while k < nc {
            tv[k] = tv[k] - vv[kb * nc + k]
            te[k] = te[k] - er[kb * nc + k]
            k += 1usize
        }
        let dim = sd[kb]
        var ch: [8]f64 = zero
        var hw2: [8]f64 = zero
        i = 0usize
        while i < d {
            hw2[i] = hh[kb * d + i]
            ch[i] = cc[kb * d + i]
            i += 1usize
        }
        hw2[dim] = hw2[dim] / 2.0f64
        i = 0usize
        while i < d {
            cc[kb * d + i] = ch[i]
            hh[kb * d + i] = hw2[i]
            cc[n * d + i] = ch[i]
            hh[n * d + i] = hw2[i]
            i += 1usize
        }
        cc[kb * d + dim] = ch[dim] - hw2[dim]
        cc[n * d + dim] = ch[dim] + hw2[dim]
        gm_rule_v(id, nc, d, cc[kb * d..kb * d + d], hh[kb * d..kb * d + d], r[0usize..8usize])
        k = 0usize
        while k < nc {
            vv[kb * nc + k] = r[k]
            er[kb * nc + k] = r[nc + k]
            k += 1usize
        }
        sd[kb] = usize(r[2usize * nc])
        gm_rule_v(id, nc, d, cc[n * d..n * d + d], hh[n * d..n * d + d], r[0usize..8usize])
        k = 0usize
        while k < nc {
            vv[n * nc + k] = r[k]
            er[n * nc + k] = r[nc + k]
            k += 1usize
        }
        sd[n] = usize(r[2usize * nc])
        n += 1usize
        ky[kb] = hv_key(er, nc, kb)
        hn = hp_push(hp, hn, ky, kb)
        ky[n - 1usize] = hv_key(er, nc, n - 1usize)
        hn = hp_push(hp, hn, ky, n - 1usize)
        k = 0usize
        while k < nc {
            tv[k] = tv[k] + vv[kb * nc + k]
            te[k] = te[k] + er[kb * nc + k]
            tv[k] = tv[k] + vv[(n - 1usize) * nc + k]
            te[k] = te[k] + er[(n - 1usize) * nc + k]
            k += 1usize
        }
        neval += 2usize * npts
    }
    k = 0usize
    while k < nc {
        tv[k] = 0.0f64
        te[k] = 0.0f64
        k += 1usize
    }
    i = 0usize
    while i < hn {
        k = 0usize
        while k < nc {
            tv[k] += vv[hp[i] * nc + k]
            te[k] += er[hp[i] * nc + k]
            k += 1usize
        }
        i += 1usize
    }
    k = 0usize
    while k < nc {
        out[k] = tv[k]
        out[nc + k] = te[k]
        k += 1usize
    }
    out[2usize * nc] = f64(neval)
    out[2usize * nc + 1usize] = 0.0f64
    ret ok
}

// the tensor Clenshaw-Curtis estimate of integrand id over the box lo..hi with sz[i] points (2^k + 1) in dimension i
fn cc_tensor(id: usize, d: usize, lo: []const f64, hi: []const f64, sz: []const usize) -> f64 {
    var total = 1usize
    var i = 0usize
    while i < d {
        total *= sz[i]
        i += 1usize
    }
    var wts: [8][1100]f64 = zero
    var nds: [8][1100]f64 = zero
    let pi = 3.141592653589793f64
    i = 0usize
    while i < d {
        let nn = sz[i] - 1usize
        if nn == 0usize {
            wts[i][0usize] = hi[i] - lo[i]
            nds[i][0usize] = (lo[i] + hi[i]) / 2.0f64
            i += 1usize
            continue
        }
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
            wts[i][j] = wj * (hi[i] - lo[i]) / 2.0f64
            nds[i][j] = (lo[i] + hi[i]) / 2.0f64 + (hi[i] - lo[i]) / 2.0f64 * cc_node(j, nn)
            j += 1usize
        }
        i += 1usize
    }
    var sum = 0.0f64
    var cell = 0usize
    while cell < total {
        var rem = cell
        var w = 1.0f64
        var p: [8]f64 = zero
        i = 0usize
        while i < d {
            let ix = rem % sz[i]
            rem = rem / sz[i]
            w *= wts[i][ix]
            p[i] = nds[i][ix]
            i += 1usize
        }
        sum += w * integrand(id, d, p[0usize..d])
        cell += 1usize
    }
    ret sum
}

// pcubature for d >= 2 dimensions without box splitting: tensor Clenshaw-Curtis rules whose per-dimension sizes start at 3 points; the error is the largest over the dimensions of the distance to
// the rule with that dimension one level lower (3 to the midpoint, 5 to 3, 9 to 5, ...), the dimension with the largest one grows to the next size, until the error is within tol * |integral|
// or the points beyond the first 3^d would pass max_eval; out = (integral, error, evaluations = the product of the sizes)
fn pcubature_nd(id: usize, d: usize, lo: []const f64, hi: []const f64, tol: f64, max_eval: usize, out: []f64) {
    var sz: [8]usize = zero
    var base = 1usize
    var i = 0usize
    while i < d {
        sz[i] = 3usize
        base *= 3usize
        i += 1usize
    }
    var it = 0usize
    while it < 60usize {
        let val = cc_tensor(id, d, lo, hi, sz[0usize..d])
        var best = 0.0f64 - 1.0f64
        var bi = 0usize
        i = 0usize
        while i < d {
            var lower: [8]usize = zero
            var c = 0usize
            while c < d {
                lower[c] = sz[c]
                c += 1usize
            }
            lower[i] = (sz[i] - 1usize) / 2usize + 1usize
            if sz[i] == 3usize { lower[i] = 1usize }
            let e = math.abs[f64](val - cc_tensor(id, d, lo, hi, lower[0usize..d]))
            if e > best {
                best = e
                bi = i
            }
            i += 1usize
        }
        var ev = 1usize
        i = 0usize
        while i < d {
            ev *= sz[i]
            i += 1usize
        }
        if best <= tol * math.abs[f64](val) || ev - base > max_eval || ev > 300000usize {
            out[0usize] = val
            out[1usize] = best
            out[2usize] = f64(ev)
            out[3usize] = 0.0f64
            if best > tol * math.abs[f64](val) && ev - base <= max_eval { out[3usize] = 1.0f64 }
            ret
        }
        sz[bi] = (sz[bi] - 1usize) * 2usize + 1usize
        it += 1usize
    }
    out[0usize] = 0.0f64 / 0.0f64
    out[1usize] = 0.0f64
    out[2usize] = 0.0f64
    out[3usize] = 1.0f64
}
// the tensor Clenshaw-Curtis estimate of every component of the vector integrand id over the box lo..hi with sz[i] points in dimension i; the nc values into out
fn cc_tensor_v(id: usize, d: usize, lo: []const f64, hi: []const f64, sz: []const usize, nc: usize, out: []f64) {
    var total = 1usize
    var i = 0usize
    while i < d {
        total *= sz[i]
        i += 1usize
    }
    var wts: [8][1100]f64 = zero
    var nds: [8][1100]f64 = zero
    let pi = 3.141592653589793f64
    i = 0usize
    while i < d {
        let nn = sz[i] - 1usize
        if nn == 0usize {
            wts[i][0usize] = hi[i] - lo[i]
            nds[i][0usize] = (lo[i] + hi[i]) / 2.0f64
            i += 1usize
            continue
        }
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
            wts[i][j] = wj * (hi[i] - lo[i]) / 2.0f64
            nds[i][j] = (lo[i] + hi[i]) / 2.0f64 + (hi[i] - lo[i]) / 2.0f64 * cc_node(j, nn)
            j += 1usize
        }
        i += 1usize
    }
    var c = 0usize
    while c < nc {
        out[c] = 0.0f64
        c += 1usize
    }
    var fv: [4]f64 = zero
    var cell = 0usize
    while cell < total {
        var rem = cell
        var w = 1.0f64
        var p: [8]f64 = zero
        i = 0usize
        while i < d {
            let ix = rem % sz[i]
            rem = rem / sz[i]
            w *= wts[i][ix]
            p[i] = nds[i][ix]
            i += 1usize
        }
        let _n = integrand_vec(id, d, p[0usize..d], fv[0usize..4usize])
        c = 0usize
        while c < nc {
            out[c] += w * fv[c]
            c += 1usize
        }
        cell += 1usize
    }
}

// pcubature of a vector integrand (error norm individual, absError 2.2e-14): the per-component error is the largest distance to the one-level-lower rule over the dimensions, the dimension to grow the one with the
// largest distance over the components; out = (integrals nc, errors nc, evaluations)
fn pcubature_nd_v(id: usize, d: usize, lo: []const f64, hi: []const f64, tol: f64, max_eval: usize, out: []f64) {
    var probe: [8]f64 = zero
    var pp: [8]f64 = zero
    var i = 0usize
    while i < d {
        pp[i] = (lo[i] + hi[i]) / 2.0f64
        i += 1usize
    }
    let nc = integrand_vec(id, d, pp[0usize..d], probe[0usize..8usize])
    var sz: [8]usize = zero
    var base = 1usize
    i = 0usize
    while i < d {
        sz[i] = 3usize
        base *= 3usize
        i += 1usize
    }
    var val: [4]f64 = zero
    var val1: [4]f64 = zero
    var ers: [4]f64 = zero
    var it = 0usize
    while it < 60usize {
        cc_tensor_v(id, d, lo, hi, sz[0usize..d], nc, val[0usize..4usize])
        var c = 0usize
        while c < nc {
            ers[c] = 0.0f64
            c += 1usize
        }
        var best = 0.0f64
        var bi = 0usize
        i = 0usize
        while i < d {
            var lower: [8]usize = zero
            var k = 0usize
            while k < d {
                lower[k] = sz[k]
                k += 1usize
            }
            lower[i] = (sz[i] - 1usize) / 2usize + 1usize
            if sz[i] == 3usize { lower[i] = 1usize }
            cc_tensor_v(id, d, lo, hi, lower[0usize..d], nc, val1[0usize..4usize])
            var emax = 0.0f64
            c = 0usize
            while c < nc {
                let e = math.abs[f64](val[c] - val1[c])
                if e > emax { emax = e }
                if e > ers[c] { ers[c] = e }
                c += 1usize
            }
            if emax > best {
                best = emax
                bi = i
            }
            i += 1usize
        }
        var ev = 1usize
        i = 0usize
        while i < d {
            ev *= sz[i]
            i += 1usize
        }
        var done = true
        c = 0usize
        while c < nc {
            if ers[c] > 2.220446049250313e-14f64 && ers[c] > math.abs[f64](val[c]) * tol { done = false }
            c += 1usize
        }
        if done || ev - base > max_eval || ev > 300000usize {
            c = 0usize
            while c < nc {
                out[c] = val[c]
                out[nc + c] = ers[c]
                c += 1usize
            }
            out[2usize * nc] = f64(ev)
            out[2usize * nc + 1usize] = 0.0f64
            if !done && ev - base <= max_eval { out[2usize * nc + 1usize] = 1.0f64 }
            ret
        }
        sz[bi] = (sz[bi] - 1usize) * 2usize + 1usize
        it += 1usize
    }
    out[2usize * nc + 1usize] = 1.0f64
}

// the Cuhre rule constants (Cuba cuhre/Rule.c): key 13, 11, 9 or 7; w gets the weight table, g the generators
fn cu_tab(key: usize, w: []f64, g: []f64) {
    if key == 13usize {
        w[0usize] = 0.00844923090033615f64
        w[1usize] = 0.3213775489050763f64
        w[2usize] = 0.3372900883288987f64
        w[3usize] = (0.0f64 - 0.8264123822525677f64)
        w[4usize] = 0.6539094339575232f64
        w[5usize] = 0.023771474018994404f64
        w[6usize] = (0.0f64 - 0.1767341636743844f64)
        w[7usize] = (0.0f64 - 0.1644903060344491f64)
        w[8usize] = 0.306583861409436f64
        w[9usize] = (0.0f64 - 0.2041614154424632f64)
        w[10usize] = 0.02940016170142405f64
        w[11usize] = 0.07347600537466073f64
        w[12usize] = 0.07707849911634623f64
        w[13usize] = 0.002389292538329435f64
        w[14usize] = (0.0f64 - 0.174698151579499f64)
        w[15usize] = 0.006644436465817374f64
        w[16usize] = (0.0f64 - 0.03638022004364754f64)
        w[17usize] = (0.0f64 - 0.03804478358506311f64)
        w[18usize] = (0.0f64 - 0.1343024157997222f64)
        w[19usize] = 0.03937939671417803f64
        w[20usize] = 0.0042536044255016f64
        w[21usize] = 0.021252979220987123f64
        w[22usize] = 0.02223559940380806f64
        w[23usize] = 0.08833366840533902f64
        w[24usize] = 0.006974520545933992f64
        w[25usize] = 0.0f64
        w[26usize] = 0.1460984204026913f64
        w[27usize] = 0.1480693879765931f64
        w[28usize] = 0.0f64
        w[29usize] = 0.0f64
        w[30usize] = 0.0040664827465935255f64
        w[31usize] = 0.017476132861520992f64
        w[32usize] = 4.467143702185815e-6f64
        w[33usize] = 0.0009786283074168292f64
        w[34usize] = 0.0066677021717782585f64
        w[35usize] = 0.03362231646315497f64
        w[36usize] = 0.1444954045641582f64
        w[37usize] = 0.150894476707413f64
        w[38usize] = (0.0f64 - 0.1319227889147519f64)
        w[39usize] = 0.05512960621544304f64
        w[40usize] = 0.033200804136503725f64
        w[41usize] = 0.0001307687976001325f64
        w[42usize] = 3.6472001075162155e-5f64
        w[43usize] = 0.00799001220015063f64
        w[44usize] = 0.05443846381278608f64
        w[45usize] = 0.014093686924979677f64
        w[46usize] = 0.0005380992313941161f64
        w[47usize] = 0.000577719899901388f64
        w[48usize] = 0.0033917470797606257f64
        w[49usize] = 0.02310903863953934f64
        w[50usize] = 0.000977069770327625f64
        w[51usize] = 0.0001042259576889814f64
        w[52usize] = 0.0001041757313688177f64
        w[53usize] = 0.0022949157182832643f64
        w[54usize] = 0.01506937747477189f64
        w[55usize] = 0.007531996943580376f64
        w[56usize] = (0.0f64 - 0.001401152865045733f64)
        w[57usize] = (0.0f64 - 0.001452822267047819f64)
        w[58usize] = (0.0f64 - 0.01358584986119197f64)
        w[59usize] = (0.0f64 - 0.060570216489018905f64)
        w[60usize] = 0.02577183086722915f64
        w[61usize] = 0.008041788181514763f64
        w[62usize] = 0.008338339968783704f64
        w[63usize] = 0.04025866859057809f64
        w[64usize] = 0.04225737654686337f64
        w[65usize] = 0.015625f64
        w[66usize] = (0.0f64 - 0.1420416552759383f64)
        w[67usize] = (0.0f64 - 0.147279632923196f64)
        w[68usize] = 0.003760268580063992f64
        w[69usize] = 0.02561989142123099f64
        g[0usize] = 0.12585646717265545f64
        g[1usize] = 0.3506966822267133f64
        g[2usize] = 0.4795480315809981f64
        g[3usize] = 0.4978005239276064f64
        g[4usize] = 0.25f64
        g[5usize] = 0.07972723291487795f64
        g[6usize] = 0.1904495567970094f64
        g[7usize] = 0.3291384627633596f64
        g[8usize] = 0.43807365825146577f64
        g[9usize] = 0.499121592026599f64
        g[10usize] = 0.4895111329084231f64
        g[11usize] = 0.32461421628226944f64
        g[12usize] = 0.43637106005656195f64
        g[13usize] = 0.1791307322940614f64
        g[14usize] = 0.2833333333333333f64
        g[15usize] = 0.1038888888888889f64
        ret
    }
    if key == 11usize {
        w[0usize] = 0.0009903847688882167f64
        w[1usize] = 1.715006248224684f64
        w[2usize] = 1.936014978949526f64
        w[3usize] = 0.517082819560576f64
        w[4usize] = 2.05440450381852f64
        w[5usize] = 0.0084964717409851f64
        w[6usize] = (0.0f64 - 0.3755893815889209f64)
        w[7usize] = (0.0f64 - 0.3673449403754268f64)
        w[8usize] = 0.01445269144914044f64
        w[9usize] = 0.013777599884901202f64
        w[10usize] = 0.00013587331735072814f64
        w[11usize] = 0.1488632145140549f64
        w[12usize] = 0.02929778657898176f64
        w[13usize] = (0.0f64 - 0.3601489663995932f64)
        w[14usize] = (0.0f64 - 0.576806291790441f64)
        w[15usize] = 0.022982920777660364f64
        w[16usize] = (0.0f64 - 0.2497046640620823f64)
        w[17usize] = (0.0f64 - 0.1151883520260315f64)
        w[18usize] = 0.3628307003418485f64
        w[19usize] = 0.03726835047700328f64
        w[20usize] = 0.004202649722286289f64
        w[21usize] = 0.1792501419135204f64
        w[22usize] = 0.05086658220872218f64
        w[23usize] = 0.007148802650872729f64
        w[24usize] = 0.0068148789397772195f64
        w[25usize] = 0.0012671889041675774f64
        w[26usize] = 0.0034461267589738897f64
        w[27usize] = 0.04453911087786469f64
        w[28usize] = (0.0f64 - 0.09222852896022966f64)
        w[29usize] = 0.057231697338518496f64
        w[30usize] = 0.0002109560854981544f64
        w[31usize] = (0.0f64 - 0.005140483185555825f64)
        w[32usize] = (0.0f64 - 0.022878282571259f64)
        w[33usize] = 0.01719339732471725f64
        w[34usize] = (0.0f64 - 0.044930187438112855f64)
        w[35usize] = 0.016830857056410086f64
        w[36usize] = 0.006536017839876424f64
        w[37usize] = 0.02908926216345833f64
        w[38usize] = (0.0f64 - 0.102141653746035f64)
        w[39usize] = 0.027292365738663484f64
        w[40usize] = 0.00021876823557504823f64
        w[41usize] = (0.0f64 - 0.00065134549392297f64)
        w[42usize] = (0.0f64 - 0.002898884350669207f64)
        w[43usize] = (0.0f64 - 0.007504397861080493f64)
        w[44usize] = 0.000354747395055699f64
        w[45usize] = 0.009690420479796819f64
        w[46usize] = (0.0f64 - 0.006304672433547204f64)
        w[47usize] = (0.0f64 - 0.028059634133074954f64)
        w[48usize] = 0.01648362537726711f64
        w[49usize] = 0.01571366799739551f64
        w[50usize] = 0.030773311284628138f64
        w[51usize] = 0.01266959399788263f64
        w[52usize] = 0.05638741361145884f64
        w[53usize] = 0.05234610158469334f64
        w[54usize] = 0.049900992192785674f64
        w[55usize] = 0.0084974310856038f64
        w[56usize] = (0.0f64 - 0.005454241018647931f64)
        w[57usize] = (0.0f64 - 0.02427469611942451f64)
        w[58usize] = 0.014454323316130661f64
        w[59usize] = 0.0137791555266677f64
        w[60usize] = 0.0017749535291258914f64
        w[61usize] = 0.004826995274768427f64
        w[62usize] = 0.021483070341828822f64
        w[63usize] = 0.003019236275367777f64
        w[64usize] = 0.0028782064230998723f64
        g[0usize] = 0.095f64
        g[1usize] = 0.25f64
        g[2usize] = 0.375f64
        g[3usize] = 0.4f64
        g[4usize] = 0.4975f64
        g[5usize] = 0.49936724991757f64
        g[6usize] = 0.38968518428362114f64
        g[7usize] = 0.49998494965443835f64
        g[8usize] = 0.3951318612385894f64
        g[9usize] = 0.22016983438253684f64
        g[10usize] = 0.4774686911397297f64
        g[11usize] = 0.2189239229503431f64
        g[12usize] = 0.4830546566815374f64
        g[13usize] = 0.2288552938881567f64
        ret
    }
    if key == 9usize {
        w[0usize] = (0.0f64 - 0.002361170967785511788400941242259231309691f64)
        w[1usize] = 0.1141539002385732526821323741697655347686f64
        w[2usize] = (0.0f64 - 0.6383392007670238909386026193674701393074f64)
        w[3usize] = 0.7484998850468520800423030047583803945205f64
        w[4usize] = (0.0f64 - 0.001432401703339912514196154599769007103671f64)
        w[5usize] = 0.05747150786448972594860897296200006759892f64
        w[6usize] = (0.0f64 - 0.1422510457143424323449521620935950679394f64)
        w[7usize] = (0.0f64 - 0.06287502873828697998942424881040490136987f64)
        w[8usize] = 0.2545911332489590890011611142429070613156f64
        w[9usize] = (0.0f64 - 1.207328566678236261002219995185143356737f64)
        w[10usize] = 0.8956736576416067650809467826488567200939f64
        w[11usize] = (0.0f64 - 0.3647935698604914666100134551377381205297f64)
        w[12usize] = 0.003541756451678267682601411863388846964536f64
        w[13usize] = (0.0f64 - 0.07260936739589367960492815865074633743652f64)
        w[14usize] = 0.1055749162521899101218622863269817454540f64
        w[15usize] = 0.002148602555009868771294231899653510655506f64
        w[16usize] = (0.0f64 - 0.03226856389295394999786630399875134318006f64)
        w[17usize] = 0.01063678399023121748083624225818915724455f64
        w[18usize] = 0.01468910249614349017540783437728097691502f64
        w[19usize] = 0.5113470834646759143109387357149329909126f64
        w[20usize] = 0.4597644812080634464633352781605214342691f64
        w[21usize] = 0.1823967849302457333050067275688690602649f64
        w[22usize] = (0.0f64 - 0.04508628929435784075980562738240804429658f64)
        w[23usize] = 0.2141588352435279340097929526588394300172f64
        w[24usize] = (0.0f64 - 0.02735154652654564472203690086290223507436f64)
        w[25usize] = 0.05494106704871123410060080562462135546101f64
        w[26usize] = 0.1193759620257077529708962121565290178730f64
        w[27usize] = 0.6508951939192025059314756320878023215278f64
        w[28usize] = 0.1474493982943446016775696826942585013243f64
        w[29usize] = 0.05769338449097348357291272840392627722165f64
        w[30usize] = 0.03499962660214358382244159694487155861542f64
        w[31usize] = (0.0f64 - 1.386862771927828143599782668709014266770f64)
        w[32usize] = (0.0f64 - 0.2386668732575008878964134721962088068396f64)
        w[33usize] = 0.01553241727660705326386197156586357005224f64
        w[34usize] = 0.003532809960709087023561817517751309380604f64
        w[35usize] = 0.09231719987444221619017126187763868745587f64
        w[36usize] = 0.02254314464717892037990281369120402214829f64
        w[37usize] = 0.01367577326327282236101845043145111753718f64
        w[38usize] = (0.0f64 - 0.3254475969596012529657378160439011607639f64)
        w[39usize] = 0.001770878225839133841300705931694423482268f64
        w[40usize] = 0.001074301277504934385647115949826755327753f64
        w[41usize] = 0.2515001149531479199576969952416196054795f64
        g[0usize] = 0.4779536579022695061928604197171830064732f64
        g[1usize] = 0.2030285873691198677998034402373279133258f64
        g[2usize] = 0.4476273546261781288207704806530998539285f64
        g[3usize] = 0.125f64
        g[4usize] = 0.3430378987808781457001426145164678603407f64
        ret
    }
    if key == 7usize {
        w[0usize] = 0.01941786667474838842844534313920462333850f64
        w[1usize] = (0.0f64 - 0.4038525770115018254611834753723880293161f64)
        w[2usize] = 0.6448566876746598222277360730193089551024f64
        w[3usize] = 0.01177982690775806141012214458820955067854f64
        w[4usize] = (0.0f64 - 0.1804131874073360901182293138710989490609f64)
        w[5usize] = (0.0f64 - 0.08878582808133504444306598174517276122439f64)
        w[6usize] = 0.05632864580828594137378124255408286479947f64
        w[7usize] = (0.0f64 - 0.009708933337374194214222671569602311669249f64)
        w[8usize] = (0.0f64 - 0.9912917677958235813775106862002319060386f64)
        w[9usize] = (0.0f64 - 0.1775716561626700888861319634903455224488f64)
        w[10usize] = 0.1235939803204323357183625846672135876752f64
        w[11usize] = 0.07497814870203369068087999555157339703666f64
        w[12usize] = 0.5548914705142355977605994477355651401434f64
        w[13usize] = 0.08804124152269277122645182458858273865209f64
        w[14usize] = 0.02111835845551338508329573367808085283304f64
        w[15usize] = (0.0f64 - 0.009930220323965333308685820460105538586058f64)
        w[16usize] = (0.0f64 - 0.06410005328501090417895544042025034295870f64)
        w[17usize] = 0.03038172903822100765927778829870429682489f64
        w[18usize] = 0.005889913453879030705061072294104775339268f64
        w[19usize] = (0.0f64 - 0.004854466668687097107111335784801155834624f64)
        w[20usize] = 0.3551433123253401777722639269806910448976f64
        g[0usize] = 0.4779536579022695061928604197171830064732f64
        g[1usize] = 0.2030285873691198677998034402373279133258f64
        g[2usize] = 0.375f64
        g[3usize] = 0.3430378987808781457001426145164678603407f64
        ret
    }
}

// Cuba Erf (Takuya Ooura's gamerf2a) and the chi-square cdf of Cuba's ChiSquare.c
fn cu_erfc(x: f64) -> f64 {
    var c: [18]f64 = zero
    c[0usize] = 2.96316885199227378e-01f64
    c[1usize] = 6.12158644495538758e-02f64
    c[2usize] = 1.81581125134637070e-01f64
    c[3usize] = 5.50942780056002085e-01f64
    c[4usize] = 6.81866451424939493e-02f64
    c[5usize] = 1.53039662058770397e+00f64
    c[6usize] = 1.56907543161966709e-02f64
    c[7usize] = 2.99957952311300634e+00f64
    c[8usize] = 2.21290116681517573e-03f64
    c[9usize] = 4.95867777128246701e+00f64
    c[10usize] = 1.91395813098742864e-04f64
    c[11usize] = 7.41471251099335407e+00f64
    c[12usize] = 9.71013284010551623e-06f64
    c[13usize] = 1.04765104356545238e+01f64
    c[14usize] = 1.66642447174307753e-07f64
    c[15usize] = 1.48455557345597957e+01f64
    c[16usize] = 6.10399733098688199e+00f64
    c[17usize] = 1.26974899965115684e+01f64
    var y = x * x
    y = math.exp[f64](0.0f64 - y) * x * (c[0usize] / (y + c[1usize]) + c[2usize] / (y + c[3usize]) + c[4usize] / (y + c[5usize]) + c[6usize] / (y + c[7usize]) + c[8usize] / (y + c[9usize]) + c[10usize] / (y + c[11usize]) + c[12usize] / (y + c[13usize]) + c[14usize] / (y + c[15usize]))
    if x < c[16usize] { y += 2.0f64 / (math.exp[f64](c[17usize] * x) + 1.0f64) }
    ret y
}

fn cu_erf(x: f64) -> f64 {
    var c: [6]f64 = zero
    c[0usize] = 1.12837916709551257e+00f64
    c[1usize] = 0.0f64 - 3.76126389031833602e-01f64
    c[2usize] = 1.12837916706621301e-01f64
    c[3usize] = 0.0f64 - 2.68661698447642378e-02f64
    c[4usize] = 5.22387877685618101e-03f64
    c[5usize] = 0.0f64 - 8.49202435186918470e-04f64
    var y = math.abs[f64](x)
    if y > 0.125f64 {
        y = 1.0f64 - cu_erfc(y)
        if x > 0.0f64 { ret y }
        ret 0.0f64 - y
    }
    y = y * y
    ret x * (c[0usize] + y * (c[1usize] + y * (c[2usize] + y * (c[3usize] + y * (c[4usize] + y * c[5usize])))))
}

fn cu_chisq(x: f64, df: i64) -> f64 {
    if df <= 0i64 { ret 0.0f64 - 999.0f64 }
    if x <= 0.0f64 { ret 0.0f64 }
    if x > 1000.0f64 * f64(df) { ret 1.0f64 }
    if df > 1000i64 {
        if x < 2.0f64 { ret 0.0f64 }
        var yy = 2.0f64 / (9.0f64 * f64(df))
        yy = (math.pow[f64](x / f64(df), 1.0f64 / 3.0f64) - (1.0f64 - yy)) / math.sqrt[f64](yy)
        if yy > 5.0f64 { ret 1.0f64 }
        if yy < 0.0f64 - 18.8055f64 { ret 0.0f64 }
        ret 0.5f64 * cu_erf(yy / 1.414213562373095048801689f64) + 0.5f64
    }
    var y = 0.5f64 * x
    if (df & 1i64) == 1i64 {
        let sq = math.sqrt[f64](y)
        var h = cu_erf(sq)
        if df == 1i64 { ret h }
        y = sq * math.exp[f64](0.0f64 - y) / 0.8862269254527579825931f64
        var i = 3i64
        while i < df {
            h -= y
            y *= x / f64(i)
            i += 2i64
        }
        y = h - y
    } else {
        var term = math.exp[f64](0.0f64 - y)
        var sum = term
        var i = 1i64
        while i < df / 2i64 {
            term *= y / f64(i)
            sum += term
            i += 1i64
        }
        y = 1.0f64 - sum
    }
    if y > 0.0f64 { ret y }
    ret 0.0f64
}

// the Cuhre sampler state: the integrand map from the unit cube (finite limits an affine map, otherwise the atan map of the R wrapper), the rule (sets, weights, null-rule scales and norms, generators) and the frame
type Cu = struct { id: usize, vec: usize, nc: usize, d: usize, inf: usize, lo: [8]f64, r: [8]f64, prodr: f64, rn: usize, ns: usize, sn: []usize, wt: []f64, sc: []f64, nm: []f64, gen: []f64, e0: f64, e1: f64, e2: f64, x: []f64, f: []f64, neval: usize }

fn cu_eval(p: *Cu, x: []const f64, out: []f64) {
    var y: [8]f64 = zero
    var pt: [8]f64 = zero
    var i = 0usize
    var cp = 1.0f64
    while i < p.d {
        y[i] = p.lo[i] + p.r[i] * x[i]
        pt[i] = y[i]
        if p.inf == 1usize {
            pt[i] = math.tan[f64](y[i])
            cp = cp * math.cos[f64](y[i])
        }
        i += 1usize
    }
    var fv: [4]f64 = zero
    if p.vec == 1usize {
        let _ = integrand_vec(p.id, p.d, pt[0usize..p.d], fv[0usize..4usize])
    } else {
        fv[0usize] = integrand(p.id, p.d, pt[0usize..p.d])
    }
    var c = 0usize
    while c < p.nc {
        if p.inf == 1usize {
            out[c] = (p.prodr * fv[c]) / (cp * cp)
        } else {
            out[c] = p.prodr * fv[c]
        }
        c += 1usize
    }
}

// Cuba's ExpandFS: the points of one generator set over the region, every sign pattern of every distinct permutation of g (g is permuted in place and restored); answers the next free slot of x
fn cu_expand(p: *Cu, blo: []const f64, bhi: []const f64, g: []f64, at: usize) -> usize {
    let d = p.d
    var xi = at
    while true {
        var k = 0usize
        while k < d {
            p.x[xi] = (0.5f64 + g[k]) * blo[k] + (0.5f64 - g[k]) * bhi[k]
            xi += 1usize
            k += 1usize
        }
        var again = 0usize
        k = 0usize
        while k < d {
            g[k] = 0.0f64 - g[k]
            let neg = g[k] < 0.0f64
            k += 1usize
            if neg {
                again = 1usize
                break
            }
        }
        if again == 1usize { continue }
        var found = 0usize
        k = 1usize
        while k < d {
            let gd = g[k]
            if g[k - 1usize] > gd {
                var i = 0usize
                var j = k
                var ix = k
                var dx = k - 1usize
                while true {
                    j -= 1usize
                    if !(i < j) { break }
                    let tmp = g[i]
                    g[i] = g[j]
                    g[j] = tmp
                    if tmp <= gd {
                        if dx > 0usize { dx -= 1usize }
                    }
                    if g[i] > gd { ix = i }
                    i += 1usize
                }
                if g[dx] <= gd { dx = ix }
                g[k] = g[dx]
                g[dx] = gd
                found = 1usize
                break
            }
            k += 1usize
        }
        if found == 1usize { continue }
        var dm = 0usize
        var nd = d
        while true {
            nd -= 1usize
            if !(dm < nd) { break }
            let tmp = g[dm]
            g[dm] = g[nd]
            g[nd] = tmp
            dm += 1usize
        }
        break
    }
    ret xi
}

// Cuba Sample for one region: the rule's integral and error estimate of every component and the dimension to bisect
fn cu_sample(p: *Cu, blo: []const f64, bhi: []const f64, div: usize, ravg: []f64, rerr: []f64, rbis: []usize) {
    let d = p.d
    let nc = p.nc
    var vol = 1.0f64
    var q = 0usize
    while q < div {
        vol = vol * 0.5f64
        q += 1usize
    }
    let qq = p.gen[2usize * d] / p.gen[d]
    let ratio = qq * qq
    let offset = 2usize * d * nc
    var maxrange = 0.0f64
    var maxdim = 0usize
    var k = 0usize
    while k < d {
        let range = bhi[k] - blo[k]
        if range > maxrange {
            maxrange = range
            maxdim = k
        }
        k += 1usize
    }
    var xi = 0usize
    var s = 0usize
    while s < p.ns {
        if p.sn[s] != 0usize {
            xi = cu_expand(p, blo, bhi, p.gen[s * d..s * d + d], xi)
        }
        s += 1usize
    }
    var pt = 0usize
    while pt < p.rn {
        cu_eval(p, p.x[pt * d..pt * d + d], p.f[pt * nc..pt * nc + nc])
        pt += 1usize
    }
    p.neval += p.rn
    var c = 0usize
    while c < nc {
        let base = p.f[c] * 2.0f64 * (1.0f64 - ratio)
        var maxdiff = 0.0f64
        var bisectdim = maxdim
        var f1 = 0usize
        var dim = 0usize
        while dim < d {
            let fp = f1 + nc
            let fm = fp + nc
            let fourth = math.abs[f64](base + ratio * (p.f[fp + c] + p.f[fm + c]) - (p.f[fp + offset + c] + p.f[fm + offset + c]))
            f1 = fm
            if fourth > maxdiff {
                maxdiff = fourth
                bisectdim = dim
            }
            dim += 1usize
        }
        rbis[c] = bisectdim
        var sum: [5]f64 = zero
        var at = c
        s = 0usize
        while s < p.ns {
            var n = p.sn[s]
            while n > 0usize {
                let fun = p.f[at]
                at += nc
                var rul = 0usize
                while rul < 5usize {
                    sum[rul] += fun * p.wt[s * 5usize + rul]
                    rul += 1usize
                }
                n -= 1usize
            }
            s += 1usize
        }
        var rul = 1usize
        while rul < 4usize {
            var maxerr = 0.0f64
            s = 0usize
            while s < p.ns {
                let v = math.abs[f64](sum[rul + 1usize] + p.sc[s * 5usize + rul] * sum[rul]) * p.nm[s * 5usize + rul]
                if v > maxerr { maxerr = v }
                s += 1usize
            }
            sum[rul] = maxerr
            rul += 1usize
        }
        ravg[c] = vol * sum[0usize]
        var m23 = sum[1usize]
        if sum[2usize] > m23 { m23 = sum[2usize] }
        if sum[3usize] > m23 { m23 = sum[3usize] }
        if p.e0 * sum[1usize] <= sum[2usize] && p.e0 * sum[2usize] <= sum[3usize] {
            rerr[c] = vol * (p.e1 * sum[1usize])
        } else {
            rerr[c] = vol * (p.e2 * m23)
        }
        c += 1usize
    }
}

// the weights, null-rule scales and norms of a rule whose sets are already filled in
fn cu_norms(p: *Cu) {
    var s = 0usize
    while s < p.ns {
        var r = 1usize
        while r < 4usize {
            var scale = 100.0f64
            if p.wt[s * 5usize + r] != 0.0f64 { scale = (0.0f64 - p.wt[s * 5usize + r + 1usize]) / p.wt[s * 5usize + r] }
            var sum = 0.0f64
            var x = 0usize
            while x < p.ns {
                sum += f64(p.sn[x]) * math.abs[f64](p.wt[x * 5usize + r + 1usize] + scale * p.wt[x * 5usize + r])
                x += 1usize
            }
            p.sc[s * 5usize + r] = scale
            p.nm[s * 5usize + r] = 1.0f64 / sum
            r += 1usize
        }
        s += 1usize
    }
}

// set s of a table rule: n points, the weights of row `row` of the table w, and up to three generators picked from g (99 for none)
fn cu_tset(p: *Cu, w: []const f64, g: []const f64, s: usize, n: usize, row: usize, g0: usize, g1: usize, g2: usize) {
    p.sn[s] = n
    var k = 0usize
    while k < 5usize {
        p.wt[s * 5usize + k] = w[row * 5usize + k]
        k += 1usize
    }
    if g0 != 99usize { p.gen[s * p.d] = g[g0] }
    if g1 != 99usize { p.gen[s * p.d + 1usize] = g[g1] }
    if g2 != 99usize { p.gen[s * p.d + 2usize] = g[g2] }
}

fn cu_put5(p: *Cu, s: usize, n: usize, a0: f64, a1: f64, a2: f64, a3: f64, a4: f64) {
    p.sn[s] = n
    p.wt[s * 5usize] = a0
    p.wt[s * 5usize + 1usize] = a1
    p.wt[s * 5usize + 2usize] = a2
    p.wt[s * 5usize + 3usize] = a3
    p.wt[s * 5usize + 4usize] = a4
}

// Rule13 (d = 2), Rule11 (d = 3) from the tables
fn cu_rule_tab(p: *Cu, key: usize, w: []const f64, g: []const f64) {
    let d = i64(p.d)
    let n2 = usize(2i64 * d)
    let n3 = usize(2i64 * d * (d - 1i64))
    let n4 = usize(4i64 * d * (d - 1i64))
    let n5 = usize(4i64 * d * (d - 1i64) * (d - 2i64) / 3i64)
    let n6 = usize(4i64 * d * (d - 1i64) * (d - 2i64))
    let x = 99usize
    cu_tset(p, w, g, 0usize, 1usize, 0usize, x, x, x)
    if key == 13usize {
        p.ns = 14usize
        cu_tset(p, w, g, 1usize, n2, 1usize, 0usize, x, x)
        cu_tset(p, w, g, 2usize, n2, 2usize, 1usize, x, x)
        cu_tset(p, w, g, 3usize, n2, 3usize, 2usize, x, x)
        cu_tset(p, w, g, 4usize, n2, 4usize, 3usize, x, x)
        cu_tset(p, w, g, 5usize, n2, 5usize, 4usize, x, x)
        cu_tset(p, w, g, 6usize, n3, 6usize, 5usize, 5usize, x)
        cu_tset(p, w, g, 7usize, n3, 7usize, 6usize, 6usize, x)
        cu_tset(p, w, g, 8usize, n3, 8usize, 7usize, 7usize, x)
        cu_tset(p, w, g, 9usize, n3, 9usize, 8usize, 8usize, x)
        cu_tset(p, w, g, 10usize, n3, 10usize, 9usize, 9usize, x)
        cu_tset(p, w, g, 11usize, n4, 11usize, 10usize, 11usize, x)
        cu_tset(p, w, g, 12usize, n4, 12usize, 12usize, 13usize, x)
        cu_tset(p, w, g, 13usize, n4, 13usize, 14usize, 15usize, x)
        p.e0 = 10.0f64
        p.e1 = 1.0f64
        p.e2 = 5.0f64
    } else {
        p.ns = 13usize
        cu_tset(p, w, g, 1usize, n2, 1usize, 0usize, x, x)
        cu_tset(p, w, g, 2usize, n2, 2usize, 1usize, x, x)
        cu_tset(p, w, g, 3usize, n2, 3usize, 2usize, x, x)
        cu_tset(p, w, g, 4usize, n2, 4usize, 3usize, x, x)
        cu_tset(p, w, g, 5usize, n2, 5usize, 4usize, x, x)
        cu_tset(p, w, g, 6usize, n3, 6usize, 5usize, 5usize, x)
        cu_tset(p, w, g, 7usize, n3, 7usize, 6usize, 6usize, x)
        cu_tset(p, w, g, 8usize, n5, 8usize, 7usize, 7usize, 7usize)
        cu_tset(p, w, g, 9usize, n5, 9usize, 8usize, 8usize, 8usize)
        cu_tset(p, w, g, 10usize, n5, 10usize, 9usize, 9usize, 9usize)
        cu_tset(p, w, g, 11usize, n6, 11usize, 10usize, 11usize, 11usize)
        cu_tset(p, w, g, 12usize, n6, 12usize, 12usize, 12usize, 13usize)
        p.e0 = 4.0f64
        p.e1 = 0.5f64
        p.e2 = 3.0f64
    }
    var s = 0usize
    var n = 0usize
    while s < p.ns {
        n += p.sn[s]
        s += 1usize
    }
    p.rn = n
}

// Rule9 (any dimension) and Rule7 from their weight formulas
fn cu_rule_gen(p: *Cu, key: usize, w: []const f64, g: []const f64) {
    let d = i64(p.d)
    let nd = f64(p.d)
    let two = f64(1usize << p.d)
    let n1 = usize(2i64 * d)
    let n2 = usize(2i64 * d * (d - 1i64))
    var n = 1usize
    if key == 9usize {
        p.ns = 9usize
        let w0 = nd * (nd * (nd * w[0usize] + w[1usize]) + w[2usize]) + w[3usize]
        let w1 = nd * (nd * (nd * w[4usize] + w[5usize]) + w[6usize]) - w[7usize]
        let w2 = nd * w[8usize] - w1
        let w3 = nd * (nd * w[9usize] + w[10usize]) - 1.0f64 + w0
        let w4 = nd * w[11usize] + 1.0f64 - w0
        cu_put5(p, 0usize, 1usize, w0, w1, w2, w3, w4)
        let a0 = nd * (nd * w[12usize] + w[13usize]) + w[14usize]
        let a1 = nd * (nd * w[15usize] + w[16usize]) + w[17usize]
        cu_put5(p, 1usize, n1, a0, a1, w[18usize] - a1, nd * w[19usize] + w[20usize] + a0, w[21usize] - a0)
        p.gen[p.d] = g[0usize]
        let b0 = nd * w[22usize] + w[23usize]
        let b1 = nd * w[24usize] + w[25usize]
        cu_put5(p, 2usize, n1, b0, b1, w[26usize] - b1, nd * w[27usize] + w[28usize], 0.0f64 - b0)
        p.gen[2usize * p.d] = g[1usize]
        cu_put5(p, 3usize, n1, w[29usize], w[30usize], 0.0f64 - w[29usize], w[31usize], 0.0f64 - w[29usize])
        p.gen[3usize * p.d] = g[2usize]
        cu_put5(p, 4usize, n1, 0.0f64, 0.0f64, w[32usize], 0.0f64, 0.0f64)
        p.gen[4usize * p.d] = g[3usize]
        let c0 = w[33usize] - nd * w[12usize]
        let c1 = w[34usize] - nd * w[15usize]
        cu_put5(p, 5usize, n2, c0, c1, 0.0f64 - c1, w[35usize] + c0, 0.0f64 - c0)
        p.gen[5usize * p.d] = g[0usize]
        if p.d > 1usize { p.gen[5usize * p.d + 1usize] = g[0usize] }
        cu_put5(p, 6usize, usize(4i64 * d * (d - 1i64)), w[36usize], w[37usize], 0.0f64 - w[37usize], w[38usize], 0.0f64 - w[36usize])
        p.gen[6usize * p.d] = g[0usize]
        if p.d > 1usize { p.gen[6usize * p.d + 1usize] = g[1usize] }
        cu_put5(p, 7usize, usize(4i64 * d * (d - 1i64) * (d - 2i64) / 3i64), w[39usize], w[40usize], 0.0f64 - w[40usize], w[39usize], 0.0f64 - w[39usize])
        p.gen[7usize * p.d] = g[0usize]
        if p.d > 1usize { p.gen[7usize * p.d + 1usize] = g[0usize] }
        if p.d > 2usize { p.gen[7usize * p.d + 2usize] = g[0usize] }
        let t0 = w[41usize] / two
        let t1 = w[7usize] / two
        cu_put5(p, 8usize, (1usize << p.d), t0, t1, 0.0f64 - t1, t0, 0.0f64 - t0)
        var k = 0usize
        while k < p.d {
            p.gen[8usize * p.d + k] = g[4usize]
            k += 1usize
        }
        p.e0 = 5.0f64
        p.e1 = 1.0f64
        p.e2 = 5.0f64
    } else {
        p.ns = 6usize
        let w0 = nd * (nd * w[0usize] + w[1usize]) + w[2usize]
        let w1 = nd * (nd * w[3usize] + w[4usize]) - w[5usize]
        let w2 = nd * w[6usize] - w1
        let w3 = nd * (nd * w[7usize] + w[8usize]) - w[9usize]
        let w4 = 1.0f64 - w0
        cu_put5(p, 0usize, 1usize, w0, w1, w2, w3, w4)
        cu_put5(p, 1usize, n1, w[10usize], w[11usize], 0.0f64 - w[10usize], w[12usize], 0.0f64 - w[10usize])
        p.gen[p.d] = g[1usize]
        let a0 = w[13usize] - nd * w[0usize]
        let a1 = w[14usize] - nd * w[3usize]
        cu_put5(p, 2usize, n1, a0, a1, w[15usize] - a1, w[16usize] - nd * w[7usize], 0.0f64 - a0)
        p.gen[2usize * p.d] = g[0usize]
        cu_put5(p, 3usize, n1, 0.0f64, 0.0f64, w[17usize], 0.0f64, 0.0f64)
        p.gen[3usize * p.d] = g[2usize]
        cu_put5(p, 4usize, n2, 0.0f64 - w[7usize], w[18usize], 0.0f64 - w[18usize], w[19usize], w[7usize])
        p.gen[4usize * p.d] = g[0usize]
        if p.d > 1usize { p.gen[4usize * p.d + 1usize] = g[0usize] }
        let t0 = w[20usize] / two
        cu_put5(p, 5usize, (1usize << p.d), t0, w[5usize] / two, 0.0f64 - w[5usize] / two, w[9usize] / two, 0.0f64 - t0)
        var k = 0usize
        while k < p.d {
            p.gen[5usize * p.d + k] = g[3usize]
            k += 1usize
        }
        p.e0 = 5.0f64
        p.e1 = 1.0f64
        p.e2 = 5.0f64
    }
    var s = 0usize
    n = 0usize
    while s < p.ns {
        n += p.sn[s]
        s += 1usize
    }
    p.rn = n
}

// Cuba's Cuhre on the fixed integrand of the module over the box lo..hi (relative and absolute tolerances, evaluation limits, rule key as cubature::cuhre with final = 1): the integrals of the nc components in out[0..nc),
// their errors in out[nc..2nc), then the evaluation count, the number of regions, the chi-square probabilities (nc) and the return code (0 converged, 1 limit reached)
fn cuhre(a: *mem.Arena, id: usize, vec: usize, d: usize, lo: []const f64, hi: []const f64, epsrel: f64, epsabs0: f64, mineval0: usize, maxeval: usize, key0: usize, out: []f64) -> err {
    var nc0 = 1usize
    if vec == 1usize {
        nc0 = 2usize
        if id >= 1usize { nc0 = 3usize }
    }
    let (sn, e1) = mem.alloc[usize](a, 16usize)
    let (wt, e2) = mem.alloc[f64](a, 16usize * 5usize)
    let (sc, e3) = mem.alloc[f64](a, 16usize * 5usize)
    let (nm, e4) = mem.alloc[f64](a, 16usize * 5usize)
    let (gen, e5) = mem.alloc[f64](a, 16usize * d)
    let (xs, e6) = mem.alloc[f64](a, 1024usize * d)
    let (fs, e7) = mem.alloc[f64](a, 1024usize * nc0)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret e1 }
    var p = Cu { id: id, vec: vec, nc: nc0, d: d, inf: 0usize, lo: zero, r: zero, prodr: 1.0f64, rn: 0usize, ns: 0usize, sn: sn, wt: wt, sc: sc, nm: nm, gen: gen, e0: 0.0f64, e1: 0.0f64, e2: 0.0f64, x: xs, f: fs, neval: 0usize }
    let nc = p.nc
    var i = 0usize
    while i < d {
        if math.abs[f64](lo[i]) >= 1.0e100f64 || math.abs[f64](hi[i]) >= 1.0e100f64 { p.inf = 1usize }
        i += 1usize
    }
    i = 0usize
    while i < d {
        if p.inf == 1usize {
            p.lo[i] = math.atan[f64](lo[i])
            p.r[i] = math.atan[f64](hi[i]) - p.lo[i]
        } else {
            p.lo[i] = lo[i]
            p.r[i] = hi[i] - lo[i]
        }
        p.prodr = p.prodr * p.r[i]
        i += 1usize
    }
    var k = 0usize
    while k < 16usize {
        sn[k] = 0usize
        k += 1usize
    }
    k = 0usize
    while k < 16usize * 5usize {
        wt[k] = 0.0f64
        sc[k] = 0.0f64
        nm[k] = 0.0f64
        k += 1usize
    }
    k = 0usize
    while k < 16usize * d {
        gen[k] = 0.0f64
        k += 1usize
    }
    var tw: [80]f64 = zero
    var tg: [16]f64 = zero
    var key = key0
    if !(key0 == 13usize && d == 2usize) && !(key0 == 11usize && d == 3usize) && key0 != 9usize && key0 != 7usize {
        key = 9usize
        if d == 2usize { key = 13usize }
        if d == 3usize { key = 11usize }
    }
    cu_tab(key, tw[0usize..80usize], tg[0usize..16usize])
    if key == 13usize || key == 11usize {
        cu_rule_tab(&p, key, tw[0usize..80usize], tg[0usize..16usize])
    } else {
        cu_rule_gen(&p, key, tw[0usize..80usize], tg[0usize..16usize])
    }
    cu_norms(&p)
    let rn = p.rn
    var epsabs = epsabs0
    let nz = 4.93038065763132378e-32f64
    if epsabs < nz { epsabs = nz }
    var mineval = mineval0
    if mineval < rn + 1usize { mineval = rn + 1usize }
    var evmax = maxeval
    if evmax < mineval { evmax = mineval }
    let cap = evmax / (2usize * rn) + 8usize
    let (rlo, e8) = mem.alloc[f64](a, cap * d)
    let (rhi, e9) = mem.alloc[f64](a, cap * d)
    let (rdv, e10) = mem.alloc[usize](a, cap)
    let (rav, e11) = mem.alloc[f64](a, cap * nc)
    let (rer, e12) = mem.alloc[f64](a, cap * nc)
    let (rbs, e13) = mem.alloc[usize](a, cap * nc)
    let (tot, e14) = mem.alloc[f64](a, 10usize * nc)
    if e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok { ret e8 }
    var rsv: [4]f64 = zero
    var rsb: [4]usize = zero
    var rse: [4]f64 = zero
    i = 0usize
    while i < d {
        rlo[i] = 0.0f64
        rhi[i] = 1.0f64
        i += 1usize
    }
    rdv[0usize] = 0usize
    var nreg = 1usize
    p.neval = 0usize
    cu_sample(&p, rlo[0usize..d], rhi[0usize..d], 0usize, rav[0usize..nc], rer[0usize..nc], rbs[0usize..nc])
    // tot layout per component c: avg, err, lastavg, lasterr, weightsum, avgsum, guess, chisum, chisqsum, chisq at 10 c + 0..9
    var c = 0usize
    while c < nc {
        let t = 10usize * c
        tot[t] = rav[c]
        tot[t + 2usize] = rav[c]
        tot[t + 6usize] = rav[c]
        tot[t + 1usize] = rer[c]
        tot[t + 3usize] = rer[c]
        var sq = rer[c] * rer[c]
        if sq < nz { sq = nz }
        tot[t + 4usize] = 1.0f64 / sq
        tot[t + 5usize] = tot[t + 4usize] * rav[c]
        tot[t + 7usize] = 0.0f64
        tot[t + 8usize] = 0.0f64
        tot[t + 9usize] = 0.0f64
        c += 1usize
    }
    var fail = 0usize
    while true {
        var maxratio = 0.0f64 - 1.7976931348623157e308f64
        var maxcomp = 0usize
        c = 0usize
        while c < nc {
            var me = epsrel * math.abs[f64](tot[10usize * c])
            if epsabs > me { me = epsabs }
            let ratio = tot[10usize * c + 1usize] / me
            if ratio > maxratio {
                maxratio = ratio
                maxcomp = c
            }
            c += 1usize
        }
        if maxratio <= 1.0f64 && p.neval >= mineval { break }
        if p.neval >= evmax {
            fail = 1usize
            break
        }
        if nreg + 1usize >= cap { break }
        var maxerr = 0.0f64 - 1.7976931348623157e308f64
        var kl = 0usize
        var pool = (nreg - 1usize) / 1024usize + 1usize
        while pool > 0usize {
            pool -= 1usize
            var j = pool * 1024usize
            var je = j + 1024usize
            if je > nreg { je = nreg }
            while j < je {
                let er = rer[j * nc + maxcomp]
                if er > maxerr {
                    maxerr = er
                    kl = j
                }
                j += 1usize
            }
        }
        let kr = nreg
        nreg += 1usize
        rdv[kl] += 1usize
        rdv[kr] = rdv[kl]
        c = 0usize
        while c < nc {
            rsv[c] = rav[kl * nc + c]
            rse[c] = rer[kl * nc + c]
            rsb[c] = rbs[kl * nc + c]
            c += 1usize
        }
        i = 0usize
        while i < d {
            rlo[kr * d + i] = rlo[kl * d + i]
            rhi[kr * d + i] = rhi[kl * d + i]
            i += 1usize
        }
        let bd = rsb[maxcomp]
        let mid = 0.5f64 * (rhi[kl * d + bd] + rlo[kl * d + bd])
        rhi[kl * d + bd] = mid
        rlo[kr * d + bd] = mid
        cu_sample(&p, rlo[kl * d..kl * d + d], rhi[kl * d..kl * d + d], rdv[kl], rav[kl * nc..kl * nc + nc], rer[kl * nc..kl * nc + nc], rbs[kl * nc..kl * nc + nc])
        cu_sample(&p, rlo[kr * d..kr * d + d], rhi[kr * d..kr * d + d], rdv[kr], rav[kr * nc..kr * nc + nc], rer[kr * nc..kr * nc + nc], rbs[kr * nc..kr * nc + nc])
        c = 0usize
        while c < nc {
            let t = 10usize * c
            let al = rav[kl * nc + c]
            let ar = rav[kr * nc + c]
            var diff = al + ar - rsv[c]
            tot[t + 2usize] += diff
            diff = math.abs[f64](0.25f64 * diff)
            let er = rer[kl * nc + c] + rer[kr * nc + c]
            if er > 0.0f64 {
                let cf = 1.0f64 + 2.0f64 * diff / er
                rer[kl * nc + c] *= cf
                rer[kr * nc + c] *= cf
            }
            rer[kl * nc + c] += diff
            rer[kr * nc + c] += diff
            tot[t + 3usize] += rer[kl * nc + c] + rer[kr * nc + c] - rse[c]
            var sq = tot[t + 3usize] * tot[t + 3usize]
            if sq < nz { sq = nz }
            var w = 1.0f64 / sq
            tot[t + 4usize] += w
            let sigsq = 1.0f64 / tot[t + 4usize]
            tot[t + 5usize] += w * tot[t + 2usize]
            let avg = sigsq * tot[t + 5usize]
            w *= tot[t + 2usize] - tot[t + 6usize]
            tot[t + 7usize] += w
            tot[t + 8usize] += w * tot[t + 2usize]
            tot[t + 9usize] = tot[t + 8usize] - avg * tot[t + 7usize]
            tot[t] = tot[t + 2usize]
            tot[t + 1usize] = tot[t + 3usize]
            c += 1usize
        }
    }
    c = 0usize
    while c < nc {
        out[c] = tot[10usize * c]
        out[nc + c] = tot[10usize * c + 1usize]
        out[2usize * nc + 2usize + c] = cu_chisq(tot[10usize * c + 9usize], i64(nreg) - 1i64)
        c += 1usize
    }
    out[2usize * nc] = f64(p.neval)
    out[2usize * nc + 1usize] = f64(nreg)
    out[3usize * nc + 2usize] = f64(fail)
    ret ok
}

// Cuba's Mersenne Twister (Random.c PART 2) in the 624-word state mt; mt[624] holds the next index
fn vg_twist(a: u64, b: u64) -> u64 {
    let mix = (a & 2147483648u64) | (b & 2147483647u64)
    var m = 0u64
    if (b & 1u64) == 1u64 { m = 2567483615u64 }
    ret (mix >> 1u64) ^ m
}

fn vg_reload(mt: []u64) {
    var s = 0usize
    while s < 227usize {
        mt[s] = mt[s + 397usize] ^ vg_twist(mt[s], mt[s + 1usize])
        s += 1usize
    }
    while s < 623usize {
        mt[s] = mt[s - 227usize] ^ vg_twist(mt[s], mt[s + 1usize])
        s += 1usize
    }
    mt[623usize] = mt[396usize] ^ vg_twist(mt[623usize], mt[0usize])
}

fn vg_mt_ini(mt: []u64, seed0: u64) {
    var seed = seed0 & 4294967295u64
    var j = 1usize
    while j <= 624usize {
        mt[j - 1usize] = seed
        seed = (1812433253u64 * (seed ^ (seed >> 30u64)) + u64(j)) & 4294967295u64
        j += 1usize
    }
    vg_reload(mt)
    mt[624usize] = 0u64
}

fn vg_mt_get(mt: []u64) -> f64 {
    if mt[624usize] >= 624u64 {
        vg_reload(mt)
        mt[624usize] = 0u64
    }
    var s = mt[usize(mt[624usize])]
    mt[624usize] += 1u64
    s = s ^ (s >> 11u64)
    s = s ^ (((s << 7u64) & 4294967295u64) & 2636928640u64)
    s = s ^ (((s << 15u64) & 4294967295u64) & 4022730752u64)
    s = s ^ (s >> 18u64)
    ret f64(s) / 4294967296.0f64
}

// Vegas RefineGrid on one dimension's grid (128 bins) with its marginal sums
fn vg_refine(grid: []f64, margsum: []f64) {
    var imp: [128]f64 = zero
    var newgrid: [128]f64 = zero
    var prev = margsum[0usize]
    var cur = margsum[1usize]
    var norm = 0.5f64 * (prev + cur)
    margsum[0usize] = norm
    var bin = 1usize
    while bin < 127usize {
        let s = prev + cur
        prev = cur
        cur = margsum[bin + 1usize]
        margsum[bin] = (s + cur) / 3.0f64
        norm += margsum[bin]
        bin += 1usize
    }
    margsum[127usize] = 0.5f64 * (prev + cur)
    norm += margsum[127usize]
    if norm == 0.0f64 { ret }
    norm = 1.0f64 / norm
    var avgperbin = 0.0f64
    bin = 0usize
    while bin < 128usize {
        var impfun = 0.0f64
        if margsum[bin] > 0.0f64 {
            let r = margsum[bin] * norm
            impfun = math.pow[f64]((r - 1.0f64) / math.log[f64](r), 1.5f64)
            avgperbin += impfun
        }
        imp[bin] = impfun
        bin += 1usize
    }
    avgperbin /= 128.0f64
    cur = 0.0f64
    var newcur = 0.0f64
    var thisbin = 0.0f64
    var ib = 0i64 - 1i64
    var newbin = 0usize
    while newbin < 127usize {
        while thisbin < avgperbin {
            ib += 1i64
            thisbin += imp[usize(ib)]
            prev = cur
            cur = grid[usize(ib)]
        }
        thisbin -= avgperbin
        let delta = (cur - prev) * thisbin
        var im1 = 0usize
        if ib > 1i64 { im1 = usize(ib - 1i64) }
        let cand = cur - 2.0f64 * delta / (imp[usize(ib)] + imp[im1])
        if cand > newcur { newcur = cand }
        newgrid[newbin] = newcur
        newbin += 1usize
    }
    bin = 0usize
    while bin < 127usize {
        grid[bin] = newgrid[bin]
        bin += 1usize
    }
    grid[127usize] = 1.0f64
}

// Cuba's Vegas (Mersenne Twister seed, final = 1, smooth = 0, no state file) on the fixed integrand of the module over lo..hi: layout of out as for cuhre except that the regions are absent:
// integrals (nc), errors (nc), evaluations, chi-square probabilities (nc), return code
fn vegas(a: *mem.Arena, id: usize, vec: usize, d: usize, lo: []const f64, hi: []const f64, epsrel: f64, epsabs: f64, mineval: usize, maxeval: usize, nstart: usize, nincrease: usize, seed: usize, out: []f64) -> err {
    var nc0 = 1usize
    if vec == 1usize {
        nc0 = 2usize
        if id >= 1usize { nc0 = 3usize }
    }
    let (sn, e1) = mem.alloc[usize](a, 1usize)
    let (wt, e2) = mem.alloc[f64](a, 1usize)
    var p = Cu { id: id, vec: vec, nc: nc0, d: d, inf: 0usize, lo: zero, r: zero, prodr: 1.0f64, rn: 0usize, ns: 0usize, sn: sn, wt: wt, sc: wt, nm: wt, gen: wt, e0: 0.0f64, e1: 0.0f64, e2: 0.0f64, x: wt, f: wt, neval: 0usize }
    let nc = nc0
    var i = 0usize
    while i < d {
        if math.abs[f64](lo[i]) >= 1.0e100f64 || math.abs[f64](hi[i]) >= 1.0e100f64 { p.inf = 1usize }
        i += 1usize
    }
    i = 0usize
    while i < d {
        if p.inf == 1usize {
            p.lo[i] = math.atan[f64](lo[i])
            p.r[i] = math.atan[f64](hi[i]) - p.lo[i]
        } else {
            p.lo[i] = lo[i]
            p.r[i] = hi[i] - lo[i]
        }
        p.prodr = p.prodr * p.r[i]
        i += 1usize
    }
    let (mt, e3) = mem.alloc[u64](a, 625usize)
    let (grid, e4) = mem.alloc[f64](a, d * 128usize)
    let (marg, e5) = mem.alloc[f64](a, nc * d * 128usize)
    let (cum, e6) = mem.alloc[f64](a, nc * 10usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret e1 }
    vg_rng_ini(mt, seed, d, maxeval)
    let nz = 4.93038065763132378e-32f64
    var bin = 0usize
    while bin < 128usize {
        var dim = 0usize
        while dim < d {
            grid[dim * 128usize + bin] = f64(bin + 1usize) / 128.0f64
            dim += 1usize
        }
        bin += 1usize
    }
    var k = 0usize
    while k < nc * 10usize {
        cum[k] = 0.0f64
        k += 1usize
    }
    var xr: [8]f64 = zero
    var ib: [8]usize = zero
    var fv: [4]f64 = zero
    var niter = 0usize
    var nsamples = nstart
    var neval = 0usize
    var fail = 0usize
    while true {
        let jac = 1.0f64 / f64(nsamples)
        k = 0usize
        while k < nc * d * 128usize {
            marg[k] = 0.0f64
            k += 1usize
        }
        var n = 0usize
        while n < nsamples {
            var weight = jac
            var dim = 0usize
            var ur: [8]f64 = zero
            vg_rng(mt, seed, d, ur[0usize..d])
            while dim < d {
                let u = ur[dim]
                let pos = u * 128.0f64
                let ipos = usize(pos)
                var prv = 0.0f64
                if ipos != 0usize { prv = grid[dim * 128usize + ipos - 1usize] }
                let diff = grid[dim * 128usize + ipos] - prv
                xr[dim] = prv + (pos - f64(ipos)) * diff
                ib[dim] = ipos
                weight *= diff * 128.0f64
                dim += 1usize
            }
            cu_eval(&p, xr[0usize..d], fv[0usize..nc])
            neval += 1usize
            var c = 0usize
            while c < nc {
                var wfun = weight * fv[c]
                if wfun != 0.0f64 {
                    cum[c * 10usize] += wfun
                    wfun *= wfun
                    cum[c * 10usize + 1usize] += wfun
                    dim = 0usize
                    while dim < d {
                        marg[(c * d + dim) * 128usize + ib[dim]] += wfun
                        dim += 1usize
                    }
                }
                c += 1usize
            }
            n += 1usize
        }
        fail = 0usize
        var c = 0usize
        while c < nc {
            let t = c * 10usize
            let sum = cum[t]
            let sq = cum[t + 1usize]
            let wr = math.sqrt[f64](sq * f64(nsamples))
            var den = (wr + sum) * (wr - sum)
            if den < nz { den = nz }
            var w = f64(nsamples - 1usize) / den
            cum[t + 2usize] += w
            var sigsq = 1.0f64 / cum[t + 2usize]
            cum[t + 3usize] += w * sum
            let avg = sigsq * cum[t + 3usize]
            cum[t + 7usize] = avg
            // final = 1: the last iteration alone
            cum[t + 7usize] = sum
            sigsq = 1.0f64 / w
            cum[t + 8usize] = math.sqrt[f64](sigsq)
            var me = epsrel * math.abs[f64](cum[t + 7usize])
            if epsabs > me { me = epsabs }
            if cum[t + 8usize] > me { fail = 1usize }
            if niter == 0usize {
                cum[t + 6usize] = sum
            } else {
                w *= sum - cum[t + 6usize]
                cum[t + 4usize] += w
                cum[t + 5usize] += w * sum
            }
            cum[t + 9usize] = cum[t + 5usize] - avg * cum[t + 4usize]
            cum[t] = 0.0f64
            cum[t + 1usize] = 0.0f64
            c += 1usize
        }
        if fail == 0usize && neval >= mineval { break }
        if neval >= maxeval { break }
        var dim = 0usize
        if nc == 1usize {
            while dim < d {
                vg_refine(grid[dim * 128usize..dim * 128usize + 128usize], marg[dim * 128usize..dim * 128usize + 128usize])
                dim += 1usize
            }
        } else {
            var wm: [128]f64 = zero
            while dim < d {
                bin = 0usize
                while bin < 128usize {
                    wm[bin] = 0.0f64
                    bin += 1usize
                }
                var comp = 0usize
                while comp < nc {
                    var w = cum[comp * 10usize + 7usize]
                    if w != 0.0f64 {
                        w = 1.0f64 / (w * w)
                        bin = 0usize
                        while bin < 128usize {
                            wm[bin] += w * marg[(comp * d + dim) * 128usize + bin]
                            bin += 1usize
                        }
                    }
                    comp += 1usize
                }
                vg_refine(grid[dim * 128usize..dim * 128usize + 128usize], wm[0usize..128usize])
                dim += 1usize
            }
        }
        niter += 1usize
        nsamples += nincrease
    }
    var c = 0usize
    while c < nc {
        out[c] = cum[c * 10usize + 7usize]
        out[nc + c] = cum[c * 10usize + 8usize]
        out[2usize * nc + 1usize + c] = cu_chisq(cum[c * 10usize + 9usize], i64(niter))
        c += 1usize
    }
    out[2usize * nc] = f64(neval)
    out[3usize * nc + 1usize] = f64(fail)
    ret ok
}

// Suave: a region keeps its samples (weights w, points x, values f), the bins of its newest batch, its bounds with one 64-bin grid per dimension and the result (avg, err, sigsq, chisq) of every component
type SuReg = struct { div: usize, df: i64, n: usize, nlast: usize, res: []f64, lo: []f64, hi: []f64, grid: []f64, w: []f64, x: []f64, f: []f64, bin: []usize }

// Suave's RefineGrid (64 bins, smooth edges)
fn su_refine(grid: []f64, margsum: []f64) {
    var imp: [64]f64 = zero
    var newgrid: [64]f64 = zero
    var prev = margsum[0usize]
    var cur = margsum[1usize]
    var norm = 0.5f64 * (prev + cur)
    margsum[0usize] = norm
    var bin = 1usize
    while bin < 63usize {
        let s = prev + cur
        prev = cur
        cur = margsum[bin + 1usize]
        margsum[bin] = (s + cur) / 3.0f64
        norm += margsum[bin]
        bin += 1usize
    }
    margsum[63usize] = 0.5f64 * (prev + cur)
    norm += margsum[63usize]
    if norm == 0.0f64 { ret }
    norm = 1.0f64 / norm
    var avgperbin = 0.0f64
    bin = 0usize
    while bin < 64usize {
        var impfun = 0.0f64
        if margsum[bin] > 0.0f64 {
            let r = margsum[bin] * norm
            impfun = math.pow[f64]((r - 1.0f64) / math.log[f64](r), 1.5f64)
            avgperbin += impfun
        }
        imp[bin] = impfun
        bin += 1usize
    }
    avgperbin /= 64.0f64
    cur = 0.0f64
    var newcur = 0.0f64
    var thisbin = 0.0f64
    var ib = 0i64 - 1i64
    var newbin = 0usize
    while newbin < 63usize {
        while thisbin < avgperbin {
            ib += 1i64
            thisbin += imp[usize(ib)]
            prev = cur
            cur = grid[usize(ib)]
        }
        thisbin -= avgperbin
        let delta = (cur - prev) * thisbin
        var im1 = 0usize
        if ib > 1i64 { im1 = usize(ib - 1i64) }
        let cand = cur - 2.0f64 * delta / (imp[usize(ib)] + imp[im1])
        var base = newcur + 16.0f64 * 2.220446049250313e-16f64
        if cand > base { base = cand }
        newcur = base
        newgrid[newbin] = newcur
        newbin += 1usize
    }
    bin = 0usize
    while bin < 63usize {
        grid[bin] = newgrid[bin]
        bin += 1usize
    }
    grid[63usize] = 1.0f64
}

// Suave's StretchGrid: the grids of the lower and upper half of a bisected dimension
fn su_stretch(grid: []const f64, gl: []f64, gr: []f64) {
    var prev = 0.0f64
    var cur = 0.0f64
    var bin = 0usize
    while bin < 64usize {
        cur = grid[bin]
        bin += 1usize
        if cur >= 0.5f64 { break }
        prev = cur
    }
    var step = (f64(bin) - (cur - 0.5f64) / (cur - prev)) / 64.0f64
    prev = 0.0f64
    var x = 0.0f64
    var gi = 0usize
    cur = grid[0usize]
    bin = 0usize
    while bin < 64usize {
        x += step
        if x > 1.0f64 {
            x -= 1.0f64
            prev = cur
            gi += 1usize
            cur = grid[gi]
        }
        gl[bin] = 2.0f64 * (prev + (cur - prev) * x)
        bin += 1usize
    }
    step = 1.0f64 - step
    bin = 0usize
    while bin < 63usize {
        x += step
        if x > 1.0f64 {
            x -= 1.0f64
            prev = cur
            gi += 1usize
            cur = grid[gi]
        }
        gr[bin] = 2.0f64 * (prev + (cur - prev) * x) - 1.0f64
        bin += 1usize
    }
    gr[63usize] = 1.0f64
}

// Suave's Sample: nnew new points in the region (after its nold inherited ones), then the region's result from all its samples in batches
fn su_sample(p: *Cu, mt: []u64, sdd: usize, rg: *SuReg, nnew: usize, nold: usize, nmin: usize) {
    let d = p.d
    let nc = p.nc
    let nz = 4.93038065763132378e-32f64
    var jac = f64(nnew)
    var q = 0usize
    while q < rg.div {
        jac = jac * 2.0f64
        q += 1usize
    }
    jac = 1.0f64 / jac
    var j = 0usize
    while j < nnew {
        let at = nold + j
        var weight = jac
        var k = 0usize
        var ur: [8]f64 = zero
        vg_rng(mt, sdd, d, ur[0usize..d])
        while k < d {
            let u = ur[k]
            let pos = u * 64.0f64
            let ipos = usize(pos)
            var prv = 0.0f64
            if ipos != 0usize { prv = rg.grid[k * 64usize + ipos - 1usize] }
            let diff = rg.grid[k * 64usize + ipos] - prv
            rg.x[at * d + k] = rg.lo[k] + (prv + (pos - f64(ipos)) * diff) * (rg.hi[k] - rg.lo[k])
            rg.bin[j * d + k] = ipos
            weight *= diff * 64.0f64
            k += 1usize
        }
        rg.w[at] = weight
        cu_eval(p, rg.x[at * d..at * d + d], rg.f[at * nc..at * nc + nc])
        j += 1usize
    }
    p.neval += nnew
    rg.w[nold + nnew - 1usize] = 0.0f64 - rg.w[nold + nnew - 1usize]
    rg.nlast = nnew
    let ntot = nold + nnew
    rg.n = ntot
    // the cumulants of a component: sum, sqsum, weight, weightsum, avg, avgsum, guess, chisum, chisqsum
    var cu: [27]f64 = zero
    var df = 0i64
    var n = 0usize
    var i = 0usize
    while i < ntot {
        let fin = rg.w[i] < 0.0f64
        let weight = math.abs[f64](rg.w[i])
        n += 1usize
        var c = 0usize
        while c < nc {
            let t = c * 9usize
            let wfun = weight * rg.f[i * nc + c]
            cu[t] += wfun
            cu[t + 1usize] += wfun * wfun
            if fin {
                if n >= nmin {
                    let wr = math.sqrt[f64](cu[t + 1usize] * f64(n))
                    var den = (wr + cu[t]) * (wr - cu[t])
                    if den < nz { den = nz }
                    var w = f64(n - 1usize) / den
                    cu[t + 3usize] += w
                    cu[t + 2usize] = w
                    cu[t + 4usize] = w * cu[t]
                    cu[t + 5usize] += cu[t + 4usize]
                    if df == 0i64 {
                        cu[t + 6usize] = cu[t]
                    } else {
                        w *= cu[t] - cu[t + 6usize]
                        cu[t + 7usize] += w
                        cu[t + 8usize] += w * cu[t]
                    }
                }
                cu[t] = 0.0f64
                cu[t + 1usize] = 0.0f64
            }
            c += 1usize
        }
        if fin {
            if n >= nmin { df += 1i64 }
            n = 0usize
        }
        i += 1usize
    }
    df -= 1i64
    rg.df = df
    var c = 0usize
    while c < nc {
        let t = c * 9usize
        let sigsq = 1.0f64 / cu[t + 3usize]
        let avg = sigsq * cu[t + 5usize]
        let r = c * 4usize
        rg.res[r + 2usize] = 1.0f64 / cu[t + 2usize]
        rg.res[r] = rg.res[r + 2usize] * cu[t + 4usize]
        rg.res[r + 1usize] = math.sqrt[f64](rg.res[r + 2usize])
        if sigsq < 0.9f64 * nz {
            rg.res[r + 3usize] = 0.0f64
        } else {
            rg.res[r + 3usize] = cu[t + 8usize] - avg * cu[t + 7usize]
        }
        c += 1usize
    }
}

fn su_newreg(a: *mem.Arena, d: usize, nc: usize, n: usize, nnew: usize, rg: *SuReg) -> err {
    let (res, e1) = mem.alloc[f64](a, nc * 4usize)
    let (lo, e2) = mem.alloc[f64](a, d)
    let (hi, e3) = mem.alloc[f64](a, d)
    let (grid, e4) = mem.alloc[f64](a, d * 64usize)
    let (w, e5) = mem.alloc[f64](a, n)
    let (x, e6) = mem.alloc[f64](a, n * d)
    let (f, e7) = mem.alloc[f64](a, n * nc)
    let (bin, e8) = mem.alloc[usize](a, nnew * d)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret e1 }
    rg.res = res
    rg.lo = lo
    rg.hi = hi
    rg.grid = grid
    rg.w = w
    rg.x = x
    rg.f = f
    rg.bin = bin
    rg.n = n
    ret ok
}

// Cuba's Suave (Mersenne Twister seed, fin = 1, smooth = 0, no state file) on the fixed integrand of the module over lo..hi: out as for cuhre (integrals, errors, evaluations, regions, probabilities, return code)
fn suave(a: *mem.Arena, id: usize, vec: usize, d: usize, lo: []const f64, hi: []const f64, epsrel: f64, epsabs0: f64, mineval: usize, maxeval: usize, nnew: usize, nmin0: usize, flatness: f64, seed: usize, out: []f64) -> err {
    var nc0 = 1usize
    if vec == 1usize {
        nc0 = 2usize
        if id >= 1usize { nc0 = 3usize }
    }
    let (sn, e1) = mem.alloc[usize](a, 1usize)
    let (wt, e2) = mem.alloc[f64](a, 1usize)
    var p = Cu { id: id, vec: vec, nc: nc0, d: d, inf: 0usize, lo: zero, r: zero, prodr: 1.0f64, rn: 0usize, ns: 0usize, sn: sn, wt: wt, sc: wt, nm: wt, gen: wt, e0: 0.0f64, e1: 0.0f64, e2: 0.0f64, x: wt, f: wt, neval: 0usize }
    let nc = nc0
    var i = 0usize
    while i < d {
        if math.abs[f64](lo[i]) >= 1.0e100f64 || math.abs[f64](hi[i]) >= 1.0e100f64 { p.inf = 1usize }
        i += 1usize
    }
    i = 0usize
    while i < d {
        if p.inf == 1usize {
            p.lo[i] = math.atan[f64](lo[i])
            p.r[i] = math.atan[f64](hi[i]) - p.lo[i]
        } else {
            p.lo[i] = lo[i]
            p.r[i] = hi[i] - lo[i]
        }
        p.prodr = p.prodr * p.r[i]
        i += 1usize
    }
    let nz = 4.93038065763132378e-32f64
    var epsabs = epsabs0
    if epsabs < nz { epsabs = nz }
    var minsamples = nmin0
    if minsamples < 10usize { minsamples = 10usize }
    let nmin = nmin0
    let cap = 8usize + maxeval / 10usize
    let (mt, e3) = mem.alloc[u64](a, 625usize)
    let (regs, e4) = mem.alloc[SuReg](a, cap)
    let (ord, e5) = mem.alloc[usize](a, cap)
    let (tot, e6) = mem.alloc[f64](a, nc * 4usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret e1 }
    vg_rng_ini(mt, seed, d, maxeval)
    // the anchor region
    var r0 = &regs[0usize]
    let e7 = su_newreg(a, d, nc, nnew, nnew, r0)
    if e7 != ok { ret e7 }
    r0.div = 0usize
    r0.df = 0i64
    r0.nlast = 0usize
    i = 0usize
    while i < d {
        r0.lo[i] = 0.0f64
        r0.hi[i] = 1.0f64
        var bin = 0usize
        while bin < 64usize {
            r0.grid[i * 64usize + bin] = f64(bin + 1usize) / 64.0f64
            bin += 1usize
        }
        i += 1usize
    }
    var nreg = 1usize
    var nid = 1usize
    ord[0usize] = 0usize
    p.neval = 0usize
    su_sample(&p, mt, seed, r0, nnew, 0usize, nmin)
    var df = r0.df
    i = 0usize
    while i < nc * 4usize {
        tot[i] = r0.res[i]
        i += 1usize
    }
    var fail = 0usize
    var c9 = 0.0f64
    c9 = math.pow[f64](8.98846567431158e307f64, 2.0f64 / 3.0f64 / flatness)
    while true {
        var maxratio = 0.0f64 - 1.7976931348623157e308f64
        var maxcomp = 0usize
        var c = 0usize
        while c < nc {
            var me = epsrel * math.abs[f64](tot[c * 4usize])
            if epsabs > me { me = epsabs }
            let ratio = tot[c * 4usize + 1usize] / me
            if ratio > maxratio {
                maxratio = ratio
                maxcomp = 0usize // Cuba never advances comp in this loop
            }
            c += 1usize
        }
        if maxratio <= 1.0f64 && p.neval >= mineval { break }
        if p.neval >= maxeval {
            fail = 1usize
            break
        }
        if nid + 2usize >= cap { break }
        var maxerr = 0.0f64 - 1.7976931348623157e308f64
        var pos = 0usize
        i = 0usize
        while i < nreg {
            let er = regs[ord[i]].res[maxcomp * 4usize + 1usize]
            if er > maxerr {
                maxerr = er
                pos = i
            }
            i += 1usize
        }
        let rid = ord[pos]
        var reg = &regs[rid]
        // the fluctuations: Cuba clamps every occupied side to one constant (MaxL where MinL was meant), so only which sides hold samples matters
        var n0: [8]usize = zero
        var n1: [8]usize = zero
        var s = 0usize
        while s < reg.n {
            var k = 0usize
            while k < d {
                if reg.x[s * d + k] >= 0.5f64 * (reg.lo[k] + reg.hi[k]) {
                    n1[k] += 1usize
                } else {
                    n0[k] += 1usize
                }
                k += 1usize
            }
            s += 1usize
        }
        var bias = 2.0f64
        if epsrel >= 1.0e-50f64 {
            let wv = math.pow[f64](2.0f64, 0.0f64 - f64(reg.div) / f64(d)) / epsrel
            if wv > bias { bias = wv }
        }
        var minfluct = 1.7976931348623157e308f64
        var bd = 0usize
        var dim = 0usize
        while dim < d {
            var f0 = 0.0f64
            var f1 = 0.0f64
            if n0[dim] > 0usize { f0 = c9 }
            if n1[dim] > 0usize { f1 = c9 }
            let fl = (f0 + f1) * (bias - reg.hi[dim] + reg.lo[dim])
            if fl < minfluct {
                minfluct = fl
                bd = dim
            }
            dim += 1usize
        }
        var v0 = 0.0f64
        var v1 = 0.0f64
        if n0[bd] > 0usize { v0 = c9 }
        if n1[bd] > 0usize { v1 = c9 }
        minfluct = v0 + v1
        var nnewL = nnew
        if minfluct < 1.7976931348623157e308f64 {
            nnewL = nnew / 2usize
            // Fluct clamps every occupied side to the same long double c = (LDBL_MAX / 2)^flat, and minfluct is a double: c / double(c + c) is 4e-17 under one half, c / double(c) under one
            if n0[bd] > 0usize && n1[bd] > 0usize { nnewL = (nnew - 1usize) / 2usize }
            if n0[bd] > 0usize && n1[bd] == 0usize { nnewL = nnew - 1usize }
            if n0[bd] == 0usize && n1[bd] > 0usize { nnewL = 0usize }
            if nnewL < minsamples { nnewL = minsamples }
        }
        let nL = n0[bd] + nnewL
        var nnewR = nnew - nnewL
        if nnew < nnewL { nnewR = 0usize }
        if nnewR < minsamples { nnewR = minsamples }
        let nR = n1[bd] + nnewR
        let lid = nid
        let rid2 = nid + 1usize
        nid += 2usize
        var rl = &regs[lid]
        var rr = &regs[rid2]
        let e8 = su_newreg(a, d, nc, nL, nnewL, rl)
        let e9 = su_newreg(a, d, nc, nR, nnewR, rr)
        if e8 != ok || e9 != ok { ret e8 }
        rl.div = reg.div + 1usize
        rr.div = reg.div + 1usize
        let mid = 0.5f64 * (reg.lo[bd] + reg.hi[bd])
        // split the samples, keeping the end-of-batch marks
        var cl = 0usize
        var cr = 0usize
        var wlast = 0usize
        s = 0usize
        while s < reg.n {
            let fin = reg.w[s] < 0.0f64
            if reg.x[s * d + bd] < mid {
                if fin && cr > 0usize { rr.w[cr - 1usize] = 0.0f64 - math.abs[f64](rr.w[cr - 1usize]) }
                rl.w[cl] = reg.w[s]
                var k = 0usize
                while k < d {
                    rl.x[cl * d + k] = reg.x[s * d + k]
                    k += 1usize
                }
                k = 0usize
                while k < nc {
                    rl.f[cl * nc + k] = reg.f[s * nc + k]
                    k += 1usize
                }
                cl += 1usize
            } else {
                if fin && cl > 0usize { rl.w[cl - 1usize] = 0.0f64 - math.abs[f64](rl.w[cl - 1usize]) }
                rr.w[cr] = reg.w[s]
                var k = 0usize
                while k < d {
                    rr.x[cr * d + k] = reg.x[s * d + k]
                    k += 1usize
                }
                k = 0usize
                while k < nc {
                    rr.f[cr * nc + k] = reg.f[s * nc + k]
                    k += 1usize
                }
                cr += 1usize
            }
            if s + 1usize < reg.n && fin { wlast = s + 1usize }
            s += 1usize
        }
        // reweight the grid of the parent from the points of its newest batch
        var marg: [512]f64 = zero
        var scale: [4]f64 = zero
        if nc == 1usize {
            scale[0usize] = 1.0f64
        } else {
            var cc = 0usize
            while cc < nc {
                if tot[cc * 4usize] != 0.0f64 { scale[cc] = 1.0f64 / tot[cc * 4usize] }
                cc += 1usize
            }
        }
        var bi = 0usize
        s = wlast
        while s < reg.n {
            var fsq = 0.0f64
            var cc = 0usize
            while cc < nc {
                let vv = reg.f[s * nc + cc] * scale[cc]
                fsq += vv * vv
                cc += 1usize
            }
            fsq *= reg.w[s] * reg.w[s]
            if fsq != 0.0f64 {
                var k = 0usize
                while k < d {
                    marg[k * 64usize + reg.bin[bi * d + k]] += fsq
                    k += 1usize
                }
            }
            bi += 1usize
            s += 1usize
        }
        dim = 0usize
        while dim < d {
            su_refine(reg.grid[dim * 64usize..dim * 64usize + 64usize], marg[dim * 64usize..dim * 64usize + 64usize])
            dim += 1usize
        }
        i = 0usize
        while i < d {
            rl.lo[i] = reg.lo[i]
            rl.hi[i] = reg.hi[i]
            rr.lo[i] = reg.lo[i]
            rr.hi[i] = reg.hi[i]
            i += 1usize
        }
        i = 0usize
        while i < d * 64usize {
            rl.grid[i] = reg.grid[i]
            rr.grid[i] = reg.grid[i]
            i += 1usize
        }
        rl.hi[bd] = mid
        rr.lo[bd] = mid
        su_stretch(reg.grid[bd * 64usize..bd * 64usize + 64usize], rl.grid[bd * 64usize..bd * 64usize + 64usize], rr.grid[bd * 64usize..bd * 64usize + 64usize])
        su_sample(&p, mt, seed, rl, nnewL, cl, nmin)
        su_sample(&p, mt, seed, rr, nnewR, cr, nmin)
        // the list: L takes the place of the parent, R follows it
        i = nreg
        while i > pos + 1usize {
            ord[i] = ord[i - 1usize]
            i -= 1usize
        }
        ord[pos] = lid
        ord[pos + 1usize] = rid2
        nreg += 1usize
        df = df + rl.df + rr.df - reg.df
        c = 0usize
        while c < nc {
            let t = c * 4usize
            var diff = rl.res[t] + rr.res[t] - reg.res[t]
            tot[t] += diff
            diff = (0.25f64 * diff) * (0.25f64 * diff)
            let sg = rl.res[t + 2usize] + rr.res[t + 2usize]
            if sg > 0.0f64 {
                let q1 = 1.0f64 + math.sqrt[f64](diff / sg)
                let cf = q1 * q1
                rl.res[t + 2usize] *= cf
                rr.res[t + 2usize] *= cf
            }
            rl.res[t + 2usize] += diff
            rl.res[t + 1usize] = math.sqrt[f64](rl.res[t + 2usize])
            rr.res[t + 2usize] += diff
            rr.res[t + 1usize] = math.sqrt[f64](rr.res[t + 2usize])
            tot[t + 2usize] += rl.res[t + 2usize] + rr.res[t + 2usize] - reg.res[t + 2usize]
            tot[t + 1usize] = math.sqrt[f64](tot[t + 2usize])
            tot[t + 3usize] += rl.res[t + 3usize] + rr.res[t + 3usize] - reg.res[t + 3usize]
            c += 1usize
        }
    }
    var cm = 0usize
    while cm < nc {
        out[cm] = tot[cm * 4usize]
        out[nc + cm] = tot[cm * 4usize + 1usize]
        out[2usize * nc + 2usize + cm] = cu_chisq(tot[cm * 4usize + 3usize], df)
        cm += 1usize
    }
    out[2usize * nc] = f64(p.neval)
    out[2usize * nc + 1usize] = f64(nreg)
    out[3usize * nc + 2usize] = f64(fail)
    ret ok
}

// the Sobol initial values of Cuba (Random.c): nine numbers per dimension from the second, the first the primitive polynomial
fn vg_sobol_tab(t: []u64) {
    t[0usize] = 3u64
    t[1usize] = 1u64
    t[2usize] = 0u64
    t[3usize] = 0u64
    t[4usize] = 0u64
    t[5usize] = 0u64
    t[6usize] = 0u64
    t[7usize] = 0u64
    t[8usize] = 0u64
    t[9usize] = 7u64
    t[10usize] = 1u64
    t[11usize] = 1u64
    t[12usize] = 0u64
    t[13usize] = 0u64
    t[14usize] = 0u64
    t[15usize] = 0u64
    t[16usize] = 0u64
    t[17usize] = 0u64
    t[18usize] = 11u64
    t[19usize] = 1u64
    t[20usize] = 3u64
    t[21usize] = 7u64
    t[22usize] = 0u64
    t[23usize] = 0u64
    t[24usize] = 0u64
    t[25usize] = 0u64
    t[26usize] = 0u64
    t[27usize] = 13u64
    t[28usize] = 1u64
    t[29usize] = 1u64
    t[30usize] = 5u64
    t[31usize] = 0u64
    t[32usize] = 0u64
    t[33usize] = 0u64
    t[34usize] = 0u64
    t[35usize] = 0u64
    t[36usize] = 19u64
    t[37usize] = 1u64
    t[38usize] = 3u64
    t[39usize] = 1u64
    t[40usize] = 1u64
    t[41usize] = 0u64
    t[42usize] = 0u64
    t[43usize] = 0u64
    t[44usize] = 0u64
    t[45usize] = 25u64
    t[46usize] = 1u64
    t[47usize] = 1u64
    t[48usize] = 3u64
    t[49usize] = 7u64
    t[50usize] = 0u64
    t[51usize] = 0u64
    t[52usize] = 0u64
    t[53usize] = 0u64
    t[54usize] = 37u64
    t[55usize] = 1u64
    t[56usize] = 3u64
    t[57usize] = 3u64
    t[58usize] = 9u64
    t[59usize] = 9u64
    t[60usize] = 0u64
    t[61usize] = 0u64
    t[62usize] = 0u64
    t[63usize] = 59u64
    t[64usize] = 1u64
    t[65usize] = 3u64
    t[66usize] = 7u64
    t[67usize] = 13u64
    t[68usize] = 3u64
    t[69usize] = 0u64
    t[70usize] = 0u64
    t[71usize] = 0u64
    t[72usize] = 47u64
    t[73usize] = 1u64
    t[74usize] = 1u64
    t[75usize] = 5u64
    t[76usize] = 11u64
    t[77usize] = 27u64
    t[78usize] = 0u64
    t[79usize] = 0u64
    t[80usize] = 0u64
    t[81usize] = 61u64
    t[82usize] = 1u64
    t[83usize] = 3u64
    t[84usize] = 5u64
    t[85usize] = 1u64
    t[86usize] = 15u64
    t[87usize] = 0u64
    t[88usize] = 0u64
    t[89usize] = 0u64
    t[90usize] = 55u64
    t[91usize] = 1u64
    t[92usize] = 1u64
    t[93usize] = 7u64
    t[94usize] = 3u64
    t[95usize] = 29u64
    t[96usize] = 0u64
    t[97usize] = 0u64
    t[98usize] = 0u64
    t[99usize] = 41u64
    t[100usize] = 1u64
    t[101usize] = 3u64
    t[102usize] = 7u64
    t[103usize] = 7u64
    t[104usize] = 21u64
    t[105usize] = 0u64
    t[106usize] = 0u64
    t[107usize] = 0u64
    t[108usize] = 67u64
    t[109usize] = 1u64
    t[110usize] = 1u64
    t[111usize] = 1u64
    t[112usize] = 9u64
    t[113usize] = 23u64
    t[114usize] = 37u64
    t[115usize] = 0u64
    t[116usize] = 0u64
    t[117usize] = 97u64
    t[118usize] = 1u64
    t[119usize] = 3u64
    t[120usize] = 3u64
    t[121usize] = 5u64
    t[122usize] = 19u64
    t[123usize] = 33u64
    t[124usize] = 0u64
    t[125usize] = 0u64
    t[126usize] = 91u64
    t[127usize] = 1u64
    t[128usize] = 1u64
    t[129usize] = 3u64
    t[130usize] = 13u64
    t[131usize] = 11u64
    t[132usize] = 7u64
    t[133usize] = 0u64
    t[134usize] = 0u64
    t[135usize] = 109u64
    t[136usize] = 1u64
    t[137usize] = 1u64
    t[138usize] = 7u64
    t[139usize] = 13u64
    t[140usize] = 25u64
    t[141usize] = 5u64
    t[142usize] = 0u64
    t[143usize] = 0u64
    t[144usize] = 103u64
    t[145usize] = 1u64
    t[146usize] = 3u64
    t[147usize] = 5u64
    t[148usize] = 11u64
    t[149usize] = 7u64
    t[150usize] = 11u64
    t[151usize] = 0u64
    t[152usize] = 0u64
    t[153usize] = 115u64
    t[154usize] = 1u64
    t[155usize] = 1u64
    t[156usize] = 1u64
    t[157usize] = 3u64
    t[158usize] = 13u64
    t[159usize] = 39u64
    t[160usize] = 0u64
    t[161usize] = 0u64
    t[162usize] = 131u64
    t[163usize] = 1u64
    t[164usize] = 3u64
    t[165usize] = 1u64
    t[166usize] = 15u64
    t[167usize] = 17u64
    t[168usize] = 63u64
    t[169usize] = 13u64
    t[170usize] = 0u64
    t[171usize] = 193u64
    t[172usize] = 1u64
    t[173usize] = 1u64
    t[174usize] = 5u64
    t[175usize] = 5u64
    t[176usize] = 1u64
    t[177usize] = 27u64
    t[178usize] = 33u64
    t[179usize] = 0u64
    t[180usize] = 137u64
    t[181usize] = 1u64
    t[182usize] = 3u64
    t[183usize] = 3u64
    t[184usize] = 3u64
    t[185usize] = 25u64
    t[186usize] = 17u64
    t[187usize] = 115u64
    t[188usize] = 0u64
    t[189usize] = 145u64
    t[190usize] = 1u64
    t[191usize] = 1u64
    t[192usize] = 3u64
    t[193usize] = 15u64
    t[194usize] = 29u64
    t[195usize] = 15u64
    t[196usize] = 41u64
    t[197usize] = 0u64
    t[198usize] = 143u64
    t[199usize] = 1u64
    t[200usize] = 3u64
    t[201usize] = 1u64
    t[202usize] = 7u64
    t[203usize] = 3u64
    t[204usize] = 23u64
    t[205usize] = 79u64
    t[206usize] = 0u64
    t[207usize] = 241u64
    t[208usize] = 1u64
    t[209usize] = 3u64
    t[210usize] = 7u64
    t[211usize] = 9u64
    t[212usize] = 31u64
    t[213usize] = 29u64
    t[214usize] = 17u64
    t[215usize] = 0u64
    t[216usize] = 157u64
    t[217usize] = 1u64
    t[218usize] = 1u64
    t[219usize] = 5u64
    t[220usize] = 13u64
    t[221usize] = 11u64
    t[222usize] = 3u64
    t[223usize] = 29u64
    t[224usize] = 0u64
    t[225usize] = 185u64
    t[226usize] = 1u64
    t[227usize] = 3u64
    t[228usize] = 1u64
    t[229usize] = 9u64
    t[230usize] = 5u64
    t[231usize] = 21u64
    t[232usize] = 119u64
    t[233usize] = 0u64
    t[234usize] = 167u64
    t[235usize] = 1u64
    t[236usize] = 1u64
    t[237usize] = 3u64
    t[238usize] = 1u64
    t[239usize] = 23u64
    t[240usize] = 13u64
    t[241usize] = 75u64
    t[242usize] = 0u64
    t[243usize] = 229u64
    t[244usize] = 1u64
    t[245usize] = 3u64
    t[246usize] = 3u64
    t[247usize] = 11u64
    t[248usize] = 27u64
    t[249usize] = 31u64
    t[250usize] = 73u64
    t[251usize] = 0u64
    t[252usize] = 171u64
    t[253usize] = 1u64
    t[254usize] = 1u64
    t[255usize] = 7u64
    t[256usize] = 7u64
    t[257usize] = 19u64
    t[258usize] = 25u64
    t[259usize] = 105u64
    t[260usize] = 0u64
    t[261usize] = 213u64
    t[262usize] = 1u64
    t[263usize] = 3u64
    t[264usize] = 5u64
    t[265usize] = 5u64
    t[266usize] = 21u64
    t[267usize] = 9u64
    t[268usize] = 7u64
    t[269usize] = 0u64
    t[270usize] = 191u64
    t[271usize] = 1u64
    t[272usize] = 1u64
    t[273usize] = 1u64
    t[274usize] = 15u64
    t[275usize] = 5u64
    t[276usize] = 49u64
    t[277usize] = 59u64
    t[278usize] = 0u64
    t[279usize] = 253u64
    t[280usize] = 1u64
    t[281usize] = 1u64
    t[282usize] = 1u64
    t[283usize] = 1u64
    t[284usize] = 1u64
    t[285usize] = 33u64
    t[286usize] = 65u64
    t[287usize] = 0u64
    t[288usize] = 203u64
    t[289usize] = 1u64
    t[290usize] = 3u64
    t[291usize] = 5u64
    t[292usize] = 15u64
    t[293usize] = 17u64
    t[294usize] = 19u64
    t[295usize] = 21u64
    t[296usize] = 0u64
    t[297usize] = 211u64
    t[298usize] = 1u64
    t[299usize] = 1u64
    t[300usize] = 7u64
    t[301usize] = 11u64
    t[302usize] = 13u64
    t[303usize] = 29u64
    t[304usize] = 3u64
    t[305usize] = 0u64
    t[306usize] = 239u64
    t[307usize] = 1u64
    t[308usize] = 3u64
    t[309usize] = 7u64
    t[310usize] = 5u64
    t[311usize] = 7u64
    t[312usize] = 11u64
    t[313usize] = 113u64
    t[314usize] = 0u64
    t[315usize] = 247u64
    t[316usize] = 1u64
    t[317usize] = 1u64
    t[318usize] = 5u64
    t[319usize] = 3u64
    t[320usize] = 15u64
    t[321usize] = 19u64
    t[322usize] = 61u64
    t[323usize] = 0u64
    t[324usize] = 285u64
    t[325usize] = 1u64
    t[326usize] = 3u64
    t[327usize] = 1u64
    t[328usize] = 1u64
    t[329usize] = 9u64
    t[330usize] = 27u64
    t[331usize] = 89u64
    t[332usize] = 7u64
    t[333usize] = 369u64
    t[334usize] = 1u64
    t[335usize] = 1u64
    t[336usize] = 3u64
    t[337usize] = 7u64
    t[338usize] = 31u64
    t[339usize] = 15u64
    t[340usize] = 45u64
    t[341usize] = 23u64
    t[342usize] = 299u64
    t[343usize] = 1u64
    t[344usize] = 3u64
    t[345usize] = 3u64
    t[346usize] = 9u64
    t[347usize] = 9u64
    t[348usize] = 25u64
    t[349usize] = 107u64
    t[350usize] = 39u64
    t[351usize] = 0u64
    t[352usize] = 0u64
    t[353usize] = 0u64
    t[354usize] = 0u64
    t[355usize] = 0u64
    t[356usize] = 0u64
    t[357usize] = 0u64
    t[358usize] = 0u64
    t[359usize] = 0u64
}

// the random-number state of Vegas and Suave: seed 0 selects Cuba's Sobol sequence (st[0] the counter, st[1] the bit count, st[2..10) the previous point, st[16 + 32 dim + bit] the direction numbers), any other seed the Mersenne Twister
fn vg_rng_ini(st: []u64, seed: usize, d: usize, maxeval: usize) {
    if seed != 0usize {
        vg_mt_ini(st, u64(seed))
        ret
    }
    var tab: [360]u64 = zero
    vg_sobol_tab(tab[0usize..360usize])
    var nbits = 0usize
    var mx = maxeval
    while mx > 0usize {
        nbits += 1usize
        mx = mx >> 1usize
    }
    st[0usize] = 0u64
    st[1usize] = u64(nbits)
    var k = 0usize
    while k < 8usize {
        st[2usize + k] = 0u64
        k += 1usize
    }
    var bit = 0usize
    while bit <= nbits {
        st[16usize + bit] = 1u64 << u64(nbits - bit)
        bit += 1usize
    }
    var dim = 1usize
    while dim < d {
        let row = (dim - 1usize) * 9usize
        let powers = tab[row]
        var inibits = 0usize
        var jj = powers >> 1u64
        while jj != 0u64 {
            inibits += 1usize
            jj = jj >> 1u64
        }
        let pv = 16usize + dim * 32usize
        var i = 0usize
        while i < inibits {
            st[pv + i] = tab[row + 1usize + i]
            i += 1usize
        }
        var p = 0usize
        bit = inibits
        while bit <= nbits {
            var newv = st[pv + p]
            var j2 = powers
            var b = 0usize
            while b < inibits {
                if (j2 & 1u64) == 1u64 { newv = newv ^ (st[pv + p + b] << u64(inibits - b)) }
                j2 = j2 >> 1u64
                b += 1usize
            }
            st[pv + p + inibits] = newv
            p += 1usize
            bit += 1usize
        }
        bit = 0usize
        while bit < nbits {
            st[pv + bit] = st[pv + bit] << u64(nbits - bit)
            bit += 1usize
        }
        dim += 1usize
    }
}

fn vg_rng(st: []u64, seed: usize, d: usize, out: []f64) {
    var dim = 0usize
    if seed != 0usize {
        while dim < d {
            out[dim] = vg_mt_get(st)
            dim += 1usize
        }
        ret
    }
    var seq = st[0usize]
    st[0usize] += 1u64
    var zb = 0usize
    while (seq & 1u64) == 1u64 {
        zb += 1usize
        seq = seq >> 1u64
    }
    let nbits = usize(st[1usize])
    var norm = 0.5f64
    var q = 0usize
    while q < nbits {
        norm = norm * 0.5f64
        q += 1usize
    }
    while dim < d {
        st[2usize + dim] = st[2usize + dim] ^ st[16usize + dim * 32usize + zb]
        out[dim] = f64(st[2usize + dim]) * norm
        dim += 1usize
    }
}

// Divonne (Cuba, Friedman and Wright partitioning), Korobov sampling: the keys 1 to 39 (multiplicators) and 40 and up (point counts) for key1, key2 and key3; the cubature-rule keys 7, 9, 11, 13
// and the Sobol and pseudo-random samples are not ported, nor are xGiven and the peak finder. Regions are fixed records in one array; Cuba's depth, next and memmove bookkeeping is kept as it is.
type DvSm = struct { x: []f64, f: []f64, n: usize, neff: usize, coeff: usize, ready: usize }
type DvTot = struct { avg: f64, spreadsq: f64, spread: f64, secondspread: f64, nneed: f64, maxerrsq: f64, mindevsq: f64, integral: f64, sigsq: f64, chisq: f64, pa0: f64, pe0: f64, pa1: f64, pe1: f64, ireg: usize }
type DvRg = struct { depth: i64, next: i64, isamples: usize, cutcomp: usize, xmajor: usize, fmajor: f64, fminor: f64, vol: f64, bd: [16]f64, avg: [4]f64, err: [4]f64, spread: [4]f64, chisq: [4]f64, fmin: [4]f64, fmax: [4]f64, mm: [64]f64 }
type DvCut = struct { i: usize, save: f64, delta: f64, f: f64, df: f64, fold: f64, lhs: f64, row: f64, sol: f64 }
type DvPt = struct { dx: f64, f: f64 }
type Dv = struct { p: Cu, d: usize, nc: usize, epsrel: f64, epsabs: f64, mineval: i64, maxeval: i64, key1: i64, key2: i64, key3: i64, maxpass: i64, blo: f64, bhi: f64, maxchisq: f64, mindev: f64, neval: i64, neval_opt: i64, neval_cut: i64, selcomp: usize, seltag: f64, sm: [3]DvSm, tot: []DvTot, reg: []DvRg, nreg: usize, cap: usize, todo: []usize, nextdim: usize, prm: []i64, cof: []i64, over: i64, marked: usize }

fn dv_fmin(a: f64, b: f64) -> f64 {
    if a < b { ret a }
    ret b
}

fn dv_fmax(a: f64, b: f64) -> f64 {
    if a > b { ret a }
    ret b
}

fn dv_ceil(x: f64) -> f64 {
    var c = f64(i64(x))
    if c < x { c = c + 1.0f64 }
    ret c
}

fn dv_abs(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

fn dv_eval(st: *Dv, n: usize, x: []const f64, f: []f64) {
    let d = st.d
    let nc = st.nc
    st.neval = st.neval + i64(n)
    var i = 0usize
    while i < n {
        cu_eval(&st.p, x[i * d..(i + 1usize) * d], f[i * nc..(i + 1usize) * nc])
        i += 1usize
    }
}

// Cuba's Sample: the selected component at x0 clamped into the unit cube, extrapolated from the interior when x0 lies in the border; sign flipped when the maximum is sought
fn dv_sample(st: *Dv, x0: []const f64) -> f64 {
    let d = st.d
    var xtmp: [16]f64 = zero
    var ftmp: [8]f64 = zero
    var dist = 0.0f64
    var n = 1usize
    var dim = 0usize
    while dim < d {
        var x1 = x0[dim]
        if x1 < 0.0f64 { x1 = 0.0f64 }
        if x1 > 1.0f64 { x1 = 1.0f64 }
        xtmp[dim] = x1
        var dx = x1 - st.blo
        if dx < 0.0f64 {
            dist += dx * dx
        } else {
            dx = x1 - st.bhi
            if dx > 0.0f64 { dist += dx * dx }
        }
        dim += 1usize
    }
    if dist > 0.0f64 {
        dist = math.sqrt[f64](dist) / (0.25f64 * st.blo)
        dim = 0usize
        while dim < d {
            var x2 = xtmp[dim]
            var dx = x2 - st.blo
            if dx < 0.0f64 {
                xtmp[dim] = st.blo
                x2 = st.blo - dx / dist
            } else {
                dx = x2 - st.bhi
                if dx > 0.0f64 {
                    xtmp[dim] = st.bhi
                    x2 = st.bhi - dx / dist
                }
            }
            xtmp[d + dim] = x2
            dim += 1usize
        }
        n = 2usize
    }
    dv_eval(st, n, xtmp[0usize..16usize], ftmp[0usize..8usize])
    let big = 0.5f64 * 1.7976931348623157e308f64
    var f = ftmp[st.selcomp]
    f = dv_fmin(dv_fmax(f, 0.0f64 - big), big)
    if n > 1usize {
        var f2 = ftmp[st.selcomp + st.nc]
        f2 = dv_fmin(dv_fmax(f2, 0.0f64 - big), big)
        f = f + dist * (f - f2)
    }
    ret st.seltag * f
}

// Cuba's SamplesLookup for a Korobov sample: sets n and neff, and over (points beyond nmax) and marked (nmax below nmin)
fn dv_lookup(st: *Dv, k: usize, key: i64, nwant: i64, nmax: i64, nmin: i64) {
    let sm = &st.sm[k]
    var n = key
    if n == 0i64 { n = 1i64 }
    if n < 40i64 { n = n * nwant }
    n = n / 2i64 + 1i64
    var m = n
    if nmax < m { m = nmax }
    if m < 0i64 { m = 0i64 }
    sm.n = usize(m)
    sm.neff = sm.n
    st.over = 0i64
    if n > nmax { st.over = n - nmax }
    st.marked = 0usize
    if nmax - nmin < 0i64 { st.marked = 1usize }
}

// Cuba's SamplesAlloc for a Korobov sample: the first tabulated prime at or above 2 n - 1 gives the point count and the multiplicator
fn dv_alloc(st: *Dv, k: usize) {
    let sm = &st.sm[k]
    var n = 2i64 * i64(sm.n) - 1i64
    if n > 9689i64 { n = 9689i64 }
    var i = ((19945i64 - n) * (n - 47i64)) / 121634i64
    var shift = 2usize
    if n < 1000i64 { shift = 1usize }
    var p = 0i64
    while true {
        if i < 0i64 { i = 0i64 }
        if i > 813i64 { i = 813i64 }
        p = st.prm[usize(i) + 1usize]
        let lower = st.prm[usize(i)]
        if !(n > p || n <= lower) { break }
        shift = shift + 1usize
        let dd = (n - (p & 1073741823i64)) >> shift
        var step = dd
        if dd == 0i64 { step = 1i64 }
        i = i + step
    }
    p = p & 1073741823i64
    sm.coeff = usize(st.cof[usize(i) * 7usize + st.d - 2usize])
    sm.neff = usize(p)
    sm.n = usize(p / 2i64 + 1i64)
}

// Cuba's SampleKorobov over the region ireg with the sample set the region selects: point 0 is the upper corner, extrapolated when the border is nonzero
fn dv_kor(st: *Dv, ireg: usize) {
    let rg = &st.reg[ireg]
    let sm = &st.sm[rg.isamples]
    let d = st.d
    let nc = st.nc
    let n = sm.n
    let neff = i64(sm.neff)
    var xi = d
    var i = 1usize
    while i < n {
        var c = i64(i)
        var dim = 0usize
        while dim < d {
            var dd = 2i64 * c - neff
            if dd < 0i64 { dd = 0i64 - dd }
            let dx = f64(dd) / f64(neff)
            sm.x[xi] = rg.bd[2usize * dim] + dx * (rg.bd[2usize * dim + 1usize] - rg.bd[2usize * dim])
            xi += 1usize
            c = c * i64(sm.coeff) % neff
            dim += 1usize
        }
        i += 1usize
    }
    var dist = 0.0f64
    var dim = 0usize
    while dim < d {
        sm.x[dim] = rg.bd[2usize * dim + 1usize]
        let dx = sm.x[dim] - st.bhi
        if dx > 0.0f64 { dist += dx * dx }
        dim += 1usize
    }
    var nextra = 0usize
    if dist > 0.0f64 {
        dist = math.sqrt[f64](dist) / (0.25f64 * st.blo)
        dim = 0usize
        while dim < d {
            var x2 = sm.x[dim]
            let dx = x2 - st.bhi
            if dx > 0.0f64 {
                sm.x[dim] = st.bhi
                x2 = st.bhi - dx / dist
            }
            sm.x[xi + dim] = x2
            dim += 1usize
        }
        nextra = 1usize
    }
    dv_eval(st, n + nextra, sm.x, sm.f)
    var avg: [4]f64 = zero
    var c = 0usize
    while c < nc {
        avg[c] = sm.f[nc + c]
        c += 1usize
    }
    var fi = 2usize * nc
    i = 2usize
    while i < n {
        c = 0usize
        while c < nc {
            avg[c] += sm.f[fi]
            fi += 1usize
            c += 1usize
        }
        i += 1usize
    }
    if nextra == 1usize {
        c = 0usize
        while c < nc {
            sm.f[c] = sm.f[c] + dist * (sm.f[c] - sm.f[n * nc + c])
            c += 1usize
        }
        dim = 0usize
        while dim < d {
            sm.x[dim] = rg.bd[2usize * dim + 1usize]
            dim += 1usize
        }
    }
    let norm = rg.vol / f64(sm.neff)
    c = 0usize
    while c < nc {
        rg.avg[c] = norm * (avg[c] + avg[c] + sm.f[c])
        rg.err[c] = 0.0f64
        c += 1usize
    }
}

fn dv_dot(n: usize, a: []const f64, b: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += a[i] * b[i]
        i += 1usize
    }
    ret s
}

fn dv_len(n: usize, v: []const f64) -> f64 {
    ret math.sqrt[f64](dv_dot(n, v, v))
}

fn dv_lsolve(n: usize, d: usize, h: []const f64, grad: []const f64, p: []f64) {
    var i = 0usize
    while i < n {
        var dir = 0.0f64 - grad[i]
        var j = 0usize
        while j < i {
            dir = dir - h[i * d + j] * p[j]
            j += 1usize
        }
        p[i] = dir
        i += 1usize
    }
    while i > 0usize {
        i = i - 1usize
        if h[i * d + i] <= 0.0f64 { ret }
        var dir = p[i] / h[i * d + i]
        var j = i + 1usize
        while j < n {
            dir = dir - h[j * d + i] * p[j]
            j += 1usize
        }
        p[i] = dir
    }
}

fn dv_renorm(n: usize, d: usize, h: []f64, z: []f64, alpha0: f64) {
    var alpha = alpha0
    var i = 0usize
    while i < n {
        let dir = z[i]
        var beta = alpha * dir
        let gamma0 = h[i * d + i]
        h[i * d + i] = h[i * d + i] + beta * dir
        let gammanew = h[i * d + i]
        if i + 1usize >= n || gammanew < 0.0f64 || (gammanew < 1.0f64 && gamma0 > 1.7976931348623157e308f64 * gammanew) { ret }
        let gamma = gamma0 / gammanew
        beta = beta / gammanew
        alpha = alpha * gamma
        var j = i + 1usize
        if gamma < 0.25f64 {
            while j < n {
                let delta = beta * z[j]
                z[j] = z[j] - dir * h[j * d + i]
                h[j * d + i] = h[j * d + i] * gamma + delta
                j += 1usize
            }
        } else {
            while j < n {
                z[j] = z[j] - dir * h[j * d + i]
                h[j * d + i] = h[j * d + i] + beta * z[j]
                j += 1usize
            }
        }
        i += 1usize
    }
}

fn dv_updchol(n: usize, d: usize, h: []f64, z: []f64, p: []f64) {
    var gamma = 0.0f64
    var i = 0usize
    while i < n {
        var dir = z[i]
        var j = 0usize
        while j < i {
            dir = dir - h[i * d + j] * p[j]
            j += 1usize
        }
        p[i] = dir
        gamma += dir * dir / h[i * d + i]
        i += 1usize
    }
    gamma = dv_fmax(dv_abs(1.0f64 - gamma), 2.220446049250313e-16f64)
    while i > 0usize {
        i = i - 1usize
        let dir = p[i]
        z[i] = dir
        var beta = dir / h[i * d + i]
        let gammanew = gamma + dir * beta
        h[i * d + i] = h[i * d + i] * (gamma / gammanew)
        beta = beta / gamma
        gamma = gammanew
        var j = i + 1usize
        while j < n {
            let delta = beta * z[j]
            z[j] = z[j] + dir * h[j * d + i]
            h[j * d + i] = h[j * d + i] - delta
            j += 1usize
        }
    }
}

fn dv_bfgs(n: usize, d: usize, h: []f64, gnew: []const f64, g: []const f64, p: []f64, dx: f64) {
    var y: [8]f64 = zero
    var i = 0usize
    while i < n {
        y[i] = gnew[i] - g[i]
        i += 1usize
    }
    var c = dx * dv_dot(n, y[0usize..8usize], p)
    if c < 1.0e-10f64 { ret }
    dv_renorm(n, d, h, y[0usize..8usize], 1.0f64 / c)
    c = dv_dot(n, g, p)
    if c >= 0.0f64 { ret }
    c = 1.0f64 / math.sqrt[f64](0.0f64 - c)
    i = 0usize
    while i < n {
        y[i] = c * g[i]
        i += 1usize
    }
    dv_updchol(n, d, h, y[0usize..8usize], p)
    i = 0usize
    while i + 1usize < n {
        var j = i + 1usize
        while j < n {
            h[i * d + j] = h[j * d + i]
            j += 1usize
        }
        i += 1usize
    }
}

// the index lists carry the upper-bound tag as 1000 added to the dimension
fn dv_untag(v: i64) -> usize {
    if v >= 1000i64 { ret usize(v - 1000i64) }
    ret usize(v)
}

fn dv_gradient(st: *Dv, nfree: usize, ifx: []const i64, bd: []const f64, x: []f64, y: f64, grad: []f64) {
    var i = 0usize
    while i < nfree {
        let dim = dv_untag(ifx[i])
        let xd = x[dim]
        var delta = 1.52587890625e-05f64
        if bd[2usize * dim + 1usize] - xd < 1.52587890625e-05f64 { delta = 0.0f64 - 1.52587890625e-05f64 }
        x[dim] = x[dim] + delta
        grad[i] = (dv_sample(st, x) - y) / delta
        x[dim] = xd
        i += 1usize
    }
}

fn dv_linesearch(st: *Dv, nfree: usize, ifree: []const i64, p: []const f64, xini: []const f64, fini: f64, x: []f64, step0: f64, range: f64, grad: f64, ftol: f64, xtol: f64, gtol: f64) -> DvPt {
    let rteps = 1.4901161193847656e-08f64
    var step = step0
    var tol = ftol
    var tol2 = tol + tol
    var cur = DvPt { dx: 0.0f64, f: fini }
    var i = 0usize
    while i < st.d {
        x[i] = xini[i]
        i += 1usize
    }
    if step > 0.0f64 && range > tol2 && grad <= 0.0f64 {
        let eps = rteps * dv_abs(range) + ftol
        let mingrad = 0.0f64 - 1.0e-4f64 * grad
        let maxgrad = 0.0f64 - gtol * grad
        var end = range + eps
        var maxstep = range - eps / (1.0f64 + rteps)
        var mn = cur
        var v = cur
        var w = cur
        var a = cur
        var b = DvPt { dx: end, f: 0.0f64 }
        var a1 = 0.0f64
        var b1 = end
        var distmin = 0.0f64
        var dist = 0.0f64
        var mid = 0.0f64
        var q = 0.0f64
        var r = 0.0f64
        var s = 0.0f64
        var first = true
        while true {
            if step >= maxstep {
                step = maxstep
                maxstep = maxstep * (1.0f64 + 0.75f64 * rteps) + 0.75f64 * tol
            }
            if dv_abs(step) >= tol {
                cur.dx = step
            } else {
                if step > 0.0f64 { cur.dx = tol } else { cur.dx = 0.0f64 - tol }
            }
            dist = distmin + cur.dx
            i = 0usize
            while i < nfree {
                let dim = usize(ifree[i])
                x[dim] = xini[dim] + dist * p[i]
                i += 1usize
            }
            cur.f = dv_sample(st, x)
            if cur.f <= mn.f {
                v = w
                w = mn
                mn.f = cur.f
                distmin = dist
                maxstep = maxstep - cur.dx
                v.dx = v.dx - cur.dx
                w.dx = w.dx - cur.dx
                a.dx = a.dx - cur.dx
                b.dx = b.dx - cur.dx
                if cur.dx < 0.0f64 { b = w } else { a = w }
                tol = rteps * dv_abs(distmin) + ftol
                tol2 = tol + tol
            } else {
                if cur.dx < 0.0f64 { a = cur } else { b = cur }
                if cur.f <= w.f || w.dx == 0.0f64 {
                    v = w
                    w = cur
                } else {
                    if cur.f <= v.f || v.dx == 0.0f64 || v.dx == w.dx { v = cur }
                }
            }
            if distmin + b.dx <= xtol { break }
            if mn.f < fini && a.f - mn.f <= dv_abs(a.dx) * maxgrad && (dv_abs(distmin - range) > tol || maxstep < b.dx) { break }
            mid = 0.5f64 * (a.dx + b.dx)
            if dv_abs(mid) <= tol2 - 0.5f64 * (b.dx - a.dx) { break }
            r = 0.0f64
            q = 0.0f64
            s = 0.0f64
            if dv_abs(end) > tol {
                if first {
                    let s1 = w.dx * grad
                    let s2 = w.f - mn.f
                    var t2 = 0.0f64
                    if distmin != 0.0f64 { t2 = 2.0f64 * s2 }
                    s = (s1 - t2) * w.dx
                    q = 2.0f64 * (s2 - s1)
                } else {
                    let s1 = w.dx * (v.f - mn.f)
                    let s2 = v.dx * (w.f - mn.f)
                    s = s1 * w.dx - s2 * v.dx
                    q = 2.0f64 * (s2 - s1)
                }
                if q > 0.0f64 { s = 0.0f64 - s }
                q = dv_abs(q)
                r = end
                if step != b1 || b.dx <= maxstep { end = step }
            }
            if distmin == a.dx {
                step = mid
            } else {
                if b.dx > maxstep {
                    if step < b.dx { step = 0.0f64 - 4.0f64 * a.dx } else { step = maxstep }
                } else {
                    var num = a.dx
                    var den = b.dx
                    if dv_abs(b.dx) <= tol || (w.dx > 0.0f64 && dv_abs(a.dx) > tol) {
                        num = b.dx
                        den = a.dx
                    }
                    num = num / (0.0f64 - den)
                    if num < 1.0f64 {
                        step = 0.5f64 * den * math.sqrt[f64](num)
                    } else {
                        step = 5.0f64 / 11.0f64 * den * (0.1f64 + 1.0f64 / num)
                    }
                }
            }
            if step > 0.0f64 {
                a1 = a.dx
                b1 = step
            } else {
                a1 = step
                b1 = b.dx
            }
            if dv_abs(s) < dv_abs(0.5f64 * q * r) && s > q * a1 && s < q * b1 {
                step = s / q
                if step - a.dx < tol2 || b.dx - step < tol2 {
                    if mid > 0.0f64 { step = tol } else { step = 0.0f64 - tol }
                }
            } else {
                if mid > 0.0f64 { end = b.dx } else { end = a.dx }
            }
            first = false
        }
        first = true
        if dv_abs(distmin - range) < tol {
            distmin = range
            if maxstep > b.dx { first = false }
        }
        cur.dx = distmin
        cur.f = mn.f
        var shift = 1i64
        while true {
            i = 0usize
            while i < nfree {
                let dim = usize(ifree[i])
                x[dim] = xini[dim] + cur.dx * p[i]
                i += 1usize
            }
            if !first { cur.f = dv_sample(st, x) }
            if cur.dx + b.dx <= xtol {
                cur.dx = 0.0f64
                break
            }
            if fini - cur.f > cur.dx * mingrad { break }
            if cur.dx <= ftol {
                cur.dx = 0.0f64
                break
            }
            first = false
            var sc = distmin
            var k = 0i64
            while k < shift && sc > 1.0e-300f64 {
                sc = sc * 0.5f64
                k = k + 1i64
            }
            if k < shift { sc = 0.0f64 }
            cur.dx = dv_fmax(sc, ftol)
            shift = shift * 2i64
        }
    }
    ret cur
}

fn dv_localsearch(st: *Dv, nfree: usize, ifree: []const i64, bd: []const f64, x: []const f64, fx: f64, z: []f64) -> f64 {
    let rteps = 1.4901161193847656e-08f64
    let rtdelta = 0.00390625f64
    let suftol = 6.103515625e-05f64
    var y: [8]f64 = zero
    var p: [8]f64 = zero
    var delta = 0.0f64
    var smax = 1.7976931348623157e308f64
    var i = 0usize
    while i < nfree {
        let dim = usize(ifree[i])
        let sp = bd[2usize * dim + 1usize] - x[dim]
        let sn = x[dim] - bd[2usize * dim]
        if sp < sn {
            smax = dv_fmin(smax, sn)
            p[i] = 0.0f64 - 1.0f64
        } else {
            smax = dv_fmin(smax, sp)
            p[i] = 1.0f64
        }
        i += 1usize
    }
    smax = smax * 0.9f64
    i = 0usize
    while i < st.d {
        y[i] = x[i]
        i += 1usize
    }
    var ftest = suftol * (1.0f64 + dv_abs(fx))
    delta = rtdelta / 5.0f64
    var fy = 0.0f64
    while true {
        delta = dv_fmin(5.0f64 * delta, smax)
        i = 0usize
        while i < nfree {
            let dim = usize(ifree[i])
            y[dim] = x[dim] + delta * p[i]
            i += 1usize
        }
        fy = dv_sample(st, y[0usize..8usize])
        if dv_abs(fy - fx) > ftest { break }
        if delta == smax { break }
    }
    var sign = 0.0f64 - 1.0f64
    if nfree <= 1usize && fy > fx { sign = 1.0f64 }
    var spmax = 1.7976931348623157e308f64
    var snmax = 1.7976931348623157e308f64
    i = 0usize
    while i < nfree {
        let dim = usize(ifree[i])
        var mult = 0.0f64
        if (nfree & 1usize) == 1usize && nfree - i <= 2usize {
            mult = 0.0f64 - 0.5f64 * sign
        } else {
            sign = 0.0f64 - sign
            mult = sign
        }
        p[i] = p[i] * mult
        let sp = (bd[2usize * dim + 1usize] - y[dim]) / p[i]
        let sn = (y[dim] - bd[2usize * dim]) / p[i]
        if p[i] > 0.0f64 {
            spmax = dv_fmin(spmax, sp)
            snmax = dv_fmin(snmax, sn)
        } else {
            spmax = dv_fmin(spmax, 0.0f64 - sn)
            snmax = dv_fmin(snmax, 0.0f64 - sp)
        }
        i += 1usize
    }
    smax = 0.9f64 * spmax
    var sopp = 0.9f64 * snmax
    if nfree > 1usize && smax < snmax {
        let tmp = smax
        smax = sopp
        sopp = tmp
        i = 0usize
        while i < nfree {
            p[i] = 0.0f64 - p[i]
            i += 1usize
        }
    }
    i = 0usize
    while i < st.d {
        z[i] = y[i]
        i += 1usize
    }
    ftest = suftol * (1.0f64 + dv_abs(fy))
    delta = rtdelta / 5.0f64
    var fz = 0.0f64
    while true {
        delta = dv_fmin(5.0f64 * delta, smax)
        i = 0usize
        while i < nfree {
            let dim = usize(ifree[i])
            z[dim] = y[dim] + delta * p[i]
            i += 1usize
        }
        fz = dv_sample(st, z)
        if dv_abs(fz - fy) > ftest { break }
        if delta == smax { break }
    }
    if fy != fz {
        var grad = 0.0f64
        var range = 0.0f64
        var step = 0.0f64
        if fy > fz {
            grad = (fz - fy) / delta
            range = smax / 0.9f64
            step = dv_fmin(delta + delta, smax)
        } else {
            grad = (fy - fz) / delta
            range = sopp / 0.9f64 + delta
            step = dv_fmin(delta + delta, sopp)
            i = 0usize
            while i < st.d {
                y[i] = z[i]
                i += 1usize
            }
            fy = fz
            i = 0usize
            while i < nfree {
                p[i] = 0.0f64 - p[i]
                i += 1usize
            }
        }
        let pleneps = dv_len(nfree, p[0usize..8usize]) + rteps
        let low = dv_linesearch(st, nfree, ifree, p[0usize..8usize], y[0usize..8usize], fy, z, step, range, grad, rteps / pleneps, 0.0f64, rteps)
        fz = low.f
    }
    if fz != fx {
        spmax = 1.7976931348623157e308f64
        snmax = 1.7976931348623157e308f64
        i = 0usize
        while i < nfree {
            let dim = usize(ifree[i])
            p[i] = z[dim] - x[dim]
            if p[i] != 0.0f64 {
                let sp = (bd[2usize * dim + 1usize] - x[dim]) / p[i]
                let sn = (x[dim] - bd[2usize * dim]) / p[i]
                if p[i] > 0.0f64 {
                    spmax = dv_fmin(spmax, sp)
                    snmax = dv_fmin(snmax, sn)
                } else {
                    spmax = dv_fmin(spmax, 0.0f64 - sn)
                    snmax = dv_fmin(snmax, 0.0f64 - sp)
                }
            }
            i += 1usize
        }
        var grad = fz - fx
        var range = spmax
        var step = dv_fmin(0.9f64 * spmax, 2.0f64)
        let pleneps = dv_len(nfree, p[0usize..8usize]) + rteps
        if fz > fx {
            delta = dv_fmin(0.9f64 * snmax, rtdelta / pleneps)
            i = 0usize
            while i < nfree {
                let dim = usize(ifree[i])
                z[dim] = x[dim] - delta * p[i]
                i += 1usize
            }
            fz = dv_sample(st, z)
            if fz < fx {
                grad = (fz - fx) / delta
                range = snmax
                step = dv_fmin(0.9f64 * snmax, delta + delta)
                i = 0usize
                while i < nfree {
                    p[i] = 0.0f64 - p[i]
                    i += 1usize
                }
            } else {
                if delta < 1.0f64 { grad = (fx - fz) / delta }
            }
        }
        let low2 = dv_linesearch(st, nfree, ifree, p[0usize..8usize], x, fx, z, step, range, grad, rteps / pleneps, 0.0f64, rteps)
        fz = low2.f
    }
    ret fz
}

fn dv_findmin(st: *Dv, bd: []const f64, xmin: []f64, fmin0: f64) -> f64 {
    let d = st.d
    let rteps = 1.4901161193847656e-08f64
    let qeps = 1.220703125e-04f64
    let delta0 = 1.52587890625e-05f64
    var fmin = fmin0
    var hess: [64]f64 = zero
    var gfree: [8]f64 = zero
    var p: [8]f64 = zero
    var tmp: [8]f64 = zero
    var ifree: [8]i64 = zero
    var ifix: [8]i64 = zero
    var fini = fmin
    let maxeval = st.neval + i64(50usize * d)
    var nfree = 0usize
    var nfix = 0usize
    var dim = 0usize
    while dim < d {
        hess[dim * d + dim] = 1.0f64
        dim += 1usize
    }
    var skip2a = false
    var local = 0usize
    while local < 2usize {
        var resample = false
        nfree = 0usize
        nfix = 0usize
        dim = 0usize
        while dim < d {
            if xmin[dim] < bd[2usize * dim] + (1.0f64 + dv_abs(bd[2usize * dim])) * qeps {
                xmin[dim] = bd[2usize * dim]
                ifix[nfix] = i64(dim)
                nfix += 1usize
                resample = true
            } else {
                if xmin[dim] > bd[2usize * dim + 1usize] - (1.0f64 + dv_abs(bd[2usize * dim + 1usize])) * qeps {
                    xmin[dim] = bd[2usize * dim + 1usize]
                    ifix[nfix] = i64(dim) + 1000i64
                    nfix += 1usize
                    resample = true
                } else {
                    ifree[nfree] = i64(dim)
                    nfree += 1usize
                }
            }
            dim += 1usize
        }
        if resample {
            fmin = dv_sample(st, xmin)
            fini = fmin
        }
        if nfree == 0usize {
            skip2a = true
            break
        }
        dv_gradient(st, nfree, ifree[0usize..8usize], bd, xmin, fmin, gfree[0usize..8usize])
        if local == 1usize || dv_len(nfree, gfree[0usize..8usize]) > 0.01f64 { break }
        let ftmp = dv_localsearch(st, nfree, ifree[0usize..8usize], bd, xmin, fmin, tmp[0usize..8usize])
        if ftmp > fmin - (1.0f64 + dv_abs(fmin)) * rteps {
            skip2a = true
            break
        }
        fmin = ftmp
        dim = 0usize
        while dim < d {
            xmin[dim] = tmp[dim]
            dim += 1usize
        }
        local += 1usize
    }
    var mini = 0usize
    var minfix = 0i64
    while true {
        if !skip2a && st.neval > maxeval { break }
        var dofix = false
        var cont = false
        if !skip2a && nfree > 0usize {
            dv_lsolve(nfree, d, hess[0usize..64usize], gfree[0usize..8usize], p[0usize..8usize])
            let plen = dv_len(nfree, p[0usize..8usize])
            let pleneps = plen + rteps
            var minstep = 1.7976931348623157e308f64
            var i = 0usize
            mini = 0usize
            minfix = 0i64
            while i < nfree {
                let dm = usize(ifree[i])
                if dv_abs(p[i]) > 2.220446049250313e-16f64 {
                    var step = 0.0f64
                    var fix = 0i64
                    if p[i] < 0.0f64 {
                        step = (bd[2usize * dm] - xmin[dm]) / p[i]
                        fix = i64(dm)
                    } else {
                        step = (bd[2usize * dm + 1usize] - xmin[dm]) / p[i]
                        fix = i64(dm) + 1000i64
                    }
                    if step < minstep {
                        minstep = step
                        mini = i
                        minfix = fix
                    }
                }
                i += 1usize
            }
            if minstep * pleneps <= delta0 {
                dofix = true
            } else {
                let low = dv_linesearch(st, nfree, ifree[0usize..8usize], p[0usize..8usize], xmin, fmin, tmp[0usize..8usize], dv_fmin(minstep, 1.0f64), dv_fmin(minstep, 100.0f64), dv_dot(nfree, gfree[0usize..8usize], p[0usize..8usize]), rteps / pleneps, delta0 / pleneps, 0.2f64)
                if low.dx > 0.0f64 {
                    fmin = low.f
                    i = 0usize
                    while i < d {
                        xmin[i] = tmp[i]
                        i += 1usize
                    }
                    dv_gradient(st, nfree, ifree[0usize..8usize], bd, xmin, fmin, tmp[0usize..8usize])
                    dv_bfgs(nfree, d, hess[0usize..64usize], tmp[0usize..8usize], gfree[0usize..8usize], p[0usize..8usize], low.dx)
                    i = 0usize
                    while i < nfree {
                        gfree[i] = tmp[i]
                        i += 1usize
                    }
                    if dv_abs(low.dx - minstep) < qeps * minstep {
                        dofix = true
                    } else {
                        let fdiff = fini - fmin
                        fini = fmin
                        if fdiff > (1.0f64 + dv_abs(fmin)) * 0.05f64 || low.dx * plen > (1.0f64 + dv_len(d, xmin)) * 0.05f64 { cont = true }
                    }
                }
            }
        }
        skip2a = false
        if dofix {
            ifix[nfix] = minfix
            nfix += 1usize
            nfree = nfree - 1usize
            if mini < nfree {
                let diag = hess[mini * d + mini]
                var i = 0usize
                while i < mini {
                    tmp[i] = 0.0f64
                    i += 1usize
                }
                i = mini
                while i < nfree {
                    tmp[i] = hess[(i + 1usize) * d + mini]
                    i += 1usize
                }
                i = mini
                while i < nfree {
                    var j = 0usize
                    while j < i {
                        hess[i * d + j] = hess[(i + 1usize) * d + j]
                        j += 1usize
                    }
                    hess[i * d + i] = hess[(i + 1usize) * d + i + 1usize]
                    i += 1usize
                }
                dv_renorm(nfree, d, hess[0usize..64usize], tmp[0usize..8usize], diag)
                i = mini
                while i < nfree {
                    ifree[i] = ifree[i + 1usize]
                    gfree[i] = gfree[i + 1usize]
                    i += 1usize
                }
            }
            continue
        }
        if cont { continue }
        if nfix > 0usize {
            var mingrad = 1.7976931348623157e308f64
            var mi = 0usize
            var repeat = false
            dv_gradient(st, nfix, ifix[0usize..8usize], bd, xmin, fmin, tmp[0usize..8usize])
            var i = 0usize
            while i < nfix {
                var grad = tmp[i]
                if ifix[i] >= 1000i64 { grad = 0.0f64 - tmp[i] }
                if grad < 0.0f64 - rteps {
                    repeat = true
                    if grad < mingrad {
                        mingrad = grad
                        mi = i
                    }
                }
                i += 1usize
            }
            if repeat {
                gfree[nfree] = tmp[mi]
                ifree[nfree] = i64(dv_untag(ifix[mi]))
                i = 0usize
                while i < nfree {
                    hess[nfree * d + i] = 0.0f64
                    i += 1usize
                }
                hess[nfree * d + nfree] = 1.0f64
                nfree += 1usize
                nfix = nfix - 1usize
                i = mi
                while i < nfix {
                    ifix[i] = ifix[i + 1usize]
                    i += 1usize
                }
                continue
            }
        }
        break
    }
    ret fmin
}

fn dv_div(a: f64, b: f64) -> f64 {
    if b != 0.0f64 { ret a / b }
    ret a
}

fn dv_somecut(st: *Dv, cut: []DvCut, bd: []f64) {
    let d = st.d
    var xmid: [8]f64 = zero
    var dim = 0usize
    while dim < d {
        xmid[dim] = 0.5f64 * (bd[2usize * dim + 1usize] + bd[2usize * dim])
        dim += 1usize
    }
    let ymid = dv_sample(st, xmid[0usize..8usize])
    var maxdev = 0.0f64
    var maxdim = 0usize
    dim = 0usize
    while dim < d {
        let x = xmid[dim]
        xmid[dim] = bd[2usize * dim]
        let ylower = dv_sample(st, xmid[0usize..8usize])
        xmid[dim] = bd[2usize * dim + 1usize]
        let yupper = dv_sample(st, xmid[0usize..8usize])
        xmid[dim] = x
        let dev = dv_abs(ymid - 0.5f64 * (ylower + yupper))
        if dev >= maxdev {
            maxdev = dev
            maxdim = dim
        }
        dim += 1usize
    }
    if maxdev > 0.0f64 {
        st.nextdim = 0usize
    } else {
        maxdim = st.nextdim % d
        st.nextdim = st.nextdim + 1usize
    }
    cut[0usize].i = 2usize * maxdim + 1usize
    cut[0usize].save = bd[2usize * maxdim + 1usize]
    bd[2usize * maxdim + 1usize] = xmid[maxdim]
}

fn dv_volume(d: usize, delta: []const f64) -> f64 {
    var vol = 1.0f64
    var dim = 0usize
    while dim < d {
        vol = vol * (delta[2usize * dim] + delta[2usize * dim + 1usize])
        dim += 1usize
    }
    ret vol
}

fn dv_setupeqs(cut: []DvCut, ncuts: usize, f0: f64) -> f64 {
    var f = f0
    var sqsum = 0.0f64
    var c = ncuts
    while c > 0usize {
        c = c - 1usize
        cut[c].lhs = f - cut[c].f
        sqsum += cut[c].lhs * cut[c].lhs
        f = cut[c].f
    }
    ret sqsum
}

fn dv_solveeqs(cut: []DvCut, ncuts0: usize, delta: []f64, diff: f64) {
    var ncuts = ncuts0
    var last = 0.0f64
    var r = 1.0f64
    var c = 0usize
    while true {
        let dim = cut[c].i >> 1usize
        r = r - dv_div(diff, (delta[2usize * dim] + delta[2usize * dim + 1usize]) * cut[c].df)
        cut[c].row = r
        ncuts = ncuts - 1usize
        if ncuts == 0usize { break }
        last += r * cut[c].lhs
        c += 1usize
    }
    last = dv_div(cut[c].lhs - last, r)
    var ci = i64(c)
    while ci >= 0i64 {
        let k = usize(ci)
        cut[k].delta = delta[cut[k].i]
        let delmin = 0.0f64 - cut[k].delta
        let delmax = 0.5f64 * (delmin + cut[k].save)
        cut[k].sol = dv_div(last, cut[k].df)
        if cut[k].sol > delmax { cut[k].sol = 0.75f64 * delmax }
        if cut[k].sol < delmin { cut[k].sol = 0.75f64 * delmin }
        last += cut[k].lhs
        ci = ci - 1i64
    }
}

fn dv_signed(i: usize, delta: []const f64) -> f64 {
    if (i & 1usize) == 1usize { ret delta[i] }
    ret 0.0f64 - delta[i]
}

fn dv_findcuts(st: *Dv, cut: []DvCut, bd: []f64, vol: f64, xmajor: []f64, fmajor: f64, fdiff: f64) -> usize {
    let d = st.d
    var sign = 1.0f64
    if fdiff < 0.0f64 { sign = 0.0f64 - 1.0f64 }
    var ncuts = 0usize
    var delta: [16]f64 = zero
    var dim = 0usize
    while dim < d {
        let xsave = xmajor[dim]
        var dist = bd[2usize * dim + 1usize] - xsave
        if dist >= 0.05f64 * (bd[2usize * dim + 1usize] - bd[2usize * dim]) {
            cut[ncuts].i = 2usize * dim + 1usize
            cut[ncuts].save = dist
            dist = dist * 0.5f64
            xmajor[dim] = xmajor[dim] + dist
            cut[ncuts].f = dv_sample(st, xmajor)
            xmajor[dim] = xsave
            ncuts += 1usize
        }
        delta[2usize * dim + 1usize] = dist
        dim += 1usize
    }
    dim = 0usize
    while dim < d {
        let xsave = xmajor[dim]
        var dist = xsave - bd[2usize * dim]
        if dist >= 0.05f64 * (bd[2usize * dim + 1usize] - bd[2usize * dim]) {
            cut[ncuts].i = 2usize * dim
            cut[ncuts].save = dist
            dist = dist * 0.5f64
            xmajor[dim] = xmajor[dim] - dist
            cut[ncuts].f = dv_sample(st, xmajor)
            xmajor[dim] = xsave
            ncuts += 1usize
        }
        delta[2usize * dim] = dist
        dim += 1usize
    }
    if ncuts == 0usize {
        dv_somecut(st, cut, bd)
        ret 1usize
    }
    var gamma = 0.0f64
    var fgamma = 0.0f64
    while true {
        var mindiff = 1.7976931348623157e308f64
        var mincut = 0usize
        var ic = 0usize
        while ic < ncuts {
            let diff = dv_abs(fmajor - cut[ic].f)
            if diff <= mindiff {
                mindiff = diff
                mincut = ic
            }
            ic += 1usize
        }
        gamma = dv_volume(d, delta[0usize..16usize]) / vol
        fgamma = fmajor + (gamma - 1.0f64) * fdiff
        if sign * (cut[mincut].f - fgamma) < 0.0f64 { break }
        ncuts = ncuts - 1usize
        if ncuts == 0usize {
            dv_somecut(st, cut, bd)
            ret 1usize
        }
        delta[cut[mincut].i] = cut[mincut].save
        ic = mincut
        while ic < ncuts {
            cut[ic] = cut[ic + 1usize]
            ic += 1usize
        }
    }
    var icut = 0usize
    while icut < ncuts {
        cut[icut].fold = cut[icut].f
        cut[icut].df = (cut[icut].f - fmajor) / delta[cut[icut].i]
        icut += 1usize
    }
    var lhssq = dv_setupeqs(cut, ncuts, fgamma)
    while true {
        dv_solveeqs(cut, ncuts, delta[0usize..16usize], gamma * fdiff)
        var again = false
        var dv = 1i64
        while dv <= 16i64 {
            icut = 0usize
            while icut < ncuts {
                let xd = cut[icut].i >> 1usize
                let xsave = xmajor[xd]
                delta[cut[icut].i] = cut[icut].delta + cut[icut].sol / f64(dv)
                xmajor[xd] = xmajor[xd] + dv_signed(cut[icut].i, delta[0usize..16usize])
                cut[icut].f = dv_sample(st, xmajor)
                xmajor[xd] = xsave
                icut += 1usize
            }
            let gammanew = dv_volume(d, delta[0usize..16usize]) / vol
            fgamma = fmajor + (gammanew - 1.0f64) * fdiff
            let lhssqnew = dv_setupeqs(cut, ncuts, fgamma)
            if lhssqnew <= lhssq {
                if dv_abs(gammanew - gamma) < 0.1f64 * gamma { break }
                gamma = gammanew
                var fmax = dv_abs(fgamma)
                icut = 0usize
                while icut < ncuts {
                    let dfmin = 1.0e-4f64 * cut[icut].df
                    let sol = cut[icut].sol / f64(dv)
                    var df = cut[icut].f - cut[icut].fold
                    if dv_abs(df) > 1.0e-10f64 * dv_abs(sol) { df = df / sol } else { df = 1.0f64 }
                    if dv_abs(df) < dv_abs(dfmin) { cut[icut].df = dfmin } else { cut[icut].df = df }
                    fmax = dv_fmax(fmax, dv_abs(cut[icut].f))
                    cut[icut].fold = cut[icut].f
                    icut += 1usize
                }
                let lt = (1.0f64 + fmax) * 0.1f64
                if lhssqnew < lt * lt { break }
                lhssq = lhssqnew
                again = true
                break
            }
            dv = dv * 4i64
        }
        if !again { break }
    }
    icut = 0usize
    while icut < ncuts {
        let ci = cut[icut].i
        cut[icut].save = bd[ci]
        bd[ci] = xmajor[ci >> 1usize] + dv_signed(ci, delta[0usize..16usize])
        icut += 1usize
    }
    ret ncuts
}

fn dv_split(st: *Dv, ireg: usize) {
    let d = st.d
    let rg = &st.reg[ireg]
    var cut: [16]DvCut = zero
    st.selcomp = rg.cutcomp
    st.seltag = 1.0f64
    st.neval_cut = st.neval_cut - st.neval
    let xm = rg.xmajor
    var ncuts = dv_findcuts(st, cut[0usize..16usize], rg.bd[0usize..16usize], rg.vol, rg.mm[xm..xm + d], rg.fmajor, rg.fmajor - rg.fminor)
    st.neval_cut = st.neval_cut + st.neval
    var depth = rg.depth - i64(ncuts)
    ncuts += 1usize
    rg.depth = 0i64 - i64(ncuts)
    let succ = i64(ireg) + rg.next
    rg.next = i64(st.nreg) - i64(ireg)
    var nd = depth
    if nd < 0i64 { nd = 0i64 }
    let rn = &st.reg[st.nreg]
    var k = 0usize
    while k < 16usize {
        rn.bd[k] = rg.bd[k]
        k += 1usize
    }
    rn.depth = nd + 1i64
    rn.next = 1i64
    rn.isamples = 0usize
    var ic = 0usize
    var last = st.nreg
    while ncuts > 1usize {
        ncuts = ncuts - 1usize
        let ci = cut[ic].i
        let tmp = rg.bd[ci ^ 1usize]
        rg.bd[ci ^ 1usize] = rg.bd[ci]
        rg.bd[ci] = cut[ic].save
        st.nreg += 1usize
        last = st.nreg
        let rr = &st.reg[st.nreg]
        k = 0usize
        while k < 16usize {
            rr.bd[k] = rg.bd[k]
            k += 1usize
        }
        nd = depth
        if nd < 0i64 { nd = 0i64 }
        rr.depth = nd + 1i64
        rr.next = 1i64
        rr.isamples = 0usize
        depth = depth + 1i64
        rg.bd[ci ^ 1usize] = tmp
        ic += 1usize
    }
    let rl = &st.reg[last]
    rl.next = succ - i64(st.nreg)
    st.nreg += 1usize
}

// Cuba's ExploreSerial: sample the region when it is new, find the extrema of every component, decide the depth and split; answers the region index or -1 when every value was NaN
fn dv_explore(st: *Dv, ireg: usize) -> i64 {
    let d = st.d
    let nc = st.nc
    let inf = 1.7976931348623157e308f64
    let rg = &st.reg[ireg]
    var emin: [4]f64 = zero
    var emax: [4]f64 = zero
    var imin: [4]i64 = zero
    var imax: [4]i64 = zero
    var c = 0usize
    while c < nc {
        emin[c] = inf
        emax[c] = 0.0f64 - inf
        imin[c] = 0i64 - 1i64
        imax[c] = 0i64 - 1i64
        c += 1usize
    }
    let k0 = rg.isamples
    if k0 == 0usize {
        var vol = 1.0f64
        var dim = 0usize
        while dim < d {
            vol = vol * (rg.bd[2usize * dim + 1usize] - rg.bd[2usize * dim])
            dim += 1usize
        }
        rg.vol = vol
        c = 0usize
        while c < nc {
            rg.fmin[c] = inf
            rg.fmax[c] = 0.0f64 - inf
            c += 1usize
        }
        dv_kor(st, ireg)
    }
    let sm = &st.sm[k0]
    var i = 0usize
    while i < sm.n {
        c = 0usize
        while c < nc {
            let y = sm.f[i * nc + c]
            if y < emin[c] {
                emin[c] = y
                imin[c] = i64(i)
            }
            if y > emax[c] {
                emax[c] = y
                imax[c] = i64(i)
            }
            c += 1usize
        }
        i += 1usize
    }
    st.neval_opt = st.neval_opt - st.neval
    let halfvol = 0.5f64 * rg.vol
    var maxerr = 0.0f64 - inf
    var maxcomp = 0i64 - 1i64
    var xtmp: [8]f64 = zero
    c = 0usize
    while c < nc {
        if imin[c] >= 0i64 {
            st.selcomp = c
            st.seltag = 1.0f64
            var j = 0usize
            while j < d {
                xtmp[j] = sm.x[usize(imin[c]) * d + j]
                j += 1usize
            }
            let ftmp = dv_findmin(st, rg.bd[0usize..16usize], xtmp[0usize..8usize], emin[c])
            if ftmp < rg.fmin[c] {
                rg.fmin[c] = ftmp
                j = 0usize
                while j < d {
                    rg.mm[2usize * c * d + j] = xtmp[j]
                    j += 1usize
                }
            }
            st.seltag = 0.0f64 - 1.0f64
            j = 0usize
            while j < d {
                xtmp[j] = sm.x[usize(imax[c]) * d + j]
                j += 1usize
            }
            let ftmp2 = 0.0f64 - dv_findmin(st, rg.bd[0usize..16usize], xtmp[0usize..8usize], 0.0f64 - emax[c])
            if ftmp2 > rg.fmax[c] {
                rg.fmax[c] = ftmp2
                j = 0usize
                while j < d {
                    rg.mm[(2usize * c + 1usize) * d + j] = xtmp[j]
                    j += 1usize
                }
            }
        }
        rg.spread[c] = halfvol * (rg.fmax[c] - rg.fmin[c])
        let er = rg.spread[c] / dv_fmax(dv_abs(rg.avg[c]), 4.930380657631324e-32f64)
        if er > maxerr {
            maxerr = er
            maxcomp = i64(c)
        }
        c += 1usize
    }
    st.neval_opt = st.neval_opt + st.neval
    if maxcomp == 0i64 - 1i64 {
        rg.depth = 0i64
        ret 0i64 - 1i64
    }
    let mc = usize(maxcomp)
    rg.cutcomp = mc
    if halfvol * (rg.fmin[mc] + rg.fmax[mc]) > rg.avg[mc] {
        rg.fminor = rg.fmin[mc]
        rg.fmajor = rg.fmax[mc]
        rg.xmajor = (2usize * mc + 1usize) * d
    } else {
        rg.fminor = rg.fmax[mc]
        rg.fmajor = rg.fmin[mc]
        rg.xmajor = 2usize * mc * d
    }
    if k0 == 0usize {
        if (rg.depth < 3i64 && rg.spread[mc] < f64(sm.neff) * rg.err[mc]) || rg.spread[mc] < st.tot[mc].secondspread { rg.depth = 0i64 }
        if rg.depth == 0i64 {
            c = 0usize
            while c < nc {
                st.tot[c].secondspread = dv_fmax(st.tot[c].secondspread, rg.spread[c])
                c += 1usize
            }
        }
    }
    if rg.depth != 0i64 { dv_split(st, ireg) }
    ret i64(ireg)
}

// Cuba's Iterate: explore the regions of a subtree, then correct their errors and spreads with the difference of every split parent from its children, and drop the parents from the array
fn dv_iterate(st: *Dv, iregion0: usize, depth: i64, isamples: i64, wtot: bool) {
    let nc = st.nc
    var iregion = iregion0
    var mreg = i64(iregion)
    st.reg[iregion].depth = depth
    st.reg[iregion].next = 0i64 - i64(iregion) - 1i64
    if isamples < 0i64 {
        dv_split(st, iregion)
    } else {
        st.reg[iregion].isamples = usize(isamples)
        let _e = dv_explore(st, iregion)
    }
    var ireg = i64(iregion) + st.reg[iregion].next
    while true {
        if st.reg[usize(ireg)].depth > 0i64 {
            st.reg[usize(ireg)].depth = st.reg[usize(ireg)].depth - 1i64
            ireg = dv_explore(st, usize(ireg))
            if ireg == 0i64 - 1i64 { ret }
        }
        if st.reg[usize(ireg)].depth < 0i64 {
            if ireg > mreg { mreg = ireg }
        }
        ireg = ireg + st.reg[usize(ireg)].next
        if ireg <= 0i64 { break }
    }
    var cavg: [4]f64 = zero
    var cerr: [4]f64 = zero
    var cspr: [4]f64 = zero
    var csq: [4]f64 = zero
    ireg = mreg
    while ireg >= i64(iregion) {
        let parent = &st.reg[usize(ireg)]
        if parent.depth < 0i64 {
            var c = 0usize
            while c < nc {
                cavg[c] = 0.0f64
                cerr[c] = 0.0f64
                cspr[c] = 0.0f64
                csq[c] = 0.0f64
                c += 1usize
            }
            var ntd = 0usize
            var nsplit = 0usize
            st.todo[0usize] = usize(ireg + parent.next)
            st.todo[1usize] = usize(i64(st.todo[0usize]) - parent.depth)
            ntd = 1usize
            var td = 0usize
            while td < ntd {
                var xreg = st.todo[2usize * td]
                let xend = st.todo[2usize * td + 1usize]
                while xreg < xend {
                    let rx = &st.reg[xreg]
                    if rx.depth < 0i64 {
                        st.todo[2usize * ntd] = usize(i64(xreg) + rx.next)
                        st.todo[2usize * ntd + 1usize] = usize(i64(st.todo[2usize * ntd]) - rx.depth)
                        ntd += 1usize
                    } else {
                        nsplit += 1usize
                        c = 0usize
                        while c < nc {
                            cavg[c] += rx.avg[c]
                            cerr[c] += rx.err[c]
                            cspr[c] += rx.spread[c] * rx.spread[c]
                            c += 1usize
                        }
                    }
                    xreg += 1usize
                }
                td += 1usize
            }
            let norm = 1.0f64 / f64(nsplit)
            nsplit = nsplit - 1usize
            c = 0usize
            while c < nc {
                let diff = dv_abs(parent.avg[c] - cavg[c]) * norm
                cavg[c] = diff * norm * f64(nsplit)
                if cerr[c] == 0.0f64 { cerr[c] = 1.0f64 } else { cerr[c] = 1.0f64 + diff / cerr[c] }
                if cspr[c] == 0.0f64 { cspr[c] = 1.0f64 } else { cspr[c] = 1.0f64 + diff / math.sqrt[f64](cspr[c]) }
                c += 1usize
            }
            td = 0usize
            while td < ntd {
                var xreg = st.todo[2usize * td]
                let xend = st.todo[2usize * td + 1usize]
                while xreg < xend {
                    let rx = &st.reg[xreg]
                    if rx.depth >= 0i64 {
                        let neff = f64(st.sm[rx.isamples].neff)
                        c = 0usize
                        while c < nc {
                            if rx.err[c] > 0.0f64 { rx.err[c] = rx.err[c] * cerr[c] + cavg[c] }
                            rx.spread[c] = rx.spread[c] * cspr[c] + cavg[c] * neff
                            csq[c] += rx.spread[c] * rx.spread[c]
                            c += 1usize
                        }
                    }
                    xreg += 1usize
                }
                td += 1usize
            }
        }
        ireg = ireg - 1i64
    }
    if wtot {
        var c = 0usize
        while c < nc {
            st.tot[c].spreadsq = st.tot[c].spreadsq + csq[c]
            c += 1usize
        }
    }
    var last = 0i64 - 1i64
    var idest = iregion
    var isrc = iregion
    while i64(iregion) <= mreg {
        var cur = 0i64
        if st.reg[iregion].depth < 0i64 { cur = 0i64 - 1i64 }
        let df = cur - last
        if df == 0i64 - 1i64 {
            var k = 0usize
            while k < iregion - isrc {
                st.reg[idest + k] = st.reg[isrc + k]
                k += 1usize
            }
            idest = idest + (iregion - isrc)
        }
        if df == 1i64 { isrc = iregion }
        last = cur
        iregion += 1usize
    }
    var k = 0usize
    while k < st.nreg - iregion {
        st.reg[idest + k] = st.reg[iregion + k]
        k += 1usize
    }
    st.nreg = st.nreg - (iregion - idest)
}

fn dv_badkey(key: i64, d: i64) -> bool {
    if key < 0i64 { ret true }
    if key == 7i64 || key == 9i64 { ret true }
    if key == 11i64 && d == 3i64 { ret true }
    if key == 13i64 && d == 2i64 { ret true }
    ret false
}

// Divonne as the R package calls it (final = 1, Korobov samples, no given points, border as passed): out[0 .. nc) the integrals, out[nc .. 2 nc) the errors, out[2 nc] the evaluations, out[2 nc + 1] the regions,
// out[2 nc + 2 .. 3 nc + 1] the chi-square probabilities, out[3 nc + 2] the return code (-1 dimension out of range, -3 a key outside the ported ones)
fn divonne(a: *mem.Arena, id: usize, vec: usize, d: usize, lo: []const f64, hi: []const f64, epsrel: f64, epsabs0: f64, mineval: usize, maxeval: usize, key1: i64, key2: i64, key3: i64, maxpass: usize, border: f64, maxchisq: f64, mindev: f64, out: []f64) -> err {
    var nc0 = 1usize
    if vec == 1usize {
        nc0 = 2usize
        if id >= 1usize { nc0 = 3usize }
    }
    let nc = nc0
    if d < 2usize || d > 8usize {
        out[3usize * nc + 2usize] = 0.0f64 - 1.0f64
        ret ok
    }
    if dv_badkey(key1, i64(d)) || dv_badkey(key2, i64(d)) || (key3 > 1i64 && dv_badkey(key3, i64(d))) || key3 < 0i64 {
        out[3usize * nc + 2usize] = 0.0f64 - 3.0f64
        ret ok
    }
    let cap = 6000usize
    let (sn, e1) = mem.alloc[usize](a, 1usize)
    let (wt, e2) = mem.alloc[f64](a, 1usize)
    let (rgs, e3) = mem.alloc[DvRg](a, cap)
    let (todo, e4) = mem.alloc[usize](a, 2usize * cap)
    let (tots, e5) = mem.alloc[DvTot](a, nc)
    let (prm, e6) = mem.alloc[i64](a, 815usize)
    let (cof, e7) = mem.alloc[i64](a, 814usize * 7usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret e1 }
    var st = Dv { p: Cu { id: id, vec: vec, nc: nc, d: d, inf: 0usize, lo: zero, r: zero, prodr: 1.0f64, rn: 0usize, ns: 0usize, sn: sn, wt: wt, sc: wt, nm: wt, gen: wt, e0: 0.0f64, e1: 0.0f64, e2: 0.0f64, x: wt, f: wt, neval: 0usize }, d: d, nc: nc, epsrel: epsrel, epsabs: epsabs0, mineval: i64(mineval), maxeval: i64(maxeval), key1: key1, key2: key2, key3: key3, maxpass: i64(maxpass), blo: border, bhi: 1.0f64 - border, maxchisq: maxchisq, mindev: mindev, neval: 0i64, neval_opt: 0i64, neval_cut: 0i64, selcomp: 0usize, seltag: 1.0f64, sm: zero, tot: tots, reg: rgs, nreg: 0usize, cap: cap, todo: todo, nextdim: 0usize, prm: prm, cof: cof, over: 0i64, marked: 0usize }
    if st.epsabs < 4.930380657631324e-32f64 { st.epsabs = 4.930380657631324e-32f64 }
    var i = 0usize
    while i < d {
        if math.abs[f64](lo[i]) >= 1.0e100f64 || math.abs[f64](hi[i]) >= 1.0e100f64 { st.p.inf = 1usize }
        i += 1usize
    }
    i = 0usize
    while i < d {
        if st.p.inf == 1usize {
            st.p.lo[i] = math.atan[f64](lo[i])
            st.p.r[i] = math.atan[f64](hi[i]) - st.p.lo[i]
        } else {
            st.p.lo[i] = lo[i]
            st.p.r[i] = hi[i] - lo[i]
        }
        st.p.prodr = st.p.prodr * st.p.r[i]
        i += 1usize
    }
    let ptxt = kt.kor_primes()
    let ctxt = kt.kor_coeffs()
    st.prm[0usize] = 0i64 - 2147483647i64
    i = 0usize
    while i < 814usize {
        var v = 0i64
        var j = 0usize
        while j < 5usize {
            v = v * 10i64 + i64(ptxt[i * 5usize + j]) - 48i64
            j += 1usize
        }
        st.prm[i + 1usize] = v
        i += 1usize
    }
    st.prm[814usize] = st.prm[814usize] + 1073741824i64
    i = 0usize
    while i < 814usize * 7usize {
        var v = 0i64
        var j = 0usize
        while j < 5usize {
            v = v * 10i64 + i64(ctxt[i * 5usize + j]) - 48i64
            j += 1usize
        }
        st.cof[i] = v
        i += 1usize
    }
    var k = 0usize
    while k < 3usize {
        let (sx, e8) = mem.alloc[f64](a, 4847usize * d)
        let (sf, e9) = mem.alloc[f64](a, 4847usize * nc)
        if e8 != ok || e9 != ok { ret e8 }
        st.sm[k].x = sx
        st.sm[k].f = sf
        st.sm[k].ready = 0usize
        k += 1usize
    }
    let zr: DvRg = zero
    let zt: DvTot = zero
    k = 0usize
    while k < cap {
        st.reg[k] = zr
        k += 1usize
    }
    k = 0usize
    while k < nc {
        st.tot[k] = zt
        k += 1usize
    }
    let imax = 2147483647i64
    dv_lookup(&st, 0usize, key1, 47i64, imax, 0i64)
    dv_alloc(&st, 0usize)
    st.sm[0usize].ready = 1usize
    i = 0usize
    while i < d {
        st.reg[0usize].bd[2usize * i] = 0.0f64
        st.reg[0usize].bd[2usize * i + 1usize] = 1.0f64
        i += 1usize
    }
    st.nreg = 1usize
    var nmin = imax
    var pass = 0i64
    var fail = 0i64
    var integral: [4]f64 = zero
    var errest: [4]f64 = zero
    var prob: [4]f64 = zero
    let big = 1.7976931348623157e308f64
    dv_iterate(&st, 0usize, 3i64, 0i64, false)
    while true {
        var c = 0usize
        while c < nc {
            st.tot[c].avg = 0.0f64
            st.tot[c].spreadsq = 0.0f64
            st.tot[c].spread = 0.0f64 - big
            st.tot[c].secondspread = 0.0f64 - big
            c += 1usize
        }
        var ir = 0usize
        while ir < st.nreg {
            c = 0usize
            while c < nc {
                let sp = st.reg[ir].spread[c]
                st.tot[c].avg = st.tot[c].avg + st.reg[ir].avg[c]
                st.tot[c].spreadsq = st.tot[c].spreadsq + sp * sp
                if sp > st.tot[c].spread {
                    st.tot[c].secondspread = st.tot[c].spread
                    st.tot[c].spread = sp
                    st.tot[c].ireg = ir
                } else {
                    if sp > st.tot[c].secondspread { st.tot[c].secondspread = sp }
                }
                c += 1usize
            }
            ir += 1usize
        }
        var maxtot = 0usize
        c = 0usize
        while c < nc {
            integral[c] = st.tot[c].avg
            if st.tot[c].spreadsq > st.tot[maxtot].spreadsq { maxtot = c }
            st.tot[c].spread = math.sqrt[f64](st.tot[c].spreadsq)
            errest[c] = st.tot[c].spread / f64(st.sm[0usize].neff)
            c += 1usize
        }
        if st.neval > st.maxeval { break }
        var maxerr = st.epsrel * dv_abs(st.tot[maxtot].avg)
        if st.epsabs > maxerr { maxerr = st.epsabs }
        let nneed = st.tot[maxtot].spread / maxerr
        if nneed < 9689.0f64 {
            let n = st.neval + i64(st.nreg) * i64(dv_ceil(nneed))
            if n < nmin {
                nmin = n
                pass = 0i64
            } else {
                pass = pass + 1i64
                if pass > st.maxpass && n >= st.mineval { break }
            }
        }
        dv_iterate(&st, st.tot[maxtot].ireg, 5i64, 0i64 - 1i64, false)
    }
    var nneed = 2.0f64 * f64(st.sm[0usize].neff)
    var c = 0usize
    while c < nc {
        var maxerr = st.epsrel * dv_abs(st.tot[c].avg)
        if st.epsabs > maxerr { maxerr = st.epsabs }
        st.tot[c].nneed = st.tot[c].spread / maxerr
        nneed = dv_fmax(nneed, st.tot[c].nneed)
        st.tot[c].maxerrsq = maxerr * maxerr
        st.tot[c].mindevsq = st.tot[c].maxerrsq * (st.mindev * st.mindev)
        c += 1usize
    }
    var nwant = i64(dv_fmin(dv_ceil(nneed), 53687091.2f64))
    dv_lookup(&st, 1usize, key2, nwant, (st.maxeval - st.neval) / i64(st.nreg) + 1i64, i64(st.sm[0usize].n) + 1i64)
    fail = st.over * i64(st.nreg)
    var df = 0i64
    if st.marked == 1usize {
        c = 0usize
        while c < nc {
            prob[c] = 0.0f64 - 999.0f64
            c += 1usize
        }
    } else {
        var can_adjust = st.key3 == 1i64 && st.sm[1usize].neff < 9689usize
        dv_alloc(&st, 1usize)
        st.sm[1usize].ready = 1usize
        var nlimit = st.maxeval - i64(st.nreg) * i64(st.sm[1usize].n)
        var ir = 0usize
        while ir < st.nreg {
            var again = true
            while again {
                again = false
                let rg = &st.reg[ir]
                c = 0usize
                while c < nc {
                    st.tot[c].pa0 = rg.avg[c]
                    st.tot[c].pe0 = rg.err[c]
                    c += 1usize
                }
                rg.isamples = 1usize
                dv_kor(&st, ir)
                c = 0usize
                while c < nc {
                    st.tot[c].pa1 = rg.avg[c]
                    st.tot[c].pe1 = rg.err[c]
                    c += 1usize
                }
                if can_adjust {
                    c = 0usize
                    while c < nc {
                        st.tot[c].spreadsq = st.tot[c].spreadsq - rg.spread[c] * rg.spread[c]
                        c += 1usize
                    }
                }
                nlimit = nlimit + i64(st.sm[1usize].n)
                var todo2 = 0usize
                c = 0usize
                while c < nc {
                    if st.neval < nlimit {
                        let avg2 = st.tot[c].pa1
                        let diffsq = (avg2 - st.tot[c].pa0) * (avg2 - st.tot[c].pa0)
                        var e0 = st.tot[c].pe0
                        if e0 == 0.0f64 { e0 = rg.spread[0usize] / f64(st.sm[0usize].neff) }
                        var e1v = st.tot[c].pe1
                        if e1v == 0.0f64 { e1v = rg.spread[0usize] / f64(st.sm[1usize].neff) }
                        let lim = dv_fmax(st.maxchisq * (e0 * e0 + e1v * e1v), 2.220446049250313e-16f64 * avg2 * avg2)
                        if rg.err[0usize] * st.tot[c].nneed > rg.spread[0usize] || diffsq > lim {
                            if st.key3 != 0i64 && diffsq > st.tot[c].mindevsq {
                                if st.key3 == 1i64 {
                                    rg.isamples = 1usize
                                    dv_iterate(&st, ir, 15i64, 1i64, true)
                                    if can_adjust {
                                        var nnew = 2147483647i64
                                        if !(st.tot[c].spreadsq / (2147483647.0f64 * 2147483647.0f64) > st.tot[c].maxerrsq) {
                                            nnew = i64(dv_ceil(math.sqrt[f64](st.tot[c].spreadsq / st.tot[c].maxerrsq)))
                                        }
                                        if nnew > nwant + nwant / 64i64 {
                                            dv_lookup(&st, 1usize, key2, nnew, (st.maxeval - st.neval) / i64(st.nreg) + 1i64, i64(st.sm[1usize].n))
                                            fail = fail + st.over * i64(st.nreg)
                                            nwant = nnew
                                            dv_alloc(&st, 1usize)
                                            if st.key2 > 0i64 && st.sm[1usize].neff >= 9689usize { can_adjust = false }
                                        }
                                    }
                                    again = true
                                    break
                                }
                                todo2 = todo2 | 3usize
                            }
                            todo2 = todo2 | 1usize
                        }
                    }
                    c += 1usize
                }
                if again { continue }
                if can_adjust {
                    c = 0usize
                    while c < nc {
                        let q = rg.spread[c] / f64(st.sm[1usize].neff)
                        st.tot[c].maxerrsq = st.tot[c].maxerrsq - q * q
                        c += 1usize
                    }
                }
                if todo2 == 1usize {
                    rg.isamples = 1usize
                    let _e = dv_explore(&st, ir)
                }
                if todo2 == 3usize {
                    if st.sm[2usize].ready == 0usize {
                        dv_lookup(&st, 2usize, key3, nwant, imax, 0i64)
                        dv_alloc(&st, 2usize)
                        st.sm[2usize].ready = 1usize
                    }
                    rg.isamples = 2usize
                    dv_kor(&st, ir)
                    let _e2 = dv_explore(&st, ir)
                    rg.depth = rg.depth + 1i64
                    df = df + 1i64
                }
                c = 0usize
                while c < nc {
                    let x1 = st.tot[c].pa0
                    var w1 = st.tot[c].pe0
                    if w1 == 0.0f64 { w1 = rg.spread[c] / f64(st.sm[0usize].neff) }
                    let v1 = w1 * w1
                    let x2 = st.tot[c].pa1
                    var w2 = st.tot[c].pe1
                    if w2 == 0.0f64 { w2 = rg.spread[c] / f64(st.sm[1usize].neff) }
                    let v2 = w2 * w2
                    var r2 = 0.0f64
                    if v1 != 0.0f64 {
                        r2 = v2 / v1
                    } else {
                        let rr = f64(st.sm[1usize].neff) / f64(st.sm[0usize].neff)
                        r2 = rr * rr
                    }
                    var sigsq = v2
                    var chisq = (x2 - x1) * (x2 - x1)
                    var chiden = v1 + v2
                    if todo2 == 3usize {
                        let x3 = rg.avg[c]
                        var w3 = rg.err[c]
                        if w3 == 0.0f64 { w3 = rg.spread[c] / f64(st.sm[2usize].neff) }
                        let v3 = w3 * w3
                        var r3 = 0.0f64
                        if v2 != 0.0f64 {
                            r3 = v3 / v2
                        } else {
                            let rr = f64(st.sm[2usize].neff) / f64(st.sm[1usize].neff)
                            r3 = rr * rr
                        }
                        sigsq = v3
                        chisq = v1 * (x3 - x2) * (x3 - x2) + v2 * (x3 - x1) * (x3 - x1) + v3 * chisq
                        chiden = v1 * v2 + v3 * chiden
                    }
                    let avg = rg.avg[c]
                    if chisq > 2.220446049250313e-16f64 { chisq = chisq / dv_fmax(chiden, 4.930380657631324e-32f64) }
                    st.tot[c].integral = st.tot[c].integral + avg
                    st.tot[c].sigsq = st.tot[c].sigsq + sigsq
                    st.tot[c].chisq = st.tot[c].chisq + chisq
                    rg.avg[c] = avg
                    rg.spread[c] = math.sqrt[f64](sigsq)
                    rg.chisq[c] = chisq
                    c += 1usize
                }
            }
            ir += 1usize
        }
        df = df + i64(st.nreg)
        c = 0usize
        while c < nc {
            integral[c] = st.tot[c].integral
            errest[c] = math.sqrt[f64](st.tot[c].sigsq)
            prob[c] = cu_chisq(st.tot[c].chisq, df)
            c += 1usize
        }
    }
    c = 0usize
    while c < nc {
        out[c] = integral[c]
        out[nc + c] = errest[c]
        out[2usize * nc + 2usize + c] = prob[c]
        c += 1usize
    }
    out[2usize * nc] = f64(st.neval)
    out[2usize * nc + 1usize] = f64(st.nreg)
    out[3usize * nc + 2usize] = f64(fail)
    ret ok
}
