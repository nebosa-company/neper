// `e.algo.timeseries`: Holt-Winters continues a linear seasonal series,
// STL recovers the season and trend of a synthetic one, CUSUM, Page-Hinkley
// and ADWIN flag a mean shift where it happens and stay quiet before it,
// GARCH likelihood, fit and forecasts behave on a simulated series, and
// the Hawkes process simulates near its expected rate with a likelihood
// that prefers the true parameters. Each check exits with its own code.

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
    // 1: Holt-Winters on 10 + 0.5 t + season (2, -1, -2, 1).
    var series: [40]f64 = zero
    var i = 0usize
    while i < 40usize {
        var s = 2.0f64
        if i % 4usize == 1usize { s = 0.0f64 - 1.0f64 } else if i % 4usize == 2usize { s = 0.0f64 - 2.0f64 } else if i % 4usize == 3usize { s = 1.0f64 }
        series[i] = 10.0f64 + 0.5f64 * f64(i) + s
        i += 1usize
    }
    var forecast: [4]f64 = zero
    var season: [4]f64 = zero
    let (level, trend, hw_error) = timeseries.holt_winters(series[..], 4usize, 0.5f64, 0.3f64, 0.4f64, 4usize, forecast[..], season[..])
    if hw_error != ok || !near(level, 29.48657743364877f64, 0.000001f64) || !near(trend, 0.4939667227675335f64, 0.000001f64) { os.exit(1i32) }
    if !near(forecast[0usize], 32.0f64, 0.05f64) || !near(forecast[1usize], 29.5f64, 0.1f64) || !near(forecast[2usize], 29.0f64, 0.1f64) || !near(forecast[3usize], 32.5f64, 0.05f64) { os.exit(1i32) }
    let (_, _, hw_invalid) = timeseries.holt_winters(series[..6usize], 4usize, 0.5f64, 0.3f64, 0.4f64, 4usize, forecast[..], season[..])
    if hw_invalid != timeseries.Invalid { os.exit(1i32) }
    let (_, _, hw_room) = timeseries.holt_winters(series[..], 4usize, 0.5f64, 0.3f64, 0.4f64, 4usize, forecast[..2usize], season[..])
    if hw_room != timeseries.TooSmall { os.exit(1i32) }

    // 2: STL on the same series recovers the season within a tenth and the trend slope.
    var trend_out: [40]f64 = zero
    var seasonal: [40]f64 = zero
    var remainder: [40]f64 = zero
    var scratch: [64]f64 = zero
    if timeseries.stl(series[..], 4usize, 9usize, trend_out[..], seasonal[..], remainder[..], scratch[..]) != ok { os.exit(2i32) }
    if !near(seasonal[0usize], 2.0f64, 0.15f64) || !near(seasonal[1usize], 0.0f64 - 1.0f64, 0.15f64) || !near(seasonal[2usize], 0.0f64 - 2.0f64, 0.15f64) || !near(seasonal[3usize], 1.0f64, 0.15f64) { os.exit(2i32) }
    if !near(trend_out[20usize] - trend_out[10usize], 5.0f64, 0.3f64) { os.exit(2i32) }
    var worst = 0.0f64
    i = 4usize
    while i < 36usize {
        if remainder[i] > worst { worst = remainder[i] }
        if 0.0f64 - remainder[i] > worst { worst = 0.0f64 - remainder[i] }
        i += 1usize
    }
    if worst > 0.3f64 { os.exit(2i32) }
    if timeseries.stl(series[..], 4usize, 2usize, trend_out[..], seasonal[..], remainder[..], scratch[..]) != timeseries.Invalid { os.exit(2i32) }
    if timeseries.loess(series[..], 5usize, trend_out[..10usize]) != timeseries.TooSmall { os.exit(2i32) }

    // 3: change detection on a stream of zeros that jumps to 3 at step 200.
    var r = rand.pcg64(3u64, 9u64)
    var c = timeseries.cusum(0.0f64, 0.5f64, 5.0f64)
    var p = timeseries.page_hinkley(0.5f64, 10.0f64)
    var ring: [128]f64 = zero
    let (w0, adwin_error) = timeseries.adwin(ring[..], 0.01f64)
    if adwin_error != ok { os.exit(3i32) }
    var w = w0
    var cusum_at = 0usize
    var ph_at = 0usize
    var adwin_at = 0usize
    i = 0usize
    while i < 400usize {
        var value = rand.pcg64_f64(&r) - 0.5f64
        if i >= 200usize { value += 3.0f64 }
        if timeseries.cusum_step(&c, value) && cusum_at == 0usize { cusum_at = i }
        if timeseries.page_hinkley_step(&p, value) && ph_at == 0usize { ph_at = i }
        if timeseries.adwin_step(&w, value) && adwin_at == 0usize { adwin_at = i }
        i += 1usize
    }
    if cusum_at < 200usize || cusum_at > 205usize || ph_at < 200usize || ph_at > 210usize || adwin_at < 200usize || adwin_at > 230usize { os.exit(3i32) }
    if !near(timeseries.adwin_mean(&w), 3.0f64, 0.2f64) || w.count > 128usize { os.exit(3i32) }
    let (_, adwin_invalid) = timeseries.adwin(ring[..], 1.5f64)
    if adwin_invalid != timeseries.Invalid { os.exit(3i32) }

    // 4: GARCH(1,1) with omega 0.1, alpha 0.2, beta 0.7 over a simulated series.
    let (returns, returns_error) = mem.alloc[f64](a, 2000usize)
    if returns_error != ok { ret returns_error }
    var variance = 1.0f64
    i = 0usize
    while i < 2000usize {
        // A standard normal by the polar method.
        var u = 0.0f64
        var q = 0.0f64
        var s2 = 2.0f64
        while s2 >= 1.0f64 || s2 == 0.0f64 {
            u = 2.0f64 * rand.pcg64_f64(&r) - 1.0f64
            q = 2.0f64 * rand.pcg64_f64(&r) - 1.0f64
            s2 = u * u + q * q
        }
        let z = u * math.sqrt[f64](0.0f64 - 2.0f64 * math.log[f64](s2) / s2)
        returns[i] = z * math.sqrt[f64](variance)
        variance = 0.1f64 + 0.2f64 * returns[i] * returns[i] + 0.7f64 * variance
        i += 1usize
    }
    let truth = timeseries.garch_log_likelihood(0.1f64, 0.2f64, 0.7f64, returns)
    let wrong = timeseries.garch_log_likelihood(0.5f64, 0.05f64, 0.3f64, returns)
    if truth <= wrong { os.exit(4i32) }
    var params: [3]f64 = zero
    params[0usize] = 0.3f64
    params[1usize] = 0.1f64
    params[2usize] = 0.5f64
    let (fitted, fit_error) = timeseries.garch_fit(returns, params[..], 2000u32, scratch[..])
    if fit_error != ok || fitted < truth - 3.0f64 { os.exit(4i32) }
    if !near(params[0usize], 0.1f64, 0.08f64) || !near(params[1usize], 0.2f64, 0.08f64) || !near(params[2usize], 0.7f64, 0.1f64) { os.exit(4i32) }
    var ahead: [3]f64 = zero
    if timeseries.garch_forecast(0.1f64, 0.2f64, 0.7f64, 2.0f64, 1.5f64, 3usize, ahead[..]) != ok { os.exit(4i32) }
    // 0.1 + 0.2 * 4 + 0.7 * 1.5 = 1.95; then 0.1 + 0.9 * 1.95 = 1.855; then 1.7695.
    if !near(ahead[0usize], 1.95f64, 0.000000001f64) || !near(ahead[1usize], 1.855f64, 0.000000001f64) || !near(ahead[2usize], 1.7695f64, 0.000000001f64) { os.exit(4i32) }
    if timeseries.garch_forecast(0.1f64, 0.2f64, 0.7f64, 2.0f64, 1.5f64, 3usize, ahead[..2usize]) != timeseries.TooSmall { os.exit(4i32) }

    // 5: Hawkes with mu 1, alpha 0.5, beta 1 (mean rate 2) over 500 units.
    let (events, events_error) = mem.alloc[f64](a, 3000usize)
    if events_error != ok { ret events_error }
    let (count, simulate_error) = timeseries.hawkes_simulate(1.0f64, 0.5f64, 1.0f64, 500.0f64, &r, events)
    if simulate_error != ok || count < 800usize || count > 1200usize { os.exit(5i32) }
    i = 1usize
    while i < count {
        if events[i] <= events[i - 1usize] || events[i] >= 500.0f64 { os.exit(5i32) }
        i += 1usize
    }
    let ll_true = timeseries.hawkes_log_likelihood(1.0f64, 0.5f64, 1.0f64, events[..count], 500.0f64)
    let ll_poisson = timeseries.hawkes_log_likelihood(2.0f64, 0.0f64, 1.0f64, events[..count], 500.0f64)
    let ll_wrong = timeseries.hawkes_log_likelihood(0.5f64, 0.9f64, 1.0f64, events[..count], 500.0f64)
    if ll_true <= ll_poisson || ll_true <= ll_wrong { os.exit(5i32) }
    if !near(timeseries.hawkes_intensity(1.0f64, 0.5f64, 1.0f64, events[..0usize], 1.0f64), 1.0f64, 0.000000001f64) { os.exit(5i32) }
    let (_, unstable) = timeseries.hawkes_simulate(1.0f64, 1.5f64, 1.0f64, 10.0f64, &r, events)
    if unstable != timeseries.Invalid { os.exit(5i32) }
    let (_, too_many) = timeseries.hawkes_simulate(1.0f64, 0.5f64, 1.0f64, 500.0f64, &r, events[..10usize])
    if too_many != timeseries.TooSmall { os.exit(5i32) }

    try io.print("algo timeseries ok\n")
    ret ok
}
