// R bayesm: the Gibbs samplers built on the helpers in bayesmpkg, equal to the package under set.seed (keep = 1).
//
// rnmixGibbs, rivGibbs. Matrices are column-major as R passes them.

use e.algo.rand.r as rng
use e.algo.rand.rdist as rd
use e.algo.stat.bayesmpkg as bz
use e.math
use e.math.dist as mdist
use e.mem

// zeroed allocation (mem.alloc leaves garbage)
fn zal(a: *mem.Arena, n: usize) -> ([]f64, err) {
    let (p, e) = mem.alloc[f64](a, n)
    if e != ok { ret (p, e) }
    var i = 0usize
    while i < n {
        p[i] = 0.0f64
        i += 1usize
    }
    ret (p, ok)
}

// out (m by n) = op(A) op(B) with op(A) m by kk and op(B) kk by n; ta / tb say the stored matrix is the transpose; ar and br are the stored row counts; all column-major
fn gemm(ta: bool, tb: bool, am: []const f64, ar: usize, bm: []const f64, br: usize, m: usize, n: usize, kk: usize, out: []f64) {
    var j = 0usize
    while j < n {
        var i = 0usize
        while i < m {
            var s = 0.0f64
            var p = 0usize
            while p < kk {
                var x = 0.0f64
                if ta { x = am[i * ar + p] } else { x = am[p * ar + i] }
                var y = 0.0f64
                if tb { y = bm[p * br + j] } else { y = bm[j * br + p] }
                s += x * y
                p += 1usize
            }
            out[j * m + i] = s
            i += 1usize
        }
        j += 1usize
    }
}

// the inverse of the upper Cholesky factor of the symmetric positive definite s (k by k) into rooti
fn rooti_of(a: *mem.Arena, s: []const f64, k: usize, rooti: []f64) -> err {
    let (u, e) = zal(a, k * k)
    if e != ok { ret e }
    if !bz.chol_upper(s, k, u) { ret mem.Full }
    bz.inv_upper(u, k, rooti)
    ret ok
}

// drawCompsFromLabels: per component mu (d) then rooti (d d) into out
fn mix_comps(a: *mem.Arena, r: *rng.Rng, y: []const f64, n: usize, d: usize, bbar: []const f64, a00: f64, nu: f64, v: []const f64, nc: usize, z: []const f64, out: []f64) -> err {
    var k = 0usize
    while k < nc {
        let start = mem.mark(a)
        var nk = 0usize
        var i = 0usize
        while i < n {
            if usize(z[i]) == k + 1usize { nk += 1usize }
            i += 1usize
        }
        let base = k * (d + d * d)
        let (ri, e0) = zal(a, d * d)
        if e0 != ok { ret mem.Full }
        if nk > 0usize {
            let (yk, e1) = zal(a, nk * d)
            let (xk, e2) = zal(a, nk)
            let (ob, e3) = zal(a, d)
            let (os2, e4) = zal(a, d * d)
            let (am1, e5) = zal(a, 1usize)
            if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
            am1[0usize] = a00
            var q = 0usize
            i = 0usize
            while i < n {
                if usize(z[i]) == k + 1usize {
                    var c = 0usize
                    while c < d {
                        yk[c * nk + q] = y[c * n + i]
                        c += 1usize
                    }
                    xk[q] = 1.0f64
                    q += 1usize
                }
                i += 1usize
            }
            if bz.rmultireg(a, r, yk, xk, bbar, am1, nu, v, nk, 1usize, d, ob, os2) != ok { ret mem.Full }
            if rooti_of(a, os2, d, ri) != ok { ret mem.Full }
            var c = 0usize
            while c < d {
                out[base + c] = ob[c]
                c += 1usize
            }
        } else {
            let (uv, e1) = zal(a, d * d)
            let (ui, e2) = zal(a, d * d)
            let (s, e3) = zal(a, d * d)
            let (w, e4) = zal(a, d * d)
            let (iw, e5) = zal(a, d * d)
            let (cc, e6) = zal(a, d * d)
            let (ci, e7) = zal(a, d * d)
            let (rv, e8) = zal(a, d)
            if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret mem.Full }
            if !bz.chol_upper(v, d, uv) { ret mem.Full }
            bz.inv_upper(uv, d, ui)
            gemm(false, true, ui, d, ui, d, d, d, d, s)
            if bz.rwishart(a, r, nu, s, d, w, iw, cc, ci) != ok { ret mem.Full }
            if rooti_of(a, iw, d, ri) != ok { ret mem.Full }
            var c = 0usize
            while c < d {
                rv[c] = rng.norm(r)
                c += 1usize
            }
            c = 0usize
            while c < d {
                var sm = 0.0f64
                var q = 0usize
                while q < d {
                    sm += ci[q * d + c] * rv[q]
                    q += 1usize
                }
                out[base + c] = bbar[c] + sm / math.sqrt[f64](a00)
                c += 1usize
            }
        }
        var c2 = 0usize
        while c2 < d * d {
            out[base + d + c2] = ri[c2]
            c2 += 1usize
        }
        mem.reset(a, start)
        k += 1usize
    }
    ret ok
}

