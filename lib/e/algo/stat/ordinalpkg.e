// R ordinal::clm: the cumulative link model P(y <= j) = F(theta_j - x beta) for logit, probit and cloglog links, fitted by Newton's method with step halving on the exact Hessian (R runs its own Newton on the same likelihood). x has no constant column; classes are 0 .. K - 1.
//
// Not here: flexible thresholds, nominal and scale effects, symmetric thresholds, the other links, weights and predictions.

use e.algo.stat.gparot as gp
use e.algo.stat.nlminb as nl
use e.algo.stat.splinepkg as spl
use e.math
use e.math.dist as dist
use e.math.nmath as nmo
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
fn loglik(x: []const f64, cls: []const f64, wts: []const f64, n: usize, p: usize, nk: usize, link: usize, par: []const f64, gr: []f64, h: []f64, want: bool) -> f64 {
    let q = nk - 1usize + p
    // ordinal puts the outer thresholds at -1e5 and 1e5, not at infinity; that matters for the heavy-tailed cauchit
    let edge = link == 4usize
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
        if edge && y == nk - 1usize {
            let (u, v, w) = link3(link, 100000.0f64 - eta)
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
        if edge && y == 0usize {
            let (u, v, w) = link3(link, 0.0f64 - 100000.0f64 - eta)
            fb = u
            db = v
            ddb = w
        }
        let dd = fa - fb
        if !(dd > 0.0f64) { ret 0.0f64 / 0.0f64 }
        let wt = wts[t]
        ll += wt * math.log[f64](dd)
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
                if y == nk - 1usize && !(edge && r >= nk - 1usize) { va = 0.0f64 }
                if y == 0usize && !(edge && r >= nk - 1usize) { vb = 0.0f64 }
                gr[r] += wt * (da * va - db * vb) / dd
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
                    if y == nk - 1usize && !(edge && s >= nk - 1usize) { wa = 0.0f64 }
                    if y == 0usize && !(edge && s >= nk - 1usize) { wb = 0.0f64 }
                    let ga2 = da * va - db * vb
                    let gb2 = da * wa - db * wb
                    h[r * q + s] += wt * ((dda * va * wa - ddb * vb * wb) / dd - ga2 * gb2 / (dd * dd))
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
fn clm_robust(a: *mem.Arena, x: []const f64, cls: []const f64, wts: []const f64, n: usize, p: usize, nk: usize, link: usize, par: []f64) -> f64 {
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
        cum[usize(cls[t])] += wts[t]
        t += 1usize
    }
    var wsum = 0.0f64
    var kk0 = 0usize
    while kk0 < nk {
        wsum += cum[kk0]
        kk0 += 1usize
    }
    var run = 0.0f64
    k = 0usize
    while k < nk - 1usize {
        run += cum[k]
        // a start below the median ordering keeps every cell positive: the cumulative link of the observed proportion
        var pq = run / wsum
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
    var ll = loglik(x, cls, wts, n, p, nk, link, par, gr, h, true)
    var it = 0usize
    var small = 0usize
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
            let ll2 = loglik(x, cls, wts, n, p, nk, link, trial, gr, h, false)
            if ll2 == ll2 && ll2 >= ll - 1.0e-11f64 {
                i = 0usize
                while i < q {
                    par[i] = trial[i]
                    i += 1usize
                }
                let step = math.abs[f64](ll2 - ll)
                ll = loglik(x, cls, wts, n, p, nk, link, par, gr, h, true)
                moved = true
                if step < 1.0e-9f64 {
                    small += 1usize
                    if small >= 2usize { ret ll }
                }
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

// clm(threshold = "equidistant"): the thresholds are theta_j = a + j b (j = 0 .. K - 2), so the parameters are (a, b, beta); Newton with step halving on the exact Hessian reduced by the chain rule (gradient T' g, Hessian T' H T with theta = T (a, b)).
// par receives the full (theta, beta) vector; the answer is the log-likelihood. K must be at least 3.
fn eq_tcol(c: usize, r: usize, nt: usize) -> f64 {
    if r < nt {
        if c == 0usize { ret 1.0f64 }
        if c == 1usize { ret f64(r) }
        ret 0.0f64
    }
    if c >= 2usize && c - 2usize == r - nt { ret 1.0f64 }
    ret 0.0f64
}

fn clm_equi(a: *mem.Arena, x: []const f64, cls: []const f64, wts: []const f64, n: usize, p: usize, nk: usize, link: usize, par: []f64) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let q = nk - 1usize + p
    let qr = 2usize + p
    let nt = nk - 1usize
    let (gr, e1) = mem.alloc[f64](a, q)
    let (h, e2) = mem.alloc[f64](a, q * q)
    let (gred, e3) = mem.alloc[f64](a, qr)
    let (hred, e4) = mem.alloc[f64](a, qr * qr)
    let (red, e5) = mem.alloc[f64](a, qr)
    let (trial, e6) = mem.alloc[f64](a, qr)
    let (tfull, e7) = mem.alloc[f64](a, q)
    let (cum, e8) = mem.alloc[f64](a, nk)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret nan }
    var k = 0usize
    while k < nk {
        cum[k] = 0.0f64
        k += 1usize
    }
    var t = 0usize
    while t < n {
        cum[usize(cls[t])] += wts[t]
        t += 1usize
    }
    var wsum = 0.0f64
    var kk0 = 0usize
    while kk0 < nk {
        wsum += cum[kk0]
        kk0 += 1usize
    }
    var run = 0.0f64
    var first = 0.0f64
    var last = 0.0f64
    k = 0usize
    while k < nt {
        run += cum[k]
        let pq = run / wsum
        var v = 0.0f64
        if link == 0usize { v = math.log[f64](pq / (1.0f64 - pq)) }
        if link == 1usize { v = dist.qnorm(pq, 0.0f64, 1.0f64, true, false) }
        if link == 2usize { v = math.log[f64](0.0f64 - math.log[f64](1.0f64 - pq)) }
        if link == 3usize { v = 0.0f64 - math.log[f64](0.0f64 - math.log[f64](pq)) }
        if k == 0usize { first = v }
        last = v
        k += 1usize
    }
    red[0usize] = first
    red[1usize] = (last - first) / f64(nt - 1usize)
    var j = 0usize
    while j < p {
        red[2usize + j] = 0.0f64
        j += 1usize
    }
    var ll = 0.0f64
    var it = 0usize
    var small = 0usize
    while it < 200usize {
        k = 0usize
        while k < nt {
            tfull[k] = red[0usize] + f64(k) * red[1usize]
            k += 1usize
        }
        j = 0usize
        while j < p {
            tfull[nt + j] = red[2usize + j]
            j += 1usize
        }
        ll = loglik(x, cls, wts, n, p, nk, link, tfull, gr, h, true)
        if ll != ll { ret nan }
        var c = 0usize
        while c < qr {
            var s = 0.0f64
            var r = 0usize
            while r < q {
                s += eq_tcol(c, r, nt) * gr[r]
                r += 1usize
            }
            gred[c] = s
            var d = 0usize
            while d < qr {
                var hs = 0.0f64
                var r2 = 0usize
                while r2 < q {
                    let t2 = eq_tcol(c, r2, nt)
                    if t2 != 0.0f64 {
                        var r3 = 0usize
                        while r3 < q {
                            hs += t2 * h[r2 * q + r3] * eq_tcol(d, r3, nt)
                            r3 += 1usize
                        }
                    }
                    r2 += 1usize
                }
                hred[c * qr + d] = hs
                d += 1usize
            }
            c += 1usize
        }
        let (inv, ie) = gp.invert(a, hred, qr)
        if ie != ok { ret nan }
        var scale = 1.0f64
        var moved = false
        var tries = 0usize
        while tries < 40usize {
            var i = 0usize
            while i < qr {
                var dd = 0.0f64
                var l = 0usize
                while l < qr {
                    dd += inv[i * qr + l] * gred[l]
                    l += 1usize
                }
                trial[i] = red[i] - scale * dd
                i += 1usize
            }
            k = 0usize
            while k < nt {
                tfull[k] = trial[0usize] + f64(k) * trial[1usize]
                k += 1usize
            }
            j = 0usize
            while j < p {
                tfull[nt + j] = trial[2usize + j]
                j += 1usize
            }
            let ll2 = loglik(x, cls, wts, n, p, nk, link, tfull, gr, h, false)
            if ll2 == ll2 && ll2 >= ll - 1.0e-11f64 {
                i = 0usize
                while i < qr {
                    red[i] = trial[i]
                    i += 1usize
                }
                moved = true
                if math.abs[f64](ll2 - ll) < 1.0e-9f64 {
                    ll = ll2
                    small += 1usize
                    if small >= 2usize { it = 1000usize }
                }
                break
            }
            scale = scale / 2.0f64
            tries += 1usize
        }
        if !moved { break }
        it += 1usize
    }
    k = 0usize
    while k < nt {
        par[k] = red[0usize] + f64(k) * red[1usize]
        k += 1usize
    }
    j = 0usize
    while j < p {
        par[nt + j] = red[2usize + j]
        j += 1usize
    }
    ret ll
}

// clm with the thresholds a linear function of fewer parameters, theta = T alpha (T is nt by na, row-major, nt = K - 1): Newton with step halving on the full gradient and Hessian reduced by the chain rule; par receives the full (theta, beta), the answer is the log-likelihood
fn clm_lin(a: *mem.Arena, x: []const f64, cls: []const f64, wts: []const f64, n: usize, p: usize, nk: usize, link: usize, tm: []const f64, na: usize, par: []f64) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let nt = nk - 1usize
    let q = nt + p
    let qr = na + p
    let (gr, e1) = mem.alloc[f64](a, q)
    let (h, e2) = mem.alloc[f64](a, q * q)
    let (gred, e3) = mem.alloc[f64](a, qr)
    let (hred, e4) = mem.alloc[f64](a, qr * qr)
    let (red, e5) = mem.alloc[f64](a, qr)
    let (trial, e6) = mem.alloc[f64](a, qr)
    let (tfull, e7) = mem.alloc[f64](a, q)
    let (cum, e8) = mem.alloc[f64](a, nk)
    let (v0, e9) = mem.alloc[f64](a, nt)
    let (ttt, e10) = mem.alloc[f64](a, na * na)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret nan }
    var k = 0usize
    while k < nk {
        cum[k] = 0.0f64
        k += 1usize
    }
    var t = 0usize
    while t < n {
        cum[usize(cls[t])] += wts[t]
        t += 1usize
    }
    var wsum = 0.0f64
    var kk0 = 0usize
    while kk0 < nk {
        wsum += cum[kk0]
        kk0 += 1usize
    }
    var run = 0.0f64
    k = 0usize
    while k < nt {
        run += cum[k]
        let pq = run / wsum
        var v = 0.0f64
        if link == 0usize { v = math.log[f64](pq / (1.0f64 - pq)) }
        if link == 1usize { v = dist.qnorm(pq, 0.0f64, 1.0f64, true, false) }
        if link == 2usize { v = math.log[f64](0.0f64 - math.log[f64](1.0f64 - pq)) }
        if link == 3usize { v = 0.0f64 - math.log[f64](0.0f64 - math.log[f64](pq)) }
        v0[k] = v
        k += 1usize
    }
    // start: alpha = (T'T)^-1 T' v0 (beta = 0)
    var i0 = 0usize
    while i0 < na {
        var j0 = 0usize
        while j0 < na {
            var s = 0.0f64
            var r = 0usize
            while r < nt {
                s += tm[r * na + i0] * tm[r * na + j0]
                r += 1usize
            }
            ttt[i0 * na + j0] = s
            j0 += 1usize
        }
        var sv = 0.0f64
        var r2 = 0usize
        while r2 < nt {
            sv += tm[r2 * na + i0] * v0[r2]
            r2 += 1usize
        }
        red[i0] = sv
        i0 += 1usize
    }
    let (tinv, eti) = gp.invert(a, ttt, na)
    if eti != ok { ret nan }
    i0 = 0usize
    while i0 < na {
        var s = 0.0f64
        var j0 = 0usize
        while j0 < na {
            s += tinv[i0 * na + j0] * red[j0]
            j0 += 1usize
        }
        trial[i0] = s
        i0 += 1usize
    }
    i0 = 0usize
    while i0 < na {
        red[i0] = trial[i0]
        i0 += 1usize
    }
    var j = 0usize
    while j < p {
        red[na + j] = 0.0f64
        j += 1usize
    }
    var ll = 0.0f64
    var it = 0usize
    var small = 0usize
    while it < 200usize {
        k = 0usize
        while k < nt {
            var s = 0.0f64
            var c0 = 0usize
            while c0 < na {
                s += tm[k * na + c0] * red[c0]
                c0 += 1usize
            }
            tfull[k] = s
            k += 1usize
        }
        j = 0usize
        while j < p {
            tfull[nt + j] = red[na + j]
            j += 1usize
        }
        ll = loglik(x, cls, wts, n, p, nk, link, tfull, gr, h, true)
        if ll != ll { ret nan }
        var c = 0usize
        while c < qr {
            var s = 0.0f64
            var r = 0usize
            while r < q {
                s += lin_t(tm, na, nt, c, r) * gr[r]
                r += 1usize
            }
            gred[c] = s
            var d = 0usize
            while d < qr {
                var hs = 0.0f64
                var r2 = 0usize
                while r2 < q {
                    let t2 = lin_t(tm, na, nt, c, r2)
                    if t2 != 0.0f64 {
                        var r3 = 0usize
                        while r3 < q {
                            hs += t2 * h[r2 * q + r3] * lin_t(tm, na, nt, d, r3)
                            r3 += 1usize
                        }
                    }
                    r2 += 1usize
                }
                hred[c * qr + d] = hs
                d += 1usize
            }
            c += 1usize
        }
        let (inv, ie) = gp.invert(a, hred, qr)
        if ie != ok { ret nan }
        var scale = 1.0f64
        var moved = false
        var tries = 0usize
        while tries < 40usize {
            var i = 0usize
            while i < qr {
                var dd = 0.0f64
                var l = 0usize
                while l < qr {
                    dd += inv[i * qr + l] * gred[l]
                    l += 1usize
                }
                trial[i] = red[i] - scale * dd
                i += 1usize
            }
            k = 0usize
            while k < nt {
                var s = 0.0f64
                var c1 = 0usize
                while c1 < na {
                    s += tm[k * na + c1] * trial[c1]
                    c1 += 1usize
                }
                tfull[k] = s
                k += 1usize
            }
            j = 0usize
            while j < p {
                tfull[nt + j] = trial[na + j]
                j += 1usize
            }
            let ll2 = loglik(x, cls, wts, n, p, nk, link, tfull, gr, h, false)
            if ll2 == ll2 && ll2 >= ll - 1.0e-11f64 {
                i = 0usize
                while i < qr {
                    red[i] = trial[i]
                    i += 1usize
                }
                moved = true
                if math.abs[f64](ll2 - ll) < 1.0e-9f64 {
                    ll = ll2
                    small += 1usize
                    if small >= 2usize { it = 1000usize }
                }
                break
            }
            scale = scale / 2.0f64
            tries += 1usize
        }
        if !moved { break }
        it += 1usize
    }
    k = 0usize
    while k < nt {
        var s = 0.0f64
        var c2 = 0usize
        while c2 < na {
            s += tm[k * na + c2] * red[c2]
            c2 += 1usize
        }
        par[k] = s
        k += 1usize
    }
    j = 0usize
    while j < p {
        par[nt + j] = red[na + j]
        j += 1usize
    }
    ret ll
}

