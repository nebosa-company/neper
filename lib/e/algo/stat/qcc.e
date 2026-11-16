// R qcc: Shewhart control charts for variables (xbar with the five standard-deviation estimators, R, S, individuals) and attributes
// (p, np, c, u) with their centre lines and limits (k sigmas, or a coverage probability for the types whose limits have a closed
// distribution), the beyond-limits and violating-runs rules, the CUSUM and EWMA charts and the process capability indices with their
// confidence limits. Group data are ng by m row-major with NaN for a missing observation; attribute charts take counts and sizes.
//
// Not here: R-chart limits from a coverage probability (they need qtukey), the T2 and g charts, the OC curves and the plotting.

use e.algo.stat.qcc_tables as tab
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

// c4(n) = sqrt(2 / (n - 1)) gamma(n / 2) / gamma((n - 1) / 2)
fn c4(n: f64) -> f64 { ret math.sqrt[f64](2.0f64 / (n - 1.0f64)) * math.exp[f64](nm.lgammafn(n / 2.0f64) - nm.lgammafn((n - 1.0f64) / 2.0f64)) }

type Chart = struct { stat: []f64, center: f64, sd: f64, lcl: []f64, ucl: []f64, sizes: []f64, ng: usize }

// the non-missing observations of group i: count, mean, standard deviation (n - 1), range
type Grp = struct { n: f64, mean: f64, sd: f64, range: f64 }

fn group(x: []const f64, i: usize, m: usize) -> Grp {
    var n = 0.0f64
    var s = 0.0f64
    var lo = 0.0f64
    var hi = 0.0f64
    var j = 0usize
    while j < m {
        let v = x[i * m + j]
        if v == v {
            if n == 0.0f64 {
                lo = v
                hi = v
            } else {
                if v < lo { lo = v }
                if v > hi { hi = v }
            }
            n += 1.0f64
            s += v
        }
        j += 1usize
    }
    let mean = s / n
    var d = 0.0f64
    j = 0usize
    while j < m {
        let v = x[i * m + j]
        if v == v { d += (v - mean) * (v - mean) }
        j += 1usize
    }
    ret Grp { n: n, mean: mean, sd: math.sqrt[f64](d / (n - 1.0f64)), range: hi - lo }
}

// the standard deviation estimate of an xbar, R or S chart: method 0 UWAVE-R, 1 UWAVE-SD, 2 MVLUE-R, 3 MVLUE-SD, 4 RMSDF
fn sd_xbar(x: []const f64, ng: usize, m: usize, method: u8) -> f64 {
    var sum = 0.0f64
    var wsum = 0.0f64
    var i = 0usize
    while i < ng {
        let g = group(x, i, m)
        if method == 0u8 {
            sum += g.range / tab.d2_tab(usize(g.n))
        } else if method == 1u8 {
            sum += g.sd / c4(g.n)
        } else if method == 2u8 {
            let d2 = tab.d2_tab(usize(g.n))
            let d3 = tab.d3_tab(usize(g.n))
            let w = (d2 / d3) * (d2 / d3)
            sum += g.range / d2 * w
            wsum += w
        } else if method == 3u8 {
            let cc = c4(g.n)
            let w = cc * cc / (1.0f64 - cc * cc)
            sum += g.sd / cc * w
            wsum += w
        } else {
            let w = g.n - 1.0f64
            sum += g.sd * g.sd * w
            wsum += w
        }
        i += 1usize
    }
    if method == 0u8 || method == 1u8 { ret sum / f64(ng) }
    if method == 4u8 { ret math.sqrt[f64](sum / wsum) / c4(wsum + 1.0f64) }
    ret sum / wsum
}

