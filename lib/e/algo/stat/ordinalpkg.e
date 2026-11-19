// R ordinal::clm: the cumulative link model P(y <= j) = F(theta_j - x beta) for logit, probit and cloglog links, fitted by Newton's method with step halving on the exact Hessian (R runs its own Newton on the same likelihood). x has no constant column; classes are 0 .. K - 1.
//
// Not here: flexible thresholds, nominal and scale effects, symmetric thresholds, the other links, weights and predictions.

use e.algo.stat.gparot as gp
use e.math
use e.math.dist as dist
use e.mem

// F, f and f' of the link at a (0 logit, 1 probit, 2 cloglog, 3 loglog, 4 cauchit)
fn link3(link: usize, a: f64) -> (f64, f64, f64) {
    if link == 0usize {
        let f0 = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - a))
        let d = f0 * (1.0f64 - f0)
        ret (f0, d, d * (1.0f64 - 2.0f64 * f0))
    }
    if link == 1usize {
        let d = dist.dnorm(a, 0.0f64, 1.0f64, false)
        ret (dist.pnorm(a, 0.0f64, 1.0f64, true, false), d, 0.0f64 - a * d)
    }
    if link == 3usize {
        let em = math.exp[f64](0.0f64 - a)
        let f3 = math.exp[f64](0.0f64 - em)
        let d3 = em * f3
        ret (f3, d3, d3 * (em - 1.0f64))
    }
    if link == 4usize {
        let pi_ = 3.141592653589793238462643383279f64
        let q = 1.0f64 + a * a
        ret (0.5f64 + math.atan[f64](a) / pi_, 1.0f64 / (pi_ * q), 0.0f64 - 2.0f64 * a / (pi_ * q * q))
    }
    let ea = math.exp[f64](a)
    let d = ea * math.exp[f64](0.0f64 - ea)
    ret (1.0f64 - math.exp[f64](0.0f64 - ea), d, d * (1.0f64 - ea))
}

