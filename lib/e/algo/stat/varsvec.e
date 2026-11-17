// R vars on a cointegrated system (urca::ca.jo): vec2var, which restates the VECM as a VAR in levels, with its impulse responses (and bootstrap bands, which
// re-run the Johansen procedure on every resampled series), forecast error variance decomposition, forecasts and residual tests, and SVEC, the structural
// VECM with short- and long-run restrictions estimated by scoring.
//
// A Vecm holds the Johansen data matrices Z0, Z1 and ZK of ca.jo and its V and W (from e.algo.stat.johansen). A Vec2 holds the VAR in levels as a
// e.algo.stat.vars2.Var whose coefficient columns are the k p lag columns then the deterministic columns (constant, trend, seasonal dummies).
//
// Not here: ca.jo's dumvar (exogenous dummies, which e.algo.stat.johansen leaves out too), SVEC's bootstrap standard errors (boot = TRUE, .bootsvec), and
// the identification check on the restrictions (R stops on an unidentified model, so the fixture only holds identified ones).

use e.algo.linalg.decomp as decomp
use e.algo.rand.r as rng
use e.algo.stat.johansen as jo
use e.algo.stat.varschk as ck
use e.algo.stat.varsstr as ss
use e.algo.stat.vars2 as vr
use e.math
use e.math.nmath as nm
use e.mem

error Unidentified

type Vecm = struct { k: usize, lag: usize, n0: usize, nn: usize, pk: usize, n1: usize, ecdet: usize, spec: usize, season: usize, x: []f64, z0: []f64, z1: []f64, zk: []f64, v: []f64, w: []f64 }

// the VAR in levels of a VECM: A holds the lag matrices (p blocks of k by k), det the k by nd deterministic coefficients, detz the obs by nd regressors
type Vec2 = struct { k: usize, p: usize, n0: usize, obs: usize, nd: usize, r: usize, ecdet: usize, season: usize, spec: usize, a: []f64, det: []f64, detz: []f64, v: vr.Var }

// ca.jo(x, ecdet, K = lag, spec, season): x is n0 by k row-major; ecdet 0 none, 1 const, 2 trend; spec 0 longrun, 1 transitory; season 0 for none
fn vecm_new(a: *mem.Arena, x: []const f64, n0: usize, k: usize, lag: usize, ecdet: usize, spec: usize, season: usize) -> (Vecm, err) {
    var m: Vecm = zero
    let nn = n0 - lag
    var pk = k
    if ecdet >= 1usize { pk += 1usize }
    var n1 = k * (lag - 1usize) + vr.season_cols(season)
    if ecdet != 1usize { n1 += 1usize }
    let z0 = vr.zeros(a, nn * k)
    let z1 = vr.zeros(a, nn * n1)
    let zk = vr.zeros(a, nn * pk)
    var t = 0usize
    while t < nn {
        var j = 0usize
        while j < k {
            z0[t * k + j] = x[(t + lag) * k + j] - x[(t + lag - 1usize) * k + j]
            j += 1usize
        }
        var c = 0usize
        if ecdet != 1usize {
            z1[t * n1] = 1.0f64
            c = 1usize
        }
        var q = 0usize
        while q < vr.season_cols(season) {
            z1[t * n1 + c] = vr.season_value(t + lag, q, season)
            c += 1usize
            q += 1usize
        }
        var l = 1usize
        while l < lag {
            j = 0usize
            while j < k {
                z1[t * n1 + c] = x[(t + lag - l) * k + j] - x[(t + lag - l - 1usize) * k + j]
                c += 1usize
                j += 1usize
            }
            l += 1usize
        }
        var base = t
        if spec == 1usize { base = t + lag - 1usize }
        j = 0usize
        while j < k {
            zk[t * pk + j] = x[base * k + j]
            j += 1usize
        }
        if ecdet == 1usize { zk[t * pk + k] = 1.0f64 }
        if ecdet == 2usize { zk[t * pk + k] = f64(base + 1usize) }
        t += 1usize
    }
    // ca_jo reads x column-major
    let xc = vr.zeros(a, n0 * k)
    t = 0usize
    while t < n0 {
        var j = 0usize
        while j < k {
            xc[j * n0 + t] = x[t * k + j]
            j += 1usize
        }
        t += 1usize
    }
    let (jr, je) = jo.ca_jo(a, xc, n0, k, 0u8, u8(ecdet), lag, u8(spec), season)
    if je != ok { ret (m, je) }
    m.k = k
    m.lag = lag
    m.n0 = n0
    m.nn = nn
    m.pk = pk
    m.n1 = n1
    m.ecdet = ecdet
    m.spec = spec
    m.season = season
    m.x = zeros_copy(a, x, n0 * k)
    m.z0 = z0
    m.z1 = z1
    m.zk = zk
    m.v = jr.v
    m.w = jr.w
    ret (m, ok)
}

