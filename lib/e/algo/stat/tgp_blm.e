// R's tgp::blm: the Bayesian linear model, a treed GP with no tree (tree prior 0), the limiting linear
// model forced on, a nugget fixed at zero and the flat beta prior (bprior = "bflat"). The Markov chain is
// tgp's own: the randomkit Mersenne-Twister seeded from R's sample(0:999, 3), draws in the order of
// Model::rounds / Gp::Draw / Gp_Prior::Draw / Tree::Predict (tree move choice every 4th round, two
// uniforms for the correlation and nugget draws, s2, beta, the s2 hyper-prior, then the predictions at
// the data and at XX), then the posterior summaries of Tgp::GetStats and the Ds2x and improv statistics.
// Only the "bflat" prior, itemps = NULL, R = 1 and d < 16 are covered: the GP and treed forms are in
// later files.

use e.algo.rand.r as rr
use e.algo.stat.tgp as tgp
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.mem

error BadInput

type Gp = struct {
    n: usize, col: usize, f: []f64, z: []f64,
    b: [16]f64, bmu: [16]f64, vb: [256]f64,
    lambda: f64, s2: f64, a0: f64, g0: f64, mean: f64, kd: f64
}

// summaries, each nn (ZZ, ds2x, improv, irank) or n (Zp) long; undone to the data scale like tgp.postprocess
type Blm = struct {
    zz_mean: []f64, zz_q1: []f64, zz_med: []f64, zz_q2: []f64, zz_q: []f64, zz_s2: []f64,
    zz_km: []f64, zz_ks2: []f64, zz_vark: []f64,
    zp_mean: []f64, zp_q1: []f64, zp_med: []f64, zp_q2: []f64, zp_q: []f64, zp_s2: []f64,
    zp_km: []f64, zp_ks2: []f64, zp_vark: []f64,
    ds2x: []f64, improv: []f64, irank: []f64,
    lambda: f64, trace: []f64
}

fn lg(x: f64) -> f64 { ret math.log[f64](x) }

// ---- draws (rand_draws.c) ----

fn rnor_pair(rk: *tgp.Rk) -> (f64, f64) {
    var v1 = 0.0f64
    var v2 = 0.0f64
    var w = 2.0f64
    while w > 1.0f64 {
        v1 = 2.0f64 * tgp.runi(rk) - 1.0f64
        v2 = 2.0f64 * tgp.runi(rk) - 1.0f64
        w = v1 * v1 + v2 * v2
    }
    let e = math.sqrt[f64]((0.0f64 - 2.0f64 * lg(w)) / w)
    ret (v2 * e, v1 * e)
}

fn rnorm_fill(rk: *tgp.Rk, x: []f64, n: usize) {
    var j = 0usize
    while j + 1usize < n {
        let (p, q) = rnor_pair(rk)
        x[j] = p
        x[j + 1usize] = q
        j += 2usize
    }
    if j + 1usize == n {
        let (p, q) = rnor_pair(rk)
        x[n - 1usize] = p + 0.0f64 * q
    }
}

fn rexpo(rk: *tgp.Rk, lambda: f64) -> f64 {
    let u = tgp.runi(rk)
    ret 0.0f64 - (1.0f64 / lambda) * lg(u)
}

fn rgamma1(rk: *tgp.Rk, alpha: f64) -> f64 {
    let e = 2.718281828459045f64
    let u0 = tgp.runi(rk)
    let u1 = tgp.runi(rk)
    if u0 > e / (alpha + e) {
        let r = 0.0f64 - lg((alpha + e) * (1.0f64 - u0) / (alpha * e))
        if u1 > math.pow[f64](r, alpha - 1.0f64) { ret 0.0f64 - 1.0f64 }
        ret r
    }
    let x = (alpha + e) * u0 / e
    let r = math.pow[f64](x, 1.0f64 / alpha)
    if u1 > math.exp[f64](0.0f64 - r) { ret 0.0f64 - 1.0f64 }
    ret r
}

fn rgamma2(rk: *tgp.Rk, alpha: f64) -> f64 {
    let c1 = alpha - 1.0f64
    let c2 = (alpha - 1.0f64 / (6.0f64 * alpha)) / c1
    let c3 = 2.0f64 / c1
    let c4 = c3 + 2.0f64
    let c5 = 1.0f64 / math.sqrt[f64](alpha)
    var u1 = 0.0f64
    var u2 = 0.0f64
    var again = true
    while again {
        u1 = tgp.runi(rk)
        u2 = tgp.runi(rk)
        if alpha > 2.5f64 { u1 = u2 + c5 * (1.0f64 - 1.86f64 * u1) }
        again = u1 >= 1.0f64 || u1 <= 0.0f64
    }
    let w = c2 * u2 / u1
    if (c3 * u1 + w + 1.0f64 / w) > c4 {
        if (c3 * lg(u1) - lg(w) + w) >= 1.0f64 { ret 0.0f64 - 1.0f64 }
    }
    ret c1 * w
}

