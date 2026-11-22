// R mixtools boot.se (the parametric bootstrap standard errors) for the fits of normalmixEM, regmixEM, mvnormalmixEM and multmixEM with
// arbmean = TRUE, draw for draw: n rmultinom(1, 1, lambda) component draws, then the simulated responses, then the refit from the fitted
// values, repeated until B refits ran without a restart (a refit that restarts or fails is dropped and redrawn). The sample standard
// deviations of the B refits are the standard errors. With arbmean = FALSE the package fails (the scale it collects is NULL), and so is not here.
// Also here: perm, wquantile and wIQR, wkde, dmvnorm, ddirichlet, rnormmix and rmvnormmix (the helpers of the package).
//
// Not here: boot.se of the other families (logistic and Poisson regression, mixed effects, repeated measures), boot.comp.

use e.algo.rand.r as rg
use e.algo.rand.rdist as rd
use e.algo.stat.mixtools as mt
use e.algo.stat.mixtools_mult as mm
use e.algo.stat.mixtools_mv as mv
use e.algo.stat.mixtools_reg as rgm
use e.math
use e.math.nmath as nmath
use e.mem

// three parameter blocks, each rows by B row-major, and their standard errors (sample sd over the B refits)
type Boot = struct { r1: usize, r2: usize, r3: usize, p1: []f64, p2: []f64, p3: []f64, se1: []f64, se2: []f64, se3: []f64, nb: usize, draws: usize }

fn sd_rows(m: []const f64, rows: usize, nb: usize, out: []f64) {
    var r = 0usize
    while r < rows {
        out[r] = math.sqrt[f64](mt.rvar(m, r * nb, nb, 1usize))
        r += 1usize
    }
}

fn finish(a: *mem.Arena, r1: usize, r2: usize, r3: usize, p1: []f64, p2: []f64, p3: []f64, nb: usize, draws: usize) -> Boot {
    let s1 = mt.buf(a, r1)
    let s2 = mt.buf(a, r2)
    let s3 = mt.buf(a, r3)
    sd_rows(p1, r1, nb, s1)
    sd_rows(p2, r2, nb, s2)
    if r3 > 0usize { sd_rows(p3, r3, nb, s3) }
    ret Boot { r1: r1, r2: r2, r3: r3, p1: p1, p2: p2, p3: p3, se1: s1, se2: s2, se3: s3, nb: nb, draws: draws }
}

// R's FixupProb: prob divided by its (double) sum before rmultinom sees it
fn fixup(a: *mem.Arena, prob: []const f64) -> []f64 {
    let out = mt.buf(a, prob.len)
    var s = 0.0f64
    var i = 0usize
    while i < prob.len {
        s += prob[i]
        i += 1usize
    }
    i = 0usize
    while i < prob.len {
        out[i] = prob[i] / s
        i += 1usize
    }
    ret out
}

// component of one rmultinom(1, 1, prob) draw
fn draw_component(a: *mem.Arena, g: *rg.Rng, prob: []const f64) -> usize {
    let start = mem.mark(a)
    let (cnt, e) = rd.rmultinom(a, g, 1i64, fixup(a, prob))
    var c = 0usize
    if e == ok {
        var j = 0usize
        while j < prob.len {
            if cnt[j] == 1i64 { c = j }
            j += 1usize
        }
    }
    mem.reset(a, start)
    ret c
}

