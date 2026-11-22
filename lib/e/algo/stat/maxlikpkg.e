// R maxLik: maxLik(method = "NR" | "BHHH" | "BFGS" | "NM") on five fixed log-likelihoods with analytic per-observation gradients and Hessians, and the standard errors stdEr() gives (the square roots of the diagonal of solve(-hessian)).
//
// maxNR is a port of maxNRCompute.R with the default control (tol 1e-8, reltol 1e-8, gradtol 1e-6, steptol 1e-10, lambdatol 1e-6, iterlim 150, qac "stephalving"): a Hessian that is not negative definite
// is shifted by (|largest eigenvalue| + lambdatol + min |diag| / 1e7) I, the step is halved while the value falls or is NA, and the five stop codes come out in R's order. BHHH is the same loop with H = -G'G.
// BFGS is optim's vmmin on -loglik (reltol 1e-8, maxit 200) and NM optim's nmmin (reltol 1e-8, maxit 500), both from rbfgs.e and rnm.e, with the analytic Hessian at the end.
//
// ponytail: the qr rank test of the step system is not made (every Hessian here is solved by Gaussian elimination with partial pivoting); a rank-deficient case would differ.
// Not here: constraints, fixed parameters, the Marquardt correction, numeric derivatives, BFGSR, CG and SANN.

use e.algo.stat.rbfgs as bf
use e.algo.stat.rnm as nm
use e.math
use e.mem

type MCtx = struct { model: usize, n: usize, p: usize, x: []const f64, y: []const f64, gm: []f64, fcnt: usize, gcnt: usize }

// number of parameters: 0 normal (mu, s), 1 poisson regression (b0, b1), 2 logistic regression (b0, b1), 3 Weibull (shape, scale), 4 linear regression with normal errors (b0, b1, s)
fn npar(model: usize) -> usize {
    if model == 4usize { ret 3usize }
    ret 2usize
}

fn nanv() -> f64 { ret 0.0f64 / 0.0f64 }

// R sums in long double; a double-double accumulator rounded once at the end reproduces its result to the last bit in all but rare cases
type Acc = struct { hi: f64, lo: f64 }

fn acc_add(a: *Acc, v: f64) {
    let s = a.hi + v
    let bb = s - a.hi
    a.lo = a.lo + ((a.hi - (s - bb)) + (v - bb))
    a.hi = s
}

fn acc_val(a: *Acc) -> f64 {
    if a.hi != a.hi || a.hi - a.hi != 0.0f64 { ret a.hi }
    ret a.hi + a.lo
}

fn addk(hi: []f64, lo: []f64, k: usize, v: f64) {
    let s = hi[k] + v
    let bb = s - hi[k]
    lo[k] = lo[k] + ((hi[k] - (s - bb)) + (v - bb))
    hi[k] = s
}

// the log-likelihood summed over the observations; NaN when a parameter is out of its support
fn ll(c: *MCtx, th: []const f64) -> f64 {
    var acc = Acc{ hi: 0.0f64, lo: 0.0f64 }
    var i = 0usize
    c.fcnt += 1usize
    while i < c.n {
        let x = c.x[i]
        let y = c.y[i]
        if c.model == 0usize {
            acc_add(&acc, -0.5f64 * math.log[f64](2.0f64 * 3.141592653589793f64) - math.log[f64](th[1usize]) - (x - th[0usize]) * (x - th[0usize]) / (2.0f64 * th[1usize] * th[1usize]))
        } else if c.model == 1usize {
            let eta = th[0usize] + th[1usize] * x
            acc_add(&acc, y * eta - math.exp[f64](eta))
        } else if c.model == 2usize {
            let eta = th[0usize] + th[1usize] * x
            acc_add(&acc, y * eta - math.log[f64](1.0f64 + math.exp[f64](eta)))
        } else if c.model == 3usize {
            acc_add(&acc, math.log[f64](th[0usize]) - th[0usize] * math.log[f64](th[1usize]) + (th[0usize] - 1.0f64) * math.log[f64](x) - math.pow[f64](x / th[1usize], th[0usize]))
        } else {
            let r = y - th[0usize] - th[1usize] * x
            acc_add(&acc, -0.5f64 * math.log[f64](2.0f64 * 3.141592653589793f64) - math.log[f64](th[2usize]) - r * r / (2.0f64 * th[2usize] * th[2usize]))
        }
        i += 1usize
    }
    ret acc_val(&acc)
}

