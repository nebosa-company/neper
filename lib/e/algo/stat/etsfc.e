// forecast.ets prediction intervals beyond the closed forms of etsfit.ets_var: class3 (error M, season M, trend N, A or Ad) by
// its matrix recursion, and the simulated intervals of every other model (pegelsfcast.C: npaths = 5000 paths of h steps through
// simulate.ets, innovations rnorm(h, 0, sqrt(sigma2)) drawn path by path from R's generator, errors floored at -1 for
// multiplicative error, quantile type 8 of each column).
//
// Not here: bootstrap = TRUE, user innovations and simulated intervals under a Box-Cox lambda (ets(lambda) is additive only,
// which makes its intervals class1).

use e.math
use e.mem
use e.algo.rand.r as rr
use e.algo.stat.classint as ci
use e.algo.stat.etsfit as es

fn alloc(ar: *mem.Arena, n: usize) -> []f64 {
    let (s, e) = mem.alloc[f64](ar, n + 1usize)
    var i = 0usize
    while i < n {
        s[i] = 0.0f64
        i += 1usize
    }
    ret s[0usize..n]
}

// out (r x c) = a (r x k) times b (k x c), row-major
fn mm(a: []const f64, r: usize, k: usize, b: []const f64, c: usize, out: []f64) {
    var i = 0usize
    while i < r {
        var j = 0usize
        while j < c {
            var s = 0.0f64
            var l = 0usize
            while l < k {
                s += a[i * k + l] * b[l * c + j]
                l += 1usize
            }
            out[i * c + j] = s
            j += 1usize
        }
        i += 1usize
    }
}

// out (r x c) = transpose of a (c x r)
fn tr(a: []const f64, r: usize, c: usize, out: []f64) {
    var i = 0usize
    while i < r {
        var j = 0usize
        while j < c {
            out[i * c + j] = a[j * r + i]
            j += 1usize
        }
        i += 1usize
    }
}

// the Kronecker product a (ar x ac) x b (br x bc)
fn kron(a: []const f64, ar_: usize, ac: usize, b: []const f64, br: usize, bc: usize, out: []f64) {
    let cols = ac * bc
    var i = 0usize
    while i < ar_ * br {
        var j = 0usize
        while j < cols {
            out[i * cols + j] = a[(i / br) * ac + j / bc] * b[(i % br) * bc + j % bc]
            j += 1usize
        }
        i += 1usize
    }
}