fn zeros_copy(a: *mem.Arena, x: []const f64, n: usize) -> []f64 {
    let o = vr.zeros(a, n)
    var i = 0usize
    while i < n {
        o[i] = x[i]
        i += 1usize
    }
    ret o
}

// coefficients of the least squares of each column of y (n by m) on all the columns of z (n by w): w by m row-major
fn multi_ols(a: *mem.Arena, z: []const f64, y: []const f64, n: usize, w: usize, m: usize, coef: []f64) -> err {
    let cols = vr.zeros_usize(a, w)
    var c = 0usize
    while c < w {
        cols[c] = c
        c += 1usize
    }
    let yy = vr.zeros(a, n)
    let cf = vr.zeros(a, w)
    let rs = vr.zeros(a, n)
    var j = 0usize
    while j < m {
        var t = 0usize
        while t < n {
            yy[t] = y[t * m + j]
            t += 1usize
        }
        let e = vr.ols_cols(a, z, n, w, cols, w, yy, cf, rs)
        if e != ok { ret e }
        c = 0usize
        while c < w {
            coef[c * m + j] = cf[c]
            c += 1usize
        }
        j += 1usize
    }
    ret ok
}

// the first r columns of V (pk by pk row-major) as a pk by r matrix
fn first_cols(a: *mem.Arena, x: []const f64, rows: usize, cols: usize, r: usize) -> []f64 {
    let o = vr.zeros(a, rows * r)
    var i = 0usize
    while i < rows {
        var j = 0usize
        while j < r {
            o[i * r + j] = x[i * cols + j]
            j += 1usize
        }
        i += 1usize
    }
    ret o
}

