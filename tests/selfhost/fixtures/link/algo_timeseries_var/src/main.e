// `e.algo.timeseries` VAR and structural coverage: a VAR(1) fit recovers its
// coefficients from a simulation, forecasts recurse by hand, the companion
// form matches its layout and steps through `e.math.filter`'s Kalman, and the
// local-level and local-linear-trend filters track a constant and a ramp,
// with the short-window, singular and small-scratch refusals. Each check
// exits with its own code.

use e.algo.rand
use e.algo.timeseries
use e.io
use e.math
use e.math.filter
use e.mem
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    var r = rand.pcg64(11u64, 77u64)

    // 1: VAR(1) with A = [[0.6, 0.15], [0.25, 0.5]], c = [2, -1] recovers
    // from 2000 kept observations with small noise.
    let (sim, sim_error) = mem.alloc[f64](a, 2200usize * 2usize)
    if sim_error != ok { ret sim_error }
    sim[0usize] = 0.0f64
    sim[1usize] = 0.0f64
    var i = 1usize
    while i < 2200usize {
        var e0 = 0.0f64
        var e1 = 0.0f64
        var s2 = 2.0f64
        while s2 >= 1.0f64 || s2 == 0.0f64 {
            e0 = 2.0f64 * rand.pcg64_f64(&r) - 1.0f64
            e1 = 2.0f64 * rand.pcg64_f64(&r) - 1.0f64
            s2 = e0 * e0 + e1 * e1
        }
        let z0 = e0 * math.sqrt[f64](0.0f64 - 2.0f64 * math.log[f64](s2) / s2) * 0.25f64
        let z1 = e1 * math.sqrt[f64](0.0f64 - 2.0f64 * math.log[f64](s2) / s2) * 0.25f64
        sim[i * 2usize] = 2.0f64 + 0.6f64 * sim[(i - 1usize) * 2usize] + 0.15f64 * sim[(i - 1usize) * 2usize + 1usize] + z0
        sim[i * 2usize + 1usize] = 0.0f64 - 1.0f64 + 0.25f64 * sim[(i - 1usize) * 2usize] + 0.5f64 * sim[(i - 1usize) * 2usize + 1usize] + z1
        i += 1usize
    }
    var coefs: [4]f64 = zero
    var icept: [2]f64 = zero
    var scratch: [128]f64 = zero
    if timeseries.var_fit(sim[400usize..4400usize], 2000usize, 2usize, 1usize, coefs[..], icept[..], scratch[..]) != ok { os.exit(1i32) }
    if !near(coefs[0usize], 0.6f64, 0.06f64) || !near(coefs[1usize], 0.15f64, 0.06f64) { os.exit(1i32) }
    if !near(coefs[2usize], 0.25f64, 0.06f64) || !near(coefs[3usize], 0.5f64, 0.06f64) { os.exit(1i32) }
    if !near(icept[0usize], 2.0f64, 0.35f64) || !near(icept[1usize], 0.0f64 - 1.0f64, 0.35f64) { os.exit(1i32) }

    // 2: forecasts recurse by hand: A = diag(0.5), c = [1, 2] from [4, 6].
    var amat: [4]f64 = zero
    amat[0usize] = 0.5f64
    amat[3usize] = 0.5f64
    var avec: [2]f64 = zero
    avec[0usize] = 1.0f64
    avec[1usize] = 2.0f64
    var hist: [2]f64 = zero
    hist[0usize] = 4.0f64
    hist[1usize] = 6.0f64
    var ahead: [6]f64 = zero
    if timeseries.var_forecast(amat[..], avec[..], 2usize, 1usize, hist[..], 3usize, ahead[..]) != ok { os.exit(2i32) }
    if !near(ahead[0usize], 3.0f64, 0.000000001f64) || !near(ahead[1usize], 5.0f64, 0.000000001f64) { os.exit(2i32) }
    if !near(ahead[2usize], 2.5f64, 0.000000001f64) || !near(ahead[3usize], 4.5f64, 0.000000001f64) { os.exit(2i32) }
    if !near(ahead[4usize], 2.25f64, 0.000000001f64) || !near(ahead[5usize], 4.25f64, 0.000000001f64) { os.exit(2i32) }
    if timeseries.var_forecast(amat[..], avec[..], 2usize, 1usize, hist[..], 3usize, ahead[..5usize]) != timeseries.TooSmall { os.exit(2i32) }
    if timeseries.var_forecast(amat[..], avec[..], 2usize, 1usize, hist[..1usize], 1usize, ahead[..2usize]) != timeseries.Invalid { os.exit(2i32) }

    // 3: the companion form of a VAR(1) is its own lag block over identity
    // observation, and its transition steps through the Kalman predict.
    var fmat: [4]f64 = zero
    var hmat: [4]f64 = zero
    if timeseries.var_companion(amat[..], 2usize, 1usize, fmat[..], hmat[..]) != ok { os.exit(3i32) }
    if !near(fmat[0usize], 0.5f64, 0.000000001f64) || !near(fmat[3usize], 0.5f64, 0.000000001f64) { os.exit(3i32) }
    if fmat[1usize] != 0.0f64 || fmat[2usize] != 0.0f64 { os.exit(3i32) }
    if hmat[0usize] != 1.0f64 || hmat[3usize] != 1.0f64 || hmat[1usize] != 0.0f64 || hmat[2usize] != 0.0f64 { os.exit(3i32) }
    var varstate: [2]f64 = zero
    varstate[0usize] = 4.0f64
    varstate[1usize] = 6.0f64
    var pmat: [4]f64 = zero
    pmat[0usize] = 1.0f64
    pmat[3usize] = 1.0f64
    var qmat: [4]f64 = zero
    var kscratch: [16]f64 = zero
    if filter.kalman_predict(varstate[..], pmat[..], fmat[..], qmat[..], 2usize, kscratch[..]) != ok { os.exit(3i32) }
    if !near(varstate[0usize], 2.0f64, 0.000000001f64) || !near(varstate[1usize], 3.0f64, 0.000000001f64) { os.exit(3i32) }
    // A VAR(2) companion shifts the second block down by identity.
    var c2: [8]f64 = zero
    c2[0usize] = 1.0f64
    c2[1usize] = 2.0f64
    c2[2usize] = 3.0f64
    c2[3usize] = 4.0f64
    c2[4usize] = 5.0f64
    c2[5usize] = 6.0f64
    c2[6usize] = 7.0f64
    c2[7usize] = 8.0f64
    var f2: [16]f64 = zero
    var h2: [8]f64 = zero
    if timeseries.var_companion(c2[..], 2usize, 2usize, f2[..], h2[..]) != ok { os.exit(3i32) }
    if !near(f2[0usize], 1.0f64, 0.000000001f64) || !near(f2[1usize], 2.0f64, 0.000000001f64) { os.exit(3i32) }
    if !near(f2[2usize], 5.0f64, 0.000000001f64) || !near(f2[3usize], 6.0f64, 0.000000001f64) { os.exit(3i32) }
    if !near(f2[8usize], 1.0f64, 0.000000001f64) || !near(f2[13usize], 1.0f64, 0.000000001f64) { os.exit(3i32) }
    if !near(h2[0usize], 1.0f64, 0.000000001f64) || !near(h2[5usize], 1.0f64, 0.000000001f64) { os.exit(3i32) }
    if timeseries.var_companion(c2[..], 2usize, 2usize, f2[..15usize], h2[..]) != timeseries.TooSmall { os.exit(3i32) }

    // 4: the local level tracks a constant, the trend filter a ramp.
    var flat: [30]f64 = zero
    i = 0usize
    while i < 30usize {
        flat[i] = 10.0f64
        i += 1usize
    }
    var levelled: [30]f64 = zero
    var fscratch: [32]f64 = zero
    if timeseries.level_filter(flat[..], 0.01f64, 1.0f64, 0.0f64, 1.0f64, levelled[..], fscratch[..]) != ok { os.exit(4i32) }
    if !near(levelled[29usize], 10.0f64, 1.0f64) || levelled[29usize] <= levelled[5usize] { os.exit(4i32) }
    var ramp: [30]f64 = zero
    i = 0usize
    while i < 30usize {
        ramp[i] = f64(i)
        i += 1usize
    }
    var tlevel: [30]f64 = zero
    var tslope: [30]f64 = zero
    var tscratch: [64]f64 = zero
    if timeseries.trend_filter(ramp[..], 0.01f64, 0.001f64, 1.0f64, 0.0f64, 0.0f64, 1.0f64, tlevel[..], tslope[..], tscratch[..]) != ok { os.exit(4i32) }
    if !near(tslope[29usize], 1.0f64, 0.2f64) || !near(tlevel[29usize], 29.0f64, 1.0f64) { os.exit(4i32) }
    if timeseries.level_filter(flat[..0usize], 0.01f64, 1.0f64, 0.0f64, 1.0f64, levelled[..], fscratch[..]) != timeseries.Invalid { os.exit(4i32) }
    if timeseries.level_filter(flat[..], 0.01f64, 0.0f64, 0.0f64, 1.0f64, levelled[..], fscratch[..]) != timeseries.Invalid { os.exit(4i32) }
    if timeseries.trend_filter(ramp[..], 0.01f64, 0.001f64, 1.0f64, 0.0f64, 0.0f64, 1.0f64, tlevel[..], tslope[..], tscratch[..10usize]) != timeseries.TooSmall { os.exit(4i32) }

    // 5: the fit refusals -- fewer rows than lags, an unidentified window, a
    // short parameter slice, short scratch and a singular design.
    var tiny: [4]f64 = zero
    var bad_coefs: [4]f64 = zero
    var bad_icept: [2]f64 = zero
    if timeseries.var_fit(tiny[..], 1usize, 2usize, 1usize, bad_coefs[..], bad_icept[..], scratch[..]) != timeseries.Invalid { os.exit(5i32) }
    if timeseries.var_fit(tiny[..], 2usize, 2usize, 1usize, bad_coefs[..], bad_icept[..], scratch[..]) != timeseries.Invalid { os.exit(5i32) }
    var short_coefs: [3]f64 = zero
    if timeseries.var_fit(sim[400usize..4400usize], 2000usize, 2usize, 1usize, short_coefs[..], bad_icept[..], scratch[..]) != timeseries.TooSmall { os.exit(5i32) }
    var short_scratch: [4]f64 = zero
    if timeseries.var_fit(sim[400usize..4400usize], 2000usize, 2usize, 1usize, bad_coefs[..], bad_icept[..], short_scratch[..]) != timeseries.TooSmall { os.exit(5i32) }
    var flatline: [12]f64 = zero
    var flat_coefs: [4]f64 = zero
    var flat_icept: [2]f64 = zero
    var flat_scratch: [32]f64 = zero
    var f = 0usize
    while f < 12usize {
        flatline[f] = 3.0f64
        f += 1usize
    }
    if timeseries.var_fit(flatline[..], 6usize, 2usize, 1usize, flat_coefs[..], flat_icept[..], flat_scratch[..]) != timeseries.Invalid { os.exit(5i32) }
    var zeros_a: [9]f64 = zero
    var zeros_b: [3]f64 = zero
    var zeros_x: [3]f64 = zero
    var zeros_w: [12]f64 = zero
    if timeseries.solve_normal(zeros_a[..], zeros_b[..], zeros_x[..], 3usize, zeros_w[..]) != timeseries.Invalid { os.exit(5i32) }

    try io.print("algo timeseries var ok\n")
    ret ok
}