// forecast.ets class3: the mean mu and the variance var (h long) of a multiplicative-error, multiplicative-season model whose trend is N, A or
// damped A, from its last state and sigma2
fn ets_class3(ar: *mem.Arena, fit: *const es.EtsFit, h: usize, mu: []f64, vr: []f64) {
    let m = fit.m
    let p = fit.p
    var rr1 = 1usize
    if fit.tt != 0usize { rr1 = 2usize }
    let dd = rr1 * m
    var phi = 1.0f64
    if fit.damped { phi = fit.phi }
    let last = fit.states[p * fit.n..p * (fit.n + 1usize)]
    let s2 = fit.sigma2
    let f1 = alloc(ar, rr1 * rr1)
    let g1 = alloc(ar, rr1 * rr1)
    f1[0usize] = 1.0f64
    g1[0usize] = fit.alpha
    if rr1 == 2usize {
        f1[1usize] = 1.0f64
        f1[3usize] = phi
        g1[1usize] = fit.alpha
        g1[2usize] = fit.beta
        g1[3usize] = fit.beta
    }
    let f2 = alloc(ar, m * m)
    let g2 = alloc(ar, m * m)
    f2[m - 1usize] = 1.0f64
    var i = 1usize
    while i < m {
        f2[i * m + i - 1usize] = 1.0f64
        i += 1usize
    }
    g2[m - 1usize] = fit.gamma
    let f21 = alloc(ar, dd * dd)
    let g21 = alloc(ar, dd * dd)
    let k1 = alloc(ar, dd * dd)
    let k2 = alloc(ar, dd * dd)
    kron(f2, m, m, f1, rr1, rr1, f21)
    kron(g2, m, m, g1, rr1, rr1, g21)
    kron(g2, m, m, f1, rr1, rr1, k1)
    kron(f2, m, m, g1, rr1, rr1, k2)
    let kk = alloc(ar, dd * dd)
    i = 0usize
    while i < dd * dd {
        kk[i] = k1[i] + k2[i]
        i += 1usize
    }
    // Mh = last[0..rr] (column) times last[p - m..p] (row): rr x m
    let mh = alloc(ar, dd)
    i = 0usize
    while i < rr1 {
        var j = 0usize
        while j < m {
            mh[i * m + j] = last[i] * last[p - m + j]
            j += 1usize
        }
        i += 1usize
    }
    let vh = alloc(ar, dd * dd)
    let vec = alloc(ar, dd)
    let vv = alloc(ar, dd * dd)
    let w1 = alloc(ar, dd * dd)
    let w2 = alloc(ar, dd * dd)
    let w3 = alloc(ar, dd * dd)
    let w4 = alloc(ar, dd * dd)
    let t1 = alloc(ar, dd * dd)
    let t2 = alloc(ar, dd * dd)
    let nh = alloc(ar, dd)
    let tm = alloc(ar, dd)
    let acc = alloc(ar, dd * dd)
    var step = 0usize
    while step < h {
        var mus = 0.0f64
        i = 0usize
        while i < rr1 {
            mus += mh[i * m + m - 1usize]
            i += 1usize
        }
        mu[step] = mus
        // H21 Vh H21' : H21 = H2 x H1 has ones at the entries (m - 1) * rr + (0..rr) of the column-major vec ordering
        var q = 0.0f64
        i = 0usize
        while i < rr1 {
            var j = 0usize
            while j < rr1 {
                q += vh[((m - 1usize) * rr1 + i) * dd + (m - 1usize) * rr1 + j]
                j += 1usize
            }
            i += 1usize
        }
        vr[step] = (1.0f64 + s2) * q + s2 * (mus * mus)
        // vec(Mh) column-major
        i = 0usize
        while i < rr1 {
            var j = 0usize
            while j < m {
                vec[j * rr1 + i] = mh[i * m + j]
                j += 1usize
            }
            i += 1usize
        }
        i = 0usize
        while i < dd {
            var j = 0usize
            while j < dd {
                vv[i * dd + j] = vec[i] * vec[j]
                j += 1usize
            }
            i += 1usize
        }
        // terms with the old Vh
        tr(f21, dd, dd, t1)
        mm(f21, dd, dd, vh, dd, w1)
        mm(w1, dd, dd, t1, dd, w2)
        // acc = F21 Vh G21' + G21 Vh F21'
        tr(g21, dd, dd, t2)
        mm(w1, dd, dd, t2, dd, w3)
        mm(g21, dd, dd, vh, dd, w1)
        mm(w1, dd, dd, t1, dd, w4)
        i = 0usize
        while i < dd * dd {
            acc[i] = w3[i] + w4[i]
            i += 1usize
        }
        // K (Vh + vv') K'
        i = 0usize
        while i < dd * dd {
            w1[i] = vh[i] + vv[i]
            i += 1usize
        }
        mm(kk, dd, dd, w1, dd, w3)
        tr(kk, dd, dd, t1)
        mm(w3, dd, dd, t1, dd, w4)
        i = 0usize
        while i < dd * dd {
            acc[i] += w4[i]
            i += 1usize
        }
        // s2 G21 (3 Vh + 2 vv') G21'
        i = 0usize
        while i < dd * dd {
            w1[i] = 3.0f64 * vh[i] + 2.0f64 * vv[i]
            i += 1usize
        }
        mm(g21, dd, dd, w1, dd, w3)
        mm(w3, dd, dd, t2, dd, w4)
        i = 0usize
        while i < dd * dd {
            acc[i] += s2 * w4[i]
            i += 1usize
        }
        i = 0usize
        while i < dd * dd {
            vh[i] = w2[i] + s2 * acc[i]
            i += 1usize
        }
        // Mh = F1 Mh F2' + s2 G1 Mh G2'
        tr(f2, m, m, t1)
        mm(f1, rr1, rr1, mh, m, w1)
        mm(w1, rr1, m, t1, m, w3)
        tr(g2, m, m, t2)
        mm(g1, rr1, rr1, mh, m, w1)
        mm(w1, rr1, m, t2, m, w4)
        i = 0usize
        while i < dd {
            nh[i] = w3[i] + s2 * w4[i]
            i += 1usize
        }
        i = 0usize
        while i < dd {
            mh[i] = nh[i]
            i += 1usize
        }
        step += 1usize
    }
}