// qcc(data, type = "xbar" (0), "R" (1), "S" (2), "xbar.one" (3), sizes, std.dev = a method code or a number, nsigmas = conf)
fn qcc_var(a: *mem.Arena, x: []const f64, ng: usize, m: usize, kind: u8, method: u8, sd_given: f64, conf: f64) -> (Chart, err) {
    var none: Chart = zero
    let (st, e1) = mem.alloc[f64](a, ng)
    let (lcl, e2) = mem.alloc[f64](a, ng)
    let (ucl, e3) = mem.alloc[f64](a, ng)
    let (sz, e4) = mem.alloc[f64](a, ng)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (none, e1) }
    var center = 0.0f64
    var sd = sd_given
    var i = 0usize
    if kind == 3u8 {
        // individuals: the data are one column
        var s = 0.0f64
        while i < ng {
            st[i] = x[i]
            sz[i] = 1.0f64
            s += x[i]
            i += 1usize
        }
        center = s / f64(ng)
        if sd_given != sd_given {
            if method == 0u8 {
                var d = 0.0f64
                var j = 1usize
                while j < ng {
                    var df = x[j] - x[j - 1usize]
                    if df < 0.0f64 { df = 0.0f64 - df }
                    d += df
                    j += 1usize
                }
                sd = (d / f64(ng - 1usize)) / tab.d2_tab(2usize)
            } else {
                var s2 = 0.0f64
                i = 0usize
                while i < ng {
                    s2 += (x[i] - center) * (x[i] - center)
                    i += 1usize
                }
                sd = math.sqrt[f64](s2 / f64(ng - 1usize)) / c4(f64(ng))
            }
        }
        i = 0usize
        while i < ng {
            if conf >= 1.0f64 {
                lcl[i] = center - conf * sd
                ucl[i] = center + conf * sd
            } else {
                let z = dist.qnorm(1.0f64 - (1.0f64 - conf) / 2.0f64, 0.0f64, 1.0f64, true, false)
                lcl[i] = center - z * sd
                ucl[i] = center + z * sd
            }
            i += 1usize
        }
        ret (Chart { stat: st, center: center, sd: sd, lcl: lcl, ucl: ucl, sizes: sz, ng: ng }, ok)
    }
    var sw = 0.0f64
    var tot = 0.0f64
    while i < ng {
        let g = group(x, i, m)
        sz[i] = g.n
        if kind == 0u8 { st[i] = g.mean }
        if kind == 1u8 { st[i] = g.range }
        if kind == 2u8 { st[i] = g.sd }
        sw += g.n * st[i]
        tot += g.n
        i += 1usize
    }
    center = sw / tot
    if sd_given != sd_given {
        var meth = method
        if kind == 0u8 && method == 9u8 {
            meth = 0u8
            i = 0usize
            while i < ng {
                if sz[i] > 25.0f64 { meth = 4u8 }
                i += 1usize
            }
        }
        if kind == 1u8 && method == 9u8 { meth = 0u8 }
        if kind == 2u8 && method == 9u8 { meth = 1u8 }
        sd = sd_xbar(x, ng, m, meth)
    }
    i = 0usize
    while i < ng {
        let n = sz[i]
        if kind == 0u8 {
            let se = sd / math.sqrt[f64](n)
            if conf >= 1.0f64 {
                lcl[i] = center - conf * se
                ucl[i] = center + conf * se
            } else {
                let z = dist.qnorm(1.0f64 - (1.0f64 - conf) / 2.0f64, 0.0f64, 1.0f64, true, false)
                lcl[i] = center - z * se
                ucl[i] = center + z * se
            }
        } else if kind == 1u8 {
            let se = tab.d3_tab(usize(n)) * sd
            lcl[i] = center - conf * se
            if lcl[i] < 0.0f64 { lcl[i] = 0.0f64 }
            ucl[i] = center + conf * se
        } else {
            let cc = c4(n)
            let se = sd * math.sqrt[f64](1.0f64 - cc * cc)
            if conf >= 1.0f64 {
                lcl[i] = center - conf * se
                if lcl[i] < 0.0f64 { lcl[i] = 0.0f64 }
                ucl[i] = center + conf * se
            } else {
                ucl[i] = sd * math.sqrt[f64](nm.qchisq(1.0f64 - (1.0f64 - conf) / 2.0f64, n - 1.0f64, true, false) / (n - 1.0f64))
                lcl[i] = sd * math.sqrt[f64](nm.qchisq((1.0f64 - conf) / 2.0f64, n - 1.0f64, true, false) / (n - 1.0f64))
            }
        }
        i += 1usize
    }
    ret (Chart { stat: st, center: center, sd: sd, lcl: lcl, ucl: ucl, sizes: sz, ng: ng }, ok)
}

