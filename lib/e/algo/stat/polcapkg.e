// R poLCA: latent class analysis of polytomous manifest variables by EM from given starting response probabilities (uniform class prior), run to a log-likelihood change below tol; returns the log-likelihood, class sizes and response probabilities.
//
// Not here: random restarts, covariates (latent class regression), standard errors, posterior class assignment output, graphing, goodness-of-fit chi-squares, missing responses.

use e.math
use e.mem
use e.algo.rand.r as rg
use e.algo.stat.quantreg as qrb

// data: n by j row-major, categories 0-based; ncat[j] categories for variable j; probs: r classes by (sum ncat) response probabilities, row-major, start in and result out; prior (r) receives the class sizes; returns the log-likelihood
fn em(a: *mem.Arena, data: []const f64, n: usize, nj: usize, ncat: []const usize, nr: usize, probs: []f64, prior: []f64, tol: f64, maxiter: usize) -> f64 {
    var tc = 0usize
    var v = 0usize
    while v < nj {
        tc += ncat[v]
        v += 1usize
    }
    let (off, e1) = mem.alloc[usize](a, nj)
    let (post, e2) = mem.alloc[f64](a, nr)
    let (acc, e3) = mem.alloc[f64](a, nr * tc)
    let (cls, e4) = mem.alloc[f64](a, nr)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret 0.0f64 / 0.0f64 }
    var o = 0usize
    v = 0usize
    while v < nj {
        off[v] = o
        o += ncat[v]
        v += 1usize
    }
    var r = 0usize
    while r < nr {
        prior[r] = 1.0f64 / f64(nr)
        r += 1usize
    }
    var ll = 0.0f64 - 1.0e300f64
    var it = 0usize
    while it < maxiter {
        r = 0usize
        while r < nr {
            cls[r] = 0.0f64
            var c = 0usize
            while c < tc {
                acc[r * tc + c] = 0.0f64
                c += 1usize
            }
            r += 1usize
        }
        var cur = 0.0f64
        var i = 0usize
        while i < n {
            var tot = 0.0f64
            r = 0usize
            while r < nr {
                var pr = prior[r]
                v = 0usize
                while v < nj {
                    pr *= probs[r * tc + off[v] + usize(data[i * nj + v])]
                    v += 1usize
                }
                post[r] = pr
                tot += pr
                r += 1usize
            }
            cur += math.log[f64](tot)
            r = 0usize
            while r < nr {
                let w = post[r] / tot
                cls[r] += w
                v = 0usize
                while v < nj {
                    acc[r * tc + off[v] + usize(data[i * nj + v])] += w
                    v += 1usize
                }
                r += 1usize
            }
            i += 1usize
        }
        // M step
        r = 0usize
        while r < nr {
            prior[r] = cls[r] / f64(n)
            v = 0usize
            while v < nj {
                var c = 0usize
                while c < ncat[v] {
                    probs[r * tc + off[v] + c] = acc[r * tc + off[v] + c] / cls[r]
                    c += 1usize
                }
                v += 1usize
            }
            r += 1usize
        }
        it += 1usize
        if math.abs[f64](cur - ll) < tol {
            ll = cur
            break
        }
        ll = cur
    }
    ret ll
}

