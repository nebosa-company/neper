// R's tgp::bgp and tgp::bgpllm: the Bayesian Gaussian process with the separable power exponential correlation
// (corr = "expsep"), no tree, the flat beta prior, hyper-priors on d and the nugget fixed (the defaults), with
// (bgpllm, gamma[1] > 0) or without (bgp, gamma[1] = 0) the limiting linear model. The Markov chain is tgp's:
// ExpSep::Draw (random-walk proposals for d and the booleans b, the MH step on the marginal posterior, then
// the nugget step), Gp::Draw's s2 and beta draws, the s2 hyper-prior step, then Tree::Predict's draws (ZZ before
// Zp under the GP, Zp before ZZ under the LLM). Not here: the other correlation functions, the other beta
// priors, tempering, the restart tgp does after 1000 straight d rejections, and the tree.

use e.algo.rand.r as rr
use e.algo.stat.tgp as tgp
use e.algo.stat.tgp_blm as lm
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.mem

error BadChain

type Gx = struct {
    g: lm.Gp, gn: lm.Gp,
    n: usize, d: usize, col: usize,
    nug: f64, dv: [16]f64, bv: [16]i64, deff: [16]f64,
    linear: bool, gam0: f64, gam1: f64, gam2: f64,
    logdet: f64, logdet_new: f64, dreject: i64,
    x: []f64, k: []f64, ki: []f64, kc: []f64, kn: []f64, kin: []f64, kcn: []f64, w: []f64
}

type Prop = struct { dn: [16]f64, bn: [16]i64, qf: f64, qb: f64, lin: bool }

fn lg(x: f64) -> f64 { ret math.log[f64](x) }

fn ninf() -> f64 { ret 0.0f64 - 1.0f64 / 0.0f64 }

// exp_corr_sep_symm: n x n correlation with the nugget on the diagonal
fn corr_symm(k: []f64, x: []const f64, n: usize, d: usize, de: [16]f64, nug: f64) {
    var i = 0usize
    while i < n {
        k[i * n + i] = 1.0f64 + nug
        var j = i + 1usize
        while j < n {
            var s = 0.0f64
            if de[0usize] != 0.0f64 {
                let diff = x[i * d] - x[j * d]
                s = diff * diff / de[0usize]
            }
            var q = 1usize
            while q < d {
                if de[q] != 0.0f64 {
                    let df = x[i * d + q] - x[j * d + q]
                    s += df * df / de[q]
                }
                q += 1usize
            }
            let v = math.exp[f64](0.0f64 - s)
            k[j * n + i] = v
            k[i * n + j] = v
            j += 1usize
        }
        i += 1usize
    }
}

// exp_corr_sep for XX (m rows) against X (n rows): out[i * n + j]
fn corr_cross(out: []f64, xx: []const f64, m: usize, x: []const f64, n: usize, d: usize, de: [16]f64) {
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < n {
            var s = 0.0f64
            if de[0usize] != 0.0f64 {
                let diff = xx[i * d] - x[j * d]
                s = diff * diff / de[0usize]
            }
            var q = 1usize
            while q < d {
                if de[q] != 0.0f64 {
                    let df = xx[i * d + q] - x[j * d + q]
                    s += df * df / de[q]
                }
                q += 1usize
            }
            out[i * n + j] = math.exp[f64](0.0f64 - s)
            j += 1usize
        }
        i += 1usize
    }
}