// the (r, c) entry of the full-parameter map: theta = T alpha, beta unchanged
fn lin_t(tm: []const f64, na: usize, nt: usize, c: usize, r: usize) -> f64 {
    if r < nt { if c < na { ret tm[r * na + c] } else { ret 0.0f64 } }
    if c >= na && c - na == r - nt { ret 1.0f64 }
    ret 0.0f64
}

// the threshold maps of ordinal: kind 1 equidistant (threshold.1, spacing), 2 symmetric (central[s] then spacings); tm (nt by na) is filled and na returned
fn thr_map(kind: usize, nt: usize, tm: []f64) -> usize {
    if kind == 1usize {
        var j = 0usize
        while j < nt {
            tm[j * 2usize] = 1.0f64
            tm[j * 2usize + 1usize] = f64(j)
            j += 1usize
        }
        ret 2usize
    }
    if nt % 2usize == 1usize {
        // odd count 2 m + 1: alpha = (c, s_1 .. s_m)
        let m = nt / 2usize
        let na = 1usize + m
        var j = 0usize
        while j < nt * na {
            tm[j] = 0.0f64
            j += 1usize
        }
        tm[m * na] = 1.0f64
        var i = 1usize
        while i <= m {
            tm[(m + i) * na] = 1.0f64
            tm[(m + i) * na + i] = 1.0f64
            tm[(m - i) * na] = 1.0f64
            tm[(m - i) * na + i] = 0.0f64 - 1.0f64
            i += 1usize
        }
        ret na
    }
    // even count 2 m: alpha = (c1, c2, s_1 .. s_{m-1})
    let m = nt / 2usize
    let na = 1usize + m
    var j = 0usize
    while j < nt * na {
        tm[j] = 0.0f64
        j += 1usize
    }
    tm[(m - 1usize) * na] = 1.0f64
    tm[m * na + 1usize] = 1.0f64
    var i = 1usize
    while i < m {
        tm[(m - 1usize - i) * na] = 1.0f64
        tm[(m - 1usize - i) * na + 1usize + i] = 0.0f64 - 1.0f64
        tm[(m + i) * na + 1usize] = 1.0f64
        tm[(m + i) * na + 1usize + i] = 1.0f64
        i += 1usize
    }
    ret na
}