// poLCA's fit statistics at the estimated probs (R by sum(ncat), row-major) and prior: which 0 npar, 1 AIC, 2 Gsq, 3 Chisq, 4 residual degrees of freedom, 5 the class counts of the modal posterior
// class weighted by class number (sum k n_k), data n by nj row-major with 0-based categories
fn fit_stats(a: *mem.Arena, data: []const f64, n: usize, nj: usize, ncat: []const usize, nr: usize, probs: []const f64, prior: []const f64, ll: f64, which: usize) -> f64 {
    var tc = 0usize
    var j = 0usize
    while j < nj {
        tc += ncat[j]
        j += 1usize
    }
    let npar = f64(nr * (tc - nj) + (nr - 1usize))
    if which == 0usize { ret npar }
    if which == 1usize { ret 0.0f64 - 2.0f64 * ll + 2.0f64 * npar }
    var cells = 1.0f64
    j = 0usize
    while j < nj {
        cells = cells * f64(ncat[j])
        j += 1usize
    }
    if which == 4usize {
        var cap = cells - 1.0f64
        if f64(n) - 1.0f64 < cap { cap = f64(n) - 1.0f64 }
        ret cap - npar
    }
    let (offs, e1) = mem.alloc[usize](a, nj)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    var acc = 0usize
    j = 0usize
    while j < nj {
        offs[j] = acc
        acc += ncat[j]
        j += 1usize
    }
    if which == 5usize {
        var tot = 0.0f64
        var i = 0usize
        while i < n {
            var best = 0usize
            var bv = 0.0f64 - 1.0f64
            var r = 0usize
            while r < nr {
                var v = prior[r]
                j = 0usize
                while j < nj {
                    v = v * probs[r * tc + offs[j] + usize(data[i * nj + j])]
                    j += 1usize
                }
                if v > bv {
                    bv = v
                    best = r
                }
                r += 1usize
            }
            tot += f64(best + 1usize)
            i += 1usize
        }
        ret tot
    }
    // patterns: for each row, count the rows equal to it and use the first occurrence only
    var gsq = 0.0f64
    var chisq = 0.0f64
    var sumexp = 0.0f64
    var i = 0usize
    while i < n {
        var first = true
        var cnt = 0.0f64
        var q = 0usize
        while q < n {
            var same = true
            j = 0usize
            while j < nj {
                if data[q * nj + j] != data[i * nj + j] { same = false }
                j += 1usize
            }
            if same {
                cnt += 1.0f64
                if q < i { first = false }
            }
            q += 1usize
        }
        if first {
            var ex = 0.0f64
            var r = 0usize
            while r < nr {
                var v = prior[r]
                j = 0usize
                while j < nj {
                    v = v * probs[r * tc + offs[j] + usize(data[i * nj + j])]
                    j += 1usize
                }
                ex += v
                r += 1usize
            }
            ex = ex * f64(n)
            sumexp += ex
            gsq += cnt * math.log[f64](cnt / ex)
            chisq += (cnt - ex) * (cnt - ex) / ex
        }
        i += 1usize
    }
    if which == 2usize { ret 2.0f64 * gsq }
    ret chisq + (f64(n) - sumexp)
}

// poLCA(..., nrep = nrep) with probs.start = NULL under set.seed(seed): each repetition draws runif(R K_j) for the variables in turn, fills an R by K_j matrix by column and divides each row by its sum;
// the best log-likelihood (the first one reached when equal repetitions tie, as poLCA keeps a strict improvement) wins. probs and prior receive the winner; returns its log-likelihood
fn em_restarts(a: *mem.Arena, data: []const f64, n: usize, nj: usize, ncat: []const usize, nr: usize, nrep: usize, seed: i64, tol: f64, maxiter: usize, probs: []f64, prior: []f64) -> f64 {
    var tc = 0usize
    var v = 0usize
    while v < nj {
        tc += ncat[v]
        v += 1usize
    }
    let (cur, e1) = mem.alloc[f64](a, nr * tc)
    let (cp, e2) = mem.alloc[f64](a, nr)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var rng: rg.Rng = zero
    rg.seed(&rng, seed)
    var best = 0.0f64 - 1.0e300f64
    var rep = 0usize
    while rep < nrep {
        var off = 0usize
        v = 0usize
        while v < nj {
            let k = ncat[v]
            let (u, e3) = mem.alloc[f64](a, nr * k)
            if e3 != ok { ret 0.0f64 / 0.0f64 }
            var q = 0usize
            while q < nr * k {
                u[q] = rg.unif(&rng)
                q += 1usize
            }
            var r = 0usize
            while r < nr {
                var sm = 0.0f64
                var c = 0usize
                while c < k {
                    sm += u[r + c * nr]
                    c += 1usize
                }
                c = 0usize
                while c < k {
                    cur[r * tc + off + c] = u[r + c * nr] / sm
                    c += 1usize
                }
                r += 1usize
            }
            off += k
            v += 1usize
        }
        let ll = em(a, data, n, nj, ncat, nr, cur, cp, tol, maxiter)
        if ll > best {
            best = ll
            var i = 0usize
            while i < nr * tc {
                probs[i] = cur[i]
                i += 1usize
            }
            i = 0usize
            while i < nr {
                prior[i] = cp[i]
                i += 1usize
            }
        }
        rep += 1usize
    }
    ret best
}

