// R gstat prediction: point kriging of any nested, anisotropic model (e.algo.stat.gstatvgm) with an arbitrary drift design: ordinary and universal kriging (the
// generalised covariance system of gls.c, with the kriging variance), simple kriging with known coefficients, the neighbourhood of nmax, maxdist and nmin,
// krige.cv with folds, and sequential Gaussian conditional simulation along R's random path (predict.gstat with nsim): the coefficient draws from their GLS
// distribution, one normal per node and realisation, the simulated values stored as single precision as gstat does when nsim > 1.
//
// Not here: block kriging, indicator and multivariable kriging, measurement-error (Err) adjustments, octant search, variogram-distance search and unconditional simulation.

use e.algo.rand.r as rr
use e.algo.stat.carlmtest as ols
use e.algo.stat.gstatvgm as gv
use e.math
use e.mem

fn nan_value() -> f64 { ret 0.0f64 / 0.0f64 }

// the covariance sum(sill) - gamma(lag) of gstat's generalised covariance, or the true covariance when exact is set
fn cov_lag(ms: []const f64, nst: usize, dx: f64, dy: f64, exact: bool) -> f64 {
    if exact { ret gv.model_cov(ms, nst, dx, dy) }
    var s = 0.0f64
    var k = 0usize
    while k < nst {
        s += ms[6usize * k + 1usize]
        k += 1usize
    }
    ret s - gv.model_gamma(ms, nst, dx, dy)
}

// the neighbourhood of (px, py): the indices of the points within maxdist (negative: no limit), nearest first, at most nmax (0: all); an empty answer when fewer than nmin
// are within maxdist. Returns the count.
fn select_nb(xy: []const f64, n: usize, px: f64, py: f64, nmax: usize, maxdist: f64, nmin: usize, idx: []usize, dd: []f64) -> usize {
    var cnt = 0usize
    var i = 0usize
    while i < n {
        let dx = xy[2usize * i] - px
        let dy = xy[2usize * i + 1usize] - py
        let d2 = dx * dx + dy * dy
        var ok_in = true
        if maxdist >= 0.0f64 && d2 > maxdist * maxdist { ok_in = false }
        if ok_in {
            var at = cnt
            while at > 0usize && dd[at - 1usize] > d2 {
                dd[at] = dd[at - 1usize]
                idx[at] = idx[at - 1usize]
                at -= 1usize
            }
            dd[at] = d2
            idx[at] = i
            cnt += 1usize
        }
        i += 1usize
    }
    if nmax > 0usize && cnt > nmax { cnt = nmax }
    if maxdist >= 0.0f64 && cnt < nmin { cnt = 0usize }
    ret cnt
}

// the lower Cholesky factor of the symmetric m by m matrix c (row-major, in place); false when it is not positive definite
fn chol_lower(c: []f64, m: usize) -> bool {
    var j = 0usize
    while j < m {
        var d = c[j * m + j]
        var k = 0usize
        while k < j {
            d -= c[j * m + k] * c[j * m + k]
            k += 1usize
        }
        if !(d > 0.0f64) { ret false }
        let dj = math.sqrt[f64](d)
        c[j * m + j] = dj
        var i = j + 1usize
        while i < m {
            var s = c[i * m + j]
            k = 0usize
            while k < j {
                s -= c[i * m + k] * c[j * m + k]
                k += 1usize
            }
            c[i * m + j] = s / dj
            i += 1usize
        }
        j += 1usize
    }
    ret true
}

// solves (L L') x = b with the factor from chol_lower, in place on b
fn chol_apply(l: []const f64, m: usize, b: []f64) {
    var i = 0usize
    while i < m {
        var s = b[i]
        var k = 0usize
        while k < i {
            s -= l[i * m + k] * b[k]
            k += 1usize
        }
        b[i] = s / l[i * m + i]
        i += 1usize
    }
    i = m
    while i > 0usize {
        i -= 1usize
        var s = b[i]
        var k = i + 1usize
        while k < m {
            s -= l[k * m + i] * b[k]
            k += 1usize
        }
        b[i] = s / l[i * m + i]
    }
}