// predict(fit, newdata, type = "prob") of a clm: out (n by nk, row-major) receives P(y = j) = F(theta_j - eta) - F(theta_(j-1) - eta) for the new design x (n by p) and par = (theta, beta)
fn clm_predict_prob(x: []const f64, n: usize, p: usize, nk: usize, link: usize, par: []const f64, out: []f64) {
    var t = 0usize
    while t < n {
        var eta = 0.0f64
        var c = 0usize
        while c < p {
            eta += par[nk - 1usize + c] * x[t * p + c]
            c += 1usize
        }
        var j = 0usize
        while j < nk {
            // the outer thresholds are +-1e5 as in the fit, so heavy-tailed links keep their tail mass
            var hi = 100000.0f64
            var lo = 0.0f64 - 100000.0f64
            if j < nk - 1usize { hi = par[j] }
            if j > 0usize { lo = par[j - 1usize] }
            let (fa, va, wa) = link3(link, hi - eta)
            let (fb, vb, wb) = link3(link, lo - eta)
            let _ = va
            let _ = wa
            let _ = vb
            let _ = wb
            out[t * nk + j] = fa - fb
            j += 1usize
        }
        t += 1usize
    }
}

// anova(fit0, fit1) of two nested clm fits: the likelihood-ratio statistic 2 (ll1 - ll0) and its chi-square p-value on df = the difference of the parameter counts; out[0] the statistic, out[1] the p-value
fn clm_anova(ll0: f64, ll1: f64, df: f64, out: []f64) {
    let st = 2.0f64 * (ll1 - ll0)
    out[0usize] = st
    out[1usize] = nmo.pchisq(st, df, false, false)
}

// clm(scale = ~ z): the cumulative link model with a log-linear scale, P(y <= j) = F((theta_j - x beta) / exp(z zeta)); par = (theta[K - 1], beta[p], zeta[ps]); returns the log-likelihood and, when want, the analytic gradient in gr
fn loglik_scale(x: []const f64, zs: []const f64, cls: []const f64, wts: []const f64, n: usize, p: usize, ps: usize, nk: usize, link: usize, par: []const f64, gr: []f64, want: bool) -> f64 {
    let nt = nk - 1usize
    let q = nt + p + ps
    var i = 0usize
    if want {
        while i < q {
            gr[i] = 0.0f64
            i += 1usize
        }
    }
    var ll = 0.0f64
    var t = 0usize
    while t < n {
        var eta = 0.0f64
        var c = 0usize
        while c < p {
            eta += par[nt + c] * x[t * p + c]
            c += 1usize
        }
        var s = 0.0f64
        c = 0usize
        while c < ps {
            s += par[nt + p + c] * zs[t * ps + c]
            c += 1usize
        }
        let sg = math.exp[f64](s)
        let y = usize(cls[t])
        var fhi = 1.0f64
        var dhi = 0.0f64
        var uhi = 0.0f64
        var flo = 0.0f64
        var dlo = 0.0f64
        var ulo = 0.0f64
        if y < nt {
            uhi = (par[y] - eta) / sg
            let (u, v, w) = link3(link, uhi)
            fhi = u
            dhi = v
            let _ = w
        }
        if y > 0usize {
            ulo = (par[y - 1usize] - eta) / sg
            let (u, v, w) = link3(link, ulo)
            flo = u
            dlo = v
            let _ = w
        }
        let pr = fhi - flo
        if !(pr > 0.0f64) { ret 0.0f64 / 0.0f64 }
        ll += wts[t] * math.log[f64](pr)
        if want {
            let wt = wts[t] / pr
            if y < nt { gr[y] += wt * dhi / sg }
            if y > 0usize { gr[y - 1usize] -= wt * dlo / sg }
            c = 0usize
            while c < p {
                gr[nt + c] -= wt * (dhi - dlo) / sg * x[t * p + c]
                c += 1usize
            }
            var term = 0.0f64
            if y < nt { term += dhi * uhi }
            if y > 0usize { term -= dlo * ulo }
            c = 0usize
            while c < ps {
                gr[nt + p + c] -= wt * term * zs[t * ps + c]
                c += 1usize
            }
        }
        t += 1usize
    }
    ret ll
}

