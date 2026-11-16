// R forecast, the Box-Cox part: `box_cox` and `inv_box_cox` (sign-preserving, as forecast::BoxCox and InvBoxCox)
// and `box_cox_lambda_loglik` (BoxCox.lambda(method = "loglik") for a plain numeric series: the profile
// log-likelihood of an intercept-only fit over the grid lower, lower + 0.05, ..., upper, first maximum).
//
// Not here: the guerrero method (Brent's optimize), tslm trend and season terms, Arima, ets, auto.arima, tbats,
// croston, thetaf, stlf, forecast intervals.

use e.math

fn box_cox(x: f64, lambda: f64) -> f64 {
    if lambda == 0.0f64 { ret math.log[f64](x) }
    var sg = 1.0f64
    if x < 0.0f64 { sg = 0.0f64 - 1.0f64 }
    if x == 0.0f64 { sg = 0.0f64 }
    ret (sg * math.pow[f64](math.abs[f64](x), lambda) - 1.0f64) / lambda
}

fn inv_box_cox(x: f64, lambda: f64) -> f64 {
    if lambda == 0.0f64 { ret math.exp[f64](x) }
    let xx = x * lambda + 1.0f64
    var sg = 1.0f64
    if xx < 0.0f64 { sg = 0.0f64 - 1.0f64 }
    if xx == 0.0f64 { sg = 0.0f64 }
    ret sg * math.pow[f64](math.abs[f64](xx), 1.0f64 / lambda)
}

// the log-likelihood at one lambda of an intercept-only fit to the positive series x
fn bc_loglik(x: []const f64, lam: f64, xdot: f64, logx: []const f64) -> f64 {
    let n = x.len
    var mean = 0.0f64
    var i = 0usize
    var sum = 0.0f64
    // transformed values scaled by xdot^(lam - 1); the residual is the deviation from the mean
    var tot = 0.0f64
    let scale = math.pow[f64](xdot, lam - 1.0f64)
    while i < n {
        var xt = 0.0f64
        if math.abs[f64](lam) > 0.02f64 {
            xt = (math.pow[f64](x[i], lam) - 1.0f64) / lam
        } else {
            let l = logx[i]
            xt = l * (1.0f64 + (lam * l) / 2.0f64 * (1.0f64 + (lam * l) / 3.0f64 * (1.0f64 + (lam * l) / 4.0f64)))
        }
        tot += xt / scale
        i += 1usize
    }
    mean = tot / f64(n)
    i = 0usize
    while i < n {
        var xt = 0.0f64
        if math.abs[f64](lam) > 0.02f64 {
            xt = (math.pow[f64](x[i], lam) - 1.0f64) / lam
        } else {
            let l = logx[i]
            xt = l * (1.0f64 + (lam * l) / 2.0f64 * (1.0f64 + (lam * l) / 3.0f64 * (1.0f64 + (lam * l) / 4.0f64)))
        }
        let r = xt / scale - mean
        sum += r * r
        i += 1usize
    }
    ret 0.0f64 - f64(n) / 2.0f64 * math.log[f64](sum)
}

// logx is a scratch of x.len; lower is raised to 0 by the caller when x has non-positive values
fn box_cox_lambda_loglik(x: []const f64, lower: f64, upper: f64, logx: []f64) -> f64 {
    if x.len <= 2usize { ret 1.0f64 }
    var gm = 0.0f64
    var i = 0usize
    while i < x.len {
        logx[i] = math.log[f64](x[i])
        gm += logx[i]
        i += 1usize
    }
    let xdot = math.exp[f64](gm / f64(x.len))
    let m = usize(math.floor[f64]((upper - lower) / 0.05f64 + 1.0e-10f64))
    var best = lower
    var bestll = 0.0f64
    var k = 0usize
    while k <= m {
        let lam = lower + f64(k) * 0.05f64
        let ll = bc_loglik(x, lam, xdot, logx)
        if k == 0usize || ll > bestll {
            bestll = ll
            best = lam
        }
        k += 1usize
    }
    ret best
}
