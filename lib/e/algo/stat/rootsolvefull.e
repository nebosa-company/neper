// rootSolve::steady (method stode) and jacobian.full on five fixed ODE systems, a port of src/steady.f: the Newton iteration of dSteady with the internally perturbed full
// Jacobian (xFullJacob), the error weights rtol * |y| + atol, the LINPACK dgefa / dgesl solve, the positivity clamp, and the two convergence tests (the weighted residual and the largest change).
// Not here: user Jacobians (jactype fullusr), banded Jacobians (bandint, steady.1D), runsteady and stodes.

use e.algo.stat.nleqslvpkg as nl
use e.mem

// the ODE right-hand side dy = f(y) of system `sid` with parameters p: 0 logistic predator-prey (r, K, a, b, m), 1 Brusselator (a, b), 2 three-species chain (i, k1, k2, k3),
// 3 Lorenz (s, r, b), 4 four-species Michaelis-Menten pathway (v, k, d); 5 to 9 are the five systems of nleqslvpkg as multiroot(f, start) sees them (multiroot is steady on dy = f(x))
fn rhs(sid: usize, p: []const f64, y: []const f64, dy: []f64) {
    if sid >= 5usize {
        nl.system(sid - 5usize, y, dy)
    } else if sid == 0usize {
        dy[0usize] = p[0usize] * y[0usize] * (1.0f64 - y[0usize] / p[1usize]) - p[2usize] * y[0usize] * y[1usize]
        dy[1usize] = p[3usize] * p[2usize] * y[0usize] * y[1usize] - p[4usize] * y[1usize]
    } else if sid == 1usize {
        dy[0usize] = p[0usize] - (p[1usize] + 1.0f64) * y[0usize] + y[0usize] * y[0usize] * y[1usize]
        dy[1usize] = p[1usize] * y[0usize] - y[0usize] * y[0usize] * y[1usize]
    } else if sid == 2usize {
        dy[0usize] = p[0usize] - p[1usize] * y[0usize]
        dy[1usize] = p[1usize] * y[0usize] - p[2usize] * y[1usize] * y[1usize]
        dy[2usize] = p[2usize] * y[1usize] * y[1usize] - p[3usize] * y[2usize]
    } else if sid == 3usize {
        dy[0usize] = p[0usize] * (y[1usize] - y[0usize])
        dy[1usize] = p[1usize] * y[0usize] - y[1usize] - y[0usize] * y[2usize]
        dy[2usize] = y[0usize] * y[1usize] - p[2usize] * y[2usize]
    } else {
        dy[0usize] = p[0usize] - p[2usize] * y[0usize]
        dy[1usize] = p[2usize] * y[0usize] - p[0usize] * y[1usize] / (p[1usize] + y[1usize])
        dy[2usize] = p[0usize] * y[1usize] / (p[1usize] + y[1usize]) - p[2usize] * y[2usize] - y[2usize] * y[3usize]
        dy[3usize] = y[2usize] * y[3usize] - p[2usize] * y[3usize] + 0.05f64
    }
}

fn dim_of(sid: usize) -> usize {
    if sid >= 5usize { ret nl.dim_of(sid - 5usize) }
    if sid == 0usize || sid == 1usize { ret 2usize }
    if sid == 4usize { ret 4usize }
    ret 3usize
}

// rootSolve's perturb: |v| * pert, at least pert
fn perturb(v: f64, pert: f64) -> f64 {
    var d = v * pert
    if v < 0.0f64 { d = (0.0f64 - v) * pert }
    if d < pert { d = pert }
    ret d
}

// LINPACK dgefa on a column-major n by n matrix (a[col * n + row]); the pivots go to ipvt, the answer is info (0 when no zero pivot)
fn dgefa(a: []f64, n: usize, ipvt: []usize) -> usize {
    var info = 0usize
    var k = 0usize
    while k + 1usize < n {
        var l = k
        var best = a[k * n + k]
        if best < 0.0f64 { best = 0.0f64 - best }
        var i = k + 1usize
        while i < n {
            var v = a[k * n + i]
            if v < 0.0f64 { v = 0.0f64 - v }
            if v > best {
                best = v
                l = i
            }
            i += 1usize
        }
        ipvt[k] = l
        if a[k * n + l] == 0.0f64 {
            info = k + 1usize
        } else {
            if l != k {
                let t = a[k * n + l]
                a[k * n + l] = a[k * n + k]
                a[k * n + k] = t
            }
            let m = -1.0f64 / a[k * n + k]
            i = k + 1usize
            while i < n {
                a[k * n + i] = a[k * n + i] * m
                i += 1usize
            }
            var j = k + 1usize
            while j < n {
                let t = a[j * n + l]
                if l != k {
                    a[j * n + l] = a[j * n + k]
                    a[j * n + k] = t
                }
                i = k + 1usize
                while i < n {
                    a[j * n + i] = a[j * n + i] + t * a[k * n + i]
                    i += 1usize
                }
                j += 1usize
            }
        }
        k += 1usize
    }
    ipvt[n - 1usize] = n - 1usize
    if a[(n - 1usize) * n + (n - 1usize)] == 0.0f64 { info = n }
    ret info
}

