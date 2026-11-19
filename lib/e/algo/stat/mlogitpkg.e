// R mlogit: the conditional (multinomial) logit of discrete choice with alternative-specific covariates sharing one coefficient each and optional alternative-specific constants (the first alternative is the reference), fitted by Newton's method on the exact Hessian; coefficients, standard errors and the log-likelihood.
//
// Not here: individual-specific covariates with alternative-specific coefficients, nested and mixed logit, probit, rank-ordered data, heteroskedastic and generalised extreme value models.

use e.algo.stat.gparot as gp
use e.math
use e.mem
use e.math.opt as opt

// x is n choosers by j alternatives by k covariates (row-major in that order); ch[i] is the chosen alternative (0-based); out = coefficients (q), standard errors (q), log-likelihood, q = (asc ? j - 1 : 0) + k
fn clogit(a: *mem.Arena, x: []const f64, ch: []const f64, n: usize, j: usize, k: usize, asc: bool, out: []f64) -> err {
    var na = 0usize
    if asc { na = j - 1usize }
    let q = na + k
    let (b, e1) = mem.alloc[f64](a, q)
    let (gr, e2) = mem.alloc[f64](a, q)
    let (h, e3) = mem.alloc[f64](a, q * q)
    let (z, e4) = mem.alloc[f64](a, j * q)
    let (pr, e5) = mem.alloc[f64](a, j)
    let (zb, e6) = mem.alloc[f64](a, q)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    var i = 0usize
    while i < q {
        b[i] = 0.0f64
        i += 1usize
    }
    var ll = 0.0f64
    var it = 0usize
    while it < 100usize {
        i = 0usize
        while i < q {
            gr[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < q * q {
            h[i] = 0.0f64
            i += 1usize
        }
        ll = 0.0f64
        var c = 0usize
        while c < n {
            var mx = 0.0f64 - 1.0e300f64
            var a2 = 0usize
            while a2 < j {
                var q2 = 0usize
                while q2 < q {
                    var zv = 0.0f64
                    if q2 < na {
                        if a2 > 0usize && q2 == a2 - 1usize { zv = 1.0f64 }
                    } else {
                        zv = x[(c * j + a2) * k + q2 - na]
                    }
                    z[a2 * q + q2] = zv
                    q2 += 1usize
                }
                var v = 0.0f64
                q2 = 0usize
                while q2 < q {
                    v += b[q2] * z[a2 * q + q2]
                    q2 += 1usize
                }
                pr[a2] = v
                if v > mx { mx = v }
                a2 += 1usize
            }
            var s = 0.0f64
            a2 = 0usize
            while a2 < j {
                pr[a2] = math.exp[f64](pr[a2] - mx)
                s += pr[a2]
                a2 += 1usize
            }
            a2 = 0usize
            while a2 < j {
                pr[a2] = pr[a2] / s
                a2 += 1usize
            }
            let yi = usize(ch[c])
            ll += math.log[f64](pr[yi])
            var q2 = 0usize
            while q2 < q {
                var m = 0.0f64
                a2 = 0usize
                while a2 < j {
                    m += pr[a2] * z[a2 * q + q2]
                    a2 += 1usize
                }
                zb[q2] = m
                gr[q2] += z[yi * q + q2] - m
                q2 += 1usize
            }
            a2 = 0usize
            while a2 < j {
                q2 = 0usize
                while q2 < q {
                    var q3 = 0usize
                    while q3 < q {
                        h[q2 * q + q3] += pr[a2] * (z[a2 * q + q2] - zb[q2]) * (z[a2 * q + q3] - zb[q3])
                        q3 += 1usize
                    }
                    q2 += 1usize
                }
                a2 += 1usize
            }
            c += 1usize
        }
        let (hi, ie) = gp.invert(a, h, q)
        if ie != ok { ret ie }
        var step = 0.0f64
        i = 0usize
        while i < q {
            var d = 0.0f64
            var l = 0usize
            while l < q {
                d += hi[i * q + l] * gr[l]
                l += 1usize
            }
            b[i] += d
            if math.abs[f64](d) > step { step = math.abs[f64](d) }
            i += 1usize
        }
        it += 1usize
        if step < 1.0e-13f64 { break }
    }
    // standard errors and the log-likelihood at the final coefficients: refresh them with one more pass
    ll = 0.0f64
    i = 0usize
    while i < q * q {
        h[i] = 0.0f64
        i += 1usize
    }
    var c = 0usize
    while c < n {
        var mx = 0.0f64 - 1.0e300f64
        var a2 = 0usize
        while a2 < j {
            var q2 = 0usize
            while q2 < q {
                var zv = 0.0f64
                if q2 < na {
                    if a2 > 0usize && q2 == a2 - 1usize { zv = 1.0f64 }
                } else {
                    zv = x[(c * j + a2) * k + q2 - na]
                }
                z[a2 * q + q2] = zv
                q2 += 1usize
            }
            var v = 0.0f64
            q2 = 0usize
            while q2 < q {
                v += b[q2] * z[a2 * q + q2]
                q2 += 1usize
            }
            pr[a2] = v
            if v > mx { mx = v }
            a2 += 1usize
        }
        var s = 0.0f64
        a2 = 0usize
        while a2 < j {
            pr[a2] = math.exp[f64](pr[a2] - mx)
            s += pr[a2]
            a2 += 1usize
        }
        a2 = 0usize
        while a2 < j {
            pr[a2] = pr[a2] / s
            a2 += 1usize
        }
        ll += math.log[f64](pr[usize(ch[c])])
        var q2 = 0usize
        while q2 < q {
            var m = 0.0f64
            a2 = 0usize
            while a2 < j {
                m += pr[a2] * z[a2 * q + q2]
                a2 += 1usize
            }
            zb[q2] = m
            q2 += 1usize
        }
        a2 = 0usize
        while a2 < j {
            q2 = 0usize
            while q2 < q {
                var q3 = 0usize
                while q3 < q {
                    h[q2 * q + q3] += pr[a2] * (z[a2 * q + q2] - zb[q2]) * (z[a2 * q + q3] - zb[q3])
                    q3 += 1usize
                }
                q2 += 1usize
            }
            a2 += 1usize
        }
        c += 1usize
    }
    let (hf, fe) = gp.invert(a, h, q)
    if fe != ok { ret fe }
    i = 0usize
    while i < q {
        out[i] = b[i]
        out[q + i] = math.sqrt[f64](hf[i * q + i])
        i += 1usize
    }
    out[2usize * q] = ll
    ret ok
}

// the fitted choice probabilities of chooser i (utility a_j + x_ij beta, a_0 = 0 as the reference): p[0 .. j]
fn clogit_probs(x: []const f64, i: usize, j: usize, k: usize, asc: bool, coef: []const f64, p: []f64) {
    var na = 0usize
    if asc { na = j - 1usize }
    var tot = 0.0f64
    var a1 = 0usize
    while a1 < j {
        var v = 0.0f64
        if asc && a1 > 0usize { v = coef[a1 - 1usize] }
        var c = 0usize
        while c < k {
            v += x[(i * j + a1) * k + c] * coef[na + c]
            c += 1usize
        }
        p[a1] = math.exp[f64](v)
        tot += p[a1]
        a1 += 1usize
    }
    a1 = 0usize
    while a1 < j {
        p[a1] = p[a1] / tot
        a1 += 1usize
    }
}

// the mean over choosers of the fitted probabilities, colMeans(fitted(f, outcome = FALSE)) of mlogit: out[0 .. j]
fn clogit_shares(x: []const f64, n: usize, j: usize, k: usize, asc: bool, coef: []const f64, out: []f64) {
    var pr: [16]f64 = zero
    var a1 = 0usize
    while a1 < j {
        out[a1] = 0.0f64
        a1 += 1usize
    }
    var i = 0usize
    while i < n {
        clogit_probs(x, i, j, k, asc, coef, pr[0usize..j])
        a1 = 0usize
        while a1 < j {
            out[a1] += pr[a1] / f64(n)
            a1 += 1usize
        }
        i += 1usize
    }
}

// effects(f, covariate = c) of mlogit ("aa", at the sample means of the covariates): the j by j matrix whose (a, b) entry is beta_c P_a (delta_ab - P_b), the change in the probability of a for a unit change of
// covariate c of alternative b, the probabilities taken at the means of the covariates by alternative (row-major out)
fn clogit_effects(x: []const f64, n: usize, j: usize, k: usize, asc: bool, coef: []const f64, cov: usize, out: []f64) {
    var na = 0usize
    if asc { na = j - 1usize }
    var pr: [16]f64 = zero
    var tot = 0.0f64
    var a1 = 0usize
    while a1 < j {
        var v = 0.0f64
        if asc && a1 > 0usize { v = coef[a1 - 1usize] }
        var c = 0usize
        while c < k {
            var m = 0.0f64
            var i = 0usize
            while i < n {
                m += x[(i * j + a1) * k + c]
                i += 1usize
            }
            v += m / f64(n) * coef[na + c]
            c += 1usize
        }
        pr[a1] = math.exp[f64](v)
        tot += pr[a1]
        a1 += 1usize
    }
    a1 = 0usize
    while a1 < j {
        pr[a1] = pr[a1] / tot
        a1 += 1usize
    }
    a1 = 0usize
    while a1 < j {
        var b1 = 0usize
        while b1 < j {
            var dl = 0.0f64
            if a1 == b1 { dl = 1.0f64 }
            out[a1 * j + b1] = coef[na + cov] * pr[a1] * (dl - pr[b1])
            b1 += 1usize
        }
        a1 += 1usize
    }
}

type NCtx = struct { x: []const f64, ch: []const f64, n: usize, j: usize, k: usize, na: usize, nest: []const usize, nn: usize, lamidx: []const usize }

// the nested logit negative log-likelihood at par = (alternative constants, covariate coefficients, the inclusive-value coefficient of each nest with two or more alternatives): the probability of j in nest m is
// exp(V_j / l_m) (sum_{i in m} exp(V_i / l_m))^(l_m - 1) / sum_m' (sum_{i in m'} exp(V_i / l_m'))^l_m'
fn nested_negll(c: *NCtx, par: []const f64) -> f64 {
    var ll = 0.0f64
    var iv: [16]f64 = zero
    var vv: [16]f64 = zero
    var sm: [16]f64 = zero
    var i = 0usize
    while i < c.n {
        var a1 = 0usize
        while a1 < c.j {
            var v = 0.0f64
            if c.na > 0usize && a1 > 0usize { v = par[a1 - 1usize] }
            var cc = 0usize
            while cc < c.k {
                v += c.x[(i * c.j + a1) * c.k + cc] * par[c.na + cc]
                cc += 1usize
            }
            vv[a1] = v
            a1 += 1usize
        }
        var m = 0usize
        while m < c.nn {
            sm[m] = 0.0f64
            m += 1usize
        }
        a1 = 0usize
        while a1 < c.j {
            var lm = 1.0f64
            if c.lamidx[c.nest[a1]] < 1000usize { lm = par[c.na + c.k + c.lamidx[c.nest[a1]]] }
            iv[a1] = lm
            sm[c.nest[a1]] += math.exp[f64](vv[a1] / lm)
            a1 += 1usize
        }
        var den = 0.0f64
        m = 0usize
        while m < c.nn {
            var lm = 1.0f64
            if c.lamidx[m] < 1000usize { lm = par[c.na + c.k + c.lamidx[m]] }
            if sm[m] > 0.0f64 { den += math.pow[f64](sm[m], lm) }
            m += 1usize
        }
        let ch = usize(c.ch[i])
        let lc = iv[ch]
        ll += vv[ch] / lc + (lc - 1.0f64) * math.log[f64](sm[c.nest[ch]]) - math.log[f64](den)
        i += 1usize
    }
    if ll != ll { ret 1.0e30f64 }
    ret 0.0f64 - ll
}

// mlogit(..., nests = ...) fitted by Nelder-Mead from the conditional logit with every inclusive value 1: nest[a] is the nest (0-based, nn of them) of alternative a. out = coefficients (constants then covariates), then the
// inclusive values of the nests with two or more alternatives in nest order, then the log-likelihood; q + nl + 1 values. Singleton nests carry no inclusive value
fn nested_logit(a: *mem.Arena, x: []const f64, ch: []const f64, n: usize, j: usize, k: usize, asc: bool, nest: []const usize, nn: usize, out: []f64) -> err {
    var na = 0usize
    if asc { na = j - 1usize }
    let q = na + k
    let (lamidx, e1) = mem.alloc[usize](a, nn)
    if e1 != ok { ret e1 }
    var nl = 0usize
    var m = 0usize
    while m < nn {
        var cnt = 0usize
        var a1 = 0usize
        while a1 < j {
            if nest[a1] == m { cnt += 1usize }
            a1 += 1usize
        }
        lamidx[m] = 1000usize
        if cnt > 1usize {
            lamidx[m] = nl
            nl += 1usize
        }
        m += 1usize
    }
    let (start, e2) = mem.alloc[f64](a, 2usize * q + 1usize)
    if e2 != ok { ret e2 }
    let e3 = clogit(a, x, ch, n, j, k, asc, start)
    if e3 != ok { ret e3 }
    let dim = q + nl
    let (par, e4) = mem.alloc[f64](a, dim)
    if e4 != ok { ret e4 }
    var i = 0usize
    while i < q {
        par[i] = start[i]
        i += 1usize
    }
    while i < dim {
        par[i] = 1.0f64
        i += 1usize
    }
    var c = NCtx { x: x, ch: ch, n: n, j: j, k: k, na: na, nest: nest, nn: nn, lamidx: lamidx }
    let (scr, e5) = mem.alloc[f64](a, (dim + 1usize) * (dim + 1usize) + 4usize * dim)
    if e5 != ok { ret e5 }
    var round = 0usize
    var last = 1.0e30f64
    var best = 1.0e30f64
    while round < 20usize {
        let (r, e6) = opt.nelder_mead[NCtx](&c, nested_negll, par, 0.2f64, 1.0e-15f64, 6000u32, scr)
        if e6 != ok { ret e6 }
        best = r.value
        if math.abs[f64](last - r.value) < 1.0e-12f64 * (1.0f64 + math.abs[f64](r.value)) && round > 2usize { break }
        last = r.value
        round += 1usize
    }
    i = 0usize
    while i < dim {
        out[i] = par[i]
        i += 1usize
    }
    out[dim] = 0.0f64 - best
    ret ok
}
