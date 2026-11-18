// R poLCA: latent class analysis of polytomous manifest variables by EM from given starting response probabilities (uniform class prior), run to a log-likelihood change below tol; returns the log-likelihood, class sizes and response probabilities.
//
// Not here: random restarts, covariates (latent class regression), standard errors, posterior class assignment output, graphing, goodness-of-fit chi-squares, missing responses.

use e.math
use e.mem

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
