// R gstat fit.variogram: the Marquardt-style Gauss-Newton fit of a nested variogram model to a sample variogram (fit.c, lm.c), with the fit.method weights 1 (N_j),
// 2 (N_j / gamma(h_j)^2), 6 (none) and 7 (N_j / h_j^2), a step limited to 20 percent of the squared parameter norm (gstat's v_norm2 is the sum of squares) while ranges are fitted, convergence when the relative
// drop of the weighted error falls under 1e-5 (at most 200 iterations), the R-level refit that fixes negative partial sills at zero, the defaults for
// unset starting values (vgm_fill_na) and the grid search over kappa for the Matern models.
//
// A model is six numbers per structure as in e.algo.stat.gstatvgm. The result of a fit is the partial sills, the ranges, the weighted error and the singular flag.
//
// Not here: the cloud fit (every np 1; gstat reads an uninitialised index there), fit.method 3 to 5, REML and GLS fits, covariograms and cross variograms.

use e.algo.stat.gstatvgm as gv
use e.math
use e.mem

// the derivative of sill * unit semivariance with respect to the range at the transformed distance h (gstat's da_Semivariance: hand-written for most families,
// a central difference of 0.1 percent of the range for the others)
fn da_semivariance(t: usize, sill: f64, h: f64, r: f64, kappa: f64) -> f64 {
    let pi = gv.gpi()
    if t == 1usize || t == 19usize || t == 20usize { ret 0.0f64 }
    if t == 2usize {
        let hr = 0.0f64 - h / r
        ret sill * ((hr / r) * math.exp[f64](hr))
    }
    if t == 3usize {
        if h > r { ret 0.0f64 }
        let hr2 = h / (r * r)
        ret sill * (1.5f64 * hr2 * (0.0f64 - 1.0f64 + h * hr2))
    }
    if t == 4usize {
        let hr = h / r
        ret sill * (((0.0f64 - hr) / r) * math.exp[f64](0.0f64 - hr * hr))
    }
    if t == 9usize {
        if r == 0.0f64 { ret 0.0f64 }
        if h > r { ret 0.0f64 }
        ret sill * (0.0f64 - h / (r * r))
    }
    if t == 11usize {
        if h >= r { ret 0.0f64 }
        let hr2 = h / (r * r)
        ret sill * (hr2 * ((0.0f64 - 15.0f64 / 8.0f64) + hr2 * ((15.0f64 / 4.0f64) * h - (15.0f64 / 8.0f64) * h * h * hr2)))
    }
    if t == 12usize { ret sill * ((2.0f64 * pi * h / (r * r)) * math.sin[f64](2.0f64 * pi * h / r)) }
    if t == 13usize { ret sill * (math.cos[f64](pi * h / r) / r - math.sin[f64](pi * h / r) / pi * h) }
    if t == 14usize {
        let hr = h / r
        let hr2 = h / (r * r)
        ret sill * (hr2 * math.sin[f64](hr) + hr * hr2 * math.cos[f64](hr))
    }
    if t == 15usize { ret sill * (1.0f64 / r) }
    if t == 16usize { ret sill * (math.log[f64](h) * math.pow[f64](h, r)) }
    var range = r
    if range < 1.0e-20f64 { range = 1.0e-20f64 }
    let low = gv.unit_gamma(t, h, range * 1.001f64, kappa)
    let high = gv.unit_gamma(t, h, range * 0.999f64, kappa)
    ret sill * (low - high) / (2.0f64 * range * 0.001f64)
}

// the Cholesky solve of the p by p system m b = rhs (m symmetric, upper triangle used); false when a leading minor is not positive definite
fn chol_solve(m: []const f64, p: usize, rhs: []const f64, w: []f64, b: []f64) -> bool {
    var j = 0usize
    while j < p {
        var d = m[j * p + j]
        var k = 0usize
        while k < j {
            d -= w[k * p + j] * w[k * p + j]
            k += 1usize
        }
        if !(d > 0.0f64) { ret false }
        let dj = math.sqrt[f64](d)
        w[j * p + j] = dj
        var c = j + 1usize
        while c < p {
            var s = m[j * p + c]
            k = 0usize
            while k < j {
                s -= w[k * p + j] * w[k * p + c]
                k += 1usize
            }
            w[j * p + c] = s / dj
            c += 1usize
        }
        j += 1usize
    }
    var i = 0usize
    while i < p {
        var s = rhs[i]
        var k = 0usize
        while k < i {
            s -= w[k * p + i] * b[k]
            k += 1usize
        }
        b[i] = s / w[i * p + i]
        i += 1usize
    }
    i = p
    while i > 0usize {
        i -= 1usize
        var s = b[i]
        var k = i + 1usize
        while k < p {
            s -= w[i * p + k] * b[k]
            k += 1usize
        }
        b[i] = s / w[i * p + i]
    }
    ret true
}

