// R MCMCpack::MCMChregress: the Gibbs sampler of cMCMChregress.cc (Chib and Carlin algorithm 2 for beta, then b_k, Vb through Scythe's rwish, sigma2) on the
// Scythe Mersenne-Twister of e.algo.stat.mcmcpacksamp, in the draw order of the C++. Matrices are row-major slices.

use e.algo.stat.mcmcpacksamp as ms
use e.math
use e.mem

// out (r x c) = a (r x m) * b (m x c)
fn mm(a: []const f64, r: usize, m: usize, b: []const f64, c: usize, out: []f64) {
    var i = 0usize
    while i < r {
        var j = 0usize
        while j < c {
            var s = 0.0f64
            var t = 0usize
            while t < m {
                s += a[i * m + t] * b[t * c + j]
                t += 1usize
            }
            out[i * c + j] = s
            j += 1usize
        }
        i += 1usize
    }
}

// mu + chol(sig) * z with z drawn as p standard normals: Scythe's rmvnorm
fn rmvn(a: *mem.Arena, g: *ms.Sc, mu: []const f64, sig: []const f64, p: usize, out: []f64) -> err {
    let (l, e1) = mem.alloc[f64](a, p * p)
    let (z, e2) = mem.alloc[f64](a, p)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if !ms.chol(sig, p, l) { ret ms.NotPd }
    var i = 0usize
    while i < p {
        z[i] = ms.sc_rnorm(g, 0.0f64, 1.0f64)
        i += 1usize
    }
    i = 0usize
    while i < p {
        var s = 0.0f64
        var j = 0usize
        while j <= i {
            s += l[i * p + j] * z[j]
            j += 1usize
        }
        out[i] = mu[i] + s
        i += 1usize
    }
    ret ok
}

// Scythe rwish(v, S): the sum of v outer products of chol(S) * z
fn rwish_sc(a: *mem.Arena, g: *ms.Sc, v: usize, s: []const f64, p: usize, out: []f64) -> err {
    let (l, e1) = mem.alloc[f64](a, p * p)
    let (z, e2) = mem.alloc[f64](a, p)
    let (al, e3) = mem.alloc[f64](a, p)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if !ms.chol(s, p, l) { ret ms.NotPd }
    var i = 0usize
    while i < p * p {
        out[i] = 0.0f64
        i += 1usize
    }
    var d = 0usize
    while d < v {
        i = 0usize
        while i < p {
            z[i] = ms.sc_rnorm(g, 0.0f64, 1.0f64)
            i += 1usize
        }
        i = 0usize
        while i < p {
            var t = 0.0f64
            var j = 0usize
            while j <= i {
                t += l[i * p + j] * z[j]
                j += 1usize
            }
            al[i] = t
            i += 1usize
        }
        i = 0usize
        while i < p {
            var j = 0usize
            while j < p {
                out[i * p + j] += al[i] * al[j]
                j += 1usize
            }
            i += 1usize
        }
        d += 1usize
    }
    ret ok
}

