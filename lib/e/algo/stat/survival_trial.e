// Time-to-event trial methods over caller storage: Kaplan-Meier curves,
// the unweighted log-rank test, Cox proportional hazards by Newton-Raphson
// (Breslow ties), Lan-DeMets alpha-spending functions, Simon two-stage
// Phase-II designs by exact exhaustive search, likelihood continual
// reassessment for dose finding, and the Farrington-Manning non-inferiority
// test with its constrained maximum-likelihood estimates.
//
// Event indicators are `u8` (1 an event, 0 censored); anything else is
// `Invalid`. Times tie by exact equality. Rows are observed cases.

use e.math
use e.math.special

error TooSmall
error Singular
error Invalid

type Result = struct { statistic: f64, p_value: f64 }
type SimonDesign = struct { n1: usize, r1: usize, n: usize, r: usize }

// Solve the dense `n × n` system in place by Gaussian elimination with
// partial pivoting; the answer replaces `rhs`. `Singular` below 1e-12 pivots.
fn survival_solve(matrix: []f64, rhs: []f64, n: usize) -> err {
    var column = 0usize
    while column < n {
        var pivot = column
        var row = column + 1usize
        while row < n {
            if math.abs[f64](matrix[row * n + column]) > math.abs[f64](matrix[pivot * n + column]) { pivot = row }
            row += 1usize
        }
        if math.abs[f64](matrix[pivot * n + column]) < 1.0e-12f64 { ret Singular }
        if pivot != column {
            var c = 0usize
            while c < n {
                let t = matrix[column * n + c]
                matrix[column * n + c] = matrix[pivot * n + c]
                matrix[pivot * n + c] = t
                c += 1usize
            }
            let t = rhs[column]
            rhs[column] = rhs[pivot]
            rhs[pivot] = t
        }
        row = column + 1usize
        while row < n {
            let factor = matrix[row * n + column] / matrix[column * n + column]
            if factor != 0.0f64 {
                var c = column
                while c < n {
                    matrix[row * n + c] -= factor * matrix[column * n + c]
                    c += 1usize
                }
                rhs[row] -= factor * rhs[column]
            }
            row += 1usize
        }
        column += 1usize
    }
    var i = n
    while i > 0usize {
        i -= 1usize
        var s = rhs[i]
        var c = i + 1usize
        while c < n {
            s -= matrix[i * n + c] * rhs[c]
            c += 1usize
        }
        rhs[i] = s / matrix[i * n + i]
    }
    ret ok
}

// The Kaplan-Meier curve: `order` (caller scratch, `n` indices) sorts the
// sample by time, then each distinct event time records its time, the
// survival probability, and the number at risk; censored-only times shrink
// the risk set without a record. Answers the record count; every output
// needs room for `n` entries.
fn kaplan_meier(times: []const f64, events: []const u8, n: usize, out_times: []f64, out_survival: []f64, out_risk: []usize, order: []usize) -> (usize, err) {
    if times.len < n || events.len < n || out_times.len < n || out_survival.len < n || out_risk.len < n || order.len < n { ret (0usize, TooSmall) }
    if n == 0usize { ret (0usize, Invalid) }
    var i = 0usize
    while i < n {
        if events[i] != 0u8 && events[i] != 1u8 { ret (0usize, Invalid) }
        order[i] = i
        i += 1usize
    }
    i = 1usize
    while i < n {
        var j = i
        while j > 0usize && times[order[j]] < times[order[j - 1usize]] {
            let swap = order[j]
            order[j] = order[j - 1usize]
            order[j - 1usize] = swap
            j -= 1usize
        }
        i += 1usize
    }
    var survival = 1.0f64
    var risk = n
    var records = 0usize
    i = 0usize
    while i < n {
        let t = times[order[i]]
        var deaths = 0usize
        var tied = 0usize
        while i + tied < n && times[order[i + tied]] == t {
            if events[order[i + tied]] == 1u8 { deaths += 1usize }
            tied += 1usize
        }
        if deaths > 0usize {
            survival = survival * (1.0f64 - f64(deaths) / f64(risk))
            out_times[records] = t
            out_survival[records] = survival
            out_risk[records] = risk
            records += 1usize
        }
        risk -= tied
        i += tied
    }
    ret (records, ok)
}