// vec2var(z, r)
fn vec2var(a: *mem.Arena, m: *const Vecm, r: usize) -> (Vec2, err) {
    var o: Vec2 = zero
    let k = m.k
    let lag = m.lag
    let pk = m.pk
    let nn = m.nn
    let vr_ = first_cols(a, m.v, pk, pk, r)
    let wr = first_cols(a, m.w, k, pk, r)
    // etc = ZK V[, 1:r]; coeffs = coef(lm(Z0 ~ -1 + etc + Z1))
    let etc = vr.mmul(a, m.zk, vr_, nn, pk, r)
    let w = r + m.n1
    let zz = ss.cbind(a, etc, r, m.z1, m.n1, nn)
    let coefs = vr.zeros(a, w * k)
    let fe = multi_ols(a, zz, m.z0, nn, w, k, coefs)
    if fe != ok { ret (o, fe) }
    // PI = W[, 1:r] t(V[, 1:r])
    let pim = vr.mmul(a, wr, vr.mtr(a, vr_, pk, r), k, r, pk)
    let ns = vr.season_cols(m.season)
    var nd = 1usize + ns
    if m.ecdet == 2usize { nd += 1usize }
    let det = vr.zeros(a, k * nd)
    let detz = vr.zeros(a, nn * nd)
    // the first Z1 row of the lag differences, and where the seasonal rows of coeffs sit
    var sd0 = r
    if m.ecdet != 1usize { sd0 = r + 1usize }
    var i = 0usize
    while i < k {
        var c = 0usize
        if m.ecdet == 1usize {
            det[i * nd + c] = pim[i * pk + k]
        } else {
            det[i * nd + c] = coefs[r * k + i]
        }
        c += 1usize
        if m.ecdet == 2usize {
            det[i * nd + c] = pim[i * pk + k]
            c += 1usize
        }
        var q = 0usize
        while q < ns {
            det[i * nd + c] = coefs[(sd0 + q) * k + i]
            c += 1usize
            q += 1usize
        }
        i += 1usize
    }
    // the deterministic regressors: constant, the ZK trend, the seasonal dummies of Z1
    var t = 0usize
    while t < nn {
        var c = 0usize
        detz[t * nd + c] = 1.0f64
        c += 1usize
        if m.ecdet == 2usize {
            detz[t * nd + c] = m.zk[t * pk + k]
            c += 1usize
        }
        var q = 0usize
        while q < ns {
            let z1c = q + (nz1_const(m.ecdet))
            detz[t * nd + c] = m.z1[t * m.n1 + z1c]
            c += 1usize
            q += 1usize
        }
        t += 1usize
    }
    // Gamma: the lag-difference coefficients, k by k (lag - 1)
    let gcols = k * (lag - 1usize)
    let gam = vr.zeros(a, k * gcols)
    let gstart = sd0 + ns
    i = 0usize
    while i < k {
        var c = 0usize
        while c < gcols {
            gam[i * gcols + c] = coefs[(gstart + c) * k + i]
            c += 1usize
        }
        i += 1usize
    }
    // the lag matrices A_1 .. A_lag
    let am = vr.zeros(a, lag * k * k)
    var l = 1usize
    while l <= lag {
        i = 0usize
        while i < k {
            var j = 0usize
            while j < k {
                var val = 0.0f64
                if l < lag { val = gam[i * gcols + (l - 1usize) * k + j] }
                if l > 1usize { val -= gam[i * gcols + (l - 2usize) * k + j] }
                if l == 1usize && i == j { val += 1.0f64 }
                if l == 1usize && m.spec == 1usize { val += pim[i * pk + j] }
                if l == lag && m.spec == 0usize { val += pim[i * pk + j] }
                am[(l - 1usize) * k * k + i * k + j] = val
                j += 1usize
            }
            i += 1usize
        }
        l += 1usize
    }
    // residuals of the VAR in levels, rows t = lag .. n0 - 1
    let obs = nn
    let nzv = k * lag + nd
    var vv: vr.Var = zero
    vv.k = k
    vv.p = lag
    vv.nz = nzv
    vv.obs = obs
    vv.t0 = m.n0
    vv.y = m.x
    vv.exo = zeros_copy(a, m.x, 0usize)
    vv.z = vr.zeros(a, obs * nzv)
    vv.yend = vr.zeros(a, obs * k)
    vv.coef = vr.zeros(a, k * nzv)
    vv.resid = vr.zeros(a, obs * k)
    vv.mask = vr.zeros(a, k * nzv)
    var q = 0usize
    while q < k * nzv {
        vv.mask[q] = 1.0f64
        q += 1usize
    }
    t = 0usize
    while t < obs {
        var l2 = 0usize
        while l2 < lag {
            var j = 0usize
            while j < k {
                vv.z[t * nzv + l2 * k + j] = m.x[(t + lag - 1usize - l2) * k + j]
                j += 1usize
            }
            l2 += 1usize
        }
        var c = 0usize
        while c < nd {
            vv.z[t * nzv + k * lag + c] = detz[t * nd + c]
            c += 1usize
        }
        var j = 0usize
        while j < k {
            vv.yend[t * k + j] = m.x[(t + lag) * k + j]
            j += 1usize
        }
        t += 1usize
    }
    i = 0usize
    while i < k {
        var l3 = 0usize
        while l3 < lag {
            var j = 0usize
            while j < k {
                vv.coef[i * nzv + l3 * k + j] = am[l3 * k * k + i * k + j]
                j += 1usize
            }
            l3 += 1usize
        }
        var c = 0usize
        while c < nd {
            vv.coef[i * nzv + k * lag + c] = det[i * nd + c]
            c += 1usize
        }
        i += 1usize
    }
    t = 0usize
    while t < obs {
        i = 0usize
        while i < k {
            var s = vv.yend[t * k + i]
            var c = 0usize
            while c < nzv {
                s -= vv.coef[i * nzv + c] * vv.z[t * nzv + c]
                c += 1usize
            }
            vv.resid[t * k + i] = s
            i += 1usize
        }
        t += 1usize
    }
    o.k = k
    o.p = lag
    o.n0 = m.n0
    o.obs = obs
    o.nd = nd
    o.r = r
    o.ecdet = m.ecdet
    o.season = m.season
    o.spec = m.spec
    o.a = am
    o.det = det
    o.detz = detz
    o.v = vv
    ret (o, ok)
}