// boot.se of a normalmixEM fit: parameters lambda (k), mu (k), sigma (k, or 1 when !arbvar)
fn boot_se_normal(a: *mem.Arena, g: *rg.Rng, n: usize, k: usize, lambda: []const f64, mu: []const f64, sigma: []const f64, arbvar: bool, nboot: usize) -> Boot {
    let ns = sigma.len
    let p1 = mt.buf(a, k * nboot)
    let p2 = mt.buf(a, k * nboot)
    let p3 = mt.buf(a, ns * nboot)
    var j = 0usize
    var draws = 0usize
    while j < nboot {
        draws += 1usize
        let start = mem.mark(a)
        let comp = mt.ibuf(a, n)
        var i = 0usize
        while i < n {
            comp[i] = draw_component(a, g, lambda)
            i += 1usize
        }
        let ys = mt.buf(a, n)
        i = 0usize
        while i < n {
            var sd = sigma[0usize]
            if arbvar { sd = sigma[comp[i]] }
            ys[i] = rg.rnorm(g, mu[comp[i]], sd)
            i += 1usize
        }
        let (f, e) = mt.normal_mix_em(a, g, ys, lambda, mu, sigma, k, true, arbvar, 0.00000001f64, 1000usize, 20usize)
        if e == ok && f.restarts == 0usize {
            var q = 0usize
            while q < k {
                p1[q * nboot + j] = f.lambda[q]
                p2[q * nboot + j] = f.mu[q]
                q += 1usize
            }
            q = 0usize
            while q < ns {
                p3[q * nboot + j] = f.sigma[q]
                q += 1usize
            }
            j += 1usize
        }
        mem.reset(a, start)
    }
    ret finish(a, k, k, ns, p1, p2, p3, nboot, draws)
}

// boot.se of a regmixEM fit with an intercept: x is n by q row-major, beta p by k row-major (p = q + 1); parameters lambda, beta (column-major
// as.vector order: component by component), sigma
fn boot_se_reg(a: *mem.Arena, g: *rg.Rng, xp: []const f64, n: usize, q: usize, k: usize, lambda: []const f64, beta: []const f64, sigma: []const f64, arbvar: bool, nboot: usize) -> Boot {
    let p = q + 1usize
    let ns = sigma.len
    let p1 = mt.buf(a, k * nboot)
    let p2 = mt.buf(a, p * k * nboot)
    let p3 = mt.buf(a, ns * nboot)
    var j = 0usize
    var draws = 0usize
    while j < nboot {
        draws += 1usize
        let start = mem.mark(a)
        let comp = mt.ibuf(a, n)
        var i = 0usize
        while i < n {
            comp[i] = draw_component(a, g, lambda)
            i += 1usize
        }
        let ys = mt.buf(a, n)
        i = 0usize
        while i < n {
            var xb = beta[comp[i]]
            var l = 1usize
            while l < p {
                xb += xp[i * q + l - 1usize] * beta[l * k + comp[i]]
                l += 1usize
            }
            var sd = sigma[0usize]
            if arbvar { sd = sigma[comp[i]] }
            ys[i] = rg.rnorm(g, xb, sd)
            i += 1usize
        }
        let (f, e) = rgm.reg_mix_em(a, g, ys, xp, q, true, lambda, beta, sigma, k, true, arbvar, 0.00000001f64, 10000usize)
        if e == ok && f.restarts == 0usize {
            var c = 0usize
            while c < k {
                p1[c * nboot + j] = f.lambda[c]
                var l = 0usize
                while l < p {
                    p2[(c * p + l) * nboot + j] = f.beta[l * k + c]
                    l += 1usize
                }
                c += 1usize
            }
            c = 0usize
            while c < ns {
                p3[c * nboot + j] = f.sigma[c]
                c += 1usize
            }
            j += 1usize
        }
        mem.reset(a, start)
    }
    ret finish(a, k, p * k, ns, p1, p2, p3, nboot, draws)
}