// the n by p matrix of per-observation gradients into c.gm
fn gobs(c: *MCtx, th: []const f64) {
    let p = c.p
    var i = 0usize
    while i < c.n {
        let x = c.x[i]
        let y = c.y[i]
        if c.model == 0usize {
            c.gm[i * p] = (x - th[0usize]) / (th[1usize] * th[1usize])
            c.gm[i * p + 1usize] = -1.0f64 / th[1usize] + (x - th[0usize]) * (x - th[0usize]) / (th[1usize] * th[1usize] * th[1usize])
        } else if c.model == 1usize {
            let mu = math.exp[f64](th[0usize] + th[1usize] * x)
            c.gm[i * p] = y - mu
            c.gm[i * p + 1usize] = (y - mu) * x
        } else if c.model == 2usize {
            let pr = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - (th[0usize] + th[1usize] * x)))
            c.gm[i * p] = y - pr
            c.gm[i * p + 1usize] = (y - pr) * x
        } else if c.model == 3usize {
            let z = x / th[1usize]
            let u = math.pow[f64](z, th[0usize])
            c.gm[i * p] = 1.0f64 / th[0usize] + math.log[f64](x) - math.log[f64](th[1usize]) - u * math.log[f64](z)
            c.gm[i * p + 1usize] = th[0usize] / th[1usize] * (u - 1.0f64)
        } else {
            let r = y - th[0usize] - th[1usize] * x
            let s2 = th[2usize] * th[2usize]
            c.gm[i * p] = r / s2
            c.gm[i * p + 1usize] = r * x / s2
            c.gm[i * p + 2usize] = -1.0f64 / th[2usize] + r * r / (s2 * th[2usize])
        }
        i += 1usize
    }
}

fn gsum(c: *MCtx, th: []const f64, g: []f64) {
    c.gcnt += 1usize
    gobs(c, th)
    var j = 0usize
    while j < c.p {
        var acc = Acc{ hi: 0.0f64, lo: 0.0f64 }
        var i = 0usize
        while i < c.n {
            acc_add(&acc, c.gm[i * c.p + j])
            i += 1usize
        }
        g[j] = acc_val(&acc)
        j += 1usize
    }
}

// the analytic Hessian of the summed log-likelihood, row-major p by p
fn hess(c: *MCtx, th: []const f64, h: []f64) {
    let p = c.p
    var k = 0usize
    var hi: [9]f64 = zero
    var lo: [9]f64 = zero
    var i = 0usize
    while i < c.n {
        let x = c.x[i]
        let y = c.y[i]
        if c.model == 0usize {
            let s = th[1usize]
            let d = x - th[0usize]
            addk(hi[0usize..9usize], lo[0usize..9usize], 0usize, -1.0f64 / (s * s))
            addk(hi[0usize..9usize], lo[0usize..9usize], 1usize, -2.0f64 * d / (s * s * s))
            addk(hi[0usize..9usize], lo[0usize..9usize], 3usize, 1.0f64 / (s * s) - 3.0f64 * d * d / (s * s * s * s))
        } else if c.model == 1usize {
            let mu = math.exp[f64](th[0usize] + th[1usize] * x)
            addk(hi[0usize..9usize], lo[0usize..9usize], 0usize, -mu)
            addk(hi[0usize..9usize], lo[0usize..9usize], 1usize, -mu * x)
            addk(hi[0usize..9usize], lo[0usize..9usize], 3usize, -mu * x * x)
        } else if c.model == 2usize {
            let pr = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - (th[0usize] + th[1usize] * x)))
            let w = pr * (1.0f64 - pr)
            addk(hi[0usize..9usize], lo[0usize..9usize], 0usize, -w)
            addk(hi[0usize..9usize], lo[0usize..9usize], 1usize, -w * x)
            addk(hi[0usize..9usize], lo[0usize..9usize], 3usize, -w * x * x)
        } else if c.model == 3usize {
            let kk = th[0usize]
            let lam = th[1usize]
            let z = x / lam
            let u = math.pow[f64](z, kk)
            let lz = math.log[f64](z)
            addk(hi[0usize..9usize], lo[0usize..9usize], 0usize, -1.0f64 / (kk * kk) - u * lz * lz)
            addk(hi[0usize..9usize], lo[0usize..9usize], 1usize, (u - 1.0f64 + kk * u * lz) / lam)
            addk(hi[0usize..9usize], lo[0usize..9usize], 3usize, kk / (lam * lam) * (1.0f64 - u - kk * u))
        } else {
            let s = th[2usize]
            let r = y - th[0usize] - th[1usize] * x
            addk(hi[0usize..9usize], lo[0usize..9usize], 0usize, -1.0f64 / (s * s))
            addk(hi[0usize..9usize], lo[0usize..9usize], 1usize, -x / (s * s))
            addk(hi[0usize..9usize], lo[0usize..9usize], 2usize, -2.0f64 * r / (s * s * s))
            addk(hi[0usize..9usize], lo[0usize..9usize], 4usize, -x * x / (s * s))
            addk(hi[0usize..9usize], lo[0usize..9usize], 5usize, -2.0f64 * r * x / (s * s * s))
            addk(hi[0usize..9usize], lo[0usize..9usize], 8usize, 1.0f64 / (s * s) - 3.0f64 * r * r / (s * s * s * s))
        }
        i += 1usize
    }
    k = 0usize
    while k < p * p {
        h[k] = hi[k] + lo[k]
        k += 1usize
    }
    if c.model == 0usize || c.model == 1usize || c.model == 2usize || c.model == 3usize {
        h[2usize] = h[1usize]
    } else {
        h[3usize] = h[1usize]
        h[6usize] = h[2usize]
        h[7usize] = h[5usize]
    }
}