// generalised least squares prediction at (px, py) from the m points xy with values z and drift rows X (m by p; x0 the drift at the target). blup: universal kriging, the
// coefficients estimated from the m points, on the generalised covariance; otherwise the coefficients are beta (simple kriging, true covariance). out: prediction,
// variance, then the p coefficients. A singular system answers NaN.
fn gls_predict(a: *mem.Arena, xy: []const f64, z: []const f64, xd: []const f64, m: usize, p: usize, x0: []const f64, px: f64, py: f64, ms: []const f64, nst: usize, blup: bool, beta: []const f64, out: []f64) -> err {
    out[0usize] = nan_value()
    out[1usize] = nan_value()
    if m == 0usize { ret ok }
    let exact = !blup
    let (c, e1) = mem.alloc[f64](a, m * m)
    if e1 != ok { ret e1 }
    let (c0, e2) = mem.alloc[f64](a, m)
    if e2 != ok { ret e2 }
    let (ciy, e3) = mem.alloc[f64](a, m)
    if e3 != ok { ret e3 }
    let (cic, e4) = mem.alloc[f64](a, m)
    if e4 != ok { ret e4 }
    let (cix, e5) = mem.alloc[f64](a, m * p)
    if e5 != ok { ret e5 }
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < m {
            c[i * m + j] = cov_lag(ms, nst, xy[2usize * i] - xy[2usize * j], xy[2usize * i + 1usize] - xy[2usize * j + 1usize], exact)
            j += 1usize
        }
        c0[i] = cov_lag(ms, nst, xy[2usize * i] - px, xy[2usize * i + 1usize] - py, exact)
        ciy[i] = z[i]
        cic[i] = c0[i]
        i += 1usize
    }
    if !chol_lower(c, m) { ret ok }
    chol_apply(c, m, ciy)
    chol_apply(c, m, cic)
    var v0 = cov_lag(ms, nst, 0.0f64, 0.0f64, exact)
    var c0ciy = 0.0f64
    var c0cic = 0.0f64
    i = 0usize
    while i < m {
        c0ciy += c0[i] * ciy[i]
        c0cic += c0[i] * cic[i]
        i += 1usize
    }
    var q = 0usize
    while q < p {
        i = 0usize
        while i < m {
            cix[i * p + q] = xd[i * p + q]
            i += 1usize
        }
        i = 0usize
        let (col, e6) = mem.alloc[f64](a, m)
        if e6 != ok { ret e6 }
        while i < m {
            col[i] = xd[i * p + q]
            i += 1usize
        }
        chol_apply(c, m, col)
        i = 0usize
        while i < m {
            cix[i * p + q] = col[i]
            i += 1usize
        }
        q += 1usize
    }
    let (b, e7) = mem.alloc[f64](a, p)
    if e7 != ok { ret e7 }
    let (ainv, e8) = mem.alloc[f64](a, p * p)
    if e8 != ok { ret e8 }
    if blup {
        let (am, e9) = mem.alloc[f64](a, p * p)
        if e9 != ok { ret e9 }
        var r = 0usize
        while r < p {
            var s = 0usize
            while s < p {
                var t = 0.0f64
                i = 0usize
                while i < m {
                    t += xd[i * p + r] * cix[i * p + s]
                    i += 1usize
                }
                am[r * p + s] = t
                s += 1usize
            }
            r += 1usize
        }
        if ols.inverse(a, am, p, ainv) != ok { ret ok }
        r = 0usize
        while r < p {
            var t = 0.0f64
            var s = 0usize
            while s < p {
                var xty = 0.0f64
                i = 0usize
                while i < m {
                    xty += xd[i * p + s] * ciy[i]
                    i += 1usize
                }
                t += ainv[r * p + s] * xty
                s += 1usize
            }
            b[r] = t
            r += 1usize
        }
    }
    if !blup {
        q = 0usize
        while q < p {
            b[q] = beta[q]
            q += 1usize
        }
    }
    // prediction: x0 beta + c0' C^-1 (y - X beta)
    var pred = 0.0f64
    q = 0usize
    while q < p {
        pred += x0[q] * b[q]
        q += 1usize
    }
    pred += c0ciy
    i = 0usize
    while i < m {
        var xb = 0.0f64
        q = 0usize
        while q < p {
            xb += cix[i * p + q] * b[q]
            q += 1usize
        }
        pred -= c0[i] * xb
        i += 1usize
    }
    var variance = v0 - c0cic
    if blup {
        let (d, e10) = mem.alloc[f64](a, p)
        if e10 != ok { ret e10 }
        q = 0usize
        while q < p {
            var s = 0.0f64
            i = 0usize
            while i < m {
                s += xd[i * p + q] * cic[i]
                i += 1usize
            }
            d[q] = x0[q] - s
            q += 1usize
        }
        var r = 0usize
        while r < p {
            var s = 0usize
            while s < p {
                variance += d[r] * ainv[r * p + s] * d[s]
                s += 1usize
            }
            r += 1usize
        }
    }
    out[0usize] = pred
    out[1usize] = variance
    q = 0usize
    while q < p {
        out[2usize + q] = b[q]
        q += 1usize
    }
    ret ok
}