// LINPACK dgesl (job 0): b receives the solution of the factored system
fn dgesl(a: []const f64, n: usize, ipvt: []const usize, b: []f64) {
    var k = 0usize
    while k + 1usize < n {
        let l = ipvt[k]
        let t = b[l]
        if l != k {
            b[l] = b[k]
            b[k] = t
        }
        var i = k + 1usize
        while i < n {
            b[i] = b[i] + t * a[k * n + i]
            i += 1usize
        }
        k += 1usize
    }
    var kb = 0usize
    while kb < n {
        let kk = n - 1usize - kb
        b[kk] = b[kk] / a[kk * n + kk]
        let t = 0.0f64 - b[kk]
        var i = 0usize
        while i < kk {
            b[i] = b[i] + t * a[kk * n + i]
            i += 1usize
        }
        kb += 1usize
    }
}

// steady(y, func, parms, method = "stode"): y is the start and the answer; the result is (iterations, steady reached 1 or 0, the last mean residual precis)
fn stode(a: *mem.Arena, sid: usize, parms: []const f64, y: []f64, rtol: f64, atol: f64, ctol: f64, maxiter: usize, positive: bool) -> (usize, usize, f64) {
    let n = dim_of(sid)
    let (beta, e1) = mem.alloc[f64](a, n)
    let (ds, e2) = mem.alloc[f64](a, n)
    let (cv, e3) = mem.alloc[f64](a, n)
    let (ewt, e4) = mem.alloc[f64](a, n)
    let (alpha, e5) = mem.alloc[f64](a, n * n)
    let (piv, e6) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (0usize, 0usize, 0.0f64) }
    var iter = 0usize
    var steady = 0usize
    var precis = 0.0f64
    var k = 1usize
    var go = true
    while go && k <= maxiter {
        iter = k
        var i = 0usize
        while i < n {
            var ay = y[i]
            if ay < 0.0f64 { ay = 0.0f64 - ay }
            ewt[i] = rtol * ay + atol
            i += 1usize
        }
        i = 0usize
        while i < n {
            ds[i] = 0.0f64
            i += 1usize
        }
        rhs(sid, parms, y, ds)
        i = 0usize
        while i < n {
            beta[i] = 0.0f64 - ds[i]
            cv[i] = y[i]
            i += 1usize
        }
        var c = 0usize
        while c < n {
            let dd = perturb(cv[c], 1.0e-8f64)
            cv[c] = cv[c] + dd
            i = 0usize
            while i < n {
                ds[i] = 0.0f64
                i += 1usize
            }
            rhs(sid, parms, cv, ds)
            i = 0usize
            while i < n {
                alpha[c * n + i] = (ds[i] + beta[i]) / dd
                i += 1usize
            }
            cv[c] = y[c]
            c += 1usize
        }
        precis = 0.0f64
        var maxewt = 0.0f64
        i = 0usize
        while i < n {
            var ab = beta[i]
            if ab < 0.0f64 { ab = 0.0f64 - ab }
            precis = precis + ab
            var q = ab / ewt[i]
            if q < 0.0f64 { q = 0.0f64 - q }
            if q > maxewt { maxewt = q }
            i += 1usize
        }
        precis = precis / f64(n)
        if maxewt <= 1.0f64 {
            steady = 1usize
            go = false
        } else {
            let info = dgefa(alpha, n, piv)
            if info != 0usize {
                go = false
            } else {
                dgesl(alpha, n, piv, beta)
                var change = 0.0f64
                i = 0usize
                while i < n {
                    var ab = beta[i]
                    if ab < 0.0f64 { ab = 0.0f64 - ab }
                    if ab > change { change = ab }
                    y[i] = y[i] + beta[i]
                    if positive && y[i] < 0.0f64 { y[i] = 0.0f64 }
                    i += 1usize
                }
                if change <= ctol {
                    steady = 1usize
                    go = false
                    if k < maxiter {
                        i = 0usize
                        while i < n {
                            beta[i] = 0.0f64
                            i += 1usize
                        }
                        rhs(sid, parms, y, beta)
                        precis = 0.0f64
                        i = 0usize
                        while i < n {
                            var ab = beta[i]
                            if ab < 0.0f64 { ab = 0.0f64 - ab }
                            precis = precis + ab
                            i += 1usize
                        }
                        precis = precis / f64(n)
                        iter = k + 1usize
                    }
                }
            }
        }
        k += 1usize
    }
    ret (iter, steady, precis)
}

// jacobian.full(y, func, parms = parms, pert = pert) with time 0: the n by n forward-difference Jacobian into jac (row-major, jac[row * n + col])
fn jacobian_full(a: *mem.Arena, sid: usize, parms: []const f64, y: []const f64, pert: f64, jac: []f64) {
    let n = dim_of(sid)
    let (ref, e1) = mem.alloc[f64](a, n)
    let (yw, e2) = mem.alloc[f64](a, n)
    let (dy, e3) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret }
    var i = 0usize
    while i < n {
        yw[i] = y[i]
        i += 1usize
    }
    rhs(sid, parms, y, ref)
    var j = 0usize
    while j < n {
        let d = perturb(y[j], pert)
        yw[j] = y[j] + d
        rhs(sid, parms, yw, dy)
        i = 0usize
        while i < n {
            jac[i * n + j] = (dy[i] - ref[i]) / d
            i += 1usize
        }
        yw[j] = y[j]
        j += 1usize
    }
}