// the weighted error of the model at the sample variogram, along the direction (0, 1) as gstat's fit does
fn fit_sserr(ms: []const f64, nst: usize, dist: []const f64, gam: []const f64, nev: usize, wt: []const f64, weighted: bool) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < nev {
        let dz = gam[i] - gv.model_gamma(ms, nst, 0.0f64, dist[i])
        if weighted { s += dz * dz * wt[i] }
        if !weighted { s += dz * dz }
        i += 1usize
    }
    ret s
}

// fits the model in place (ms: partial sill and range of each structure). method 1, 2, 6 or 7; fsill and frange flag which parameters move. out[0] the singular flag
// (1 when a step failed), out[1] the weighted error, out[2] the number of iterations.
fn fit_vgm(a: *mem.Arena, ms: []f64, nst: usize, np: []const f64, dist: []const f64, gam: []const f64, nev: usize, method: usize, fsill: []f64, frange: []f64, out: []f64) -> err {
    let (wt, e1) = mem.alloc[f64](a, nev)
    if e1 != ok { ret e1 }
    let (xm, e2) = mem.alloc[f64](a, nev * 2usize * nst)
    if e2 != ok { ret e2 }
    let (ye, e3) = mem.alloc[f64](a, nev)
    if e3 != ok { ret e3 }
    let (xtx, e4) = mem.alloc[f64](a, 4usize * nst * nst)
    if e4 != ok { ret e4 }
    let (xty, e5) = mem.alloc[f64](a, 2usize * nst)
    if e5 != ok { ret e5 }
    let (cw, e6) = mem.alloc[f64](a, 4usize * nst * nst)
    if e6 != ok { ret e6 }
    let (beta, e7) = mem.alloc[f64](a, 2usize * nst)
    if e7 != ok { ret e7 }
    let (start, e8) = mem.alloc[f64](a, 2usize * nst)
    if e8 != ok { ret e8 }
    let (pidx, e9) = mem.alloc[usize](a, 2usize * nst)
    if e9 != ok { ret e9 }
    out[0usize] = 0.0f64
    var k = 0usize
    while k < nst {
        if ms[6usize * k + 1usize] == 0.0f64 && fsill[k] != 0.0f64 { ms[6usize * k + 1usize] = 1.0f64 }
        k += 1usize
    }
    let weighted = method != 6usize
    var usew = false
    var sserr = 0.0f64
    var old = 1.7976931348623157e308f64
    var iter = 0usize
    var bounded = false
    var stop = false
    while !stop {
        // update_variogram: no range is fitted for a nugget, an intercept or a linear model with range 0
        k = 0usize
        while k < nst {
            let t = usize(ms[6usize * k])
            if t == 1usize || t == 20usize || (t == 9usize && ms[6usize * k + 2usize] == 0.0f64) { frange[k] = 0.0f64 }
            k += 1usize
        }
        // the Gauss-Newton step
        var nfit = 0usize
        var fit_ranges = false
        k = 0usize
        while k < nst {
            if fsill[k] != 0.0f64 {
                pidx[nfit] = k
                nfit += 1usize
            }
            if frange[k] != 0.0f64 {
                pidx[nfit] = k + nst
                nfit += 1usize
                fit_ranges = true
            }
            k += 1usize
        }
        var singular = false
        if nfit > 0usize {
            var q = 0usize
            while q < nfit {
                if pidx[q] < nst { start[q] = ms[6usize * pidx[q] + 1usize] }
                if pidx[q] >= nst { start[q] = ms[6usize * (pidx[q] - nst) + 2usize] }
                q += 1usize
            }
            var i = 0usize
            while i < nev {
                let h = dist[i]
                ye[i] = gam[i] - gv.model_gamma(ms, nst, 0.0f64, h)
                var j = 0usize
                while j < nfit {
                    var m = pidx[j]
                    var col = 0.0f64
                    if m < nst {
                        col = gv.unit_gamma(usize(ms[6usize * m]), gv.aniso_norm(ms[6usize * m + 4usize], ms[6usize * m + 5usize], 0.0f64, h), ms[6usize * m + 2usize], ms[6usize * m + 3usize])
                    }
                    if m >= nst {
                        m -= nst
                        col = da_semivariance(usize(ms[6usize * m]), ms[6usize * m + 1usize], gv.aniso_norm(ms[6usize * m + 4usize], ms[6usize * m + 5usize], 0.0f64, h), ms[6usize * m + 2usize], ms[6usize * m + 3usize])
                    }
                    xm[i * nfit + j] = col
                    j += 1usize
                }
                i += 1usize
            }
            if nev < nfit { singular = true }
            if iter == 0usize && weighted && !singular {
                usew = true
                i = 0usize
                while i < nev {
                    var s = dist[i]
                    if method != 7usize { s = gv.model_gamma(ms, nst, 0.0f64, dist[i]) }
                    wt[i] = np[i]
                    if method != 1usize {
                        if math.abs[f64](s) > 1.0e-30f64 { wt[i] = wt[i] / (s * s) }
                        if !(math.abs[f64](s) > 1.0e-30f64) { singular = true }
                    }
                    i += 1usize
                }
            }
            if !singular {
                // X'WX and X'Wy
                var r = 0usize
                while r < nfit {
                    var c = 0usize
                    while c < nfit {
                        var s = 0.0f64
                        var n = 0usize
                        while n < nev {
                            var w = 1.0f64
                            if weighted { w = wt[n] }
                            s += xm[n * nfit + r] * xm[n * nfit + c] * w
                            n += 1usize
                        }
                        xtx[r * nfit + c] = s
                        c += 1usize
                    }
                    var sy = 0.0f64
                    var n2 = 0usize
                    while n2 < nev {
                        var w2 = 1.0f64
                        if weighted { w2 = wt[n2] }
                        sy += xm[n2 * nfit + r] * ye[n2] * w2
                        n2 += 1usize
                    }
                    xty[r] = sy
                    r += 1usize
                }
                if !chol_solve(xtx, nfit, xty, cw, beta) { singular = true }
            }
            if !singular {
                if fit_ranges {
                    var nb = 0.0f64
                    var ns = 0.0f64
                    var q2 = 0usize
                    while q2 < nfit {
                        nb += beta[q2] * beta[q2]
                        ns += start[q2] * start[q2]
                        q2 += 1usize
                    }
                    let sc = nb / ns
                    if sc > 0.2f64 {
                        q2 = 0usize
                        while q2 < nfit {
                            beta[q2] = beta[q2] * (0.2f64 / sc)
                            q2 += 1usize
                        }
                        bounded = true
                    }
                    if !(sc > 0.2f64) { bounded = false }
                }
                if !fit_ranges { bounded = false }
                var q3 = 0usize
                while q3 < nfit {
                    if pidx[q3] < nst { ms[6usize * pidx[q3] + 1usize] = start[q3] + beta[q3] }
                    if pidx[q3] >= nst { ms[6usize * (pidx[q3] - nst) + 2usize] = start[q3] + beta[q3] }
                    q3 += 1usize
                }
            }
        }
        if singular {
            out[0usize] = 1.0f64
            out[1usize] = fit_sserr(ms, nst, dist, gam, nev, wt, usew)
            out[2usize] = f64(iter)
            ret ok
        }
        sserr = fit_sserr(ms, nst, dist, gam, nev, wt, usew)
        var step = old - sserr
        if sserr > 2.220446049250313e-15f64 { step = step / sserr }
        iter += 1usize
        old = sserr
        stop = (step < 1.0e-5f64 && step >= 0.0f64 && !bounded) || iter == 200usize
    }
    out[1usize] = sserr
    out[2usize] = f64(iter)
    ret ok
}