// the index of the first seasonal column in Z1: after the constant unless the constant lives in the cointegration space
fn nz1_const(ecdet: usize) -> usize {
    if ecdet == 1usize { ret 0usize }
    ret 1usize
}

// irf(vec2var): ortho uses Psi.vec2var (the residual covariance divided by obs), else Phi; cumulative sums the horizons
fn vec2_irf(a: *mem.Arena, x: *const Vec2, h: usize, ortho: bool, cumulative: bool, out: []f64) -> bool {
    let k = x.k
    if ortho {
        if !vr.var_psi_div(a, &x.v, h, f64(x.obs), out) { ret false }
    } else {
        vr.var_phi_all(&x.v, h, out)
    }
    if cumulative {
        var s = 1usize
        while s <= h {
            var q = 0usize
            while q < k * k {
                out[s * k * k + q] += out[(s - 1usize) * k * k + q]
                q += 1usize
            }
            s += 1usize
        }
    }
    ret true
}

// fevd(vec2var): the shares, with .fecovvec2var's error covariances (sigma = crossprod / obs)
fn vec2_fevd(a: *mem.Arena, x: *const Vec2, h: usize, out: []f64) -> bool {
    let k = x.k
    let psi = vr.zeros(a, (h + 1usize) * k * k)
    if !vr.var_psi_div(a, &x.v, h, f64(x.obs), psi) { ret false }
    let sg = vr.resid_cov(a, x.v.resid, x.obs, k, f64(x.obs))
    let msey = vr.zeros(a, h * k * k)
    vr.fecov_sigma(a, &x.v, sg, h, msey)
    vr.fevd_shares(psi, msey, k, h, out)
    ret true
}

// predict(vec2var, n.ahead = h, ci): fc and half are h by k
fn vec2_predict(a: *mem.Arena, x: *const Vec2, h: usize, ci: f64, fc: []f64, half: []f64) {
    let k = x.k
    let p = x.p
    let sg = vr.resid_cov(a, x.v.resid, x.obs, k, f64(x.obs))
    let sig = vr.zeros(a, h * k * k)
    vr.fecov_sigma(a, &x.v, sg, h, sig)
    let zq = 0.0f64 - vr.nm_qnorm((1.0f64 - ci) / 2.0f64)
    var i = 0usize
    while i < h {
        var j = 0usize
        while j < k {
            half[i * k + j] = zq * math.sqrt[f64](sig[i * k * k + j * k + j])
            j += 1usize
        }
        i += 1usize
    }
    let hist = vr.zeros(a, (p + h) * k)
    i = 0usize
    while i < p {
        var j = 0usize
        while j < k {
            hist[i * k + j] = x.v.y[(x.n0 - p + i) * k + j]
            j += 1usize
        }
        i += 1usize
    }
    let ns = vr.season_cols(x.season)
    var s = 0usize
    while s < h {
        let row = p + s
        var j = 0usize
        while j < k {
            var val = 0.0f64
            var l = 0usize
            while l < p {
                var c = 0usize
                while c < k {
                    val += x.v.coef[j * x.v.nz + l * k + c] * hist[(row - 1usize - l) * k + c]
                    c += 1usize
                }
                l += 1usize
            }
            // the deterministic row: constant, trend (seq(obs + p, length = h)) for ecdet trend, then the seasonal dummies
            var c = 0usize
            val += x.det[j * x.nd + c]
            c += 1usize
            if x.ecdet == 2usize {
                val += x.det[j * x.nd + c] * f64(x.obs + p + s)
                c += 1usize
            }
            var q = 0usize
            while q < ns {
                val += x.det[j * x.nd + c] * vr.season_value(x.n0 + s, q, x.season)
                c += 1usize
                q += 1usize
            }
            hist[row * k + j] = val
            fc[s * k + j] = val
            j += 1usize
        }
        s += 1usize
    }
}

