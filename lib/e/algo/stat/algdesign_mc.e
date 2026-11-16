// R AlgDesign's optMonteCarlo (MonteOpt.R): random candidate sets drawn over the variable ranges (levels, a mixture on the simplex,
// optional constraints), each searched by the Fedorov exchange of algdesign_fed, repeated while the criterion improves, at most
// nRepeats + 1 times. The model expansion (R's formula and model.matrix) is the caller's `expand`: it maps nrows by nvar variable
// values (row-major) to the nrows by k model matrix. RandomStart = FALSE (nullification with random candidates) is not here.
//
// R sums the mixture with long doubles; here the sum is in double, which differs in the last bit only.

use e.algo.rand.r as rng
use e.algo.stat.algdesign_fed as fed
use e.math
use e.mem
use e.text.prettyunits as pu

// the variables: lim_lo, lim_range (high - low) and lim_center, the number of levels, rounding digits and the mixture flag, each nvar long
type Vars = struct {
    nvar: usize,
    lo: []f64,
    range: []f64,
    center: []f64,
    nlevels: []f64,
    digits: []usize,
    mixture: []bool,
}

// Expand[C]: variable values (nrows by nvar, row-major) to the model matrix (nrows by k); returns k
type McRes = struct { dd: f64, aa: f64, ii: f64, gg: f64, nrows: usize, design: []f64, proportions: []f64, errcode: i64 }

fn count_true(m: []const bool) -> usize {
    var c = 0usize
    var i = 0usize
    while i < m.len {
        if m[i] { c += 1usize }
        i += 1usize
    }
    ret c
}

// RandomMixture(N): barycentric values summing to the rounded mixtureSum
fn random_mixture(a: *mem.Arena, g: *rng.Rng, nm: usize, msum: f64, mix_round: usize, out: []f64) -> err {
    var s = 0.0f64
    var i = 0usize
    while i < nm {
        out[i] = rng.rexp(g, 1.0f64)
        s += out[i]
        i += 1usize
    }
    var ms = msum
    i = 0usize
    while i < nm {
        out[i] = out[i] / s
        i += 1usize
    }
    if msum != 0.0f64 {
        ms = pu.fround(msum, mix_round)
        i = 0usize
        while i < nm {
            out[i] = out[i] * ms
            i += 1usize
        }
    }
    var t = 0.0f64
    i = 0usize
    while i < nm {
        out[i] = pu.fround(out[i], mix_round)
        t += out[i]
        i += 1usize
    }
    let d = ms - t
    let (perm, e) = rng.sample_int(a, g, i64(nm), i64(nm), false)
    if e != ok { ret e }
    let j = usize(perm[0usize] - 1i64)
    out[j] = out[j] + d
    ret ok
}

// RandomCand(N, nTrials): nrows candidate points, row-major, centred when do_center
fn random_cand[C: type](a: *mem.Arena, g: *rng.Rng, v: *const Vars, nrows: usize, do_center: bool, mix_sum: f64, mix_round: usize, constraints_ctx: *C, constraints: fn(*C, []const f64) -> bool, has_constraints: bool, out: []f64) -> err {
    let nv = v.nvar
    let nmix = count_true(v.mixture)
    let (q, e1) = mem.alloc[f64](a, nv)
    let (mx, e2) = mem.alloc[f64](a, nmix + 1usize)
    if e1 != ok || e2 != ok { ret e1 }
    var i = 0usize
    while i < nv {
        q[i] = 0.0f64
        i += 1usize
    }
    var inside = 0usize
    while inside < nrows {
        if nv > nmix {
            // RandomLevels over the non-mixture variables: runif once per variable, in order
            i = 0usize
            while i < nv {
                if !v.mixture[i] {
                    let s = v.nlevels[i] - 1.0f64
                    let u = rng.unif(g)
                    q[i] = v.lo[i] + pu.rint(s * u) / s * v.range[i]
                }
                i += 1usize
            }
        }
        if nmix > 0usize {
            let me = random_mixture(a, g, nmix, mix_sum, mix_round, mx)
            if me != ok { ret me }
            var j = 0usize
            i = 0usize
            while i < nv {
                if v.mixture[i] {
                    q[i] = mx[j]
                    j += 1usize
                }
                i += 1usize
            }
        }
        var accept = true
        if has_constraints { accept = constraints(constraints_ctx, q) }
        if accept {
            if do_center {
                i = 0usize
                while i < nv {
                    if !v.mixture[i] { q[i] = q[i] - v.center[i] }
                    i += 1usize
                }
            }
            i = 0usize
            while i < nv {
                out[inside * nv + i] = q[i]
                i += 1usize
            }
            inside += 1usize
        }
    }
    i = 0usize
    while i < nv {
        if !v.mixture[i] {
            var r = 0usize
            while r < nrows {
                out[r * nv + i] = pu.fround(out[r * nv + i], v.digits[i])
                r += 1usize
            }
        }
        i += 1usize
    }
    ret ok
}