// The unweighted (Mantel-Cox) log-rank test of two samples: the score over
// pooled distinct event times with the hypergeometric variance, the
// chi-squared statistic on one degree of freedom, and its p-value. Event
// times are swept in order by repeated scans, so no sorting scratch is
// needed. With no events at all the statistic is 0 with p-value 1.
fn log_rank(ta: []const f64, ea: []const u8, na: usize, tb: []const f64, eb: []const u8, nb: usize) -> (Result, err) {
    if ta.len < na || ea.len < na || tb.len < nb || eb.len < nb { ret (zero, TooSmall) }
    if na == 0usize || nb == 0usize { ret (zero, Invalid) }
    var i = 0usize
    while i < na {
        if ea[i] != 0u8 && ea[i] != 1u8 { ret (zero, Invalid) }
        i += 1usize
    }
    i = 0usize
    while i < nb {
        if eb[i] != 0u8 && eb[i] != 1u8 { ret (zero, Invalid) }
        i += 1usize
    }
    var score = 0.0f64
    var variance = 0.0f64
    var have_floor = false
    var floor = 0.0f64
    while true {
        var t = 0.0f64
        var have = false
        i = 0usize
        while i < na {
            if ea[i] == 1u8 && (!have_floor || ta[i] > floor) && (!have || ta[i] < t) {
                t = ta[i]
                have = true
            }
            i += 1usize
        }
        i = 0usize
        while i < nb {
            if eb[i] == 1u8 && (!have_floor || tb[i] > floor) && (!have || tb[i] < t) {
                t = tb[i]
                have = true
            }
            i += 1usize
        }
        if !have { break }
        var risk_a = 0usize
        var deaths_a = 0usize
        i = 0usize
        while i < na {
            if !(ta[i] < t) {
                risk_a += 1usize
                if ta[i] == t && ea[i] == 1u8 { deaths_a += 1usize }
            }
            i += 1usize
        }
        var risk_b = 0usize
        var deaths_b = 0usize
        i = 0usize
        while i < nb {
            if !(tb[i] < t) {
                risk_b += 1usize
                if tb[i] == t && eb[i] == 1u8 { deaths_b += 1usize }
            }
            i += 1usize
        }
        let risk = risk_a + risk_b
        let deaths = deaths_a + deaths_b
        score += f64(deaths_a) - f64(deaths) * f64(risk_a) / f64(risk)
        if risk > 1usize {
            variance += f64(risk_a) * f64(risk_b) * f64(deaths) * f64(risk - deaths) / (f64(risk) * f64(risk) * f64(risk - 1usize))
        }
        have_floor = true
        floor = t
    }
    if variance <= 0.0f64 { ret (Result { statistic: 0.0f64, p_value: 1.0f64 }, ok) }
    let statistic = score * score / variance
    ret (Result { statistic: statistic, p_value: 1.0f64 - special.chi_squared_cdf(statistic, 1.0f64) }, ok)
}