// rgamma_wb: Gelman parametrisation, mean alpha / beta
fn rgamma_wb(rk: *tgp.Rk, alpha: f64, beta: f64) -> f64 {
    var random = 0.0f64
    if alpha < 1.0f64 {
        var again = true
        while again {
            random = rgamma1(rk, alpha) / beta
            again = random < 0.0f64
        }
    }
    if alpha == 1.0f64 { random = rexpo(rk, 1.0f64) / beta }
    if alpha > 1.0f64 {
        var again = true
        while again {
            random = rgamma2(rk, alpha) / beta
            again = random < 0.0f64
        }
    }
    ret random
}

// unif_propose_pos: (draw, q_fwd, q_bak)
fn unif_propose_pos(rk: *tgp.Rk, last: f64) -> (f64, f64, f64) {
    let left = 3.0f64 * last / 4.0f64
    let right = 4.0f64 * last / 3.0f64
    var ret_v = tgp.runi(rk) * (right - left) + left
    let qf = 1.0f64 / (right - left)
    let left2 = 3.0f64 * ret_v / 4.0f64
    let right2 = 4.0f64 * ret_v / 3.0f64
    let qb = 1.0f64 / (right2 - left2)
    if ret_v > 100000000000.0f64 { ret_v = 10.0f64 }
    ret (ret_v, qf, qb)
}

// ---- the leaf model (gp.cc, all_draws.c for flat beta prior, K = I) ----

fn fz(g: *Gp, j: usize, i: usize) -> f64 { ret g.f[j * g.n + i] }

// inverse of the col x col matrix a (row stride 16) by Gauss-Jordan with partial pivoting
fn invert_small(a0: [256]f64, col: usize) -> [256]f64 {
    var m: [512]f64 = zero
    var i = 0usize
    while i < col {
        var j = 0usize
        while j < col {
            m[i * 32usize + j] = a0[i * 16usize + j]
            j += 1usize
        }
        m[i * 32usize + 16usize + i] = 1.0f64
        i += 1usize
    }
    var c = 0usize
    while c < col {
        var p = c
        var best = math.abs[f64](m[c * 32usize + c])
        var r = c + 1usize
        while r < col {
            let v = math.abs[f64](m[r * 32usize + c])
            if v > best {
                best = v
                p = r
            }
            r += 1usize
        }
        if p != c {
            var q = 0usize
            while q < 32usize {
                let t = m[c * 32usize + q]
                m[c * 32usize + q] = m[p * 32usize + q]
                m[p * 32usize + q] = t
                q += 1usize
            }
        }
        let piv = m[c * 32usize + c]
        var q2 = 0usize
        while q2 < 32usize {
            m[c * 32usize + q2] = m[c * 32usize + q2] / piv
            q2 += 1usize
        }
        var r2 = 0usize
        while r2 < col {
            if r2 != c {
                let fac = m[r2 * 32usize + c]
                var q3 = 0usize
                while q3 < 32usize {
                    m[r2 * 32usize + q3] = m[r2 * 32usize + q3] - fac * m[c * 32usize + q3]
                    q3 += 1usize
                }
            }
            r2 += 1usize
        }
        c += 1usize
    }
    var out: [256]f64 = zero
    i = 0usize
    while i < col {
        var j = 0usize
        while j < col {
            out[i * 16usize + j] = m[i * 32usize + 16usize + j]
            j += 1usize
        }
        i += 1usize
    }
    ret out
}

// Gp::Compute with Ti = 0, tau2 = 1, itemp = 1, Kdiag = 1: vb = inv(F F'), bmu = vb F Z, lambda = Z Z - bmu . F Z
fn compute(g: *Gp) {
    let col = g.col
    let n = g.n
    var m: [512]f64 = zero
    var by: [16]f64 = zero
    var i = 0usize
    while i < col {
        var j = 0usize
        while j < col {
            var s = 0.0f64
            var k = 0usize
            while k < n {
                s += fz(g, i, k) / g.kd * fz(g, j, k)
                k += 1usize
            }
            m[i * 32usize + j] = s
            m[i * 32usize + 16usize + j] = 0.0f64
            j += 1usize
        }
        m[i * 32usize + 16usize + i] = 1.0f64
        var s2 = 0.0f64
        var k2 = 0usize
        while k2 < n {
            s2 += fz(g, i, k2) / g.kd * g.z[k2]
            k2 += 1usize
        }
        by[i] = s2
        i += 1usize
    }
    // Gauss-Jordan with partial pivoting: [A | I] -> [I | inv(A)]
    var c = 0usize
    while c < col {
        var p = c
        var best = math.abs[f64](m[c * 32usize + c])
        var r = c + 1usize
        while r < col {
            let v = math.abs[f64](m[r * 32usize + c])
            if v > best {
                best = v
                p = r
            }
            r += 1usize
        }
        if p != c {
            var q = 0usize
            while q < 32usize {
                let t = m[c * 32usize + q]
                m[c * 32usize + q] = m[p * 32usize + q]
                m[p * 32usize + q] = t
                q += 1usize
            }
        }
        let piv = m[c * 32usize + c]
        var q2 = 0usize
        while q2 < 32usize {
            m[c * 32usize + q2] = m[c * 32usize + q2] / piv
            q2 += 1usize
        }
        var r2 = 0usize
        while r2 < col {
            if r2 != c {
                let fac = m[r2 * 32usize + c]
                var q3 = 0usize
                while q3 < 32usize {
                    m[r2 * 32usize + q3] = m[r2 * 32usize + q3] - fac * m[c * 32usize + q3]
                    q3 += 1usize
                }
            }
            r2 += 1usize
        }
        c += 1usize
    }
    i = 0usize
    while i < col {
        var j = 0usize
        while j < col {
            g.vb[i * 16usize + j] = m[i * 32usize + 16usize + j]
            j += 1usize
        }
        i += 1usize
    }
    var zz = 0.0f64
    var k3 = 0usize
    while k3 < n {
        zz += g.z[k3] / g.kd * g.z[k3]
        k3 += 1usize
    }
    var bvb = 0.0f64
    i = 0usize
    while i < col {
        var s3 = 0.0f64
        var j = 0usize
        while j < col {
            s3 += g.vb[i * 16usize + j] * by[j]
            j += 1usize
        }
        g.bmu[i] = s3
        bvb += s3 * by[i]
        i += 1usize
    }
    g.lambda = zz - bvb
}