// the attribute charts: kind 0 p, 1 np, 2 c, 3 u; data are the counts and sizes the group sizes (all equal for c)
fn qcc_attr(a: *mem.Arena, data: []const f64, sizes: []const f64, kind: u8, conf: f64) -> (Chart, err) {
    var none: Chart = zero
    let ng = data.len
    let (st, e1) = mem.alloc[f64](a, ng)
    let (lcl, e2) = mem.alloc[f64](a, ng)
    let (ucl, e3) = mem.alloc[f64](a, ng)
    let (sz, e4) = mem.alloc[f64](a, ng)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (none, e1) }
    var sd_sum = 0.0f64
    var sz_sum = 0.0f64
    var i = 0usize
    while i < ng {
        sd_sum += data[i]
        sz_sum += sizes[i]
        sz[i] = sizes[i]
        i += 1usize
    }
    var center = 0.0f64
    var sd = 0.0f64
    let pbar = sd_sum / sz_sum
    if kind == 0u8 {
        center = pbar
        sd = math.sqrt[f64](pbar * (1.0f64 - pbar))
    } else if kind == 1u8 {
        center = sizes[0usize] * pbar
        sd = math.sqrt[f64](sizes[0usize] * pbar * (1.0f64 - pbar))
    } else if kind == 2u8 {
        center = sd_sum / f64(ng)
        sd = math.sqrt[f64](center)
    } else {
        center = sd_sum / sz_sum
        sd = math.sqrt[f64](center)
    }
    i = 0usize
    while i < ng {
        let n = sizes[i]
        if kind == 0u8 { st[i] = data[i] / n }
        if kind == 1u8 { st[i] = data[i] }
        if kind == 2u8 { st[i] = data[i] }
        if kind == 3u8 { st[i] = data[i] / n }
        if kind <= 1u8 {
            // limits.np on the count scale: the centre count is center (np) or center * n (p)
            var cn = center
            if kind == 0u8 { cn = center * n }
            let pb = cn / n
            var lo = 0.0f64
            var hi = 0.0f64
            if conf >= 1.0f64 {
                let tol = conf * math.sqrt[f64](pb * (1.0f64 - pb) * n)
                lo = cn - tol
                if lo < 0.0f64 { lo = 0.0f64 }
                hi = cn + tol
                if hi > n { hi = n }
            } else {
                lo = qbinom((1.0f64 - conf) / 2.0f64, n, pb, true)
                hi = qbinom((1.0f64 - conf) / 2.0f64, n, pb, false)
            }
            if kind == 0u8 {
                lo = lo / n
                hi = hi / n
            }
            lcl[i] = lo
            ucl[i] = hi
        } else {
            var cn = center
            if kind == 3u8 { cn = center * n }
            var lo = 0.0f64
            var hi = 0.0f64
            if conf >= 1.0f64 {
                lo = cn - conf * math.sqrt[f64](cn)
                if lo < 0.0f64 { lo = 0.0f64 }
                hi = cn + conf * math.sqrt[f64](cn)
            } else {
                hi = qpois(1.0f64 - (1.0f64 - conf) / 2.0f64, cn)
                lo = qpois((1.0f64 - conf) / 2.0f64, cn)
            }
            if kind == 3u8 {
                lo = lo / n
                hi = hi / n
            }
            lcl[i] = lo
            ucl[i] = hi
        }
        i += 1usize
    }
    ret (Chart { stat: st, center: center, sd: sd, lcl: lcl, ucl: ucl, sizes: sz, ng: ng }, ok)
}

// the smallest x with P(X <= x) >= p (lower) for Binomial(n, pb), and the upper-tail version qbinom(p, n, pb, lower.tail = FALSE)
fn qbinom(p: f64, n: f64, pb: f64, lower: bool) -> f64 {
    var x = 0.0f64
    if lower {
        while x < n && dist_pbinom(x, n, pb) < p * (1.0f64 - 64.0f64 * 2.220446049250313e-16f64) { x += 1.0f64 }
        ret x
    }
    // smallest x with P(X > x) <= p
    while x < n && (1.0f64 - dist_pbinom(x, n, pb)) > p * (1.0f64 + 64.0f64 * 2.220446049250313e-16f64) { x += 1.0f64 }
    ret x
}

fn dist_pbinom(x: f64, n: f64, pb: f64) -> f64 {
    var s = 0.0f64
    var k = 0.0f64
    while k <= x {
        s += math.exp[f64](nm.lgammafn(n + 1.0f64) - nm.lgammafn(k + 1.0f64) - nm.lgammafn(n - k + 1.0f64) + k * math.log[f64](pb) + (n - k) * math.log[f64](1.0f64 - pb))
        k += 1.0f64
    }
    ret s
}

// the smallest x with P(X <= x) >= p for Poisson(lambda)
fn qpois(p: f64, lambda: f64) -> f64 {
    var x = 0.0f64
    while nm.ppois(x, lambda, true, false) < p * (1.0f64 - 64.0f64 * 2.220446049250313e-16f64) { x += 1.0f64 }
    ret x
}

