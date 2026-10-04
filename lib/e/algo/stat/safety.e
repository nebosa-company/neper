// Pharmacovigilance signal detection over FAERS-style counts: the reporting
// odds ratio, the proportional reporting ratio and the BCPNN information
// component with Wald-style 95% intervals and their standard signal rules,
// plus Apriori frequent-itemset and association-rule mining over comedication
// transactions for drug-drug interaction screening.
//
// A `Table` is the 2x2 `[[a, b], [c, d]]` of (drug, event) against
// (drug, other), (other drug, event) and (other, other) report counts. Scores
// answer a `Score` of estimate with lower and upper 95% bounds; a zero cell
// where a ratio needs it is `Invalid` (add an explicit continuity correction
// upstream instead of a silent one). Transactions are `u64` bitmasks over at
// most 64 items; mining answers frequent masks with supports and `Rule`
// records with support, confidence and lift, all in caller storage.

use e.math

type Table = struct { a: u64, b: u64, c: u64, d: u64 }
type Score = struct { estimate: f64, lower: f64, upper: f64 }
type Rule = struct { antecedent: u64, consequent: u64, support: usize, confidence: f64, lift: f64 }
error TooSmall
error Invalid

// The Pearson chi-square of the 2x2 `t` (no continuity correction, the form
// the Evans PRR criteria use); an empty or degenerate table is `Invalid`.
fn chi_square_2x2(t: Table) -> (f64, err) {
    let n = f64(t.a + t.b + t.c + t.d)
    if n == 0.0f64 { ret (0.0f64, Invalid) }
    let row1 = f64(t.a + t.b)
    let row2 = f64(t.c + t.d)
    let col1 = f64(t.a + t.c)
    let col2 = f64(t.b + t.d)
    if row1 == 0.0f64 || row2 == 0.0f64 || col1 == 0.0f64 || col2 == 0.0f64 { ret (0.0f64, Invalid) }
    var statistic = 0.0f64
    let cells = [4]f64 { f64(t.a), f64(t.b), f64(t.c), f64(t.d) }
    let expected = [4]f64 { row1 * col1 / n, row1 * col2 / n, row2 * col1 / n, row2 * col2 / n }
    var i = 0usize
    while i < 4usize {
        let gap = cells[i] - expected[i]
        statistic += gap * gap / expected[i]
        i += 1usize
    }
    ret (statistic, ok)
}

// The reporting odds ratio `a d / (b c)` with the Woolf logit interval from
// `sqrt(1/a + 1/b + 1/c + 1/d)`; any zero cell is `Invalid`.
fn ror(t: Table) -> (Score, err) {
    if t.a == 0u64 || t.b == 0u64 || t.c == 0u64 || t.d == 0u64 { ret (zero, Invalid) }
    let estimate = f64(t.a) * f64(t.d) / (f64(t.b) * f64(t.c))
    let se = math.sqrt[f64](1.0f64 / f64(t.a) + 1.0f64 / f64(t.b) + 1.0f64 / f64(t.c) + 1.0f64 / f64(t.d))
    let middle = math.log[f64](estimate)
    ret (Score { estimate: estimate, lower: math.exp[f64](middle - 1.96f64 * se), upper: math.exp[f64](middle + 1.96f64 * se) }, ok)
}

// The proportional reporting ratio `a (c + d) / (c (a + b))` with its logit
// interval from `sqrt(1/a - 1/(a+b) + 1/c - 1/(c+d))`; a zero `a` or `c` or
// an empty row is `Invalid`.
fn prr(t: Table) -> (Score, err) {
    if t.a == 0u64 || t.c == 0u64 || t.a + t.b == 0u64 || t.c + t.d == 0u64 { ret (zero, Invalid) }
    let estimate = f64(t.a) * f64(t.c + t.d) / (f64(t.c) * f64(t.a + t.b))
    let se = math.sqrt[f64](1.0f64 / f64(t.a) - 1.0f64 / f64(t.a + t.b) + 1.0f64 / f64(t.c) - 1.0f64 / f64(t.c + t.d))
    let middle = math.log[f64](estimate)
    ret (Score { estimate: estimate, lower: math.exp[f64](middle - 1.96f64 * se), upper: math.exp[f64](middle + 1.96f64 * se) }, ok)
}

