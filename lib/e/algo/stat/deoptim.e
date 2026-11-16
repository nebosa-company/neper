// R DEoptimR::JDEoptim, the jDE differential evolution of Brest et al. with Tsutsui-style adaptive handling of
// constraints, on the R random stream: the same draws in the same order, so under the same seed the population,
// the returned optimum, the value and the iteration count are the package's. Constraints follow the package:
// `constr` fills m values that must be <= 0, the first `meq` being equalities taken as |h| - eps <= 0.
//
// Not here: add_to_init_pop, the `trace` output, jitter_factor = NULL (the one-row F matrix), details.

use e.algo.rand.r as rr
use e.math
use e.mem

type Result = struct { value: f64, iter: usize, convergence: u8 }

type Prob[C: type] = struct { f: fn(*C, []const f64) -> f64, cons: fn(*C, []const f64, []f64), ctx: *C, m: usize, meq: usize, eps: f64 }

fn median_of(v: []const f64, tmp: []f64) -> f64 {
    let n = v.len
    var i = 0usize
    while i < n {
        tmp[i] = v[i]
        i += 1usize
    }
    // insertion sort; n is a population size
    i = 1usize
    while i < n {
        let x = tmp[i]
        var j = i
        while j > 0usize && tmp[j - 1usize] > x {
            tmp[j] = tmp[j - 1usize]
            j -= 1usize
        }
        tmp[j] = x
        i += 1usize
    }
    if n % 2usize == 1usize { ret tmp[n / 2usize] }
    ret (tmp[n / 2usize - 1usize] + tmp[n / 2usize]) / 2.0f64
}

// constr1: apply the equality shift and fill h; returns the total violation sum(max(h, 0))
fn evaluate_constraints[C: type](p: *Prob[C], x: []const f64, h: []f64) -> f64 {
    p.cons(p.ctx, x, h)
    var k = 0usize
    while k < p.meq {
        h[k] = math.abs[f64](h[k]) - p.eps
        k += 1usize
    }
    var tav = 0.0f64
    k = 0usize
    while k < p.m {
        if h[k] > 0.0f64 { tav += h[k] }
        k += 1usize
    }
    ret tav
}

