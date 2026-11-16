// R PerformanceAnalytics: annualized return, maximum drawdown, downside deviation, Sortino, Calmar and Sharpe ratios, and VaR and ES by
// the historical, Gaussian and (VaR only) Cornish-Fisher modified methods, for one series of returns.
//
// Not here: the modified ES, the portfolio and component forms, the other methods (kernel, gpd, lognormal, Monte Carlo), CAPM,
// the information, omega and tracking measures, Return.calculate and findDrawdowns.

use e.math
use e.math.dist as dist
use e.mem

fn mean_of(r: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < r.len {
        s += r[i]
        i += 1usize
    }
    ret s / f64(r.len)
}

fn sd_of(r: []const f64) -> f64 {
    let m = mean_of(r)
    var s = 0.0f64
    var i = 0usize
    while i < r.len {
        s += (r[i] - m) * (r[i] - m)
        i += 1usize
    }
    ret math.sqrt[f64](s / (f64(r.len) - 1.0f64))
}

fn return_annualized(r: []const f64, scale: f64, geometric: bool) -> f64 {
    if !geometric { ret mean_of(r) * scale }
    var p = 1.0f64
    var i = 0usize
    while i < r.len {
        p = p * (1.0f64 + r[i])
        i += 1usize
    }
    ret math.pow[f64](p, scale / f64(r.len)) - 1.0f64
}

// the positive worst peak-to-trough loss (invert = TRUE)
fn max_drawdown(r: []const f64, geometric: bool) -> f64 {
    var cum = 1.0f64
    if !geometric { cum = 1.0f64 }
    var top = 1.0f64
    var worst = 0.0f64
    var i = 0usize
    var level = 1.0f64
    while i < r.len {
        if geometric {
            level = level * (1.0f64 + r[i])
        } else {
            cum += r[i]
            level = cum
        }
        if level > top { top = level }
        let dd = level / top - 1.0f64
        if dd < worst { worst = dd }
        i += 1usize
    }
    ret 0.0f64 - worst
}

// potential = false gives the deviation, true the downside potential; subset divides by the number of returns below mar
fn downside_deviation(r: []const f64, mar: f64, subset: bool, potential: bool) -> f64 {
    var cnt = 0usize
    var s = 0.0f64
    var i = 0usize
    while i < r.len {
        if r[i] < mar {
            cnt += 1usize
            if potential { s += mar - r[i] } else { s += (mar - r[i]) * (mar - r[i]) }
        }
        i += 1usize
    }
    var len = f64(r.len)
    if subset { len = f64(cnt) }
    if potential { ret s / len }
    ret math.sqrt[f64](s / len)
}

fn sortino(r: []const f64, mar: f64) -> f64 { ret (mean_of(r) - mar) / downside_deviation(r, mar, false, false) }

fn calmar(r: []const f64, scale: f64) -> f64 { ret return_annualized(r, scale, true) / max_drawdown(r, true) }

fn sharpe(r: []const f64, rf: f64) -> f64 { ret (mean_of(r) - rf) / sd_of(r) }

fn skew_moment(r: []const f64) -> f64 {
    let m = mean_of(r)
    let n = f64(r.len)
    var a = 0.0f64
    var b = 0.0f64
    var i = 0usize
    while i < r.len {
        a += (r[i] - m) * (r[i] - m) * (r[i] - m) / n
        b += (r[i] - m) * (r[i] - m) / n
        i += 1usize
    }
    ret a / math.pow[f64](b, 1.5f64)
}

// excess kurtosis by the moment estimator
fn kurt_moment(r: []const f64) -> f64 {
    let m = mean_of(r)
    let n = f64(r.len)
    var a = 0.0f64
    var b = 0.0f64
    var i = 0usize
    while i < r.len {
        a += (r[i] - m) * (r[i] - m) * (r[i] - m) * (r[i] - m) / n
        b += (r[i] - m) * (r[i] - m) / n
        i += 1usize
    }
    ret a / (b * b) - 3.0f64
}

// the R type-7 sample quantile
fn quantile7(a: *mem.Arena, r: []const f64, p: f64) -> f64 {
    let (s, e) = mem.alloc[f64](a, r.len)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < r.len {
        s[i] = r[i]
        i += 1usize
    }
    i = 1usize
    while i < s.len {
        let t = s[i]
        var j = i
        while j > 0usize && s[j - 1usize] > t {
            s[j] = s[j - 1usize]
            j -= 1usize
        }
        s[j] = t
        i += 1usize
    }
    let h = (f64(s.len) - 1.0f64) * p
    let lo = math.floor[f64](h + 4.0f64 * 2.220446049250313e-16f64)
    var f = h - lo
    if f < 4.0f64 * 2.220446049250313e-16f64 { f = 0.0f64 }
    let k = usize(lo)
    if k + 1usize >= s.len { ret s[s.len - 1usize] }
    ret s[k] + f * (s[k + 1usize] - s[k])
}

// method 0 historical, 1 Gaussian, 2 modified; the loss as a positive number (invert = FALSE)
fn var_loss(a: *mem.Arena, r: []const f64, p: f64, method: usize) -> f64 {
    if method == 0usize { ret 0.0f64 - quantile7(a, r, 1.0f64 - p) }
    let z = dist.qnorm(1.0f64 - p, 0.0f64, 1.0f64, true, false)
    if method == 1usize { ret 0.0f64 - mean_of(r) - z * sd_pop(r) }
    let s = skew_moment(r)
    let k = kurt_moment(r)
    let h = z + (z * z - 1.0f64) * s / 6.0f64 + (z * z * z - 3.0f64 * z) * k / 24.0f64 - (2.0f64 * z * z * z - 5.0f64 * z) * s * s / 36.0f64
    ret 0.0f64 - mean_of(r) - h * sd_pop(r)
}