// Cox proportional hazards with `p` covariates by Newton-Raphson (Breslow
// ties, ties joining the risk set before contributing): from zero,
// Fisher steps to 1e-10 in the largest step (at most 100 rounds). Answers
// the rounds taken, the coefficients in `beta`, and their model-based
// covariance. `fscratch.len >= n + 3 * p * p + 3 * p` holds hazards, score
// and information temporaries, the step, the solve workspace, and the risk
// accumulators; `iscratch.len >= n` the time order. `Singular` when nothing
// is estimable (no events among them).
fn cox_ph(times: []const f64, events: []const u8, x: []const f64, n: usize, p: usize, beta: []f64, covariance: []f64, fscratch: []f64, iscratch: []usize) -> (u32, err) {
    if times.len < n || events.len < n || x.len < n * p || beta.len < p || covariance.len < p * p || fscratch.len < n + 3usize * p * p + 3usize * p || iscratch.len < n { ret (0u32, TooSmall) }
    if n == 0usize || p == 0usize { ret (0u32, Invalid) }
    var i = 0usize
    while i < n {
        if events[i] != 0u8 && events[i] != 1u8 { ret (0u32, Invalid) }
        iscratch[i] = i
        i += 1usize
    }
    i = 1usize
    while i < n {
        var j = i
        while j > 0usize && times[iscratch[j]] < times[iscratch[j - 1usize]] {
            let swap = iscratch[j]
            iscratch[j] = iscratch[j - 1usize]
            iscratch[j - 1usize] = swap
            j -= 1usize
        }
        i += 1usize
    }
    var at = 0usize
    var hazards = fscratch[..n]
    at += n
    var score = fscratch[at..at + p]
    at += p
    var info = fscratch[at..at + p * p]
    at += p * p
    var step = fscratch[at..at + p]
    at += p
    var work = fscratch[at..at + p * p]
    at += p * p
    var acc1 = fscratch[at..at + p]
    at += p
    var acc2 = fscratch[at..at + p * p]
    var b = 0usize
    while b < p {
        beta[b] = 0.0f64
        b += 1usize
    }
    var iteration = 0u32
    var done = false
    while iteration < 100u32 && !done {
        i = 0usize
        while i < n {
            var s = 0.0f64
            var j = 0usize
            while j < p {
                s += x[i * p + j] * beta[j]
                j += 1usize
            }
            hazards[i] = math.exp[f64](s)
            i += 1usize
        }
        b = 0usize
        while b < p {
            score[b] = 0.0f64
            b += 1usize
        }
        var e = 0usize
        while e < p * p {
            info[e] = 0.0f64
            e += 1usize
        }
        // Descending risk sets (Breslow: tied subjects join before any of
        // their events contribute).
        var acc0 = 0.0f64
        b = 0usize
        while b < p {
            acc1[b] = 0.0f64
            b += 1usize
        }
        e = 0usize
        while e < p * p {
            acc2[e] = 0.0f64
            e += 1usize
        }
        var idx = n
        while idx > 0usize {
            let t = times[iscratch[idx - 1usize]]
            var start = idx - 1usize
            while start > 0usize && times[iscratch[start - 1usize]] == t {
                start -= 1usize
            }
            var k = start
            while k < idx {
                let s = iscratch[k]
                acc0 += hazards[s]
                b = 0usize
                while b < p {
                    acc1[b] += x[s * p + b] * hazards[s]
                    b += 1usize
                }
                var a = 0usize
                while a < p {
                    b = 0usize
                    while b < p {
                        acc2[a * p + b] += x[s * p + a] * x[s * p + b] * hazards[s]
                        b += 1usize
                    }
                    a += 1usize
                }
                k += 1usize
            }
            k = start
            while k < idx {
                let s = iscratch[k]
                if events[s] == 1u8 {
                    b = 0usize
                    while b < p {
                        score[b] += x[s * p + b] - acc1[b] / acc0
                        b += 1usize
                    }
                    var a = 0usize
                    while a < p {
                        b = 0usize
                        while b < p {
                            info[a * p + b] += acc2[a * p + b] / acc0 - acc1[a] / acc0 * (acc1[b] / acc0)
                            b += 1usize
                        }
                        a += 1usize
                    }
                }
                k += 1usize
            }
            idx = start
        }
        e = 0usize
        while e < p * p {
            work[e] = info[e]
            e += 1usize
        }
        let step_error = survival_solve(work, step, p)
        if step_error != ok { ret (iteration, step_error) }
        var largest = 0.0f64
        b = 0usize
        while b < p {
            beta[b] += step[b]
            largest = math.max[f64](largest, math.abs[f64](step[b]))
            b += 1usize
        }
        iteration += 1u32
        if largest < 0.0000000001f64 { done = true }
    }
    // The inverse column by column from the final information, which the
    // solves above never overwrite (they run on the `work` copy).
    var c = 0usize
    while c < p {
        var e = 0usize
        while e < p * p {
            work[e] = info[e]
            e += 1usize
        }
        var r = 0usize
        while r < p {
            if r == c {
                step[r] = 1.0f64
            } else {
                step[r] = 0.0f64
            }
            r += 1usize
        }
        // The last round left the information at the optimum in place; a
        // failed solve answers no covariance.
        let inverse_error = survival_solve(work, step, p)
        if inverse_error != ok { ret (iteration, inverse_error) }
        r = 0usize
        while r < p {
            covariance[r * p + c] = step[r]
            r += 1usize
        }
        c += 1usize
    }
    ret (iteration, ok)
}

