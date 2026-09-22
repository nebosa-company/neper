// `e.algo.stat`'s batch statistics against numpy, scipy and scikit-learn on
// LCG-generated samples of twenty: the compensated mean, every Hyndman-Fan
// quantile, sample skewness and kurtosis, entropy, the covariance matrix and its
// Ledoit-Wolf shrinkage, Pearson, Spearman and Kendall with ties, kernel density
// with both bandwidth rules, a PCG-driven bootstrap, a jackknife of the
// variance, Wilson and Clopper-Pearson intervals, value at risk and expected
// shortfall, and moment and maximum-likelihood fits. Each check exits with its
// own code.

use e.algo.rand
use e.algo.stat
use e.io
use e.mem
use e.os

type Lcg = struct { state: u64 }
type Unit = struct { calls: usize }

fn draw(g: *Lcg) -> u64 {
    g.state = g.state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret g.state >> 33u32
}

fn uniform(g: *Lcg) -> f64 { ret f64(draw(g)) / 2147483648.0f64 }

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn plain_mean(c: *Unit, xs: []const f64) -> f64 {
    c.calls += 1usize
    var total = 0.0f64
    var i = 0usize
    while i < xs.len {
        total += xs[i]
        i += 1usize
    }
    ret total / f64(xs.len)
}

fn population_variance(c: *Unit, xs: []const f64) -> f64 {
    let m = plain_mean(c, xs)
    var total = 0.0f64
    var i = 0usize
    while i < xs.len {
        total += (xs[i] - m) * (xs[i] - m)
        i += 1usize
    }
    ret total / f64(xs.len)
}

