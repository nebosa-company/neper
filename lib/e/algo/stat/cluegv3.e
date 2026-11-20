// R clue, cl_consensus(method = "GV3"): the membership matrix M (n by k, stochastic) minimising |Y - M M'|^2 for Y the weighted comembership matrix of the ensemble, by clue's sumt
// (sequential unconstrained minimisation: a quadratic penalty for negative entries and row sums off one, the penalty weight times ten until the iterate settles) with optim's
// conjugate gradients "CG" (R's cgmin: Fletcher-Reeves, 100 gradient evaluations per call, the point of the last gradient evaluation is the answer). The start is the rank k root of Y
// from eigen(Y), the further runs perturb it with rnorm(sd = sd(m) / sqrt(3)). Memberships are n by k row-major with every partition padded to k columns; the working vector m is the
// column-major n by k matrix as in R.

use e.algo.linalg.lapack_syevr as sy
use e.algo.rand.r as rr
use e.math
use e.math.nmath as nm
use e.mem

error Malformed

type Prob = struct { n: usize, k: usize, y: []const f64, cm: []f64, rho: f64 }

// R's sum() and rowSums() accumulate in a long double (the 64-bit mantissa of x87) and round the result to double. The accumulator keeps the exact value as hi + lo with lo
// rounded to the 64-bit mantissa after every addition (ties to even), so the sums come out as R's
type Acc = struct { hi: f64, lo: f64 }

fn acc_add(s: *Acc, x: f64) {
    let t = s.hi + x
    let bb = t - s.hi
    let er = (s.hi - (t - bb)) + (x - bb)
    let lo0 = s.lo + er
    let h2 = t + lo0
    let l2 = lo0 - (h2 - t)
    if h2 == 0.0f64 || l2 == 0.0f64 {
        s.hi = h2
        s.lo = l2
        ret
    }
    let (_, ex) = nm.frexp(h2)
    let q = nm.ldexp(1.0f64, ex - 64i64)
    let kq = l2 / q
    var fl = math.floor[f64](kq)
    let fr = kq - fl
    if fr > 0.5f64 { fl += 1.0f64 }
    if fr == 0.5f64 {
        let half = math.floor[f64](fl / 2.0f64) * 2.0f64
        if half != fl { fl += 1.0f64 }
    }
    s.hi = h2
    s.lo = fl * q
}

fn acc_val(s: *const Acc) -> f64 { ret s.hi + s.lo }

// tcrossprod(matrix(m, n)): out[i * n + l] = sum_j m[j n + i] m[j n + l]
fn tcross(m: []const f64, n: usize, k: usize, out: []f64) {
    var i = 0usize
    while i < n {
        var l = 0usize
        while l < n {
            var s = 0.0f64
            var j = 0usize
            while j < k {
                s += m[j * n + i] * m[j * n + l]
                j += 1usize
            }
            out[i * n + l] = s
            l += 1usize
        }
        i += 1usize
    }
}

fn lval(p: *Prob, m: []const f64) -> f64 {
    tcross(m, p.n, p.k, p.cm)
    var s = Acc { hi: 0.0f64, lo: 0.0f64 }
    var l = 0usize
    while l < p.n {
        var i = 0usize
        while i < p.n {
            let d = p.y[i * p.n + l] - p.cm[i * p.n + l]
            acc_add(&s, d * d)
            i += 1usize
        }
        l += 1usize
    }
    ret acc_val(&s)
}

fn pval(p: *Prob, m: []const f64) -> f64 {
    var s1 = Acc { hi: 0.0f64, lo: 0.0f64 }
    var i = 0usize
    while i < p.n * p.k {
        if m[i] < 0.0f64 { acc_add(&s1, m[i] * m[i]) }
        i += 1usize
    }
    var s2 = Acc { hi: 0.0f64, lo: 0.0f64 }
    i = 0usize
    while i < p.n {
        var rs = Acc { hi: 0.0f64, lo: 0.0f64 }
        var j = 0usize
        while j < p.k {
            acc_add(&rs, m[j * p.n + i])
            j += 1usize
        }
        let rv = acc_val(&rs)
        acc_add(&s2, (rv - 1.0f64) * (rv - 1.0f64))
        i += 1usize
    }
    ret acc_val(&s1) + acc_val(&s2)
}