// Newton fit of the location-scale clm with a central-difference Hessian of the analytic gradient and step halving; par receives (theta, beta, zeta); the answer is the log-likelihood
fn clm_scale(a: *mem.Arena, x: []const f64, zs: []const f64, cls: []const f64, wts: []const f64, n: usize, p: usize, ps: usize, nk: usize, link: usize, par: []f64) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let nt = nk - 1usize
    let q = nt + p + ps
    let (gr, e1) = mem.alloc[f64](a, q)
    let (g1, e2) = mem.alloc[f64](a, q)
    let (g2, e3) = mem.alloc[f64](a, q)
    let (h, e4) = mem.alloc[f64](a, q * q)
    let (trial, e5) = mem.alloc[f64](a, q)
    let (w, e6) = mem.alloc[f64](a, q)
    let (cum, e7) = mem.alloc[f64](a, nk)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret nan }
    var k = 0usize
    while k < nk {
        cum[k] = 0.0f64
        k += 1usize
    }
    var tt = 0usize
    var wsum = 0.0f64
    while tt < n {
        cum[usize(cls[tt])] += wts[tt]
        wsum += wts[tt]
        tt += 1usize
    }
    var run = 0.0f64
    k = 0usize
    while k < nt {
        run += cum[k]
        let pq = run / wsum
        var v = 0.0f64
        if link == 0usize { v = math.log[f64](pq / (1.0f64 - pq)) }
        if link == 1usize { v = dist.qnorm(pq, 0.0f64, 1.0f64, true, false) }
        if link == 2usize { v = math.log[f64](0.0f64 - math.log[f64](1.0f64 - pq)) }
        if link == 3usize { v = 0.0f64 - math.log[f64](0.0f64 - math.log[f64](pq)) }
        par[k] = v
        k += 1usize
    }
    k = nt
    while k < q {
        par[k] = 0.0f64
        k += 1usize
    }
    var ll = loglik_scale(x, zs, cls, wts, n, p, ps, nk, link, par, gr, true)
    if ll != ll { ret nan }
    var it = 0usize
    var small = 0usize
    while it < 200usize {
        // Hessian by central differences of the gradient
        var c = 0usize
        while c < q {
            let hstep = 1.0e-5f64 * (1.0f64 + math.abs[f64](par[c]))
            var d = 0usize
            while d < q {
                w[d] = par[d]
                d += 1usize
            }
            w[c] = par[c] + hstep
            let _a = loglik_scale(x, zs, cls, wts, n, p, ps, nk, link, w, g1, true)
            w[c] = par[c] - hstep
            let _b = loglik_scale(x, zs, cls, wts, n, p, ps, nk, link, w, g2, true)
            d = 0usize
            while d < q {
                h[c * q + d] = (g1[d] - g2[d]) / (2.0f64 * hstep)
                d += 1usize
            }
            c += 1usize
        }
        // symmetrise
        c = 0usize
        while c < q {
            var d = c + 1usize
            while d < q {
                let m2 = 0.5f64 * (h[c * q + d] + h[d * q + c])
                h[c * q + d] = m2
                h[d * q + c] = m2
                d += 1usize
            }
            c += 1usize
        }
        let (inv, ie) = gp.invert(a, h, q)
        if ie != ok { ret nan }
        var scale = 1.0f64
        var moved = false
        var tries = 0usize
        while tries < 40usize {
            var i = 0usize
            while i < q {
                var dd = 0.0f64
                var l = 0usize
                while l < q {
                    dd += inv[i * q + l] * gr[l]
                    l += 1usize
                }
                trial[i] = par[i] - scale * dd
                i += 1usize
            }
            let ll2 = loglik_scale(x, zs, cls, wts, n, p, ps, nk, link, trial, g1, false)
            if ll2 == ll2 && ll2 >= ll - 1.0e-11f64 {
                i = 0usize
                while i < q {
                    par[i] = trial[i]
                    i += 1usize
                }
                let step = math.abs[f64](ll2 - ll)
                ll = loglik_scale(x, zs, cls, wts, n, p, ps, nk, link, par, gr, true)
                moved = true
                if step < 1.0e-9f64 {
                    small += 1usize
                    if small >= 2usize { ret ll }
                }
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

// clm(nominal = ~ w): every threshold carries its own covariate effects, P(y <= j) = F(theta_j + sgn * w tau_j - x beta) (sgn 1 or -1); par = (theta[K - 1], beta[p], tau[(K - 1) * pn] stored threshold after threshold); returns the log-likelihood and, when want, the analytic gradient
fn loglik_nominal(x: []const f64, ws: []const f64, cls: []const f64, wts: []const f64, n: usize, p: usize, pn: usize, nk: usize, link: usize, sgn: f64, par: []const f64, gr: []f64, want: bool) -> f64 {
    let nt = nk - 1usize
    let q = nt + p + nt * pn
    var i = 0usize
    if want {
        while i < q {
            gr[i] = 0.0f64
            i += 1usize
        }
    }
    var ll = 0.0f64
    var t = 0usize
    while t < n {
        var eta = 0.0f64
        var c = 0usize
        while c < p {
            eta += par[nt + c] * x[t * p + c]
            c += 1usize
        }
        let y = usize(cls[t])
        var fhi = 1.0f64
        var dhi = 0.0f64
        var flo = 0.0f64
        var dlo = 0.0f64
        if y < nt {
            var wt = 0.0f64
            c = 0usize
            while c < pn {
                wt += par[nt + p + y * pn + c] * ws[t * pn + c]
                c += 1usize
            }
            let (u, v, w) = link3(link, par[y] + sgn * wt - eta)
            fhi = u
            dhi = v
            let _ = w
        }
        if y > 0usize {
            var wt = 0.0f64
            c = 0usize
            while c < pn {
                wt += par[nt + p + (y - 1usize) * pn + c] * ws[t * pn + c]
                c += 1usize
            }
            let (u, v, w) = link3(link, par[y - 1usize] + sgn * wt - eta)
            flo = u
            dlo = v
            let _ = w
        }
        let pr = fhi - flo
        if !(pr > 0.0f64) { ret 0.0f64 / 0.0f64 }
        ll += wts[t] * math.log[f64](pr)
        if want {
            let wq = wts[t] / pr
            if y < nt {
                gr[y] += wq * dhi
                c = 0usize
                while c < pn {
                    gr[nt + p + y * pn + c] += wq * dhi * sgn * ws[t * pn + c]
                    c += 1usize
                }
            }
            if y > 0usize {
                gr[y - 1usize] -= wq * dlo
                c = 0usize
                while c < pn {
                    gr[nt + p + (y - 1usize) * pn + c] -= wq * dlo * sgn * ws[t * pn + c]
                    c += 1usize
                }
            }
            c = 0usize
            while c < p {
                gr[nt + c] -= wq * (dhi - dlo) * x[t * p + c]
                c += 1usize
            }
        }
        t += 1usize
    }
    ret ll
}

// Newton fit of the nominal-effects clm by the same central-difference Hessian scheme; par receives (theta, beta, tau); the answer is the log-likelihood
fn clm_nominal(a: *mem.Arena, x: []const f64, ws: []const f64, cls: []const f64, wts: []const f64, n: usize, p: usize, pn: usize, nk: usize, link: usize, sgn: f64, par: []f64) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let nt = nk - 1usize
    let q = nt + p + nt * pn
    let (gr, e1) = mem.alloc[f64](a, q)
    let (g1, e2) = mem.alloc[f64](a, q)
    let (g2, e3) = mem.alloc[f64](a, q)
    let (h, e4) = mem.alloc[f64](a, q * q)
    let (trial, e5) = mem.alloc[f64](a, q)
    let (w, e6) = mem.alloc[f64](a, q)
    let (cum, e7) = mem.alloc[f64](a, nk)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret nan }
    var k = 0usize
    while k < nk {
        cum[k] = 0.0f64
        k += 1usize
    }
    var tt = 0usize
    var wsum = 0.0f64
    while tt < n {
        cum[usize(cls[tt])] += wts[tt]
        wsum += wts[tt]
        tt += 1usize
    }
    var run = 0.0f64
    k = 0usize
    while k < nt {
        run += cum[k]
        let pq = run / wsum
        var v = 0.0f64
        if link == 0usize { v = math.log[f64](pq / (1.0f64 - pq)) }
        if link == 1usize { v = dist.qnorm(pq, 0.0f64, 1.0f64, true, false) }
        if link == 2usize { v = math.log[f64](0.0f64 - math.log[f64](1.0f64 - pq)) }
        if link == 3usize { v = 0.0f64 - math.log[f64](0.0f64 - math.log[f64](pq)) }
        par[k] = v
        k += 1usize
    }
    k = nt
    while k < q {
        par[k] = 0.0f64
        k += 1usize
    }
    var ll = loglik_nominal(x, ws, cls, wts, n, p, pn, nk, link, sgn, par, gr, true)
    if ll != ll { ret nan }
    var it = 0usize
    var small = 0usize
    while it < 300usize {
        var c = 0usize
        while c < q {
            let hstep = 1.0e-5f64 * (1.0f64 + math.abs[f64](par[c]))
            var d = 0usize
            while d < q {
                w[d] = par[d]
                d += 1usize
            }
            w[c] = par[c] + hstep
            let _a = loglik_nominal(x, ws, cls, wts, n, p, pn, nk, link, sgn, w, g1, true)
            w[c] = par[c] - hstep
            let _b = loglik_nominal(x, ws, cls, wts, n, p, pn, nk, link, sgn, w, g2, true)
            d = 0usize
            while d < q {
                h[c * q + d] = (g1[d] - g2[d]) / (2.0f64 * hstep)
                d += 1usize
            }
            c += 1usize
        }
        c = 0usize
        while c < q {
            var d = c + 1usize
            while d < q {
                let m2 = 0.5f64 * (h[c * q + d] + h[d * q + c])
                h[c * q + d] = m2
                h[d * q + c] = m2
                d += 1usize
            }
            c += 1usize
        }
        let (inv, ie) = gp.invert(a, h, q)
        if ie != ok { ret nan }
        var scale = 1.0f64
        var moved = false
        var tries = 0usize
        while tries < 40usize {
            var i = 0usize
            while i < q {
                var dd = 0.0f64
                var l = 0usize
                while l < q {
                    dd += inv[i * q + l] * gr[l]
                    l += 1usize
                }
                trial[i] = par[i] - scale * dd
                i += 1usize
            }
            let ll2 = loglik_nominal(x, ws, cls, wts, n, p, pn, nk, link, sgn, trial, g1, false)
            if ll2 == ll2 && ll2 >= ll - 1.0e-11f64 {
                i = 0usize
                while i < q {
                    par[i] = trial[i]
                    i += 1usize
                }
                let step = math.abs[f64](ll2 - ll)
                ll = loglik_nominal(x, ws, cls, wts, n, p, pn, nk, link, sgn, par, gr, true)
                moved = true
                if step < 1.0e-9f64 {
                    small += 1usize
                    if small >= 2usize { ret ll }
                }
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

// ---- R's own fitting path (clm_fit_NR, clm_fit_flex, clmm with a single random intercept): the same iterations as ordinal runs, so a run equals R's wherever R's start and stopping rules decide the answer.

// the lower Cholesky factor of the q x q matrix m into l (false when not positive definite, as LAPACK dpotrf judges it)
fn chol_lower(m: []const f64, l: []f64, q: usize) -> bool {
    var j = 0usize
    while j < q {
        var s = m[j * q + j]
        var k = 0usize
        while k < j {
            s -= l[j * q + k] * l[j * q + k]
            k += 1usize
        }
        if !(s > 0.0f64) { ret false }
        let d = math.sqrt[f64](s)
        l[j * q + j] = d
        var i = j + 1usize
        while i < q {
            var t = m[i * q + j]
            k = 0usize
            while k < j {
                t -= l[i * q + k] * l[j * q + k]
                k += 1usize
            }
            l[i * q + j] = t / d
            i += 1usize
        }
        j += 1usize
    }
    ret true
}

fn max_abs_v(v: []const f64, q: usize) -> f64 {
    var m = 0.0f64
    var i = 0usize
    while i < q {
        let t = math.abs[f64](v[i])
        if t > m || t != t { m = t }
        i += 1usize
    }
    ret m
}

// the negative log-likelihood, infinite when a cell is not positive
fn nll_of(x: []const f64, cls: []const f64, wts: []const f64, n: usize, p: usize, nk: usize, link: usize, par: []const f64, gr: []f64, h: []f64) -> f64 {
    let ll = loglik(x, cls, wts, n, p, nk, link, par, gr, h, false)
    if !(ll == ll) { ret math.inf64() }
    ret 0.0f64 - ll
}

// ordinal's clm_fit_NR from the start in par: Newton with a Cholesky solve, the step halved while the negative log-likelihood rises; returns the log-likelihood at par, NaN when R would fail
fn clm_nr(a: *mem.Arena, x: []const f64, cls: []const f64, wts: []const f64, n: usize, p: usize, nk: usize, link: usize, par: []f64, grad_tol: f64, rel_tol: f64, max_iter: usize) -> f64 {
    ret clm_nrf(a, x, cls, wts, n, p, nk, link, par, grad_tol, rel_tol, max_iter, nk - 1usize + p)
}

// row and column fix of the Hessian h and entry fix of the gradient g held out of the Newton step (fix >= q holds none): a parameter fixed at its value, as profile.clm does with an offset
fn mask_fix(g: []f64, h: []f64, q: usize, fix: usize) {
    if fix >= q { ret }
    g[fix] = 0.0f64
    var k = 0usize
    while k < q {
        h[fix * q + k] = 0.0f64
        h[k * q + fix] = 0.0f64
        k += 1usize
    }
    h[fix * q + fix] = 1.0f64
}

// clm_nr with parameter fix held at its value in par
fn clm_nrf(a: *mem.Arena, x: []const f64, cls: []const f64, wts: []const f64, n: usize, p: usize, nk: usize, link: usize, par: []f64, grad_tol: f64, rel_tol: f64, max_iter: usize, fix: usize) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let q = nk - 1usize + p
    let (gr, e1) = mem.alloc[f64](a, q)
    let (g2, e2) = mem.alloc[f64](a, q)
    let (h, e3) = mem.alloc[f64](a, q * q)
    let (hn, e4) = mem.alloc[f64](a, q * q)
    let (l, e5) = mem.alloc[f64](a, q * q)
    let (st, e6) = mem.alloc[f64](a, q)
    let (zz, e7) = mem.alloc[f64](a, q)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret nan }
    var nll = nll_of(x, cls, wts, n, p, nk, link, par, g2, hn)
    if !(nll < math.inf64()) { ret nan }
    var step_factor = 1.0f64
    var abs_iter = 0usize
    var i = 0usize
    while i <= max_iter {
        let _ = loglik(x, cls, wts, n, p, nk, link, par, gr, h, true)
        // the gradient and Hessian of the negative log-likelihood are the negatives
        var r = 0usize
        while r < q {
            gr[r] = 0.0f64 - gr[r]
            r += 1usize
        }
        r = 0usize
        while r < q * q {
            hn[r] = 0.0f64 - h[r]
            r += 1usize
        }
        mask_fix(gr, hn, q, fix)
        let max_grad = max_abs_v(gr, q)
        let abs_conv = max_grad < grad_tol
        if abs_conv { abs_iter += 1usize }
        if !chol_lower(hn, l, q) {
            if abs_conv { break }
            ret nan
        }
        // solve (l l') s = g
        r = 0usize
        while r < q {
            var s = gr[r]
            var k = 0usize
            while k < r {
                s -= l[r * q + k] * zz[k]
                k += 1usize
            }
            zz[r] = s / l[r * q + r]
            r += 1usize
        }
        r = q
        while r > 0usize {
            r -= 1usize
            var s = zz[r]
            var k = r + 1usize
            while k < q {
                s -= l[k * q + r] * st[k]
                k += 1usize
            }
            st[r] = s / l[r * q + r]
        }
        let rel_conv = max_abs_v(st, q) < rel_tol
        if abs_conv && rel_conv { break }
        r = 0usize
        while r < q {
            par[r] = par[r] - step_factor * st[r]
            r += 1usize
        }
        var nll_try = nll_of(x, cls, wts, n, p, nk, link, par, g2, hn)
        var stephalf = nll_try > nll
        if stephalf && math.abs[f64](nll - nll_try) < 1.0e-10f64 {
            let _ = loglik(x, cls, wts, n, p, nk, link, par, g2, hn, true)
            mask_fix(g2, hn, q, fix)
            stephalf = max_grad < max_abs_v(g2, q)
        }
        if abs_conv && stephalf {
            r = 0usize
            while r < q {
                par[r] = par[r] + step_factor * st[r]
                r += 1usize
            }
            break
        }
        if abs_conv && abs_iter >= 5usize { break }
        var line_iter = 0usize
        var failed = false
        while stephalf {
            step_factor = step_factor / 2.0f64
            r = 0usize
            while r < q {
                par[r] = par[r] + step_factor * st[r]
                r += 1usize
            }
            nll_try = nll_of(x, cls, wts, n, p, nk, link, par, g2, hn)
            line_iter += 1usize
            if line_iter > 15usize {
                failed = true
                break
            }
            stephalf = nll_try > nll
            if stephalf && math.abs[f64](nll - nll_try) < 1.0e-10f64 {
                let _ = loglik(x, cls, wts, n, p, nk, link, par, g2, hn, true)
                mask_fix(g2, hn, q, fix)
                stephalf = max_grad < max_abs_v(g2, q)
            }
        }
        if failed { break }
        nll = nll_try
        step_factor = math.min[f64](1.0f64, 2.0f64 * step_factor)
        i += 1usize
    }
    ret loglik(x, cls, wts, n, p, nk, link, par, g2, hn, false)
}

// ordinal's start: thresholds qlogis(j / K), coefficients 0
fn clm_start_r(nk: usize, p: usize, par: []f64) {
    var j = 0usize
    while j < nk - 1usize {
        let pj = f64(j + 1usize) / f64(nk)
        par[j] = math.log[f64](pj / (1.0f64 - pj))
        j += 1usize
    }
    j = 0usize
    while j < p {
        par[nk - 1usize + j] = 0.0f64
        j += 1usize
    }
}

// clm(link = ...) the way ordinal fits it: R's start, and for cauchit a loose probit fit first (set.start)
fn clm_r(a: *mem.Arena, x: []const f64, cls: []const f64, wts: []const f64, n: usize, p: usize, nk: usize, link: usize, par: []f64, grad_tol: f64, max_iter: usize) -> f64 {
    clm_start_r(nk, p, par)
    if link == 4usize {
        let l0 = clm_nr(a, x, cls, wts, n, p, nk, 1usize, par, 1.0e-3f64, 1.0e-3f64, 100usize)
        if !(l0 == l0) { ret l0 }
    }
    ret clm_nr(a, x, cls, wts, n, p, nk, link, par, grad_tol, 1.0e-6f64, max_iter)
}

// fits the model: par receives theta (K - 1 values) then beta (p); returns the log-likelihood (R's iterations, the robust Newton when those fail)
fn clm(a: *mem.Arena, x: []const f64, cls: []const f64, wts: []const f64, n: usize, p: usize, nk: usize, link: usize, par: []f64) -> f64 {
    let r = clm_r(a, x, cls, wts, n, p, nk, link, par, 1.0e-10f64, 500usize)
    if r == r { ret r }
    ret clm_robust(a, x, cls, wts, n, p, nk, link, par)
}

// ---- the flexible links: clm(link = "Aranda-Ordaz") and clm(link = "log-gamma") estimate lambda with nlminb (R's clm_fit_flex), starting from a loose probit fit

type Flx = struct { x: []const f64, cls: []const f64, wts: []const f64, n: usize, p: usize, nk: usize, link: usize }

// the cumulative distribution of the link at q for lambda (link 5 Aranda-Ordaz, 6 log-gamma): ordinal's d_pAO and d_plgamma, lower tail
fn pflex(link: usize, q: f64, lam: f64) -> f64 {
    if link == 5usize {
        ret 1.0f64 - math.pow[f64](lam * math.exp[f64](q) + 1.0f64, 0.0f64 - 1.0f64 / lam)
    }
    if lam <= 1.0e-6f64 && lam >= 0.0f64 - 1.0e-6f64 { ret dist.pnorm(q, 0.0f64, 1.0f64, true, false) }
    let q2 = 1.0f64 / (lam * lam)
    let v = q2 * math.exp[f64](lam * q)
    if lam < 0.0f64 { ret 1.0f64 - nmo.pgamma(v, q2, 1.0f64, true, false) }
    ret nmo.pgamma(v, q2, 1.0f64, true, false)
}

// the negative log-likelihood of the flexible-link model at par = (theta, beta, lambda); ordinal puts the outer thresholds at -1e5 and 1e5
fn flex_obj(c: *Flx, par: []const f64) -> f64 {
    let nk = c.nk
    let p = c.p
    let lam = par[nk - 1usize + p]
    var acc = 0.0f64
    var ld = Ld { m: 0u64, e: 0i64 }
    var pos = false
    var t = 0usize
    while t < c.n {
        let y = usize(c.cls[t])
        var s1 = 0.0f64
        var s2 = 0.0f64
        if y < nk - 1usize { s1 = par[y] }
        if y > 0usize { s2 = par[y - 1usize] }
        var j = 0usize
        while j < p {
            let tb = (0.0f64 - c.x[t * p + j]) * par[nk - 1usize + j]
            s1 += tb
            s2 += tb
            j += 1usize
        }
        var e1 = s1
        var e2 = s2
        if y == nk - 1usize { e1 = s1 + 100000.0f64 }
        if y == 0usize { e2 = s2 - 100000.0f64 }
        let fit = pflex(c.link, e1, lam) - pflex(c.link, e2, lam)
        if !(fit > 0.0f64) || fit == math.inf64() { ret math.inf64() }
        let term = c.wts[t] * math.log[f64](fit)
        acc += term
        ld = ld_add(ld, 0.0f64 - term)
        if term > 0.0f64 { pos = true }
        t += 1usize
    }
    if pos { ret 0.0f64 - acc }
    ret ld_to_f64(ld)
}

fn flex_grad(c: *Flx, par: []const f64, g: []f64) {
}

// fits the model; par receives theta (K - 1 values), beta (p) and lambda; link 5 or 6; returns the log-likelihood
fn clm_flex(a: *mem.Arena, x: []const f64, cls: []const f64, wts: []const f64, n: usize, p: usize, nk: usize, link: usize, par: []f64) -> f64 {
    let r = clm_flex_fit(a, x, cls, wts, n, p, nk, link, par)
    ret 0.0f64 - r.objective
}

// the fit itself, returning nlminb's result (objective NaN when the start fails)
fn clm_flex_fit(a: *mem.Arena, x: []const f64, cls: []const f64, wts: []const f64, n: usize, p: usize, nk: usize, link: usize, par: []f64) -> nl.Nlminb {
    let nan = 0.0f64 / 0.0f64
    let q = nk - 1usize + p
    var r = nl.Nlminb { objective: nan, code: 0i64, iterations: 0usize, fevals: 0usize, gevals: 0usize }
    clm_start_r(nk, p, par)
    let l0 = clm_nr(a, x, cls, wts, n, p, nk, 1usize, par[0usize..q], 1.0e-3f64, 1.0e-3f64, 100usize)
    if !(l0 == l0) { ret r }
    par[q] = 1.0f64
    if link == 6usize { par[q] = 0.1f64 }
    var c = Flx { x: x, cls: cls, wts: wts, n: n, p: p, nk: nk, link: link }
    var none: [1]f64 = zero
    if link == 5usize {
        let (lo, e1) = mem.alloc[f64](a, q + 1usize)
        let (hi, e2) = mem.alloc[f64](a, q + 1usize)
        if e1 != ok || e2 != ok { ret r }
        var i = 0usize
        while i < q {
            lo[i] = 0.0f64 - math.inf64()
            hi[i] = math.inf64()
            i += 1usize
        }
        lo[q] = 1.0e-5f64
        hi[q] = math.inf64()
        r = nl.nlminb_bounded[Flx](a, &c, flex_obj, flex_grad, false, par, none[0usize..0usize], lo, hi)
    } else {
        r = nl.nlminb[Flx](a, &c, flex_obj, flex_grad, false, par, none[0usize..0usize])
    }
    ret r
}

// ---- R's sum() accumulates in an 80-bit long double (64-bit significand); the nlminb run is sensitive to that last rounding through its finite-difference gradient, so the sum of the negative terms of a log-likelihood is carried the same way. A value is m * 2^e with m normalised (bit 63 set), or m = 0.

type Ld = struct { m: u64, e: i64 }

// m * 2^e shifted right by d bits as a 128-bit (hi, lo) pair, with a flag for any one bit lost
fn ld_shr(hi: u64, lo: u64, d: usize) -> (u64, u64, bool) {
    if d == 0usize { ret (hi, lo, false) }
    if d < 64usize {
        let lost = (lo << u64(64usize - d)) != 0u64
        ret (hi >> u64(d), (lo >> u64(d)) | (hi << u64(64usize - d)), lost)
    }
    if d == 64usize { ret (0u64, hi, lo != 0u64) }
    if d < 128usize {
        let k = d - 64usize
        let lost = lo != 0u64 || (hi << u64(64usize - k)) != 0u64
        ret (0u64, hi >> u64(k), lost)
    }
    ret (0u64, 0u64, hi != 0u64 || lo != 0u64)
}

// acc + x for a positive finite double x, rounded to 64 bits to nearest even
fn ld_add(acc: Ld, x: f64) -> Ld {
    if !(x > 0.0f64) { ret acc }
    let bits = mem.bitcast[u64](x)
    let ex0 = i64(bits >> 52u64 & 2047u64)
    var mx = bits & 4503599627370495u64
    var ex = ex0 - 1075i64
    if ex0 == 0i64 {
        ex = 0i64 - 1074i64
    } else {
        mx = mx | 4503599627370496u64
    }
    // normalise to bit 63
    while (mx >> 63u64) == 0u64 {
        mx = mx << 1u64
        ex -= 1i64
    }
    if acc.m == 0u64 { ret Ld { m: mx, e: ex } }
    var mbig = acc.m
    var ebig = acc.e
    var msm = mx
    var esm = ex
    if ex > acc.e {
        mbig = mx
        ebig = ex
        msm = acc.m
        esm = acc.e
    }
    let dd = ebig - esm
    var d = 200usize
    if dd < 200i64 { d = usize(dd) }
    let (sh, sl, lost) = ld_shr(msm, 0u64, d)
    var hi = mbig +% sh
    var lo = sl
    var carry = hi < mbig
    var sticky = lost
    var e = ebig
    if carry {
        if (lo & 1u64) != 0u64 { sticky = true }
        lo = (lo >> 1u64) | (hi << 63u64)
        hi = (hi >> 1u64) | 9223372036854775808u64
        e += 1i64
    }
    let rb = (lo >> 63u64) != 0u64
    let rest = (lo << 1u64) != 0u64 || sticky
    if rb && (rest || (hi & 1u64) != 0u64) {
        hi = hi +% 1u64
        if hi == 0u64 {
            hi = 9223372036854775808u64
            e += 1i64
        }
    }
    ret Ld { m: hi, e: e }
}

// the double nearest the long double (ties to even)
fn ld_to_f64(v: Ld) -> f64 {
    if v.m == 0u64 { ret 0.0f64 }
    var top = v.m >> 11u64
    let rb = ((v.m >> 10u64) & 1u64) != 0u64
    let rest = (v.m & 1023u64) != 0u64
    var e = v.e + 11i64
    if rb && (rest || (top & 1u64) != 0u64) {
        top += 1u64
        if top == 9007199254740992u64 {
            top = 4503599627370496u64
            e += 1i64
        }
    }
    ret f64(top) * mem.bitcast[f64](u64(1023i64 + e) << 52u64)
}

// ---- clmm: a cumulative link mixed model with one random intercept per group, P(y <= j | u) = F(theta_j - x beta - u), u ~ N(0, sigma^2); Laplace (agq 1) or adaptive Gauss-Hermite quadrature

type Mm = struct { x: []const f64, cls: []const f64, grp: []const f64, n: usize, p: usize, nk: usize, ng: usize, link: usize, agq: usize, zx: []const f64, zw: []const f64, u: []f64, g1: []f64, g2: []f64, lg: []f64, ek: []f64, st: []f64, ef1: []f64, ef2: []f64, et1: []f64, et2: []f64, pr: []f64, p1: []f64, p2: []f64 }

// Gauss-Hermite nodes and weights for the weight exp(-z^2) (Newton on the Hermite recurrence)
fn gauher(x: []f64, w: []f64, n: usize) {
    let pim = 0.7511255444649425f64
    let m = (n + 1usize) / 2usize
    var z = 0.0f64
    var i = 0usize
    while i < m {
        if i == 0usize {
            z = math.sqrt[f64](f64(2usize * n + 1usize)) - 1.85575f64 * math.pow[f64](f64(2usize * n + 1usize), 0.0f64 - 1.0f64 / 6.0f64)
        } else if i == 1usize {
            z = z - 1.14f64 * math.pow[f64](f64(n), 0.426f64) / z
        } else if i == 2usize {
            z = 1.86f64 * z - 0.86f64 * x[0usize]
        } else if i == 3usize {
            z = 1.91f64 * z - 0.91f64 * x[1usize]
        } else {
            z = 2.0f64 * z - x[i - 2usize]
        }
        var pp = 1.0f64
        var its = 0usize
        var done = false
        while its < 100usize && !done {
            var p1 = pim
            var p2 = 0.0f64
            var j = 0usize
            while j < n {
                let p3 = p2
                p2 = p1
                p1 = z * math.sqrt[f64](2.0f64 / f64(j + 1usize)) * p2 - math.sqrt[f64](f64(j) / f64(j + 1usize)) * p3
                j += 1usize
            }
            pp = math.sqrt[f64](f64(2usize * n)) * p2
            let z1 = z
            z = z1 - p1 / pp
            if math.abs[f64](z - z1) < 1.0e-15f64 { done = true }
            its += 1usize
        }
        x[i] = z
        x[n - 1usize - i] = 0.0f64 - z
        w[i] = 2.0f64 / (pp * pp)
        w[n - 1usize - i] = w[i]
        i += 1usize
    }
}

// ordinal's C pfun2 for the links 0 logit, 1 probit, 2 the port's cloglog (ordinal's "loglog" in clmm), 3 the port's loglog (ordinal's "cloglog" in clmm): the lower tail F(a) and the upper tail, each the way ordinal computes it. e marks an outer threshold at plus (1) or minus (2) infinity
fn mm_flo(link: usize, a: f64, e: usize) -> f64 {
    if e == 1usize { ret 1.0f64 }
    if e == 2usize { ret 0.0f64 }
    if link == 0usize { ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - a)) }
    if link == 1usize { ret dist.pnorm(a, 0.0f64, 1.0f64, true, false) }
    if link == 3usize { ret math.exp[f64](0.0f64 - math.exp[f64](0.0f64 - a)) }
    ret 1.0f64 - math.exp[f64](0.0f64 - math.exp[f64](a))
}

fn mm_fup(link: usize, a: f64, e: usize) -> f64 {
    if e == 1usize { ret 0.0f64 }
    if e == 2usize { ret 1.0f64 }
    if link == 0usize { ret 1.0f64 / (1.0f64 + math.exp[f64](a)) }
    if link == 1usize { ret dist.pnorm(a, 0.0f64, 1.0f64, false, false) }
    if link == 3usize { ret 1.0f64 - math.exp[f64](0.0f64 - math.exp[f64](0.0f64 - a)) }
    ret math.exp[f64](0.0f64 - math.exp[f64](a))
}

// the density and its derivative; zero at an infinite threshold
fn mm_fd(link: usize, a: f64, e: usize) -> (f64, f64) {
    if e != 0usize { ret (0.0f64, 0.0f64) }
    let (f0, d0, s0) = link3(link, a)
    ret (d0, s0)
}

// P(y) between the thresholds e1 > e2, from whichever tail is accurate (ordinal's d_nll)
fn mm_pr(link: usize, e1: f64, e2: f64, k1: usize, k2: usize) -> f64 {
    if e2 <= 0.0f64 { ret mm_flo(link, e1, k1) - mm_flo(link, e2, k2) }
    ret mm_fup(link, e2, k2) - mm_fup(link, e1, k1)
}

fn mm_k1(c: *Mm, t: usize) -> usize {
    if usize(c.cls[t]) == c.nk - 1usize { ret 1usize }
    ret 0usize
}

fn mm_k2(c: *Mm, t: usize) -> usize {
    if usize(c.cls[t]) == 0usize { ret 2usize }
    ret 0usize
}

// the fixed-effect part of both predictors for par = (theta, beta, log tau): theta_y - x beta, with the outer thresholds at 1e5 and -1e5 as ordinal has them
fn mm_prep(c: *Mm, par: []const f64) {
    let nk = c.nk
    var t = 0usize
    while t < c.n {
        let y = usize(c.cls[t])
        var xb = 0.0f64
        var j = 0usize
        while j < c.p {
            xb += c.x[t * c.p + j] * par[nk - 1usize + j]
            j += 1usize
        }
        if y < nk - 1usize { c.ef1[t] = par[y] - xb } else { c.ef1[t] = 100000.0f64 - xb }
        if y > 0usize { c.ef2[t] = par[y - 1usize] - xb } else { c.ef2[t] = 0.0f64 - 100000.0f64 - xb }
        t += 1usize
    }
}

// d_nll: the negative log-likelihood of the observations given the modes c.u plus the standard normal prior; fills et1, et2 and pr; infinite when a probability is not positive
fn mm_nll(c: *Mm, tau: f64) -> f64 {
    var total = 0.0f64
    var t = 0usize
    while t < c.n {
        let o = c.u[usize(c.grp[t])] * tau
        c.et1[t] = c.ef1[t] - o
        c.et2[t] = c.ef2[t] - o
        let pr = mm_pr(c.link, c.et1[t], c.et2[t], mm_k1(c, t), mm_k2(c, t))
        if !(pr < math.inf64()) || pr <= 0.0f64 { ret math.inf64() }
        c.pr[t] = pr
        total -= math.log[f64](pr)
        t += 1usize
    }
    var g = 0usize
    while g < c.ng {
        total -= dist.dnorm(c.u[g], 0.0f64, 1.0f64, true)
        g += 1usize
    }
    ret total
}

// grad_C: the gradient of d_nll in the modes, into c.g1
fn mm_grad_u(c: *Mm, tau: f64) {
    var g = 0usize
    while g < c.ng {
        c.g1[g] = 0.0f64
        g += 1usize
    }
    var t = 0usize
    while t < c.n {
        let (d1, h1) = mm_fd(c.link, c.et1[t], mm_k1(c, t))
        let (d2, h2) = mm_fd(c.link, c.et2[t], mm_k2(c, t))
        c.p1[t] = d1
        c.p2[t] = d2
        let wp = 1.0f64 / c.pr[t] / 1.0f64
        let gi = usize(c.grp[t])
        c.g1[gi] += tau * wp * (d1 - d2)
        t += 1usize
    }
    g = 0usize
    while g < c.ng {
        c.g1[g] += c.u[g]
        g += 1usize
    }
}

// hess: the Hessian of d_nll in the modes (diagonal), into c.g2
fn mm_hess(c: *Mm, tau: f64) {
    var g = 0usize
    while g < c.ng {
        c.g2[g] = 0.0f64
        g += 1usize
    }
    var t = 0usize
    while t < c.n {
        let (d1, h1) = mm_fd(c.link, c.et1[t], mm_k1(c, t))
        let (d2, h2) = mm_fd(c.link, c.et2[t], mm_k2(c, t))
        let wp = 1.0f64 / c.pr[t] / 1.0f64
        let dp = c.p1[t] - c.p2[t]
        let gi = usize(c.grp[t])
        c.g2[gi] += (dp * dp / c.pr[t] - (h1 - h2)) * wp
        t += 1usize
    }
    g = 0usize
    while g < c.ng {
        c.g2[g] = c.g2[g] * tau * tau + 1.0f64
        g += 1usize
    }
}

// ordinal's NRalgv3: Newton for the modes from u = 0 with the step halved while the negative log-likelihood rises; stops at max|gradient| < 1e-4 (clmm.control gradTol), after 50 iterations or after 50 halvings, keeping whatever it reached as ordinal does. The modes are left in c.u and the Hessian of the last hess call (1 when none was made) in c.g2; returns the negative log-likelihood (infinite when it is not finite at the start)
fn mm_inner(c: *Mm, tau: f64) -> f64 {
    let inf = math.inf64()
    var g = 0usize
    while g < c.ng {
        c.u[g] = 0.0f64
        c.g2[g] = 1.0f64
        g += 1usize
    }
    var fv = mm_nll(c, tau)
    if !(fv < inf) { ret inf }
    mm_grad_u(c, tau)
    var maxg = max_abs_v(c.g1, c.ng)
    var sf = 1.0f64
    var i = 0usize
    while i < 50usize {
        if maxg < 1.0e-4f64 { ret fv }
        mm_hess(c, tau)
        g = 0usize
        while g < c.ng {
            c.st[g] = c.g1[g] / c.g2[g]
            c.u[g] -= sf * c.st[g]
            g += 1usize
        }
        var ft = mm_nll(c, tau)
        var li = 0usize
        while ft > fv {
            sf = sf * 0.5f64
            g = 0usize
            while g < c.ng {
                c.u[g] += sf * c.st[g]
                g += 1usize
            }
            ft = mm_nll(c, tau)
            li += 1usize
            if li > 50usize { ret fv }
        }
        fv = ft
        mm_grad_u(c, tau)
        maxg = max_abs_v(c.g1, c.ng)
        sf = math.min[f64](1.0f64, sf * 2.0f64)
        i += 1usize
    }
    ret fv
}

// ordinal's objective for a single random intercept (getNLA.ssr, getNAGQ.ssr): the negative log marginal likelihood at par = (theta, beta, log tau), by the Laplace approximation at the modes from mm_inner (agq <= 1) or adaptive Gauss-Hermite quadrature centred there
fn mm_obj(c: *Mm, par: []const f64) -> f64 {
    let inf = math.inf64()
    let q = c.nk - 1usize + c.p
    let tau = math.exp[f64](par[q])
    mm_prep(c, par)
    let fv = mm_inner(c, tau)
    if !(fv < inf) { ret inf }
    let l2pi = math.log[f64](3.141592653589793f64 * 2.0f64)
    var g = 0usize
    if c.agq <= 1usize {
        var ld = 0.0f64
        while g < c.ng {
            if c.g2[g] <= 0.0f64 { ret inf }
            ld += math.log[f64](c.g2[g])
            g += 1usize
        }
        ret fv - f64(c.ng) * l2pi / 2.0f64 + ld / 2.0f64
    }
    while g < c.ng {
        if c.g2[g] < 0.0f64 { ret inf }
        c.st[g] = math.sqrt[f64](2.0f64 / c.g2[g])
        c.ek[g] = 0.0f64
        g += 1usize
    }
    var k = 0usize
    while k < c.agq {
        g = 0usize
        while g < c.ng {
            c.lg[g] = 0.0f64
            g += 1usize
        }
        var t = 0usize
        while t < c.n {
            let gi = usize(c.grp[t])
            let ran = tau * (c.u[gi] + c.st[gi] * c.zx[k])
            let pr = mm_pr(c.link, c.ef1[t] - ran, c.ef2[t] - ran, mm_k1(c, t), mm_k2(c, t))
            c.lg[gi] += math.log[f64](pr)
            t += 1usize
        }
        let lw = math.log[f64](c.zw[k])
        let nsq = c.zx[k] * c.zx[k]
        g = 0usize
        while g < c.ng {
            let w = c.u[g] + c.st[g] * c.zx[k]
            c.ek[g] += math.exp[f64](c.lg[g] + lw + nsq - 0.5f64 * (w * w))
            g += 1usize
        }
        k += 1usize
    }
    var total = 0.0f64
    g = 0usize
    while g < c.ng {
        total -= math.log[f64](c.ek[g]) + math.log[f64](c.st[g])
        g += 1usize
    }
    ret total + f64(c.ng) * l2pi * 0.5f64
}

fn mm_grad(c: *Mm, par: []const f64, g: []f64) {
}

// fits the model the way ordinal's clmm does (start from clm, log tau = 0, nlminb on the objective without a gradient), or, when fit is false, only evaluates the log marginal likelihood at the given par. grp holds 0-based group numbers (ng groups); par holds theta (K - 1), beta (p) and the random-effect standard deviation tau; returns the log marginal likelihood (NaN when the start fails). When fit is true and ranef and cvar have ng entries they receive ordinal's ranef (modes times tau) and condVar (tau^2 / D)
fn clmm_full(a: *mem.Arena, x: []const f64, cls: []const f64, grp: []const f64, n: usize, p: usize, nk: usize, ng: usize, link: usize, agq: usize, fit: bool, par: []f64, ranef: []f64, cvar: []f64) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let q = nk - 1usize + p
    let (wts, e0) = mem.alloc[f64](a, n)
    let (zx, e1) = mem.alloc[f64](a, agq + 1usize)
    let (zw, e2) = mem.alloc[f64](a, agq + 1usize)
    let (us, e3) = mem.alloc[f64](a, ng)
    let (g1, e4) = mem.alloc[f64](a, ng)
    let (g2, e5) = mem.alloc[f64](a, ng)
    let (lg, e6) = mem.alloc[f64](a, ng)
    let (ek, e7) = mem.alloc[f64](a, ng)
    let (st, e8) = mem.alloc[f64](a, ng)
    let (nv, e9) = mem.alloc[f64](a, 7usize * n)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret nan }
    var i = 0usize
    while i < n {
        wts[i] = 1.0f64
        i += 1usize
    }
    if agq > 1usize { gauher(zx, zw, agq) }
    var c = Mm { x: x, cls: cls, grp: grp, n: n, p: p, nk: nk, ng: ng, link: link, agq: agq, zx: zx, zw: zw, u: us, g1: g1, g2: g2, lg: lg, ek: ek, st: st, ef1: nv[0usize..n], ef2: nv[n..2usize * n], et1: nv[2usize * n..3usize * n], et2: nv[3usize * n..4usize * n], pr: nv[4usize * n..5usize * n], p1: nv[5usize * n..6usize * n], p2: nv[6usize * n..7usize * n] }
    if !fit {
        par[q] = math.log[f64](par[q])
        let v = mm_obj(&c, par)
        par[q] = math.exp[f64](par[q])
        ret 0.0f64 - v
    }
    let l0 = clm_r(a, x, cls, wts, n, p, nk, link, par[0usize..q], 1.0e-6f64, 100usize)
    if !(l0 == l0) { ret nan }
    par[q] = 0.0f64
    var none: [1]f64 = zero
    let r = nl.nlminb[Mm](a, &c, mm_obj, mm_grad, false, par, none[0usize..0usize])
    let tau = math.exp[f64](par[q])
    if ranef.len >= ng && cvar.len >= ng {
        mm_prep(&c, par)
        let _ = mm_inner(&c, tau)
        var g = 0usize
        while g < ng {
            ranef[g] = c.u[g] * tau
            cvar[g] = 1.0f64 / c.g2[g] * (tau * tau)
            g += 1usize
        }
    }
    par[q] = tau
    ret 0.0f64 - r.objective
}

