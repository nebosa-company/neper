// R mixtools npEM (the EM-like fit of a nonparametric mixture with repeated measures, same or per-component bandwidths, stochastic
// variant) and spEMsymloc (the semiparametric symmetric location mixture), value for value: the starting partition from stats::kmeans
// (Hartigan-Wong as in e.algo.stat.fpc_km, the centers given or drawn), the C kernels KDErepeated, KDErepeatedbw and KDEsymloc, the
// weighted IQR bandwidth update and the stopping rules. Data are n by r row-major.
//
// Not here: kmeans with a single cluster (m = 1 for spEMsymloc), the list printing, and the other np* fits (mvnpEM, npMSL, spEM, ...).

use e.algo.rand.r as rg
use e.algo.rand.rdist as rd
use e.algo.stat.fpc_km as km
use e.algo.stat.mixtools as mt
use e.math
use e.mem

type Np = struct { post: []f64, lambda: []f64, bw: []f64, lambdahat: []f64, loglik: []f64, mu: []f64, muhat: []f64, iter: usize, m: usize }

// kmeans partition: z[i, cluster - 1] = 1. centers0 is m by r row-major (empty: m random rows as R draws them).
fn start_partition(a: *mem.Arena, g: *rg.Rng, x: []const f64, n: usize, r: usize, m: usize, centers0: []const f64, z: []f64) -> err {
    let cl = mt.ibuf(a, n + 1usize)
    if centers0.len > 0usize {
        let c = mt.buf(a, m * r)
        var i = 0usize
        while i < m * r {
            c[i] = centers0[i]
            i += 1usize
        }
        let nc = mt.ibuf(a, m + 1usize)
        let wss = mt.buf(a, m)
        let (flt, it, e) = km.kmns(a, x, n, r, c, m, 10usize, cl, nc, wss)
        if e != ok { ret e }
        if flt == 1usize || flt == 3usize { ret km.Malformed }
    } else {
        let cent = mt.buf(a, m * r)
        let wss = mt.buf(a, m)
        let size = mt.ibuf(a, m + 1usize)
        let info = mt.buf(a, 8usize)
        let (flt, e) = km.kmeans_hw(a, g, x, n, r, m, 10usize, 1usize, cl, cent, wss, size, info)
        if e != ok { ret e }
        if flt == 1usize || flt == 3usize { ret km.Malformed }
    }
    var i2 = 0usize
    while i2 < n * m {
        z[i2] = 0.0f64
        i2 += 1usize
    }
    i2 = 0usize
    while i2 < n {
        z[i2 * m + cl[i2 + 1usize] - 1usize] = 1.0f64
        i2 += 1usize
    }
    ret ok
}

// t(apply(z.hat, 1, function(prob) rmultinom(1, 1, prob)))
fn one_hot_draw(a: *mem.Arena, g: *rg.Rng, zhat: []const f64, n: usize, m: usize, out: []f64) -> err {
    var i = 0usize
    while i < n {
        let start = mem.mark(a)
        let (cnt, e) = rd.rmultinom(a, g, 1i64, zhat[i * m..i * m + m])
        if e != ok { ret e }
        var j = 0usize
        while j < m {
            out[i * m + j] = f64(cnt[j])
            j += 1usize
        }
        mem.reset(a, start)
        i += 1usize
    }
    ret ok
}

// normalise by column, columns with no mass get 1/n
fn col_norm(zin: []const f64, n: usize, m: usize, out: []f64) {
    var j = 0usize
    while j < m {
        var acs = mt.Acc { hi: 0.0f64, lo: 0.0f64 }
        var i = 0usize
        while i < n {
            mt.acc_add(&acs, zin[i * m + j])
            i += 1usize
        }
        let cs = mt.acc_val(acs)
        i = 0usize
        while i < n {
            if cs == 0.0f64 { out[i * m + j] = 1.0f64 / f64(n) } else { out[i * m + j] = zin[i * m + j] / cs }
            i += 1usize
        }
        j += 1usize
    }
}

