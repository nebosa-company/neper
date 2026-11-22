// R mixtools regmixEM: the EM fit of a mixture of linear regressions, value for value: regmix.init (a split of the y-ordered data in
// bins sized by lambda, lm per bin, sd and coefficient draws, including that the coefficient draws recycle the sd over the intercept),
// the weighted fits of lm (dqrls, through e.algo.linalg.decomp), the restart on any decrease of the log-likelihood, and that with
// arbmean = FALSE the package reorders the posterior twice. x is n by q row-major (the predictors); the intercept is added here.

use e.algo.linalg.decomp as dc
use e.algo.rand.r as rg
use e.algo.stat.mixtools as mt
use e.algo.stat.mixtools_mv as mv
use e.math
use e.mem

type Reg = struct { lambda: []f64, beta: []f64, sigma: []f64, scale: []f64, post: []f64, ll: []f64, loglik: f64, iter: usize, restarts: usize, k: usize, p: usize }

// R's round(): ties to even
fn r_round(x: f64) -> f64 {
    let f = math.floor[f64](x)
    let d = x - f
    if d < 0.5f64 { ret f }
    if d > 0.5f64 { ret f + 1.0f64 }
    var odd = f - 2.0f64 * math.floor[f64](f / 2.0f64)
    if odd == 0.0f64 { ret f }
    ret f + 1.0f64
}

// lm / lm.wfit coefficients of y on the n by p column-major design xc (rows scaled by sqrt(w) when w is not empty); rss of the unscaled fit
fn wfit(a: *mem.Arena, xc: []const f64, n: usize, p: usize, y: []const f64, w: []const f64, coef: []f64) -> f64 {
    let xs = mt.buf(a, n * p)
    let ys = mt.buf(a, n)
    var i = 0usize
    while i < n {
        var sw = 1.0f64
        if w.len > 0usize { sw = math.sqrt[f64](w[i]) }
        ys[i] = y[i] * sw
        var c = 0usize
        while c < p {
            xs[c * n + i] = xc[c * n + i] * sw
            c += 1usize
        }
        i += 1usize
    }
    let (f, e) = dc.lm_fit(a, xs, n, p, ys, 0.0000001f64)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var c2 = 0usize
    while c2 < p {
        coef[c2] = f.coef[c2]
        c2 += 1usize
    }
    var rss = 0.0f64
    i = 0usize
    while i < n {
        var r = y[i]
        c2 = 0usize
        while c2 < p {
            r -= xc[c2 * n + i] * coef[c2]
            c2 += 1usize
        }
        rss += r * r
        i += 1usize
    }
    ret rss
}