// -G'G, the BHHH Hessian, from the per-observation gradients at th
fn hess_bhhh(c: *MCtx, th: []const f64, h: []f64) {
    let p = c.p
    gobs(c, th)
    var a = 0usize
    while a < p {
        var b = 0usize
        while b < p {
            var s = 0.0f64
            var i = 0usize
            while i < c.n {
                s += c.gm[i * p + a] * c.gm[i * p + b]
                i += 1usize
            }
            h[a * p + b] = 0.0f64 - s
            b += 1usize
        }
        a += 1usize
    }
}

// the largest eigenvalue of the symmetric p by p matrix m (cyclic Jacobi on a copy in w)
fn max_eigen(m: []const f64, p: usize, w: []f64) -> f64 {
    var i = 0usize
    while i < p * p {
        w[i] = m[i]
        i += 1usize
    }
    var sweep = 0usize
    while sweep < 100usize {
        var off = 0.0f64
        var r = 0usize
        while r < p {
            var q = r + 1usize
            while q < p {
                off += w[r * p + q] * w[r * p + q]
                q += 1usize
            }
            r += 1usize
        }
        if off < 1.0e-300f64 { break }
        r = 0usize
        while r < p {
            var q = r + 1usize
            while q < p {
                let apq = w[r * p + q]
                if apq != 0.0f64 {
                    let theta = (w[q * p + q] - w[r * p + r]) / (2.0f64 * apq)
                    var t = 1.0f64 / (math.abs[f64](theta) + math.sqrt[f64](theta * theta + 1.0f64))
                    if theta < 0.0f64 { t = 0.0f64 - t }
                    let cs = 1.0f64 / math.sqrt[f64](t * t + 1.0f64)
                    let sn = t * cs
                    var k = 0usize
                    while k < p {
                        let akp = w[k * p + r]
                        let akq = w[k * p + q]
                        w[k * p + r] = cs * akp - sn * akq
                        w[k * p + q] = sn * akp + cs * akq
                        k += 1usize
                    }
                    k = 0usize
                    while k < p {
                        let apk = w[r * p + k]
                        let aqk = w[q * p + k]
                        w[r * p + k] = cs * apk - sn * aqk
                        w[q * p + k] = sn * apk + cs * aqk
                        k += 1usize
                    }
                }
                q += 1usize
            }
            r += 1usize
        }
        sweep += 1usize
    }
    var best = w[0usize]
    i = 1usize
    while i < p {
        if w[i * p + i] > best { best = w[i * p + i] }
        i += 1usize
    }
    ret best
}