// Gp::Draw for the leaf: Corr::Draw (two uniforms under the forced LLM and a fixed nugget), sigma2_draw_no_b_margin
// (flat beta prior takes col off the prior a0), beta_draw_margin
fn gp_draw(g: *Gp, rk: *tgp.Rk, tmp: []f64) {
    let _u1 = tgp.runi(rk)
    let _u2 = tgp.runi(rk)
    draw_s2_beta(g, rk, tmp)
}

// the s2 and beta draws of Gp::Draw, after the correlation draws
fn draw_s2_beta(g: *Gp, rk: *tgp.Rk, tmp: []f64) {
    let col = g.col
    var lam = g.lambda
    if lam < 0.0f64 { lam = 0.0f64 }
    let alpha = (g.a0 - f64(col) + f64(g.n)) / 2.0f64
    let gg = (g.g0 + lam) / 2.0f64
    g.s2 = 1.0f64 / rgamma_wb(rk, alpha, gg)
    // beta_draw_margin: V = s2 Vb, lower Cholesky, b = bmu + L z
    var l: [256]f64 = zero
    var info = 0usize
    if col > 1usize {
        var i = 0usize
        while i < col && info == 0usize {
            var j = 0usize
            while j <= i {
                var s = g.s2 * g.vb[i * 16usize + j]
                var k = 0usize
                while k < j {
                    s -= l[i * 16usize + k] * l[j * 16usize + k]
                    k += 1usize
                }
                if i == j {
                    if s > 0.0f64 { l[i * 16usize + i] = math.sqrt[f64](s) } else { info = 1usize }
                } else {
                    l[i * 16usize + j] = s / l[j * 16usize + j]
                }
                j += 1usize
            }
            i += 1usize
        }
    }
    if info != 0usize {
        var i = 0usize
        while i < col {
            g.b[i] = 0.0f64
            i += 1usize
        }
        g.b[0usize] = g.mean
    } else {
        rnorm_fill(rk, tmp, col)
        if col > 1usize {
            var j = 0usize
            while j < col {
                var s = 0.0f64
                var i = 0usize
                while i <= j {
                    s += l[j * 16usize + i] * tmp[i]
                    i += 1usize
                }
                g.b[j] = s + g.bmu[j]
                j += 1usize
            }
        } else {
            g.b[0usize] = tmp[0usize] * math.sqrt[f64](g.s2 * g.vb[0usize]) + g.bmu[0usize]
        }
    }
}

fn invgam_lp(x: f64, a: f64, b: f64) -> f64 {
    ret a * lg(b) - nm.lgammafn(a) - (a + 1.0f64) * lg(x) - b / x
}

fn gam_lp(x: f64, a: f64, b: f64) -> f64 {
    ret a * lg(b) - nm.lgammafn(a) + (a - 1.0f64) * lg(x) - b * x
}

// sigma2_prior_draw with the default hyper-prior lambdas (0.2, 10)
fn s2_prior_draw(g: *Gp, rk: *tgp.Rk) {
    let (r1, qf, qb) = unif_propose_pos(rk, g.a0 - 2.0f64)
    let a0n = 2.0f64 + r1
    var lp = 0.0f64
    lp += invgam_lp(g.s2, a0n / 2.0f64, g.g0 / 2.0f64)
    lp -= invgam_lp(g.s2, g.a0 / 2.0f64, g.g0 / 2.0f64)
    lp += gam_lp(a0n, 1.0f64, 0.2f64)
    lp -= gam_lp(g.a0, 1.0f64, 0.2f64)
    let al = math.exp[f64](lp) * qb / qf
    if tgp.runi(rk) < al { g.a0 = a0n }
    let (r2, qf2, qb2) = unif_propose_pos(rk, g.g0 - 0.0000000001f64)
    let g0n = r2 + 0.0000000001f64
    var lp2 = 0.0f64
    lp2 += invgam_lp(g.s2, g.a0 / 2.0f64, g0n / 2.0f64)
    lp2 -= invgam_lp(g.s2, g.a0 / 2.0f64, g.g0 / 2.0f64)
    lp2 += gam_lp(g0n, 1.0f64, 10.0f64)
    lp2 -= gam_lp(g.g0, 1.0f64, 10.0f64)
    let al2 = math.exp[f64](lp2) * qb2 / qf2
    if tgp.runi(rk) < al2 { g.g0 = g0n }
}