// one rmixGibbs sweep: draw the components from the labels z, then new labels from the components and p, then p from the label counts; z and p are updated, comps gets mu (d) and rooti (d d) per component
fn mix_step(a: *mem.Arena, r: *rng.Rng, y: []const f64, n: usize, d: usize, bbar: []const f64, a00: f64, nu: f64, v: []const f64, av: []const f64, nc: usize, z: []f64, p: []f64, comps: []f64) -> err {
    let (a2, e3) = zal(a, nc)
    if e3 != ok { ret mem.Full }
    var i = 0usize
    if mix_comps(a, r, y, n, d, bbar, a00, nu, v, nc, z, comps) != ok { ret mem.Full }
    let (pr, e4) = zal(a, n * nc)
    let (u, e5) = zal(a, n)
    if e4 != ok || e5 != ok { ret mem.Full }
    var k = 0usize
    while k < nc {
        let base = k * (d + d * d)
        var lg = 0.0f64
        var q = 0usize
        while q < d {
            lg += math.log[f64](comps[base + d + q * d + q])
            q += 1usize
        }
        i = 0usize
        while i < n {
            var ss = 0.0f64
            var j = 0usize
            while j < d {
                var t = 0.0f64
                q = 0usize
                while q <= j {
                    t += comps[base + d + j * d + q] * (y[q * n + i] - comps[base + q])
                    q += 1usize
                }
                ss += t * t
                j += 1usize
            }
            pr[k * n + i] = math.exp[f64](-(f64(d) / 2.0f64) * 1.8378770664093453f64 + lg - 0.5f64 * ss) * p[k]
            i += 1usize
        }
        k += 1usize
    }
    k = 1usize
    while k < nc {
        i = 0usize
        while i < n {
            pr[k * n + i] += pr[(k - 1usize) * n + i]
            i += 1usize
        }
        k += 1usize
    }
    i = 0usize
    while i < n {
        u[i] = rng.unif(r) * pr[(nc - 1usize) * n + i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        var lab = 0usize
        while lab + 1usize < nc && u[i] > pr[lab * n + i] { lab += 1usize }
        z[i] = f64(lab + 1usize)
        i += 1usize
    }
    i = 0usize
    while i < nc {
        a2[i] = av[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        a2[usize(z[i]) - 1usize] += 1.0f64
        i += 1usize
    }
    bz.rdirichlet(r, a2, p)
    ret ok
}

// rnmixGibbs with keep = 1: nr sweeps from z = rep(1:nc) and p = 1/nc; draw rep occupies nc + n + nc (d + d d) values: p, z, then mu and rooti per component
fn rnmix_gibbs(a: *mem.Arena, r: *rng.Rng, y: []const f64, n: usize, d: usize, bbar: []const f64, a00: f64, nu: f64, v: []const f64, av: []const f64, nc: usize, nr: usize, out: []f64) -> err {
    let (z, e1) = zal(a, n)
    let (p, e2) = zal(a, nc)
    if e1 != ok || e2 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        z[i] = f64(i % nc + 1usize)
        i += 1usize
    }
    i = 0usize
    while i < nc {
        p[i] = 1.0f64 / f64(nc)
        i += 1usize
    }
    let w = nc + n + nc * (d + d * d)
    var rep = 0usize
    while rep < nr {
        let start = mem.mark(a)
        let o = out[rep * w..(rep + 1usize) * w]
        let comps = o[nc + n..w]
        if mix_step(a, r, y, n, d, bbar, a00, nu, v, av, nc, z, p, comps) != ok { ret mem.Full }
        i = 0usize
        while i < nc {
            o[i] = p[i]
            i += 1usize
        }
        i = 0usize
        while i < n {
            o[nc + i] = z[i]
            i += 1usize
        }
        mem.reset(a, start)
        rep += 1usize
    }
    ret ok
}

// rivGibbs with keep = 1: y, x length n; z n by dd; w n by dg; mbg and abg for (beta, gamma); md and ad for delta; V 2 by 2; draw rep is delta (dd), beta, gamma (dg), Sigma (4)
fn riv_gibbs(a: *mem.Arena, r: *rng.Rng, y: []const f64, x: []const f64, z: []const f64, w: []const f64, mbg: []const f64, abg: []const f64, md: []const f64, ad: []const f64, v: []const f64, nu: f64, n: usize, dd: usize, dg: usize, nr: usize, out: []f64) -> err {
    let (sg, e1) = zal(a, 4usize)
    let (delta, e2) = zal(a, dd)
    if e1 != ok || e2 != ok { ret mem.Full }
    sg[0usize] = 1.0f64
    sg[3usize] = 1.0f64
    var i = 0usize
    while i < dd {
        delta[i] = 0.1f64
        i += 1usize
    }
    let wd = dd + 1usize + dg + 4usize
    var rep = 0usize
    while rep < nr {
        let start = mem.mark(a)
        let (yt, e3) = zal(a, n)
        let (xt, e4) = zal(a, n * (1usize + dg))
        let (bg, e5) = zal(a, 1usize + dg)
        if e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
        let sig = math.sqrt[f64](sg[3usize] - (sg[1usize] * sg[1usize]) / sg[0usize])
        i = 0usize
        while i < n {
            var zd = 0.0f64
            var j = 0usize
            while j < dd {
                zd += z[j * n + i] * delta[j]
                j += 1usize
            }
            let ee2 = (sg[1usize] / sg[0usize]) * (x[i] - zd)
            yt[i] = (y[i] - ee2) / sig
            xt[i] = x[i] / sig
            j = 0usize
            while j < dg {
                xt[(j + 1usize) * n + i] = w[j * n + i] / sig
                j += 1usize
            }
            i += 1usize
        }
        if bz.breg(a, r, yt, xt, mbg, abg, 1usize + dg, bg) != ok { ret mem.Full }
        let beta = bg[0usize]
        // B = C Sigma C' with C = [1 0; beta 1]
        let (cm, e6) = zal(a, 4usize)
        let (t1, e7) = zal(a, 4usize)
        let (bm, e8) = zal(a, 4usize)
        let (ub, e9) = zal(a, 4usize)
        let (ubi, e10) = zal(a, 4usize)
        if e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret mem.Full }
        cm[0usize] = 1.0f64
        cm[1usize] = beta
        cm[3usize] = 1.0f64
        gemm(false, false, cm, 2usize, sg, 2usize, 2usize, 2usize, 2usize, t1)
        gemm(false, true, t1, 2usize, cm, 2usize, 2usize, 2usize, 2usize, bm)
        if !bz.chol_upper(bm, 2usize, ub) { ret mem.Full }
        bz.inv_upper(ub, 2usize, ubi)
        // Li = t(ubi): Li(r, c) = ubi[r * 2 + c]
        let (yd, e11) = zal(a, 2usize * n)
        let (xtd, e12) = zal(a, 2usize * n * dd)
        if e11 != ok || e12 != ok { ret mem.Full }
        i = 0usize
        while i < n {
            var wg = 0.0f64
            var j = 0usize
            while j < dg {
                wg += w[j * n + i] * bg[1usize + j]
                j += 1usize
            }
            let u = y[i] - wg
            yd[2usize * i] = ubi[0usize] * x[i] + ubi[1usize] * u
            yd[2usize * i + 1usize] = ubi[2usize] * x[i] + ubi[3usize] * u
            j = 0usize
            while j < dd {
                let zv = z[j * n + i]
                xtd[j * 2usize * n + 2usize * i] = ubi[0usize] * zv + ubi[1usize] * beta * zv
                xtd[j * 2usize * n + 2usize * i + 1usize] = ubi[2usize] * zv + ubi[3usize] * beta * zv
                j += 1usize
            }
            i += 1usize
        }
        if bz.breg(a, r, yd, xtd, md, ad, dd, delta) != ok { ret mem.Full }
        // Sigma
        let (rs, e13) = zal(a, 2usize * n)
        let (ss, e14) = zal(a, 4usize)
        if e13 != ok || e14 != ok { ret mem.Full }
        i = 0usize
        while i < n {
            var zd = 0.0f64
            var j = 0usize
            while j < dd {
                zd += z[j * n + i] * delta[j]
                j += 1usize
            }
            var wg = 0.0f64
            j = 0usize
            while j < dg {
                wg += w[j * n + i] * bg[1usize + j]
                j += 1usize
            }
            rs[i] = x[i] - zd
            rs[n + i] = y[i] - beta * x[i] - wg
            i += 1usize
        }
        gemm(true, false, rs, n, rs, n, 2usize, 2usize, n, ss)
        let (vs, e15) = zal(a, 4usize)
        let (uc, e16) = zal(a, 4usize)
        let (uci, e17) = zal(a, 4usize)
        let (vsi, e18) = zal(a, 4usize)
        let (w1, e19) = zal(a, 4usize)
        let (c1, e20) = zal(a, 4usize)
        let (c2, e21) = zal(a, 4usize)
        let (iw, e22) = zal(a, 4usize)
        if e15 != ok || e16 != ok || e17 != ok || e18 != ok || e19 != ok || e20 != ok || e21 != ok || e22 != ok { ret mem.Full }
        i = 0usize
        while i < 4usize {
            vs[i] = v[i] + ss[i]
            i += 1usize
        }
        if !bz.chol_upper(vs, 2usize, uc) { ret mem.Full }
        bz.inv_upper(uc, 2usize, uci)
        gemm(false, true, uci, 2usize, uci, 2usize, 2usize, 2usize, 2usize, vsi)
        if bz.rwishart(a, r, nu + f64(n), vsi, 2usize, w1, iw, c1, c2) != ok { ret mem.Full }
        i = 0usize
        while i < 4usize {
            sg[i] = iw[i]
            i += 1usize
        }
        let o = out[rep * wd..(rep + 1usize) * wd]
        i = 0usize
        while i < dd {
            o[i] = delta[i]
            i += 1usize
        }
        o[dd] = beta
        i = 0usize
        while i < dg {
            o[dd + 1usize + i] = bg[1usize + i]
            i += 1usize
        }
        i = 0usize
        while i < 4usize {
            o[dd + 1usize + dg + i] = sg[i]
            i += 1usize
        }
        mem.reset(a, start)
        rep += 1usize
    }
    ret ok
}