// krige(): the prediction and variance at (px, py) from the n data with the neighbourhood nmax, maxdist, nmin. mode 0 universal (ordinary when the drift is one column), 1 simple
// with the coefficients beta. out: prediction, variance.
fn krige_point(a: *mem.Arena, xy: []const f64, z: []const f64, xd: []const f64, n: usize, p: usize, x0: []const f64, px: f64, py: f64, ms: []const f64, nst: usize, mode: usize, beta: []const f64, nmax: usize, maxdist: f64, nmin: usize, out: []f64) -> err {
    let (idx, e1) = mem.alloc[usize](a, n + 1usize)
    if e1 != ok { ret e1 }
    let (dd, e2) = mem.alloc[f64](a, n + 1usize)
    if e2 != ok { ret e2 }
    let cnt = select_nb(xy, n, px, py, nmax, maxdist, nmin, idx, dd)
    let (sxy, e3) = mem.alloc[f64](a, 2usize * cnt + 2usize)
    if e3 != ok { ret e3 }
    let (sz, e4) = mem.alloc[f64](a, cnt + 1usize)
    if e4 != ok { ret e4 }
    let (sx, e5) = mem.alloc[f64](a, cnt * p + 1usize)
    if e5 != ok { ret e5 }
    var i = 0usize
    while i < cnt {
        sxy[2usize * i] = xy[2usize * idx[i]]
        sxy[2usize * i + 1usize] = xy[2usize * idx[i] + 1usize]
        sz[i] = z[idx[i]]
        var q = 0usize
        while q < p {
            sx[i * p + q] = xd[idx[i] * p + q]
            q += 1usize
        }
        i += 1usize
    }
    let (o, e6) = mem.alloc[f64](a, 2usize + p)
    if e6 != ok { ret e6 }
    if gls_predict(a, sxy, sz, sx, cnt, p, x0, px, py, ms, nst, mode == 0usize, beta, o) != ok { ret e6 }
    out[0usize] = o[0usize]
    out[1usize] = o[1usize]
    ret ok
}

// krige.cv(): for each data point the prediction and variance from the data outside its fold. fold gives each point's fold (any integer values). out: pred then var, n each.
fn krige_cv(a: *mem.Arena, xy: []const f64, z: []const f64, xd: []const f64, n: usize, p: usize, fold: []const f64, ms: []const f64, nst: usize, mode: usize, beta: []const f64, nmax: usize, maxdist: f64, nmin: usize, out: []f64) -> err {
    let (txy, e1) = mem.alloc[f64](a, 2usize * n)
    if e1 != ok { ret e1 }
    let (tz, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret e2 }
    let (tx, e3) = mem.alloc[f64](a, n * p)
    if e3 != ok { ret e3 }
    let (o, e4) = mem.alloc[f64](a, 2usize)
    if e4 != ok { ret e4 }
    var i = 0usize
    while i < n {
        var cnt = 0usize
        var k = 0usize
        while k < n {
            if fold[k] != fold[i] {
                txy[2usize * cnt] = xy[2usize * k]
                txy[2usize * cnt + 1usize] = xy[2usize * k + 1usize]
                tz[cnt] = z[k]
                var q = 0usize
                while q < p {
                    tx[cnt * p + q] = xd[k * p + q]
                    q += 1usize
                }
                cnt += 1usize
            }
            k += 1usize
        }
        let mk = mem.mark(a)
        if krige_point(a, txy, tz, tx, cnt, p, xd[i * p..i * p + p], xy[2usize * i], xy[2usize * i + 1usize], ms, nst, mode, beta, nmax, maxdist, nmin, o) != ok { ret e4 }
        out[i] = o[0usize]
        out[n + i] = o[1usize]
        mem.reset(a, mk)
        i += 1usize
    }
    ret ok
}