// predict_linear: mean F' bmu, variance s2 (1 + f Vb f); Ds2xy rows (sum over columns) into ds if not empty
fn predict_linear(g: *Gp, ff: []const f64, m: usize, zm: []f64, zs2: []f64, ds: []f64, want_ds: bool) {
    let col = g.col
    var i = 0usize
    while i < m {
        var f: [16]f64 = zero
        var vbf: [16]f64 = zero
        var j = 0usize
        var s = 0.0f64
        while j < col {
            f[j] = ff[j * m + i]
            s += f[j] * g.bmu[j]
            j += 1usize
        }
        zm[i] = s
        j = 0usize
        while j < col {
            var t = 0.0f64
            var k = 0usize
            while k < col {
                t += g.vb[j * 16usize + k] * f[k]
                k += 1usize
            }
            vbf[j] = t
            j += 1usize
        }
        var fvbf = 0.0f64
        j = 0usize
        while j < col {
            fvbf += vbf[j] * f[j]
            j += 1usize
        }
        if want_ds {
            var tot = 0.0f64
            var y = 0usize
            while y < m {
                var fyv = 0.0f64
                var q = 0usize
                while q < col {
                    fyv += vbf[q] * ff[q * m + y]
                    q += 1usize
                }
                tot += g.s2 * fyv * fyv / (g.kd + fvbf)
                y += 1usize
            }
            ds[i] = tot
        }
        zs2[i] = g.s2 * (g.kd + fvbf)
        i += 1usize
    }
}

// predict_draw with err = TRUE: z = N(mean, s2)
fn predict_draw(rk: *tgp.Rk, z: []f64, mean: []const f64, s2: []const f64, m: usize) {
    rnorm_fill(rk, z, m)
    var i = 0usize
    while i < m {
        if s2[i] == 0.0f64 { z[i] = mean[i] } else { z[i] = z[i] * math.sqrt[f64](s2[i]) + mean[i] }
        i += 1usize
    }
}

fn zeros(a: *mem.Arena, n: usize) -> ([]f64, err) {
    let (s, e) = mem.alloc[f64](a, n + 1usize)
    if e != ok { ret (s, e) }
    var i = 0usize
    while i < n + 1usize {
        s[i] = 0.0f64
        i += 1usize
    }
    ret (s, ok)
}

fn sort_into(v: []f64, n: usize) {
    var i = 1usize
    while i < n {
        let x = v[i]
        var j = i
        while j > 0usize && v[j - 1usize] > x {
            v[j] = v[j - 1usize]
            j -= 1usize
        }
        v[j] = x
        i += 1usize
    }
}

// column statistics of an rr x nc matrix (row-major draws): mean, and the (0.05, 0.5, 0.95) order
// statistics floor(rr q) of quantiles(): rank k of the sorted column
fn col_mean(m: []const f64, nrows: usize, nc: usize, out: []f64) {
    var i = 0usize
    while i < nc {
        var s = 0.0f64
        var j = 0usize
        while j < nrows {
            s += m[j * nc + i]
            j += 1usize
        }
        out[i] = s / f64(nrows)
        i += 1usize
    }
}

fn col_var(m: []const f64, nrows: usize, nc: usize, out: []f64) {
    var i = 0usize
    while i < nc {
        var s = 0.0f64
        var j = 0usize
        while j < nrows {
            s += m[j * nc + i]
            j += 1usize
        }
        let mu = s / f64(nrows)
        var v = 0.0f64
        j = 0usize
        while j < nrows {
            v += (m[j * nc + i] - mu) * (m[j * nc + i] - mu)
            j += 1usize
        }
        out[i] = v / f64(nrows)
        i += 1usize
    }
}

fn col_sq_mean(m: []const f64, nrows: usize, nc: usize, mean: []const f64, out: []f64) {
    var i = 0usize
    while i < nc {
        var s = 0.0f64
        var j = 0usize
        while j < nrows {
            s += m[j * nc + i] * m[j * nc + i]
            j += 1usize
        }
        out[i] = s / f64(nrows) - mean[i] * mean[i]
        i += 1usize
    }
}

fn col_quant(a: *mem.Arena, m: []const f64, nrows: usize, nc: usize, q1: []f64, med: []f64, q2: []f64) -> err {
    let (col, e) = zeros(a, nrows)
    if e != ok { ret e }
    var i = 0usize
    while i < nc {
        var j = 0usize
        while j < nrows {
            col[j] = m[j * nc + i]
            j += 1usize
        }
        sort_into(col, nrows)
        q1[i] = col[usize(math.floor[f64](f64(nrows) * 0.05f64))]
        med[i] = col[usize(math.floor[f64](f64(nrows) * 0.5f64))]
        q2[i] = col[usize(math.floor[f64](f64(nrows) * 0.95f64))]
        i += 1usize
    }
    ret ok
}