// regmix.init. xc is the n by p column-major design (intercept first when addint). lambda (k), beta (p by k row-major, or p when
// !arbmean) and s (k or 1) are filled; an empty lambda0, beta0 or s0 is NULL.
fn reg_init(a: *mem.Arena, g: *rg.Rng, y: []const f64, xc: []const f64, n: usize, p: usize, addint: bool, lambda0: []const f64, beta0: []const f64, s0: []const f64, k: usize, arbmean: bool, arbvar: bool, lambda: []f64, beta: []f64, s: []f64) -> usize {
    var i = 0usize
    var j = 0usize
    if lambda0.len == 0usize {
        var tot = 0.0f64
        j = 0usize
        while j < k {
            lambda[j] = rg.runif(g, 0.0f64, 1.0f64)
            tot += lambda[j]
            j += 1usize
        }
        j = 0usize
        while j < k {
            lambda[j] = lambda[j] / tot
            j += 1usize
        }
    } else {
        j = 0usize
        while j < k {
            lambda[j] = lambda0[j]
            j += 1usize
        }
    }
    let size = mt.ibuf(a, k)
    var small = true
    while small {
        small = false
        j = 0usize
        while j < k {
            size[j] = usize(r_round(lambda[j] * f64(n)))
            if size[j] < 4usize { small = true }
            j += 1usize
        }
        if small {
            var tot = 0.0f64
            j = 0usize
            while j < k {
                lambda[j] = rg.runif(g, 0.0f64, 1.0f64)
                tot += lambda[j]
                j += 1usize
            }
            j = 0usize
            while j < k {
                lambda[j] = lambda[j] / tot
                j += 1usize
            }
        }
    }
    var used = 0usize
    j = 0usize
    while j + 1usize < k {
        used += size[j]
        j += 1usize
    }
    size[k - 1usize] = n - used
    let ord = mt.order_of(a, y)
    let shyp = mt.buf(a, k)
    let hyp = mt.buf(a, p * k)
    var start = 0usize
    j = 0usize
    while j < k {
        let m = size[j]
        let xb = mt.buf(a, m * p)
        let yb = mt.buf(a, m)
        i = 0usize
        while i < m {
            yb[i] = y[ord[start + i]]
            var c = 0usize
            while c < p {
                xb[c * m + i] = xc[c * n + ord[start + i]]
                c += 1usize
            }
            i += 1usize
        }
        let cf = mt.buf(a, p)
        let rss = wfit(a, xb, m, p, yb, yb[0usize..0usize], cf)
        var h = math.sqrt[f64](rss / f64(m - p))
        if m <= p || h != h || h <= 0.0f64 { h = 1.0f64 }
        shyp[j] = h
        var c3 = 0usize
        while c3 < p {
            hyp[c3 * k + j] = cf[c3]
            c3 += 1usize
        }
        start += m
        j += 1usize
    }
    var shyp_scalar = false
    var shyp_mean = 0.0f64
    if s0.len == 0usize {
        if arbvar {
            j = 0usize
            while j < k {
                s[j] = 1.0f64 / rg.rexp(g, 1.0f64 / shyp[j])
                j += 1usize
            }
        } else {
            shyp_mean = mt.rmean(shyp, 0usize, k, 1usize)
            shyp_scalar = true
            s[0usize] = 1.0f64 / rg.rexp(g, 1.0f64 / shyp_mean)
        }
    } else {
        j = 0usize
        while j < s0.len {
            s[j] = s0[j]
            j += 1usize
        }
    }
    if beta0.len == 0usize {
        // x.x = solve(t(x) %*% x) over the predictors (the intercept column dropped when added), diag recycled over the p draws
        var q = p
        var off = 0usize
        if addint {
            q = p - 1usize
            off = 1usize
        }
        let xtx = mt.buf(a, q * q)
        var r = 0usize
        while r < q {
            var c = 0usize
            while c < q {
                var sacc = 0.0f64
                i = 0usize
                while i < n {
                    sacc += xc[(off + r) * n + i] * xc[(off + c) * n + i]
                    i += 1usize
                }
                xtx[r * q + c] = sacc
                c += 1usize
            }
            r += 1usize
        }
        let inv = mt.buf(a, q * q)
        let _ = mv.inv_det(a, xtx, q, inv)
        j = 0usize
        while j < k {
            var hsel = 0.0f64
            if shyp_scalar { hsel = shyp_mean } else {
                if arbvar { hsel = shyp[j] } else { hsel = shyp[0usize] }
            }
            var l = 0usize
            while l < p {
                beta[l * k + j] = rg.rnorm(g, hyp[l * k + j], hsel * math.sqrt[f64](inv[(l % q) * q + (l % q)]))
                l += 1usize
            }
            j += 1usize
        }
        if !arbmean {
            var l = 0usize
            while l < p {
                beta[l] = mt.rmean(beta, l * k, k, 1usize)
                l += 1usize
            }
        }
    } else {
        i = 0usize
        while i < beta0.len {
            beta[i] = beta0[i]
            i += 1usize
        }
    }
    ret k
}

// squared residuals, n by k row-major (the same column for every component when !arbmean)
fn reg_res(xc: []const f64, y: []const f64, n: usize, p: usize, k: usize, beta: []const f64, arbmean: bool, res: []f64) {
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < k {
            var xb = 0.0f64
            var l = 0usize
            while l < p {
                if arbmean { xb += xc[l * n + i] * beta[l * k + j] } else { xb += xc[l * n + i] * beta[l] }
                l += 1usize
            }
            res[i * k + j] = (y[i] - xb) * (y[i] - xb)
            j += 1usize
        }
        i += 1usize
    }
}

fn comp_loglik(res: []const f64, n: usize, k: usize, lambda: []const f64, s: []const f64, arbvar: bool) -> f64 {
    var tot = mt.Acc { hi: 0.0f64, lo: 0.0f64 }
    var i = 0usize
    while i < n {
        var rs = 0.0f64
        var j = 0usize
        while j < k {
            var sj = s[0usize]
            if arbvar { sj = s[j] }
            rs += lambda[j] / math.sqrt[f64](2.0f64 * 3.141592653589793238462643383279f64 * sj * sj) * math.exp[f64](0.0f64 - res[i * k + j] / (2.0f64 * sj * sj))
            j += 1usize
        }
        mt.acc_add(&tot, math.log[f64](rs))
        i += 1usize
    }
    ret mt.acc_val(tot)
}