// the log-likelihood at par = (theta[K - 1], beta[p]); when gr and h are given they receive the gradient and Hessian (q by q)
fn loglik(x: []const f64, cls: []const f64, n: usize, p: usize, nk: usize, link: usize, par: []const f64, gr: []f64, h: []f64, want: bool) -> f64 {
    let q = nk - 1usize + p
    var i = 0usize
    if want {
        while i < q {
            gr[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < q * q {
            h[i] = 0.0f64
            i += 1usize
        }
    }
    var ll = 0.0f64
    var t = 0usize
    while t < n {
        var eta = 0.0f64
        var c = 0usize
        while c < p {
            eta += par[nk - 1usize + c] * x[t * p + c]
            c += 1usize
        }
        let y = usize(cls[t])
        var fa = 1.0f64
        var da = 0.0f64
        var dda = 0.0f64
        var fb = 0.0f64
        var db = 0.0f64
        var ddb = 0.0f64
        if y < nk - 1usize {
            let (u, v, w) = link3(link, par[y] - eta)
            fa = u
            da = v
            dda = w
        }
        if y > 0usize {
            let (u, v, w) = link3(link, par[y - 1usize] - eta)
            fb = u
            db = v
            ddb = w
        }
        let dd = fa - fb
        if !(dd > 0.0f64) { ret 0.0f64 / 0.0f64 }
        ll += math.log[f64](dd)
        if want {
            // dl = (da * da_vec - db * db_vec) / dd with da_vec = e_theta_y - x, db_vec = e_theta_(y-1) - x
            var r = 0usize
            while r < q {
                var va = 0.0f64
                var vb = 0.0f64
                if r < nk - 1usize {
                    if r == y { va = 1.0f64 }
                    if y > 0usize && r == y - 1usize { vb = 1.0f64 }
                } else {
                    va = 0.0f64 - x[t * p + r - (nk - 1usize)]
                    vb = va
                }
                if y == nk - 1usize { va = 0.0f64 }
                if y == 0usize { vb = 0.0f64 }
                gr[r] += (da * va - db * vb) / dd
                var s = 0usize
                while s < q {
                    var wa = 0.0f64
                    var wb = 0.0f64
                    if s < nk - 1usize {
                        if s == y { wa = 1.0f64 }
                        if y > 0usize && s == y - 1usize { wb = 1.0f64 }
                    } else {
                        wa = 0.0f64 - x[t * p + s - (nk - 1usize)]
                        wb = wa
                    }
                    if y == nk - 1usize { wa = 0.0f64 }
                    if y == 0usize { wb = 0.0f64 }
                    let ga2 = da * va - db * vb
                    let gb2 = da * wa - db * wb
                    h[r * q + s] += (dda * va * wa - ddb * vb * wb) / dd - ga2 * gb2 / (dd * dd)
                    s += 1usize
                }
                r += 1usize
            }
        }
        t += 1usize
    }
    ret ll
}

// fits the model: par receives theta (K - 1 values) then beta (p); returns the log-likelihood
fn clm(a: *mem.Arena, x: []const f64, cls: []const f64, n: usize, p: usize, nk: usize, link: usize, par: []f64) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let q = nk - 1usize + p
    let (gr, e1) = mem.alloc[f64](a, q)
    let (h, e2) = mem.alloc[f64](a, q * q)
    let (trial, e3) = mem.alloc[f64](a, q)
    let (cum, e4) = mem.alloc[f64](a, nk)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan }
    var k = 0usize
    while k < nk {
        cum[k] = 0.0f64
        k += 1usize
    }
    var t = 0usize
    while t < n {
        cum[usize(cls[t])] += 1.0f64
        t += 1usize
    }
    var run = 0.0f64
    k = 0usize
    while k < nk - 1usize {
        run += cum[k]
        // a start below the median ordering keeps every cell positive: the cumulative link of the observed proportion
        var pq = run / f64(n)
        if link == 0usize { par[k] = math.log[f64](pq / (1.0f64 - pq)) }
        if link == 1usize { par[k] = dist.qnorm(pq, 0.0f64, 1.0f64, true, false) }
        if link == 2usize { par[k] = math.log[f64](0.0f64 - math.log[f64](1.0f64 - pq)) }
        if link == 3usize { par[k] = 0.0f64 - math.log[f64](0.0f64 - math.log[f64](pq)) }
        if link == 4usize { par[k] = math.tan[f64](3.141592653589793238462643383279f64 * (pq - 0.5f64)) }
        k += 1usize
    }
    var j = 0usize
    while j < p {
        par[nk - 1usize + j] = 0.0f64
        j += 1usize
    }
    var ll = loglik(x, cls, n, p, nk, link, par, gr, h, true)
    var it = 0usize
    while it < 200usize {
        let (inv, ie) = gp.invert(a, h, q)
        if ie != ok { ret nan }
        // Newton step is par - H^-1 g
        var scale = 1.0f64
        var moved = false
        var tries = 0usize
        while tries < 40usize {
            var i = 0usize
            while i < q {
                var d = 0.0f64
                var l = 0usize
                while l < q {
                    d += inv[i * q + l] * gr[l]
                    l += 1usize
                }
                trial[i] = par[i] - scale * d
                i += 1usize
            }
            let ll2 = loglik(x, cls, n, p, nk, link, trial, gr, h, false)
            if ll2 == ll2 && ll2 >= ll - 1.0e-14f64 {
                i = 0usize
                while i < q {
                    par[i] = trial[i]
                    i += 1usize
                }
                let step = math.abs[f64](ll2 - ll)
                ll = loglik(x, cls, n, p, nk, link, par, gr, h, true)
                moved = true
                if step < 1.0e-13f64 { ret ll }
                break
            }
            scale = scale / 2.0f64
            tries += 1usize
        }
        if !moved { break }
        it += 1usize
    }
    ret ll
}