// The O'Brien-Fleming Lan-DeMets cumulative alpha spent at information
// fraction `t` of an overall `alpha`: `2 (1 - Φ(z / √t))`.
fn spending_obrien_fleming(t: f64, alpha: f64) -> (f64, err) {
    if !(t > 0.0f64 && t <= 1.0f64 && alpha > 0.0f64 && alpha < 1.0f64) { ret (0.0f64, Invalid) }
    let z = special.normal_quantile(1.0f64 - alpha / 2.0f64)
    ret (2.0f64 * (1.0f64 - special.normal_cdf(z / math.sqrt[f64](t))), ok)
}

// The Pocock Lan-DeMets cumulative alpha spent: `α ln(1 + (e - 1) t)`.
fn spending_pocock(t: f64, alpha: f64) -> (f64, err) {
    if !(t > 0.0f64 && t <= 1.0f64 && alpha > 0.0f64 && alpha < 1.0f64) { ret (0.0f64, Invalid) }
    ret (alpha * math.log[f64](1.0f64 + (math.exp[f64](1.0f64) - 1.0f64) * t), ok)
}

// The binomial survival function `P(X >= k)` by forward recurrence; exact
// endpoints (`k <= 0` is 1, past `n` is 0) need no arithmetic.
fn binom_sf(n: usize, k: usize, p: f64) -> (f64, err) {
    if !(p >= 0.0f64 && p <= 1.0f64) { ret (0.0f64, Invalid) }
    if k <= 0usize { ret (1.0f64, ok) }
    if k > n { ret (0.0f64, ok) }
    if p <= 0.0f64 { ret (0.0f64, ok) }
    if p >= 1.0f64 { ret (1.0f64, ok) }
    var term = math.pow[f64](1.0f64 - p, f64(n))
    var total = 0.0f64
    var j = 0usize
    while j <= n {
        if j >= k { total += term }
        term = term * f64(n - j) / f64(j + 1usize) * p / (1.0f64 - p)
        j += 1usize
    }
    ret (total, ok)
}

// The operating characteristics of one Simon design at response rate `p`:
// the rejection probability and the expected sample size. `scratch.len >=
// 2 * n + 4` holds both stage distributions and the stage-2 survival
// function.
fn simon_oc(n1: usize, r1: usize, n: usize, r: usize, p: f64, scratch: []f64) -> (f64, f64, err) {
    if !(p >= 0.0f64 && p <= 1.0f64) { ret (0.0f64, 0.0f64, Invalid) }
    if n1 == 0usize || n1 >= n || r1 > n1 || r > n { ret (0.0f64, 0.0f64, Invalid) }
    let n2 = n - n1
    if scratch.len < 2usize * n + 4usize { ret (0.0f64, 0.0f64, TooSmall) }
    var b1 = scratch[..n1 + 1usize]
    var at = n1 + 1usize
    var pmf2 = scratch[at..at + n2 + 1usize]
    at += n2 + 1usize
    var sf2 = scratch[at..at + n2 + 2usize]
    let e1 = simon_pmf(n1, p, b1)
    if e1 != ok { ret (0.0f64, 0.0f64, e1) }
    let e2 = simon_pmf(n2, p, pmf2)
    if e2 != ok { ret (0.0f64, 0.0f64, e2) }
    sf2[n2 + 1usize] = 0.0f64
    var k = n2
    while k > 0usize {
        k -= 1usize
        sf2[k] = sf2[k + 1usize] + pmf2[k]
    }
    var pet = 0.0f64
    var x = 0usize
    while x <= r1 {
        pet += b1[x]
        x += 1usize
    }
    var reject = 0.0f64
    x = r1 + 1usize
    while x <= n1 {
        var tail = 0.0f64
        if r < x {
            tail = 1.0f64
        } else {
            let need = r - x + 1usize
            if need <= n2 + 1usize { tail = sf2[need] }
        }
        reject += b1[x] * tail
        x += 1usize
    }
    ret (reject, f64(n1) + (1.0f64 - pet) * f64(n2), ok)
}