// pop receives the final population (d by NP, column-major) and best the optimum
fn jdeoptim[C: type](a: *mem.Arena, g: *rr.Rng, prob: *Prob[C], lower: []const f64, upper: []const f64, np: usize, fl: f64, fu: f64, tau_f: f64, tau_cr: f64, tau_pf: f64, jitter: f64, tol: f64, maxiter: usize, fnscale: f64, use_max: bool, best: []f64) -> (Result, err) {
    let d = lower.len
    var res: Result = zero
    let has_cons = prob.m > 0usize
    let (pop, e1) = mem.alloc[f64](a, d * np)
    let (fm, e2) = mem.alloc[f64](a, d * np)
    let (cr, e3) = mem.alloc[f64](a, np)
    let (pf, e4) = mem.alloc[f64](a, np)
    let (fpop, e5) = mem.alloc[f64](a, np)
    let (hpop, e6) = mem.alloc[f64](a, prob.m * np + 1usize)
    let (tav, e7) = mem.alloc[f64](a, np)
    let (tmp, e8) = mem.alloc[f64](a, np)
    let (trial, e9) = mem.alloc[f64](a, d)
    let (ftrial, e10) = mem.alloc[f64](a, d)
    let (htrial, e11) = mem.alloc[f64](a, prob.m + 1usize)
    let (ign, e12) = mem.alloc[bool](a, d)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok { ret (res, e1) }
    var k = 0usize
    while k < d * np {
        pop[k] = rr.runif(g, lower[k % d], upper[k % d])
        k += 1usize
    }
    // F = (1 + jitter * runif(d, -0.5, 0.5)) %o% runif(NP, Fl, Fu)
    let (jv, e13) = mem.alloc[f64](a, d)
    if e13 != ok { ret (res, e13) }
    k = 0usize
    while k < d {
        jv[k] = 1.0f64 + jitter * rr.runif(g, 0.0f64 - 0.5f64, 0.5f64)
        k += 1usize
    }
    var i = 0usize
    while i < np {
        let u = rr.runif(g, fl, fu)
        k = 0usize
        while k < d {
            fm[i * d + k] = jv[k] * u
            k += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < np {
        cr[i] = rr.unif(g)
        i += 1usize
    }
    i = 0usize
    while i < np {
        pf[i] = rr.unif(g)
        i += 1usize
    }
    i = 0usize
    while i < np {
        fpop[i] = prob.f(prob.ctx, pop[i * d..i * d + d])
        i += 1usize
    }
    var mu = 0.0f64
    if has_cons {
        i = 0usize
        while i < np {
            prob.cons(prob.ctx, pop[i * d..i * d + d], htrial)
            k = 0usize
            while k < prob.meq {
                htrial[k] = math.abs[f64](htrial[k]) - prob.eps
                k += 1usize
            }
            var t = 0.0f64
            k = 0usize
            while k < prob.m {
                hpop[i * prob.m + k] = htrial[k]
                if htrial[k] > 0.0f64 { t += htrial[k] }
                k += 1usize
            }
            tav[i] = t
            i += 1usize
        }
        mu = median_of(tav, tmp)
    }
    var xb = which_best(fpop, tav, mu, np, has_cons)
    var converge = 0.0f64
    if use_max { converge = (vmax(fpop) - fpop[xb]) / fnscale } else { converge = (median_of(fpop, tmp) - fpop[xb]) / fnscale }
    var iteration = 0usize
    while converge >= tol || (has_cons && any_pos(hpop, xb * prob.m, prob.m)) {
        if iteration >= maxiter {
            res.convergence = 1u8
            break
        }
        iteration += 1usize
        var ii = 1usize
        while ii <= np {
            let idx = (iteration + ii) % np
            // 0-based population member
            let mi = idx
            // Ftrial
            if rr.unif(g) <= tau_f {
                let u = rr.runif(g, fl, fu)
                k = 0usize
                while k < d {
                    ftrial[k] = u * (1.0f64 + jitter * rr.runif(g, 0.0f64 - 0.5f64, 0.5f64))
                    k += 1usize
                }
            } else {
                k = 0usize
                while k < d {
                    ftrial[k] = fm[mi * d + k]
                    k += 1usize
                }
            }
            var crt = cr[mi]
            if rr.unif(g) <= tau_cr { crt = rr.unif(g) }
            var pft = pf[mi]
            if rr.unif(g) <= tau_pf { pft = rr.unif(g) }
            // r <- sample(popIndex[-i], 3): population indices other than member mi, in order
            let (s3, se) = rr.sample_int(a, g, i64(np - 1usize), 3i64, false)
            if se != ok { ret (res, se) }
            var r1 = 0usize
            var r2 = 0usize
            var r3 = 0usize
            var q = 0usize
            while q < 3usize {
                var pick = usize(s3[q]) - 1usize
                if pick >= mi { pick += 1usize }
                if q == 0usize { r1 = pick } else if q == 1usize { r2 = pick } else { r3 = pick }
                q += 1usize
            }
            // performReproduction
            var all_ignore = true
            k = 0usize
            while k < d {
                ign[k] = rr.unif(g) > crt
                if !ign[k] { all_ignore = false }
                k += 1usize
            }
            if all_ignore {
                let (s1, s1e) = rr.sample_int(a, g, i64(d), 1i64, false)
                if s1e != ok { ret (res, s1e) }
                ign[usize(s1[0usize]) - 1usize] = false
            }
            let use_f = rr.unif(g) <= pft
            k = 0usize
            while k < d {
                let xbase = pop[r1 * d + k]
                let x1 = pop[r2 * d + k]
                let x2 = pop[r3 * d + k]
                var t = 0.0f64
                if use_f { t = xbase + ftrial[k] * (x1 - x2) } else { t = xbase + 0.5f64 * (ftrial[k] + 1.0f64) * (x1 + x2 - 2.0f64 * xbase) }
                if ign[k] { t = pop[mi * d + k] }
                // handle.bounds
                if t > upper[k] { t = 0.5f64 * (upper[k] + xbase) }
                if t < lower[k] { t = 0.5f64 * (lower[k] + xbase) }
                trial[k] = t
                k += 1usize
            }
            if !has_cons {
                let ft = prob.f(prob.ctx, trial)
                if ft <= fpop[mi] {
                    accept(pop, fm, cr, pf, mi, d, trial, ftrial, crt, pft)
                    fpop[mi] = ft
                }
            } else {
                let tt = evaluate_constraints[C](prob, trial, htrial)
                if tt > mu {
                    if tt <= tav[mi] {
                        accept(pop, fm, cr, pf, mi, d, trial, ftrial, crt, pft)
                        copy_h(hpop, mi, prob.m, htrial)
                        tav[mi] = tt
                    }
                } else if tav[mi] > mu {
                    accept(pop, fm, cr, pf, mi, d, trial, ftrial, crt, pft)
                    fpop[mi] = prob.f(prob.ctx, trial)
                    copy_h(hpop, mi, prob.m, htrial)
                    tav[mi] = tt
                    if prob.meq == 0usize { mu = mu * (1.0f64 - frac_feasible(tav, mu, np) / f64(np)) }
                } else {
                    let ft = prob.f(prob.ctx, trial)
                    if ft <= fpop[mi] {
                        accept(pop, fm, cr, pf, mi, d, trial, ftrial, crt, pft)
                        fpop[mi] = ft
                        copy_h(hpop, mi, prob.m, htrial)
                        tav[mi] = tt
                        mu = mu * (1.0f64 - frac_feasible(tav, mu, np) / f64(np))
                    }
                }
            }
            xb = which_best(fpop, tav, mu, np, has_cons)
            ii += 1usize
        }
        if use_max { converge = (vmax(fpop) - fpop[xb]) / fnscale } else { converge = (median_of(fpop, tmp) - fpop[xb]) / fnscale }
    }
    k = 0usize
    while k < d {
        best[k] = pop[xb * d + k]
        k += 1usize
    }
    res.value = fpop[xb]
    res.iter = iteration
    ret (res, ok)
}

fn vmax(v: []const f64) -> f64 {
    var m = v[0usize]
    var i = 1usize
    while i < v.len {
        if v[i] > m { m = v[i] }
        i += 1usize
    }
    ret m
}

fn any_pos(h: []const f64, at: usize, m: usize) -> bool {
    var k = 0usize
    while k < m {
        if h[at + k] > 0.0f64 { ret true }
        k += 1usize
    }
    ret false
}

fn frac_feasible(tav: []const f64, mu: f64, np: usize) -> f64 {
    var c = 0.0f64
    var i = 0usize
    while i < np {
        if tav[i] <= mu { c += 1.0f64 }
        i += 1usize
    }
    ret c / f64(np)
}

fn copy_h(hpop: []f64, mi: usize, m: usize, h: []const f64) {
    var k = 0usize
    while k < m {
        hpop[mi * m + k] = h[k]
        k += 1usize
    }
}

fn accept(pop: []f64, fm: []f64, cr: []f64, pf: []f64, mi: usize, d: usize, trial: []const f64, ftrial: []const f64, crt: f64, pft: f64) {
    var k = 0usize
    while k < d {
        pop[mi * d + k] = trial[k]
        fm[mi * d + k] = ftrial[k]
        k += 1usize
    }
    cr[mi] = crt
    pf[mi] = pft
}

fn which_best(fpop: []const f64, tav: []const f64, mu: f64, np: usize, has_cons: bool) -> usize {
    var best = 0usize
    var i = 1usize
    if !has_cons {
        while i < np {
            if fpop[i] < fpop[best] { best = i }
            i += 1usize
        }
        ret best
    }
    var count = 0usize
    i = 0usize
    while i < np {
        if tav[i] <= mu { count += 1usize }
        i += 1usize
    }
    if count == np {
        i = 1usize
        while i < np {
            if fpop[i] < fpop[best] { best = i }
            i += 1usize
        }
        ret best
    }
    if count > 0usize {
        var found = false
        i = 0usize
        while i < np {
            if tav[i] <= mu && (!found || fpop[i] < fpop[best]) {
                best = i
                found = true
            }
            i += 1usize
        }
        ret best
    }
    i = 1usize
    while i < np {
        if tav[i] < tav[best] { best = i }
        i += 1usize
    }
    ret best
}