fn sort_values(values: []f64) {
    var i = 1usize
    while i < values.len {
        var j = i
        while j > 0usize && values[j] < values[j - 1usize] {
            let swap = values[j]
            values[j] = values[j - 1usize]
            values[j - 1usize] = swap
            j -= 1usize
        }
        i += 1usize
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    var g = Lcg { state: 42u64 }
    var x: [20]f64 = zero
    var y: [20]f64 = zero
    var tx: [20]f64 = zero
    var ty: [20]f64 = zero
    var pos: [20]f64 = zero
    var unit: [20]f64 = zero
    var counts: [16]u64 = zero
    var mat: [90]f64 = zero
    var i = 0usize
    while i < 20usize {
        x[i] = uniform(&g) * 10.0f64 - 3.0f64
        i += 1usize
    }
    i = 0usize
    while i < 20usize {
        y[i] = uniform(&g) * 10.0f64 - 3.0f64
        i += 1usize
    }
    i = 0usize
    while i < 20usize {
        tx[i] = f64(draw(&g) >> 28u32)
        i += 1usize
    }
    i = 0usize
    while i < 20usize {
        ty[i] = f64(draw(&g) >> 28u32)
        i += 1usize
    }
    i = 0usize
    while i < 20usize {
        pos[i] = uniform(&g) * 10.0f64 + 0.5f64
        i += 1usize
    }
    i = 0usize
    while i < 20usize {
        unit[i] = (f64(draw(&g)) + 1.0f64) / 2147483650.0f64
        i += 1usize
    }
    i = 0usize
    while i < 64usize {
        counts[usize(draw(&g) & 15u64)] += 1u64
        i += 1usize
    }
    i = 0usize
    while i < 30usize {
        let ca = uniform(&g) * 4.0f64 - 1.0f64
        let cb = uniform(&g)
        let cc = uniform(&g) * 0.5f64
        mat[i * 3usize] = ca
        mat[i * 3usize + 1usize] = ca * 2.0f64 + cb
        mat[i * 3usize + 2usize] = cc
        i += 1usize
    }
    if x[0usize] != 2.682303262874484f64 || y[19usize] != 3.4861243264749646f64 || tx[1usize] != 7.0f64 || counts[1usize] != 8u64 { os.exit(1i32) }
    let eps = 0.000000001f64

    // 1: compensated mean.
    let (mc, has_mc) = stat.mean_compensated(x[..])
    if !has_mc || !near(mc, 1.2602101410739124f64, eps) { os.exit(1i32) }
    let (_, has_empty) = stat.mean_compensated(x[..0usize])
    if has_empty { os.exit(1i32) }

    // 2: quantiles, every method at p = 0.3 and the discrete corners.
    var xs: [20]f64 = zero
    i = 0usize
    while i < 20usize {
        xs[i] = x[i]
        i += 1usize
    }
    sort_values(xs[..])
    let (q1, _) = stat.quantile(xs[..], 0.3f64, .R1)
    let (q2, _) = stat.quantile(xs[..], 0.3f64, .R2)
    let (q3, _) = stat.quantile(xs[..], 0.3f64, .R3)
    let (q4, _) = stat.quantile(xs[..], 0.3f64, .R4)
    let (q5, _) = stat.quantile(xs[..], 0.3f64, .R5)
    let (q6, _) = stat.quantile(xs[..], 0.3f64, .R6)
    let (q7, _) = stat.quantile(xs[..], 0.3f64, .R7)
    let (q8, _) = stat.quantile(xs[..], 0.3f64, .R8)
    let (q9, _) = stat.quantile(xs[..], 0.3f64, .R9)
    let (qn, _) = stat.quantile(xs[..], 0.3f64, .Nearest)
    if q1 != 0.0f64 - 0.7453657146543264f64 || q2 != 0.0f64 - 0.2400964703410864f64 || q3 != 0.0f64 - 0.7453657146543264f64 { os.exit(2i32) }
    if q4 != 0.0f64 - 0.7453657146543264f64 || q5 != 0.0f64 - 0.2400964703410864f64 || q6 != 0.0f64 - 0.4422041680663826f64 { os.exit(2i32) }
    if q7 != 0.0f64 - 0.0379887726157902f64 || q8 != 0.0f64 - 0.3074657029161848f64 || q9 != 0.0f64 - 0.2906233947724102f64 || qn != 0.26517277397215366f64 { os.exit(2i32) }
    // n p integral: R1 keeps the previous, R2 averages, R3 wants an odd index.
    let (e1, _) = stat.quantile(xs[..], 0.25f64, .R1)
    let (e2, _) = stat.quantile(xs[..], 0.25f64, .R2)
    let (e3, _) = stat.quantile(xs[..], 0.25f64, .R3)
    if e1 != 0.0f64 - 1.4754495788365602f64 || e2 != 0.0f64 - 1.1104076467454433f64 || e3 != 0.0f64 - 1.4754495788365602f64 { os.exit(2i32) }
    let (o3, _) = stat.quantile(xs[..], 0.275f64, .R3)
    let (v3, _) = stat.quantile(xs[..], 0.325f64, .R3)
    let (v4, _) = stat.quantile(xs[..], 0.325f64, .R4)
    if o3 != 0.0f64 - 0.7453657146543264f64 || v3 != 0.0f64 - 0.7453657146543264f64 || v4 != 0.0f64 - 0.2400964703410864f64 { os.exit(2i32) }
    let (lo4, _) = stat.quantile(xs[..], 0.0f64, .R4)
    let (hi9, _) = stat.quantile(xs[..], 1.0f64, .R9)
    let (low7, _) = stat.quantile(xs[..], 0.02f64, .R7)
    let (low6, _) = stat.quantile(xs[..], 0.02f64, .R6)
    if lo4 != 0.0f64 - 2.7823919681832194f64 || hi9 != 6.2047028336673975f64 || low7 != 0.0f64 - 2.770845620520413f64 || low6 != 0.0f64 - 2.7823919681832194f64 { os.exit(2i32) }
    let (_, has_q) = stat.quantile(xs[..], 1.5f64, .R7)
    if has_q { os.exit(2i32) }

    // 3: shape and entropy.
    let (sk, has_sk) = stat.skewness(x[..])
    let (ku, has_ku) = stat.kurtosis(x[..])
    if !has_sk || !has_ku || !near(sk, 0.0f64 - 0.0008089872165334089f64, eps) || !near(ku, 0.0f64 - 1.0171593858127443f64, eps) { os.exit(3i32) }
    let (_, has_sk3) = stat.skewness(x[..2usize])
    if has_sk3 { os.exit(3i32) }
    let (h, has_h) = stat.entropy(pos[..])
    let (hb, has_hb) = stat.entropy_counts(counts[..])
    if !has_h || !has_hb || !near(h, 2.872435508992349f64, eps) || !near(hb, 3.8063038618967613f64, eps) { os.exit(3i32) }
    let (_, has_neg) = stat.entropy(x[..])
    if has_neg { os.exit(3i32) }

    // 4: covariance and its shrinkage.
    var cov: [9]f64 = zero
    if stat.covariance_matrix(mat[..], 3usize, cov[..]) != ok { os.exit(4i32) }
    if !near(cov[0usize], 1.3477394883260432f64, eps) || !near(cov[1usize], 2.735201635033151f64, eps) || !near(cov[5usize], 0.0054841293205091166f64, eps) || !near(cov[8usize], 0.02306660147259235f64, eps) { os.exit(4i32) }
    if cov[3usize] != cov[1usize] || cov[6usize] != cov[2usize] { os.exit(4i32) }
    if stat.covariance_matrix(mat[..], 3usize, cov[..8usize]) != stat.TooSmall || stat.covariance_matrix(mat[..], 7usize, cov[..]) != stat.Invalid { os.exit(4i32) }
    let (shrinkage, shrink_error) = stat.covariance_shrink(mat[..], 3usize, cov[..])
    if shrink_error != ok || !near(shrinkage, 0.059869452454157944f64, eps) { os.exit(4i32) }
    if !near(cov[0usize], 1.3604759694012722f64, eps) || !near(cov[1usize], 2.4857317237655985f64, eps) || !near(cov[8usize], 0.15662270451249524f64, eps) { os.exit(4i32) }

    // 5: correlations and ranks.
    let (pr, has_pr) = stat.correlation_pearson(x[..], y[..])
    if !has_pr || !near(pr, 0.0f64 - 0.3479894043066584f64, eps) { os.exit(5i32) }
    var scratch: [40]f64 = zero
    var order: [20]usize = zero
    let (sp, sp_error) = stat.correlation_spearman(tx[..], ty[..], scratch[..], order[..])
    if sp_error != ok || !near(sp, 0.13174117931260815f64, eps) { os.exit(5i32) }
    let (_, sp_room) = stat.correlation_spearman(tx[..], ty[..], scratch[..39usize], order[..])
    if sp_room != stat.TooSmall { os.exit(5i32) }
    let (kt, has_kt) = stat.correlation_kendall(tx[..], ty[..])
    let (kp, has_kp) = stat.correlation_kendall(x[..], y[..])
    if !has_kt || !has_kp || !near(kt, 0.0890211634396684f64, eps) || !near(kp, 0.0f64 - 0.28421052631578947f64, eps) { os.exit(5i32) }
    if stat.rank(tx[..], scratch[..], order[..]) != ok || scratch[1usize] != 19.5f64 || scratch[7usize] != 2.5f64 || scratch[16usize] != 8.5f64 { os.exit(5i32) }
    var flat: [20]f64 = zero
    let (_, has_flat) = stat.correlation_kendall(tx[..], flat[..])
    if has_flat { os.exit(5i32) }

    // 6: kernel density.
    let (bw_scott, has_scott) = stat.kde_bandwidth(x[..], .Scott)
    let (bw_silverman, has_silverman) = stat.kde_bandwidth(x[..], .Silverman)
    if !has_scott || !has_silverman || !near(bw_scott, 1.5306408096617972f64, eps) || !near(bw_silverman, 1.6212912376760327f64, eps) { os.exit(6i32) }
    var points: [3]f64 = zero
    points[0usize] = 0.0f64 - 2.0f64
    points[1usize] = 0.5f64
    points[2usize] = 4.0f64
    var density: [3]f64 = zero
    if stat.kde(x[..], bw_scott, points[..], density[..]) != ok { os.exit(6i32) }
    if !near(density[0usize], 0.08275042700009413f64, eps) || !near(density[1usize], 0.1092437699387216f64, eps) || !near(density[2usize], 0.09269160467504163f64, eps) { os.exit(6i32) }
    if stat.kde(x[..], 0.0f64, points[..], density[..]) != stat.Invalid || stat.kde(x[..], 1.0f64, points[..], density[..2usize]) != stat.TooSmall { os.exit(6i32) }

    // 7: bootstrap and jackknife.
    var r = rand.pcg64(7u64, 11u64)
    var c = Unit { calls: 0usize }
    var sample: [20]f64 = zero
    var boot: [200]f64 = zero
    let (interval, boot_error) = stat.bootstrap[Unit](&r, x[..], &c, plain_mean, 200usize, 0.9f64, sample[..], boot[..])
    if boot_error != ok || c.calls != 200usize || !near(interval.low, 0.18936540684662764f64, eps) || !near(interval.high, 2.1912309304694646f64, eps) { os.exit(7i32) }
    let (_, boot_room) = stat.bootstrap[Unit](&r, x[..], &c, plain_mean, 200usize, 0.9f64, sample[..], boot[..199usize])
    if boot_room != stat.TooSmall { os.exit(7i32) }
    let (jk, jk_error) = stat.jackknife[Unit](x[..], &c, population_variance, scratch[..19usize])
    if jk_error != ok || !near(jk.estimate, 7.377040708314266f64, eps) || !near(jk.bias, 0.0f64 - 0.38826530043757934f64, eps) || !near(jk.standard_error, 1.7218832553052106f64, eps) { os.exit(7i32) }
    let (_, jk_room) = stat.jackknife[Unit](x[..], &c, population_variance, scratch[..18usize])
    if jk_room != stat.TooSmall { os.exit(7i32) }

    // 8: proportion intervals.
    let (wi, wi_error) = stat.interval_wilson(7u64, 20u64, 0.95f64)
    if wi_error != ok || !near(wi.low, 0.18119182410108206f64, eps) || !near(wi.high, 0.5671457233147638f64, eps) { os.exit(8i32) }
    let (cp, cp_error) = stat.interval_clopper_pearson(7u64, 20u64, 0.95f64)
    if cp_error != ok || !near(cp.low, 0.1539092047845412f64, eps) || !near(cp.high, 0.5921885345328282f64, eps) { os.exit(8i32) }
    let (cp0, _) = stat.interval_clopper_pearson(0u64, 20u64, 0.95f64)
    let (cpn, _) = stat.interval_clopper_pearson(20u64, 20u64, 0.95f64)
    if cp0.low != 0.0f64 || !near(cp0.high, 0.16843347098308528f64, eps) || cpn.high != 1.0f64 || !near(cpn.low, 0.8315665290169147f64, eps) { os.exit(8i32) }
    let (_, cp_bad) = stat.interval_clopper_pearson(21u64, 20u64, 0.95f64)
    let (_, wi_bad) = stat.interval_wilson(1u64, 20u64, 1.0f64)
    if cp_bad != stat.Invalid || wi_bad != stat.Invalid { os.exit(8i32) }

    // 9: value at risk and expected shortfall.
    let (var95, has_var) = stat.value_at_risk(xs[..], 0.95f64)
    let (es90, has_es) = stat.expected_shortfall(xs[..], 0.9f64)
    if !has_var || !has_es || !near(var95, 5.021122136618943f64, eps) || !near(es90, 5.581765624694526f64, eps) { os.exit(9i32) }
    let (_, has_es1) = stat.expected_shortfall(xs[..], 1.0f64)
    if has_es1 { os.exit(9i32) }

    // 10: fits by moments and by maximum likelihood.
    let (fnorm, fnorm_error) = stat.fit_moments(pos[..], .Normal)
    let (fe, fe_error) = stat.fit_moments(pos[..], .Exponential)
    let (fg, fg_error) = stat.fit_moments(pos[..], .Gamma)
    let (fb, fb_error) = stat.fit_moments(unit[..], .Beta)
    if fnorm_error != ok || !near(fnorm.a, 5.92277382966131f64, eps) || !near(fnorm.b, 2.687292346116803f64, eps) { os.exit(10i32) }
    if fe_error != ok || !near(fe.a, 0.16883980863695827f64, eps) || fe.b != 0.0f64 { os.exit(10i32) }
    if fg_error != ok || !near(fg.a, 4.857585652325051f64, eps) || !near(fg.b, 1.219283457580704f64, eps) { os.exit(10i32) }
    if fb_error != ok || !near(fb.a, 1.3213504215730423f64, eps) || !near(fb.b, 0.9604449159357199f64, eps) { os.exit(10i32) }
    let (_, fb_bad) = stat.fit_moments(pos[..], .Beta)
    if fb_bad != stat.Invalid { os.exit(10i32) }
    let fit_eps = 0.000001f64
    let (mg, mg_error) = stat.fit_mle(pos[..], .Gamma)
    if mg_error != ok || !near(mg.a, 2.982232554588216f64, fit_eps) || !near(mg.b, 1.9860201111912015f64, fit_eps) { os.exit(10i32) }
    let (mb, mb_error) = stat.fit_mle(unit[..], .Beta)
    if mb_error != ok || !near(mb.a, 1.0394318647226635f64, fit_eps) || !near(mb.b, 0.8852499445662869f64, fit_eps) { os.exit(10i32) }
    let (mn, mn_error) = stat.fit_mle(pos[..], .Normal)
    if mn_error != ok || mn.a != fnorm.a || mn.b != fnorm.b { os.exit(10i32) }
    let (_, mb_bad) = stat.fit_mle(pos[..], .Beta)
    if mb_bad != stat.Invalid { os.exit(10i32) }

    // 11: the digamma pair.
    if !near(stat.digamma(0.3f64), 0.0f64 - 3.502524222200133f64, eps) || !near(stat.trigamma(0.3f64), 12.245364546107734f64, eps) || !near(stat.digamma(25.0f64), 3.198742512851974f64, eps) { os.exit(11i32) }

    try io.print("algo stat plan ok\n")
    ret ok
}
