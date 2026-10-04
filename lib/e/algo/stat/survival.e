// Nonparametric survival estimators over right-censored times: the
// Nelson-Aalen cumulative hazard, the Aalen-Johansen cumulative incidence
// for competing risks, restricted mean survival with Greenwood standard
// error, and weighted log-rank tests (Breslow, Tarone-Ware, Peto-Peto,
// Fleming-Harrington) beside the unweighted Mantel-Cox in
// `e.algo.stat.survival_trial`.
//
// Times pair with `u8` status flags (0 censored, 1 event); competing-risk
// causes ride `u8` codes with 0 censored and the target any nonzero code.
// Estimates land in caller slices over the event times that move them;
// `order` is caller sort scratch.

use e.math
use e.math.special

type Result = struct { statistic: f64, p_value: f64 }
type Weight = enum u8 { LogRank, Breslow, TaroneWare, PetoPeto, FlemingHarrington }
type Rmst = struct { mean: f64, se: f64 }
error TooSmall
error Invalid

// The Nelson-Aalen cumulative hazard with Aalen's variance: at each event
// time `H += deaths / risk`, `V += deaths / risk^2`. Answers the event-time
// count with parallel `out_times`, `out_hazard`, `out_variance` and
// `out_risk`.
fn nelson_aalen(times: []const f64, events: []const u8, n: usize, out_times: []f64, out_hazard: []f64, out_variance: []f64, out_risk: []usize, order: []usize) -> (usize, err) {
    if times.len < n || events.len < n || out_times.len < n || out_hazard.len < n || out_variance.len < n || out_risk.len < n || order.len < n { ret (0usize, TooSmall) }
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
    var hazard = 0.0f64
    var variance = 0.0f64
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
            hazard += f64(deaths) / f64(risk)
            variance += f64(deaths) / (f64(risk) * f64(risk))
            out_times[records] = t
            out_hazard[records] = hazard
            out_variance[records] = variance
            out_risk[records] = risk
            records += 1usize
        }
        risk -= tied
        i += tied
    }
    ret (records, ok)
}

