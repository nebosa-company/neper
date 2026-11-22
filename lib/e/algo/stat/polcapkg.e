// R poLCA 1.6.0.2: latent class analysis and latent class regression of polytomous manifest variables, ported from the package's R driver and C kernels (ylik, postclass, probhat, d2lldbeta2) in their
// order of operations: random restarts from runif under set.seed, the error trap that redraws the start, missing responses (na.rm = FALSE), standard errors (poLCA.se with MASS ginv), the fit statistics,
// the predicted cells and poLCA.entropy.
//
// Not here: nclass = 1, dropping a manifest variable with one observed category, the probs.start format check, graphs and printing.
// R's sum, rowSums and colMeans add in long double; here a compensated sum stands in, so a total can differ from R's in its last bit.

use e.math
use e.mem
use e.algo.rand.r as rg
use e.algo.linalg.lapack_gesdd as gesdd
use e.algo.sort

type Fit = struct {
    n: usize, nj: usize, nr: usize, ns: usize, ncat: []usize, tc: usize,
    llik: f64, numiter: usize, eflag: bool,
    probs: []f64, probs_start: []f64, prior_p: []f64, posterior: []f64, predclass: []usize, attempts: []f64, nattempt: usize,
    coeff: []f64, coeff_se: []f64, coeff_v: []f64, probs_se: []f64, p_se: []f64,
    npar: f64, aic: f64, bic: f64, nobs: usize, chisq: f64, gsq: f64, resid_df: f64,
    ncell: usize, cells: []f64, observed: []f64, expected: []f64
}

type Acc = struct { s: f64, c: f64 }

fn acc_add(t: *Acc, x: f64) {
    let s = t.s + x
    if math.abs[f64](t.s) >= math.abs[f64](x) {
        t.c = t.c + ((t.s - s) + x)
    } else {
        t.c = t.c + ((x - s) + t.s)
    }
    t.s = s
}

fn acc_val(t: *const Acc) -> f64 { ret t.s + t.c }

fn xmax() -> f64 { ret 1.7976931348623157e308f64 }

// poLCA.ylik for one row y (1-based, 0 missing) and class r over the vectorized probabilities (variable blocks of R rows of K_j)
fn ylik1(vp: []const f64, y: []const f64, nj: usize, ncat: []const usize, nr: usize, r: usize) -> f64 {
    var lik = xmax()
    var off = 0usize
    var k = 0usize
    while k < nj {
        if y[k] > 0.5f64 { lik *= vp[off + r * ncat[k] + usize(y[k]) - 1usize] }
        off += nr * ncat[k]
        k += 1usize
    }
    ret lik
}

// poLCA.updatePrior(b, x, R): x n by s row-major (intercept first), b s by (R - 1) column-major
fn update_prior(b: []const f64, x: []const f64, n: usize, ns: usize, nr: usize, prior: []f64) {
    var i = 0usize
    while i < n {
        var rs: Acc = zero
        var r = 1usize
        while r < nr {
            var eta = 0.0f64
            var l = 0usize
            while l < ns {
                eta += b[(r - 1usize) * ns + l] * x[i * ns + l]
                l += 1usize
            }
            prior[i * nr + r] = math.exp[f64](eta)
            acc_add(&rs, prior[i * nr + r])
            r += 1usize
        }
        let den = acc_val(&rs) + 1.0f64
        prior[i * nr] = 1.0f64 / den
        r = 1usize
        while r < nr {
            prior[i * nr + r] = prior[i * nr + r] / den
            r += 1usize
        }
        i += 1usize
    }
}