fn mean_range(v: []const f64, from: usize, to: usize) -> f64 {
    var s = 0.0f64
    var i = from
    while i < to {
        s += v[i]
        i += 1usize
    }
    ret s / f64(to - from)
}

// fit.variogram(): unset (negative) starting values are filled as vgm_fill_na does, the ranges of nuggets and measurement error are not fitted, and for a direct variogram
// any negative partial sill is fixed at zero and the fit repeated from the original ranges. out: nst partial sills, nst ranges, the weighted error, the singular flag.
fn fit_variogram(a: *mem.Arena, ms0: []const f64, nst: usize, np: []const f64, dist: []const f64, gam: []const f64, nev: usize, method: usize, fsill0: []const f64, frange0: []const f64, direct: bool, out: []f64) -> err {
    let (ms, e1) = mem.alloc[f64](a, 6usize * nst)
    if e1 != ok { ret e1 }
    let (fs, e2) = mem.alloc[f64](a, nst)
    if e2 != ok { ret e2 }
    let (fr, e3) = mem.alloc[f64](a, nst)
    if e3 != ok { ret e3 }
    let (init, e4) = mem.alloc[f64](a, nst)
    if e4 != ok { ret e4 }
    let (fo, e5) = mem.alloc[f64](a, 3usize)
    if e5 != ok { ret e5 }
    var k = 0usize
    while k < 6usize * nst {
        ms[k] = ms0[k]
        k += 1usize
    }
    // vgm_fill_na
    var any_na_range = false
    var any_na_sill = false
    k = 0usize
    while k < nst {
        if ms[6usize * k + 2usize] < 0.0f64 { any_na_range = true }
        if ms[6usize * k + 1usize] < 0.0f64 { any_na_sill = true }
        k += 1usize
    }
    if any_na_range {
        var dmax = dist[0usize]
        var i = 1usize
        while i < nev {
            if dist[i] > dmax { dmax = dist[i] }
            i += 1usize
        }
        k = 0usize
        while k < nst {
            let t = usize(ms[6usize * k])
            if t == 1usize || t == 19usize { ms[6usize * k + 2usize] = 0.0f64 }
            if !(t == 1usize || t == 19usize) { ms[6usize * k + 2usize] = dmax / 3.0f64 }
            k += 1usize
        }
    }
    if any_na_sill {
        var nonnug = 0usize
        k = 0usize
        while k < nst {
            if usize(ms[6usize * k]) != 1usize { nonnug += 1usize }
            k += 1usize
        }
        var h3 = 3usize
        if nev < 3usize { h3 = nev }
        var t5 = 0usize
        if nev > 5usize { t5 = nev - 5usize }
        k = 0usize
        while k < nst {
            if ms[6usize * k + 1usize] < 0.0f64 {
                if usize(ms[6usize * k]) == 1usize { ms[6usize * k + 1usize] = mean_range(gam, 0usize, h3) }
                if usize(ms[6usize * k]) != 1usize { ms[6usize * k + 1usize] = mean_range(gam, t5, nev) / f64(nonnug) }
            }
            k += 1usize
        }
    }
    k = 0usize
    while k < nst {
        init[k] = ms[6usize * k + 2usize]
        fs[k] = fsill0[k]
        fr[k] = frange0[k]
        let t = usize(ms[6usize * k])
        if t == 1usize || t == 19usize { fr[k] = 0.0f64 }
        k += 1usize
    }
    var again = true
    var rounds = 0usize
    while again && rounds < 50usize {
        again = false
        rounds += 1usize
        if fit_vgm(a, ms, nst, np, dist, gam, nev, method, fs, fr, fo) != ok { ret e1 }
        if direct {
            var neg = false
            k = 0usize
            while k < nst {
                if ms[6usize * k + 1usize] < 0.0f64 { neg = true }
                k += 1usize
            }
            if neg {
                k = 0usize
                while k < nst {
                    if ms[6usize * k + 1usize] < 0.0f64 { ms[6usize * k + 1usize] = 0.0f64 }
                    fs[k] = 0.0f64
                    if ms[6usize * k + 1usize] > 0.0f64 { fs[k] = 1.0f64 }
                    ms[6usize * k + 2usize] = init[k]
                    k += 1usize
                }
                again = true
            }
        }
    }
    k = 0usize
    while k < nst {
        out[k] = ms[6usize * k + 1usize]
        out[nst + k] = ms[6usize * k + 2usize]
        k += 1usize
    }
    out[2usize * nst] = fo[1usize]
    out[2usize * nst + 1usize] = fo[0usize]
    out[2usize * nst + 2usize] = fo[2usize]
    ret ok
}