// clmm_full without the random-effect modes
fn clmm(a: *mem.Arena, x: []const f64, cls: []const f64, grp: []const f64, n: usize, p: usize, nk: usize, ng: usize, link: usize, agq: usize, fit: bool, par: []f64) -> f64 {
    var none: [1]f64 = zero
    ret clmm_full(a, x, cls, grp, n, p, nk, ng, link, agq, fit, par, none[0usize..0usize], none[0usize..0usize])
}

// ---- profile likelihood for clm: ordinal's profile.clm (beta) and confint.profile.clm

// sqrt(diag(H^-1)) for the positive definite q x q matrix hn (false when it is not)
fn se_from_h(a: *mem.Arena, hn: []const f64, q: usize, se: []f64) -> bool {
    let (l, e1) = mem.alloc[f64](a, q * q)
    let (z, e2) = mem.alloc[f64](a, q)
    let (s, e3) = mem.alloc[f64](a, q)
    if e1 != ok || e2 != ok || e3 != ok { ret false }
    if !chol_lower(hn, l, q) { ret false }
    var c = 0usize
    while c < q {
        var r = 0usize
        while r < q {
            var v = 0.0f64
            if r == c { v = 1.0f64 }
            var k = 0usize
            while k < r {
                v -= l[r * q + k] * z[k]
                k += 1usize
            }
            z[r] = v / l[r * q + r]
            r += 1usize
        }
        r = q
        while r > 0usize {
            r -= 1usize
            var v = z[r]
            var k = r + 1usize
            while k < q {
                v -= l[k * q + r] * s[k]
                k += 1usize
            }
            s[r] = v / l[r * q + r]
        }
        se[c] = math.sqrt[f64](s[c])
        c += 1usize
    }
    ret true
}