// solves m x = b by Gaussian elimination with partial pivoting; m is destroyed, b receives x; false on a zero pivot
fn solve(m: []f64, p: usize, b: []f64) -> bool {
    var k = 0usize
    while k < p {
        var l = k
        var best = math.abs[f64](m[k * p + k])
        var i = k + 1usize
        while i < p {
            if math.abs[f64](m[i * p + k]) > best {
                best = math.abs[f64](m[i * p + k])
                l = i
            }
            i += 1usize
        }
        if best == 0.0f64 { ret false }
        if l != k {
            var j = 0usize
            while j < p {
                let t = m[k * p + j]
                m[k * p + j] = m[l * p + j]
                m[l * p + j] = t
                j += 1usize
            }
            let tb = b[k]
            b[k] = b[l]
            b[l] = tb
        }
        i = k + 1usize
        while i < p {
            let f = m[i * p + k] / m[k * p + k]
            var j = k
            while j < p {
                m[i * p + j] = m[i * p + j] - f * m[k * p + j]
                j += 1usize
            }
            b[i] = b[i] - f * b[k]
            i += 1usize
        }
        k += 1usize
    }
    var kb = 0usize
    while kb < p {
        let kk = p - 1usize - kb
        var s = b[kk]
        var j = kk + 1usize
        while j < p {
            s = s - m[kk * p + j] * b[j]
            j += 1usize
        }
        b[kk] = s / m[kk * p + kk]
        kb += 1usize
    }
    ret true
}

// stdEr(): the square roots of the diagonal of solve(-hessian) into se; false when the Hessian cannot be inverted
fn std_err(a: *mem.Arena, h: []const f64, p: usize, se: []f64) -> bool {
    let (m, e1) = mem.alloc[f64](a, p * p)
    let (col, e2) = mem.alloc[f64](a, p)
    let (inv, e3) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok { ret false }
    var j = 0usize
    while j < p {
        var i = 0usize
        while i < p {
            m[i * p + i] = 0.0f64 - h[i * p + i]
            var q = 0usize
            while q < p {
                m[i * p + q] = 0.0f64 - h[i * p + q]
                q += 1usize
            }
            col[i] = 0.0f64
            i += 1usize
        }
        col[j] = 1.0f64
        if !solve(m, p, col) { ret false }
        i = 0usize
        while i < p {
            inv[i * p + j] = col[i]
            i += 1usize
        }
        j += 1usize
    }
    var i = 0usize
    while i < p {
        se[i] = math.sqrt[f64](inv[i * p + i])
        i += 1usize
    }
    ret true
}