// fit.variogram(fit.kappa = TRUE): the fit over kappa = 0.3, 0.4, ..., 5 for every Matern structure (types 6 and 7), the one with the least weighted error
fn fit_variogram_kappa(a: *mem.Arena, ms0: []const f64, nst: usize, np: []const f64, dist: []const f64, gam: []const f64, nev: usize, method: usize, fsill0: []const f64, frange0: []const f64, out: []f64) -> err {
    let (ms, e1) = mem.alloc[f64](a, 6usize * nst)
    if e1 != ok { ret e1 }
    let (o, e2) = mem.alloc[f64](a, 2usize * nst + 3usize)
    if e2 != ok { ret e2 }
    var best = 1.7976931348623157e308f64
    var i = 0usize
    while i <= 47usize {
        var k = 0usize
        while k < 6usize * nst {
            ms[k] = ms0[k]
            k += 1usize
        }
        k = 0usize
        while k < nst {
            let t = usize(ms[6usize * k])
            if t == 6usize || t == 7usize { ms[6usize * k + 3usize] = 0.3f64 + f64(i) * 0.1f64 }
            k += 1usize
        }
        if fit_variogram(a, ms, nst, np, dist, gam, nev, method, fsill0, frange0, true, o) != ok { ret e1 }
        if o[2usize * nst] < best {
            best = o[2usize * nst]
            k = 0usize
            while k < 2usize * nst + 3usize {
                out[k] = o[k]
                k += 1usize
            }
        }
        i += 1usize
    }
    ret ok
}