// the dnorm-based log-likelihood of the M-step
fn dnorm_loglik(xc: []const f64, y: []const f64, n: usize, p: usize, k: usize, lambda: []const f64, beta: []const f64, s: []const f64, arbmean: bool, arbvar: bool) -> f64 {
    var tot = mt.Acc { hi: 0.0f64, lo: 0.0f64 }
    var i = 0usize
    while i < n {
        var rs = 0.0f64
        var j = 0usize
        while j < k {
            var xb = 0.0f64
            var l = 0usize
            while l < p {
                if arbmean { xb += xc[l * n + i] * beta[l * k + j] } else { xb += xc[l * n + i] * beta[l] }
                l += 1usize
            }
            var sj = s[0usize]
            if arbvar { sj = s[j] }
            let zz = math.abs[f64]((y[i] - xb) / sj)
            // R's dnorm4: the plain formula below 5, a split of the exponent above, zero past the underflow point
            var dens = 0.0f64
            if zz < 5.0f64 {
                dens = 0.398942280401432677939946059934f64 * math.exp[f64](0.0f64 - 0.5f64 * zz * zz) / sj
            } else {
                if zz < 38.56804f64 {
                    let x1 = math.floor[f64](zz * 65536.0f64 + 0.5f64) / 65536.0f64
                    let x2 = zz - x1
                    dens = 0.398942280401432677939946059934f64 / sj * (math.exp[f64](0.0f64 - 0.5f64 * x1 * x1) * math.exp[f64]((0.0f64 - 0.5f64 * x2 - x1) * x2))
                }
            }
            rs += lambda[j] * dens
            j += 1usize
        }
        mt.acc_add(&tot, math.log[f64](rs))
        i += 1usize
    }
    ret mt.acc_val(tot)
}