// runiregG: one Gibbs step of a univariate regression; beta drawn given sigmasq (k normals) and then sigmasq given beta (one chi-square); abb is A betabar; returns the new sigmasq, beta into beta
fn runireg_g(a: *mem.Arena, r: *rng.Rng, y: []const f64, x: []const f64, xpx: []const f64, xpy: []const f64, sigmasq: f64, am: []const f64, abb: []const f64, nu: f64, ssq: f64, n: usize, k: usize, beta: []f64) -> f64 {
    let start = mem.mark(a)
    let (m1, e1) = zal(a, k * k)
    let (u, e2) = zal(a, k * k)
    let (ir, e3) = zal(a, k * k)
    let (cov, e4) = zal(a, k * k)
    let (rhs, e5) = zal(a, k)
    let (bt, e6) = zal(a, k)
    let (nz, e7) = zal(a, k)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < k * k {
        m1[i] = xpx[i] / sigmasq + am[i]
        i += 1usize
    }
    if !bz.chol_upper(m1, k, u) { ret 0.0f64 / 0.0f64 }
    bz.inv_upper(u, k, ir)
    gemm(false, true, ir, k, ir, k, k, k, k, cov)
    i = 0usize
    while i < k {
        rhs[i] = xpy[i] / sigmasq + abb[i]
        i += 1usize
    }
    i = 0usize
    while i < k {
        nz[i] = rng.norm(r)
        i += 1usize
    }
    var c = 0usize
    while c < k {
        var s = 0.0f64
        var q = 0usize
        while q < k {
            s += cov[q * k + c] * rhs[q]
            q += 1usize
        }
        var t = 0.0f64
        q = 0usize
        while q < k {
            t += ir[q * k + c] * nz[q]
            q += 1usize
        }
        beta[c] = s + t
        c += 1usize
    }
    var ssr = 0.0f64
    i = 0usize
    while i < n {
        var f = 0.0f64
        c = 0usize
        while c < k {
            f += x[c * n + i] * beta[c]
            c += 1usize
        }
        ssr += (y[i] - f) * (y[i] - f)
        i += 1usize
    }
    let out = (ssr + nu * ssq) / rd.rchisq(r, nu + f64(n))
    mem.reset(a, start)
    ret out
}