// profile.clm for coefficient which (0-based) at alpha: lroot = -direction * sqrt(2 (logLik - profile logLik)) at beta = beta_hat + direction * step * delta * se, each fitted by R's Newton with the coefficient held fixed. lr and bv (capacity 101) receive the points by ascending beta, the maximum included; returns their number (0 when a fit fails)
fn clm_profile(a: *mem.Arena, x: []const f64, cls: []const f64, wts: []const f64, n: usize, p: usize, nk: usize, link: usize, which: usize, alpha: f64, lr: []f64, bv: []f64) -> usize {
    let q = nk - 1usize + p
    let ix = nk - 1usize + which
    let (ph, e1) = mem.alloc[f64](a, q)
    let (pw, e2) = mem.alloc[f64](a, q)
    let (gr, e3) = mem.alloc[f64](a, q)
    let (h, e4) = mem.alloc[f64](a, q * q)
    let (se, e5) = mem.alloc[f64](a, q)
    let (tl, e6) = mem.alloc[f64](a, 100usize)
    let (tb, e7) = mem.alloc[f64](a, 100usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret 0usize }
    let llh = clm_r(a, x, cls, wts, n, p, nk, link, ph, 1.0e-6f64, 100usize)
    if !(llh == llh) { ret 0usize }
    let _ = loglik(x, cls, wts, n, p, nk, link, ph, gr, h, true)
    var r = 0usize
    while r < q * q {
        h[r] = 0.0f64 - h[r]
        r += 1usize
    }
    if !se_from_h(a, h, q, se) { ret 0usize }
    let lmax = dist.qnorm(1.0f64 - alpha / 2.0f64, 0.0f64, 1.0f64, true, false)
    let delta = lmax / 8.0f64
    var cnt0 = 0usize
    var cnt1 = 0usize
    var dir = 0usize
    while dir < 2usize {
        var sgn = 1.0f64
        if dir == 0usize { sgn = 0.0f64 - 1.0f64 }
        r = 0usize
        while r < q {
            pw[r] = ph[r]
            r += 1usize
        }
        var step = 1usize
        while step <= 50usize {
            let bi = ph[ix] + sgn * f64(step) * delta * se[ix]
            pw[ix] = bi
            let ll = clm_nrf(a, x, cls, wts, n, p, nk, link, pw, 1.0e-6f64, 1.0e-6f64, 100usize, ix)
            if !(ll == ll) { ret 0usize }
            let lroot = 0.0f64 - sgn * math.sqrt[f64](2.0f64 * (llh - ll))
            tl[dir * 50usize + step - 1usize] = lroot
            tb[dir * 50usize + step - 1usize] = bi
            if dir == 0usize { cnt0 = step } else { cnt1 = step }
            if math.abs[f64](lroot) > lmax { break }
            step += 1usize
        }
        dir += 1usize
    }
    var m = 0usize
    var k = 0usize
    while k < cnt0 {
        lr[m] = tl[cnt0 - 1usize - k]
        bv[m] = tb[cnt0 - 1usize - k]
        m += 1usize
        k += 1usize
    }
    lr[m] = 0.0f64
    bv[m] = ph[ix]
    m += 1usize
    k = 0usize
    while k < cnt1 {
        lr[m] = tl[50usize + k]
        bv[m] = tb[50usize + k]
        m += 1usize
        k += 1usize
    }
    ret m
}