// regmixEM(y, x, lambda, beta, sigma, k, addintercept, arbmean, arbvar, epsilon, maxit)
fn reg_mix_em(a: *mem.Arena, g: *rg.Rng, y: []const f64, xp: []const f64, q: usize, addint: bool, lambda0: []const f64, beta0: []const f64, s0: []const f64, k: usize, arbmean: bool, arbvar: bool, epsilon: f64, maxit: usize) -> (Reg, err) {
    var empty: Reg = zero
    let n = y.len
    var p = q
    if addint { p = q + 1usize }
    let xc = mt.buf(a, n * p)
    var i = 0usize
    while i < n {
        var c = 0usize
        if addint { xc[i] = 1.0f64 }
        while c < q {
            if addint { xc[(c + 1usize) * n + i] = xp[i * q + c] } else { xc[c * n + i] = xp[i * q + c] }
            c += 1usize
        }
        i += 1usize
    }
    let lambda = mt.buf(a, k)
    let beta = mt.buf(a, p * k)
    let s = mt.buf(a, k)
    let res = mt.buf(a, n * k)
    let z = mt.buf(a, n * k)
    let lamn = mt.buf(a, k)
    let betan = mt.buf(a, p * k)
    let sn = mt.buf(a, k)
    let ll = mt.buf(a, maxit + 2usize)
    let wv = mt.buf(a, n)
    let _ = reg_init(a, g, y, xc, n, p, addint, lambda0, beta0, s0, k, arbmean, arbvar, lambda, beta, s)
    reg_res(xc, y, n, p, k, beta, arbmean, res)
    var obs = comp_loglik(res, n, k, lambda, s, arbvar)
    var nll = 0usize
    ll[nll] = obs
    nll += 1usize
    var diff = 1.0f64
    var iter = 0usize
    var restarts = 0usize
    var newobs = 0.0f64
    while diff > epsilon && iter < maxit {
        i = 0usize
        while i < n {
            var rs = 0.0f64
            var j = 0usize
            while j < k {
                var sj = s[0usize]
                if arbvar { sj = s[j] }
                var den = 0.0f64
                var h = 0usize
                while h < k {
                    var sh = s[0usize]
                    if arbvar { sh = s[h] }
                    den += (lambda[h] / lambda[j]) * (sj / sh) * math.exp[f64](0.0f64 - 0.5f64 * ((1.0f64 / (sh * sh)) * res[i * k + h] - (1.0f64 / (sj * sj)) * res[i * k + j]))
                    h += 1usize
                }
                z[i * k + j] = 1.0f64 / den
                rs += z[i * k + j]
                j += 1usize
            }
            j = 0usize
            while j < k {
                z[i * k + j] = z[i * k + j] / rs
                j += 1usize
            }
            i += 1usize
        }
        mt.col_means(z, n, k, lamn)
        var sing = false
        var j2 = 0usize
        while j2 < k {
            if lamn[j2] < 0.00000001f64 || lamn[j2] != lamn[j2] { sing = true }
            j2 += 1usize
        }
        if !sing {
            if !arbmean {
                i = 0usize
                while i < n {
                    var sw = 0.0f64
                    var j = 0usize
                    while j < k {
                        var sj = s[0usize]
                        if arbvar { sj = s[j] }
                        sw += z[i * k + j] / (sj * sj)
                        j += 1usize
                    }
                    wv[i] = sw
                    i += 1usize
                }
                let cf = mt.buf(a, p)
                let _ = wfit(a, xc, n, p, y, wv, cf)
                var l = 0usize
                while l < p {
                    betan[l] = cf[l]
                    l += 1usize
                }
            } else {
                var j = 0usize
                while j < k {
                    i = 0usize
                    while i < n {
                        wv[i] = z[i * k + j]
                        i += 1usize
                    }
                    let cf = mt.buf(a, p)
                    let _ = wfit(a, xc, n, p, y, wv, cf)
                    var l = 0usize
                    while l < p {
                        betan[l * k + j] = cf[l]
                        l += 1usize
                    }
                    j += 1usize
                }
            }
            reg_res(xc, y, n, p, k, betan, arbmean, res)
            if arbvar {
                var j = 0usize
                while j < k {
                    var num = 0.0f64
                    var den = 0.0f64
                    i = 0usize
                    while i < n {
                        num += z[i * k + j] * res[i * k + j]
                        den += z[i * k + j]
                        i += 1usize
                    }
                    sn[j] = math.sqrt[f64](num / den)
                    j += 1usize
                }
            } else {
                var num = 0.0f64
                i = 0usize
                while i < n * k {
                    num += z[i] * res[i]
                    i += 1usize
                }
                sn[0usize] = math.sqrt[f64](num / f64(n))
            }
            var jj = 0usize
            while jj < k {
                lambda[jj] = lamn[jj]
                jj += 1usize
            }
            jj = 0usize
            while jj < p * k {
                beta[jj] = betan[jj]
                jj += 1usize
            }
            jj = 0usize
            while jj < k {
                s[jj] = sn[jj]
                jj += 1usize
            }
            var ns = 1usize
            if arbvar { ns = k }
            jj = 0usize
            while jj < ns {
                if s[jj] < 0.00000001f64 { sing = true }
                jj += 1usize
            }
            newobs = dnorm_loglik(xc, y, n, p, k, lambda, beta, s, arbmean, arbvar)
        }
        if sing || newobs != newobs || newobs < obs || math.abs[f64](newobs) == 1.0f64 / 0.0f64 {
            restarts += 1usize
            if restarts > 15usize { ret (empty, mt.TooManyTries) }
            let _ = reg_init(a, g, y, xc, n, p, addint, lambda0[0usize..0usize], beta0[0usize..0usize], s0[0usize..0usize], k, arbmean, arbvar, lambda, beta, s)
            diff = 1.0f64
            iter = 0usize
            reg_res(xc, y, n, p, k, beta, arbmean, res)
            obs = comp_loglik(res, n, k, lambda, s, arbvar)
            nll = 0usize
            ll[nll] = obs
            nll += 1usize
        } else {
            diff = newobs - obs
            obs = newobs
            ll[nll] = obs
            nll += 1usize
            iter += 1usize
        }
    }
    var out = Reg { lambda: lambda, beta: beta, sigma: s, scale: s, post: z, ll: ll[0usize..nll], loglik: obs, iter: iter, restarts: restarts, k: k, p: p }
    if !arbmean {
        let ord = mt.order_of(a, s[0usize..k])
        let lam2 = mt.buf(a, k)
        let sc = mt.buf(a, k)
        let post2 = mt.buf(a, n * k)
        let smin = s[ord[0usize]]
        var jq = 0usize
        while jq < k {
            lam2[jq] = lambda[ord[jq]]
            sc[jq] = s[ord[jq]] / smin
            var ii = 0usize
            while ii < n {
                // z[, ord] and then z[, ord] again, as the package does
                post2[ii * k + jq] = z[ii * k + ord[ord[jq]]]
                ii += 1usize
            }
            jq += 1usize
        }
        let sg1 = mt.buf(a, 1usize)
        sg1[0usize] = smin
        out.lambda = lam2
        out.scale = sc
        out.post = post2
        out.sigma = sg1
    }
    ret (out, ok)
}