// C KDErepeated / KDErepeatedbw for the block columns cols (r2 of them) of x: f (n by m) the r2-fold KDE products, hh one bandwidth per component
fn kde_repeated(x: []const f64, n: usize, r: usize, cols: []const usize, m: usize, hh: []const f64, samebw: bool, z: []const f64, f: []f64) {
    let r2 = cols.len
    var j = 0usize
    while j < m {
        var h = hh[0usize]
        if !samebw { h = hh[j] }
        let c1 = 0.0f64 - 0.5f64 / (h * h)
        var c2 = 0.39894228040143267794f64 / (h * f64(r2))
        if !samebw { c2 = 0.39894228040143267794f64 / f64(r2) }
        var i = 0usize
        while i < n {
            f[i * m + j] = 1.0f64
            var k = 0usize
            while k < r2 {
                var sum1 = 0.0f64
                let xik = x[i * r + cols[k]]
                var ii = 0usize
                while ii < n {
                    var sum2 = 0.0f64
                    var kk = 0usize
                    while kk < r2 {
                        let tmp = xik - x[ii * r + cols[kk]]
                        sum2 += math.exp[f64](tmp * tmp * c1)
                        kk += 1usize
                    }
                    sum1 += z[ii * m + j] * sum2
                    ii += 1usize
                }
                if samebw { f[i * m + j] *= sum1 * c2 } else { f[i * m + j] *= sum1 * c2 / h }
                k += 1usize
            }
            i += 1usize
        }
        j += 1usize
    }
}

