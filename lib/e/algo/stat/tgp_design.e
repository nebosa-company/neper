// R's tgp::dopt.gp: sequential D-optimal design, an exchange algorithm over a candidate set with the
// randomkit generator seeded from R's sample(0:999, 3), and tgp.design on a fit without a tree (one partition,
// so it is dopt.gp over all the candidates with howmany new inputs). The criterion is the log determinant of the
// isotropic exponential correlation (range 0.001 m^2, nugget 0.01) of the fixed inputs and the chosen ones.
// The treed form (tgp.design on a fit with a tree) is design_treed in tgp_tree.e, which needs the best tree of the fit.

use e.algo.rand.r as rr
use e.algo.stat.tgp as tgp
use e.algo.stat.tgp_blm as lm
use e.math
use e.mem

error BadDesign

// log |K| of the n x n correlation of the rows of x (normalised), d the range and nug the nugget; -Inf if K is not
// positive definite (dpotrf fails)
fn design_logdet(x: []const f64, n: usize, m: usize, d: f64, nug: f64, k: []f64) -> f64 {
    var i = 0usize
    while i < n {
        k[i * n + i] = 1.0f64 + nug
        var j = i + 1usize
        while j < n {
            var s = 0.0f64
            var q = 0usize
            while q < m {
                let diff = x[i * m + q] - x[j * m + q]
                s += diff * diff
                q += 1usize
            }
            var v = 1.0f64
            if d != 0.0f64 { v = math.exp[f64](0.0f64 - s / d) } else { v = 0.0f64 }
            k[i * n + j] = v
            k[j * n + i] = v
            j += 1usize
        }
        i += 1usize
    }
    // in-place lower Cholesky, then 2 sum log diag
    var tot = 0.0f64
    i = 0usize
    while i < n {
        var j = 0usize
        while j <= i {
            var s = k[i * n + j]
            var t = 0usize
            while t < j {
                s -= k[i * n + t] * k[j * n + t]
                t += 1usize
            }
            if i == j {
                if s > 0.0f64 { k[i * n + i] = math.sqrt[f64](s) } else { ret 0.0f64 - 1.0f64 / 0.0f64 }
                tot += math.log[f64](k[i * n + i])
            } else {
                k[i * n + j] = s / k[j * n + j]
            }
            j += 1usize
        }
        i += 1usize
    }
    ret 2.0f64 * tot
}

// isample over equal weights: the index (0-based) chosen by one uniform
fn pick_equal(rk: *tgp.Rk, len: usize) -> usize {
    let p = 1.0f64 / f64(len)
    var cum = 0.0f64
    var last = 0.0f64
    var i = 0usize
    while i < len {
        cum += p
        last = cum
        i += 1usize
    }
    var top = last
    if top < 1.0f64 { top = 1.0f64 }
    let pick = tgp.runi(rk)
    var c = 0usize
    var run = 0.0f64
    while c + 1usize < len {
        run += p
        if run < pick { c += 1usize } else { ret c }
    }
    ret c
}

// dopt.gp(nn, X, Xcand, iter) under set.seed: the 1-based candidate indices of the nn chosen inputs; x is n x m,
// xc is ncand x m (row-major, n may be 0)
fn dopt_gp(a: *mem.Arena, r: *rr.Rng, nn: usize, x: []const f64, n: usize, m: usize, xc: []const f64, ncand: usize, iter: usize) -> ([]i64, err) {
    var none: []i64 = zero
    if nn == 0usize || nn > ncand { ret (none, BadDesign) }
    let (idx, e0) = rr.sample_int(a, r, 1000i64, 3i64, false)
    if e0 != ok { ret (none, e0) }
    var rk = tgp.rk_state(idx[0usize] - 1i64, idx[1usize] - 1i64, idx[2usize] - 1i64)
    // rectangle of the fixed inputs and the candidates
    let (lo, e1) = lm.zeros(a, m)
    let (hi, e2) = lm.zeros(a, m)
    if e1 != ok || e2 != ok { ret (none, BadDesign) }
    var j = 0usize
    while j < m {
        var first = true
        var i = 0usize
        while i < n + ncand {
            var v = 0.0f64
            if i < n { v = x[i * m + j] } else { v = xc[(i - n) * m + j] }
            if first {
                lo[j] = v
                hi[j] = v
                first = false
            } else {
                if v < lo[j] {
                    lo[j] = v
                } else {
                    if v > hi[j] { hi[j] = v }
                }
            }
            i += 1usize
        }
        j += 1usize
    }
    let (fixed, e3) = lm.normalise(a, x, n, m, lo, hi)
    let (cand, e4) = lm.normalise(a, xc, ncand, m, lo, hi)
    if e3 != ok || e4 != ok { ret (none, BadDesign) }
    let (xs, e5) = lm.zeros(a, (n + nn) * m)
    let (kk, e6) = lm.zeros(a, (n + nn) * (n + nn))
    let (u, e7) = lm.zeros(a, ncand)
    if e5 != ok || e6 != ok || e7 != ok { ret (none, BadDesign) }
    let (fi, e8) = mem.alloc[i64](a, nn)
    let (avail, e9) = mem.alloc[i64](a, ncand - nn + 1usize)
    let (ord, e10) = mem.alloc[i64](a, ncand)
    if e8 != ok || e9 != ok || e10 != ok { ret (none, BadDesign) }
    var i = 0usize
    while i < n * m {
        xs[i] = fixed[i]
        i += 1usize
    }
    // rand_indices: the order (1-based) of ncand uniforms
    i = 0usize
    while i < ncand {
        u[i] = tgp.runi(&rk)
        ord[i] = i64(i)
        i += 1usize
    }
    i = 1usize
    while i < ncand {
        let xo = ord[i]
        var q = i
        while q > 0usize && u[usize(ord[q - 1usize])] > u[usize(xo)] {
            ord[q] = ord[q - 1usize]
            q -= 1usize
        }
        ord[q] = xo
        i += 1usize
    }
    i = 0usize
    while i < nn {
        fi[i] = ord[i] + 1i64
        var q = 0usize
        while q < m {
            xs[(n + i) * m + q] = cand[usize(ord[i]) * m + q]
            q += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < ncand - nn {
        avail[i] = ord[nn + i] + 1i64
        i += 1usize
    }
    let dd = 0.001f64 * f64(m * m)
    var logdet = design_logdet(xs, n + nn, m, dd, 0.01f64, kk)
    if ncand > nn {
        var it = 0usize
        while it < iter {
            let fii = pick_equal(&rk, nn)
            let ai = pick_equal(&rk, ncand - nn)
            let f = fi[fii]
            let av = avail[ai]
            fi[fii] = av
            avail[ai] = f
            var q = 0usize
            while q < m {
                xs[(n + fii) * m + q] = cand[usize(av - 1i64) * m + q]
                q += 1usize
            }
            let nl = design_logdet(xs, n + nn, m, dd, 0.01f64, kk)
            if logdet < nl {
                logdet = nl
            } else {
                fi[fii] = f
                avail[ai] = av
                q = 0usize
                while q < m {
                    xs[(n + fii) * m + q] = cand[usize(f - 1i64) * m + q]
                    q += 1usize
                }
            }
            it += 1usize
        }
    }
    ret (fi, ok)
}
