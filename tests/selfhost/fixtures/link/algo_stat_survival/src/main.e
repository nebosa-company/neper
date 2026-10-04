// `e.algo.stat.survival`: Nelson-Aalen against its hand sum, competing-risk
// incidence against its hand sum, RMST against the Kaplan-Meier area with its
// Greenwood error, the weighted log-ranks significant where they should be
// (and equal to Mantel-Cox for the plain weight), with every refusal. Each
// check exits with its own code.

use e.algo.stat.survival
use e.algo.stat.survival_trial
use e.io
use e.mem
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: Nelson-Aalen on [1, 2, 3, 4, 5, 6] with events at 1, 3, 4, 6.
    var times: [6]f64 = zero
    times[0usize] = 1.0f64
    times[1usize] = 2.0f64
    times[2usize] = 3.0f64
    times[3usize] = 4.0f64
    times[4usize] = 5.0f64
    times[5usize] = 6.0f64
    var events: [6]u8 = zero
    events[0usize] = 1u8
    events[2usize] = 1u8
    events[3usize] = 1u8
    events[5usize] = 1u8
    var ht: [6]f64 = zero
    var hh: [6]f64 = zero
    var hv: [6]f64 = zero
    var hr: [6]usize = zero
    var horder: [6]usize = zero
    let (hcount, h_error) = survival.nelson_aalen(times[..], events[..], 6usize, ht[..], hh[..], hv[..], hr[..], horder[..])
    if h_error != ok || hcount != 4usize { os.exit(1i32) }
    if !near(hh[3usize], 1.75f64, 0.000000001f64) { os.exit(1i32) }
    if !near(hv[3usize], 1.201388888889f64, 0.000001f64) { os.exit(1i32) }
    if hr[0usize] != 6usize || !near(ht[0usize], 1.0f64, 0.000000001f64) { os.exit(1i32) }
    let (hempty, hempty_error) = survival.nelson_aalen(times[..], events[..], 0usize, ht[..], hh[..], hv[..], hr[..], horder[..])
    if hempty_error != survival.Invalid || hempty != 0usize { os.exit(1i32) }
    var bad: [6]u8 = zero
    bad[0usize] = 2u8
    let (_, hbad) = survival.nelson_aalen(times[..], bad[..], 6usize, ht[..], hh[..], hv[..], hr[..], horder[..])
    if hbad != survival.Invalid { os.exit(1i32) }
    let (_, hshort) = survival.nelson_aalen(times[..], events[..], 6usize, ht[..5usize], hh[..], hv[..], hr[..], horder[..])
    if hshort != survival.TooSmall { os.exit(1i32) }

    // 2: competing risks [1, 2, 3, 4, 5] with causes [1, 0, 2, 1, 2].
    var ctimes: [5]f64 = zero
    ctimes[0usize] = 1.0f64
    ctimes[1usize] = 2.0f64
    ctimes[2usize] = 3.0f64
    ctimes[3usize] = 4.0f64
    ctimes[4usize] = 5.0f64
    var causes: [5]u8 = zero
    causes[0usize] = 1u8
    causes[2usize] = 2u8
    causes[3usize] = 1u8
    causes[4usize] = 2u8
    var ct: [5]f64 = zero
    var cf: [5]f64 = zero
    var corder: [5]usize = zero
    let (ccount, c_error) = survival.cumulative_incidence(ctimes[..], causes[..], 5usize, 1u8, ct[..], cf[..], corder[..])
    if c_error != ok || ccount != 2usize { os.exit(2i32) }
    if !near(cf[0usize], 0.2f64, 0.000000001f64) || !near(cf[1usize], 0.466666666667f64, 0.000000001f64) { os.exit(2i32) }
    let (_, czero) = survival.cumulative_incidence(ctimes[..], causes[..], 5usize, 0u8, ct[..], cf[..], corder[..])
    if czero != survival.Invalid { os.exit(2i32) }
    let (_, cshort) = survival.cumulative_incidence(ctimes[..], causes[..], 5usize, 1u8, ct[..4usize], cf[..], corder[..])
    if cshort != survival.TooSmall { os.exit(2i32) }

    // 3: RMST of the check-1 data to tau 4 and 10.
    var rorder: [6]usize = zero
    let (rm4, rm4_error) = survival.rmst(times[..], events[..], 6usize, 4.0f64, rorder[..])
    if rm4_error != ok { os.exit(3i32) }
    if !near(rm4.mean, 3.291666666667f64, 0.000001f64) { os.exit(3i32) }
    if !near(rm4.se, 0.455642f64, 0.001f64) { os.exit(3i32) }
    let (rm10, rm10_error) = survival.rmst(times[..], events[..], 6usize, 10.0f64, rorder[..])
    if rm10_error != ok || !near(rm10.mean, 4.125f64, 0.000001f64) { os.exit(3i32) }
    let (_, rtau) = survival.rmst(times[..], events[..], 6usize, 0.0f64, rorder[..])
    if rtau != survival.Invalid { os.exit(3i32) }
    let (_, rempty) = survival.rmst(times[..], events[..], 0usize, 4.0f64, rorder[..])
    if rempty != survival.Invalid { os.exit(3i32) }

    // 4: separated groups [1, 2, 3] against [4, 5, 6] are significant under
    // every weight, and the plain weight equals Mantel-Cox.
    var ta: [3]f64 = zero
    ta[0usize] = 1.0f64
    ta[1usize] = 2.0f64
    ta[2usize] = 3.0f64
    var ea: [3]u8 = zero
    ea[0usize] = 1u8
    ea[1usize] = 1u8
    ea[2usize] = 1u8
    var tb: [3]f64 = zero
    tb[0usize] = 4.0f64
    tb[1usize] = 5.0f64
    tb[2usize] = 6.0f64
    var eb: [3]u8 = zero
    eb[0usize] = 1u8
    eb[1usize] = 1u8
    eb[2usize] = 1u8
    let (plain, plain_error) = survival.weighted_log_rank(ta[..], ea[..], 3usize, tb[..], eb[..], 3usize, .LogRank)
    let (classic, classic_error) = survival_trial.log_rank(ta[..], ea[..], 3usize, tb[..], eb[..], 3usize)
    if plain_error != ok || classic_error != ok { os.exit(4i32) }
    if !near(plain.statistic, classic.statistic, 0.000000001f64) { os.exit(4i32) }
    if !near(plain.p_value, classic.p_value, 0.000000001f64) { os.exit(4i32) }
    if plain.p_value >= 0.05f64 { os.exit(4i32) }
    let (breslow, breslow_error) = survival.weighted_log_rank(ta[..], ea[..], 3usize, tb[..], eb[..], 3usize, .Breslow)
    if breslow_error != ok || breslow.p_value >= 0.05f64 { os.exit(4i32) }
    let (tarone, tarone_error) = survival.weighted_log_rank(ta[..], ea[..], 3usize, tb[..], eb[..], 3usize, .TaroneWare)
    if tarone_error != ok || tarone.p_value >= 0.05f64 { os.exit(4i32) }
    let (peto, peto_error) = survival.weighted_log_rank(ta[..], ea[..], 3usize, tb[..], eb[..], 3usize, .PetoPeto)
    if peto_error != ok || peto.p_value >= 0.05f64 { os.exit(4i32) }
    let (fh, fh_error) = survival.fleming_harrington(ta[..], ea[..], 3usize, tb[..], eb[..], 3usize, 1.0f64, 0.0f64)
    if fh_error != ok || fh.p_value >= 0.05f64 { os.exit(4i32) }
    let (fh00, fh00_error) = survival.fleming_harrington(ta[..], ea[..], 3usize, tb[..], eb[..], 3usize, 0.0f64, 0.0f64)
    if fh00_error != ok || !near(fh00.statistic, plain.statistic, 0.000000001f64) { os.exit(4i32) }
    let (_, rhoneg) = survival.fleming_harrington(ta[..], ea[..], 3usize, tb[..], eb[..], 3usize, 0.0f64 - 1.0f64, 0.0f64)
    if rhoneg != survival.Invalid { os.exit(4i32) }

    // 5: identical groups carry no signal under any weight.
    let (same, same_error) = survival.weighted_log_rank(ta[..], ea[..], 3usize, ta[..], ea[..], 3usize, .LogRank)
    if same_error != ok || same.statistic != 0.0f64 || same.p_value != 1.0f64 { os.exit(5i32) }
    let (same_b, same_b_error) = survival.weighted_log_rank(ta[..], ea[..], 3usize, ta[..], ea[..], 3usize, .Breslow)
    if same_b_error != ok || same_b.p_value != 1.0f64 { os.exit(5i32) }
    let (same_fh, same_fh_error) = survival.fleming_harrington(ta[..], ea[..], 3usize, ta[..], ea[..], 3usize, 0.5f64, 0.5f64)
    if same_fh_error != ok || same_fh.p_value != 1.0f64 { os.exit(5i32) }
    var badflag: [3]u8 = zero
    badflag[0usize] = 3u8
    let (_, bad_error) = survival.weighted_log_rank(ta[..], badflag[..], 3usize, tb[..], eb[..], 3usize, .LogRank)
    if bad_error != survival.Invalid { os.exit(5i32) }
    let (_, empty_error) = survival.weighted_log_rank(ta[..], ea[..], 0usize, tb[..], eb[..], 3usize, .LogRank)
    if empty_error != survival.Invalid { os.exit(5i32) }

    try io.print("algo stat survival ok\n")
    ret ok
}