// The binomial probability mass function into `pmf` (`n + 1` entries) by
// forward recurrence.
fn simon_pmf(n: usize, p: f64, pmf: []f64) -> err {
    if pmf.len < n + 1usize { ret TooSmall }
    if !(p >= 0.0f64 && p <= 1.0f64) { ret Invalid }
    if p <= 0.0f64 {
        pmf[0usize] = 1.0f64
        var k = 1usize
        while k <= n {
            pmf[k] = 0.0f64
            k += 1usize
        }
        ret ok
    }
    if p >= 1.0f64 {
        var k = 0usize
        while k < n {
            pmf[k] = 0.0f64
            k += 1usize
        }
        pmf[n] = 1.0f64
        ret ok
    }
    pmf[0usize] = math.pow[f64](1.0f64 - p, f64(n))
    var k = 0usize
    while k < n {
        pmf[k + 1usize] = pmf[k] * f64(n - k) / f64(k + 1usize) * p / (1.0f64 - p)
        k += 1usize
    }
    ret ok
}

// The exhaustive Simon search behind both designs: totals `2..=60`, every
// stage-1 size and futility bound, and for each the first total cutoff that
// spends no more than `alpha` under `p0` (power only falls from there, so
// one check decides the pair). Optimal keeps the smallest expected sample
// size under `p0` (ties to the smaller total, then stage, then bounds);
// minimax keeps the smallest total (ties to the smaller expectation). Six
// scratch regions of 62 entries hold both stages' distributions and
// survival functions at the largest total, so `scratch.len >= 372`.
fn simon_search(p0: f64, p1: f64, alpha: f64, beta: f64, minimax: bool, scratch: []f64) -> (SimonDesign, err) {
    if !(p0 >= 0.0f64 && p0 <= 1.0f64 && p1 >= 0.0f64 && p1 <= 1.0f64 && p1 > p0) { ret (zero, Invalid) }
    if !(alpha > 0.0f64 && alpha < 1.0f64 && beta > 0.0f64 && beta < 1.0f64) { ret (zero, Invalid) }
    if scratch.len < 372usize { ret (zero, TooSmall) }
    var b1_0 = scratch[..62usize]
    var b1_1 = scratch[62usize..124usize]
    var b2_0 = scratch[124usize..186usize]
    var b2_1 = scratch[186usize..248usize]
    var sf_0 = scratch[248usize..310usize]
    var sf_1 = scratch[310usize..372usize]
    var have = false
    var best = SimonDesign { n1: 0usize, r1: 0usize, n: 0usize, r: 0usize }
    var best_n = 0usize
    var best_expected = 0.0f64
    var n = 2usize
    while n <= 60usize {
        if minimax && have && n > best_n { break }
        var n1 = 1usize
        while n1 < n {
            let n2 = n - n1
            let fill_error = simon_fill(n1, n2, p0, p1, b1_0, b1_1, b2_0, b2_1, sf_0, sf_1)
            if fill_error != ok { ret (zero, fill_error) }
            var r1 = 0usize
            while r1 <= n1 {
                var pet0 = 0.0f64
                var x = 0usize
                while x <= r1 {
                    pet0 += b1_0[x]
                    x += 1usize
                }
                var r = 0usize
                var decided = false
                while r <= n && !decided {
                    var type1 = 0.0f64
                    var power = 0.0f64
                    x = r1 + 1usize
                    while x <= n1 {
                        type1 += b1_0[x] * simon_tail(sf_0, n2, r, x)
                        power += b1_1[x] * simon_tail(sf_1, n2, r, x)
                        x += 1usize
                    }
                    if type1 <= alpha {
                        if power >= 1.0f64 - beta {
                            let expected = f64(n1) + (1.0f64 - pet0) * f64(n2)
                            if minimax {
                                if !have || n < best_n || (n == best_n && expected < best_expected) {
                                    have = true
                                    best_n = n
                                    best_expected = expected
                                    best = SimonDesign { n1: n1, r1: r1, n: n, r: r }
                                }
                            } else {
                                if !have || expected < best_expected {
                                    have = true
                                    best_expected = expected
                                    best = SimonDesign { n1: n1, r1: r1, n: n, r: r }
                                }
                            }
                        }
                        decided = true
                    }
                    r += 1usize
                }
                r1 += 1usize
            }
            n1 += 1usize
        }
        n += 1usize
    }
    if !have { ret (zero, Invalid) }
    ret (best, ok)
}

