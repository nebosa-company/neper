// Pharmacokinetic and pharmacodynamic mathematics over `f64`.
//
// Non-compartmental analysis (NCA) of a concentration-time profile: the
// linear and linear-up/log-down trapezoidal areas under the curve, the area
// under the first moment, the peak concentration and its time, the terminal
// elimination rate by log-linear regression and the half-life from it, and an
// `nca` call that fills the whole set.
//
// Two saturating dose-response fits over `e.math.opt`'s Nelder-Mead simplex:
// the Emax/Hill sigmoid `E0 + Emax C^h / (EC50^h + C^h)` (the plain Emax is
// `h = 1`) and the Michaelis-Menten rate `Vmax S / (Km + S)`. Each fit
// minimises the sum of squared residuals, writes the fitted parameters into
// the caller's slice, and answers the residual sum, the iteration count and
// whether the simplex converged. The model evaluators and the residual
// objectives are public as well, so a caller may drive another optimiser.
//
// Times, concentrations and doses are borrowed and read-only; every fit takes
// the caller's parameter slice as its initial guess and the caller's scratch.

use e.math
use e.math.opt

type Peak = struct { value: f64, time: f64 }
type Nca = struct { auc: f64, auc_inf: f64, aumc: f64, mrt: f64, cmax: f64, tmax: f64, lambda_z: f64, half_life: f64 }
type Fit = struct { value: f64, iterations: u32, converged: bool }
type Data = struct { x: []const f64, y: []const f64 }

error TooFew
error Invalid

// The linear trapezoidal area under `values` over `times`: the two slices are
// the same length and the sum runs over every adjacent pair.
fn auc_linear(times: []const f64, values: []const f64) -> f64 {
    var sum = 0.0f64
    var i = 1usize
    while i < times.len {
        sum += (times[i] - times[i - 1usize]) * (values[i] + values[i - 1usize]) / 2.0f64
        i += 1usize
    }
    ret sum
}

// The linear-up/log-down trapezoidal area: an interval whose end value falls
// below its start (both positive) uses the log formula
// `(v0 - v1) dt / ln(v0 / v1)`, every other interval the linear one.
fn auc_log_linear(times: []const f64, values: []const f64) -> f64 {
    var sum = 0.0f64
    var i = 1usize
    while i < times.len {
        let dt = times[i] - times[i - 1usize]
        let v0 = values[i - 1usize]
        let v1 = values[i]
        if v0 > 0.0f64 && v1 > 0.0f64 && v1 < v0 {
            sum += dt * (v0 - v1) / math.log[f64](v0 / v1)
        } else {
            sum += dt * (v0 + v1) / 2.0f64
        }
        i += 1usize
    }
    ret sum
}

// The area under the first moment curve `t * values`, by the linear trapezoid.
fn aumc_linear(times: []const f64, values: []const f64) -> f64 {
    var sum = 0.0f64
    var i = 1usize
    while i < times.len {
        let dt = times[i] - times[i - 1usize]
        sum += dt * (times[i] * values[i] + times[i - 1usize] * values[i - 1usize]) / 2.0f64
        i += 1usize
    }
    ret sum
}

// The peak concentration and the first time it is reached; an empty profile
// answers the origin.
fn peak(times: []const f64, values: []const f64) -> Peak {
    let n = times.len
    if n == 0usize { ret Peak { value: 0.0f64, time: 0.0f64 } }
    var best = 0usize
    var i = 1usize
    while i < n {
        if values[i] > values[best] { best = i }
        i += 1usize
    }
    ret Peak { value: values[best], time: times[best] }
}

// The terminal elimination rate constant from the log-linear regression of
// `ln(values)` on `times` over the points from `first` to the last; the
// profile there must be strictly positive and strictly ordered in time.
fn terminal_rate(times: []const f64, values: []const f64, first: usize) -> (f64, err) {
    let n = times.len
    if first >= n { ret (0.0f64, TooFew) }
    let count = n - first
    if count < 2usize { ret (0.0f64, TooFew) }
    var t_sum = 0.0f64
    var y_sum = 0.0f64
    var i = first
    while i < n {
        if values[i] <= 0.0f64 { ret (0.0f64, Invalid) }
        if i > first && times[i] <= times[i - 1usize] { ret (0.0f64, Invalid) }
        t_sum += times[i]
        y_sum += math.log[f64](values[i])
        i += 1usize
    }
    let t_mean = t_sum / f64(count)
    let y_mean = y_sum / f64(count)
    var sxy = 0.0f64
    var sxx = 0.0f64
    i = first
    while i < n {
        let dt = times[i] - t_mean
        sxy += dt * (math.log[f64](values[i]) - y_mean)
        sxx += dt * dt
        i += 1usize
    }
    if sxx <= 0.0f64 { ret (0.0f64, Invalid) }
    ret (0.0f64 - sxy / sxx, ok)
}