// GetImprovRank with g = 1, numirank = nn, no weights: pntind (0 where unranked)
fn improv_rank(a: *mem.Arena, im: []const f64, nrows: usize, nn: usize, numirank: usize, out: []f64) -> err {
    let (mat, e) = zeros(a, nrows * nn)
    if e != ok { ret e }
    let (cm, e2) = zeros(a, nn)
    if e2 != ok { ret e2 }
    let (mc, e3) = zeros(a, nrows)
    if e3 != ok { ret e3 }
    var i = 0usize
    while i < nrows * nn {
        mat[i] = im[i]
        i += 1usize
    }
    i = 0usize
    while i < nn {
        out[i] = 0.0f64
        i += 1usize
    }
    if numirank == 0usize { ret ok }
    col_mean(mat, nrows, nn, cm)
    var maxj = 0usize
    var j = 1usize
    while j < nn {
        if cm[j] > cm[maxj] { maxj = j }
        j += 1usize
    }
    out[maxj] = 1.0f64
    i = 0usize
    while i < nrows {
        mc[i] = mat[i * nn + maxj]
        i += 1usize
    }
    var k = 1usize
    var stop = false
    while k < numirank && !stop {
        j = 0usize
        while j < nn {
            i = 0usize
            while i < nrows {
                var v = mat[i * nn + j]
                if mc[i] > v { v = mc[i] }
                mat[i * nn + j] = v
                i += 1usize
            }
            j += 1usize
        }
        col_mean(mat, nrows, nn, cm)
        maxj = 0usize
        j = 1usize
        while j < nn {
            if cm[j] > cm[maxj] { maxj = j }
            j += 1usize
        }
        if out[maxj] != 0.0f64 {
            stop = true
        } else {
            out[maxj] = f64(k + 1usize)
            i = 0usize
            while i < nrows {
                mc[i] = mat[i * nn + maxj]
                i += 1usize
            }
        }
        k += 1usize
    }
    ret ok
}

// normalised copy of the n x d matrix x by rect (lo, hi per dimension), NORMSCALE = 1
fn normalise(a: *mem.Arena, x: []const f64, n: usize, d: usize, lo: []const f64, hi: []const f64) -> ([]f64, err) {
    let (out, e) = zeros(a, n * d)
    if e != ok { ret (out, e) }
    var i = 0usize
    while i < d {
        var norm = math.abs[f64](hi[i] - lo[i])
        if norm == 0.0f64 { norm = math.abs[f64](lo[i]) }
        var j = 0usize
        while j < n {
            if lo[i] < 0.0f64 {
                out[j * d + i] = (x[j * d + i] + math.abs[f64](lo[i])) / norm
            } else {
                out[j * d + i] = (x[j * d + i] - lo[i]) / norm
            }
            j += 1usize
        }
        i += 1usize
    }
    ret (out, ok)
}

fn design_f(a: *mem.Arena, x: []const f64, m: usize, d: usize, col: usize) -> ([]f64, err) {
    let (f, e) = zeros(a, col * m)
    if e != ok { ret (f, e) }
    var i = 0usize
    while i < m {
        f[i] = 1.0f64
        var j = 1usize
        while j < col {
            f[j * m + i] = x[i * d + (j - 1usize)]
            j += 1usize
        }
        i += 1usize
    }
    ret (f, ok)
}

// undo.mean0.range1 on a vector: add amean unless nomean, then scale by range (squared for variances)
fn undo(v: []f64, m: usize, amean: f64, range: f64, nomean: bool, sq: bool) {
    var i = 0usize
    while i < m {
        var x = v[i]
        if !nomean { x += amean }
        if sq { x = x * range * range } else { x = x * range }
        v[i] = x
        i += 1usize
    }
}

// blm(X, Z, XX, BTE = c(b, t, e), meanfn, m0r1, pred.n, Ds2x, improv) under set.seed: x is n x d, xx is nn x d,
// both row-major; the state is sample(seq(0, 999), 3) of the R generator r
type Run = struct {
    rk: tgp.Rk, g: Gp, col: usize, kept: usize, f: []f64, ffm: []f64,
    zlow: f64, amean: f64, range: f64,
    zzd: []f64, zzm: []f64, zzv: []f64, zzs: []f64, zpd: []f64, zpm: []f64, zpv: []f64, zps: []f64,
    trc: []f64, ds: []f64, imp: []f64, tmp: []f64,
    w1: []f64, w2: []f64, w3: []f64, w4: []f64, dsr: []f64, ez1: []f64,
    zpz: []f64, zzz: []f64, zpvm: []f64, zzvm: []f64,
    xn: []f64, xxn: []f64, kk: []f64, kxx: []f64, rhs: []f64, kz: []f64
}