// rhierLinearModel with keep = 1; regression i has ns[i] rows, its y and X sit one after another in ys (ns[i]) and xs (ns[i] by nvar, column-major); Delta starts at 0, Vbeta at I, tau at tau0; draw rep is Vbeta (nvar^2), Delta (nz nvar), tau (nreg), betas (nreg nvar)
fn rhier_linear(a: *mem.Arena, r: *rng.Rng, ns: []const f64, ys: []const f64, xs: []const f64, zm: []const f64, dbar: []const f64, am: []const f64, nu: f64, v: []const f64, nue: f64, ssq: []const f64, tau0: []const f64, nreg: usize, nvar: usize, nz: usize, nr: usize, out: []f64) -> err {
    let (tau, e1) = zal(a, nreg)
    let (delta, e2) = zal(a, nz * nvar)
    let (vb, e3) = zal(a, nvar * nvar)
    let (betas, e4) = zal(a, nreg * nvar)
    let (xpx, e5) = zal(a, nreg * nvar * nvar)
    let (xpy, e6) = zal(a, nreg * nvar)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret mem.Full }
    var i = 0usize
    while i < nreg {
        tau[i] = tau0[i]
        i += 1usize
    }
    i = 0usize
    while i < nvar {
        vb[i * nvar + i] = 1.0f64
        i += 1usize
    }
    // per-regression XpX and Xpy
    var off = 0usize
    var g = 0usize
    while g < nreg {
        let ng = usize(ns[g])
        let xg = xs[off * nvar..(off + ng) * nvar]
        gemm(true, false, xg, ng, xg, ng, nvar, nvar, ng, xpx[g * nvar * nvar..(g + 1usize) * nvar * nvar])
        gemm(true, false, xg, ng, ys[off..off + ng], ng, nvar, 1usize, ng, xpy[g * nvar..(g + 1usize) * nvar])
        off += ng
        g += 1usize
    }
    let w = nvar * nvar + nz * nvar + nreg + nreg * nvar
    var rep = 0usize
    while rep < nr {
        let start = mem.mark(a)
        let (u, e7) = zal(a, nvar * nvar)
        let (ui, e8) = zal(a, nvar * nvar)
        let (ab, e9) = zal(a, nvar * nvar)
        let (bb, e10) = zal(a, nreg * nvar)
        let (abb, e11) = zal(a, nvar * nreg)
        let (ob, e12) = zal(a, nz * nvar)
        let (os2, e13) = zal(a, nvar * nvar)
        let (bg, e14) = zal(a, nvar)
        if e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok { ret mem.Full }
        if !bz.chol_upper(vb, nvar, u) { ret mem.Full }
        bz.inv_upper(u, nvar, ui)
        gemm(false, true, ui, nvar, ui, nvar, nvar, nvar, nvar, ab)
        gemm(false, false, zm, nreg, delta, nz, nreg, nvar, nz, bb)
        gemm(false, true, ab, nvar, bb, nreg, nvar, nreg, nvar, abb)
        off = 0usize
        g = 0usize
        while g < nreg {
            let ng = usize(ns[g])
            tau[g] = runireg_g(a, r, ys[off..off + ng], xs[off * nvar..(off + ng) * nvar], xpx[g * nvar * nvar..(g + 1usize) * nvar * nvar], xpy[g * nvar..(g + 1usize) * nvar], tau[g], ab, abb[g * nvar..(g + 1usize) * nvar], nue, ssq[g], ng, nvar, bg)
            i = 0usize
            while i < nvar {
                betas[i * nreg + g] = bg[i]
                i += 1usize
            }
            off += ng
            g += 1usize
        }
        if bz.rmultireg(a, r, betas, zm, dbar, am, nu, v, nreg, nz, nvar, ob, os2) != ok { ret mem.Full }
        i = 0usize
        while i < nvar * nvar {
            vb[i] = os2[i]
            i += 1usize
        }
        i = 0usize
        while i < nz * nvar {
            delta[i] = ob[i]
            i += 1usize
        }
        let o = out[rep * w..(rep + 1usize) * w]
        i = 0usize
        while i < nvar * nvar {
            o[i] = vb[i]
            i += 1usize
        }
        i = 0usize
        while i < nz * nvar {
            o[nvar * nvar + i] = delta[i]
            i += 1usize
        }
        i = 0usize
        while i < nreg {
            o[nvar * nvar + nz * nvar + i] = tau[i]
            i += 1usize
        }
        i = 0usize
        while i < nreg * nvar {
            o[nvar * nvar + nz * nvar + nreg + i] = betas[i]
            i += 1usize
        }
        mem.reset(a, start)
        rep += 1usize
    }
    ret ok
}