// Stage distributions and survival functions for one total each.
fn simon_fill(n1: usize, n2: usize, p0: f64, p1: f64, b1_0: []f64, b1_1: []f64, b2_0: []f64, b2_1: []f64, sf_0: []f64, sf_1: []f64) -> err {
    let e1 = simon_pmf(n1, p0, b1_0)
    if e1 != ok { ret e1 }
    let e2 = simon_pmf(n1, p1, b1_1)
    if e2 != ok { ret e2 }
    let e3 = simon_pmf(n2, p0, b2_0)
    if e3 != ok { ret e3 }
    let e4 = simon_pmf(n2, p1, b2_1)
    if e4 != ok { ret e4 }
    sf_0[n2 + 1usize] = 0.0f64
    sf_1[n2 + 1usize] = 0.0f64
    var k = n2
    while k > 0usize {
        k -= 1usize
        sf_0[k] = sf_0[k + 1usize] + b2_0[k]
        sf_1[k] = sf_1[k + 1usize] + b2_1[k]
    }
    ret ok
}

// `P(X2 > r - x)` from a survival array (`sf[n2 + 1] == 0` sentinel).
fn simon_tail(sf: []const f64, n2: usize, r: usize, x: usize) -> f64 {
    if r < x { ret 1.0f64 }
    let need = r - x + 1usize
    if need > n2 + 1usize { ret 0.0f64 }
    ret sf[need]
}

// Simon's optimal two-stage design: the feasible design of smallest
// expected sample size under `p0` (ties to smaller totals first).
fn simon_optimal(p0: f64, p1: f64, alpha: f64, beta: f64, scratch: []f64) -> (SimonDesign, err) {
    let (design, search_error) = simon_search(p0, p1, alpha, beta, false, scratch)
    if search_error != ok { ret (zero, search_error) }
    ret (design, ok)
}

// Simon's minimax two-stage design: the feasible design of smallest total
// (ties to the smaller expectation).
fn simon_minimax(p0: f64, p1: f64, alpha: f64, beta: f64, scratch: []f64) -> (SimonDesign, err) {
    let (design, search_error) = simon_search(p0, p1, alpha, beta, true, scratch)
    if search_error != ok { ret (zero, search_error) }
    ret (design, ok)
}

// The negative log-likelihood of the power-model exponent `a`: the
// skeleton to `exp(a)` at each assigned dose against its outcome.
fn crm_objective(skeleton: []const f64, doses: usize, assigned: []const usize, outcomes: []const u8, patients: usize, a: f64) -> f64 {
    let exponent = math.exp[f64](a)
    var total = 0.0f64
    var i = 0usize
    while i < patients {
        let s = skeleton[assigned[i]]
        if outcomes[i] == 1u8 {
            total += exponent * math.log[f64](s)
        } else {
            total += math.log[f64](1.0f64 - math.pow[f64](s, exponent))
        }
        i += 1usize
    }
    ret 0.0f64 - total
}