// grp[n] is the 0-based group of each row. out is nstore x (np + nq * ngroup + nq * nq + 2) in R's column order (beta, b by covariate then group, Vb by column,
// sigma2, Deviance); ypred[n] is the posterior mean of the fitted values.
fn hregress(a: *mem.Arena, g: *ms.Sc, grp: []const f64, y: []const f64, x: []const f64, w: []const f64, n: usize, ng: usize, np: usize, nq: usize, mubeta: []const f64, vbeta: []const f64, r: f64, rr: []const f64, s1: f64, s2: f64, beta0: []const f64, sig0: f64, vb0: []const f64, burnin: usize, mcmc: usize, thin: usize, out: []f64, ypred: []f64) -> err {
    let nstore = mcmc / thin
    let ncol = np + nq * ng + nq * nq + 2usize
    let (vbetainv, e1) = mem.alloc[f64](a, np * np)
    let (beta, e2) = mem.alloc[f64](a, np)
    let (vb, e3) = mem.alloc[f64](a, nq * nq)
    let (bk, e4) = mem.alloc[f64](a, ng * nq)
    let (cpx, e5) = mem.alloc[f64](a, ng * np * np)
    let (xw, e6) = mem.alloc[f64](a, ng * np * nq)
    let (cpw, e7) = mem.alloc[f64](a, ng * nq * nq)
    let (xy, e8) = mem.alloc[f64](a, ng * np)
    let (wy, e9) = mem.alloc[f64](a, ng * nq)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    var ld = 0.0f64
    if ms.inv_pd(a, vbeta, np, vbetainv, &ld) != ok { ret ms.NotPd }
    var i = 0usize
    while i < np {
        beta[i] = beta0[i]
        i += 1usize
    }
    i = 0usize
    while i < nq * nq {
        vb[i] = vb0[i]
        i += 1usize
    }
    i = 0usize
    while i < ng * nq {
        bk[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < ng * np * np {
        cpx[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < ng * np * nq {
        xw[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < ng * nq * nq {
        cpw[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < ng * np {
        xy[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < ng * nq {
        wy[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        let k = usize(grp[i])
        var p1 = 0usize
        while p1 < np {
            var p2 = 0usize
            while p2 < np {
                cpx[k * np * np + p1 * np + p2] += x[i * np + p1] * x[i * np + p2]
                p2 += 1usize
            }
            var q = 0usize
            while q < nq {
                xw[k * np * nq + p1 * nq + q] += x[i * np + p1] * w[i * nq + q]
                q += 1usize
            }
            xy[k * np + p1] += x[i * np + p1] * y[i]
            p1 += 1usize
        }
        var q1 = 0usize
        while q1 < nq {
            var q2 = 0usize
            while q2 < nq {
                cpw[k * nq * nq + q1 * nq + q2] += w[i * nq + q1] * w[i * nq + q2]
                q2 += 1usize
            }
            wy[k * nq + q1] += w[i * nq + q1] * y[i]
            q1 += 1usize
        }
        ypred[i] = 0.0f64
        i += 1usize
    }
    // R hands the start variance through as.integer, which truncates it
    var vrun = f64(i64(sig0))
    let tot = burnin + mcmc
    var it = 0usize
    while it < tot {
        let start = mem.mark(a)
        let (vbinv, f1) = mem.alloc[f64](a, nq * nq)
        let (sumv, f2) = mem.alloc[f64](a, np * np)
        let (sumvv, f3) = mem.alloc[f64](a, np)
        let (m1, f4) = mem.alloc[f64](a, nq * nq)
        let (m2, f5) = mem.alloc[f64](a, nq * nq)
        let (t1, f6) = mem.alloc[f64](a, np * nq)
        let (t2, f7) = mem.alloc[f64](a, np * np)
        let (t3, f8) = mem.alloc[f64](a, np)
        let (bigv, f9) = mem.alloc[f64](a, np * np)
        let (sm, f10) = mem.alloc[f64](a, np)
        let (mu, f11) = mem.alloc[f64](a, np)
        if f1 != ok { ret f1 }
        if f2 != ok { ret f2 }
        if f3 != ok { ret f3 }
        if f4 != ok { ret f4 }
        if f5 != ok { ret f5 }
        if f6 != ok { ret f6 }
        if f7 != ok { ret f7 }
        if f8 != ok { ret f8 }
        if f9 != ok { ret f9 }
        if f10 != ok { ret f10 }
        if f11 != ok { ret f11 }
        if ms.inv_pd(a, vb, nq, vbinv, &ld) != ok { ret ms.NotPd }
        let iv = 1.0f64 / vrun
        i = 0usize
        while i < np * np {
            sumv[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < np {
            sumvv[i] = 0.0f64
            i += 1usize
        }
        var k = 0usize
        while k < ng {
            i = 0usize
            while i < nq * nq {
                m1[i] = vbinv[i] + cpw[k * nq * nq + i] * iv
                i += 1usize
            }
            if ms.inv_pd(a, m1, nq, m2, &ld) != ok { ret ms.NotPd }
            mm(xw[k * np * nq..(k + 1usize) * np * nq], np, nq, m2, nq, t1)
            // t2 = tXW M tWX, tWX[q][p] = xw[p][q]
            var p1 = 0usize
            while p1 < np {
                var p2 = 0usize
                while p2 < np {
                    var s = 0.0f64
                    var q = 0usize
                    while q < nq {
                        s += t1[p1 * nq + q] * xw[k * np * nq + p2 * nq + q]
                        q += 1usize
                    }
                    t2[p1 * np + p2] = s
                    p2 += 1usize
                }
                var s3 = 0.0f64
                var q3 = 0usize
                while q3 < nq {
                    s3 += t1[p1 * nq + q3] * wy[k * nq + q3]
                    q3 += 1usize
                }
                t3[p1] = s3
                p1 += 1usize
            }
            i = 0usize
            while i < np * np {
                sumv[i] += iv * cpx[k * np * np + i] - iv * iv * t2[i]
                i += 1usize
            }
            i = 0usize
            while i < np {
                sumvv[i] += iv * xy[k * np + i] - iv * iv * t3[i]
                i += 1usize
            }
            k += 1usize
        }
        i = 0usize
        while i < np * np {
            t2[i] = vbetainv[i] + sumv[i] * iv
            i += 1usize
        }
        if ms.inv_pd(a, t2, np, bigv, &ld) != ok { ret ms.NotPd }
        i = 0usize
        while i < np {
            var s = 0.0f64
            var j = 0usize
            while j < np {
                s += vbetainv[i * np + j] * mubeta[j]
                j += 1usize
            }
            sm[i] = s + sumvv[i] * iv
            i += 1usize
        }
        i = 0usize
        while i < np {
            var s = 0.0f64
            var j = 0usize
            while j < np {
                s += bigv[i * np + j] * sm[j]
                j += 1usize
            }
            mu[i] = s
            i += 1usize
        }
        if rmvn(a, g, mu, bigv, np, beta) != ok { ret ms.NotPd }
        // b_k
        k = 0usize
        while k < ng {
            i = 0usize
            while i < nq * nq {
                m1[i] = vbinv[i] + cpw[k * nq * nq + i] * iv
                i += 1usize
            }
            if ms.inv_pd(a, m1, nq, m2, &ld) != ok { ret ms.NotPd }
            // small_vk = tW (Y - X beta) / V  accumulated over the rows of group k
            let (sv, h1) = mem.alloc[f64](a, nq)
            let (mq, h2) = mem.alloc[f64](a, nq)
            if h1 != ok { ret h1 }
            if h2 != ok { ret h2 }
            var q = 0usize
            while q < nq {
                sv[q] = 0.0f64
                q += 1usize
            }
            i = 0usize
            while i < n {
                if usize(grp[i]) == k {
                    var xb = 0.0f64
                    var p1b = 0usize
                    while p1b < np {
                        xb += x[i * np + p1b] * beta[p1b]
                        p1b += 1usize
                    }
                    q = 0usize
                    while q < nq {
                        sv[q] += w[i * nq + q] * (y[i] - xb)
                        q += 1usize
                    }
                }
                i += 1usize
            }
            q = 0usize
            while q < nq {
                sv[q] = sv[q] / vrun
                q += 1usize
            }
            q = 0usize
            while q < nq {
                var s = 0.0f64
                var j = 0usize
                while j < nq {
                    s += m2[q * nq + j] * sv[j]
                    j += 1usize
                }
                mq[q] = s
                q += 1usize
            }
            if rmvn(a, g, mq, m2, nq, bk[k * nq..(k + 1usize) * nq]) != ok { ret ms.NotPd }
            k += 1usize
        }
        // Vb
        i = 0usize
        while i < nq * nq {
            m1[i] = 0.0f64
            i += 1usize
        }
        k = 0usize
        while k < ng {
            var q1 = 0usize
            while q1 < nq {
                var q2 = 0usize
                while q2 < nq {
                    m1[q1 * nq + q2] += bk[k * nq + q1] * bk[k * nq + q2]
                    q2 += 1usize
                }
                q1 += 1usize
            }
            k += 1usize
        }
        i = 0usize
        while i < nq * nq {
            m1[i] = m1[i] + r * rr[i]
            i += 1usize
        }
        if ms.inv_pd(a, m1, nq, m2, &ld) != ok { ret ms.NotPd }
        if rwish_sc(a, g, usize(r + f64(ng)), m2, nq, m1) != ok { ret ms.NotPd }
        if ms.inv_pd(a, m1, nq, vb, &ld) != ok { ret ms.NotPd }
        // sigma2
        var e = 0.0f64
        i = 0usize
        while i < n {
            let k2 = usize(grp[i])
            var fit = 0.0f64
            var p1c = 0usize
            while p1c < np {
                fit += x[i * np + p1c] * beta[p1c]
                p1c += 1usize
            }
            var q = 0usize
            while q < nq {
                fit += w[i * nq + q] * bk[k2 * nq + q]
                q += 1usize
            }
            e += (y[i] - fit) * (y[i] - fit)
            i += 1usize
        }
        let sh = s1 + f64(n / 2usize)
        vrun = 1.0f64 / ms.sc_rgamma(g, sh, s2 + 0.5f64 * e)
        if it + 1usize > burnin && (it + 1usize) % thin == 0usize {
            let row = ((it + 1usize) - burnin) / thin - 1usize
            var dev = 0.0f64
            i = 0usize
            while i < n {
                let k2 = usize(grp[i])
                var fit = 0.0f64
                var p1c = 0usize
                while p1c < np {
                    fit += x[i * np + p1c] * beta[p1c]
                    p1c += 1usize
                }
                var q = 0usize
                while q < nq {
                    fit += w[i * nq + q] * bk[k2 * nq + q]
                    q += 1usize
                }
                let sd = math.sqrt[f64](vrun)
                let zz = y[i] - fit
                let dn = 1.0f64 / (math.sqrt[f64](2.0f64 * 3.141592653589793f64) * sd) * math.exp[f64](-1.0f64 * zz * zz / (2.0f64 * sd * sd))
                dev += math.log[f64](dn)
                ypred[i] += fit / f64(nstore)
                i += 1usize
            }
            var c = 0usize
            while c < np {
                out[row * ncol + c] = beta[c]
                c += 1usize
            }
            var qo = 0usize
            while qo < nq {
                var kk = 0usize
                while kk < ng {
                    out[row * ncol + np + qo * ng + kk] = bk[kk * nq + qo]
                    kk += 1usize
                }
                qo += 1usize
            }
            var qp = 0usize
            while qp < nq {
                var qq = 0usize
                while qq < nq {
                    out[row * ncol + np + nq * ng + qp * nq + qq] = vb[qq * nq + qp]
                    qq += 1usize
                }
                qp += 1usize
            }
            out[row * ncol + ncol - 2usize] = vrun
            out[row * ncol + ncol - 1usize] = -2.0f64 * dev
        }
        mem.reset(a, start)
        it += 1usize
    }
    ret ok
}