// the common set-up of blm and bgp: seed the generator from R's sample(0:999, 3), take the three uniforms of
// Model::Model, normalise Z (m0r1) and X, build F and FF, allocate the kept draws
fn setup(a: *mem.Arena, r: *rr.Rng, x: []const f64, z0: []const f64, xx: []const f64, n: usize, d: usize, nn: usize, bb: usize, tt: usize, ee: usize, linear_mean: bool, m0r1: bool) -> (Run, err) {
    var out: Run = zero
    if d > 15usize || n < 2usize || ee == 0usize || tt <= bb || (tt - bb) % ee != 0usize { ret (out, BadInput) }
    let (idx, e0) = rr.sample_int(a, r, 1000i64, 3i64, false)
    if e0 != ok { ret (out, e0) }
    var rk = tgp.rk_state(idx[0usize] - 1i64, idx[1usize] - 1i64, idx[2usize] - 1i64)
    // Model::Model: newRNGstate_rand draws three uniforms for the prediction consumer's state
    let _c1 = tgp.runi(&rk)
    let _c2 = tgp.runi(&rk)
    let _c3 = tgp.runi(&rk)
    var col = 1usize
    if linear_mean { col = d + 1usize }
    // Z on mean 0, range 1
    let (z, ez) = zeros(a, n)
    if ez != ok { ret (out, ez) }
    var zmin = z0[0usize]
    var zmax = z0[0usize]
    var i = 0usize
    while i < n {
        if z0[i] < zmin { zmin = z0[i] }
        if z0[i] > zmax { zmax = z0[i] }
        i += 1usize
    }
    let range = zmax - zmin
    var amean = 0.0f64
    i = 0usize
    while i < n {
        z[i] = z0[i]
        if m0r1 { z[i] = z0[i] / range }
        i += 1usize
    }
    if m0r1 {
        var s = 0.0f64
        i = 0usize
        while i < n {
            s += z[i]
            i += 1usize
        }
        amean = s / f64(n)
        i = 0usize
        while i < n {
            z[i] = z[i] - amean
            i += 1usize
        }
    }
    // rectangle of rbind(X, XX)
    let (lo, e1) = zeros(a, d)
    let (hi, e2) = zeros(a, d)
    if e1 != ok || e2 != ok { ret (out, BadInput) }
    var j = 0usize
    while j < d {
        lo[j] = x[j]
        hi[j] = x[j]
        i = 0usize
        while i < n + nn {
            var v = 0.0f64
            if i < n { v = x[i * d + j] } else { v = xx[(i - n) * d + j] }
            if v < lo[j] {
                lo[j] = v
            } else {
                if v > hi[j] { hi[j] = v }
            }
            i += 1usize
        }
        j += 1usize
    }
    let (xn, e3) = normalise(a, x, n, d, lo, hi)
    if e3 != ok { ret (out, e3) }
    let (xxn, e4) = normalise(a, xx, nn, d, lo, hi)
    if e4 != ok { ret (out, e4) }
    let (f, e5) = design_f(a, xn, n, d, col)
    if e5 != ok { ret (out, e5) }
    let (ffm, e6) = design_f(a, xxn, nn, d, col)
    if e6 != ok { ret (out, e6) }
    // the single leaf
    var g: Gp = zero
    g.n = n
    g.col = col
    g.f = f
    g.z = z
    g.s2 = 1.0f64
    g.kd = 1.0f64
    g.a0 = 5.0f64
    g.g0 = 10.0f64
    var zsum = 0.0f64
    var zlow = z[0usize]
    i = 0usize
    while i < n {
        zsum += z[i]
        if z[i] < zlow { zlow = z[i] }
        i += 1usize
    }
    g.mean = zsum / f64(n)
    compute(&g)
    // predictions kept every ee-th round after the burn-in
    let kept = (tt - bb) / ee
    let (zzd, f1) = zeros(a, kept * nn)
    let (zzm, f2) = zeros(a, kept * nn)
    let (zzv, f3) = zeros(a, kept * nn)
    let (zzs, f4) = zeros(a, kept * nn)
    let (zpd, f5) = zeros(a, kept * n)
    let (zpm, f6) = zeros(a, kept * n)
    let (zpv, f7) = zeros(a, kept * n)
    let (zps, f8) = zeros(a, kept * n)
    let (trc, f22) = zeros(a, kept * (col + 3usize))
    let (ds, f9) = zeros(a, kept * nn)
    let (imp, f10) = zeros(a, kept * nn)
    if f1 != ok || f2 != ok || f3 != ok || f4 != ok || f5 != ok || f6 != ok || f7 != ok || f8 != ok || f9 != ok || f10 != ok || f22 != ok { ret (out, BadInput) }
    let (tmp, f11) = zeros(a, 16usize)
    let (w1, f12) = zeros(a, n + nn)
    let (w2, f13) = zeros(a, n + nn)
    let (w3, f14) = zeros(a, n + nn)
    let (w4, f15) = zeros(a, n + nn)
    let (dsr, fx16) = zeros(a, nn)
    let (ez1, f17) = zeros(a, n + nn)
    let (zpz, f18) = zeros(a, n)
    let (zzz, f19) = zeros(a, nn)
    let (zpvm, f20) = zeros(a, n)
    let (zzvm, f21) = zeros(a, nn)
    if f11 != ok || f12 != ok || f13 != ok || f14 != ok || f15 != ok || fx16 != ok || f17 != ok || f18 != ok || f19 != ok || f20 != ok || f21 != ok { ret (out, BadInput) }
    out.rk = rk
    out.g = g
    out.col = col
    out.kept = kept
    out.f = f
    out.ffm = ffm
    out.zlow = zlow
    out.amean = amean
    out.range = range
    out.zzd = zzd
    out.zzm = zzm
    out.zzv = zzv
    out.zzs = zzs
    out.zpd = zpd
    out.zpm = zpm
    out.zpv = zpv
    out.zps = zps
    out.trc = trc
    out.ds = ds
    out.imp = imp
    out.tmp = tmp
    out.w1 = w1
    out.w2 = w2
    out.w3 = w3
    out.w4 = w4
    out.dsr = dsr
    out.ez1 = ez1
    out.zpz = zpz
    out.zzz = zzz
    out.zpvm = zpvm
    out.zzvm = zzvm
    out.xn = xn
    out.xxn = xxn
    ret (out, ok)
}

