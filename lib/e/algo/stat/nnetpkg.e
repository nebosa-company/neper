// R nnet::multinom without weight decay: the multinomial logit by Newton's method (R runs BFGS on the same likelihood, so the two agree to R's reltol). Class 0 is the reference; the coefficients are the K - 1 rows for classes 1 .. K - 1, p columns each (row-major).
//
// Not here: weight decay, case weights, the hidden-layer networks of nnet, softmax and censored responses.

use e.algo.stat.gparot as gp
use e.math
use e.mem

// returns the deviance, -2 log-likelihood (NaN if the Hessian is singular); iterations in it
fn multinom(a: *mem.Arena, x: []const f64, cls: []const f64, n: usize, p: usize, nk: usize, coef: []f64) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let q = (nk - 1usize) * p
    let (gr, e1) = mem.alloc[f64](a, q)
    let (h, e2) = mem.alloc[f64](a, q * q)
    let (pr, e3) = mem.alloc[f64](a, nk)
    if e1 != ok || e2 != ok || e3 != ok { ret nan }
    var i = 0usize
    while i < q {
        coef[i] = 0.0f64
        i += 1usize
    }
    var dev = 0.0f64
    var it = 0usize
    while it < 100usize {
        let start = mem.mark(a)
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
        dev = 0.0f64
        var t = 0usize
        while t < n {
            var mx = 0.0f64
            var k = 1usize
            while k < nk {
                var eta = 0.0f64
                var c = 0usize
                while c < p {
                    eta += coef[(k - 1usize) * p + c] * x[t * p + c]
                    c += 1usize
                }
                pr[k] = eta
                if eta > mx { mx = eta }
                k += 1usize
            }
            pr[0usize] = 0.0f64
            var s = 0.0f64
            k = 0usize
            while k < nk {
                pr[k] = math.exp[f64](pr[k] - mx)
                s += pr[k]
                k += 1usize
            }
            k = 0usize
            while k < nk {
                pr[k] = pr[k] / s
                k += 1usize
            }
            let yc = usize(cls[t])
            dev -= 2.0f64 * math.log[f64](pr[yc])
            k = 1usize
            while k < nk {
                var d = 0.0f64
                if yc == k { d = 1.0f64 }
                var c = 0usize
                while c < p {
                    gr[(k - 1usize) * p + c] += (d - pr[k]) * x[t * p + c]
                    var l = 1usize
                    while l < nk {
                        var dl = 0.0f64
                        if l == k { dl = 1.0f64 }
                        var c2 = 0usize
                        while c2 < p {
                            h[((k - 1usize) * p + c) * q + (l - 1usize) * p + c2] += pr[k] * (dl - pr[l]) * x[t * p + c] * x[t * p + c2]
                            c2 += 1usize
                        }
                        l += 1usize
                    }
                    c += 1usize
                }
                k += 1usize
            }
            t += 1usize
        }
        let (inv, ie) = gp.invert(a, h, q)
        if ie != ok { ret nan }
        var step = 0.0f64
        i = 0usize
        while i < q {
            var d = 0.0f64
            var j = 0usize
            while j < q {
                d += inv[i * q + j] * gr[j]
                j += 1usize
            }
            coef[i] += d
            if math.abs[f64](d) > step { step = math.abs[f64](d) }
            i += 1usize
        }
        mem.reset(a, start)
        it += 1usize
        if step < 1.0e-12f64 { break }
    }
    // deviance at the final coefficients
    var t = 0usize
    dev = 0.0f64
    while t < n {
        var mx = 0.0f64
        var k = 1usize
        while k < nk {
            var eta = 0.0f64
            var c = 0usize
            while c < p {
                eta += coef[(k - 1usize) * p + c] * x[t * p + c]
                c += 1usize
            }
            pr[k] = eta
            if eta > mx { mx = eta }
            k += 1usize
        }
        pr[0usize] = 0.0f64
        var s = 0.0f64
        k = 0usize
        while k < nk {
            pr[k] = math.exp[f64](pr[k] - mx)
            s += pr[k]
            k += 1usize
        }
        dev -= 2.0f64 * math.log[f64](pr[usize(cls[t])] / s)
        t += 1usize
    }
    ret dev
}