// trunNormBelow(a): a standard normal truncated below at a; for a <= -4 the rejection draw is made and then dropped, as the package does, before the inverse-cdf draw that is returned
fn trun_norm_below(r: *rng.Rng, a: f64) -> f64 {
    if a > 4.0f64 {
        while true {
            let e = -math.log[f64](rng.unif(r))
            let e1 = -math.log[f64](rng.unif(r))
            if e * e <= 2.0f64 * e1 * a * a { ret a + e / a }
        }
    }
    if a <= -4.0f64 {
        var got = false
        while !got {
            let c = rng.norm(r)
            if c >= a { got = true }
        }
    }
    let pa = mdist.pnorm(a, 0.0f64, 1.0f64, true, false)
    let u = rng.unif(r)
    ret mdist.qnorm(u * (1.0f64 - pa) + pa, 0.0f64, 1.0f64, true, false)
}

// trunNorm(mu, sig, trunpt, above): above = false truncates from below at trunpt, true from above
fn trun_norm(r: *rng.Rng, mu: f64, sig: f64, trunpt: f64, above: bool) -> f64 {
    if !above {
        let z = trun_norm_below(r, (trunpt - mu) / sig)
        ret sig * z + mu
    }
    let z = trun_norm_below(r, (mu - trunpt) / sig)
    ret -sig * z + mu
}

