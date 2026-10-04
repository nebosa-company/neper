// `e.algo.timeseries` ARIMA and inventory coverage: differencing inverts a
// trend, an AR(1) fit and an ARMA(1,1) fit recover their parameters from
// simulations, the CSS prefers the truth and forecasts recurse by hand, while
// EOQ matches its closed form with a minimum at the optimum and the
// newsvendor picks the fractile quantity -- with every refusal. Each check
// exits with its own code.

use e.algo.rand
use e.algo.timeseries
use e.io
use e.math
use e.mem
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: differences of a ramp are constant then zero; d = 0 copies.
    var ramp: [10]f64 = zero
    var i = 0usize
    while i < 10usize {
        ramp[i] = f64(i)
        i += 1usize
    }
    var diffed: [10]f64 = zero
    let (n1, d1_error) = timeseries.arima_difference(ramp[..], 1usize, diffed[..])
    if d1_error != ok || n1 != 9usize { os.exit(1i32) }
    i = 0usize
    while i < 9usize {
        if !near(diffed[i], 1.0f64, 0.000000001f64) { os.exit(1i32) }
        i += 1usize
    }
    let (n2, d2_error) = timeseries.arima_difference(diffed[..9usize], 1usize, diffed[..])
    if d2_error != ok || n2 != 8usize { os.exit(1i32) }
    i = 0usize
    while i < 8usize {
        if !near(diffed[i], 0.0f64, 0.000000001f64) { os.exit(1i32) }
        i += 1usize
    }
    let (n0, d0_error) = timeseries.arima_difference(ramp[..], 0usize, diffed[..])
    if d0_error != ok || n0 != 10usize || !near(diffed[9usize], 9.0f64, 0.000000001f64) { os.exit(1i32) }
    let (_, deep_error) = timeseries.arima_difference(ramp[..], 11usize, diffed[..])
    if deep_error != timeseries.Invalid { os.exit(1i32) }
    let (_, room_error) = timeseries.arima_difference(ramp[..], 1usize, diffed[..9usize])
    if room_error != timeseries.TooSmall { os.exit(1i32) }

    // 2: AR(1) with phi 0.7 and intercept 1 recovers from 2000 observations.
    var r = rand.pcg64(23u64, 5u64)
    let (sim, sim_error) = mem.alloc[f64](a, 2200usize)
    if sim_error != ok { ret sim_error }
    sim[0usize] = 0.0f64
    i = 1usize
    while i < 2200usize {
        var u = 0.0f64
        var v = 0.0f64
        var s2 = 2.0f64
        while s2 >= 1.0f64 || s2 == 0.0f64 {
            u = 2.0f64 * rand.pcg64_f64(&r) - 1.0f64
            v = 2.0f64 * rand.pcg64_f64(&r) - 1.0f64
            s2 = u * u + v * v
        }
        sim[i] = 1.0f64 + 0.7f64 * sim[i - 1usize] + u * math.sqrt[f64](0.0f64 - 2.0f64 * math.log[f64](s2) / s2) * 0.5f64
        i += 1usize
    }
    var arcoefs: [1]f64 = zero
    var aricept: [1]f64 = zero
    var scratch: [128]f64 = zero
    if timeseries.ar_fit(sim[200usize..2200usize], 1usize, arcoefs[..], aricept[..], scratch[..]) != ok { os.exit(2i32) }
    if !near(arcoefs[0usize], 0.7f64, 0.05f64) || !near(aricept[0usize], 1.0f64, 0.2f64) { os.exit(2i32) }
    if timeseries.ar_fit(sim[..1usize], 1usize, arcoefs[..], aricept[..], scratch[..]) != timeseries.Invalid { os.exit(2i32) }

    // 3: the ARMA(1,1) CSS prefers the truth and the fit recovers it.
    let (arma, arma_error) = mem.alloc[f64](a, 2200usize)
    if arma_error != ok { ret arma_error }
    arma[0usize] = 0.0f64
    var eprev = 0.0f64
    i = 1usize
    while i < 2200usize {
        var u = 0.0f64
        var v = 0.0f64
        var s2 = 2.0f64
        while s2 >= 1.0f64 || s2 == 0.0f64 {
            u = 2.0f64 * rand.pcg64_f64(&r) - 1.0f64
            v = 2.0f64 * rand.pcg64_f64(&r) - 1.0f64
            s2 = u * u + v * v
        }
        let shock = u * math.sqrt[f64](0.0f64 - 2.0f64 * math.log[f64](s2) / s2) * 0.5f64
        arma[i] = 1.0f64 + 0.6f64 * arma[i - 1usize] + shock + 0.3f64 * eprev
        eprev = shock
        i += 1usize
    }
    let (resid, resid_error) = mem.alloc[f64](a, 2000usize)
    if resid_error != ok { ret resid_error }
    var true_ar: [1]f64 = zero
    true_ar[0usize] = 0.6f64
    var true_ma: [1]f64 = zero
    true_ma[0usize] = 0.3f64
    let (css_true, css_true_error) = timeseries.arma_css(arma[200usize..2200usize], true_ar[..], true_ma[..], 1.0f64, resid[..])
    if css_true_error != ok { os.exit(3i32) }
    var wrong_ar: [1]f64 = zero
    wrong_ar[0usize] = 0.1f64
    let (css_wrong, css_wrong_error) = timeseries.arma_css(arma[200usize..2200usize], wrong_ar[..], true_ma[..], 1.0f64, resid[..])
    if css_wrong_error != ok || css_true >= css_wrong { os.exit(3i32) }
    var params: [3]f64 = zero
    params[0usize] = 0.8f64
    params[1usize] = 0.4f64
    params[2usize] = 0.1f64
    let (fitscratch, fitscratch_error) = mem.alloc[f64](a, 2048usize)
    if fitscratch_error != ok { ret fitscratch_error }
    let (css_fit, fit_error) = timeseries.arma_fit(arma[200usize..2200usize], 1usize, 1usize, params[..], 0.3f64, 1.0e-9f64, 5000u32, fitscratch[..])
    if fit_error != ok || css_fit > css_true + 5.0f64 { os.exit(3i32) }
    if !near(params[0usize], 1.0f64, 0.25f64) || !near(params[1usize], 0.6f64, 0.1f64) || !near(params[2usize], 0.3f64, 0.15f64) { os.exit(3i32) }
    var bad_params: [2]f64 = zero
    let (_, bad_error) = timeseries.arma_fit(arma[200usize..2200usize], 1usize, 1usize, bad_params[..], 0.3f64, 1.0e-9f64, 10u32, fitscratch[..])
    if bad_error != timeseries.Invalid { os.exit(3i32) }
    let (_, css_room) = timeseries.arma_css(arma[200usize..2200usize], true_ar[..], true_ma[..], 1.0f64, resid[..10usize])
    if css_room != timeseries.TooSmall { os.exit(3i32) }

    // 4: forecasts recurse by hand -- AR(1) then a pure MA(1) tail of zeros.
    var past: [1]f64 = zero
    past[0usize] = 6.0f64
    var spare: [1]f64 = zero
    var no_resid = spare[..0usize]
    var empty_ma = spare[..0usize]
    var phi: [1]f64 = zero
    phi[0usize] = 0.5f64
    var ahead: [3]f64 = zero
    if timeseries.arma_forecast(phi[..], empty_ma[..], 2.0f64, past[..], no_resid[..], 3usize, ahead[..]) != ok { os.exit(4i32) }
    if !near(ahead[0usize], 5.0f64, 0.000000001f64) || !near(ahead[1usize], 4.5f64, 0.000000001f64) { os.exit(4i32) }
    if !near(ahead[2usize], 4.25f64, 0.000000001f64) { os.exit(4i32) }
    var theta: [1]f64 = zero
    theta[0usize] = 0.4f64
    var shock_past: [1]f64 = zero
    shock_past[0usize] = 2.0f64
    var no_past = spare[..0usize]
    var ma_ahead: [3]f64 = zero
    if timeseries.arma_forecast(empty_ma[..], theta[..], 1.0f64, no_past[..], shock_past[..], 3usize, ma_ahead[..]) != ok { os.exit(4i32) }
    if !near(ma_ahead[0usize], 1.8f64, 0.000000001f64) || !near(ma_ahead[1usize], 1.0f64, 0.000000001f64) { os.exit(4i32) }
    if !near(ma_ahead[2usize], 1.0f64, 0.000000001f64) { os.exit(4i32) }
    if timeseries.arma_forecast(phi[..], empty_ma[..], 2.0f64, past[..], no_resid[..], 3usize, ahead[..2usize]) != timeseries.TooSmall { os.exit(4i32) }

    // 5: EOQ matches sqrt(2DS/H) with a minimum there; the newsvendor takes
    // the first demand past the critical ratio.
    let (star, star_error) = timeseries.eoq(1200.0f64, 50.0f64, 2.0f64)
    if star_error != ok || !near(star, 244.94897427831782f64, 0.000001f64) { os.exit(5i32) }
    let (cost_star, cost_star_error) = timeseries.eoq_total(1200.0f64, 50.0f64, 2.0f64, star)
    let (cost_off, cost_off_error) = timeseries.eoq_total(1200.0f64, 50.0f64, 2.0f64, 100.0f64)
    if cost_star_error != ok || cost_off_error != ok || cost_star >= cost_off { os.exit(5i32) }
    if !near(cost_star, 489.89794855663565f64, 0.000001f64) { os.exit(5i32) }
    let (_, eoq_bad) = timeseries.eoq(1200.0f64, 0.0f64 - 50.0f64, 2.0f64)
    if eoq_bad != timeseries.Invalid { os.exit(5i32) }
    let (ratio, ratio_error) = timeseries.newsvendor_ratio(3.0f64, 2.0f64)
    if ratio_error != ok || !near(ratio, 0.6f64, 0.000000001f64) { os.exit(5i32) }
    var levels: [5]f64 = zero
    levels[0usize] = 0.0f64
    levels[1usize] = 1.0f64
    levels[2usize] = 2.0f64
    levels[3usize] = 3.0f64
    levels[4usize] = 4.0f64
    var chances: [5]f64 = zero
    chances[0usize] = 0.1f64
    chances[1usize] = 0.2f64
    chances[2usize] = 0.3f64
    chances[3usize] = 0.25f64
    chances[4usize] = 0.15f64
    let (order, order_error) = timeseries.newsvendor_discrete(levels[..], chances[..], ratio)
    if order_error != ok || !near(order, 2.0f64, 0.000000001f64) { os.exit(5i32) }
    let (_, ratio_bad) = timeseries.newsvendor_ratio(3.0f64, 0.0f64 - 2.0f64)
    if ratio_bad != timeseries.Invalid { os.exit(5i32) }
    let (_, discrete_bad) = timeseries.newsvendor_discrete(levels[..4usize], chances[..], ratio)
    if discrete_bad != timeseries.Invalid { os.exit(5i32) }
    let (_, ratio_range) = timeseries.newsvendor_discrete(levels[..], chances[..], 1.5f64)
    if ratio_range != timeseries.Invalid { os.exit(5i32) }

    try io.print("algo timeseries arima ok\n")
    ret ok
}