fn blm(a: *mem.Arena, r: *rr.Rng, x: []const f64, z0: []const f64, xx: []const f64, n: usize, d: usize, nn: usize, bb: usize, tt: usize, ee: usize, linear_mean: bool, m0r1: bool, pred_n: bool, improv_on: bool, ds2x_on: bool) -> (Blm, err) {
    var out: Blm = zero
    let (run0, es) = setup(a, r, x, z0, xx, n, d, nn, bb, tt, ee, linear_mean, m0r1)
    if es != ok { ret (out, es) }
    var run = run0
    var rk = run.rk
    var g = run.g
    let col = run.col
    let kept = run.kept
    let f = run.f
    let ffm = run.ffm
    let zlow = run.zlow
    let trc = run.trc
    let ds = run.ds
    let imp = run.imp
    let zzd = run.zzd
    let zzm = run.zzm
    let zzv = run.zzv
    let zzs = run.zzs
    let zpd = run.zpd
    let zpm = run.zpm
    let zpv = run.zpv
    let zps = run.zps
    let tmp = run.tmp
    let w1 = run.w1
    let w2 = run.w2
    let w3 = run.w3
    let w4 = run.w4
    let dsr = run.dsr
    let ez1 = run.ez1
    let zpz = run.zpz
    let zzz = run.zzz
    let zpvm = run.zpvm
    let zzvm = run.zzvm
    // the rounds: burn-in rounds 0 .. bb - 1 (no predictions), then rounds 0 .. tt - bb - 1 with predictions
    var phase = 0usize
    while phase < 2usize {
        var total = bb
        if phase == 1usize { total = tt - bb }
        var rd = 0usize
        while rd < total {
            if (rd + 1usize) % 4usize == 0usize { let _pick = tgp.runi(&rk) }
            gp_draw(&g, &rk, tmp)
            s2_prior_draw(&g, &rk)
            compute(&g)
            if phase == 1usize && rd % ee == 0usize {
                let row = rd / ee
                trc[row * (col + 3usize)] = g.s2
                var tq = 0usize
                while tq < col {
                    trc[row * (col + 3usize) + 1usize + tq] = g.b[tq]
                    tq += 1usize
                }
                trc[row * (col + 3usize) + 1usize + col] = g.a0
                trc[row * (col + 3usize) + 2usize + col] = g.g0
                if pred_n {
                    predict_linear(&g, f, n, w1, w2, dsr, false)
                    var q = 0usize
                    while q < n {
                        zpm[row * n + q] = w1[q]
                        zps[row * n + q] = w2[q]
                        q += 1usize
                    }
                    predict_draw(&rk, zpz, w1, w2, n)
                    q = 0usize
                    while q < n {
                        zpd[row * n + q] = zpz[q]
                        ez1[q] = w2[q] - g.s2
                        q += 1usize
                    }
                    predict_draw(&rk, zpvm, w1, ez1, n)
                    q = 0usize
                    while q < n {
                        zpv[row * n + q] = zpvm[q]
                        q += 1usize
                    }
                }
                if nn > 0usize {
                    predict_linear(&g, ffm, nn, w3, w4, dsr, ds2x_on)
                    var q = 0usize
                    while q < nn {
                        zzm[row * nn + q] = w3[q]
                        zzs[row * nn + q] = w4[q]
                        if ds2x_on { ds[row * nn + q] = dsr[q] / f64(nn) }
                        q += 1usize
                    }
                    predict_draw(&rk, zzz, w3, w4, nn)
                    q = 0usize
                    while q < nn {
                        zzd[row * nn + q] = zzz[q]
                        ez1[q] = w4[q] - g.s2
                        q += 1usize
                    }
                    predict_draw(&rk, zzvm, w3, ez1, nn)
                    q = 0usize
                    while q < nn {
                        zzv[row * nn + q] = zzvm[q]
                        q += 1usize
                    }
                    if improv_on {
                        q = 0usize
                        if pred_n {
                            // predicted_improv: fmin = min(zp, Zmin), Zmin = Inf for the leaf holding the minimum
                            var fmin = zpz[0usize]
                            var p = 1usize
                            while p < n {
                                if zpz[p] < fmin { fmin = zpz[p] }
                                p += 1usize
                            }
                            while q < nn {
                                let df = fmin - zzz[q]
                                if df > 0.0f64 { imp[row * nn + q] = df } else { imp[row * nn + q] = 0.0f64 }
                                q += 1usize
                            }
                        } else {
                            while q < nn {
                                let zs = math.sqrt[f64](w4[q])
                                let df = zlow - w3[q]
                                let st = df / zs
                                let dl = 0.0f64 - 0.91893853320467274f64 - 0.5f64 * (st * st)
                                let dd = math.exp[f64](dl)
                                let pp = dist.pnorm(st, 0.0f64, 1.0f64, true, false)
                                var iv = df * pp + zs * dd
                                if iv < 0.0f64 { iv = 0.0f64 }
                                imp[row * nn + q] = iv
                                q += 1usize
                            }
                        }
                    }
                }
            }
            rd += 1usize
        }
        phase += 1usize
    }
    let (sm, se) = summarize(a, &run, n, nn, pred_n, improv_on, ds2x_on, m0r1)
    ret (sm, se)
}