// R's approx (linear, rule 1) at v on ascending xs
fn approx_lin(xs: []const f64, ys: []const f64, m: usize, v: f64) -> f64 {
    if m == 0usize || v < xs[0usize] || v > xs[m - 1usize] { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    var j = m - 1usize
    while i + 1usize < j {
        let ij = (i + j) / 2usize
        if v < xs[ij] { j = ij } else { i = ij }
    }
    if v == xs[j] { ret ys[j] }
    if v == xs[i] { ret ys[i] }
    ret ys[i] + (ys[j] - ys[i]) * ((v - xs[i]) / (xs[j] - xs[i]))
}

// confint.profile.clm for the profile (lr, bv) of m points: spline(bv, lr) at 3 m points, then the beta where lroot crosses +-qnorm(1 - (1 - level) / 2); out = (lower, upper)
fn clm_confint(a: *mem.Arena, lr: []const f64, bv: []const f64, m: usize, level: f64, out: []f64) {
    let nan = 0.0f64 / 0.0f64
    out[0usize] = nan
    out[1usize] = nan
    let nn = 3usize * m
    let (b, e1) = mem.alloc[f64](a, m)
    let (c, e2) = mem.alloc[f64](a, m)
    let (d, e3) = mem.alloc[f64](a, m)
    let (sx, e4) = mem.alloc[f64](a, nn)
    let (sy, e5) = mem.alloc[f64](a, nn)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret }
    spl.fmm_spline(m, bv, lr, b, c, d)
    let from = bv[0usize]
    let by = (bv[m - 1usize] - from) / f64(nn - 1usize)
    var i = 0usize
    while i < nn {
        // approx wants its x ascending: the spline's lroot falls with beta, so fill from the end
        var u = from + f64(i) * by
        if i == nn - 1usize { u = bv[m - 1usize] }
        sy[nn - 1usize - i] = u
        sx[nn - 1usize - i] = spl.spline_eval(m, bv, lr, b, c, d, u)
        i += 1usize
    }
    let z = dist.qnorm(1.0f64 - (1.0f64 - level) / 2.0f64, 0.0f64, 1.0f64, true, false)
    out[0usize] = approx_lin(sx, sy, nn, z)
    out[1usize] = approx_lin(sx, sy, nn, 0.0f64 - z)
}