// pegelsfcast.C intervals: npaths simulated paths of h steps from the fit's last state; the 80 and 95 percent limits (type 8 quantiles)
// land in lo80, up80, lo95, up95 (h long each). False when a path cannot be simulated.
fn ets_sim_pi(ar: *mem.Arena, fit: *const es.EtsFit, h: usize, npaths: usize, g: *rr.Rng, lo80: []f64, up80: []f64, lo95: []f64, up95: []f64) -> bool {
    let p = fit.p
    let m = fit.m
    let last = fit.states[p * fit.n..p * (fit.n + 1usize)]
    var phi = 1.0f64
    if fit.damped { phi = fit.phi }
    var beta = 0.0f64
    if fit.tt != 0usize { beta = fit.beta }
    var gamma = 0.0f64
    if fit.st != 0usize { gamma = fit.gamma }
    var off = 1usize
    if fit.tt != 0usize { off = 2usize }
    let sd = math.sqrt[f64](fit.sigma2)
    let paths = alloc(ar, npaths * h)
    let s = alloc(ar, m + 1usize)
    let olds = alloc(ar, m + 1usize)
    let f = alloc(ar, 2usize)
    var path = 0usize
    while path < npaths {
        let st = mem.mark(ar)
        var l = last[0usize]
        var b = 0.0f64
        if fit.tt != 0usize { b = last[1usize] }
        var i = 0usize
        if fit.st != 0usize {
            while i < m {
                s[i] = last[off + i]
                i += 1usize
            }
        }
        var step = 0usize
        var bad = false
        while step < h {
            var e = rr.rnorm(g, 0.0f64, sd)
            if fit.et == 2usize && e < 0.0f64 - 1.0f64 { e = 0.0f64 - 1.0f64 }
            let oldl = l
            var oldb = 0.0f64
            if fit.tt != 0usize { oldb = b }
            if fit.st != 0usize {
                i = 0usize
                while i < m {
                    olds[i] = s[i]
                    i += 1usize
                }
            }
            es.es_forecast(oldl, oldb, olds, m, fit.tt, fit.st, phi, f, 1usize, 1usize)
            if f[0usize] != f[0usize] { bad = true }
            var y = f[0usize] + e
            if fit.et == 2usize { y = f[0usize] * (1.0f64 + e) }
            paths[path * h + step] = y
            if !bad {
                let (nl, nb) = es.es_update(oldl, oldb, olds, s, m, fit.tt, fit.st, fit.alpha, beta, gamma, phi, y)
                l = nl
                b = nb
            }
            step += 1usize
        }
        if bad { ret false }
        mem.reset(ar, st)
        path += 1usize
    }
    let col = alloc(ar, npaths)
    var step2 = 0usize
    while step2 < h {
        var k = 0usize
        while k < npaths {
            col[k] = paths[k * h + step2]
            k += 1usize
        }
        ci.sort_up(col)
        lo80[step2] = ci.quantile_r(col, 0.1f64, 8u8)
        up80[step2] = ci.quantile_r(col, 0.9f64, 8u8)
        lo95[step2] = ci.quantile_r(col, 0.025f64, 8u8)
        up95[step2] = ci.quantile_r(col, 0.975f64, 8u8)
        step2 += 1usize
    }
    ret true
}