// npEM(x, mu0, blockid, bw, samebw, eps, maxiter, stochastic). centers0 is m by r row-major or empty (m random rows); bw is the scalar
// (samebw) or an nb by m matrix row-major (the starting values; only the shape matters when not samebw) -- pass bw0 of length 1 to fill it.
fn np_em(a: *mem.Arena, g: *rg.Rng, x: []const f64, n: usize, r: usize, m: usize, centers0: []const f64, blockid: []const usize, bw0: f64, samebw: bool, eps: f64, maxiter: usize, stochastic: bool) -> (Np, err) {
    var empty: Np = zero
    // u = match(blockid, unique(blockid))
    let u = mt.ibuf(a, r)
    let uniq = mt.ibuf(a, r)
    var nu = 0usize
    var c = 0usize
    while c < r {
        var found = nu
        var q = 0usize
        while q < nu {
            if uniq[q] == blockid[c] { found = q }
            q += 1usize
        }
        if found == nu {
            uniq[nu] = blockid[c]
            nu += 1usize
        }
        u[c] = found
        c += 1usize
    }
    let nb = nu
    var bw = mt.buf(a, nb * m)
    var j = 0usize
    while j < nb * m {
        bw[j] = bw0
        j += 1usize
    }
    let zhat = mt.buf(a, n * m)
    if m == 1usize {
        j = 0usize
        while j < n {
            zhat[j] = 1.0f64
            j += 1usize
        }
    } else {
        let e0 = start_partition(a, g, x, n, r, m, centers0, zhat)
        if e0 != ok { ret (empty, e0) }
    }
    let lambda = mt.buf(a, maxiter * m)
    let loglik = mt.buf(a, maxiter)
    let sumpost = mt.buf(a, n * m)
    let zdraw = mt.buf(a, n * m)
    let ztmp = mt.buf(a, n * m)
    let fk = mt.buf(a, n * m)
    let ff = mt.buf(a, n * m)
    let bwold = mt.buf(a, nb * m)
    let hrow = mt.buf(a, m)
    var iter = 0usize
    var finished = false
    while !finished {
        iter += 1usize
        j = 0usize
        while j < nb * m {
            bwold[j] = bw[j]
            j += 1usize
        }
        let lam = lambda[(iter - 1usize) * m..iter * m]
        mt.col_means(zhat, n, m, lam)
        if stochastic {
            let e1 = one_hot_draw(a, g, zhat, n, m, zdraw)
            if e1 != ok { ret (empty, e1) }
            col_norm(zdraw, n, m, ztmp)
        } else {
            col_norm(zhat, n, m, ztmp)
        }
        j = 0usize
        while j < n * m {
            fk[j] = 1.0f64
            j += 1usize
        }
        j = 0usize
        while j < m {
            hrow[j] = bw0
            j += 1usize
        }
        var blk = 0usize
        while blk < nb {
            let cols = mt.ibuf(a, r)
            var r2 = 0usize
            c = 0usize
            while c < r {
                if u[c] == blk {
                    cols[r2] = c
                    r2 += 1usize
                }
                c += 1usize
            }
            let cl = cols[0usize..r2]
            if !samebw {
                // weighted variances and IQRs of the block's pooled coordinates, per component
                let tot = n * r2
                let xx = mt.buf(a, tot)
                var kq = 0usize
                while kq < r2 {
                    var i = 0usize
                    while i < n {
                        xx[kq * n + i] = x[i * r + cl[kq]]
                        i += 1usize
                    }
                    kq += 1usize
                }
                let ord = mt.order_of(a, xx)
                var jc = 0usize
                while jc < m {
                    var macc = mt.Acc { hi: 0.0f64, lo: 0.0f64 }
                    var t = 0usize
                    while t < tot {
                        mt.acc_add(&macc, (ztmp[(t % n) * m + jc] / f64(r2)) * xx[t])
                        t += 1usize
                    }
                    let mean = mt.acc_val(macc)
                    var vacc = mt.Acc { hi: 0.0f64, lo: 0.0f64 }
                    t = 0usize
                    while t < tot {
                        let d = xx[t] - mean
                        mt.acc_add(&vacc, (ztmp[(t % n) * m + jc] / f64(r2)) * (d * d))
                        t += 1usize
                    }
                    let variance = mt.acc_val(vacc)
                    // wquantile at 0.25 and 0.75 over the sorted values with cumulated weights
                    var cs = mt.Acc { hi: 0.0f64, lo: 0.0f64 }
                    var n25 = 0usize
                    var n75 = 0usize
                    t = 0usize
                    while t < tot {
                        mt.acc_add(&cs, ztmp[(ord[t] % n) * m + jc] / f64(r2))
                        if mt.acc_val(cs) <= 0.25f64 { n25 = t + 1usize }
                        if mt.acc_val(cs) <= 0.75f64 { n75 = t + 1usize }
                        t += 1usize
                    }
                    var q25 = 0.0f64
                    var q75 = 0.0f64
                    if n25 > 0usize { q25 = xx[ord[n25 - 1usize]] }
                    if n75 > 0usize { q75 = xx[ord[n75 - 1usize]] }
                    let iqr = q75 - q25
                    var sdv = math.sqrt[f64](variance)
                    if iqr / 1.34f64 < sdv { sdv = iqr / 1.34f64 }
                    var sz = f64(r2) * f64(n) * lam[jc]
                    if sz < 1.0f64 { sz = 1.0f64 }
                    let hv = 0.9f64 * sdv * math.pow[f64](sz, 0.0f64 - 0.2f64)
                    bw[blk * m + jc] = hv
                    hrow[jc] = hv
                    jc += 1usize
                }
            }
            kde_repeated(x, n, r, cl, m, hrow, samebw, ztmp, ff)
            j = 0usize
            while j < n * m {
                fk[j] *= ff[j]
                j += 1usize
            }
            blk += 1usize
        }
        var ll = mt.Acc { hi: 0.0f64, lo: 0.0f64 }
        var i = 0usize
        while i < n {
            var rs = 0.0f64
            j = 0usize
            while j < m {
                rs += fk[i * m + j] * lam[j]
                j += 1usize
            }
            j = 0usize
            while j < m {
                zhat[i * m + j] = fk[i * m + j] * lam[j] / rs
                j += 1usize
            }
            mt.acc_add(&ll, math.log[f64](rs))
            i += 1usize
        }
        loglik[iter - 1usize] = mt.acc_val(ll)
        finished = iter >= maxiter
        if stochastic {
            j = 0usize
            while j < n * m {
                sumpost[j] += zhat[j]
                j += 1usize
            }
        } else {
            if iter > 1usize {
                var mc = 0.0f64
                j = 0usize
                while j < m {
                    var d = lambda[(iter - 1usize) * m + j] - lambda[(iter - 2usize) * m + j]
                    if d < 0.0f64 { d = 0.0f64 - d }
                    if d > mc { mc = d }
                    j += 1usize
                }
                if !samebw {
                    j = 0usize
                    while j < nb * m {
                        var d = bwold[j] - bw[j]
                        if d < 0.0f64 { d = 0.0f64 - d }
                        if d > mc { mc = d }
                        j += 1usize
                    }
                }
                if mc < eps { finished = true }
            }
        }
    }
    let lamhat = mt.buf(a, m)
    var post = zhat
    var nl = iter
    if stochastic {
        post = mt.buf(a, n * m)
        j = 0usize
        while j < n * m {
            post[j] = sumpost[j] / f64(iter)
            j += 1usize
        }
        nl = maxiter
        mt.col_means(lambda, maxiter, m, lamhat)
    } else {
        j = 0usize
        while j < m {
            lamhat[j] = lambda[(iter - 1usize) * m + j]
            j += 1usize
        }
    }
    var np = Np { post: post, lambda: lambda[0usize..nl * m], bw: bw, lambdahat: lamhat, loglik: loglik[0usize..iter], mu: lambda[0usize..0usize], muhat: lamhat[0usize..0usize], iter: iter, m: m }
    ret (np, ok)
}

