// The D885 gap fillers across six modules, each against a Python reference in
// the scratchpad: `rand.reservoir_decayed`, `dist.normal_polar`,
// `importance_weights` and `copula_gaussian` (a PCG64 replica),
// `sat.encode_at_most`, `encode_pseudo_boolean` and `tseitin` (a truth table),
// `stat.test.ks`, `anderson_darling` and `shapiro_wilk` (SciPy),
// `timeseries.garch` and `hawkes` (the recursions), and `uuid.v5` (RFC
// vectors), `ulid`, `ulid_monotonic`, `snowflake` and `nanoid` (replicas).
// Each check exits with its own code.

use e.algo.rand
use e.algo.rand.dist as dist
use e.algo.sat
use e.algo.stat.test as test
use e.algo.timeseries
use e.algo.uuid
use e.io
use e.math
use e.math.special
use e.mem
use e.os
use e.str

type Normal = struct { mean: f64, sd: f64 }

fn normal_cdf(c: *Normal, x: f64) -> f64 { ret special.normal_cdf((x - c.mean) / c.sd) }
fn target_density(c: *Normal, x: f64) -> f64 { ret math.exp[f64](0.0f64 - x) }
fn proposal_density(c: *Normal, x: f64) -> f64 { ret 0.25f64 }

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

