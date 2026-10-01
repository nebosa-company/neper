// `e.algo.stat.survival_trial`: Kaplan-Meier curves, the log-rank test and
// a Cox fit on two arms against hand-computed values, spending functions,
// Simon optimal and minimax designs with operating characteristics,
// likelihood CRM dose finding, Farrington-Manning non-inferiority, and the
// storage and degenerate cases. Each check exits with its own code.

use e.algo.stat.survival_trial as trial
use e.math
use e.mem
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    var ta: [8]f64 = zero
    ta[0usize] = 5.0f64
    ta[1usize] = 6.0f64
    ta[2usize] = 6.0f64
    ta[3usize] = 8.0f64
    ta[4usize] = 10.0f64
    ta[5usize] = 12.0f64
    ta[6usize] = 15.0f64
    ta[7usize] = 20.0f64
    var ea: [8]u8 = zero
    ea[0usize] = 1u8
    ea[1usize] = 1u8
    ea[3usize] = 1u8
    ea[4usize] = 1u8
    ea[6usize] = 1u8
    ea[7usize] = 1u8
    var tb: [8]f64 = zero
    tb[0usize] = 3.0f64
    tb[1usize] = 4.0f64
    tb[2usize] = 7.0f64
    tb[3usize] = 9.0f64
    tb[4usize] = 11.0f64
    tb[5usize] = 13.0f64
    tb[6usize] = 14.0f64
    tb[7usize] = 18.0f64
    var eb: [8]u8 = zero
    eb[0usize] = 1u8
    eb[1usize] = 1u8
    eb[2usize] = 1u8
    eb[4usize] = 1u8
    eb[5usize] = 1u8
    eb[7usize] = 1u8
    var ktimes: [8]f64 = zero
    var ksurv: [8]f64 = zero
    var krisk: [8]usize = zero
    var korder: [8]usize = zero

    // 1: Kaplan-Meier curves of both arms.
    let (records_a, a_error) = trial.kaplan_meier(ta[..], ea[..], 8usize, ktimes[..], ksurv[..], krisk[..], korder[..])
    if a_error != ok { os.exit(1i32) }
    if records_a != 6usize { os.exit(1i32) }
    if ktimes[0usize] != 5.0f64 || krisk[0usize] != 8usize { os.exit(1i32) }
    if !near(ksurv[0usize], 0.875f64, 0.000000001f64) { os.exit(1i32) }
    if ktimes[2usize] != 8.0f64 || krisk[2usize] != 5usize { os.exit(1i32) }
    if !near(ksurv[2usize], 0.6f64, 0.000000001f64) { os.exit(1i32) }
    if ktimes[5usize] != 20.0f64 || krisk[5usize] != 1usize { os.exit(1i32) }
    if !near(ksurv[5usize], 0.0f64, 0.000000001f64) { os.exit(1i32) }
    let (records_b, b_error) = trial.kaplan_meier(tb[..], eb[..], 8usize, ktimes[..], ksurv[..], krisk[..], korder[..])
    if b_error != ok { os.exit(1i32) }
    if records_b != 6usize { os.exit(1i32) }
    if ktimes[0usize] != 3.0f64 || krisk[0usize] != 8usize { os.exit(1i32) }
    if !near(ksurv[0usize], 0.875f64, 0.000000001f64) { os.exit(1i32) }
    if ktimes[2usize] != 7.0f64 || krisk[2usize] != 6usize { os.exit(1i32) }
    if !near(ksurv[2usize], 0.625f64, 0.000000001f64) { os.exit(1i32) }
    if !near(ksurv[3usize], 0.46875f64, 0.000000001f64) { os.exit(1i32) }
    if !near(ksurv[5usize], 0.0f64, 0.000000001f64) { os.exit(1i32) }

    // 2: the log-rank test and a Cox fit on the arm indicator.
    let (lr, lr_error) = trial.log_rank(ta[..], ea[..], 8usize, tb[..], eb[..], 8usize)
    if lr_error != ok { os.exit(2i32) }
    if !near(lr.statistic, 0.13037083743158018f64, 0.000000001f64) { os.exit(2i32) }
    if !near(lr.p_value, 0.7180478514602853f64, 0.000000001f64) { os.exit(2i32) }
    var cx: [16]f64 = zero
    var i = 8usize
    while i < 16usize {
        cx[i] = 1.0f64
        i += 1usize
    }
    var times: [16]f64 = zero
    var events: [16]u8 = zero
    i = 0usize
    while i < 8usize {
        times[i] = ta[i]
        events[i] = ea[i]
        times[8usize + i] = tb[i]
        events[8usize + i] = eb[i]
        i += 1usize
    }
    var beta: [1]f64 = zero
    var bcov: [1]f64 = zero
    var fscratch: [24]f64 = zero
    var iscratch: [16]usize = zero
    let (cox_rounds, cox_error) = trial.cox_ph(times[..], events[..], cx[..], 16usize, 1usize, beta[..], bcov[..], fscratch[..], iscratch[..])
    if cox_error != ok { os.exit(2i32) }
    if cox_rounds == 0u32 { os.exit(2i32) }
    if !near(beta[0usize], 0.22033518545808548f64, 0.000000001f64) { os.exit(2i32) }
    if !near(math.sqrt[f64](bcov[0usize]), 0.6113976945511455f64, 0.000000001f64) { os.exit(2i32) }

    // 3: spending functions and Simon designs.
    let (of_half, of_half_error) = trial.spending_obrien_fleming(0.5f64, 0.05f64)
    if of_half_error != ok { os.exit(3i32) }
    let (pk_half, pk_half_error) = trial.spending_pocock(0.5f64, 0.05f64)
    if pk_half_error != ok { os.exit(3i32) }
    let (of_full, of_full_error) = trial.spending_obrien_fleming(1.0f64, 0.05f64)
    if of_full_error != ok { os.exit(3i32) }
    let (pk_full, pk_full_error) = trial.spending_pocock(1.0f64, 0.05f64)
    if pk_full_error != ok { os.exit(3i32) }
    if !near(of_half, 0.005574596680784305f64, 0.000000001f64) { os.exit(3i32) }
    if !near(pk_half, 0.031005725347913876f64, 0.000000001f64) { os.exit(3i32) }
    if !near(of_full, 0.050000000000000044f64, 0.000000001f64) { os.exit(3i32) }
    if !near(pk_full, 0.05f64, 0.000000001f64) { os.exit(3i32) }
    var sscratch: [372]f64 = zero
    let (optimal, optimal_error) = trial.simon_optimal(0.10f64, 0.30f64, 0.05f64, 0.20f64, sscratch[..])
    if optimal_error != ok { os.exit(3i32) }
    if optimal.n1 != 10usize || optimal.r1 != 1usize || optimal.n != 29usize || optimal.r != 5usize { os.exit(3i32) }
    let (minimax, minimax_error) = trial.simon_minimax(0.10f64, 0.30f64, 0.05f64, 0.20f64, sscratch[..])
    if minimax_error != ok { os.exit(3i32) }
    if minimax.n1 != 11usize || minimax.r1 != 0usize || minimax.n != 25usize || minimax.r != 5usize { os.exit(3i32) }
    var oscratch: [64]f64 = zero
    let (type1, expected, oc_error) = trial.simon_oc(10usize, 1usize, 29usize, 5usize, 0.10f64, oscratch[..])
    if oc_error != ok { os.exit(3i32) }
    if !near(type1, 0.04708630664389136f64, 0.000000001f64) { os.exit(3i32) }
    if !near(expected, 15.014120347099997f64, 0.000000001f64) { os.exit(3i32) }
    let (power, _, power_error) = trial.simon_oc(10usize, 1usize, 29usize, 5usize, 0.30f64, oscratch[..])
    if power_error != ok { os.exit(3i32) }
    if !near(power, 0.8050629131503234f64, 0.000000001f64) { os.exit(3i32) }
    let (tail, tail_error) = trial.binom_sf(10usize, 3usize, 0.5f64)
    if tail_error != ok { os.exit(3i32) }
    if !near(tail, 0.9453125f64, 0.000000000001f64) { os.exit(3i32) }

    // 4: CRM dose finding and Farrington-Manning non-inferiority.
    var skeleton: [5]f64 = zero
    skeleton[0usize] = 0.05f64
    skeleton[1usize] = 0.12f64
    skeleton[2usize] = 0.20f64
    skeleton[3usize] = 0.30f64
    skeleton[4usize] = 0.40f64
    var assigned: [6]usize = zero
    assigned[3usize] = 1usize
    assigned[4usize] = 1usize
    assigned[5usize] = 1usize
    var outcomes: [6]u8 = zero
    outcomes[5usize] = 1u8
    var means: [5]f64 = zero
    let (dose, dose_error) = trial.crm_next(skeleton[..], 5usize, 0.25f64, assigned[..], outcomes[..], 6usize, means[..])
    if dose_error != ok { os.exit(4i32) }
    if dose != 1usize { os.exit(4i32) }
    if !near(means[0usize], 0.10434243667918248f64, 0.000001f64) { os.exit(4i32) }
    if !near(means[1usize], 0.20197825152324508f64, 0.000001f64) { os.exit(4i32) }
    if !near(means[2usize], 0.29694393968798316f64, 0.000001f64) { os.exit(4i32) }
    if !near(means[3usize], 0.40320266709777247f64, 0.000001f64) { os.exit(4i32) }
    if !near(means[4usize], 0.500934810221053f64, 0.000001f64) { os.exit(4i32) }
    let (pt, pc, mle_error) = trial.fm_mle(85u64, 100u64, 78u64, 100u64, 0.10f64)
    if mle_error != ok { os.exit(4i32) }
    if !near(pt, 0.7489323747425957f64, 0.000000001f64) { os.exit(4i32) }
    if !near(pc, 0.8489323747425956f64, 0.000000001f64) { os.exit(4i32) }
    if !near(pt - pc + 0.10f64, 0.0f64, 0.000000000001f64) { os.exit(4i32) }
    let (fm, fm_error) = trial.farrington_manning(85u64, 100u64, 78u64, 100u64, 0.10f64)
    if fm_error != ok { os.exit(4i32) }
    if !near(fm.statistic, 3.0228307515139816f64, 0.000000001f64) { os.exit(4i32) }
    if !near(fm.p_value, 0.001252111283510952f64, 0.000000001f64) { os.exit(4i32) }

    // 5: storage and degenerate cases.
    let (_, km_empty_error) = trial.kaplan_meier(ta[..0usize], ea[..0usize], 0usize, ktimes[..0usize], ksurv[..0usize], krisk[..0usize], korder[..0usize])
    if km_empty_error != trial.Invalid { os.exit(5i32) }
    ea[0usize] = 2u8
    let (_, km_bad_error) = trial.kaplan_meier(ta[..], ea[..], 8usize, ktimes[..], ksurv[..], krisk[..], korder[..])
    if km_bad_error != trial.Invalid { os.exit(5i32) }
    ea[0usize] = 1u8
    let (_, lr_empty_error) = trial.log_rank(ta[..0usize], ea[..0usize], 0usize, tb[..], eb[..], 8usize)
    if lr_empty_error != trial.Invalid { os.exit(5i32) }
    let (_, cox_nocov_error) = trial.cox_ph(times[..], events[..], cx[..], 16usize, 0usize, beta[..0usize], bcov[..0usize], fscratch[..0usize], iscratch[..0usize])
    if cox_nocov_error != trial.Invalid { os.exit(5i32) }
    var allevents: [16]u8 = zero
    let (_, cox_singular_error) = trial.cox_ph(times[..], allevents[..], cx[..], 16usize, 1usize, beta[..], bcov[..], fscratch[..], iscratch[..])
    if cox_singular_error != trial.Singular { os.exit(5i32) }
    let (_, spend_early_error) = trial.spending_obrien_fleming(0.0f64, 0.05f64)
    if spend_early_error != trial.Invalid { os.exit(5i32) }
    let (_, spend_late_error) = trial.spending_pocock(2.0f64, 0.05f64)
    if spend_late_error != trial.Invalid { os.exit(5i32) }
    let (_, spend_alpha_error) = trial.spending_pocock(0.5f64, 0.0f64)
    if spend_alpha_error != trial.Invalid { os.exit(5i32) }
    let (_, _, simon_bad_error) = trial.simon_oc(29usize, 1usize, 29usize, 5usize, 0.10f64, oscratch[..])
    if simon_bad_error != trial.Invalid { os.exit(5i32) }
    let (_, simon_equal_error) = trial.simon_optimal(0.20f64, 0.20f64, 0.05f64, 0.20f64, sscratch[..])
    if simon_equal_error != trial.Invalid { os.exit(5i32) }
    let (_, binom_bad_error) = trial.binom_sf(10usize, 3usize, 2.0f64)
    if binom_bad_error != trial.Invalid { os.exit(5i32) }
    skeleton[0usize] = 0.0f64
    let (_, crm_bad_error) = trial.crm_next(skeleton[..], 5usize, 0.25f64, assigned[..], outcomes[..], 6usize, means[..])
    if crm_bad_error != trial.Invalid { os.exit(5i32) }
    skeleton[0usize] = 0.05f64
    let (_, crm_target_error) = trial.crm_next(skeleton[..], 5usize, 0.0f64, assigned[..], outcomes[..], 6usize, means[..])
    if crm_target_error != trial.Invalid { os.exit(5i32) }
    let (_, fm_margin_error) = trial.farrington_manning(85u64, 100u64, 78u64, 100u64, 0.0f64)
    if fm_margin_error != trial.Invalid { os.exit(5i32) }
    let (_, fm_count_error) = trial.farrington_manning(101u64, 100u64, 78u64, 100u64, 0.10f64)
    if fm_count_error != trial.Invalid { os.exit(5i32) }
    ret ok
}