// serial.test PT on a vec2var: the degrees of freedom gain K
fn vec2_serial_pt(a: *mem.Arena, x: *const Vec2, lags: usize, out: []f64) {
    ck.var_serial_pt(a, &x.v, lags, out)
    out[2usize] += f64(x.k)
    out[3usize] = ck.p_chisq(out[0usize], out[2usize])
    out[4usize] = ck.p_chisq(out[1usize], out[2usize])
}

// the bootstrap bands of irf(vec2var, boot = TRUE) or irf(svec, boot = TRUE) (svec: lr and sr hold the restriction matrices, with NaN for a free element)
fn vec2_irf_boot(a: *mem.Arena, m: *const Vecm, r: usize, svec: bool, lr: []const f64, sr: []const f64, h: usize, ortho: bool, cumulative: bool, runs: usize, ci: f64, seed: i64, lower: []f64, upper: []f64) -> err {
    let (x0, xe) = vec2var(a, m, r)
    if xe != ok { ret xe }
    let k = x0.k
    let p = x0.p
    let obs = x0.obs
    let blk = (h + 1usize) * k * k
    let store = vr.zeros(a, runs * blk)
    var rg: rng.Rng = zero
    rng.seed(&rg, seed)
    let resorig = vr.zeros(a, obs * k)
    var j = 0usize
    while j < k {
        var mu = 0.0f64
        var t = 0usize
        while t < obs {
            mu += x0.v.resid[t * k + j]
            t += 1usize
        }
        mu = mu / f64(obs)
        t = 0usize
        while t < obs {
            resorig[t * k + j] = x0.v.resid[t * k + j] - mu
            t += 1usize
        }
        j += 1usize
    }
    var run = 0usize
    while run < runs {
        let mk = mem.mark(a)
        let (booted, se) = rng.sample_int(a, &rg, i64(obs), i64(obs), true)
        if se != ok { ret se }
        // ysampled: the first p rows of y, then B [det row, lasty] + the resampled residual; det comes before the lags in B
        let ys = vr.zeros(a, x0.n0 * k)
        var i = 0usize
        while i < p * k {
            ys[i] = x0.v.y[i]
            i += 1usize
        }
        var jj = 0usize
        while jj < obs {
            let t = p + jj
            var q = 0usize
            while q < k {
                var s = 0.0f64
                var c = 0usize
                while c < x0.nd {
                    s += x0.det[q * x0.nd + c] * x0.detz[jj * x0.nd + c]
                    c += 1usize
                }
                var l = 0usize
                while l < p {
                    var mm = 0usize
                    while mm < k {
                        s += x0.a[l * k * k + q * k + mm] * ys[(t - 1usize - l) * k + mm]
                        mm += 1usize
                    }
                    l += 1usize
                }
                ys[t * k + q] = s + resorig[(usize(booted[jj]) - 1usize) * k + q]
                q += 1usize
            }
            jj += 1usize
        }
        let (mb, me) = vecm_new(a, ys, x0.n0, k, m.lag, m.ecdet, m.spec, m.season)
        if me != ok { ret me }
        let (xb, xe2) = vec2var(a, &mb, r)
        if xe2 != ok { ret xe2 }
        let tmp = vr.zeros(a, blk)
        if svec {
            var sv: SvecFit = zero
            let fe = svec_fit(a, &mb, r, lr, sr, vr.zeros(a, 0usize), 100usize, 1.0e-7f64, 1.0f64, &rg, &sv)
            if fe != ok { ret fe }
            svec_irf(a, &xb, sv.sr, h, cumulative, tmp)
        } else {
            if !vec2_irf(a, &xb, h, ortho, cumulative, tmp) { ret Unidentified }
        }
        var q = 0usize
        while q < blk {
            store[run * blk + q] = tmp[q]
            q += 1usize
        }
        mem.reset(a, mk)
        run += 1usize
    }
    let colv = vr.zeros(a, runs)
    var q = 0usize
    while q < blk {
        run = 0usize
        while run < runs {
            colv[run] = store[run * blk + q]
            run += 1usize
        }
        lower[q] = vr.quantile7(colv, runs, (1.0f64 - ci) / 2.0f64)
        upper[q] = vr.quantile7(colv, runs, 1.0f64 - (1.0f64 - ci) / 2.0f64)
        q += 1usize
    }
    ret ok
}