// symmetric square root of the p by p row-major matrix s by cyclic Jacobi sweeps: out = V sqrt(D) V'
fn sym_sqrt(a: *mem.Arena, s: []const f64, p: usize, out: []f64) {
    let w = mt.buf(a, p * p)
    let v = mt.buf(a, p * p)
    var i = 0usize
    while i < p * p {
        w[i] = s[i]
        i += 1usize
    }
    i = 0usize
    while i < p {
        v[i * p + i] = 1.0f64
        i += 1usize
    }
    var sweep = 0usize
    while sweep < 60usize {
        var off = 0.0f64
        var r = 0usize
        while r < p {
            var c = r + 1usize
            while c < p {
                off += w[r * p + c] * w[r * p + c]
                c += 1usize
            }
            r += 1usize
        }
        if off < 1.0e-300f64 { break }
        r = 0usize
        while r < p {
            var c = r + 1usize
            while c < p {
                let apq = w[r * p + c]
                if apq != 0.0f64 {
                    let theta = (w[c * p + c] - w[r * p + r]) / (2.0f64 * apq)
                    var t = 1.0f64 / (math.abs[f64](theta) + math.sqrt[f64](theta * theta + 1.0f64))
                    if theta < 0.0f64 { t = 0.0f64 - t }
                    let cs = 1.0f64 / math.sqrt[f64](t * t + 1.0f64)
                    let sn = t * cs
                    var q = 0usize
                    while q < p {
                        let wq1 = w[q * p + r]
                        let wq2 = w[q * p + c]
                        w[q * p + r] = cs * wq1 - sn * wq2
                        w[q * p + c] = sn * wq1 + cs * wq2
                        q += 1usize
                    }
                    q = 0usize
                    while q < p {
                        let w1 = w[r * p + q]
                        let w2 = w[c * p + q]
                        w[r * p + q] = cs * w1 - sn * w2
                        w[c * p + q] = sn * w1 + cs * w2
                        q += 1usize
                    }
                    q = 0usize
                    while q < p {
                        let v1 = v[q * p + r]
                        let v2 = v[q * p + c]
                        v[q * p + r] = cs * v1 - sn * v2
                        v[q * p + c] = sn * v1 + cs * v2
                        q += 1usize
                    }
                }
                c += 1usize
            }
            r += 1usize
        }
        sweep += 1usize
    }
    var r2 = 0usize
    while r2 < p {
        var c2 = 0usize
        while c2 < p {
            var t = 0.0f64
            var q = 0usize
            while q < p {
                var ev = w[q * p + q]
                if ev < 0.0f64 { ev = 0.0f64 }
                t += v[r2 * p + q] * math.sqrt[f64](ev) * v[c2 * p + q]
                q += 1usize
            }
            out[r2 * p + c2] = t
            c2 += 1usize
        }
        r2 += 1usize
    }
}

// boot.se of an mvnormalmixEM fit: mu is k by p row-major, sigma k blocks of p by p (one block when !arbvar). Parameters: lambda, mu (component
// by component), sigma (block by block)
fn boot_se_mvnormal(a: *mem.Arena, g: *rg.Rng, n: usize, p: usize, k: usize, lambda: []const f64, mu: []const f64, sigma: []const f64, arbvar: bool, nboot: usize) -> Boot {
    var nb = 1usize
    if arbvar { nb = k }
    let p1 = mt.buf(a, k * nboot)
    let p2 = mt.buf(a, k * p * nboot)
    let p3 = mt.buf(a, nb * p * p * nboot)
    var j = 0usize
    var draws = 0usize
    while j < nboot {
        draws += 1usize
        let start = mem.mark(a)
        let comp = mt.ibuf(a, n)
        var i = 0usize
        while i < n {
            comp[i] = draw_component(a, g, lambda)
            i += 1usize
        }
        let roots = mt.buf(a, nb * p * p)
        var b = 0usize
        while b < nb {
            sym_sqrt(a, sigma[b * p * p..b * p * p + p * p], p, roots[b * p * p..b * p * p + p * p])
            b += 1usize
        }
        let ys = mt.buf(a, n * p)
        let zv = mt.buf(a, p)
        i = 0usize
        while i < n {
            var bi = 0usize
            if arbvar { bi = comp[i] }
            var c = 0usize
            while c < p {
                zv[c] = rg.rnorm(g, 0.0f64, 1.0f64)
                c += 1usize
            }
            c = 0usize
            while c < p {
                var t = 0.0f64
                var d = 0usize
                while d < p {
                    t += roots[bi * p * p + c * p + d] * zv[d]
                    d += 1usize
                }
                ys[i * p + c] = mu[comp[i] * p + c] + t
                c += 1usize
            }
            i += 1usize
        }
        let (f, e) = mv.mvnormal_mix_em(a, g, ys, n, p, lambda, mu, sigma, k, true, arbvar, 0.00000001f64, 10000usize)
        if e == ok && f.restarts == 0usize {
            var q = 0usize
            while q < k {
                p1[q * nboot + j] = f.lambda[q]
                q += 1usize
            }
            q = 0usize
            while q < k * p {
                p2[q * nboot + j] = f.mu[q]
                q += 1usize
            }
            q = 0usize
            while q < nb * p * p {
                p3[q * nboot + j] = f.sigma[q]
                q += 1usize
            }
            j += 1usize
        }
        mem.reset(a, start)
    }
    ret finish(a, k, k * p, nb * p * p, p1, p2, p3, nboot, draws)
}

