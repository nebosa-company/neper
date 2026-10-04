// `e.algo.stat.safety`: ROR/PRR with logit intervals and Evans/CI signal rules,
// the BCPNN information component with its credibility signal, and Apriori
// frequent itemsets plus association rules over comedication masks -- with the
// zero-cell, empty-table and short-storage refusals. Each check exits with
// its own code.

use e.algo.stat.safety
use e.io
use e.mem
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: ROR on [[20, 10], [5, 100]] is 40 with SE 0.6, signalling.
    var hot = safety.Table { a: 20u64, b: 10u64, c: 5u64, d: 100u64 }
    let (r, r_error) = safety.ror(hot)
    if r_error != ok { os.exit(1i32) }
    if !near(r.estimate, 40.0f64, 0.000000001f64) { os.exit(1i32) }
    if !near(r.lower, 12.336f64, 0.05f64) || !near(r.upper, 129.74f64, 0.5f64) { os.exit(1i32) }
    let (rs, rs_error) = safety.ror_signal(hot)
    if rs_error != ok || !rs { os.exit(1i32) }
    let (chi, chi_error) = safety.chi_square_2x2(hot)
    if chi_error != ok || !near(chi, 59.28f64, 0.1f64) { os.exit(1i32) }
    var zeroed = safety.Table { a: 0u64, b: 10u64, c: 5u64, d: 100u64 }
    let (_, ror_bad) = safety.ror(zeroed)
    if ror_bad != safety.Invalid { os.exit(1i32) }

    // 2: PRR on the same table is 14 with the Evans signal.
    let (p, p_error) = safety.prr(hot)
    if p_error != ok { os.exit(2i32) }
    if !near(p.estimate, 14.0f64, 0.000000001f64) { os.exit(2i32) }
    if !near(p.lower, 5.738f64, 0.02f64) || !near(p.upper, 34.16f64, 0.1f64) { os.exit(2i32) }
    let (ps, ps_error) = safety.prr_signal(hot)
    if ps_error != ok || !ps { os.exit(2i32) }
    var noc = safety.Table { a: 20u64, b: 10u64, c: 0u64, d: 100u64 }
    let (_, prr_bad) = safety.prr(noc)
    if prr_bad != safety.Invalid { os.exit(2i32) }

    // 3: the BCPNN information component and its credibility signal.
    let (info, info_error) = safety.ic(hot)
    if info_error != ok { os.exit(3i32) }
    if !near(info.estimate, 1.62735f64, 0.00001f64) { os.exit(3i32) }
    if !near(info.lower, 0.72983f64, 0.00001f64) || !near(info.upper, 2.52487f64, 0.00001f64) { os.exit(3i32) }
    let (is, is_error) = safety.ic_signal(hot)
    if is_error != ok || !is { os.exit(3i32) }
    var flat = safety.Table { a: 0u64, b: 0u64, c: 0u64, d: 0u64 }
    let (_, ic_bad) = safety.ic(flat)
    if ic_bad != safety.Invalid { os.exit(3i32) }
    let (_, chi_bad) = safety.chi_square_2x2(flat)
    if chi_bad != safety.Invalid { os.exit(3i32) }

    // 4: a quiet table signals nowhere.
    var calm = safety.Table { a: 2u64, b: 50u64, c: 10u64, d: 100u64 }
    let (rs2, rs2_error) = safety.ror_signal(calm)
    if rs2_error != ok || rs2 { os.exit(4i32) }
    let (ps2, ps2_error) = safety.prr_signal(calm)
    if ps2_error != ok || ps2 { os.exit(4i32) }
    let (is2, is2_error) = safety.ic_signal(calm)
    if is2_error != ok || is2 { os.exit(4i32) }

    // 5: Apriori finds seven frequent sets; the rules at confidence 0.6 are
    // the two singletons splits plus the three-item splits.
    var masks: [11]u64 = zero
    masks[0usize] = 3u64
    masks[1usize] = 3u64
    masks[2usize] = 3u64
    masks[3usize] = 3u64
    masks[4usize] = 7u64
    masks[5usize] = 7u64
    masks[6usize] = 7u64
    masks[7usize] = 5u64
    masks[8usize] = 5u64
    masks[9usize] = 8u64
    masks[10usize] = 8u64
    var found: [16]u64 = zero
    var held: [16]usize = zero
    let (frequent, mine_error) = safety.apriori(masks[..], 3usize, found[..], held[..])
    if mine_error != ok || frequent != 7usize { os.exit(5i32) }
    if found[0usize] != 1u64 || held[0usize] != 9usize { os.exit(5i32) }
    if found[3usize] != 3u64 || held[3usize] != 7usize { os.exit(5i32) }
    if found[6usize] != 7u64 || held[6usize] != 3usize { os.exit(5i32) }
    if safety.support_of(masks[..], 8u64) != 2usize { os.exit(5i32) }
    var scratch_sets: [16]u64 = zero
    var scratch_held: [16]usize = zero
    var mined: [8]safety.Rule = zero
    let (rules, rules_error) = safety.apriori_rules(masks[..], 3usize, 0.6f64, mined[..], scratch_sets[..], scratch_held[..])
    if rules_error != ok || rules != 7usize { os.exit(5i32) }
    if mined[0usize].antecedent != 2u64 || mined[0usize].consequent != 1u64 { os.exit(5i32) }
    if !near(mined[0usize].confidence, 1.0f64, 0.000000001f64) { os.exit(5i32) }
    if mined[6usize].antecedent != 4u64 || mined[6usize].consequent != 3u64 { os.exit(5i32) }
    if !near(mined[6usize].confidence, 0.6f64, 0.000000001f64) { os.exit(5i32) }
    if !near(mined[6usize].lift, 0.9429f64, 0.001f64) { os.exit(5i32) }

    // 6: the mining refusals -- no support bar, no transactions, short
    // caller storage and a confidence outside [0, 1].
    let (_, nosupport) = safety.apriori(masks[..], 0usize, found[..], held[..])
    if nosupport != safety.Invalid { os.exit(6i32) }
    var spare: [1]u64 = zero
    let (_, empty_tx) = safety.apriori(spare[..0usize], 1usize, found[..], held[..])
    if empty_tx != safety.Invalid { os.exit(6i32) }
    var tight_sets: [2]u64 = zero
    var tight_held: [2]usize = zero
    let (partial, tight_error) = safety.apriori(masks[..], 3usize, tight_sets[..], tight_held[..])
    if tight_error != safety.TooSmall || partial != 2usize { os.exit(6i32) }
    var tight_rules: [2]safety.Rule = zero
    let (few, few_error) = safety.apriori_rules(masks[..], 3usize, 0.6f64, tight_rules[..], scratch_sets[..], scratch_held[..])
    if few_error != safety.TooSmall || few != 2usize { os.exit(6i32) }
    let (_, conf_bad) = safety.apriori_rules(masks[..], 3usize, 1.5f64, mined[..], scratch_sets[..], scratch_held[..])
    if conf_bad != safety.Invalid { os.exit(6i32) }

    try io.print("algo stat safety ok\n")
    ret ok
}