// MASS ginv of an m by m column-major matrix through LAPACK dgesdd, singular values not above sqrt(eps) times the largest dropped; g receives m by m column-major
fn ginv_sq(a: *mem.Arena, h: []const f64, m: usize, g: []f64) -> err {
    let (s, e1) = mem.alloc[f64](a, m)
    let (u, e2) = mem.alloc[f64](a, m * m)
    let (vt, e3) = mem.alloc[f64](a, m * m)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    let e4 = gesdd.svd_all(a, h, m, m, s, u, vt)
    if e4 != ok { ret e4 }
    var tol = 1.4901161193847656e-8f64 * s[0usize]
    if tol < 0.0f64 { tol = 0.0f64 }
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < m {
            var t = 0.0f64
            var l = 0usize
            while l < m {
                if s[l] > tol { t += vt[i * m + l] * ((1.0f64 / s[l]) * u[l * m + j]) }
                l += 1usize
            }
            g[j * m + i] = t
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// poLCA(cbind(y_1 .. y_J) ~ x_1 + .. + x_q, nclass = nr, maxiter, tol, na.rm, probs.start, nrep) with calc.se = TRUE. y n by nj row-major, categories 1-based, 0 for a missing response; x n by q row-major
// covariates without the intercept (q = 0 for none). start: the vectorized probs.start (per variable, the R by K_j matrix by rows), empty for NULL. The RNG is R's after set.seed.
fn lca_fit(a: *mem.Arena, y_in: []const f64, n_in: usize, nj: usize, x_in: []const f64, q: usize, nr: usize, start: []const f64, nrep: usize, rng: *rg.Rng, tol: f64, maxiter: usize, na_rm: bool) -> (Fit, err) {
    var f: Fit = zero
    let ns = q + 1usize
    var n = 0usize
    var i = 0usize
    while i < n_in {
        var keep = true
        if na_rm {
            var j0 = 0usize
            while j0 < nj {
                if y_in[i * nj + j0] < 0.5f64 { keep = false }
                j0 += 1usize
            }
        }
        if keep { n += 1usize }
        i += 1usize
    }
    let (y, e1) = mem.alloc[f64](a, n * nj)
    let (x, e2) = mem.alloc[f64](a, n * ns)
    let (ncat, e3) = mem.alloc[usize](a, nj)
    if e1 != ok || e2 != ok || e3 != ok { ret (f, mem.Full) }
    var w = 0usize
    i = 0usize
    while i < n_in {
        var keep = true
        if na_rm {
            var j1 = 0usize
            while j1 < nj {
                if y_in[i * nj + j1] < 0.5f64 { keep = false }
                j1 += 1usize
            }
        }
        if keep {
            var j2 = 0usize
            while j2 < nj {
                y[w * nj + j2] = y_in[i * nj + j2]
                j2 += 1usize
            }
            x[w * ns] = 1.0f64
            var l0 = 0usize
            while l0 < q {
                x[w * ns + 1usize + l0] = x_in[i * q + l0]
                l0 += 1usize
            }
            w += 1usize
        }
        i += 1usize
    }
    var tc = 0usize
    var j = 0usize
    while j < nj {
        var mx = 0usize
        i = 0usize
        while i < n {
            if usize(y[i * nj + j]) > mx { mx = usize(y[i * nj + j]) }
            i += 1usize
        }
        ncat[j] = mx
        tc += mx
        j += 1usize
    }
    let nv = nr * tc
    let nb = ns * (nr - 1usize)
    f.n = n
    f.nj = nj
    f.nr = nr
    f.ns = ns
    f.ncat = ncat
    f.tc = tc
    let (vp, e4) = mem.alloc[f64](a, nv)
    let (vinit, e5) = mem.alloc[f64](a, nv)
    let (prior, e6) = mem.alloc[f64](a, n * nr)
    let (rgivy, e7) = mem.alloc[f64](a, n * nr)
    let (b, e8) = mem.alloc[f64](a, nb)
    let (grad, e9) = mem.alloc[f64](a, nb)
    let (hess, e10) = mem.alloc[f64](a, nb * nb)
    let (gi, e11) = mem.alloc[f64](a, nb * nb)
    let (den, e12) = mem.alloc[f64](a, nr * nj)
    let (lk, e13) = mem.alloc[f64](a, nr)
    if e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok { ret (f, mem.Full) }
    let (bp, e14) = mem.alloc[f64](a, nv)
    let (bst, e15) = mem.alloc[f64](a, nv)
    let (bprior, e16) = mem.alloc[f64](a, n * nr)
    let (bpost, e17) = mem.alloc[f64](a, n * nr)
    let (bb, e18) = mem.alloc[f64](a, nb)
    let (att, e19) = mem.alloc[f64](a, nrep)
    if e14 != ok || e15 != ok || e16 != ok || e17 != ok || e18 != ok || e19 != ok { ret (f, mem.Full) }
    let lxm = math.log[f64](xmax())
    var best = 0.0f64 - math.inf64()
    var best_iter = 0usize
    var best_eflag = false
    var eflag = false
    var repl = 0usize
    while repl < nrep {
        var failed = true
        var firstrun = true
        var llast = 0.0f64
        var iter = 1usize
        while failed {
            failed = false
            i = 0usize
            while i < nb {
                b[i] = 0.0f64
                i += 1usize
            }
            update_prior(b, x, n, ns, nr, prior)
            if start.len == 0usize || !firstrun || repl > 0usize {
                var off = 0usize
                j = 0usize
                while j < nj {
                    let k = ncat[j]
                    let (u, e20) = mem.alloc[f64](a, nr * k)
                    if e20 != ok { ret (f, mem.Full) }
                    var t = 0usize
                    while t < nr * k {
                        u[t] = rg.unif(rng)
                        t += 1usize
                    }
                    var r = 0usize
                    while r < nr {
                        var rs: Acc = zero
                        var c = 0usize
                        while c < k {
                            acc_add(&rs, u[r + c * nr])
                            c += 1usize
                        }
                        let sm = acc_val(&rs)
                        c = 0usize
                        while c < k {
                            vp[off + r * k + c] = u[r + c * nr] / sm
                            c += 1usize
                        }
                        r += 1usize
                    }
                    off += nr * k
                    j += 1usize
                }
            } else {
                i = 0usize
                while i < nv {
                    vp[i] = start[i]
                    i += 1usize
                }
            }
            i = 0usize
            while i < nv {
                vinit[i] = vp[i]
                i += 1usize
            }
            iter = 1usize
            var lprev = 0.0f64 - math.inf64()
            var dll = math.inf64()
            while iter <= maxiter && dll > tol && !failed {
                iter += 1usize
                // postclass
                i = 0usize
                while i < n {
                    var dn = 0.0f64
                    var r = 0usize
                    while r < nr {
                        lk[r] = ylik1(vp, y[i * nj..(i + 1usize) * nj], nj, ncat, nr, r)
                        dn += prior[i * nr + r] * lk[r]
                        r += 1usize
                    }
                    r = 0usize
                    while r < nr {
                        rgivy[i * nr + r] = prior[i * nr + r] * lk[r] / dn
                        r += 1usize
                    }
                    i += 1usize
                }
                // probhat
                i = 0usize
                while i < nv {
                    vp[i] = 0.0f64
                    i += 1usize
                }
                i = 0usize
                while i < nr * nj {
                    den[i] = 0.0f64
                    i += 1usize
                }
                i = 0usize
                while i < n {
                    var r = 0usize
                    while r < nr {
                        var cum = 0usize
                        var k = 0usize
                        while k < nj {
                            if y[i * nj + k] > 0.5f64 {
                                vp[r * ncat[k] + nr * cum + usize(y[i * nj + k]) - 1usize] += rgivy[i * nr + r]
                                den[r * nj + k] += rgivy[i * nr + r]
                            }
                            cum += ncat[k]
                            k += 1usize
                        }
                        r += 1usize
                    }
                    i += 1usize
                }
                var r = 0usize
                while r < nr {
                    var cum = 0usize
                    var k = 0usize
                    while k < nj {
                        var c = 0usize
                        while c < ncat[k] {
                            vp[r * ncat[k] + nr * cum + c] = vp[r * ncat[k] + nr * cum + c] / den[r * nj + k]
                            c += 1usize
                        }
                        cum += ncat[k]
                        k += 1usize
                    }
                    r += 1usize
                }
                if ns > 1usize {
                    let ge = beta_step(a, rgivy, prior, x, n, nr, ns, grad, hess, gi, b)
                    if ge != ok { ret (f, ge) }
                    update_prior(b, x, n, ns, nr, prior)
                } else {
                    r = 0usize
                    while r < nr {
                        var cs: Acc = zero
                        i = 0usize
                        while i < n {
                            acc_add(&cs, rgivy[i * nr + r])
                            i += 1usize
                        }
                        let cm = acc_val(&cs) / f64(n)
                        i = 0usize
                        while i < n {
                            prior[i * nr + r] = cm
                            i += 1usize
                        }
                        r += 1usize
                    }
                }
                var tl: Acc = zero
                i = 0usize
                while i < n {
                    var rs: Acc = zero
                    r = 0usize
                    while r < nr {
                        acc_add(&rs, prior[i * nr + r] * ylik1(vp, y[i * nj..(i + 1usize) * nj], nj, ncat, nr, r))
                        r += 1usize
                    }
                    acc_add(&tl, math.log[f64](acc_val(&rs)) - lxm)
                    i += 1usize
                }
                llast = acc_val(&tl)
                dll = llast - lprev
                lprev = llast
                if dll != dll {
                    failed = true
                } else if ns > 1usize && dll < 0.0f64 - 1.0e-7f64 {
                    failed = true
                }
            }
            if failed { eflag = true }
            firstrun = false
        }
        att[repl] = llast
        if llast > best {
            best = llast
            best_iter = iter - 1usize
            best_eflag = eflag
            i = 0usize
            while i < nv {
                bp[i] = vp[i]
                bst[i] = vinit[i]
                i += 1usize
            }
            i = 0usize
            while i < n * nr {
                bprior[i] = prior[i]
                bpost[i] = rgivy[i]
                i += 1usize
            }
            i = 0usize
            while i < nb {
                bb[i] = b[i]
                i += 1usize
            }
        }
        repl += 1usize
    }
    f.llik = best
    f.numiter = best_iter
    f.eflag = best_eflag
    f.probs = bp
    f.probs_start = bst
    f.posterior = bpost
    f.attempts = att
    f.nattempt = nrep
    f.coeff = bb
    let (pp, e21) = mem.alloc[f64](a, nr)
    let (pc, e22) = mem.alloc[usize](a, n)
    if e21 != ok || e22 != ok { ret (f, mem.Full) }
    var r0 = 0usize
    while r0 < nr {
        var cs: Acc = zero
        i = 0usize
        while i < n {
            acc_add(&cs, bpost[i * nr + r0])
            i += 1usize
        }
        pp[r0] = acc_val(&cs) / f64(n)
        r0 += 1usize
    }
    i = 0usize
    while i < n {
        var bi = 0usize
        var r1 = 1usize
        while r1 < nr {
            if bpost[i * nr + r1] > bpost[i * nr + bi] { bi = r1 }
            r1 += 1usize
        }
        pc[i] = bi + 1usize
        i += 1usize
    }
    f.prior_p = pp
    f.predclass = pc
    let se_e = lca_se(a, &f, y, x, bprior)
    if se_e != ok { ret (f, se_e) }
    let st_e = lca_stats(a, &f, y, na_rm)
    ret (f, st_e)
}

// poLCA.dLL2dBeta.C then b <- b + ginv(-hess) %*% grad
fn beta_step(a: *mem.Arena, rgivy: []const f64, prior: []const f64, x: []const f64, n: usize, nr: usize, ns: usize, grad: []f64, hess: []f64, g: []f64, b: []f64) -> err {
    let cr = ns * (nr - 1usize)
    var i = 0usize
    while i < cr {
        grad[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < cr * cr {
        hess[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        let ro = i * nr
        let xo = i * ns
        var k = 0usize
        while k < ns {
            var j = 1usize
            while j < nr {
                grad[(j - 1usize) * ns + k] += x[xo + k] * (rgivy[ro + j] - prior[ro + j])
                j += 1usize
            }
            var m = 0usize
            while m <= k {
                j = 1usize
                while j < nr {
                    var col = (j - 1usize) * ns + m
                    let row = (j - 1usize) * ns + k
                    let rj = rgivy[ro + j]
                    let pj = prior[ro + j]
                    hess[row * cr + col] += x[xo + m] * x[xo + k] * ((0.0f64 - rj) * (1.0f64 - rj) + pj * (1.0f64 - pj))
                    var nn = 1usize
                    while nn < j {
                        col = (nn - 1usize) * ns + m
                        hess[row * cr + col] += x[xo + m] * x[xo + k] * (rj * rgivy[ro + nn] - pj * prior[ro + nn])
                        nn += 1usize
                    }
                    j += 1usize
                }
                m += 1usize
            }
            k += 1usize
        }
        i += 1usize
    }
    var c1 = 1usize
    while c1 < nr {
        var c2 = c1 + 1usize
        while c2 < nr {
            var k = 0usize
            while k < ns {
                var nn = k + 1usize
                while nn < ns {
                    let row = (c2 - 1usize) * ns + nn
                    let col = (c1 - 1usize) * ns + k
                    let nrow = (c2 - 1usize) * ns + k
                    let ncol = (c1 - 1usize) * ns + nn
                    hess[nrow * cr + ncol] = hess[row * cr + col]
                    nn += 1usize
                }
                k += 1usize
            }
            c2 += 1usize
        }
        c1 += 1usize
    }
    var col = 0usize
    while col < cr {
        var row = 0usize
        while row < col {
            hess[row * cr + col] = hess[col * cr + row]
            row += 1usize
        }
        col += 1usize
    }
    // hess is symmetric, so its row-major layout is also the column-major matrix
    let ge = ginv_sq(a, hess, cr, g)
    if ge != ok { ret ge }
    i = 0usize
    while i < cr {
        var t = 0.0f64
        var j = 0usize
        while j < cr {
            t += g[j * cr + i] * grad[j]
            j += 1usize
        }
        b[i] = b[i] + t
        i += 1usize
    }
    ret ok
}

// poLCA.se(y, x, probs, prior, rgivy) at the best fit: probs.se (vectorized layout), P.se, coeff.se and coeff.V
fn lca_se(a: *mem.Arena, f: *Fit, y: []const f64, x: []const f64, prior: []const f64) -> err {
    let n = f.n
    let nj = f.nj
    let nr = f.nr
    let ns = f.ns
    let ncat = f.ncat
    let probs = f.probs
    let post = f.posterior
    var m = 0usize
    var j = 0usize
    while j < nj {
        m += nr * (ncat[j] - 1usize)
        j += 1usize
    }
    let nb = ns * (nr - 1usize)
    let q = m + nb
    let (sc, e1) = mem.alloc[f64](a, n * q)
    let (info, e2) = mem.alloc[f64](a, q * q)
    let (vce, e3) = mem.alloc[f64](a, q * q)
    let (voff, e4) = mem.alloc[usize](a, nj)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    var o = 0usize
    j = 0usize
    while j < nj {
        voff[j] = o
        o += nr * ncat[j]
        j += 1usize
    }
    var i = 0usize
    while i < n {
        var c = 0usize
        var r = 0usize
        while r < nr {
            j = 0usize
            while j < nj {
                let yv = y[i * nj + j]
                var k = 1usize
                while k < ncat[j] {
                    var v = 0.0f64
                    if yv > 0.5f64 {
                        var ind = 0.0f64
                        if usize(yv) == k + 1usize { ind = 1.0f64 }
                        v = post[i * nr + r] * (ind - probs[voff[j] + r * ncat[j] + k])
                    }
                    sc[i * q + c] = v
                    c += 1usize
                    k += 1usize
                }
                j += 1usize
            }
            r += 1usize
        }
        r = 1usize
        while r < nr {
            let pd = post[i * nr + r] - prior[i * nr + r]
            var l = 0usize
            while l < ns {
                sc[i * q + c] = x[i * ns + l] * pd
                c += 1usize
                l += 1usize
            }
            r += 1usize
        }
        i += 1usize
    }
    var p1 = 0usize
    while p1 < q {
        var p2 = 0usize
        while p2 < q {
            var t = 0.0f64
            i = 0usize
            while i < n {
                t += sc[i * q + p2] * sc[i * q + p1]
                i += 1usize
            }
            info[p2 * q + p1] = t
            p2 += 1usize
        }
        p1 += 1usize
    }
    let ge = ginv_sq(a, info, q, vce)
    if ge != ok { ret ge }
    // response probabilities by the delta method, block (class r, variable j) of K_j rows on K_j - 1 columns
    let (pse, e5) = mem.alloc[f64](a, f.tc * nr)
    let (tmp, e6) = mem.alloc[f64](a, 64usize)
    if e5 != ok || e6 != ok { ret mem.Full }
    var cpos = 0usize
    var r2 = 0usize
    while r2 < nr {
        j = 0usize
        while j < nj {
            let k = ncat[j]
            let po = voff[j] + r2 * k
            var a1 = 0usize
            while a1 < k {
                var c2 = 1usize
                while c2 < k {
                    var t = 0.0f64
                    var l = 1usize
                    while l < k {
                        var jl = 0.0f64 - probs[po + a1] * probs[po + l]
                        if a1 == l { jl = probs[po + a1] * (1.0f64 - probs[po + a1]) }
                        t += jl * vce[(cpos + c2 - 1usize) * q + cpos + l - 1usize]
                        l += 1usize
                    }
                    tmp[c2] = t
                    c2 += 1usize
                }
                var dg = 0.0f64
                c2 = 1usize
                while c2 < k {
                    var jc = 0.0f64 - probs[po + a1] * probs[po + c2]
                    if a1 == c2 { jc = probs[po + a1] * (1.0f64 - probs[po + a1]) }
                    dg += tmp[c2] * jc
                    c2 += 1usize
                }
                if dg < 0.0f64 { dg = 0.0f64 }
                pse[po + a1] = math.sqrt[f64](dg)
                a1 += 1usize
            }
            cpos += k - 1usize
            j += 1usize
        }
        r2 += 1usize
    }
    f.probs_se = pse
    // coefficients and class shares
    let (vb, e7) = mem.alloc[f64](a, nb * nb)
    let (bse, e8) = mem.alloc[f64](a, nb)
    let (jm, e9) = mem.alloc[f64](a, nr * nb)
    let (mse, e10) = mem.alloc[f64](a, nr)
    let (tm, e11) = mem.alloc[f64](a, nb)
    if e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret mem.Full }
    var c3 = 0usize
    while c3 < nb {
        var r3 = 0usize
        while r3 < nb {
            vb[c3 * nb + r3] = vce[(m + c3) * q + m + r3]
            r3 += 1usize
        }
        bse[c3] = math.sqrt[f64](vb[c3 * nb + c3])
        c3 += 1usize
    }
    var rr = 1usize
    while rr < nr {
        var l = 0usize
        while l < ns {
            var s = 0usize
            while s < nr {
                var cs: Acc = zero
                i = 0usize
                while i < n {
                    var pt = 0.0f64 - prior[i * nr + s] * prior[i * nr + rr]
                    if s == rr { pt = prior[i * nr + s] * (1.0f64 - prior[i * nr + s]) }
                    acc_add(&cs, pt * x[i * ns + l])
                    i += 1usize
                }
                jm[((rr - 1usize) * ns + l) * nr + s] = acc_val(&cs) / f64(n)
                s += 1usize
            }
            l += 1usize
        }
        rr += 1usize
    }
    var s1 = 0usize
    while s1 < nr {
        var c4 = 0usize
        while c4 < nb {
            var t = 0.0f64
            var l2 = 0usize
            while l2 < nb {
                t += jm[l2 * nr + s1] * vb[c4 * nb + l2]
                l2 += 1usize
            }
            tm[c4] = t
            c4 += 1usize
        }
        var dg = 0.0f64
        c4 = 0usize
        while c4 < nb {
            dg += tm[c4] * jm[c4 * nr + s1]
            c4 += 1usize
        }
        mse[s1] = math.sqrt[f64](dg)
        s1 += 1usize
    }
    f.coeff_se = bse
    f.coeff_v = vb
    f.p_se = mse
    ret ok
}

// npar, AIC, BIC, Nobs, resid.df and, over the fully observed rows compressed to their sorted distinct patterns (poLCA.compress), the expected cell counts, Pearson Chisq and Gsq
fn lca_stats(a: *mem.Arena, f: *Fit, y: []const f64, na_rm: bool) -> err {
    let n = f.n
    let nj = f.nj
    let nr = f.nr
    let ncat = f.ncat
    var np = 0usize
    var cells = 1.0f64
    var j = 0usize
    while j < nj {
        np += ncat[j] - 1usize
        cells = cells * f64(ncat[j])
        j += 1usize
    }
    var npar = f64(nr * np + (nr - 1usize))
    if f.ns > 1usize { npar = npar + f64(f.ns * (nr - 1usize)) - f64(nr - 1usize) }
    f.npar = npar
    f.aic = (0.0f64 - 2.0f64 * f.llik) + 2.0f64 * npar
    f.bic = (0.0f64 - 2.0f64 * f.llik) + math.log[f64](f64(n)) * npar
    var cap = cells - 1.0f64
    if f64(n) < cap { cap = f64(n) }
    f.resid_df = cap - npar
    let (codes, e1) = mem.alloc[u64](a, n)
    if e1 != ok { ret mem.Full }
    var no = 0usize
    var i = 0usize
    while i < n {
        var full = true
        var code = 0u64
        j = 0usize
        while j < nj {
            if y[i * nj + j] < 0.5f64 { full = false }
            code = code * u64(ncat[j] + 1usize) + u64(y[i * nj + j])
            j += 1usize
        }
        if full {
            codes[no] = code
            no += 1usize
        }
        i += 1usize
    }
    f.nobs = no
    f.chisq = 0.0f64 / 0.0f64
    f.gsq = 0.0f64 / 0.0f64
    if no == 0usize { ret ok }
    let sl = codes[0usize..no]
    let se = sort.radix_u64_in_place(a, sl)
    if se != ok { ret se }
    var nc = 1usize
    i = 1usize
    while i < no {
        if sl[i] != sl[i - 1usize] { nc += 1usize }
        i += 1usize
    }
    let (cl, e2) = mem.alloc[f64](a, nc * nj)
    let (ob, e3) = mem.alloc[f64](a, nc)
    let (ex, e4) = mem.alloc[f64](a, nc)
    if e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    var c = 0usize
    i = 0usize
    while i < no {
        if i > 0usize && sl[i] != sl[i - 1usize] { c += 1usize }
        if i == 0usize || sl[i] != sl[i - 1usize] {
            ob[c] = 0.0f64
            var cd = sl[i]
            var jj = nj
            while jj > 0usize {
                jj -= 1usize
                cl[c * nj + jj] = f64(cd % u64(ncat[jj] + 1usize))
                cd = cd / u64(ncat[jj] + 1usize)
            }
        }
        ob[c] = ob[c] + 1.0f64
        i += 1usize
    }
    var tot = f64(n)
    if !na_rm { tot = f64(no) }
    let sc = tot / xmax()
    var xs: Acc = zero
    var fs: Acc = zero
    var gs: Acc = zero
    c = 0usize
    while c < nc {
        var t = 0.0f64
        var r = 0usize
        while r < nr {
            t += f.prior_p[r] * ylik1(f.probs, cl[c * nj..(c + 1usize) * nj], nj, ncat, nr, r)
            r += 1usize
        }
        ex[c] = sc * t
        let d = ob[c] - ex[c]
        acc_add(&xs, d * d / ex[c])
        acc_add(&fs, ex[c])
        acc_add(&gs, ob[c] * math.log[f64](ob[c] / ex[c]))
        c += 1usize
    }
    f.chisq = acc_val(&xs) + (tot - acc_val(&fs))
    f.gsq = 2.0f64 * acc_val(&gs)
    f.ncell = nc
    f.cells = cl
    f.observed = ob
    f.expected = ex
    ret ok
}

// poLCA.entropy(lc): over the full cross-classification (first variable fastest), P = (ylik / xmax) %*% P, and -sum(P log P) without the empty cells
fn lca_entropy(a: *mem.Arena, f: *const Fit) -> f64 {
    let nj = f.nj
    let (row, e1) = mem.alloc[f64](a, nj)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    var cells = 1usize
    var j = 0usize
    while j < nj {
        cells *= f.ncat[j]
        j += 1usize
    }
    var h: Acc = zero
    var cell = 0usize
    while cell < cells {
        var rem = cell
        j = 0usize
        while j < nj {
            row[j] = f64(rem % f.ncat[j] + 1usize)
            rem = rem / f.ncat[j]
            j += 1usize
        }
        var pc = 0.0f64
        var r = 0usize
        while r < f.nr {
            pc += f.prior_p[r] * (ylik1(f.probs, row, nj, f.ncat, f.nr, r) / xmax())
            r += 1usize
        }
        if pc > 0.0f64 { acc_add(&h, pc * math.log[f64](pc)) }
        cell += 1usize
    }
    ret 0.0f64 - acc_val(&h)
}