// Tgp::GetStats over the kept draws, then undo.mean0.range1 as tgp.postprocess does
fn summarize(a: *mem.Arena, run: *Run, n: usize, nn: usize, pred_n: bool, improv_on: bool, ds2x_on: bool, m0r1: bool) -> (Blm, err) {
    var out: Blm = zero
    let kept = run.kept
    let amean = run.amean
    let range = run.range
    let zpd = run.zpd
    let zpm = run.zpm
    let zpv = run.zpv
    let zps = run.zps
    let zzd = run.zzd
    let zzm = run.zzm
    let zzv = run.zzv
    let zzs = run.zzs
    let ds = run.ds
    let imp = run.imp
    var i = 0usize
    let (m1, g1) = zeros(a, n)
    let (m2, g2) = zeros(a, n)
    let (m3, g3) = zeros(a, n)
    let (m4, g4) = zeros(a, n)
    let (m5, g5) = zeros(a, n)
    let (m6, g6) = zeros(a, n)
    let (m7, g7) = zeros(a, n)
    let (m8, g8) = zeros(a, n)
    let (m9, g9) = zeros(a, n)
    let (k1, h1) = zeros(a, nn)
    let (k2, h2) = zeros(a, nn)
    let (k3, h3) = zeros(a, nn)
    let (k4, h4) = zeros(a, nn)
    let (k5, h5) = zeros(a, nn)
    let (k6, h6) = zeros(a, nn)
    let (k7, h7) = zeros(a, nn)
    let (k8, h8) = zeros(a, nn)
    let (k9, h9) = zeros(a, nn)
    let (dsm, h10) = zeros(a, nn)
    let (imm, h11) = zeros(a, nn)
    let (irk, h12) = zeros(a, nn)
    if g1 != ok || g2 != ok || g3 != ok || g4 != ok || g5 != ok || g6 != ok || g7 != ok || g8 != ok || g9 != ok { ret (out, BadInput) }
    if h1 != ok || h2 != ok || h3 != ok || h4 != ok || h5 != ok || h6 != ok || h7 != ok || h8 != ok || h9 != ok || h10 != ok || h11 != ok || h12 != ok { ret (out, BadInput) }
    if pred_n {
        col_mean(zpd, kept, n, m1)
        col_mean(zpm, kept, n, m2)
        col_var(zpv, kept, n, m3)
        col_sq_mean(zpd, kept, n, m1, m4)
        col_mean(zps, kept, n, m5)
        let eq = col_quant(a, zpd, kept, n, m6, m7, m8)
        if eq != ok { ret (out, eq) }
        i = 0usize
        while i < n {
            m9[i] = m8[i] - m6[i]
            i += 1usize
        }
    }
    if nn > 0usize {
        col_mean(zzd, kept, nn, k1)
        col_mean(zzm, kept, nn, k2)
        col_var(zzv, kept, nn, k3)
        col_sq_mean(zzd, kept, nn, k1, k4)
        col_mean(zzs, kept, nn, k5)
        let eq2 = col_quant(a, zzd, kept, nn, k6, k7, k8)
        if eq2 != ok { ret (out, eq2) }
        i = 0usize
        while i < nn {
            k9[i] = k8[i] - k6[i]
            i += 1usize
        }
        if ds2x_on { col_mean(ds, kept, nn, dsm) }
        if improv_on {
            col_mean(imp, kept, nn, imm)
            let er = improv_rank(a, imp, kept, nn, nn, irk)
            if er != ok { ret (out, er) }
            i = 0usize
            while i < nn {
                if irk[i] == 0.0f64 { irk[i] = f64(nn) }
                i += 1usize
            }
        }
    }
    if m0r1 {
        undo(m1, n, amean, range, false, false)
        undo(m2, n, amean, range, false, false)
        undo(m3, n, amean, range, true, true)
        undo(m4, n, amean, range, true, true)
        undo(m5, n, amean, range, true, true)
        undo(m6, n, amean, range, false, false)
        undo(m7, n, amean, range, false, false)
        undo(m8, n, amean, range, false, false)
        undo(m9, n, amean, range, true, false)
        undo(k1, nn, amean, range, false, false)
        undo(k2, nn, amean, range, false, false)
        undo(k3, nn, amean, range, true, true)
        undo(k4, nn, amean, range, true, true)
        undo(k5, nn, amean, range, true, true)
        undo(k6, nn, amean, range, false, false)
        undo(k7, nn, amean, range, false, false)
        undo(k8, nn, amean, range, false, false)
        undo(k9, nn, amean, range, true, false)
    }
    out.zp_mean = m1
    out.zp_km = m2
    out.zp_vark = m3
    out.zp_s2 = m4
    out.zp_ks2 = m5
    out.zp_q1 = m6
    out.zp_med = m7
    out.zp_q2 = m8
    out.zp_q = m9
    out.zz_mean = k1
    out.zz_km = k2
    out.zz_vark = k3
    out.zz_s2 = k4
    out.zz_ks2 = k5
    out.zz_q1 = k6
    out.zz_med = k7
    out.zz_q2 = k8
    out.zz_q = k9
    out.ds2x = dsm
    out.improv = imm
    out.irank = irk
    out.lambda = run.g.lambda
    out.trace = run.trc
    ret (out, ok)
}
