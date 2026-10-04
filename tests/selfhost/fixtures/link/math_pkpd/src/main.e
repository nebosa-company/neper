// `e.math.pkpd`: non-compartmental analysis of an exponential decay, the
// linear and linear-up/log-down trapezoid against the closed forms, and the
// Emax/Hill and Michaelis-Menten fits recovering their parameters from clean
// data, with the too-few, non-positive and wrong-parameter refusals. Each
// check exits with its own code.

use e.io
use e.math.pkpd
use e.mem
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    // An exponential decay C(t) = 10 * 2^(-t): exact in the log-down area.
    var times: [5]f64 = zero
    times[0usize] = 0.0f64
    times[1usize] = 1.0f64
    times[2usize] = 2.0f64
    times[3usize] = 3.0f64
    times[4usize] = 4.0f64
    var conc: [5]f64 = zero
    conc[0usize] = 10.0f64
    conc[1usize] = 5.0f64
    conc[2usize] = 2.5f64
    conc[3usize] = 1.25f64
    conc[4usize] = 0.625f64

    // 1: linear trapezoid, first moment and peak against the closed forms.
    if !near(pkpd.auc_linear(times[..], conc[..]), 14.0625f64, 1.0e-9f64) { os.exit(1i32) }
    if !near(pkpd.aumc_linear(times[..], conc[..]), 15.0f64, 1.0e-9f64) { os.exit(1i32) }
    let p = pkpd.peak(times[..], conc[..])
    if !near(p.value, 10.0f64, 1.0e-12f64) || !near(p.time, 0.0f64, 1.0e-12f64) { os.exit(1i32) }

    // 2: log-down area equals the integral (C0 - Clast) / ln 2.
    if !near(pkpd.auc_log_linear(times[..], conc[..]), 13.525266008334032f64, 1.0e-9f64) { os.exit(2i32) }

    // 3: the whole NCA set, its terminal window the last three samples.
    var report: pkpd.Nca = zero
    if pkpd.nca(times[..], conc[..], 2usize, &report) != ok { os.exit(3i32) }
    if !near(report.auc, 14.0625f64, 1.0e-9f64) { os.exit(3i32) }
    if !near(report.aumc, 15.0f64, 1.0e-9f64) { os.exit(3i32) }
    if !near(report.lambda_z, 0.6931471805599454f64, 1.0e-9f64) { os.exit(3i32) }
    if !near(report.half_life, 1.0f64, 1.0e-9f64) { os.exit(3i32) }
    if !near(report.auc_inf, 14.964184400555602f64, 1.0e-9f64) { os.exit(3i32) }
    if !near(report.mrt, 1.0666666666666667f64, 1.0e-9f64) { os.exit(3i32) }
    if !near(report.cmax, 10.0f64, 1.0e-12f64) || !near(report.tmax, 0.0f64, 1.0e-12f64) { os.exit(3i32) }
    let (rate, rate_error) = pkpd.terminal_rate(times[..], conc[..], 2usize)
    if rate_error != ok || !near(rate, 0.6931471805599454f64, 1.0e-9f64) { os.exit(3i32) }
    if !near(pkpd.half_life(rate), 1.0f64, 1.0e-9f64) { os.exit(3i32) }

    // 4: the model evaluators at their midpoints.
    if !near(pkpd.emax(0.0f64, 100.0f64, 5.0f64, 5.0f64), 50.0f64, 1.0e-12f64) { os.exit(4i32) }
    if !near(pkpd.hill(0.0f64, 100.0f64, 5.0f64, 2.0f64, 5.0f64), 50.0f64, 1.0e-12f64) { os.exit(4i32) }
    if !near(pkpd.hill(0.0f64, 100.0f64, 5.0f64, 2.0f64, 0.0f64), 0.0f64, 1.0e-12f64) { os.exit(4i32) }
    if !near(pkpd.mm_rate(10.0f64, 3.0f64, 3.0f64), 5.0f64, 1.0e-12f64) { os.exit(4i32) }

    // 5: the Hill fit recovers E0 = 0, Emax = 100, EC50 = 5, h = 2 from clean data.
    var doses: [7]f64 = zero
    doses[0usize] = 0.5f64
    doses[1usize] = 1.0f64
    doses[2usize] = 2.0f64
    doses[3usize] = 5.0f64
    doses[4usize] = 10.0f64
    doses[5usize] = 20.0f64
    doses[6usize] = 50.0f64
    var effect: [7]f64 = zero
    var i = 0usize
    while i < 7usize {
        effect[i] = pkpd.hill(0.0f64, 100.0f64, 5.0f64, 2.0f64, doses[i])
        i += 1usize
    }
    var curve = pkpd.Data { x: doses[..], y: effect[..] }
    var parameters: [4]f64 = zero
    parameters[0usize] = 0.0f64
    parameters[1usize] = 90.0f64
    parameters[2usize] = 4.0f64
    parameters[3usize] = 1.5f64
    var fit_scratch: [64]f64 = zero
    let (hill_fit, hill_error) = pkpd.emax_hill(&curve, parameters[..], 2.0f64, 1.0e-12f64, 20000u32, fit_scratch[..])
    if hill_error != ok || !hill_fit.converged || hill_fit.value > 1.0e-6f64 { os.exit(5i32) }
    if !near(parameters[0usize], 0.0f64, 0.01f64) { os.exit(5i32) }
    if !near(parameters[1usize], 100.0f64, 0.05f64) { os.exit(5i32) }
    if !near(parameters[2usize], 5.0f64, 0.01f64) { os.exit(5i32) }
    if !near(parameters[3usize], 2.0f64, 0.01f64) { os.exit(5i32) }

    // 6: the Michaelis-Menten fit recovers Vmax = 10, Km = 3.
    var substrate: [6]f64 = zero
    substrate[0usize] = 0.5f64
    substrate[1usize] = 1.0f64
    substrate[2usize] = 2.0f64
    substrate[3usize] = 5.0f64
    substrate[4usize] = 10.0f64
    substrate[5usize] = 20.0f64
    var velocity: [6]f64 = zero
    i = 0usize
    while i < 6usize {
        velocity[i] = pkpd.mm_rate(10.0f64, 3.0f64, substrate[i])
        i += 1usize
    }
    var enzyme = pkpd.Data { x: substrate[..], y: velocity[..] }
    var kinetics: [2]f64 = zero
    kinetics[0usize] = 8.0f64
    kinetics[1usize] = 2.0f64
    let (mm_fit, mm_error) = pkpd.michaelis_menten(&enzyme, kinetics[..], 1.0f64, 1.0e-12f64, 20000u32, fit_scratch[..])
    if mm_error != ok || !mm_fit.converged || mm_fit.value > 1.0e-6f64 { os.exit(6i32) }
    if !near(kinetics[0usize], 10.0f64, 0.01f64) { os.exit(6i32) }
    if !near(kinetics[1usize], 3.0f64, 0.01f64) { os.exit(6i32) }

    // 7: the refusals -- a non-positive terminal sample, too short a window,
    // a profile below two samples and a fit slice of the wrong length.
    var bad_conc: [5]f64 = zero
    bad_conc[0usize] = 10.0f64
    let (_, bad_rate) = pkpd.terminal_rate(times[..], bad_conc[..], 2usize)
    if bad_rate != pkpd.Invalid { os.exit(7i32) }
    let (_, short_rate) = pkpd.terminal_rate(times[..], conc[..], 4usize)
    if short_rate != pkpd.TooFew { os.exit(7i32) }
    var short_report: pkpd.Nca = zero
    if pkpd.nca(times[..1usize], conc[..1usize], 0usize, &short_report) != pkpd.TooFew { os.exit(7i32) }
    var wrong: [3]f64 = zero
    let (_, wrong_fit) = pkpd.emax_hill(&curve, wrong[..], 1.0f64, 1.0e-9f64, 10u32, fit_scratch[..])
    if wrong_fit != pkpd.Invalid { os.exit(7i32) }

    try io.print("math pkpd ok\n")
    ret ok
}