// The ROR signal: at least three drug-event reports and the lower 95% bound
// above one.
fn ror_signal(t: Table) -> (bool, err) {
    let (s, score_error) = ror(t)
    if score_error != ok { ret (false, score_error) }
    ret (t.a >= 3u64 && s.lower > 1.0f64, ok)
}

// The Evans PRR signal: at least three reports, an estimate of at least two
// and a chi-square of at least four.
fn prr_signal(t: Table) -> (bool, err) {
    let (s, score_error) = prr(t)
    if score_error != ok { ret (false, score_error) }
    let (chi, chi_error) = chi_square_2x2(t)
    if chi_error != ok { ret (false, chi_error) }
    ret (t.a >= 3u64 && s.estimate >= 2.0f64 && chi >= 4.0f64, ok)
}

// The BCPNN information component (Noren et al. 2006) with unit prior weight:
// `estimate` its posterior expectation in bits, `lower`/`upper` two posterior
// standard deviations out; an empty table is `Invalid`.
fn ic(t: Table) -> (Score, err) {
    let fa = f64(t.a)
    let fb = f64(t.b)
    let fc = f64(t.c)
    let fd = f64(t.d)
    let n = fa + fb + fc + fd
    if n == 0.0f64 { ret (zero, Invalid) }
    let gab = fa + fb + 1.0f64
    let gac = fa + fc + 1.0f64
    let gam = (n + 2.0f64) * (n + 2.0f64) / (gab * gac)
    let estimate = math.log2[f64]((fa + 1.0f64) * (n + 2.0f64) * (n + 2.0f64) / ((n + gam) * gab * gac))
    let ln2 = math.log[f64](2.0f64)
    var variance = ((n - fa + gam - 1.0f64) / ((fa + 1.0f64) * (1.0f64 + n + gam)) + (n - (fa + fb) + 1.0f64) / (gab * (3.0f64 + n)) + (n - (fa + fc) + 1.0f64) / (gac * (3.0f64 + n))) / (ln2 * ln2)
    if variance < 0.0f64 { variance = 0.0f64 }
    let sd = math.sqrt[f64](variance)
    ret (Score { estimate: estimate, lower: estimate - 2.0f64 * sd, upper: estimate + 2.0f64 * sd }, ok)
}

// The BCPNN signal: the lower credibility bound above zero.
fn ic_signal(t: Table) -> (bool, err) {
    let (s, score_error) = ic(t)
    if score_error != ok { ret (false, score_error) }
    ret (s.lower > 0.0f64, ok)
}

// The population count of `mask`.
fn bit_count(mask: u64) -> usize {
    var count = 0usize
    var rest = mask
    while rest != 0u64 {
        if (rest & 1u64) == 1u64 { count += 1usize }
        rest = rest >> 1u64
    }
    ret count
}

// The number of transactions holding every item of `mask`.
fn support_of(masks: []const u64, mask: u64) -> usize {
    var count = 0usize
    var i = 0usize
    while i < masks.len {
        if (masks[i] & mask) == mask { count += 1usize }
        i += 1usize
    }
    ret count
}

// Whether `mask` already sits in the first `count` entries of `masks`.
fn mask_seen(masks: []const u64, count: usize, mask: u64) -> bool {
    var i = 0usize
    while i < count {
        if masks[i] == mask { ret true }
        i += 1usize
    }
    ret false
}