// boot.se of a multmixEM fit: y is n by p counts, theta k by p row-major. Parameters: lambda, theta (as.vector order: column by column)
fn boot_se_mult(a: *mem.Arena, g: *rg.Rng, y: []const f64, n: usize, p: usize, k: usize, lambda: []const f64, theta: []const f64, nboot: usize) -> Boot {
    let p1 = mt.buf(a, k * nboot)
    let p2 = mt.buf(a, k * p * nboot)
    var j = 0usize
    var draws = 0usize
    while j < nboot {
        draws += 1usize
        let start = mem.mark(a)
        let comp = mt.ibuf(a, n)
        var i = 0usize
        while i < n {
            comp[i] = draw_component(a, g, lambda)
            i += 1usize
        }
        let ys = mt.buf(a, n * p)
        i = 0usize
        while i < n {
            var size = 0.0f64
            var c = 0usize
            while c < p {
                size += y[i * p + c]
                c += 1usize
            }
            let (cnt, e) = rd.rmultinom(a, g, i64(size), fixup(a, theta[comp[i] * p..comp[i] * p + p]))
            if e != ok { break }
            c = 0usize
            while c < p {
                ys[i * p + c] = f64(cnt[c])
                c += 1usize
            }
            i += 1usize
        }
        let empty0 = mt.buf(a, 0usize)
        let (f, e2) = mm.mult_mix_em(a, g, ys, n, p, lambda, theta, k, 10000usize, 0.00000001f64)
        if e2 == ok && f.restarts == 0usize {
            var q = 0usize
            while q < k {
                p1[q * nboot + j] = f.lambda[q]
                var c = 0usize
                while c < p {
                    p2[(c * k + q) * nboot + j] = f.theta[q * p + c]
                    c += 1usize
                }
                q += 1usize
            }
            j += 1usize
        }
        mem.reset(a, start)
    }
    ret finish(a, k, k * p, 0usize, p1, p2, mt.buf(a, 0usize), nboot, draws)
}

// perm(n, r, v): the arrangements of r of the n values of v in R's order, rows by r row-major; returns the row count
fn perm(a: *mem.Arena, n: usize, r: usize, v: []const f64, out: []f64) -> usize {
    if r == 1usize {
        var i = 0usize
        while i < n {
            out[i] = v[i]
            i += 1usize
        }
        ret n
    }
    if n == 1usize {
        var c = 0usize
        while c < r {
            out[c] = v[0usize]
            c += 1usize
        }
        ret 1usize
    }
    var rows = 0usize
    var i2 = 0usize
    while i2 < n {
        let rest = mt.buf(a, n - 1usize)
        var q = 0usize
        var w = 0usize
        while q < n {
            if q != i2 {
                rest[w] = v[q]
                w += 1usize
            }
            q += 1usize
        }
        var sub_cap = 1usize
        var f = 1usize
        var t = 0usize
        while t + 1usize < r {
            f = f * (n - 1usize - t)
            t += 1usize
        }
        sub_cap = f
        let sub = mt.buf(a, sub_cap * (r - 1usize) + 1usize)
        let sr = perm(a, n - 1usize, r - 1usize, rest, sub)
        var s = 0usize
        while s < sr {
            out[(rows + s) * r] = v[i2]
            var c = 0usize
            while c + 1usize < r {
                out[(rows + s) * r + 1usize + c] = sub[s * (r - 1usize) + c]
                c += 1usize
            }
            s += 1usize
        }
        rows += sr
        i2 += 1usize
    }
    ret rows
}

