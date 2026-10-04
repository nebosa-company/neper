// `e.algo.stat.meta`: effect sizes against hand arithmetic, fixed/random
// pooling with heterogeneity, subgroup Q arithmetic and a dose meta-regression
// against its normal equations, with the zero-cell and short-storage refusals.
// Each check exits with its own code.

use e.algo.stat.meta
use e.io
use e.mem
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: log odds ratio and log risk ratio on [[20, 10], [5, 100]].
    let (or, or_error) = meta.log_odds_ratio(20u64, 10u64, 5u64, 100u64)
    if or_error != ok { os.exit(1i32) }
    if !near(or.estimate, 3.688879f64, 0.000001f64) || !near(or.variance, 0.36f64, 0.000000001f64) { os.exit(1i32) }
    let (rr, rr_error) = meta.log_risk_ratio(20u64, 10u64, 5u64, 100u64)
    if rr_error != ok { os.exit(1i32) }
    if !near(rr.estimate, 2.639057f64, 0.000001f64) || !near(rr.variance, 0.207143f64, 0.000001f64) { os.exit(1i32) }
    let (_, or_bad) = meta.log_odds_ratio(0u64, 10u64, 5u64, 100u64)
    if or_bad != meta.Invalid { os.exit(1i32) }
    let (_, rr_bad) = meta.log_risk_ratio(20u64, 10u64, 0u64, 100u64)
    if rr_bad != meta.Invalid { os.exit(1i32) }

    // 2: Cohen-d, Hedges-g and Fisher-z.
    let (d, d_error) = meta.cohen_d(10.0f64, 2.0f64, 25u64, 8.0f64, 2.5f64, 30u64)
    if d_error != ok { os.exit(2i32) }
    if !near(d.estimate, 0.874444f64, 0.000001f64) || !near(d.variance, 0.080285f64, 0.000001f64) { os.exit(2i32) }
    let (g, g_error) = meta.hedges_g(10.0f64, 2.0f64, 25u64, 8.0f64, 2.5f64, 30u64)
    if g_error != ok { os.exit(2i32) }
    if !near(g.estimate, 0.862011f64, 0.000001f64) || !near(g.variance, 0.078018f64, 0.000001f64) { os.exit(2i32) }
    let (z, z_error) = meta.fisher_z(0.6f64, 30u64)
    if z_error != ok { os.exit(2i32) }
    if !near(z.estimate, 0.693147f64, 0.000001f64) || !near(z.variance, 0.037037f64, 0.000001f64) { os.exit(2i32) }
    let (_, sd_bad) = meta.cohen_d(10.0f64, 0.0f64, 25u64, 8.0f64, 2.5f64, 30u64)
    if sd_bad != meta.Invalid { os.exit(2i32) }
    let (_, r_bad) = meta.fisher_z(1.0f64, 30u64)
    if r_bad != meta.Invalid { os.exit(2i32) }
    let (_, n_bad) = meta.fisher_z(0.6f64, 3u64)
    if n_bad != meta.Invalid { os.exit(2i32) }

    // 3: fixed and DerSimonian-Laird random pooling of [0.5, 0.8, 0.3].
    var est: [3]f64 = zero
    est[0usize] = 0.5f64
    est[1usize] = 0.8f64
    est[2usize] = 0.3f64
    var va: [3]f64 = zero
    va[0usize] = 0.04f64
    va[1usize] = 0.09f64
    va[2usize] = 0.01f64
    let (fixed, fixed_error) = meta.fixed_pool(est[..], va[..], 3usize)
    if fixed_error != ok { os.exit(3i32) }
    if !near(fixed.estimate, 0.37755f64, 0.00001f64) { os.exit(3i32) }
    let (q, q_error) = meta.q_statistic(est[..], va[..], 3usize, fixed.estimate)
    if q_error != ok || !near(q, 2.9592f64, 0.0001f64) { os.exit(3i32) }
    if !near(meta.i_squared(q, 2usize), 0.32414f64, 0.00001f64) { os.exit(3i32) }
    let (tau2, tau2_error) = meta.tau_squared_dl(q, va[..], 3usize)
    if tau2_error != ok || !near(tau2, 0.016786f64, 0.000001f64) { os.exit(3i32) }
    let (random, random_error) = meta.random_pool(est[..], va[..], 3usize, tau2)
    if random_error != ok { os.exit(3i32) }
    if !near(random.estimate, 0.42758f64, 0.00001f64) || !near(random.se, 0.12470f64, 0.00001f64) { os.exit(3i32) }
    let (_, neg_tau) = meta.random_pool(est[..], va[..], 3usize, 0.0f64 - 0.1f64)
    if neg_tau != meta.Invalid { os.exit(3i32) }
    let (_, one_study) = meta.tau_squared_dl(q, va[..1usize], 1usize)
    if one_study != meta.Invalid { os.exit(3i32) }
    if meta.i_squared(0.0f64, 2usize) != 0.0f64 { os.exit(3i32) }

    // 4: subgroup Q splits additively; the dose meta-regression matches its
    // normal equations.
    let (qb, qb_error) = meta.q_statistic(est[1usize..3usize], va[1usize..3usize], 2usize, 0.35f64)
    if qb_error != ok || !near(qb, 2.5f64, 0.0001f64) { os.exit(4i32) }
    var subq: [1]f64 = zero
    subq[0usize] = qb
    let (between, between_error) = meta.q_between(q, subq[..], 1usize)
    if between_error != ok || !near(between, 0.4592f64, 0.0001f64) { os.exit(4i32) }
    var my: [4]f64 = zero
    my[0usize] = 0.3f64
    my[1usize] = 0.5f64
    my[2usize] = 0.7f64
    my[3usize] = 0.9f64
    var mv: [4]f64 = zero
    mv[0usize] = 0.04f64
    mv[1usize] = 0.09f64
    mv[2usize] = 0.01f64
    mv[3usize] = 0.04f64
    var mx: [8]f64 = zero
    mx[0usize] = 1.0f64
    mx[1usize] = 0.0f64
    mx[2usize] = 1.0f64
    mx[3usize] = 0.0f64
    mx[4usize] = 1.0f64
    mx[5usize] = 1.0f64
    mx[6usize] = 1.0f64
    mx[7usize] = 1.0f64
    var mbeta: [2]f64 = zero
    var mcov: [4]f64 = zero
    var mscratch: [24]f64 = zero
    if meta.meta_regression(my[..], mv[..], mx[..], 4usize, 2usize, 0.0f64, mbeta[..], mcov[..], mscratch[..]) != ok { os.exit(4i32) }
    if !near(mbeta[0usize], 0.36154f64, 0.00001f64) || !near(mbeta[1usize], 0.37846f64, 0.00001f64) { os.exit(4i32) }
    if !near(mcov[0usize], 0.027692f64, 0.000001f64) || !near(mcov[1usize], 0.0f64 - 0.027692f64, 0.000001f64) { os.exit(4i32) }
    if !near(mcov[3usize], 0.035692f64, 0.000001f64) { os.exit(4i32) }
    var short_beta: [1]f64 = zero
    if meta.meta_regression(my[..], mv[..], mx[..], 4usize, 2usize, 0.0f64, short_beta[..], mcov[..], mscratch[..]) != meta.TooSmall { os.exit(4i32) }
    if meta.meta_regression(my[..], mv[..], mx[..], 4usize, 2usize, 0.0f64 - 1.0f64, mbeta[..], mcov[..], mscratch[..]) != meta.Invalid { os.exit(4i32) }

    try io.print("algo stat meta ok\n")
    ret ok
}