// Apriori frequent itemsets over `masks` at absolute `min_support`: level by
// level from the singletons, joining pairs whose union adds one item and
// keeping unions whose every submask is already frequent. `itemsets` and
// `supports` are parallel caller arrays sharing their capacity; answers the
// frequent count. A zero or unreachable `min_support` is `Invalid`; overflow
// past the caller capacity is `TooSmall`.
fn apriori(masks: []const u64, min_support: usize, itemsets: []u64, supports: []usize) -> (usize, err) {
    let n = masks.len
    if n == 0usize || min_support == 0usize { ret (0usize, Invalid) }
    if supports.len < itemsets.len { ret (0usize, TooSmall) }
    let cap = itemsets.len
    var found = 0usize
    var b = 0usize
    while b < 64usize {
        let bit = 1u64 << u64(b)
        let held = support_of(masks, bit)
        if held >= min_support {
            if found >= cap { ret (found, TooSmall) }
            itemsets[found] = bit
            supports[found] = held
            found += 1usize
        }
        b += 1usize
    }
    var level_start = 0usize
    var level_count = found
    var width = 1usize
    while level_count > 1usize {
        var next_start = found
        var i = level_start
        while i < next_start {
            var j = i + 1usize
            while j < next_start {
                let joined = itemsets[i] | itemsets[j]
                if bit_count(joined) == width + 1usize && !mask_seen(itemsets, found, joined) {
                    var whole = true
                    var drop = joined
                    while drop != 0u64 && whole {
                        let vessel = drop & (0u64 -% drop)
                        if !mask_seen(itemsets[level_start..next_start], level_count, joined - vessel) { whole = false }
                        drop = drop - vessel
                    }
                    if whole {
                        let held = support_of(masks, joined)
                        if held >= min_support {
                            if found >= cap { ret (found, TooSmall) }
                            itemsets[found] = joined
                            supports[found] = held
                            found += 1usize
                        }
                    }
                }
                j += 1usize
            }
            i += 1usize
        }
        if found == next_start { ret (found, ok) }
        level_start = next_start
        level_count = found - next_start
        width += 1usize
    }
    ret (found, ok)
}

// Apriori association rules: every frequent itemset of two or more items
// (mined into `scratch_items`/`scratch_sups`) splits over each non-empty
// proper submask, keeping splits whose confidence reaches `min_confidence`.
// Itemsets above twenty items skip rule duty (their submask walk is
// exponential). `rules` is caller storage; answers the rule count. Confidence
// outside `[0, 1]` is `Invalid`; overflow past `rules` (or the scratch) is
// `TooSmall`.
fn apriori_rules(masks: []const u64, min_support: usize, min_confidence: f64, rules: []Rule, scratch_items: []u64, scratch_sups: []usize) -> (usize, err) {
    if min_confidence < 0.0f64 || min_confidence > 1.0f64 { ret (0usize, Invalid) }
    let (found, mine_error) = apriori(masks, min_support, scratch_items, scratch_sups)
    if mine_error != ok { ret (0usize, mine_error) }
    let n = f64(masks.len)
    var made = 0usize
    var z = 0usize
    while z < found {
        let whole = scratch_items[z]
        let held_whole = scratch_sups[z]
        let width = bit_count(whole)
        if width >= 2usize && width <= 20usize {
            var sub = (whole - 1u64) & whole
            while sub != 0u64 {
                let held_sub = support_of(masks, sub)
                if held_sub > 0usize {
                    let confidence = f64(held_whole) / f64(held_sub)
                    if confidence >= min_confidence {
                        if made >= rules.len { ret (made, TooSmall) }
                        let rest = whole - sub
                        let held_rest = support_of(masks, rest)
                        var lift = 0.0f64
                        if held_rest > 0usize { lift = confidence / (f64(held_rest) / n) }
                        rules[made] = Rule { antecedent: sub, consequent: rest, support: held_whole, confidence: confidence, lift: lift }
                        made += 1usize
                    }
                }
                sub = (sub - 1u64) & whole
            }
        }
        z += 1usize
    }
    ret (made, ok)
}
