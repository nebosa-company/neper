// R vars' structural models on a fitted VAR (e.algo.stat.vars2.Var): SVAR by the scoring algorithm (the A, B and AB models, the standard errors and the
// likelihood ratio test of the over-identifying restrictions), and the impulse responses (with bootstrap bands) and forecast error variance
// decomposition of a structural VAR.
//
// SVAR(estmethod = "direct") is here too, through a port of optim's Nelder-Mead (nmmin) with its defaults.
//
// Not here: the hessian of the direct method (optim(hessian = TRUE), so no standard errors for it), and the structural models of a VECM
// (e.algo.stat.varsvec).

use e.algo.rand.r as rng
use e.algo.stat.vars2 as vr
use e.math
use e.math.nmath as nm
use e.mem

error NotConverged

type Svar = struct { k: usize, params: usize, iter: usize, a: []f64, b: []f64, ase: []f64, bse: []f64, sigma_u: []f64, has_lr: bool, lr_stat: f64, lr_df: f64, lr_p: f64 }

fn is_nan(x: f64) -> bool { ret x != x }

// kronecker(x (m by n), y (p by q)), row-major: out[(i p + r) (n q) + (j q + c)] = x[i][j] y[r][c]
fn kron(a: *mem.Arena, x: []const f64, m: usize, n: usize, y: []const f64, p: usize, q: usize) -> []f64 {
    let o = vr.zeros(a, m * p * n * q)
    var i = 0usize
    while i < m {
        var j = 0usize
        while j < n {
            var r = 0usize
            while r < p {
                var c = 0usize
                while c < q {
                    o[(i * p + r) * n * q + j * q + c] = x[i * n + j] * y[r * q + c]
                    c += 1usize
                }
                r += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    ret o
}

// c(m): the column-major vector of a rows by cols row-major matrix
fn vec_of(a: *mem.Arena, m: []const f64, rows: usize, cols: usize) -> []f64 {
    let o = vr.zeros(a, rows * cols)
    var i = 0usize
    while i < rows {
        var j = 0usize
        while j < cols {
            o[j * rows + i] = m[i * cols + j]
            j += 1usize
        }
        i += 1usize
    }
    ret o
}

// matrix(v, rows, cols): a row-major matrix from the column-major vector v
fn mat_of(a: *mem.Arena, v: []const f64, rows: usize, cols: usize) -> []f64 {
    let o = vr.zeros(a, rows * cols)
    var i = 0usize
    while i < rows {
        var j = 0usize
        while j < cols {
            o[i * cols + j] = v[j * rows + i]
            j += 1usize
        }
        i += 1usize
    }
    ret o
}

// -m
fn neg(a: *mem.Arena, m: []const f64) -> []f64 {
    let o = vr.zeros(a, m.len)
    var i = 0usize
    while i < m.len {
        o[i] = 0.0f64 - m[i]
        i += 1usize
    }
    ret o
}

// the commutation matrix of vars: diag(k^2)[, c(sapply(1:k, function(i) seq(i, k^2, k)))]
fn commutation(a: *mem.Arena, k: usize) -> []f64 {
    let o = vr.zeros(a, k * k * k * k)
    var i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            // column i k + j is the unit vector of position i + j k
            o[(i + j * k) * k * k + (i * k + j)] = 1.0f64
            j += 1usize
        }
        i += 1usize
    }
    ret o
}

// rbind of two row-major blocks with the same number of columns
fn rbind(a: *mem.Arena, x: []const f64, y: []const f64) -> []f64 {
    let o = vr.zeros(a, x.len + y.len)
    var i = 0usize
    while i < x.len {
        o[i] = x[i]
        i += 1usize
    }
    i = 0usize
    while i < y.len {
        o[x.len + i] = y[i]
        i += 1usize
    }
    ret o
}

// cbind of two row-major blocks of `rows` rows and cx, cy columns
fn cbind(a: *mem.Arena, x: []const f64, cx: usize, y: []const f64, cy: usize, rows: usize) -> []f64 {
    let o = vr.zeros(a, rows * (cx + cy))
    var i = 0usize
    while i < rows {
        var j = 0usize
        while j < cx {
            o[i * (cx + cy) + j] = x[i * cx + j]
            j += 1usize
        }
        j = 0usize
        while j < cy {
            o[i * (cx + cy) + cx + j] = y[i * cy + j]
            j += 1usize
        }
        i += 1usize
    }
    ret o
}

// the scoring iterations of SVAR and SVEC on gamma with vec(A, B) = sm gamma + s0 (sm is 2 k^2 by l row-major); sigma is the k by k residual covariance and
// obs the sample size in the likelihood. gamma holds the start and ends at the last iterate; a_last and b_last are the A and B of the last iteration's start
// (which is what R returns), infgamma that iteration's information matrix (l by l); iters is R's `iter + 1`
fn svar_scoring(a: *mem.Arena, k: usize, obs: f64, sigma: []const f64, sm: []const f64, s0: []const f64, l: usize, gamma: []f64, max_iter: usize, conv: f64, maxls: f64, a_last: []f64, b_last: []f64, infgamma: []f64) -> usize {
    let k2 = k * k
    let ik = vr.ident(a, k)
    let ik2 = vr.ident(a, k2)
    let kkk = commutation(a, k)
    let mat2 = vr.zeros(a, k2 * k2)
    var q = 0usize
    while q < k2 * k2 {
        mat2[q] = ik2[q] + kkk[q]
        q += 1usize
    }
    let smt = vr.mtr(a, sm, 2usize * k2, l)
    var iters = 0usize
    var cv = conv + 1.0f64
    while cv > conv {
        let start = mem.mark(a)
        let z = vr.zeros(a, l)
        q = 0usize
        while q < l {
            z[q] = gamma[q]
            q += 1usize
        }
        let vecab = vr.mmul(a, sm, gamma, 2usize * k2, l, 1usize)
        q = 0usize
        while q < 2usize * k2 {
            vecab[q] += s0[q]
            q += 1usize
        }
        let am = mat_of(a, vecab[0usize..k2], k, k)
        let bm = mat_of(a, vecab[k2..2usize * k2], k, k)
        let binv = vr.minv(a, bm, k)
        let btinv = vr.minv(a, vr.mtr(a, bm, k, k), k)
        let bia = vr.mmul(a, binv, am, k, k, k)
        let ibia = vr.minv(a, bia, k)
        let m1 = rbind(a, kron(a, ibia, k, k, btinv, k, k), neg(a, kron(a, ik, k, k, btinv, k, k)))
        let m3 = cbind(a, kron(a, vr.mtr(a, ibia, k, k), k, k, binv, k, k), k2, neg(a, kron(a, ik, k, k, binv, k, k)), k2, k2)
        let infab = vr.mmul(a, vr.mmul(a, m1, mat2, 2usize * k2, k2, k2), m3, 2usize * k2, k2, 2usize * k2)
        q = 0usize
        while q < 4usize * k2 * k2 {
            infab[q] = infab[q] * obs
            q += 1usize
        }
        let ig = vr.mmul(a, smt, vr.mmul(a, infab, sm, 2usize * k2, 2usize * k2, l), l, 2usize * k2, l)
        let igi = vr.minv(a, ig, l)
        // score of vec(B^-1 A)
        let t1 = vec_of(a, vr.minv(a, vr.mtr(a, bia, k, k), k), k, k)
        let sk = kron(a, sigma, k, k, ik, k, k)
        let vbia = vec_of(a, bia, k, k)
        let t2 = vr.mmul(a, sk, vbia, k2, k2, 1usize)
        let sv = vr.zeros(a, k2)
        q = 0usize
        while q < k2 {
            sv[q] = obs * t1[q] - obs * t2[q]
            q += 1usize
        }
        let sab = rbind(a, kron(a, ik, k, k, btinv, k, k), neg(a, kron(a, bia, k, k, btinv, k, k)))
        let score = vr.mmul(a, sab, sv, 2usize * k2, k2, 1usize)
        let sg = vr.mmul(a, smt, score, l, 2usize * k2, 1usize)
        let dir = vr.mmul(a, igi, sg, l, l, 1usize)
        var len = 0.0f64
        q = 0usize
        while q < l {
            if math.abs[f64](dir[q]) > len { len = math.abs[f64](dir[q]) }
            q += 1usize
        }
        var lambda = 1.0f64
        if len > maxls { lambda = maxls / len }
        // keep the last iteration's A, B and information matrix (the allocations below the mark are released after the copy)
        q = 0usize
        while q < k2 {
            a_last[q] = am[q]
            b_last[q] = bm[q]
            q += 1usize
        }
        q = 0usize
        while q < l * l {
            infgamma[q] = ig[q]
            q += 1usize
        }
        q = 0usize
        while q < l {
            gamma[q] = gamma[q] + lambda * dir[q]
            q += 1usize
        }
        iters += 1usize
        cv = 0.0f64
        q = 0usize
        while q < l {
            let d = math.abs[f64](z[q] - gamma[q])
            if d > cv { cv = d }
            q += 1usize
        }
        mem.reset(a, start)
        if iters >= max_iter { cv = 0.0f64 }
    }
    ret iters
}

// SVAR(x, Amat, Bmat, estmethod = "scoring", start, max.iter, conv.crit, maxls, lrtest = TRUE): mode 0 A-model (Amat only), 1 B-model (Bmat only),
// 2 AB-model; amat and bmat are k by k row-major with NaN for a free element; start has one value per free element (empty for R's 0.1)
fn svar_fit(a: *mem.Arena, v: *const vr.Var, mode: usize, amat: []const f64, bmat: []const f64, start: []const f64, max_iter: usize, conv: f64, maxls: f64, direct: bool, out: *Svar) -> err {
    let k = v.k
    let k2 = k * k
    let obs = f64(v.obs)
    let sigma = vr.resid_cov(a, v.resid, v.obs, k, vr.eq_df(v, 0usize))
    let am0 = vr.zeros(a, k2)
    let bm0 = vr.zeros(a, k2)
    let ik = vr.ident(a, k)
    var i = 0usize
    while i < k2 {
        if mode == 0usize || mode == 2usize { am0[i] = amat[i] } else { am0[i] = ik[i] }
        if mode == 1usize || mode == 2usize { bm0[i] = bmat[i] } else { bm0[i] = ik[i] }
        i += 1usize
    }
    if mode == 2usize {
        i = 0usize
        while i < k {
            am0[i * k + i] = 1.0f64
            i += 1usize
        }
    }
    // the free elements in column-major order
    let ra = vec_of(a, am0, k, k)
    let rb = vec_of(a, bm0, k, k)
    var pa = 0usize
    var pb = 0usize
    i = 0usize
    while i < k2 {
        if is_nan(ra[i]) { pa += 1usize }
        if is_nan(rb[i]) { pb += 1usize }
        i += 1usize
    }
    let params = pa + pb
    let sm = vr.zeros(a, 2usize * k2 * params)
    let s0 = vr.zeros(a, 2usize * k2)
    var col = 0usize
    i = 0usize
    while i < k2 {
        if is_nan(ra[i]) {
            sm[i * params + col] = 1.0f64
            col += 1usize
            s0[i] = 0.0f64
        } else {
            s0[i] = ra[i]
        }
        i += 1usize
    }
    i = 0usize
    while i < k2 {
        if is_nan(rb[i]) {
            sm[(k2 + i) * params + col] = 1.0f64
            col += 1usize
            s0[k2 + i] = 0.0f64
        } else {
            s0[k2 + i] = rb[i]
        }
        i += 1usize
    }
    let gamma = vr.zeros(a, params)
    i = 0usize
    while i < params {
        if start.len == params { gamma[i] = start[i] } else { gamma[i] = 0.1f64 }
        i += 1usize
    }
    let al = vr.zeros(a, k2)
    let bl = vr.zeros(a, k2)
    out.k = k
    out.params = params
    if direct {
        // optim(start, logLc) by Nelder-Mead with the defaults; the standard errors need the hessian, which is not computed
        var ctx: DirectCtx = zero
        ctx.k = k
        ctx.obs = obs
        ctx.sigma = sigma
        ctx.ra = ra
        ctx.rb = rb
        let xo = vr.zeros(a, params)
        let (fmin, fncount, fail) = nmmin(a, &ctx, params, gamma, xo, 1.4901161193847656e-8f64, 500usize)
        let _ = fmin
        let _ = fail
        out.iter = fncount
        let av = direct_vec(a, &ctx, xo, true)
        let bv = direct_vec(a, &ctx, xo, false)
        let am1 = mat_of(a, av, k, k)
        let bm1 = mat_of(a, bv, k, k)
        i = 0usize
        while i < k2 {
            al[i] = am1[i]
            bl[i] = bm1[i]
            i += 1usize
        }
        out.ase = vr.zeros(a, k2)
        out.bse = vr.zeros(a, k2)
    } else {
        let ig = vr.zeros(a, params * params)
        let iters = svar_scoring(a, k, obs, sigma, sm, s0, params, gamma, max_iter, conv, maxls, al, bl, ig)
        out.iter = iters - 1usize
        // abSigma = sqrt(diag(R solve(infgamma) R'))
        let igi = vr.minv(a, ig, params)
        let rr = vr.mmul(a, vr.mmul(a, sm, igi, 2usize * k2, params, params), vr.mtr(a, sm, 2usize * k2, params), 2usize * k2, params, 2usize * k2)
        let ab = vr.zeros(a, 2usize * k2)
        i = 0usize
        while i < 2usize * k2 {
            ab[i] = math.sqrt[f64](rr[i * 2usize * k2 + i])
            i += 1usize
        }
        out.ase = mat_of(a, ab[0usize..k2], k, k)
        out.bse = mat_of(a, ab[k2..2usize * k2], k, k)
    }
    let af = vr.zeros(a, k2)
    let bf = vr.zeros(a, k2)
    i = 0usize
    while i < k2 {
        af[i] = al[i]
        bf[i] = bl[i]
        i += 1usize
    }
    // sign normalisation
    if mode == 2usize {
        var j = 0usize
        while j < k {
            if af[j * k + j] < 0.0f64 {
                i = 0usize
                while i < k {
                    af[i * k + j] = 0.0f64 - af[i * k + j]
                    i += 1usize
                }
            }
            if bf[j * k + j] < 0.0f64 {
                i = 0usize
                while i < k {
                    bf[i * k + j] = 0.0f64 - bf[i * k + j]
                    i += 1usize
                }
            }
            j += 1usize
        }
    } else {
        let ainvb = vr.mmul(a, vr.minv(a, af, k), bf, k, k, k)
        var j = 0usize
        while j < k {
            if ainvb[j * k + j] < 0.0f64 {
                i = 0usize
                while i < k {
                    if mode == 1usize { bf[i * k + j] = 0.0f64 - bf[i * k + j] } else { af[i * k + j] = 0.0f64 - af[i * k + j] }
                    i += 1usize
                }
            }
            j += 1usize
        }
    }
    out.a = af
    out.b = bf
    let ainv = vr.minv(a, af, k)
    let ab1 = vr.mmul(a, ainv, bf, k, k, k)
    out.sigma_u = vr.mmul(a, ab1, vr.mtr(a, ab1, k, k), k, k, k)
    let kk = f64(k * (k + 1usize) / 2usize)
    let degrees = kk - f64(params)
    out.has_lr = degrees != 0.0f64
    if out.has_lr {
        out.lr_stat = obs * (math.log[f64](vr.mdet(a, out.sigma_u, k)) - math.log[f64](vr.mdet(a, sigma, k)))
        out.lr_df = degrees
        out.lr_p = 1.0f64 - nm.pchisq(out.lr_stat, degrees, true, false)
    }
    ret ok
}

// the responses Phi_s (VAR) times A^-1 B for s = 0 ..= h (k by k blocks [s][response][impulse]), cumulated when asked; as irf.svarest
fn svar_irf(a: *mem.Arena, v: *const vr.Var, am: []const f64, bm: []const f64, h: usize, cumulative: bool, out: []f64) {
    let k = v.k
    let phi = vr.zeros(a, (h + 1usize) * k * k)
    vr.var_phi_all(v, h, phi)
    let ab = vr.mmul(a, vr.minv(a, am, k), bm, k, k, k)
    var s = 0usize
    while s <= h {
        let m = vr.mmul(a, phi[s * k * k..(s + 1usize) * k * k], ab, k, k, k)
        var q = 0usize
        while q < k * k {
            out[s * k * k + q] = m[q]
            if cumulative && s > 0usize { out[s * k * k + q] += out[(s - 1usize) * k * k + q] }
            q += 1usize
        }
        s += 1usize
    }
}

// the share fevd of a structural model from its responses theta (h + 1 blocks): .fecovsvar and fevd.svarest
fn struct_fevd(a: *mem.Arena, theta: []const f64, k: usize, h: usize, out: []f64) {
    let msey = vr.zeros(a, h * k * k)
    var n = 1usize
    while n <= h {
        var j = 0usize
        while j < n {
            let t = theta[j * k * k..(j + 1usize) * k * k]
            let m = vr.mmul(a, t, vr.mtr(a, t, k, k), k, k, k)
            var q = 0usize
            while q < k * k {
                msey[(n - 1usize) * k * k + q] += m[q]
                q += 1usize
            }
            j += 1usize
        }
        n += 1usize
    }
    vr.fevd_shares(theta, msey, k, h, out)
}

// the likelihood of SVAR(estmethod = "direct"): ra and rb are vec(A) and vec(B) (column-major) with NaN for a free element, filled from par in order
type DirectCtx = struct { k: usize, obs: f64, sigma: []f64, ra: []f64, rb: []f64 }

// vec(A) (A true) or vec(B) as a column-major vector, the free elements taken from par (A's first, then B's)
fn direct_vec(a: *mem.Arena, c: *const DirectCtx, par: []const f64, want_a: bool) -> []f64 {
    let k2 = c.k * c.k
    let o = vr.zeros(a, k2)
    var at = 0usize
    var i = 0usize
    while i < k2 {
        if is_nan(c.ra[i]) { at += 1usize }
        i += 1usize
    }
    // B's free elements follow A's in par
    var cnt = 0usize
    i = 0usize
    while i < k2 {
        if want_a {
            if is_nan(c.ra[i]) {
                o[i] = par[cnt]
                cnt += 1usize
            } else {
                o[i] = c.ra[i]
            }
        } else {
            if is_nan(c.rb[i]) {
                o[i] = par[at + cnt]
                cnt += 1usize
            } else {
                o[i] = c.rb[i]
            }
        }
        i += 1usize
    }
    ret o
}

// -logLc of SVAR(direct): -(-(k obs / 2) log(2 pi) + obs / 2 log(det(A)^2) - obs / 2 log(det(B)^2) - obs / 2 sum(diag(A' B'^-1 B^-1 A sigma)))
fn direct_obj(a: *mem.Arena, c: *const DirectCtx, par: []const f64) -> f64 {
    let k = c.k
    let start = mem.mark(a)
    let am = mat_of(a, direct_vec(a, c, par, true), k, k)
    let bm = mat_of(a, direct_vec(a, c, par, false), k, k)
    let da = vr.mdet(a, am, k)
    let db = vr.mdet(a, bm, k)
    let bt = vr.mtr(a, bm, k, k)
    let t1 = vr.mmul(a, vr.mtr(a, am, k, k), vr.minv(a, bt, k), k, k, k)
    let t2 = vr.mmul(a, t1, vr.minv(a, bm, k), k, k, k)
    let t3 = vr.mmul(a, t2, am, k, k, k)
    let t4 = vr.mmul(a, t3, c.sigma, k, k, k)
    let tr = vr.trace_of(t4, k)
    let ll = 0.0f64 - f64(k) * c.obs / 2.0f64 * math.log[f64](2.0f64 * 3.141592653589793f64) + c.obs / 2.0f64 * math.log[f64](da * da) - c.obs / 2.0f64 * math.log[f64](db * db) - c.obs / 2.0f64 * tr
    mem.reset(a, start)
    ret 0.0f64 - ll
}

fn finite_value(x: f64) -> bool { ret x == x && x - x == 0.0f64 }

// R's nmmin (optim, method = "Nelder-Mead") with alpha 1, beta 1/2, gamma 2, abstol -Inf, from bvec; the minimiser goes to xout; answers (value, function count, fail code)
fn nmmin(a: *mem.Arena, c: *const DirectCtx, n: usize, bvec: []f64, xout: []f64, intol: f64, maxit: usize) -> (f64, usize, usize) {
    let big = 1.0e35f64
    let alpha = 1.0f64
    let bet = 0.5f64
    let gamm = 2.0f64
    let n1 = n + 1usize
    let cc = n + 2usize
    let w = cc
    let p = vr.zeros(a, n1 * w)
    var fail = 0usize
    var f = direct_obj(a, c, bvec)
    var funcount = 1usize
    let convtol = intol * (math.abs[f64](f) + intol)
    p[(n1 - 1usize) * w] = f
    var i = 0usize
    while i < n {
        p[i * w] = bvec[i]
        i += 1usize
    }
    var ll = 1usize
    var size = 0.0f64
    var step = 0.0f64
    i = 0usize
    while i < n {
        if 0.1f64 * math.abs[f64](bvec[i]) > step { step = 0.1f64 * math.abs[f64](bvec[i]) }
        i += 1usize
    }
    if step == 0.0f64 { step = 0.1f64 }
    var j = 2usize
    while j <= n1 {
        i = 0usize
        while i < n {
            p[i * w + j - 1usize] = bvec[i]
            i += 1usize
        }
        var trystep = step
        while p[(j - 2usize) * w + j - 1usize] == bvec[j - 2usize] {
            p[(j - 2usize) * w + j - 1usize] = bvec[j - 2usize] + trystep
            trystep = trystep * 10.0f64
        }
        size += trystep
        j += 1usize
    }
    var oldsize = size
    var calcvert = true
    var go = true
    while go {
        if calcvert {
            j = 0usize
            while j < n1 {
                if j + 1usize != ll {
                    i = 0usize
                    while i < n {
                        bvec[i] = p[i * w + j]
                        i += 1usize
                    }
                    f = direct_obj(a, c, bvec)
                    if !finite_value(f) { f = big }
                    funcount += 1usize
                    p[(n1 - 1usize) * w + j] = f
                }
                j += 1usize
            }
            calcvert = false
        }
        var vl = p[(n1 - 1usize) * w + ll - 1usize]
        var vh = vl
        var hh = ll
        j = 1usize
        while j <= n1 {
            if j != ll {
                f = p[(n1 - 1usize) * w + j - 1usize]
                if f < vl {
                    ll = j
                    vl = f
                }
                if f > vh {
                    hh = j
                    vh = f
                }
            }
            j += 1usize
        }
        if vh <= vl + convtol {
            go = false
        } else {
            i = 0usize
            while i < n {
                var temp = 0.0f64 - p[i * w + hh - 1usize]
                j = 0usize
                while j < n1 {
                    temp += p[i * w + j]
                    j += 1usize
                }
                p[i * w + cc - 1usize] = temp / f64(n)
                i += 1usize
            }
            i = 0usize
            while i < n {
                bvec[i] = (1.0f64 + alpha) * p[i * w + cc - 1usize] - alpha * p[i * w + hh - 1usize]
                i += 1usize
            }
            f = direct_obj(a, c, bvec)
            if !finite_value(f) { f = big }
            funcount += 1usize
            let vr_ = f
            if vr_ < vl {
                p[(n1 - 1usize) * w + cc - 1usize] = f
                i = 0usize
                while i < n {
                    f = gamm * bvec[i] + (1.0f64 - gamm) * p[i * w + cc - 1usize]
                    p[i * w + cc - 1usize] = bvec[i]
                    bvec[i] = f
                    i += 1usize
                }
                f = direct_obj(a, c, bvec)
                if !finite_value(f) { f = big }
                funcount += 1usize
                if f < vr_ {
                    i = 0usize
                    while i < n {
                        p[i * w + hh - 1usize] = bvec[i]
                        i += 1usize
                    }
                    p[(n1 - 1usize) * w + hh - 1usize] = f
                } else {
                    i = 0usize
                    while i < n {
                        p[i * w + hh - 1usize] = p[i * w + cc - 1usize]
                        i += 1usize
                    }
                    p[(n1 - 1usize) * w + hh - 1usize] = vr_
                }
            } else {
                if vr_ < vh {
                    i = 0usize
                    while i < n {
                        p[i * w + hh - 1usize] = bvec[i]
                        i += 1usize
                    }
                    p[(n1 - 1usize) * w + hh - 1usize] = vr_
                }
                i = 0usize
                while i < n {
                    bvec[i] = (1.0f64 - bet) * p[i * w + hh - 1usize] + bet * p[i * w + cc - 1usize]
                    i += 1usize
                }
                f = direct_obj(a, c, bvec)
                if !finite_value(f) { f = big }
                funcount += 1usize
                if f < p[(n1 - 1usize) * w + hh - 1usize] {
                    i = 0usize
                    while i < n {
                        p[i * w + hh - 1usize] = bvec[i]
                        i += 1usize
                    }
                    p[(n1 - 1usize) * w + hh - 1usize] = f
                } else {
                    if vr_ >= vh {
                        calcvert = true
                        size = 0.0f64
                        j = 0usize
                        while j < n1 {
                            if j + 1usize != ll {
                                i = 0usize
                                while i < n {
                                    p[i * w + j] = bet * (p[i * w + j] - p[i * w + ll - 1usize]) + p[i * w + ll - 1usize]
                                    size += math.abs[f64](p[i * w + j] - p[i * w + ll - 1usize])
                                    i += 1usize
                                }
                            }
                            j += 1usize
                        }
                        if size < oldsize {
                            oldsize = size
                        } else {
                            fail = 10usize
                            go = false
                        }
                    }
                }
            }
            if go && funcount > maxit { go = false }
        }
    }
    i = 0usize
    while i < n {
        xout[i] = p[i * w + ll - 1usize]
        i += 1usize
    }
    if funcount > maxit { fail = 1usize }
    ret (p[(n1 - 1usize) * w + ll - 1usize], funcount, fail)
}

// irf(svar, boot = TRUE, runs, ci, seed): the bootstrap bands, re-estimating the SVAR on every resampled series from the same start
fn svar_irf_boot(a: *mem.Arena, v: *const vr.Var, mode: usize, amat: []const f64, bmat: []const f64, start: []const f64, max_iter: usize, conv: f64, maxls: f64, direct: bool, h: usize, cumulative: bool, runs: usize, ci: f64, seed: i64, lower: []f64, upper: []f64) -> err {
    let k = v.k
    let blk = (h + 1usize) * k * k
    let store = vr.zeros(a, runs * blk)
    var rg: rng.Rng = zero
    rng.seed(&rg, seed)
    let resorig = vr.zeros(a, v.obs * k)
    var j = 0usize
    while j < k {
        var m = 0.0f64
        var t = 0usize
        while t < v.obs {
            m += v.resid[t * k + j]
            t += 1usize
        }
        m = m / f64(v.obs)
        t = 0usize
        while t < v.obs {
            resorig[t * k + j] = v.resid[t * k + j] - m
            t += 1usize
        }
        j += 1usize
    }
    var run = 0usize
    while run < runs {
        let mk = mem.mark(a)
        let (booted, se) = rng.sample_int(a, &rg, i64(v.obs), i64(v.obs), true)
        if se != ok { ret se }
        let ys = vr.zeros(a, v.t0 * k)
        vr.boot_series(v, resorig, booted, ys)
        let (vb, ne) = vr.var_new(a, ys, v.t0, k, v.p, v.det, v.season, v.exo, v.nexo)
        if ne != ok { ret ne }
        var sv: Svar = zero
        let fe = svar_fit(a, &vb, mode, amat, bmat, start, max_iter, conv, maxls, direct, &sv)
        if fe != ok { ret fe }
        let tmp = vr.zeros(a, blk)
        svar_irf(a, &vb, sv.a, sv.b, h, cumulative, tmp)
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