// poLCA's standard errors (poLCA.se, intercept-only, no covariates): the information is the cross product of the per-case scores of the free response logits (categories 2 .. K_j of each class and variable) and the
// class logits, the response probability errors follow by the delta method, and the class size errors from the class-logit block. probs, prior at the fit (probs R by sum(ncat) row-major, as `em`).
// out[0 .. R tc] the standard errors of the response probabilities (class r, variable offset + category at r tc + off + k), then R the standard errors of the class sizes; false when the information is singular
fn se(a: *mem.Arena, data: []const f64, n: usize, nj: usize, ncat: []const usize, nr: usize, probs: []const f64, prior: []const f64, out: []f64) -> bool {
    var tc = 0usize
    var v = 0usize
    while v < nj {
        tc += ncat[v]
        v += 1usize
    }
    var m = 0usize
    v = 0usize
    while v < nj {
        m += nr * (ncat[v] - 1usize)
        v += 1usize
    }
    let q = m + (nr - 1usize)
    let (off, e1) = mem.alloc[usize](a, nj)
    let (sc, e2) = mem.alloc[f64](a, q)
    let (info, e3) = mem.alloc[f64](a, q * q)
    let (post, e4) = mem.alloc[f64](a, nr)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret false }
    var o = 0usize
    v = 0usize
    while v < nj {
        off[v] = o
        o += ncat[v]
        v += 1usize
    }
    var i = 0usize
    while i < q * q {
        info[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        var tot = 0.0f64
        var r = 0usize
        while r < nr {
            var pr = prior[r]
            v = 0usize
            while v < nj {
                pr *= probs[r * tc + off[v] + usize(data[i * nj + v])]
                v += 1usize
            }
            post[r] = pr
            tot += pr
            r += 1usize
        }
        r = 0usize
        while r < nr {
            post[r] = post[r] / tot
            r += 1usize
        }
        var c = 0usize
        r = 0usize
        while r < nr {
            v = 0usize
            while v < nj {
                var k = 1usize
                while k < ncat[v] {
                    var ind = 0.0f64
                    if usize(data[i * nj + v]) == k { ind = 1.0f64 }
                    sc[c] = post[r] * (ind - probs[r * tc + off[v] + k])
                    c += 1usize
                    k += 1usize
                }
                v += 1usize
            }
            r += 1usize
        }
        r = 1usize
        while r < nr {
            sc[c] = post[r] - prior[r]
            c += 1usize
            r += 1usize
        }
        var j = 0usize
        while j < q {
            var l = 0usize
            while l < q {
                info[j * q + l] += sc[j] * sc[l]
                l += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    let (vce, e5) = mem.alloc[f64](a, q * q)
    let (mat, e6) = mem.alloc[f64](a, q * q)
    let (col, e7) = mem.alloc[f64](a, q)
    if e5 != ok || e6 != ok || e7 != ok { ret false }
    var cc = 0usize
    while cc < q {
        var t = 0usize
        while t < q * q {
            mat[t] = info[t]
            t += 1usize
        }
        t = 0usize
        while t < q {
            col[t] = 0.0f64
            t += 1usize
        }
        col[cc] = 1.0f64
        if !qrb.solve_dense(mat, col, q) { ret false }
        t = 0usize
        while t < q {
            vce[t * q + cc] = col[t]
            t += 1usize
        }
        cc += 1usize
    }
    // response probabilities: the delta method on blocks of K_j rows with the Jacobian of the softmax without its first logit
    var rpos = 0usize
    var cpos = 0usize
    var r = 0usize
    while r < nr {
        v = 0usize
        while v < nj {
            let k = ncat[v]
            var a1 = 0usize
            while a1 < k {
                var vr = 0.0f64
                var b1 = 1usize
                while b1 < k {
                    var b2 = 1usize
                    while b2 < k {
                        var ja = 0.0f64 - probs[r * tc + off[v] + a1] * probs[r * tc + off[v] + b1]
                        if a1 == b1 { ja = probs[r * tc + off[v] + a1] * (1.0f64 - probs[r * tc + off[v] + a1]) }
                        var jb = 0.0f64 - probs[r * tc + off[v] + a1] * probs[r * tc + off[v] + b2]
                        if a1 == b2 { jb = probs[r * tc + off[v] + a1] * (1.0f64 - probs[r * tc + off[v] + a1]) }
                        vr += ja * vce[(cpos + b1 - 1usize) * q + cpos + b2 - 1usize] * jb
                        b2 += 1usize
                    }
                    b1 += 1usize
                }
                if vr < 0.0f64 { vr = 0.0f64 }
                out[r * tc + off[v] + a1] = math.sqrt[f64](vr)
                a1 += 1usize
            }
            rpos += k
            cpos += k - 1usize
            v += 1usize
        }
        r += 1usize
    }
    // class sizes
    var s1 = 0usize
    while s1 < nr {
        var vs = 0.0f64
        var ra = 1usize
        while ra < nr {
            var rb = 1usize
            while rb < nr {
                var ja = 0.0f64 - prior[s1] * prior[ra]
                if s1 == ra { ja = prior[s1] * (1.0f64 - prior[s1]) }
                var jb = 0.0f64 - prior[s1] * prior[rb]
                if s1 == rb { jb = prior[s1] * (1.0f64 - prior[s1]) }
                vs += ja * vce[(m + ra - 1usize) * q + m + rb - 1usize] * jb
                rb += 1usize
            }
            ra += 1usize
        }
        out[nr * tc + s1] = math.sqrt[f64](vs)
        s1 += 1usize
    }
    ret true
}