// method 0 historical, 1 Gaussian
fn es_loss(a: *mem.Arena, r: []const f64, p: f64, method: usize) -> f64 {
    if method == 0usize {
        let q = quantile7(a, r, 1.0f64 - p)
        var s = 0.0f64
        var c = 0usize
        var i = 0usize
        while i < r.len {
            if r[i] < q {
                s += r[i]
                c += 1usize
            }
            i += 1usize
        }
        if c == 0usize { ret 0.0f64 - q }
        ret 0.0f64 - s / f64(c)
    }
    let z = dist.qnorm(1.0f64 - p, 0.0f64, 1.0f64, true, false)
    ret 0.0f64 - mean_of(r) + sd_pop(r) * dist.dnorm(z, 0.0f64, 1.0f64, false) / (1.0f64 - p)
}

// the package's Gaussian and Cornish-Fisher risk measures scale by the population standard deviation (sqrt of the second central moment)
fn sd_pop(r: []const f64) -> f64 { ret sd_of(r) * math.sqrt[f64]((f64(r.len) - 1.0f64) / f64(r.len)) }

// ---- two series: ra the asset, rb the benchmark, equal length

fn cov_of(x: []const f64, y: []const f64) -> f64 {
    let mx = mean_of(x)
    let my = mean_of(y)
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += (x[i] - mx) * (y[i] - my)
        i += 1usize
    }
    ret s / (f64(x.len) - 1.0f64)
}

// CAPM.beta on excess returns (rf subtracted from both)
fn capm_beta(ra: []const f64, rb: []const f64, rf: f64, a: *mem.Arena) -> f64 {
    let (xa, e1) = mem.alloc[f64](a, ra.len)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let (xb, e2) = mem.alloc[f64](a, ra.len)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < ra.len {
        xa[i] = ra[i] - rf
        xb[i] = rb[i] - rf
        i += 1usize
    }
    ret cov_of(xa, xb) / cov_of(xb, xb)
}

fn capm_alpha(ra: []const f64, rb: []const f64, rf: f64, a: *mem.Arena) -> f64 {
    let b = capm_beta(ra, rb, rf, a)
    ret (mean_of(ra) - rf) - b * (mean_of(rb) - rf)
}

fn tracking_error(ra: []const f64, rb: []const f64, a: *mem.Arena, scale: f64) -> f64 {
    let (d, e) = mem.alloc[f64](a, ra.len)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < ra.len {
        d[i] = ra[i] - rb[i]
        i += 1usize
    }
    ret sd_of(d) * math.sqrt[f64](scale)
}

fn information_ratio(ra: []const f64, rb: []const f64, a: *mem.Arena, scale: f64) -> f64 {
    let ap = return_annualized(ra, scale, true) - return_annualized(rb, scale, true)
    ret ap / tracking_error(ra, rb, a, scale)
}

fn omega_sharpe(r: []const f64, mar: f64) -> f64 {
    let n = f64(r.len)
    var up = 0.0f64
    var dn = 0.0f64
    var i = 0usize
    while i < r.len {
        if r[i] > mar { up += (r[i] - mar) / n }
        if r[i] < mar { dn += (mar - r[i]) / n }
        i += 1usize
    }
    ret (up - dn) / dn
}

fn cum_return(r: []const f64, keep: []const bool) -> f64 {
    var p = 1.0f64
    var i = 0usize
    while i < r.len {
        if keep[i] { p = p * (1.0f64 + r[i]) }
        i += 1usize
    }
    ret p - 1.0f64
}

// method 0 Capture, 1 Number, 2 Percent; side 0 Up, 1 Down; geometric as in the package
fn up_down(a: *mem.Arena, ra: []const f64, rb: []const f64, method: usize, side: usize, geometric: bool) -> f64 {
    let (k, e) = mem.alloc[bool](a, ra.len)
    if e != ok { ret 0.0f64 / 0.0f64 }
    let (kb, e2) = mem.alloc[bool](a, ra.len)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    var cnt_i = 0usize
    var cnt_b = 0usize
    var sa = 0.0f64
    var sb = 0.0f64
    while i < ra.len {
        var inb = rb[i] > 0.0f64
        if side == 1usize { inb = rb[i] <= 0.0f64 }
        if method > 0usize && side == 1usize { inb = rb[i] < 0.0f64 }
        k[i] = inb
        kb[i] = inb
        if inb {
            cnt_b += 1usize
            sa += ra[i]
            sb += rb[i]
            if method == 1usize {
                if side == 0usize && ra[i] > 0.0f64 { cnt_i += 1usize }
                if side == 1usize && ra[i] < 0.0f64 { cnt_i += 1usize }
            }
            if method == 2usize && ra[i] > rb[i] { cnt_i += 1usize }
        }
        i += 1usize
    }
    if method > 0usize { ret f64(cnt_i) / f64(cnt_b) }
    if geometric { ret cum_return(ra, k) / cum_return(rb, kb) }
    ret sa / sb
}