// inverse_chol: lower Cholesky factor of k into kc and k^-1 into ki (w is scratch); false if k is not positive definite
fn chol_inv(k: []const f64, ki: []f64, kc: []f64, n: usize, w: []f64) -> bool {
    var i = 0usize
    while i < n {
        var j = 0usize
        while j <= i {
            var s = k[i * n + j]
            var m = 0usize
            while m < j {
                s -= kc[i * n + m] * kc[j * n + m]
                m += 1usize
            }
            if i == j {
                if s > 0.0f64 { kc[i * n + i] = math.sqrt[f64](s) } else { ret false }
            } else {
                kc[i * n + j] = s / kc[j * n + j]
            }
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n * n {
        w[i] = 0.0f64
        i += 1usize
    }
    var c = 0usize
    while c < n {
        i = c
        while i < n {
            var s = 0.0f64
            if i == c { s = 1.0f64 }
            var m = c
            while m < i {
                s -= kc[i * n + m] * w[m * n + c]
                m += 1usize
            }
            w[i * n + c] = s / kc[i * n + i]
            i += 1usize
        }
        c += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j <= i {
            var s = 0.0f64
            var m = i
            while m < n {
                s += w[m * n + i] * w[m * n + j]
                m += 1usize
            }
            ki[i * n + j] = s
            ki[j * n + i] = s
            j += 1usize
        }
        i += 1usize
    }
    ret true
}

fn log_det_chol(kc: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += lg(kc[i * n + i])
        i += 1usize
    }
    ret 2.0f64 * s
}

// log |Vb| through a Cholesky factor; -Inf when it fails
fn log_det_small(vb: [256]f64, col: usize) -> f64 {
    var l: [256]f64 = zero
    var i = 0usize
    var s = 0.0f64
    while i < col {
        var j = 0usize
        while j <= i {
            var t = vb[i * 16usize + j]
            var m = 0usize
            while m < j {
                t -= l[i * 16usize + m] * l[j * 16usize + m]
                m += 1usize
            }
            if i == j {
                if t > 0.0f64 {
                    l[i * 16usize + i] = math.sqrt[f64](t)
                    s += lg(l[i * 16usize + i])
                } else {
                    ret ninf()
                }
            } else {
                l[i * 16usize + j] = t / l[j * 16usize + j]
            }
            j += 1usize
        }
        i += 1usize
    }
    ret 2.0f64 * s
}

// compute_lambda with Ti = 0, tau2 = 1, itemp = 1 and the n x n inverse ki: fills vb, bmu and lambda of g
fn compute_ki(g: *lm.Gp, ki: []const f64, kz: []f64) {
    let n = g.n
    let col = g.col
    var vbi: [256]f64 = zero
    var by: [16]f64 = zero
    // kz = Ki Z
    var q = 0usize
    var zkz = 0.0f64
    while q < n {
        var s = 0.0f64
        var m = 0usize
        while m < n {
            s += ki[q * n + m] * g.z[m]
            m += 1usize
        }
        kz[q] = s
        zkz += g.z[q] * s
        q += 1usize
    }
    var i = 0usize
    while i < col {
        var j = 0usize
        while j <= i {
            var tot = 0.0f64
            q = 0usize
            while q < n {
                var s = 0.0f64
                var m = 0usize
                while m < n {
                    s += ki[q * n + m] * lm.fz(g, j, m)
                    m += 1usize
                }
                tot += lm.fz(g, i, q) * s
                q += 1usize
            }
            vbi[i * 16usize + j] = tot
            vbi[j * 16usize + i] = tot
            j += 1usize
        }
        var sy = 0.0f64
        q = 0usize
        while q < n {
            sy += lm.fz(g, i, q) * kz[q]
            q += 1usize
        }
        by[i] = sy
        i += 1usize
    }
    g.vb = lm.invert_small(vbi, col)
    var bvb = 0.0f64
    i = 0usize
    while i < col {
        var s = 0.0f64
        var j = 0usize
        while j < col {
            s += g.vb[i * 16usize + j] * by[j]
            j += 1usize
        }
        g.bmu[i] = s
        bvb += s * by[i]
        i += 1usize
    }
    g.lambda = zkz - bvb
}

fn post_margin(n: usize, col: usize, lambda: f64, vb: [256]f64, log_det_k: f64, a0: f64, g0: f64) -> f64 {
    let lvb = log_det_small(vb, col)
    if lvb == ninf() || lambda < 0.0f64 || log_det_k == ninf() { ret ninf() }
    let one = lvb - log_det_k
    let two = 0.0f64 - 0.5f64 * (a0 + f64(n)) * lg(0.5f64 * (g0 + lambda))
    let p = 0.5f64 * one + two
    if p != p { ret ninf() }
    ret p
}

// gamma_mixture_pdf, log scale
fn gamma_mix_lp(x: f64, a0: f64, b0: f64, a1: f64, b1: f64) -> f64 {
    var p1 = 0.0f64
    var p2 = 0.0f64
    if a0 != 0.0f64 { p1 = a0 * lg(b0) - nm.lgammafn(a0) + (a0 - 1.0f64) * lg(x) - b0 * x }
    if a1 != 0.0f64 { p2 = a1 * lg(b1) - nm.lgammafn(a1) + (a1 - 1.0f64) * lg(x) - b1 * x }
    ret lg(0.5f64 * (math.exp[f64](p1) + math.exp[f64](p2)))
}

// log_DPrior_pdf with the default d prior: alpha = (1, 10), beta = (20, 10)
fn log_d_prior(dv: [16]f64, dim: usize) -> f64 {
    var p = 0.0f64
    var i = 0usize
    while i < dim {
        p += gamma_mix_lp(dv[i], 1.0f64, 20.0f64, 10.0f64, 10.0f64)
        i += 1usize
    }
    ret p
}

// LINEAR(gamma, min, max, d)
fn lin_prob(gm: *Gx, dv: f64) -> f64 { ret gm.gam1 + gm.gam2 / (1.0f64 + math.exp[f64](0.0f64 - gm.gam0 * (dv - 0.5f64))) }

// ExpSep::propose_new_d
fn propose_new_d(gm: *Gx, rk: *tgp.Rk) -> Prop {
    var p: Prop = zero
    p.dn = gm.dv
    p.bn = gm.bv
    p.qf = 1.0f64
    p.qb = 1.0f64
    p.lin = false
    let dim = gm.d
    let llm = gm.gam0 > 0.0f64
    if dim == 1usize || tgp.runi(rk) < 0.3333333333f64 {
        var i = 0usize
        while i < dim {
            let (v, qf, qb) = lm.unif_propose_pos(rk, gm.dv[i])
            p.dn[i] = v
            p.qf = p.qf * qf
            p.qb = p.qb * qb
            i += 1usize
        }
        if llm {
            if dim == 1usize || tgp.runi(rk) < 0.5f64 {
                // linear_rand_sep
                var all = true
                i = 0usize
                while i < dim {
                    let pb = lin_prob(gm, p.dn[i])
                    if tgp.runi(rk) < pb { p.bn[i] = 0i64 } else { p.bn[i] = 1i64 }
                    if p.bn[i] == 1i64 { all = false }
                    i += 1usize
                }
                p.lin = all
            } else {
                p.lin = gm.linear
            }
        }
        ret p
    }
    // draw just the ds with b == 1 or just those with b == 0
    var eq = false
    if tgp.runi(rk) < 0.5f64 { eq = true }
    var idx: [16]usize = zero
    var len = 0usize
    var i2 = 0usize
    while i2 < dim {
        var hit = gm.deff[i2] != 0.0f64
        if eq { hit = gm.deff[i2] == 0.0f64 }
        if hit {
            idx[len] = i2
            len += 1usize
        }
        i2 += 1usize
    }
    if len == 0usize {
        p.lin = gm.linear
        ret p
    }
    i2 = 0usize
    while i2 < len {
        let (v, qf, qb) = lm.unif_propose_pos(rk, gm.dv[idx[i2]])
        p.dn[idx[i2]] = v
        p.qf = p.qf * qf
        p.qb = p.qb * qb
        i2 += 1usize
    }
    if !llm { ret p }
    if tgp.runi(rk) < 0.5f64 {
        i2 = 0usize
        while i2 < len {
            let pb = lin_prob(gm, p.dn[idx[i2]])
            if tgp.runi(rk) < pb { p.bn[idx[i2]] = 0i64 } else { p.bn[idx[i2]] = 1i64 }
            i2 += 1usize
        }
        var all = true
        i2 = 0usize
        while i2 < dim {
            if p.bn[i2] == 1i64 { all = false }
            i2 += 1usize
        }
        p.lin = all
    } else {
        p.lin = gm.linear
    }
    ret p
}

fn swap_new(gm: *Gx) {
    gm.g.vb = gm.gn.vb
    gm.g.bmu = gm.gn.bmu
    gm.g.lambda = gm.gn.lambda
    gm.logdet = gm.logdet_new
    if !gm.linear {
        let t = gm.k
        gm.k = gm.kn
        gm.kn = t
        let u = gm.ki
        gm.ki = gm.kin
        gm.kin = u
    }
}

// d_sep_draw_margin: 1 accepted, 0 rejected, -1 a NaN acceptance ratio
fn d_sep_margin(gm: *Gx, has_eff: bool, dne: [16]f64, lin: bool, q_ratio: f64, p_ratio: f64, rk: *tgp.Rk) -> i64 {
    let n = gm.n
    let col = gm.col
    var pd = 0.0f64
    var pdlast = 0.0f64
    gm.gn = gm.g
    if !lin && has_eff {
        corr_symm(gm.kn, gm.x, n, gm.d, dne, gm.nug)
        if chol_inv(gm.kn, gm.kin, gm.kcn, n, gm.w) { gm.logdet_new = log_det_chol(gm.kcn, n) } else { gm.logdet_new = ninf() }
        compute_ki(&gm.gn, gm.kin, gm.w)
    } else {
        if lin {
            gm.logdet_new = f64(n) * lg(1.0f64 + gm.nug)
            gm.gn.kd = 1.0f64 + gm.nug
            lm.compute(&gm.gn)
        }
    }
    if has_eff || lin {
        let a0 = gm.g.a0 - f64(col)
        pd = post_margin(n, col, gm.gn.lambda, gm.gn.vb, gm.logdet_new, a0, gm.g.g0)
        pdlast = post_margin(n, col, gm.g.lambda, gm.g.vb, gm.logdet, a0, gm.g.g0)
    }
    let alpha = math.exp[f64](pd - pdlast + p_ratio) * q_ratio
    if alpha != alpha { ret 0i64 - 1i64 }
    if tgp.runi(rk) < alpha { ret 1i64 }
    ret 0i64
}

// DrawNugs: with probability one half, the MH step for the nugget; true when it moved
fn nugs_draw(gm: *Gx, rk: *tgp.Rk) -> bool {
    let ru = tgp.runi(rk)
    if ru > 0.5f64 { ret false }
    let n = gm.n
    let col = gm.col
    let last = gm.nug
    let (r1, qf, qb) = lm.unif_propose_pos(rk, last - 0.0000000001f64)
    let nugn = r1 + 0.0000000001f64
    gm.gn = gm.g
    if gm.linear {
        gm.logdet_new = f64(n) * lg(1.0f64 + nugn)
        gm.gn.kd = 1.0f64 + nugn
        lm.compute(&gm.gn)
    } else {
        var t = 0usize
        while t < n * n {
            gm.kn[t] = gm.k[t]
            t += 1usize
        }
        t = 0usize
        while t < n {
            gm.kn[t * n + t] += nugn - last
            t += 1usize
        }
        if chol_inv(gm.kn, gm.kin, gm.kcn, n, gm.w) { gm.logdet_new = log_det_chol(gm.kcn, n) } else { gm.logdet_new = ninf() }
        compute_ki(&gm.gn, gm.kin, gm.w)
    }
    let a0 = gm.g.a0 - f64(col)
    var pnug = gamma_mix_lp(nugn - 0.0000000001f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64)
    pnug += post_margin(n, col, gm.gn.lambda, gm.gn.vb, gm.logdet_new, a0, gm.g.g0)
    var pnuglast = gamma_mix_lp(last - 0.0000000001f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64)
    pnuglast += post_margin(n, col, gm.g.lambda, gm.g.vb, gm.logdet, a0, gm.g.g0)
    let alpha = math.exp[f64](pnug - pnuglast) * (qb / qf)
    if tgp.runi(rk) > alpha { ret false }
    gm.nug = nugn
    swap_new(gm)
    ret true
}

// ExpSep::Draw (no forced linear model): 1 or 0, -1 on a NaN ratio, -2 after 1000 rejections in a row
fn corr_draw(gm: *Gx, rk: *tgp.Rk) -> i64 {
    if gm.linear {
        if tgp.runi(rk) > 0.5f64 {
            if nugs_draw(gm, rk) { ret 1i64 }
            ret 0i64
        }
    }
    let pr = propose_new_d(gm, rk)
    let d = gm.d
    var has_eff = false
    var dne: [16]f64 = zero
    if !pr.lin {
        var equal = true
        var i = 0usize
        while i < d {
            dne[i] = pr.dn[i] * f64(pr.bn[i])
            if dne[i] != gm.deff[i] { equal = false }
            i += 1usize
        }
        if !equal { has_eff = true }
    }
    let p_ratio = log_d_prior(pr.dn, d) - log_d_prior(gm.dv, d)
    let q_ratio = pr.qb / pr.qf
    let success = d_sep_margin(gm, has_eff, dne, pr.lin, q_ratio, p_ratio, rk)
    if success == 1i64 {
        gm.dv = pr.dn
        if !pr.lin && has_eff { gm.deff = dne }
        if pr.lin {
            var z: [16]f64 = zero
            gm.deff = z
        }
        gm.linear = pr.lin
        gm.bv = pr.bn
        if gm.linear || has_eff { swap_new(gm) }
    }
    if success == 0i64 - 1i64 { ret success }
    if success == 0i64 { gm.dreject += 1i64 } else { gm.dreject = 0i64 }
    if gm.dreject >= 1000i64 { ret 0i64 - 2i64 }
    let changed = nugs_draw(gm, rk)
    if success == 1i64 || changed { ret 1i64 }
    ret 0i64
}

// Gp::Compute
fn gp_compute(gm: *Gx) {
    if gm.linear {
        gm.g.kd = 1.0f64 + gm.nug
        lm.compute(&gm.g)
    } else {
        compute_ki(&gm.g, gm.ki, gm.w)
    }
}

fn zz_improv(imp: []f64, base: usize, nn: usize, m: []const f64, s2: []const f64, zlow: f64) {
    var q = 0usize
    while q < nn {
        let zs = math.sqrt[f64](s2[q])
        let df = zlow - m[q]
        let st = df / zs
        let dl = 0.0f64 - 0.91893853320467274f64 - 0.5f64 * (st * st)
        let dd = math.exp[f64](dl)
        let pp = dist.pnorm(st, 0.0f64, 1.0f64, true, false)
        var iv = df * pp + zs * dd
        if iv < 0.0f64 { iv = 0.0f64 }
        imp[base + q] = iv
        q += 1usize
    }
}

fn data_improv(imp: []f64, base: usize, nn: usize, zp: []const f64, n: usize, zz: []const f64) {
    var fmin = zp[0usize]
    var p = 1usize
    while p < n {
        if zp[p] < fmin { fmin = zp[p] }
        p += 1usize
    }
    var q = 0usize
    while q < nn {
        let df = fmin - zz[q]
        if df > 0.0f64 { imp[base + q] = df } else { imp[base + q] = 0.0f64 }
        q += 1usize
    }
}

// Tree::Predict at the single leaf: the draws and the kriging moments of round `row`
fn record(gm: *Gx, run: *lm.Run, rk: *tgp.Rk, row: usize, nn: usize, pred_n: bool, improv_on: bool, ds2x_on: bool) {
    let n = gm.n
    let col = gm.col
    let d = gm.d
    let ss2 = gm.g.s2
    let nug = gm.nug
    let w1 = run.w1
    let w2 = run.w2
    let w3 = run.w3
    let w4 = run.w4
    let ez1 = run.ez1
    if gm.linear {
        gm.g.kd = 1.0f64 + nug
        if pred_n {
            lm.predict_linear(&gm.g, run.f, n, w1, w2, run.dsr, false)
            var q = 0usize
            while q < n {
                run.zpm[row * n + q] = w1[q]
                run.zps[row * n + q] = w2[q]
                q += 1usize
            }
            lm.predict_draw(rk, run.zpz, w1, w2, n)
            q = 0usize
            while q < n {
                run.zpd[row * n + q] = run.zpz[q]
                ez1[q] = w2[q] - ss2
                q += 1usize
            }
            lm.predict_draw(rk, run.zpvm, w1, ez1, n)
            q = 0usize
            while q < n {
                run.zpv[row * n + q] = run.zpvm[q]
                q += 1usize
            }
        }
        if nn > 0usize {
            lm.predict_linear(&gm.g, run.ffm, nn, w3, w4, run.dsr, ds2x_on)
            var q = 0usize
            while q < nn {
                run.zzm[row * nn + q] = w3[q]
                run.zzs[row * nn + q] = w4[q]
                if ds2x_on { run.ds[row * nn + q] = run.dsr[q] / f64(nn) }
                q += 1usize
            }
            lm.predict_draw(rk, run.zzz, w3, w4, nn)
            q = 0usize
            while q < nn {
                run.zzd[row * nn + q] = run.zzz[q]
                ez1[q] = w4[q] - ss2
                q += 1usize
            }
            lm.predict_draw(rk, run.zzvm, w3, ez1, nn)
            q = 0usize
            while q < nn {
                run.zzv[row * nn + q] = run.zzvm[q]
                q += 1usize
            }
            if improv_on {
                if pred_n { data_improv(run.imp, row * nn, nn, run.zpz, n, run.zzz) } else { zz_improv(run.imp, row * nn, nn, w3, w4, run.zlow) }
            }
        }
        ret
    }
    // the GP: KiZmFb = Ki (Z - F bmu)
    let zmfb = run.w1
    var i = 0usize
    while i < n {
        var s = gm.g.z[i]
        var j = 0usize
        while j < col {
            s -= lm.fz(&gm.g, j, i) * gm.g.bmu[j]
            j += 1usize
        }
        zmfb[i] = s
        i += 1usize
    }
    let kz = run.kz
    i = 0usize
    while i < n {
        var s = 0.0f64
        var m = 0usize
        while m < n {
            s += gm.ki[i * n + m] * zmfb[m]
            m += 1usize
        }
        kz[i] = s
        i += 1usize
    }
    if nn > 0usize {
        corr_cross(run.kk, run.xxn, nn, run.xn, n, d, gm.deff)
        if ds2x_on { corr_symm(run.kxx, run.xxn, nn, d, gm.deff, nug) }
        i = 0usize
        while i < nn {
            var mean = 0.0f64
            var j = 0usize
            while j < col {
                mean += run.ffm[j * nn + i] * gm.g.bmu[j]
                j += 1usize
            }
            var kt = 0.0f64
            var m = 0usize
            while m < n {
                kt += run.kk[i * n + m] * kz[m]
                m += 1usize
            }
            run.w3[i] = mean + kt
            // rhs = Ki Q, Q = the correlation row of XX_i
            m = 0usize
            while m < n {
                var s = 0.0f64
                var t = 0usize
                while t < n {
                    s += gm.ki[m * n + t] * run.kk[i * n + t]
                    t += 1usize
                }
                run.rhs[m] = s
                m += 1usize
            }
            var last = 0.0f64
            m = 0usize
            while m < n {
                last += run.kk[i * n + m] * run.rhs[m]
                m += 1usize
            }
            var cdiag = 1.0f64 + nug
            if ds2x_on { cdiag = run.kxx[i * nn + i] + nug }
            var s2cor = cdiag - last
            var s2v = ss2 * s2cor
            if s2v <= 0.0f64 {
                s2v = 0.0f64
                s2cor = cdiag - 1.0f64
            }
            run.w4[i] = s2v
            if ds2x_on {
                var tot = 0.0f64
                var y = 0usize
                while y < nn {
                    var lt = 0.0f64
                    m = 0usize
                    while m < n {
                        lt += run.kk[y * n + m] * run.rhs[m]
                        m += 1usize
                    }
                    let diff = lt - run.kxx[y * nn + i]
                    if s2cor > 0.0f64 { tot += ss2 * diff * diff / s2cor }
                    y += 1usize
                }
                run.dsr[i] = tot
            }
            i += 1usize
        }
        var q = 0usize
        while q < nn {
            run.zzm[row * nn + q] = w3[q]
            run.zzs[row * nn + q] = w4[q]
            if ds2x_on { run.ds[row * nn + q] = run.dsr[q] / f64(nn) }
            q += 1usize
        }
        lm.predict_draw(rk, run.zzz, w3, w4, nn)
        q = 0usize
        while q < nn {
            run.zzd[row * nn + q] = run.zzz[q]
            ez1[q] = w4[q] - ss2 * nug
            q += 1usize
        }
        lm.predict_draw(rk, run.zzvm, w3, ez1, nn)
        q = 0usize
        while q < nn {
            run.zzv[row * nn + q] = run.zzvm[q]
            q += 1usize
        }
    }
    if pred_n {
        i = 0usize
        while i < n {
            var mean = 0.0f64
            var j = 0usize
            while j < col {
                mean += lm.fz(&gm.g, j, i) * gm.g.bmu[j]
                j += 1usize
            }
            var kt = 0.0f64
            var m = 0usize
            while m < n {
                var kv = gm.k[i * n + m]
                if m == i { kv = kv - nug }
                kt += kv * kz[m]
                m += 1usize
            }
            run.w1[i] = mean + kt
            run.w2[i] = nug * ss2
            i += 1usize
        }
        var q = 0usize
        while q < n {
            run.zpm[row * n + q] = run.w1[q]
            run.zps[row * n + q] = run.w2[q]
            q += 1usize
        }
        lm.predict_draw(rk, run.zpz, run.w1, run.w2, n)
        q = 0usize
        while q < n {
            run.zpd[row * n + q] = run.zpz[q]
            ez1[q] = run.w2[q] - ss2 * nug
            q += 1usize
        }
        lm.predict_draw(rk, run.zpvm, run.w1, ez1, n)
        q = 0usize
        while q < n {
            run.zpv[row * n + q] = run.zpvm[q]
            q += 1usize
        }
    }
    if improv_on && nn > 0usize {
        if pred_n { data_improv(run.imp, row * nn, nn, run.zpz, n, run.zzz) } else { zz_improv(run.imp, row * nn, nn, w3, w4, run.zlow) }
    }
}

// bgp (gamma0 = 0) and bgpllm (gamma0 > 0, gamma1, gamma2 the LLM prior): the BTE rounds under set.seed
fn bgp(a: *mem.Arena, r: *rr.Rng, x: []const f64, z0: []const f64, xx: []const f64, n: usize, d: usize, nn: usize, bb: usize, tt: usize, ee: usize, linear_mean: bool, m0r1: bool, pred_n: bool, improv_on: bool, ds2x_on: bool, gam0: f64, gam1: f64, gam2: f64) -> (lm.Blm, err) {
    var out: lm.Blm = zero
    let (run0, es) = lm.setup(a, r, x, z0, xx, n, d, nn, bb, tt, ee, linear_mean, m0r1)
    if es != ok { ret (out, es) }
    var run = run0
    var rk = run.rk
    var gm: Gx = zero
    gm.g = run.g
    gm.n = n
    gm.d = d
    gm.col = run.col
    gm.x = run.xn
    gm.nug = 0.1f64
    var i = 0usize
    while i < d {
        gm.dv[i] = 0.5f64
        gm.bv[i] = 1i64
        gm.deff[i] = 0.5f64
        i += 1usize
    }
    gm.gam0 = gam0
    gm.gam1 = gam1
    gm.gam2 = gam2
    gm.linear = gam0 > 0.0f64
    let (k1, e1) = lm.zeros(a, n * n)
    let (k2, e2) = lm.zeros(a, n * n)
    let (k3, e3) = lm.zeros(a, n * n)
    let (k4, e4) = lm.zeros(a, n * n)
    let (k5, e5) = lm.zeros(a, n * n)
    let (k6, e6) = lm.zeros(a, n * n)
    let (k7, e7) = lm.zeros(a, n * n)
    let (c1, e8) = lm.zeros(a, nn * n)
    let (c2, e9) = lm.zeros(a, nn * nn)
    let (c3, e10) = lm.zeros(a, n)
    let (c4, e11) = lm.zeros(a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret (out, BadChain) }
    gm.k = k1
    gm.ki = k2
    gm.kc = k3
    gm.kn = k4
    gm.kin = k5
    gm.kcn = k6
    gm.w = k7
    run.kk = c1
    run.kxx = c2
    run.rhs = c3
    run.kz = c4
    // Gp::Update: K, its inverse and determinant unless the LLM is where we start; then Gp::Compute
    if !gm.linear {
        corr_symm(gm.k, gm.x, n, d, gm.deff, gm.nug)
        if chol_inv(gm.k, gm.ki, gm.kc, n, gm.w) { gm.logdet = log_det_chol(gm.kc, n) } else { gm.logdet = ninf() }
    } else {
        gm.logdet = f64(n) * lg(1.0f64 + gm.nug)
    }
    gp_compute(&gm)
    var phase = 0usize
    while phase < 2usize {
        var total = bb
        if phase == 1usize { total = tt - bb }
        var rd = 0usize
        while rd < total {
            if (rd + 1usize) % 4usize == 0usize { let _pick = tgp.runi(&rk) }
            // Gp::Draw: up to five tries at the correlation draw
            var success = 0i64
            var tries = 0usize
            while tries < 5usize {
                success = corr_draw(&gm, &rk)
                if success != 0i64 - 1i64 { tries = 5usize } else { tries += 1usize }
            }
            if success < 0i64 { ret (out, BadChain) }
            lm.draw_s2_beta(&gm.g, &rk, run.tmp)
            lm.s2_prior_draw(&gm.g, &rk)
            gp_compute(&gm)
            if phase == 1usize && rd % ee == 0usize {
                record(&gm, &run, &rk, rd / ee, nn, pred_n, improv_on, ds2x_on)
            }
            rd += 1usize
        }
        phase += 1usize
    }
    let (sm, se) = lm.summarize(a, &run, n, nn, pred_n, improv_on, ds2x_on, m0r1)
    ret (sm, se)
}