fn phi(p: *Prob, m: []const f64) -> f64 { ret lval(p, m) + p.rho * pval(p, m) }

// grad L + rho grad P: 4 (M M' - Y) M + rho 2 (pmin(m, 0) + (rowSums(M) - 1))
fn gphi(p: *Prob, m: []const f64, g: []f64) {
    tcross(m, p.n, p.k, p.cm)
    var j = 0usize
    while j < p.k {
        var i = 0usize
        while i < p.n {
            var s = 0.0f64
            var l = 0usize
            while l < p.n {
                s += (p.cm[i * p.n + l] - p.y[i * p.n + l]) * m[j * p.n + l]
                l += 1usize
            }
            var rsa = Acc { hi: 0.0f64, lo: 0.0f64 }
            var q = 0usize
            while q < p.k {
                acc_add(&rsa, m[q * p.n + i])
                q += 1usize
            }
            let rs = acc_val(&rsa)
            var mn = m[j * p.n + i]
            if mn > 0.0f64 { mn = 0.0f64 }
            g[j * p.n + i] = 4.0f64 * s + p.rho * 2.0f64 * (mn + (rs - 1.0f64))
            i += 1usize
        }
        j += 1usize
    }
}

fn finite(x: f64) -> bool { ret x == x && x - x == 0.0f64 }

// optim(x, fn, gr, method = "CG") with the defaults (type 1, reltol sqrt(eps), maxit 100, abstol -Inf): x holds the start and receives the point of the last gradient evaluation
fn cgmin(a: *mem.Arena, p: *Prob, x: []f64) -> err {
    let n = p.n * p.k
    let (bvec, e0) = mem.alloc[f64](a, n)
    let (c, e1) = mem.alloc[f64](a, n)
    let (g, e2) = mem.alloc[f64](a, n)
    let (t, e3) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    let intol = 1.4901161193847656e-8f64
    let maxit = 100usize
    let stepredn = 0.2f64
    let acctol = 0.0001f64
    let reltest = 10.0f64
    let setstep = 1.7f64
    var i = 0usize
    while i < n {
        bvec[i] = x[i]
        i += 1usize
    }
    let tol = intol * f64(n) * math.sqrt[f64](intol)
    var f = phi(p, bvec)
    if !finite(f) { ret Malformed }
    var fmin = f
    var gradcount = 0usize
    var cycle = 0usize
    var count = 0usize
    var g1 = 0.0f64
    var steplength = 1.0f64
    var again = true
    while again {
        i = 0usize
        while i < n {
            t[i] = 0.0f64
            c[i] = 0.0f64
            i += 1usize
        }
        cycle = 0usize
        var oldstep = 1.0f64
        count = 0usize
        var inner = true
        while inner {
            cycle += 1usize
            gradcount += 1usize
            if gradcount > maxit { ret ok }
            gphi(p, bvec, g)
            g1 = 0.0f64
            var g2 = 0.0f64
            i = 0usize
            while i < n {
                x[i] = bvec[i]
                g1 += g[i] * g[i]
                g2 += c[i] * c[i]
                c[i] = g[i]
                i += 1usize
            }
            if g1 > tol {
                var g3 = 1.0f64
                if g2 > 0.0f64 { g3 = g1 / g2 }
                var gradproj = 0.0f64
                i = 0usize
                while i < n {
                    t[i] = t[i] * g3 - g[i]
                    gradproj += t[i] * g[i]
                    i += 1usize
                }
                steplength = oldstep
                var accpoint = false
                var search = true
                while search {
                    count = 0usize
                    i = 0usize
                    while i < n {
                        bvec[i] = x[i] + steplength * t[i]
                        if reltest + x[i] == reltest + bvec[i] { count += 1usize }
                        i += 1usize
                    }
                    if count < n {
                        f = phi(p, bvec)
                        accpoint = finite(f) && f <= fmin + gradproj * steplength * acctol
                        if !accpoint {
                            steplength = steplength * stepredn
                        } else {
                            fmin = f
                        }
                    }
                    if count == n || accpoint { search = false }
                }
                if count < n {
                    var newstep = 2.0f64 * (f - fmin - gradproj * steplength)
                    if newstep > 0.0f64 {
                        newstep = 0.0f64 - gradproj * steplength * steplength / newstep
                        i = 0usize
                        while i < n {
                            bvec[i] = x[i] + newstep * t[i]
                            i += 1usize
                        }
                        fmin = f
                        f = phi(p, bvec)
                        if f < fmin {
                            fmin = f
                        } else {
                            i = 0usize
                            while i < n {
                                bvec[i] = x[i] + steplength * t[i]
                                i += 1usize
                            }
                        }
                    }
                }
            }
            oldstep = setstep * steplength
            if oldstep > 1.0f64 { oldstep = 1.0f64 }
            if !(count != n && g1 > tol && cycle != n) { inner = false }
        }
        if !(cycle != 1usize || (count != n && g1 > tol)) { again = false }
    }
    ret ok
}