// The Aalen-Johansen cumulative incidence of `cause`: overall survival times
// the cause-specific hazard summed over the target's event times, answering
// the target-time count with parallel `out_times` and `out_cif`. `cause`
// zero (the censored code) is `Invalid`; every other nonzero code competes.
fn cumulative_incidence(times: []const f64, causes: []const u8, n: usize, cause: u8, out_times: []f64, out_cif: []f64, order: []usize) -> (usize, err) {
    if times.len < n || causes.len < n || out_times.len < n || out_cif.len < n || order.len < n { ret (0usize, TooSmall) }
    if n == 0usize || cause == 0u8 { ret (0usize, Invalid) }
    var i = 0usize
    while i < n {
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
    var incidence = 0.0f64
    var risk = n
    var records = 0usize
    i = 0usize
    while i < n {
        let t = times[order[i]]
        var wanted = 0usize
        var any = 0usize
        var tied = 0usize
        while i + tied < n && times[order[i + tied]] == t {
            if causes[order[i + tied]] != 0u8 {
                any += 1usize
                if causes[order[i + tied]] == cause { wanted += 1usize }
            }
            tied += 1usize
        }
        if wanted > 0usize {
            incidence += survival * f64(wanted) / f64(risk)
            out_times[records] = t
            out_cif[records] = incidence
            records += 1usize
        }
        if any > 0usize { survival = survival * (1.0f64 - f64(any) / f64(risk)) }
        risk -= tied
        i += tied
    }
    ret (records, ok)
}

// Restricted mean survival to `tau`: the Kaplan-Meier area with Greenwood
// standard error (terms with the whole risk set failing contribute nothing).
// Answers `mean` with `se`.
fn rmst(times: []const f64, events: []const u8, n: usize, tau: f64, order: []usize) -> (Rmst, err) {
    if times.len < n || events.len < n || order.len < n { ret (zero, TooSmall) }
    if n == 0usize || !(tau > 0.0f64) { ret (zero, Invalid) }
    var i = 0usize
    while i < n {
        if events[i] != 0u8 && events[i] != 1u8 { ret (zero, Invalid) }
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
    var previous = 0.0f64
    var area = 0.0f64
    i = 0usize
    while i < n {
        let t = times[order[i]]
        if t > tau { break }
        var deaths = 0usize
        var tied = 0usize
        while i + tied < n && times[order[i + tied]] == t {
            if events[order[i + tied]] == 1u8 { deaths += 1usize }
            tied += 1usize
        }
        area += survival * (t - previous)
        if deaths > 0usize { survival = survival * (1.0f64 - f64(deaths) / f64(risk)) }
        previous = t
        risk -= tied
        i += tied
    }
    area += survival * (tau - previous)
    var running = 0.0f64
    survival = 1.0f64
    risk = n
    previous = 0.0f64
    var variance = 0.0f64
    i = 0usize
    while i < n {
        let t = times[order[i]]
        if t > tau { ret (Rmst { mean: area, se: math.sqrt[f64](variance) }, ok) }
        var deaths = 0usize
        var tied = 0usize
        while i + tied < n && times[order[i + tied]] == t {
            if events[order[i + tied]] == 1u8 { deaths += 1usize }
            tied += 1usize
        }
        running += survival * (t - previous)
        if deaths > 0usize && deaths < risk {
            let ahead = area - running
            variance += f64(deaths) / (f64(risk) * f64(risk - deaths)) * ahead * ahead
        }
        if deaths > 0usize { survival = survival * (1.0f64 - f64(deaths) / f64(risk)) }
        previous = t
        risk -= tied
        i += tied
    }
    ret (Rmst { mean: area, se: math.sqrt[f64](variance) }, ok)
}

// The weighted log-rank sweep both public tests share: the score over pooled
// distinct event times with hypergeometric variance, each time weighted per
// `weight` (`rho`/`gamma` only steer Fleming-Harrington), the chi-squared
// statistic on one degree of freedom, and its p-value. Pooled survival runs
// alongside for the Peto-Peto and Fleming-Harrington weights. With no events
// at all the statistic is 0 with p-value 1.
fn wlw_sweep(ta: []const f64, ea: []const u8, na: usize, tb: []const f64, eb: []const u8, nb: usize, weight: Weight, rho: f64, gamma: f64) -> (Result, err) {
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
    var pooled = 1.0f64
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
        var w = 1.0f64
        if weight == .Breslow {
            w = f64(risk)
        } else if weight == .TaroneWare {
            w = math.sqrt[f64](f64(risk))
        } else if weight == .PetoPeto {
            w = pooled
        } else if weight == .FlemingHarrington {
            w = math.pow[f64](pooled, rho) * math.pow[f64](1.0f64 - pooled, gamma)
        }
        score += w * (f64(deaths_a) - f64(deaths) * f64(risk_a) / f64(risk))
        if risk > 1usize {
            variance += w * w * f64(risk_a) * f64(risk_b) * f64(deaths) * f64(risk - deaths) / (f64(risk) * f64(risk) * f64(risk - 1usize))
        }
        pooled = pooled * (1.0f64 - f64(deaths) / f64(risk))
        have_floor = true
        floor = t
    }
    if variance <= 0.0f64 { ret (Result { statistic: 0.0f64, p_value: 1.0f64 }, ok) }
    let statistic = score * score / variance
    ret (Result { statistic: statistic, p_value: 1.0f64 - special.chi_squared_cdf(statistic, 1.0f64) }, ok)
}

// A weighted log-rank test of two samples (`FlemingHarrington` through this
// entry runs G(0, 0), the log-rank; `fleming_harrington` sets the shape).
fn weighted_log_rank(ta: []const f64, ea: []const u8, na: usize, tb: []const f64, eb: []const u8, nb: usize, weight: Weight) -> (Result, err) {
    let (r, sweep_error) = wlw_sweep(ta, ea, na, tb, eb, nb, weight, 0.0f64, 0.0f64)
    ret (r, sweep_error)
}

// The Fleming-Harrington G(`rho`, `gamma`) test, weighting pooled survival
// to `rho` against one minus it to `gamma` (`rho` = `gamma` = 0 is the
// unweighted log-rank).
fn fleming_harrington(ta: []const f64, ea: []const u8, na: usize, tb: []const f64, eb: []const u8, nb: usize, rho: f64, gamma: f64) -> (Result, err) {
    if !(rho >= 0.0f64) || !(gamma >= 0.0f64) { ret (zero, Invalid) }
    let (r, sweep_error) = wlw_sweep(ta, ea, na, tb, eb, nb, .FlemingHarrington, rho, gamma)
    ret (r, sweep_error)
}