// MASS::Null(m): a basis of the orthogonal complement of the columns of m (rows by cols, row-major), from qr's Householder reflections; written row-major
// (rows by the returned count)
fn null_space(a: *mem.Arena, m: []const f64, rows: usize, cols: usize, out: []f64) -> usize {
    let cm = vr.zeros(a, rows * cols)
    var i = 0usize
    while i < rows {
        var j = 0usize
        while j < cols {
            cm[j * rows + i] = m[i * cols + j]
            j += 1usize
        }
        i += 1usize
    }
    let (f, e) = decomp.qr(a, cm, rows, cols, 1.0e-7f64)
    if e != ok { ret 0usize }
    var first = f.rank
    var count = rows - f.rank
    if f.rank == 0usize {
        first = 0usize
        count = cols
    }
    var c = 0usize
    while c < count {
        let y = vr.zeros(a, rows)
        y[first + c] = 1.0f64
        decomp.qr_qy(&f, y)
        i = 0usize
        while i < rows {
            out[i * count + c] = y[i]
            i += 1usize
        }
        c += 1usize
    }
    ret count
}

// the rank of m (rows by cols, row-major) as qr() reports it
fn qr_rank(a: *mem.Arena, m: []const f64, rows: usize, cols: usize) -> usize {
    let cm = vr.zeros(a, rows * cols)
    var i = 0usize
    while i < rows {
        var j = 0usize
        while j < cols {
            cm[j * rows + i] = m[i * cols + j]
            j += 1usize
        }
        i += 1usize
    }
    let (f, e) = decomp.qr(a, cm, rows, cols, 1.0e-7f64)
    if e != ok { ret 0usize }
    ret f.rank
}

type SvecFit = struct { sr: []f64, lr: []f64, sigma_u: []f64, nres_c1: usize, nres_b: usize, l: usize, iter: usize, has_lr: bool, lr_stat: f64, lr_df: f64, lr_p: f64 }