// maxNR (bhhh false) and maxBHHH (bhhh true) from `th`, which receives the estimate; hout the final Hessian, gout the final gradient. Returns (maximum, code, iterations)
fn max_nr(a: *mem.Arena, c: *MCtx, th: []f64, bhhh: bool, gout: []f64, hout: []f64) -> (f64, usize, usize) {
    let p = c.p
    let (g0, e1) = mem.alloc[f64](a, p)
    let (g1, e2) = mem.alloc[f64](a, p)
    let (h0, e3) = mem.alloc[f64](a, p * p)
    let (h1, e4) = mem.alloc[f64](a, p * p)
    let (hh, e5) = mem.alloc[f64](a, p * p)
    let (wk, e6) = mem.alloc[f64](a, p * p)
    let (amount, e7) = mem.alloc[f64](a, p)
    let (s0, e8) = mem.alloc[f64](a, p)
    let (s1, e9) = mem.alloc[f64](a, p)
    let (sol, e10) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret (nanv(), 9usize, 0usize) }
    let lambdatol = 1.0e-6f64
    let steptol = 1.0e-10f64
    let gradtol = 1.0e-6f64
    let tol = 1.0e-8f64
    let reltol = 1.0e-8f64
    var i = 0usize
    while i < p {
        s1[i] = th[i]
        i += 1usize
    }
    var f1 = ll(c, s1)
    gsum(c, s1, g1)
    if bhhh { hess_bhhh(c, s1, h1) } else { hess(c, s1, h1) }
    var iter = 0usize
    var code = 4usize
    var step = 1.0f64
    var go = true
    while go {
        if iter >= 150usize {
            code = 4usize
            go = false
        } else {
            iter += 1usize
            i = 0usize
            while i < p {
                s0[i] = s1[i]
                g0[i] = g1[i]
                i += 1usize
            }
            i = 0usize
            while i < p * p {
                h0[i] = h1[i]
                hh[i] = h1[i]
                i += 1usize
            }
            let f0 = f1
            step = 1.0f64
            var count = 0usize
            var me = max_eigen(hh, p, wk)
            while me >= 0.0f64 - lambdatol && count <= 100usize {
                var md = math.abs[f64](hh[0usize])
                i = 1usize
                while i < p {
                    if math.abs[f64](hh[i * p + i]) < md { md = math.abs[f64](hh[i * p + i]) }
                    i += 1usize
                }
                let lambda1 = math.abs[f64](me) + lambdatol + md / 1.0e7f64
                i = 0usize
                while i < p {
                    hh[i * p + i] = hh[i * p + i] - lambda1
                    i += 1usize
                }
                count += 1usize
                me = max_eigen(hh, p, wk)
            }
            i = 0usize
            while i < p * p {
                sol[i] = hh[i]
                i += 1usize
            }
            i = 0usize
            while i < p {
                amount[i] = g0[i]
                i += 1usize
            }
            if !solve(sol, p, amount) {
                code = 3usize
                go = false
            } else {
                i = 0usize
                while i < p {
                    s1[i] = s0[i] - step * amount[i]
                    i += 1usize
                }
                f1 = ll(c, s1)
                var ok_step = step >= steptol
                while f1 != f1 || (f1 < f0 && ok_step) {
                    step = step / 2.0f64
                    i = 0usize
                    while i < p {
                        s1[i] = s0[i] - step * amount[i]
                        i += 1usize
                    }
                    f1 = ll(c, s1)
                }
                ok_step = step >= steptol
                if !ok_step {
                    i = 0usize
                    while i < p {
                        s1[i] = s0[i]
                        i += 1usize
                    }
                    f1 = f0
                }
                gsum(c, s1, g1)
                if bhhh { hess_bhhh(c, s1, h1) } else { hess(c, s1, h1) }
                if step < steptol {
                    code = 3usize
                    go = false
                } else {
                    var gn = 0.0f64
                    i = 0usize
                    while i < p {
                        gn += g1[i] * g1[i]
                        i += 1usize
                    }
                    if math.sqrt[f64](gn) < gradtol {
                        code = 1usize
                        go = false
                    } else if f1 - f0 < tol {
                        code = 2usize
                        go = false
                    } else if f1 - f0 < reltol * math.abs[f64](f1 + reltol) {
                        code = 8usize
                        go = false
                    }
                }
            }
        }
    }
    i = 0usize
    while i < p {
        th[i] = s1[i]
        i += 1usize
    }
    gsum(c, th, gout)
    if bhhh { hess_bhhh(c, th, hout) } else { hess(c, th, hout) }
    ret (f1, code, iter)
}

fn nll(c: *MCtx, th: []const f64) -> f64 { ret 0.0f64 - ll(c, th) }

fn ngr(c: *MCtx, th: []const f64, g: []f64) {
    gsum(c, th, g)
    var j = 0usize
    while j < c.p {
        g[j] = 0.0f64 - g[j]
        j += 1usize
    }
}

// maxBFGS (method 2) and maxNM (method 3) from `th`, which receives the estimate. Returns (maximum, code, function count)
fn max_optim(a: *mem.Arena, c: *MCtx, th: []f64, method: usize, gout: []f64, hout: []f64) -> (f64, usize, usize) {
    var fv = 0.0f64
    var code = 0usize
    var cnt2 = 0usize
    c.fcnt = 0usize
    if method == 2usize {
        fv = bf.vmmin[MCtx](a, c, nll, ngr, th, 1.0e-8f64, 200usize)
        cnt2 = c.fcnt
    } else {
        let (st, e1) = mem.alloc[f64](a, c.p)
        if e1 != ok { ret (nanv(), 9usize, 0usize) }
        var i = 0usize
        while i < c.p {
            st[i] = th[i]
            i += 1usize
        }
        let (v, cnt, fail) = nm.nmmin[MCtx](a, c, nll, st, 0.0f64 - 1.0e308f64, 1.0e-8f64, 1.0f64, 0.5f64, 2.0f64, 500usize, 1.0f64, th)
        fv = v
        code = fail
        cnt2 = cnt
    }
    gsum(c, th, gout)
    hess(c, th, hout)
    ret (0.0f64 - fv, code, cnt2)
}