// predict.gstat(nsim): sequential Gaussian simulation of the nnew locations nxy (drift rows nxd) given n data. known: the coefficients beta are given (simple kriging, no draw);
// otherwise each realisation draws its coefficients from N(beta_gls, Cov(beta_gls)) first. The path is R's sample() of the rows, then per location one normal per realisation.
// out holds the nsim realisations column by column, each in the order of the rows of nxy.
fn sgs_simulate(a: *mem.Arena, rng: *rr.Rng, xy: []const f64, z: []const f64, xd: []const f64, n: usize, p: usize, nxy: []const f64, nxd: []const f64, nnew: usize, ms: []const f64, nst: usize, nsim: usize, known: bool, beta0: []const f64, nmax: usize, maxdist: f64, nmin: usize, out: []f64) -> err {
    let (perm, pe) = rr.sample_int(a, rng, i64(nnew), i64(nnew), false)
    if pe != ok { ret pe }
    let (betas, e1) = mem.alloc[f64](a, nsim * p)
    if e1 != ok { ret e1 }
    var j = 0usize
    while j < nsim {
        var q = 0usize
        while q < p {
            betas[j * p + q] = 0.0f64
            if known { betas[j * p + q] = beta0[q] }
            q += 1usize
        }
        j += 1usize
    }
    if !known {
        let (o, e2) = mem.alloc[f64](a, 2usize + p)
        if e2 != ok { ret e2 }
        // the GLS estimate and its covariance on the true covariance
        let (c, e3) = mem.alloc[f64](a, n * n)
        if e3 != ok { ret e3 }
        var i = 0usize
        while i < n {
            var k = 0usize
            while k < n {
                c[i * n + k] = cov_lag(ms, nst, xy[2usize * i] - xy[2usize * k], xy[2usize * i + 1usize] - xy[2usize * k + 1usize], true)
                k += 1usize
            }
            i += 1usize
        }
        if !chol_lower(c, n) { ret e2 }
        let (cix, e4) = mem.alloc[f64](a, n * p)
        if e4 != ok { ret e4 }
        let (ciy, e5) = mem.alloc[f64](a, n)
        if e5 != ok { ret e5 }
        let (col, e6) = mem.alloc[f64](a, n)
        if e6 != ok { ret e6 }
        var q = 0usize
        while q < p {
            i = 0usize
            while i < n {
                col[i] = xd[i * p + q]
                i += 1usize
            }
            chol_apply(c, n, col)
            i = 0usize
            while i < n {
                cix[i * p + q] = col[i]
                i += 1usize
            }
            q += 1usize
        }
        i = 0usize
        while i < n {
            ciy[i] = z[i]
            i += 1usize
        }
        chol_apply(c, n, ciy)
        let (am, e7) = mem.alloc[f64](a, p * p)
        if e7 != ok { ret e7 }
        let (ainv, e8) = mem.alloc[f64](a, p * p)
        if e8 != ok { ret e8 }
        var r = 0usize
        while r < p {
            var s = 0usize
            while s < p {
                var t = 0.0f64
                i = 0usize
                while i < n {
                    t += xd[i * p + r] * cix[i * p + s]
                    i += 1usize
                }
                am[r * p + s] = t
                s += 1usize
            }
            r += 1usize
        }
        if ols.inverse(a, am, p, ainv) != ok { ret e2 }
        let (bh, e9) = mem.alloc[f64](a, p)
        if e9 != ok { ret e9 }
        r = 0usize
        while r < p {
            var t = 0.0f64
            var s = 0usize
            while s < p {
                var xty = 0.0f64
                i = 0usize
                while i < n {
                    xty += xd[i * p + s] * ciy[i]
                    i += 1usize
                }
                t += ainv[r * p + s] * xty
                s += 1usize
            }
            bh[r] = t
            r += 1usize
        }
        let (lf, e10) = mem.alloc[f64](a, p * p)
        if e10 != ok { ret e10 }
        i = 0usize
        while i < p * p {
            lf[i] = ainv[i]
            i += 1usize
        }
        if !chol_lower(lf, p) { ret e2 }
        let (zz, e11) = mem.alloc[f64](a, p)
        if e11 != ok { ret e11 }
        j = 0usize
        while j < nsim {
            q = 0usize
            while q < p {
                zz[q] = rr.norm(rng)
                q += 1usize
            }
            r = 0usize
            while r < p {
                var t = bh[r]
                var s = 0usize
                while s <= r {
                    t += lf[r * p + s] * zz[s]
                    s += 1usize
                }
                betas[j * p + r] = t
                r += 1usize
            }
            j += 1usize
        }
    }
    // the nodes: data first, simulated locations after
    let tot = n + nnew
    let (axy, e12) = mem.alloc[f64](a, 2usize * tot)
    if e12 != ok { ret e12 }
    let (ax, e13) = mem.alloc[f64](a, tot * p)
    if e13 != ok { ret e13 }
    let (az, e14) = mem.alloc[f64](a, nsim * tot)
    if e14 != ok { ret e14 }
    var i = 0usize
    while i < n {
        axy[2usize * i] = xy[2usize * i]
        axy[2usize * i + 1usize] = xy[2usize * i + 1usize]
        var q = 0usize
        while q < p {
            ax[i * p + q] = xd[i * p + q]
            q += 1usize
        }
        j = 0usize
        while j < nsim {
            az[j * tot + i] = z[i]
            j += 1usize
        }
        i += 1usize
    }
    let (idx, e15) = mem.alloc[usize](a, tot + 1usize)
    if e15 != ok { ret e15 }
    let (dd, e16) = mem.alloc[f64](a, tot + 1usize)
    if e16 != ok { ret e16 }
    let (sxy, e17) = mem.alloc[f64](a, 2usize * tot + 2usize)
    if e17 != ok { ret e17 }
    let (sz, e18) = mem.alloc[f64](a, tot + 1usize)
    if e18 != ok { ret e18 }
    let (sx, e19) = mem.alloc[f64](a, tot * p + 1usize)
    if e19 != ok { ret e19 }
    let (o2, e20) = mem.alloc[f64](a, 2usize + p)
    if e20 != ok { ret e20 }
    var t = 0usize
    while t < nnew {
        let row = usize(perm[t]) - 1usize
        let px = nxy[2usize * row]
        let py = nxy[2usize * row + 1usize]
        let cnt = select_nb(axy, n + t, px, py, nmax, maxdist, nmin, idx, dd)
        var s = 0usize
        while s < cnt {
            sxy[2usize * s] = axy[2usize * idx[s]]
            sxy[2usize * s + 1usize] = axy[2usize * idx[s] + 1usize]
            var q = 0usize
            while q < p {
                sx[s * p + q] = ax[idx[s] * p + q]
                q += 1usize
            }
            s += 1usize
        }
        j = 0usize
        while j < nsim {
            s = 0usize
            while s < cnt {
                sz[s] = az[j * tot + idx[s]]
                s += 1usize
            }
            let mk = mem.mark(a)
            if gls_predict(a, sxy, sz, sx, cnt, p, nxd[row * p..row * p + p], px, py, ms, nst, false, betas[j * p..j * p + p], o2) != ok { ret e20 }
            mem.reset(a, mk)
            var v = o2[0usize]
            if o2[1usize] >= 2.220446049250313e-15f64 { v = o2[0usize] + math.sqrt[f64](o2[1usize]) * rr.norm(rng) }
            if nsim > 1usize { v = f64(f32(v)) }
            az[j * tot + n + t] = v
            out[j * nnew + row] = v
            j += 1usize
        }
        axy[2usize * (n + t)] = px
        axy[2usize * (n + t) + 1usize] = py
        var q = 0usize
        while q < p {
            ax[(n + t) * p + q] = nxd[row * p + q]
            q += 1usize
        }
        t += 1usize
    }
    ret ok
}