// The terminal half-life `ln 2 / lambda_z`; a non-positive rate answers zero.
fn half_life(lambda_z: f64) -> f64 {
    if lambda_z <= 0.0f64 { ret 0.0f64 }
    ret 0.6931471805599453f64 / lambda_z
}

// The whole non-compartmental set: the linear areas to the last sample and
// extrapolated to infinity, the first-moment area, the mean residence time,
// the peak, and the terminal rate and half-life from the window starting at
// `first`. Fewer than two samples (or a rejected terminal window) refuses.
fn nca(times: []const f64, values: []const f64, first: usize, out: *Nca) -> err {
    let n = times.len
    if n < 2usize || values.len < n { ret TooFew }
    let (rate, rate_error) = terminal_rate(times, values, first)
    if rate_error != ok { ret rate_error }
    let area = auc_linear(times, values)
    let moment = aumc_linear(times, values)
    let p = peak(times, values)
    out.auc = area
    out.aumc = moment
    out.cmax = p.value
    out.tmax = p.time
    out.lambda_z = rate
    out.half_life = half_life(rate)
    out.auc_inf = area + values[n - 1usize] / rate
    out.mrt = 0.0f64
    if area > 0.0f64 { out.mrt = moment / area }
    ret ok
}

// The Emax model `E0 + Emax C / (EC50 + C)`.
fn emax(e0: f64, e_max: f64, ec50: f64, c: f64) -> f64 {
    ret e0 + e_max * c / (ec50 + c)
}

// The Hill (sigmoid Emax) model `E0 + Emax C^h / (EC50^h + C^h)`.
fn hill(e0: f64, e_max: f64, ec50: f64, h: f64, c: f64) -> f64 {
    let top = math.pow[f64](c, h)
    let bottom = math.pow[f64](ec50, h) + top
    ret e0 + e_max * top / bottom
}

// The Michaelis-Menten rate `Vmax S / (Km + S)`.
fn mm_rate(v_max: f64, k_m: f64, s: f64) -> f64 {
    ret v_max * s / (k_m + s)
}

// The sum of squared residuals of the Hill model at
// `parameters = [E0, Emax, EC50, h]` over `data`; a non-positive EC50 or h
// answers a large penalty so a derivative-free search turns back.
fn emax_hill_sse(data: *Data, parameters: []const f64) -> f64 {
    let e0 = parameters[0usize]
    let e_max = parameters[1usize]
    let ec50 = parameters[2usize]
    let h = parameters[3usize]
    if ec50 <= 0.0f64 || h <= 0.0f64 { ret 1.0e300f64 }
    var sum = 0.0f64
    var i = 0usize
    while i < data.x.len {
        let residual = data.y[i] - hill(e0, e_max, ec50, h, data.x[i])
        sum += residual * residual
        i += 1usize
    }
    ret sum
}

// Fit the Hill (equivalently Emax) model to `data` by Nelder-Mead:
// `parameters` must hold four entries, an initial guess in place, and receives
// the fitted `[E0, Emax, EC50, h]`; `scratch` needs `(5 * 5) + 4 * 4` entries.
fn emax_hill(data: *Data, parameters: []f64, scale: f64, tolerance: f64, max_iterations: u32, scratch: []f64) -> (Fit, err) {
    if parameters.len != 4usize { ret (zero, Invalid) }
    if data.x.len != data.y.len || data.x.len < 4usize { ret (zero, TooFew) }
    let (result, fit_error) = opt.nelder_mead[Data](data, emax_hill_sse, parameters, scale, tolerance, max_iterations, scratch)
    ret (Fit { value: result.value, iterations: result.iterations, converged: result.converged }, fit_error)
}

// The sum of squared residuals of the Michaelis-Menten rate at
// `parameters = [Vmax, Km]`; a non-positive Km answers a large penalty.
fn michaelis_menten_sse(data: *Data, parameters: []const f64) -> f64 {
    let v_max = parameters[0usize]
    let k_m = parameters[1usize]
    if k_m <= 0.0f64 { ret 1.0e300f64 }
    var sum = 0.0f64
    var i = 0usize
    while i < data.x.len {
        let residual = data.y[i] - mm_rate(v_max, k_m, data.x[i])
        sum += residual * residual
        i += 1usize
    }
    ret sum
}

// Fit the Michaelis-Menten rate to `data` by Nelder-Mead: `parameters` must
// hold two entries, an initial guess in place, and receives the fitted
// `[Vmax, Km]`; `scratch` needs `(3 * 3) + 4 * 2` entries.
fn michaelis_menten(data: *Data, parameters: []f64, scale: f64, tolerance: f64, max_iterations: u32, scratch: []f64) -> (Fit, err) {
    if parameters.len != 2usize { ret (zero, Invalid) }
    if data.x.len != data.y.len || data.x.len < 2usize { ret (zero, TooFew) }
    let (result, fit_error) = opt.nelder_mead[Data](data, michaelis_menten_sse, parameters, scale, tolerance, max_iterations, scratch)
    ret (Fit { value: result.value, iterations: result.iterations, converged: result.converged }, fit_error)
}