// the sumt of clue from one start: x holds the start and receives the minimiser; the answer is the penalised value at the stopping point
fn sumt_run(a: *mem.Arena, p: *Prob, x: []f64) -> (f64, err) {
    let n = p.n * p.k
    let (xold, e0) = mem.alloc[f64](a, n)
    if e0 != ok { ret (0.0f64, mem.Full) }
    let eps = 1.4901161193847656e-8f64
    var l0 = lval(p, x)
    if l0 < 0.00001f64 { l0 = 0.00001f64 }
    var p0 = pval(p, x)
    if p0 < 0.00001f64 { p0 = 0.00001f64 }
    p.rho = l0 / p0
    var go = true
    while go {
        var i = 0usize
        while i < n {
            xold[i] = x[i]
            i += 1usize
        }
        let e = cgmin(a, p, x)
        if e != ok { ret (0.0f64, e) }
        var md = 0.0f64
        i = 0usize
        while i < n {
            var d = xold[i] - x[i]
            if d < 0.0f64 { d = 0.0f64 - d }
            if d > md { md = d }
            i += 1usize
        }
        if md < eps { go = false } else { p.rho = 10.0f64 * p.rho }
    }
    ret (phi(p, x), ok)
}

// cl_consensus(method = "GV3", weights = w, control = list(nruns = nruns)) after set.seed: mems are bn memberships n by k row-major; out receives the n by k consensus membership
fn consensus_gv3(a: *mem.Arena, g: *rr.Rng, mems: []const f64, w: []const f64, bn: usize, n: usize, k: usize, nruns: usize, stage: usize, out: []f64) -> err {
    let sz = n * k
    let (y, e0) = mem.alloc[f64](a, n * n)
    let (cm, e1) = mem.alloc[f64](a, n * n)
    let (ev, e2) = mem.alloc[f64](a, n)
    let (zv, e3) = mem.alloc[f64](a, n * n)
    let (m0, e4) = mem.alloc[f64](a, sz)
    let (x, e5) = mem.alloc[f64](a, sz)
    let (best, e6) = mem.alloc[f64](a, sz)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret mem.Full }
    var wacc = Acc { hi: 0.0f64, lo: 0.0f64 }
    var b = 0usize
    while b < bn {
        acc_add(&wacc, w[b])
        b += 1usize
    }
    let ws = acc_val(&wacc)
    var i = 0usize
    while i < n {
        var l = 0usize
        while l < n {
            var sacc = Acc { hi: 0.0f64, lo: 0.0f64 }
            b = 0usize
            while b < bn {
                var cs = 0.0f64
                var j = 0usize
                while j < k {
                    cs += mems[b * sz + i * k + j] * mems[b * sz + l * k + j]
                    j += 1usize
                }
                acc_add(&sacc, (w[b] / ws) * cs)
                b += 1usize
            }
            // column-major y, symmetric
            y[l * n + i] = acc_val(&sacc)
            l += 1usize
        }
        i += 1usize
    }
    let ee = sy.dsyevr_all(a, y, n, ev, zv)
    if ee != ok { ret ee }
    // M = U_k lambda_k^(1/2), column-major
    var j2 = 0usize
    while j2 < k {
        let col = n - 1usize - j2
        let sq = math.sqrt[f64](ev[col])
        i = 0usize
        while i < n {
            m0[j2 * n + i] = zv[col * n + i] * sq
            i += 1usize
        }
        j2 += 1usize
    }
    // y is symmetric: the row-major copy the objective reads is the same matrix
    var p = Prob { n: n, k: k, y: y, cm: cm, rho: 1.0f64 }
    if stage == 1usize {
        var q = 0usize
        while q < sz {
            out[q] = m0[q]
            q += 1usize
        }
        ret ok
    }
    if stage == 3usize {
        var q = 0usize
        while q < sz {
            x[q] = m0[q]
            q += 1usize
        }
        let (sv, es) = sumt_run(a, &p, x)
        let _ = sv
        q = 0usize
        while q < sz {
            out[q] = x[q]
            q += 1usize
        }
        ret es
    }
    if stage == 2usize {
        var q = 0usize
        while q < sz {
            x[q] = m0[q]
            q += 1usize
        }
        var l0 = lval(&p, x)
        if l0 < 0.00001f64 { l0 = 0.00001f64 }
        var p0 = pval(&p, x)
        if p0 < 0.00001f64 { p0 = 0.00001f64 }
        p.rho = l0 / p0
        var ec = ok
        var calls = 0usize
        while calls < nruns {
            let (xold2, ex2) = mem.alloc[f64](a, sz)
            if ex2 != ok { ret ex2 }
            var u = 0usize
            while u < sz {
                xold2[u] = x[u]
                u += 1usize
            }
            ec = cgmin(a, &p, x)
            var mxd = 0.0f64
            u = 0usize
            while u < sz {
                var dd = xold2[u] - x[u]
                if dd < 0.0f64 { dd = 0.0f64 - dd }
                if dd > mxd { mxd = dd }
                u += 1usize
            }
            if mxd < 1.4901161193847656e-8f64 { calls = nruns } else {
                p.rho = 10.0f64 * p.rho
                calls += 1usize
            }
        }
        q = 0usize
        while q < sz {
            out[q] = x[q]
            q += 1usize
        }
        ret ec
    }
    var vbest = 0.0f64
    var run = 0usize
    while run < nruns {
        i = 0usize
        while i < sz {
            x[i] = m0[i]
            i += 1usize
        }
        if run > 0usize {
            var mean = 0.0f64
            i = 0usize
            while i < sz {
                mean += m0[i]
                i += 1usize
            }
            mean = mean / f64(sz)
            var ss = 0.0f64
            i = 0usize
            while i < sz {
                ss += (m0[i] - mean) * (m0[i] - mean)
                i += 1usize
            }
            let sdv = math.sqrt[f64](ss / f64(sz - 1usize)) / math.sqrt[f64](3.0f64)
            i = 0usize
            while i < sz {
                x[i] = m0[i] + rr.rnorm(g, 0.0f64, sdv)
                i += 1usize
            }
        }
        let (v, e) = sumt_run(a, &p, x)
        if e != ok { ret e }
        if run == 0usize || v < vbest {
            vbest = v
            i = 0usize
            while i < sz {
                best[i] = x[i]
                i += 1usize
            }
        }
        run += 1usize
    }
    // .stochastify and the row-major result
    i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < k {
            var v = best[j * n + i]
            if v < 0.0f64 { v = 0.0f64 }
            out[i * k + j] = v
            s += v
            j += 1usize
        }
        j = 0usize
        while j < k {
            out[i * k + j] = out[i * k + j] / s
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}