// beyond.limits: the 1-based indices above the upper limit, then those below the lower
fn beyond_limits(c: Chart, out: []usize) -> usize {
    var k = 0usize
    var i = 0usize
    while i < c.ng {
        if c.stat[i] > c.ucl[i] {
            out[k] = i + 1usize
            k += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < c.ng {
        if c.stat[i] < c.lcl[i] {
            out[k] = i + 1usize
            k += 1usize
        }
        i += 1usize
    }
    ret k
}

// violating.runs: for every run of at least `rl` statistics on one side of the centre (above-runs first) the 1-based indices from the rl-th point of the run on, as R lists them
fn violating_runs(c: Chart, rl: usize, out: []usize) -> usize {
    var k = 0usize
    var side = 0usize
    while side < 2usize {
        var i = 0usize
        while i < c.ng {
            let d = c.stat[i] - c.center
            var s = 0i64
            if d > 0.0f64 { s = 1i64 }
            if d < 0.0f64 { s = 0i64 - 1i64 }
            let want = if_side(side)
            if s == want {
                var j = i
                while j < c.ng {
                    var dj = c.stat[j] - c.center
                    var sj = 0i64
                    if dj > 0.0f64 { sj = 1i64 }
                    if dj < 0.0f64 { sj = 0i64 - 1i64 }
                    if sj != want { break }
                    j += 1usize
                }
                if j - i >= rl {
                    var q = i + rl - 1usize
                    while q < j {
                        out[k] = q + 1usize
                        k += 1usize
                        q += 1usize
                    }
                }
                i = j
            } else {
                i += 1usize
            }
        }
        side += 1usize
    }
    ret k
}

fn if_side(side: usize) -> i64 {
    if side == 0usize { ret 1i64 }
    ret 0i64 - 1i64
}

type Cusum = struct { pos: []f64, neg: []f64, nlower: usize, nupper: usize }

// cusum(data, head.start, decision.interval, se.shift) with the chart's centre and standard deviation given
fn cusum(a: *mem.Arena, stat: []const f64, sizes: []const f64, center: f64, sd: f64, head: f64, di: f64, shift: f64) -> (Cusum, err) {
    var none: Cusum = zero
    let n = stat.len
    let (pos, e1) = mem.alloc[f64](a, n)
    let (neg, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret (none, e1) }
    var i = 0usize
    var nu = 0usize
    var nl = 0usize
    while i < n {
        let z = (stat[i] - center) / (sd / math.sqrt[f64](sizes[i]))
        var pp = head
        var nn = head
        if i > 0usize {
            pp = pos[i - 1usize]
            nn = 0.0f64 - neg[i - 1usize]
        }
        var vp = pp + (z - shift / 2.0f64)
        if vp < 0.0f64 { vp = 0.0f64 }
        var vn = nn - (z + shift / 2.0f64)
        if vn < 0.0f64 { vn = 0.0f64 }
        pos[i] = vp
        neg[i] = 0.0f64 - vn
        if neg[i] < 0.0f64 - di { nl += 1usize }
        if pos[i] > di { nu += 1usize }
        i += 1usize
    }
    ret (Cusum { pos: pos, neg: neg, nlower: nl, nupper: nu }, ok)
}

// ewma(data, lambda, nsigmas): the smoothed series y and the control limits at each point
fn ewma(a: *mem.Arena, stat: []const f64, sizes: []const f64, center: f64, sd: f64, lambda: f64, nsig: f64) -> ([]f64, []f64, []f64, err) {
    let n = stat.len
    let (y, e1) = mem.alloc[f64](a, n)
    let (lo, e2) = mem.alloc[f64](a, n)
    let (hi, e3) = mem.alloc[f64](a, n)
    if e1 != ok { ret (y, lo, hi, e1) }
    if e2 != ok { ret (y, lo, hi, e2) }
    if e3 != ok { ret (y, lo, hi, e3) }
    var prev = center
    var i = 0usize
    while i < n {
        prev = lambda * stat[i] + (1.0f64 - lambda) * prev
        y[i] = prev
        let s2 = sd * sd / sizes[i] * ((lambda / (2.0f64 - lambda)) * (1.0f64 - math.pow[f64](1.0f64 - lambda, f64(2usize * (i + 1usize)))))
        lo[i] = center - nsig * math.sqrt[f64](s2)
        hi[i] = center + nsig * math.sqrt[f64](s2)
        i += 1usize
    }
    ret (y, lo, hi, ok)
}

type Cap = struct { cp: f64, cpl: f64, cpu: f64, cpk: f64, cpm: f64, cp_lo: f64, cp_hi: f64, cpl_lo: f64, cpl_hi: f64, cpu_lo: f64, cpu_hi: f64, cpk_lo: f64, cpk_hi: f64, cpm_lo: f64, cpm_hi: f64 }

// process.capability(object, spec.limits, tgt): n observations (all the data), the chart's centre and standard deviation, nsigmas
fn process_capability(n: f64, center: f64, sd: f64, nsig: f64, lsl: f64, usl: f64, tgt: f64, conf: f64) -> Cap {
    let cp = (usl - lsl) / (2.0f64 * nsig * sd)
    let cpu = (usl - center) / (nsig * sd)
    let cpl = (center - lsl) / (nsig * sd)
    var cpk = cpu
    if cpl < cpu { cpk = cpl }
    let cpm = cp / math.sqrt[f64](1.0f64 + ((center - tgt) / sd) * ((center - tgt) / sd))
    let alpha = 1.0f64 - conf
    let zc = dist.qnorm(conf, 0.0f64, 1.0f64, true, false)
    let za = dist.qnorm(1.0f64 - alpha / 2.0f64, 0.0f64, 1.0f64, true, false)
    let cp_lo = cp * math.sqrt[f64](nm.qchisq(alpha / 2.0f64, n - 1.0f64, true, false) / (n - 1.0f64))
    let cp_hi = cp * math.sqrt[f64](nm.qchisq(1.0f64 - alpha / 2.0f64, n - 1.0f64, true, false) / (n - 1.0f64))
    let ru = math.sqrt[f64](1.0f64 / (9.0f64 * n * cpu * cpu) + 1.0f64 / (2.0f64 * (n - 1.0f64)))
    let rl = math.sqrt[f64](1.0f64 / (9.0f64 * n * cpl * cpl) + 1.0f64 / (2.0f64 * (n - 1.0f64)))
    let rk = math.sqrt[f64](1.0f64 / (9.0f64 * n * cpk * cpk) + 1.0f64 / (2.0f64 * (n - 1.0f64)))
    let dd = (center - tgt) / sd
    let df = n * (1.0f64 + dd * dd) / (1.0f64 + 2.0f64 * dd * dd)
    ret Cap { cp: cp, cpl: cpl, cpu: cpu, cpk: cpk, cpm: cpm, cp_lo: cp_lo, cp_hi: cp_hi, cpl_lo: cpl * (1.0f64 - zc * rl), cpl_hi: cpl * (1.0f64 + zc * rl), cpu_lo: cpu * (1.0f64 - zc * ru), cpu_hi: cpu * (1.0f64 + zc * ru), cpk_lo: cpk * (1.0f64 - za * rk), cpk_hi: cpk * (1.0f64 + za * rk), cpm_lo: cpm * math.sqrt[f64](nm.qchisq(alpha / 2.0f64, df, true, false) / df), cpm_hi: cpm * math.sqrt[f64](nm.qchisq(1.0f64 - alpha / 2.0f64, df, true, false) / df) }
}

// pareto.chart(data): the frequencies sorted decreasingly with their cumulative sums, percentages and cumulative percentages (n by 4, row-major)
fn pareto(a: *mem.Arena, data: []const f64) -> ([]f64, err) {
    let n = data.len
    let (o, e) = mem.alloc[f64](a, 4usize * n)
    let (s, e2) = mem.alloc[f64](a, n)
    if e != ok { ret (o, e) }
    if e2 != ok { ret (o, e2) }
    var i = 0usize
    while i < n {
        s[i] = data[i]
        i += 1usize
    }
    i = 1usize
    while i < n {
        let v = s[i]
        var j = i
        while j > 0usize && s[j - 1usize] < v {
            s[j] = s[j - 1usize]
            j -= 1usize
        }
        s[j] = v
        i += 1usize
    }
    var tot = 0.0f64
    i = 0usize
    while i < n {
        tot += s[i]
        i += 1usize
    }
    var cum = 0.0f64
    i = 0usize
    while i < n {
        cum += s[i]
        o[i * 4usize] = s[i]
        o[i * 4usize + 1usize] = cum
        o[i * 4usize + 2usize] = s[i] / tot * 100.0f64
        o[i * 4usize + 3usize] = cum / tot * 100.0f64
        i += 1usize
    }
    ret (o, ok)
}