// rmnpGibbs (mvp = false, y holds 1..p per observation, p = pm1) and rmvpGibbs (mvp = true, y is n p zeros and ones) with keep = 1: x is n p by k; draw rep is beta (k) and Sigma (p p)
fn mnp_gibbs(a: *mem.Arena, r: *rng.Rng, mvp: bool, y: []const f64, x: []const f64, beta0: []const f64, sigma0: []const f64, v: []const f64, nu: f64, betabar: []const f64, am: []const f64, p: usize, n: usize, k: usize, nr: usize, out: []f64) -> err {
    let xr = n * p
    let (w, e1) = zal(a, xr)
    let (beta, e2) = zal(a, k)
    let (cm, e3) = zal(a, p * p)
    let (si, e4) = zal(a, p * p)
    let (u0, e5) = zal(a, p * p)
    let (u0i, e6) = zal(a, p * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret mem.Full }
    var i = 0usize
    while i < k {
        beta[i] = beta0[i]
        i += 1usize
    }
    bz.inv_upper(sigma0, p, u0i)
    if !bz.chol_upper(u0i, p, cm) { ret mem.Full }
    let wd = k + p * p
    var rep = 0usize
    while rep < nr {
        let start = mem.mark(a)
        gemm(true, false, cm, p, cm, p, p, p, p, si)
        let (mu, e7) = zal(a, xr)
        let (zw, e8) = zal(a, xr)
        let (zx, e9) = zal(a, xr * k)
        let (bn, e10) = zal(a, k)
        let (eps, e11) = zal(a, xr)
        let (ss, e12) = zal(a, p * p)
        if e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok { ret mem.Full }
        gemm(false, false, x, xr, beta, k, xr, 1usize, k, mu)
        // draw w, observation by observation, component by component
        var ob = 0usize
        while ob < n {
            let at = ob * p
            var q = 0usize
            while q < p {
                var bound = 0.0f64
                var above = true
                if mvp {
                    above = y[at + q] == 0.0f64
                } else {
                    bound = 0.0f64
                    var j = 0usize
                    while j < p {
                        if j != q && w[at + j] > bound { bound = w[at + j] }
                        j += 1usize
                    }
                    above = usize(y[ob]) != q + 1usize
                }
                let csig = 1.0f64 / si[q * p + q]
                var m = 0.0f64
                var j = 0usize
                while j < p {
                    if j != q { m += -csig * si[q * p + j] * (w[at + j] - mu[at + j]) }
                    j += 1usize
                }
                w[at + q] = trun_norm(r, mu[at + q] + m, math.sqrt[f64](csig), bound, above)
                q += 1usize
            }
            ob += 1usize
        }
        // zmat: C applied to every block of p rows
        ob = 0usize
        while ob < n {
            let at = ob * p
            var q = 0usize
            while q < p {
                var s = 0.0f64
                var j = q
                while j < p {
                    s += cm[j * p + q] * w[at + j]
                    j += 1usize
                }
                zw[at + q] = s
                var c = 0usize
                while c < k {
                    var t = 0.0f64
                    j = q
                    while j < p {
                        t += cm[j * p + q] * x[c * xr + at + j]
                        j += 1usize
                    }
                    zx[c * xr + at + q] = t
                    c += 1usize
                }
                q += 1usize
            }
            ob += 1usize
        }
        if bz.breg(a, r, zw, zx, betabar, am, k, bn) != ok { ret mem.Full }
        i = 0usize
        while i < k {
            beta[i] = bn[i]
            i += 1usize
        }
        gemm(false, false, x, xr, beta, k, xr, 1usize, k, eps)
        i = 0usize
        while i < xr {
            eps[i] = w[i] - eps[i]
            i += 1usize
        }
        // S = sum over observations of eps_i eps_i'
        gemm(false, true, eps, p, eps, p, p, p, n, ss)
        let (vs, e13) = zal(a, p * p)
        let (uc, e14) = zal(a, p * p)
        let (uci, e15) = zal(a, p * p)
        let (vsi, e16) = zal(a, p * p)
        let (w1, e17) = zal(a, p * p)
        let (iw, e18) = zal(a, p * p)
        let (c2, e19) = zal(a, p * p)
        if e13 != ok || e14 != ok || e15 != ok || e16 != ok || e17 != ok || e18 != ok || e19 != ok { ret mem.Full }
        i = 0usize
        while i < p * p {
            vs[i] = v[i] + ss[i]
            i += 1usize
        }
        if !bz.chol_upper(vs, p, uc) { ret mem.Full }
        bz.inv_upper(uc, p, uci)
        gemm(false, true, uci, p, uci, p, p, p, p, vsi)
        if bz.rwishart(a, r, nu + f64(n), vsi, p, w1, iw, cm, c2) != ok { ret mem.Full }
        let o = out[rep * wd..(rep + 1usize) * wd]
        i = 0usize
        while i < k {
            o[i] = beta[i]
            i += 1usize
        }
        i = 0usize
        while i < p * p {
            o[k + i] = iw[i]
            i += 1usize
        }
        mem.reset(a, start)
        rep += 1usize
    }
    ret ok
}