// wquantile(wt, x, probs, already.sorted = FALSE, already.normalized = FALSE) for one probability
fn wquantile(a: *mem.Arena, wt: []const f64, x: []const f64, prob: f64) -> f64 {
    let n = x.len
    let o = mt.order_of(a, x)
    var tot = mt.Acc { hi: 0.0f64, lo: 0.0f64 }
    var i = 0usize
    while i < n {
        mt.acc_add(&tot, wt[i])
        i += 1usize
    }
    let total = mt.acc_val(tot)
    var cs = mt.Acc { hi: 0.0f64, lo: 0.0f64 }
    var idx = 0usize
    i = 0usize
    while i < n {
        mt.acc_add(&cs, wt[o[i]] / total)
        if mt.acc_val(cs) <= prob { idx = i + 1usize }
        i += 1usize
    }
    if idx == 0usize { ret 0.0f64 / 0.0f64 }
    ret x[o[idx - 1usize]]
}

// wkde(x, u, w, bw): the weighted Gaussian kernel density estimate at u
fn wkde(x: []const f64, u: f64, w: []const f64, bw: f64) -> f64 {
    var tw = mt.Acc { hi: 0.0f64, lo: 0.0f64 }
    var i = 0usize
    while i < x.len {
        mt.acc_add(&tw, w[i])
        i += 1usize
    }
    let total = mt.acc_val(tw)
    var s = mt.Acc { hi: 0.0f64, lo: 0.0f64 }
    i = 0usize
    while i < x.len {
        let d = x[i] / bw - u / bw
        mt.acc_add(&s, (w[i] / total) * math.exp[f64](0.0f64 - d * d / 2.0f64))
        i += 1usize
    }
    ret mt.acc_val(s) / (bw * math.sqrt[f64](2.0f64 * 3.141592653589793238462643383279f64))
}

// ddirichlet(x, alpha)
fn ddirichlet(x: []const f64, alpha: []const f64) -> f64 {
    var sl = mt.Acc { hi: 0.0f64, lo: 0.0f64 }
    var sa = mt.Acc { hi: 0.0f64, lo: 0.0f64 }
    var s = mt.Acc { hi: 0.0f64, lo: 0.0f64 }
    var sx = mt.Acc { hi: 0.0f64, lo: 0.0f64 }
    var bad = false
    var i = 0usize
    while i < x.len {
        mt.acc_add(&sl, nmath.lgammafn(alpha[i]))
        mt.acc_add(&sa, alpha[i])
        mt.acc_add(&s, (alpha[i] - 1.0f64) * math.log[f64](x[i]))
        mt.acc_add(&sx, x[i])
        if x[i] < 0.0f64 || x[i] > 1.0f64 { bad = true }
        i += 1usize
    }
    var pd = math.exp[f64](mt.acc_val(s) - (mt.acc_val(sl) - nmath.lgammafn(mt.acc_val(sa))))
    if bad { pd = 0.0f64 }
    if mt.acc_val(sx) != 1.0f64 { pd = 0.0f64 }
    ret pd
}

// rnormmix(n, lambda, mu, sigma) = rmvnormmix with one column: z = sample(m, n, TRUE, prob = lambda), then rnorm over the rows
fn rnormmix(a: *mem.Arena, g: *rg.Rng, n: usize, lambda: []const f64, mu: []const f64, sigma: []const f64, out: []f64) -> err {
    let (z, e) = rd.sample_prob(a, g, lambda.len, n, true, lambda)
    if e != ok { ret e }
    var i = 0usize
    while i < n {
        out[i] = rg.rnorm(g, mu[usize(z[i]) - 1usize], sigma[usize(z[i]) - 1usize])
        i += 1usize
    }
    ret ok
}
