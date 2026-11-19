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
fn loglik(x: []const f64, cls: []const f64, wts: []const f64, n: usize, p: usize, nk: usize, link: usize, par: []const f64, gr: []f64, h: []f64, want: bool) -> f64 {
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
                if y == nk - 1usize { va = 0.0f64 }
                if y == 0usize { vb = 0.0f64 }
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
                    if y == nk - 1usize { wa = 0.0f64 }
                    if y == 0usize { wb = 0.0f64 }
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
fn clm(a: *mem.Arena, x: []const f64, cls: []const f64, wts: []const f64, n: usize, p: usize, nk: usize, link: usize, par: []f64) -> f64 {
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
            if ll2 == ll2 && ll2 >= ll - 1.0e-14f64 {
                i = 0usize
                while i < q {
                    par[i] = trial[i]
                    i += 1usize
                }
                let step = math.abs[f64](ll2 - ll)
                ll = loglik(x, cls, wts, n, p, nk, link, par, gr, h, true)
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
            if ll2 == ll2 && ll2 >= ll - 1.0e-14f64 {
                i = 0usize
                while i < qr {
                    red[i] = trial[i]
                    i += 1usize
                }
                moved = true
                if math.abs[f64](ll2 - ll) < 1.0e-13f64 {
                    ll = ll2
                    it = 1000usize
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
            if ll2 == ll2 && ll2 >= ll - 1.0e-14f64 {
                i = 0usize
                while i < qr {
                    red[i] = trial[i]
                    i += 1usize
                }
                moved = true
                if math.abs[f64](ll2 - ll) < 1.0e-13f64 {
                    ll = ll2
                    it = 1000usize
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