// The fixture's LCG: `u = (state >> 33) / 2^31`, replicated in the reference.
fn uniform(state: *u64) -> f64 {
    *state = *state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret f64(*state >> 33u32) / 2147483648.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: the decayed reservoir keeps the recent items (weight 1, time i, rate 0.2).
    var items: [8]u64 = zero
    var keys: [8]f64 = zero
    var res = rand.reservoir_decayed[u64](items[..], keys[..])
    var r = rand.pcg64(42u64, 54u64)
    var i = 0usize
    while i < 40usize {
        rand.reservoir_decayed_offer[u64](&res, &r, u64(i), 1.0f64, f64(i), 0.2f64)
        i += 1usize
    }
    let sample = rand.reservoir_weighted_sample[u64](&res)
    if sample.len != 8usize { os.exit(1i32) }
    var sum = 0u64
    var squares = 0u64
    i = 0usize
    while i < 8usize {
        sum += sample[i]
        squares += sample[i] * sample[i]
        i += 1usize
    }
    if sum != 263u64 || squares != 8881u64 { os.exit(1i32) }

    // 2: the polar pair against the replica, and its first value is `normal`'s.
    r = rand.pcg64(7u64, 11u64)
    let (p0, p1) = dist.normal_polar(&r)
    if !near(p0, 0.0f64 - 2.3851539715368455f64, 1.0e-12f64) || !near(p1, 0.0f64 - 0.8941037220770837f64, 1.0e-12f64) { os.exit(2i32) }
    r = rand.pcg64(7u64, 11u64)
    if dist.normal(&r) != p0 { os.exit(2i32) }

    // 3: importance weights of 16 uniform proposals on [0, 4) against exp(-x).
    var state = 99u64
    var xs: [16]f64 = zero
    i = 0usize
    while i < 16usize {
        xs[i] = uniform(&state) * 4.0f64
        i += 1usize
    }
    var weights: [16]f64 = zero
    var ctx = Normal { mean: 0.0f64, sd: 1.0f64 }
    let (ess, ess_error) = dist.importance_weights[Normal](xs[..], &ctx, target_density, proposal_density, weights[..])
    if ess_error != ok || !near(ess, 6.712062897649309f64, 1.0e-9f64) { os.exit(3i32) }
    if !near(weights[0usize], 0.14178188241917747f64, 1.0e-12f64) || !near(weights[15usize], 0.011224110177373306f64, 1.0e-12f64) { os.exit(3i32) }
    let (_, short_error) = dist.importance_weights[Normal](xs[..], &ctx, target_density, proposal_density, weights[..15usize])
    if short_error != dist.TooSmall { os.exit(3i32) }

    // 4: a Gaussian copula with rho 0.7: uniform marginals whose correlation is
    // (6 / pi) asin(rho / 2) = 0.6829 over 4,000 draws, the first draw exact.
    var corr: [4]f64 = zero
    corr[0usize] = 1.0f64
    corr[1usize] = 0.7f64
    corr[2usize] = 0.7f64
    corr[3usize] = 1.0f64
    var factor: [4]f64 = zero
    if dist.cholesky(corr[..], 2usize, factor[..]) != ok { os.exit(4i32) }
    r = rand.pcg64(3u64, 5u64)
    var pair: [2]f64 = zero
    var scratch4: [4]f64 = zero
    var sx = 0.0f64
    var sy = 0.0f64
    var sxx = 0.0f64
    var syy = 0.0f64
    var sxy = 0.0f64
    i = 0usize
    while i < 4000usize {
        if dist.copula_gaussian(&r, factor[..], 2usize, pair[..], scratch4[..]) != ok { os.exit(4i32) }
        if i == 0usize && (!near(pair[0usize], 0.7602205062626191f64, 1.0e-12f64) || !near(pair[1usize], 0.45705393048639353f64, 1.0e-12f64)) { os.exit(4i32) }
        if pair[0usize] <= 0.0f64 || pair[0usize] >= 1.0f64 || pair[1usize] <= 0.0f64 || pair[1usize] >= 1.0f64 { os.exit(4i32) }
        sx += pair[0usize]
        sy += pair[1usize]
        sxx += pair[0usize] * pair[0usize]
        syy += pair[1usize] * pair[1usize]
        sxy += pair[0usize] * pair[1usize]
        i += 1usize
    }
    let n4 = 4000.0f64
    let rho = (sxy - sx * sy / n4) / math.sqrt[f64]((sxx - sx * sx / n4) * (syy - sy * sy / n4))
    if !near(rho, 0.6854793479421373f64, 1.0e-9f64) || !near(rho, 0.6829105038240887f64, 0.05f64) { os.exit(4i32) }
    if dist.copula_gaussian(&r, factor[..], 2usize, pair[..], scratch4[..3usize]) != dist.TooSmall { os.exit(4i32) }

    // 5: the planned encodings: at most two of five, 2a + 3b + 4c <= 5, and the
    // Tseitin tree of (x1 and x2) xor (not x3 or x4) against its truth table.
    var literals: [512]i32 = zero
    var starts: [128]usize = zero
    var assignment: [64]i8 = zero
    var trail: [64]u32 = zero
    var level: [64]u32 = zero
    var flipped: [65]u8 = zero
    var learned: [512]i32 = zero
    var learned_starts: [64]usize = zero
    let (f0, f_error) = sat.cnf(literals[..], starts[..], 5usize)
    if f_error != ok { os.exit(5i32) }
    var f = f0
    var five: [5]i32 = zero
    i = 0usize
    while i < 5usize {
        five[i] = i32(i + 1usize)
        i += 1usize
    }
    if sat.encode_at_most(&f, five[..], 2usize) != ok { os.exit(5i32) }
    if sat.clause1(&f, 1i32) != ok || sat.clause1(&f, 2i32) != ok { os.exit(5i32) }
    if sat.solve(&f, assignment[..], trail[..], level[..], flipped[..], learned[..], learned_starts[..], 10000usize) != ok { os.exit(5i32) }
    if assignment[2usize] != 0i8 - 1i8 || assignment[3usize] != 0i8 - 1i8 || assignment[4usize] != 0i8 - 1i8 { os.exit(5i32) }
    if sat.clause1(&f, 3i32) != ok { os.exit(5i32) }
    if sat.solve(&f, assignment[..], trail[..], level[..], flipped[..], learned[..], learned_starts[..], 10000usize) != sat.Unsatisfiable { os.exit(5i32) }
    let (g0, g_error) = sat.cnf(literals[..], starts[..], 3usize)
    if g_error != ok { os.exit(5i32) }
    var g = g0
    var coefficients: [3]u32 = zero
    coefficients[0usize] = 2u32
    coefficients[1usize] = 3u32
    coefficients[2usize] = 4u32
    var memo: [32]i32 = zero
    if sat.encode_pseudo_boolean(&g, five[..3usize], coefficients[..], 5u32, memo[..]) != ok { os.exit(5i32) }
    if sat.clause1(&g, 3i32) != ok { os.exit(5i32) }
    if sat.solve(&g, assignment[..], trail[..], level[..], flipped[..], learned[..], learned_starts[..], 10000usize) != ok { os.exit(5i32) }
    if assignment[0usize] != 0i8 - 1i8 || assignment[1usize] != 0i8 - 1i8 || assignment[2usize] != 1i8 { os.exit(5i32) }
    // Nodes 0..3 are the variables, 4 = 0 and 1, 5 = not 2, 6 = 5 or 3, 7 = 4 xor 6.
    var kind: [8]sat.Gate = zero
    var left: [8]i32 = zero
    var right: [8]i32 = zero
    i = 0usize
    while i < 4usize {
        kind[i] = .Var
        left[i] = i32(i + 1usize)
        i += 1usize
    }
    kind[4usize] = .And
    left[4usize] = 0i32
    right[4usize] = 1i32
    kind[5usize] = .Not
    left[5usize] = 2i32
    kind[6usize] = .Or
    left[6usize] = 5i32
    right[6usize] = 3i32
    kind[7usize] = .Xor
    left[7usize] = 4i32
    right[7usize] = 6i32
    let (h0, h_error) = sat.cnf(literals[..], starts[..], 4usize)
    if h_error != ok { os.exit(5i32) }
    var h = h0
    let (root, root_error) = sat.tseitin(&h, kind[..], left[..], right[..], 7usize)
    if root_error != ok || root != 7i32 || h.clauses != 10usize { os.exit(5i32) }
    let base = h.clauses
    var mask = 0u32
    var assign = 0usize
    while assign < 16usize {
        h.clauses = base
        var v = 0usize
        while v < 4usize {
            var lit = i32(v + 1usize)
            if ((assign >> u32(v)) & 1usize) == 0usize { lit = 0i32 - lit }
            if sat.clause1(&h, lit) != ok { os.exit(5i32) }
            v += 1usize
        }
        if sat.clause1(&h, root) != ok { os.exit(5i32) }
        let verdict = sat.solve(&h, assignment[..], trail[..], level[..], flipped[..], learned[..], learned_starts[..], 10000usize)
        if verdict == ok { mask = mask | (1u32 << u32(assign)) } else if verdict != sat.Unsatisfiable { os.exit(5i32) }
        assign += 1usize
    }
    if mask != 30599u32 { os.exit(5i32) }
    let (_, bad_root) = sat.tseitin(&h, kind[..], left[..], right[..], 8usize)
    if bad_root != sat.Invalid { os.exit(5i32) }

    // 6: one-sample KS of 20 uniforms on [-2, 2] against the standard normal.
    state = 7u64
    var x: [20]f64 = zero
    i = 0usize
    while i < 20usize {
        x[i] = uniform(&state) * 4.0f64 - 2.0f64
        i += 1usize
    }
    var work: [20]f64 = zero
    i = 0usize
    while i < 20usize {
        work[i] = x[i]
        i += 1usize
    }
    let (ks, ks_error) = test.ks[Normal](work[..], &ctx, normal_cdf)
    if ks_error != ok || !near(ks.statistic, 0.2183286201667045f64, 1.0e-12f64) || !near(ks.p_value, 0.2961666864099259f64, 1.0e-9f64) { os.exit(6i32) }
    let (_, empty_error) = test.ks[Normal](work[..0usize], &ctx, normal_cdf)
    if empty_error != test.Invalid { os.exit(6i32) }

    // 7: Anderson-Darling against the fitted normal, SciPy's statistic and the
    // D Agostino-Stephens p-value.
    var fitted = Normal { mean: 0.0f64 - 0.07234519198536873f64, sd: 1.286753487930473f64 }
    let (ad, ad_error) = test.anderson_darling[Normal](work[..], &fitted, normal_cdf)
    if ad_error != ok || !near(ad.statistic, 0.6735355082549894f64, 1.0e-9f64) || !near(ad.p_value, 0.06665949862068934f64, 1.0e-9f64) { os.exit(7i32) }

    // 8: Shapiro-Wilk at n = 3, 5, 8, 20 and 50 against SciPy (W to 1e-6, p to 1e-4).
    var coefficients8: [26]f64 = zero
    var want_w: [5]f64 = zero
    var want_p: [5]f64 = zero
    var sizes: [5]usize = zero
    sizes[0usize] = 3usize
    want_w[0usize] = 0.8286135100879067f64
    want_p[0usize] = 0.18481218182902914f64
    sizes[1usize] = 5usize
    want_w[1usize] = 0.8334757527012966f64
    want_p[1usize] = 0.1476798442210333f64
    sizes[2usize] = 8usize
    want_w[2usize] = 0.8510323778745592f64
    want_p[2usize] = 0.09758928425406099f64
    sizes[3usize] = 20usize
    want_w[3usize] = 0.8998508711229157f64
    want_p[3usize] = 0.04097413786862044f64
    sizes[4usize] = 50usize
    want_w[4usize] = 0.9245442004149342f64
    want_p[4usize] = 0.003455378178013099f64
    var x50: [50]f64 = zero
    state = 11u64
    i = 0usize
    while i < 50usize {
        x50[i] = uniform(&state) * 4.0f64 - 2.0f64
        i += 1usize
    }
    var c = 0usize
    while c < 5usize {
        i = 0usize
        while i < 20usize {
            work[i] = x[i]
            i += 1usize
        }
        var subject = x50[..]
        if c < 4usize { subject = work[..sizes[c]] }
        let (sw, sw_error) = test.shapiro_wilk(subject, coefficients8[..])
        if sw_error != ok || !near(sw.statistic, want_w[c], 1.0e-6f64) || !near(sw.p_value, want_p[c], 1.0e-4f64) { os.exit(8i32) }
        c += 1usize
    }
    let (_, two_error) = test.shapiro_wilk(work[..2usize], coefficients8[..])
    if two_error != test.Invalid { os.exit(8i32) }
    let (_, tight_error) = test.shapiro_wilk(x50[..], coefficients8[..25usize])
    if tight_error != test.TooSmall { os.exit(8i32) }

    // 9: the GARCH variance path and the Hawkes intensities at the events of a
    // simulated path, both against the replica.
    var returns: [30]f64 = zero
    state = 5u64
    i = 0usize
    while i < 30usize {
        returns[i] = uniform(&state) * 2.0f64 - 1.0f64
        i += 1usize
    }
    var path: [30]f64 = zero
    if timeseries.garch(0.1f64, 0.2f64, 0.7f64, returns[..], path[..]) != ok { os.exit(9i32) }
    var total = 0.0f64
    i = 0usize
    while i < 30usize {
        total += path[i]
        i += 1usize
    }
    if !near(total, 16.207446563282375f64, 1.0e-12f64) || !near(path[29usize], 0.4746577144297784f64, 1.0e-12f64) { os.exit(9i32) }
    if timeseries.garch(0.1f64, 0.2f64, 0.7f64, returns[..], path[..29usize]) != timeseries.TooSmall { os.exit(9i32) }
    var events: [200]f64 = zero
    r = rand.pcg64(9u64, 9u64)
    let (count, simulate_error) = timeseries.hawkes_simulate(1.0f64, 0.5f64, 1.0f64, 50.0f64, &r, events[..])
    if simulate_error != ok || count != 93usize || !near(events[92usize], 49.80569839162228f64, 1.0e-9f64) { os.exit(9i32) }
    var lambdas: [200]f64 = zero
    if timeseries.hawkes(1.0f64, 0.5f64, 1.0f64, events[..count], lambdas[..]) != ok { os.exit(9i32) }
    total = 0.0f64
    i = 0usize
    while i < count {
        total += lambdas[i]
        i += 1usize
    }
    if !near(total, 194.40566923180995f64, 1.0e-9f64) || !near(lambdas[92usize], 1.148596976334151f64, 1.0e-12f64) { os.exit(9i32) }
    if timeseries.hawkes(1.0f64, 0.5f64, 1.0f64, events[..count], lambdas[..10usize]) != timeseries.TooSmall { os.exit(9i32) }

    // 10: version 5 against the RFC's DNS vector and Python's URL one.
    var scratch: [64]u8 = zero
    var text: [36]u8 = zero
    let (dns, dns_error) = uuid.v5(uuid.namespace_dns(), "www.example.com", scratch[..])
    if dns_error != ok || uuid.version(dns) != 5u8 || uuid.variant(dns) != 1u8 { os.exit(10i32) }
    let (dns_text, dns_text_error) = uuid.format(dns, text[..])
    if dns_text_error != ok || !str.eq(dns_text, "2ed6657d-e927-568b-95e1-2665a8aea6a2") { os.exit(10i32) }
    let (url, url_error) = uuid.v5(uuid.namespace_url(), "https://example.org/", scratch[..])
    let (url_text, _) = uuid.format(url, text[..])
    if url_error != ok || !str.eq(url_text, "527dda32-a0de-5105-a042-cb475b5f7d11") { os.exit(10i32) }
    let (_, cramped) = uuid.v5(uuid.namespace_dns(), "www.example.com", scratch[..30usize])
    if cramped != uuid.Invalid { os.exit(10i32) }

    // 11: ULIDs against the replica: the largest, one draw, its monotonic
    // successor in the same millisecond, and a fresh one a millisecond later.
    var ones: [16]u8 = zero
    i = 0usize
    while i < 16usize {
        ones[i] = 255u8
        i += 1usize
    }
    var top: uuid.Uuid = zero
    top.bytes = ones
    let (top_text, top_error) = uuid.ulid_format(top, text[..])
    if top_error != ok || !str.eq(top_text, "7ZZZZZZZZZZZZZZZZZZZZZZZZZ") { os.exit(11i32) }
    r = rand.pcg64(1u64, 2u64)
    let (first, first_error) = uuid.ulid(1469918176385u64, &r)
    let (first_text, _) = uuid.ulid_format(first, text[..])
    if first_error != ok || !str.eq(first_text, "01ARYZ6S414ZANXV7EGBEBDYJZ") { os.exit(11i32) }
    let (first_hex, _) = uuid.format(first, text[..])
    if !str.eq(first_hex, "01563df3-6481-27d5-5eec-ee82dcb6fa5f") { os.exit(11i32) }
    let (second, second_error) = uuid.ulid_monotonic(first, 1469918176385u64, &r)
    let (second_text, _) = uuid.ulid_format(second, text[..])
    if second_error != ok || !str.eq(second_text, "01ARYZ6S414ZANXV7EGBEBDYK0") { os.exit(11i32) }
    if uuid.uuid_cmp(first, second) >= 0i32 { os.exit(11i32) }
    let (third, third_error) = uuid.ulid_monotonic(second, 1469918176386u64, &r)
    let (third_text, _) = uuid.ulid_format(third, text[..])
    if third_error != ok || !str.eq(third_text, "01ARYZ6S42QB598M27C8THNFMT") { os.exit(11i32) }
    if uuid.uuid_cmp(second, third) >= 0i32 { os.exit(11i32) }
    let (_, overflow) = uuid.ulid_monotonic(top, 1u64, &r)
    if overflow != uuid.Invalid { os.exit(11i32) }
    let (_, late) = uuid.ulid(281474976710656u64, &r)
    if late != uuid.Invalid { os.exit(11i32) }
    let (_, narrow) = uuid.ulid_format(first, text[..25usize])
    if narrow != uuid.Invalid { os.exit(11i32) }

    // 12: Snowflake ids: two in one millisecond, a later one, the rollover
    // after 4,096 in a millisecond, and the clock then catching up.
    let (s0, s_error) = uuid.snowflake(1288834974657u64, 5u64)
    if s_error != ok { os.exit(12i32) }
    var s = s0
    let (id0, e0) = uuid.snowflake_next(&s, 1288834975657u64)
    let (id1, e1) = uuid.snowflake_next(&s, 1288834975657u64)
    let (id2, e2) = uuid.snowflake_next(&s, 1288834975662u64)
    if e0 != ok || e1 != ok || e2 != ok || id0 != 4194324480u64 || id1 != 4194324481u64 || id2 != 4215296000u64 { os.exit(12i32) }
    i = 0usize
    while i < 4095usize {
        let (_, e_loop) = uuid.snowflake_next(&s, 1288834975662u64)
        if e_loop != ok { os.exit(12i32) }
        i += 1usize
    }
    let (id3, e3) = uuid.snowflake_next(&s, 1288834975662u64)
    let (id4, e4) = uuid.snowflake_next(&s, 1288834975663u64)
    if e3 != ok || e4 != ok || id3 != 4219490304u64 || id4 != 4219490305u64 { os.exit(12i32) }
    let (_, backwards) = uuid.snowflake_next(&s, 1288834975000u64)
    if backwards != uuid.Invalid { os.exit(12i32) }
    let (_, wide_worker) = uuid.snowflake(0u64, 1024u64)
    if wide_worker != uuid.Invalid { os.exit(12i32) }

    // 13: a Nano ID from the replica's bytes.
    r = rand.pcg64(4u64, 4u64)
    var id: [21]u8 = zero
    let nano = uuid.nanoid(&r, id[..])
    if nano.len != 21usize || !str.eq(nano, "tW26-yVpR3WhqfSE4f4u6") { os.exit(13i32) }

    try io.print("algo gaps b ok\n")
    ret ok
}