// C KDEsymloc: f (n by m) the symmetric KDE at x_a - mu_b; z is the (unnormalised) posterior or indicator matrix
fn kde_symloc(n: usize, m: usize, mu: []const f64, x: []const f64, h: f64, z: []const f64, f: []f64) {
    let c1 = 0.0f64 - 1.0f64 / (2.0f64 * h * h)
    let c2 = 0.39894228040143267794f64 / (2.0f64 * h * f64(n))
    var aa = 0usize
    while aa < n {
        var b = 0usize
        while b < m {
            var sum = 0.0f64
            let u1 = x[aa] - mu[b]
            var i = 0usize
            while i < n {
                var j = 0usize
                while j < m {
                    let u2 = x[i] - mu[j]
                    let t1 = u1 - u2
                    let t2 = 0.0f64 - u1 - u2
                    sum += z[i * m + j] * (math.exp[f64](t1 * t1 * c1) + math.exp[f64](t2 * t2 * c1))
                    j += 1usize
                }
                i += 1usize
            }
            f[aa * m + b] = sum * c2
            b += 1usize
        }
        aa += 1usize
    }
}

// spEMsymloc(x, mu0, bw, eps, maxiter, stochastic); centers0 holds the m given centers, or is empty for m random ones
fn sp_em_symloc(a: *mem.Arena, g: *rg.Rng, x: []const f64, m: usize, centers0: []const f64, bw: f64, eps: f64, maxiter: usize, stochastic: bool) -> (Np, err) {
    var empty: Np = zero
    let n = x.len
    let zhat = mt.buf(a, n * m)
    let e0 = start_partition(a, g, x, n, 1usize, m, centers0, zhat)
    if e0 != ok { ret (empty, e0) }
    let lambda = mt.buf(a, maxiter * m)
    let mu = mt.buf(a, maxiter * m)
    let sumpost = mt.buf(a, n * m)
    let zdraw = mt.buf(a, n * m)
    let fk = mt.buf(a, n * m)
    var iter = 0usize
    var finished = false
    while !finished {
        iter += 1usize
        let lam = lambda[(iter - 1usize) * m..iter * m]
        let mur = mu[(iter - 1usize) * m..iter * m]
        mt.col_means(zhat, n, m, lam)
        var j = 0usize
        while j < m {
            var s = mt.Acc { hi: 0.0f64, lo: 0.0f64 }
            var i = 0usize
            while i < n {
                mt.acc_add(&s, zhat[i * m + j] * x[i])
                i += 1usize
            }
            mur[j] = (mt.acc_val(s) / f64(n)) / lam[j]
            j += 1usize
        }
        if stochastic {
            let e1 = one_hot_draw(a, g, zhat, n, m, zdraw)
            if e1 != ok { ret (empty, e1) }
            kde_symloc(n, m, mur, x, bw, zdraw, fk)
        } else {
            kde_symloc(n, m, mur, x, bw, zhat, fk)
        }
        var i2 = 0usize
        while i2 < n {
            var rs = 0.0f64
            j = 0usize
            while j < m {
                rs += fk[i2 * m + j] * lam[j]
                j += 1usize
            }
            j = 0usize
            while j < m {
                zhat[i2 * m + j] = fk[i2 * m + j] * lam[j] / rs
                j += 1usize
            }
            i2 += 1usize
        }
        finished = iter >= maxiter
        if stochastic {
            j = 0usize
            while j < n * m {
                sumpost[j] += zhat[j]
                j += 1usize
            }
        } else {
            if iter > 1usize {
                var mc = 0.0f64
                j = 0usize
                while j < m {
                    var d1 = lambda[(iter - 1usize) * m + j] - lambda[(iter - 2usize) * m + j]
                    if d1 < 0.0f64 { d1 = 0.0f64 - d1 }
                    if d1 > mc { mc = d1 }
                    var d2 = mu[(iter - 1usize) * m + j] - mu[(iter - 2usize) * m + j]
                    if d2 < 0.0f64 { d2 = 0.0f64 - d2 }
                    if d2 > mc { mc = d2 }
                    j += 1usize
                }
                if mc < eps { finished = true }
            }
        }
    }
    let lamhat = mt.buf(a, m)
    let muhat = mt.buf(a, m)
    var post = zhat
    var nl = iter
    var j3 = 0usize
    if stochastic {
        post = mt.buf(a, n * m)
        while j3 < n * m {
            post[j3] = sumpost[j3] / f64(iter)
            j3 += 1usize
        }
        nl = maxiter
        mt.col_means(lambda, maxiter, m, lamhat)
        mt.col_means(mu, maxiter, m, muhat)
    } else {
        while j3 < m {
            lamhat[j3] = lambda[(iter - 1usize) * m + j3]
            muhat[j3] = mu[(iter - 1usize) * m + j3]
            j3 += 1usize
        }
    }
    ret (Np { post: post, lambda: lambda[0usize..nl * m], bw: lamhat[0usize..0usize], lambdahat: lamhat, loglik: lamhat[0usize..0usize], mu: mu[0usize..nl * m], muhat: muhat, iter: iter, m: m }, ok)
}