// SVEC(x, LR, SR, r, start, max.iter, conv.crit, maxls, lrtest): lr and sr are k by k row-major with 0 for a restriction (anything else is free); an empty start
// draws rnorm(l) from rg as R does
fn svec_fit(a: *mem.Arena, m: *const Vecm, r: usize, lr: []const f64, sr: []const f64, start: []const f64, max_iter: usize, conv: f64, maxls: f64, rg: *rng.Rng, out: *SvecFit) -> err {
    let k = m.k
    let k2 = k * k
    let pp = m.lag - 1usize
    let pk = m.pk
    let nn = m.nn
    // cajorls: betanorm = beta solve(beta[1:r, 1:r]); rlm = lm(Z0 ~ -1 + ECT + Z1)
    let beta = first_cols(a, m.v, pk, pk, r)
    let b1 = vr.zeros(a, r * r)
    var i = 0usize
    while i < r {
        var j = 0usize
        while j < r {
            b1[i * r + j] = beta[i * r + j]
            j += 1usize
        }
        i += 1usize
    }
    let bnorm = vr.mmul(a, beta, vr.minv(a, b1, r), pk, r, r)
    let ect = vr.mmul(a, m.zk, bnorm, nn, pk, r)
    let w = r + m.n1
    let zz = ss.cbind(a, ect, r, m.z1, m.n1, nn)
    let coefs = vr.zeros(a, w * k)
    let fe = multi_ols(a, zz, m.z0, nn, w, k, coefs)
    if fe != ok { ret fe }
    // residuals of the rlm
    let resid = vr.zeros(a, nn * k)
    var t = 0usize
    while t < nn {
        i = 0usize
        while i < k {
            var s = m.z0[t * k + i]
            var c = 0usize
            while c < w {
                s -= zz[t * w + c] * coefs[c * k + i]
                c += 1usize
            }
            resid[t * k + i] = s
            i += 1usize
        }
        t += 1usize
    }
    let obs = f64(nn)
    let sigma = vr.resid_cov(a, resid, nn, k, obs)
    // alpha (k by r) = t(Coef[1:r, ]); the Null space of alpha (r > 1) or of t(alpha) as a column (r == 1) is the same set of columns
    let alpha = vr.zeros(a, k * r)
    i = 0usize
    while i < k {
        var j = 0usize
        while j < r {
            alpha[i * r + j] = coefs[j * k + i]
            j += 1usize
        }
        i += 1usize
    }
    let ao = vr.zeros(a, k * k)
    let nao = null_space(a, alpha, k, r, ao)
    let bk = vr.zeros(a, k * r)
    i = 0usize
    while i < k {
        var j = 0usize
        while j < r {
            bk[i * r + j] = bnorm[i * r + j]
            j += 1usize
        }
        i += 1usize
    }
    let bo = vr.zeros(a, k * k)
    let nbo = null_space(a, bk, k, r, bo)
    // Gamma = sum of the lagged-difference coefficient blocks
    let gamma_sum = vr.zeros(a, k2)
    var jb = 0usize
    while jb < pp {
        i = 0usize
        while i < k {
            var mm = 0usize
            while mm < k {
                gamma_sum[i * k + mm] += coefs[(w - k * pp + jb * k + mm) * k + i]
                mm += 1usize
            }
            i += 1usize
        }
        jb += 1usize
    }
    let ik = vr.ident(a, k)
    let ikg = vr.zeros(a, k2)
    i = 0usize
    while i < k2 {
        ikg[i] = ik[i] - gamma_sum[i]
        i += 1usize
    }
    // Xi = beta.orth (alpha.orth' (I - Gamma) beta.orth)^-1 alpha.orth'
    let aoc = first_cols(a, ao, k, nao, nao)
    let boc = first_cols(a, bo, k, nbo, nbo)
    let mid = vr.mmul(a, vr.mmul(a, vr.mtr(a, aoc, k, nao), ikg, nao, k, k), boc, nao, k, nbo)
    let xi = vr.mmul(a, vr.mmul(a, boc, vr.minv(a, mid, nbo), k, nbo, nao), vr.mtr(a, aoc, k, nao), k, nao, k)
    // restrictions: the zero entries of SR (in column-major order) select rows of I; those of LR rows of kron(I, Xi)
    var nsr = 0usize
    var nlr = 0usize
    i = 0usize
    while i < k2 {
        if sr[i] == 0.0f64 { nsr += 1usize }
        if lr[i] == 0.0f64 { nlr += 1usize }
        i += 1usize
    }
    let rb = vr.zeros(a, nsr * k2)
    let rc = vr.zeros(a, k2 * k2)
    let kx = ss.kron(a, ik, k, k, xi, k, k)
    var rowb = 0usize
    var rowc = 0usize
    var cc = 0usize
    while cc < k {
        var rr = 0usize
        while rr < k {
            // column-major position cc k + rr of the matrix element (rr, cc)
            if sr[rr * k + cc] == 0.0f64 {
                rb[rowb * k2 + cc * k + rr] = 1.0f64
                rowb += 1usize
            }
            if lr[rr * k + cc] == 0.0f64 {
                var q = 0usize
                while q < k2 {
                    rc[rowc * k2 + q] = kx[(cc * k + rr) * k2 + q]
                    q += 1usize
                }
                rowc += 1usize
            }
            rr += 1usize
        }
        cc += 1usize
    }
    // R.C1 keeps its K^2 rows (all zero) when there is no long-run restriction
    var c1rows = nlr
    if nlr == 0usize { c1rows = k2 }
    let nres_c1 = qr_rank(a, rc[0usize..c1rows * k2], c1rows, k2)
    var nres_b = 0usize
    var rtot = c1rows
    var rm = rc[0usize..c1rows * k2]
    if nsr > 0usize {
        nres_b = qr_rank(a, rb, nsr, k2)
        rm = ss.rbind(a, rc[0usize..c1rows * k2], rb)
        rtot = c1rows + nsr
    }
    if nres_c1 + nres_b < k * (k - 1usize) / 2usize { ret Unidentified }
    // Sb = Null(t(R))
    let rmt = vr.mtr(a, rm, rtot, k2)
    let sbuf = vr.zeros(a, k2 * k2)
    let l = null_space(a, rmt, k2, rtot, sbuf)
    let sm = vr.zeros(a, 2usize * k2 * l)
    i = 0usize
    while i < k2 {
        var j = 0usize
        while j < l {
            sm[(k2 + i) * l + j] = sbuf[i * l + j]
            j += 1usize
        }
        i += 1usize
    }
    let s0 = vr.zeros(a, 2usize * k2)
    i = 0usize
    while i < k {
        s0[i * k + i] = 1.0f64
        i += 1usize
    }
    let gamma = vr.zeros(a, l)
    i = 0usize
    while i < l {
        if start.len == l { gamma[i] = start[i] } else { gamma[i] = rng.norm(rg) }
        i += 1usize
    }
    let al = vr.zeros(a, k2)
    let bl = vr.zeros(a, k2)
    let ig = vr.zeros(a, l * l)
    let iters = ss.svar_scoring(a, k, obs, sigma, sm, s0, l, gamma, max_iter, conv, maxls, al, bl, ig)
    // vec(A) is column-major: al/bl are row-major k by k as svar_scoring returns them
    let srf = vr.zeros(a, k2)
    i = 0usize
    while i < k2 {
        srf[i] = bl[i]
        i += 1usize
    }
    let ainvb = vr.mmul(a, vr.minv(a, al, k), bl, k, k, k)
    var cj = 0usize
    while cj < k {
        if ainvb[cj * k + cj] < 0.0f64 {
            i = 0usize
            while i < k {
                srf[i * k + cj] = 0.0f64 - srf[i * k + cj]
                i += 1usize
            }
        }
        cj += 1usize
    }
    let lrm = vr.mmul(a, xi, srf, k, k, k)
    let ai = vr.minv(a, al, k)
    let ab = vr.mmul(a, ai, bl, k, k, k)
    let su = vr.mmul(a, ab, vr.mtr(a, ab, k, k), k, k, k)
    i = 0usize
    while i < k2 {
        if math.abs[f64](lrm[i]) < 1.0e-9f64 { lrm[i] = 0.0f64 }
        if math.abs[f64](srf[i]) < 1.0e-9f64 { srf[i] = 0.0f64 }
        i += 1usize
    }
    out.sr = srf
    out.lr = lrm
    out.sigma_u = su
    out.nres_c1 = nres_c1
    out.nres_b = nres_b
    out.l = l
    out.iter = iters - 1usize
    let degrees = f64(k * (k + 1usize) / 2usize) - f64(l)
    out.has_lr = degrees != 0.0f64
    if out.has_lr {
        out.lr_stat = (math.log[f64](vr.mdet(a, su, k)) - math.log[f64](vr.mdet(a, sigma, k))) * obs
        out.lr_df = degrees
        out.lr_p = 1.0f64 - nm.pchisq(out.lr_stat, degrees, true, false)
    }
    ret ok
}

// the responses of an SVEC: Phi_s (of vec2var) times SR, s = 0 ..= h, cumulated when asked
fn svec_irf(a: *mem.Arena, x: *const Vec2, sr: []const f64, h: usize, cumulative: bool, out: []f64) {
    let k = x.k
    let phi = vr.zeros(a, (h + 1usize) * k * k)
    vr.var_phi_all(&x.v, h, phi)
    var s = 0usize
    while s <= h {
        let mt = vr.mmul(a, phi[s * k * k..(s + 1usize) * k * k], sr, k, k, k)
        var q = 0usize
        while q < k * k {
            out[s * k * k + q] = mt[q]
            if cumulative && s > 0usize { out[s * k * k + q] += out[(s - 1usize) * k * k + q] }
            q += 1usize
        }
        s += 1usize
    }
}