// optMonteCarlo(frml, data, nTrials, approximate, criterion, evaluateI, mixtureSum, constraints, RandomStart = TRUE, nRepeats, nCand, DFrac, CFrac)
// criterion 0 D, 1 A, 2 I; n_trials 0 means missing; ncand 0 means 10 k; has_intercept is whether the model matrix has an intercept
fn opt_monte_carlo[C: type](a: *mem.Arena, g: *rng.Rng, v: *const Vars, ctx: *C, expand: fn(*C, []const f64, usize, usize, []f64) -> usize, has_intercept: bool,
                            constraints: fn(*C, []const f64) -> bool, has_constraints: bool, n_trials0: usize, approx: bool, criterion: i64, evaluate_i: bool,
                            mix_sum: f64, n_repeats: i64, ncand0: usize, dfrac: f64, cfrac: f64) -> (McRes, err) {
    var res: McRes = zero
    let nv = v.nvar
    let nmix = count_true(v.mixture)
    var mix_round = 2usize
    var i = 0usize
    while i < nv {
        if v.mixture[i] && v.digits[i] > mix_round { mix_round = v.digits[i] }
        i += 1usize
    }
    // k from one random candidate, drawn uncentred (doCenter is FALSE at this point), as R does
    let (one, e1) = mem.alloc[f64](a, nv)
    if e1 != ok { ret (res, e1) }
    let re = random_cand[C](a, g, v, 1usize, false, mix_sum, mix_round, ctx, constraints, has_constraints, one)
    if re != ok { ret (res, re) }
    let (x1, e2) = mem.alloc[f64](a, 4096usize)
    if e2 != ok { ret (res, e2) }
    let k = expand(ctx, one, 1usize, nv, x1)
    let do_center = has_intercept
    var miss_trials = false
    var n_trials = n_trials0
    if n_trials == 0usize {
        n_trials = k + 5usize
        miss_trials = true
    }
    var ncand = ncand0
    if ncand == 0usize { ncand = 10usize * k }
    var best_crit = 1.0e8f64
    if criterion == 0i64 { best_crit = 0.0f64 - 1.0e8f64 }
    var more = true
    var iter = 0i64
    var have = false
    var best: McRes = zero
    let (cand, e3) = mem.alloc[f64](a, ncand * nv)
    let (xm, e4) = mem.alloc[f64](a, ncand * k)
    let (rows, e5) = mem.alloc[i64](a, ncand + 1usize)
    let (prop, e6) = mem.alloc[f64](a, ncand + 1usize)
    if e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (res, e3) }
    while more {
        let mark = mem.mark(a)
        let ce = random_cand[C](a, g, v, ncand, do_center, mix_sum, mix_round, ctx, constraints, has_constraints, cand)
        if ce != ok { ret (res, ce) }
        let kk = expand(ctx, cand, ncand, nv, xm)
        var j = 0usize
        while j < ncand + 1usize {
            rows[j] = 0i64
            prop[j] = 0.0f64
            j += 1usize
        }
        var nt = n_trials
        if approx {
            if miss_trials { nt = k + 5usize }
        }
        var maxit = 100i64
        if approx { maxit = 1000i64 }
        var dummy: [1]f64 = zero
        let (aa, fe) = fed.fedorov(a, g, xm, ncand, kk, !approx, 0i64, criterion, evaluate_i, dummy[0usize..0usize], false, 0usize, approx, nt, maxit, 5i64, dfrac, cfrac, rows, prop)
        if fe != ok { ret (res, fe) }
        if aa.errcode != 0i64 {
            res.errcode = aa.errcode
            ret (res, mem.Invalid)
        }
        var save = false
        if criterion == 0i64 && aa.dd > best_crit {
            best_crit = aa.dd
            save = true
        } else if criterion == 1i64 && aa.aa < best_crit {
            best_crit = aa.aa
            save = true
        } else if criterion == 2i64 && aa.ii < best_crit {
            best_crit = aa.ii
            save = true
        }
        if save {
            // the chosen candidate rows (sorted, 1-based modulo N) with the centring taken off
            var cnt = nt
            var idx: []i64 = rows
            if approx {
                cnt = 0usize
                j = 0usize
                while j < ncand {
                    if prop[j] > 0.0f64 { cnt += 1usize }
                    j += 1usize
                }
            }
            let (dsn, de) = mem.alloc[f64](a, cnt * nv)
            let (srt, se) = mem.alloc[i64](a, cnt)
            if de != ok || se != ok { ret (res, de) }
            if approx {
                var c2 = 0usize
                j = 0usize
                while j < ncand {
                    if prop[j] > 0.0f64 {
                        srt[c2] = i64(j)
                        c2 += 1usize
                    }
                    j += 1usize
                }
            } else {
                j = 0usize
                while j < cnt {
                    srt[j] = idx[j] % i64(ncand)
                    j += 1usize
                }
                var s1 = 1usize
                while s1 < cnt {
                    let t = srt[s1]
                    var s2 = s1
                    while s2 > 0usize && srt[s2 - 1usize] > t {
                        srt[s2] = srt[s2 - 1usize]
                        s2 -= 1usize
                    }
                    srt[s2] = t
                    s1 += 1usize
                }
            }
            j = 0usize
            while j < cnt {
                var c3 = 0usize
                while c3 < nv {
                    var val = cand[usize(srt[j]) * nv + c3]
                    if do_center { val = val + v.center[c3] }
                    dsn[j * nv + c3] = val
                    c3 += 1usize
                }
                j += 1usize
            }
            best = aa_to_mc(aa)
            best.nrows = cnt
            best.design = dsn
            have = true
        } else {
            more = false
        }
        iter += 1i64
        if iter > n_repeats { more = false }
        if more == false { }
    }
    if !have { ret (res, mem.Invalid) }
    ret (best, ok)
}

fn aa_to_mc(r: fed.Res) -> McRes {
    var m: McRes = zero
    m.dd = r.dd
    m.aa = r.aa
    m.ii = r.ii
    m.gg = r.gg
    ret m
}