// Likelihood continual reassessment: the power-model exponent by golden
// section on `[-3, 3]` (200 rounds, fixed), the posterior-mean toxicity of
// every dose into `means`, and the dose closest to `goal` without
// skipping an untried dose past the highest tried one (ties to the lower
// dose). Past the data the likelihood can favour a boundary, which is
// answered as is; start heterogeneous data in practice.
fn crm_next(skeleton: []const f64, doses: usize, goal: f64, assigned: []const usize, outcomes: []const u8, patients: usize, means: []f64) -> (usize, err) {
    if skeleton.len < doses || assigned.len < patients || outcomes.len < patients || means.len < doses { ret (0usize, TooSmall) }
    if doses == 0usize || patients == 0usize { ret (0usize, Invalid) }
    if !(goal > 0.0f64 && goal < 1.0f64) { ret (0usize, Invalid) }
    var d = 0usize
    while d < doses {
        if !(skeleton[d] > 0.0f64 && skeleton[d] < 1.0f64) { ret (0usize, Invalid) }
        d += 1usize
    }
    var highest = 0usize
    var i = 0usize
    while i < patients {
        if assigned[i] >= doses { ret (0usize, Invalid) }
        if outcomes[i] != 0u8 && outcomes[i] != 1u8 { ret (0usize, Invalid) }
        if assigned[i] > highest { highest = assigned[i] }
        i += 1usize
    }
    var lo = 0.0f64 - 3.0f64
    var hi = 3.0f64
    var c = hi - 0.6180339887498949f64 * (hi - lo)
    var e = lo + 0.6180339887498949f64 * (hi - lo)
    var rounds = 0u32
    while rounds < 200u32 {
        if crm_objective(skeleton, doses, assigned, outcomes, patients, c) < crm_objective(skeleton, doses, assigned, outcomes, patients, e) {
            hi = e
            e = c
            c = hi - 0.6180339887498949f64 * (hi - lo)
        } else {
            lo = c
            c = e
            e = lo + 0.6180339887498949f64 * (hi - lo)
        }
        rounds += 1u32
    }
    let exponent = math.exp[f64]((lo + hi) / 2.0f64)
    d = 0usize
    while d < doses {
        means[d] = math.pow[f64](skeleton[d], exponent)
        d += 1usize
    }
    var cap = highest + 1usize
    if cap >= doses { cap = doses - 1usize }
    var best = 0usize
    var best_gap = 2.0f64
    d = 0usize
    while d <= cap {
        var gap = means[d] - goal
        if gap < 0.0f64 { gap = 0.0f64 - gap }
        if gap < best_gap {
            best_gap = gap
            best = d
        }
        d += 1usize
    }
    ret (best, ok)
}

// The constrained maximum-likelihood pair under `treatment - control =
// -margin`: treatment first, by bisection on the profile score (200
// rounds); a score of one sign throughout takes the nearer boundary.
fn fm_mle(x1: u64, n1: u64, x2: u64, n2: u64, margin: f64) -> (f64, f64, err) {
    if n1 == 0u64 || n2 == 0u64 || x1 > n1 || x2 > n2 { ret (0.0f64, 0.0f64, Invalid) }
    if !(margin > 0.0f64 && margin < 1.0f64) { ret (0.0f64, 0.0f64, Invalid) }
    let d = 0.0f64 - margin
    var lo = margin + 0.000000000001f64
    var hi = 1.0f64 - 0.000000000001f64
    if fm_score(x1, n1, x2, n2, d, lo) <= 0.0f64 { ret (lo + d, lo, ok) }
    if fm_score(x1, n1, x2, n2, d, hi) >= 0.0f64 { ret (hi + d, hi, ok) }
    var rounds = 0u32
    while rounds < 200u32 {
        let mid = (lo + hi) / 2.0f64
        if fm_score(x1, n1, x2, n2, d, mid) > 0.0f64 {
            lo = mid
        } else {
            hi = mid
        }
        rounds += 1u32
    }
    let pc = (lo + hi) / 2.0f64
    ret (pc + d, pc, ok)
}

// The constrained score at control rate `pc` (treatment at `pc + d`).
fn fm_score(x1: u64, n1: u64, x2: u64, n2: u64, d: f64, pc: f64) -> f64 {
    let pt = pc + d
    ret f64(x1) / pt - f64(n1 - x1) / (1.0f64 - pt) + f64(x2) / pc - f64(n2 - x2) / (1.0f64 - pc)
}

// The Farrington-Manning non-inferiority test of two proportions against
// `margin`: the constrained estimates, the standardized observed
// difference, and the one-sided p-value.
fn farrington_manning(x1: u64, n1: u64, x2: u64, n2: u64, margin: f64) -> (Result, err) {
    let (pt, pc, mle_error) = fm_mle(x1, n1, x2, n2, margin)
    if mle_error != ok { ret (zero, mle_error) }
    let v0 = pt * (1.0f64 - pt) / f64(n1) + pc * (1.0f64 - pc) / f64(n2)
    if !(v0 > 0.0f64) { ret (zero, Invalid) }
    let z = (f64(x1) / f64(n1) - f64(x2) / f64(n2) + margin) / math.sqrt[f64](v0)
    ret (Result { statistic: z, p_value: 1.0f64 - special.normal_cdf(z) }, ok)
}
