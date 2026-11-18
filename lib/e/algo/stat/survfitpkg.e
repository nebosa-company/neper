// R survival::survfit for one sample: the Kaplan-Meier estimate with Greenwood's variance and the log, plain and log-log confidence intervals, one row per distinct event time.
//
// Not here: Fleming-Harrington and Nelson-Aalen forms, left and interval censoring, strata and the other conf.type values.

use e.math
use e.math.dist as dist
use e.mem

// the table row k (0-based, in increasing event time) of survfit(Surv(t, e) ~ 1, conf.int = conf, conf.type = ctype) (0 log, 1 plain, 2 log-log): col 0 time, 1 n.risk, 2 n.event, 3 surv,
// 4 std.err (of the log survival), 5 lower, 6 upper; the number of rows is returned and rows past it are not written
fn km_table(a: *mem.Arena, t: []const f64, e: []const f64, conf: f64, ctype: usize, out: []f64, rows_max: usize) -> usize {
    let n = t.len
    let z = dist.qnorm(1.0f64 - (1.0f64 - conf) / 2.0f64, 0.0f64, 1.0f64, true, false)
    var surv = 1.0f64
    var gsum = 0.0f64
    var row = 0usize
    var done = 0usize
    var cur = 0.0f64 - 1.0e300f64
    while row < rows_max {
        // the next distinct event time above cur
        var nxt = 1.0e300f64
        var i = 0usize
        while i < n {
            if e[i] != 0.0f64 && t[i] > cur && t[i] < nxt { nxt = t[i] }
            i += 1usize
        }
        if nxt >= 1.0e300f64 { break }
        var nr = 0.0f64
        var d = 0.0f64
        i = 0usize
        while i < n {
            if t[i] >= nxt { nr += 1.0f64 }
            if t[i] == nxt && e[i] != 0.0f64 { d += 1.0f64 }
            i += 1usize
        }
        surv = surv * (1.0f64 - d / nr)
        if nr > d { gsum += d / (nr * (nr - d)) }
        let se = math.sqrt[f64](gsum)
        var lo = 0.0f64
        var hi = 0.0f64
        if ctype == 0usize {
            lo = math.exp[f64](math.log[f64](surv) - z * se)
            hi = math.exp[f64](math.log[f64](surv) + z * se)
        } else if ctype == 1usize {
            lo = surv - z * se * surv
            hi = surv + z * se * surv
        } else {
            let ls = math.log[f64](surv)
            let sc = se / ls
            lo = math.exp[f64](0.0f64 - math.exp[f64](math.log[f64](0.0f64 - ls) - z * sc))
            hi = math.exp[f64](0.0f64 - math.exp[f64](math.log[f64](0.0f64 - ls) + z * sc))
        }
        if hi > 1.0f64 { hi = 1.0f64 }
        if lo < 0.0f64 { lo = 0.0f64 }
        out[row * 7usize] = nxt
        out[row * 7usize + 1usize] = nr
        out[row * 7usize + 2usize] = d
        out[row * 7usize + 3usize] = surv
        out[row * 7usize + 4usize] = se
        out[row * 7usize + 5usize] = lo
        out[row * 7usize + 6usize] = hi
        row += 1usize
        cur = nxt
        done = row
    }
    ret done
}

// survfit(type = "fleming-harrington") (fh2 false: the Nelson-Aalen hazard d / n, surv = exp(-H), variance d / n^2) and type = "fh2" (fh2 true: the tie-adjusted hazard sum over k < d of 1 / (n - k),
// variance sum of 1 / (n - k)^2), with the log confidence interval; same row layout as km_table
fn na_table(t: []const f64, e: []const f64, conf: f64, fh2: bool, out: []f64, rows_max: usize) -> usize {
    let n = t.len
    let z = dist.qnorm(1.0f64 - (1.0f64 - conf) / 2.0f64, 0.0f64, 1.0f64, true, false)
    var h = 0.0f64
    var v = 0.0f64
    var row = 0usize
    var cur = 0.0f64 - 1.0e300f64
    while row < rows_max {
        var nxt = 1.0e300f64
        var i = 0usize
        while i < n {
            if e[i] != 0.0f64 && t[i] > cur && t[i] < nxt { nxt = t[i] }
            i += 1usize
        }
        if nxt >= 1.0e300f64 { break }
        var nr = 0.0f64
        var d = 0.0f64
        i = 0usize
        while i < n {
            if t[i] >= nxt { nr += 1.0f64 }
            if t[i] == nxt && e[i] != 0.0f64 { d += 1.0f64 }
            i += 1usize
        }
        if fh2 {
            var k = 0.0f64
            while k < d {
                h += 1.0f64 / (nr - k)
                v += 1.0f64 / ((nr - k) * (nr - k))
                k += 1.0f64
            }
        } else {
            h += d / nr
            v += d / (nr * nr)
        }
        let se = math.sqrt[f64](v)
        let surv = math.exp[f64](0.0f64 - h)
        var hi = math.exp[f64](math.log[f64](surv) + z * se)
        if hi > 1.0f64 { hi = 1.0f64 }
        out[row * 7usize] = nxt
        out[row * 7usize + 1usize] = nr
        out[row * 7usize + 2usize] = d
        out[row * 7usize + 3usize] = surv
        out[row * 7usize + 4usize] = se
        out[row * 7usize + 5usize] = math.exp[f64](math.log[f64](surv) - z * se)
        out[row * 7usize + 6usize] = hi
        row += 1usize
        cur = nxt
    }
    ret row
}

// survdiff(Surv(t, e) ~ g, rho) for k groups (grp[i] in 0..k-1): the chi-square on k - 1 degrees of freedom from the observed less expected events of the first k - 1 groups and the
// hypergeometric covariance, weights S(t-)^rho from the pooled Kaplan-Meier; out receives (chi-square, degrees of freedom)
fn survdiff_k(a: *mem.Arena, t: []const f64, e: []const f64, grp: []const usize, k: usize, rho: f64, out: []f64) -> err {
    let n = t.len
    let (oe, e1) = mem.alloc[f64](a, k)
    let (vm, e2) = mem.alloc[f64](a, k * k)
    let (nr, e3) = mem.alloc[f64](a, k)
    let (dk, e4) = mem.alloc[f64](a, k)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    var i = 0usize
    while i < k {
        oe[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k * k {
        vm[i] = 0.0f64
        i += 1usize
    }
    var surv = 1.0f64
    var cur = 0.0f64 - 1.0e300f64
    while true {
        var nxt = 1.0e300f64
        i = 0usize
        while i < n {
            if e[i] != 0.0f64 && t[i] > cur && t[i] < nxt { nxt = t[i] }
            i += 1usize
        }
        if nxt >= 1.0e300f64 { break }
        var tot = 0.0f64
        var d = 0.0f64
        var g = 0usize
        while g < k {
            nr[g] = 0.0f64
            dk[g] = 0.0f64
            g += 1usize
        }
        i = 0usize
        while i < n {
            if t[i] >= nxt {
                nr[grp[i]] += 1.0f64
                tot += 1.0f64
            }
            if t[i] == nxt && e[i] != 0.0f64 {
                dk[grp[i]] += 1.0f64
                d += 1.0f64
            }
            i += 1usize
        }
        let w = math.pow[f64](surv, rho)
        g = 0usize
        while g < k {
            oe[g] += w * (dk[g] - d * nr[g] / tot)
            g += 1usize
        }
        if tot > 1.0f64 {
            let vf = w * w * d * (tot - d) / (tot * tot * (tot - 1.0f64))
            g = 0usize
            while g < k {
                var h = 0usize
                while h < k {
                    var c = 0.0f64 - nr[g] * nr[h]
                    if g == h { c = nr[g] * (tot - nr[g]) }
                    vm[g * k + h] += vf * c
                    h += 1usize
                }
                g += 1usize
            }
        }
        surv = surv * (1.0f64 - d / tot)
        cur = nxt
    }
    // chi-square: u' V^-1 u over the first k - 1 groups, by Gauss-Jordan on the (k - 1) block
    let m = k - 1usize
    let (aug, e5) = mem.alloc[f64](a, m * (m + 1usize))
    if e5 != ok { ret mem.Full }
    var r = 0usize
    while r < m {
        var c = 0usize
        while c < m {
            aug[r * (m + 1usize) + c] = vm[r * k + c]
            c += 1usize
        }
        aug[r * (m + 1usize) + m] = oe[r]
        r += 1usize
    }
    var col = 0usize
    while col < m {
        var piv = col
        r = col + 1usize
        while r < m {
            if math.abs[f64](aug[r * (m + 1usize) + col]) > math.abs[f64](aug[piv * (m + 1usize) + col]) { piv = r }
            r += 1usize
        }
        var c = 0usize
        while c <= m {
            let tmp = aug[col * (m + 1usize) + c]
            aug[col * (m + 1usize) + c] = aug[piv * (m + 1usize) + c]
            aug[piv * (m + 1usize) + c] = tmp
            c += 1usize
        }
        let dv = aug[col * (m + 1usize) + col]
        c = 0usize
        while c <= m {
            aug[col * (m + 1usize) + c] = aug[col * (m + 1usize) + c] / dv
            c += 1usize
        }
        r = 0usize
        while r < m {
            if r != col {
                let f = aug[r * (m + 1usize) + col]
                c = 0usize
                while c <= m {
                    aug[r * (m + 1usize) + c] = aug[r * (m + 1usize) + c] - f * aug[col * (m + 1usize) + c]
                    c += 1usize
                }
            }
            r += 1usize
        }
        col += 1usize
    }
    var chi = 0.0f64
    r = 0usize
    while r < m {
        chi += oe[r] * aug[r * (m + 1usize) + m]
        r += 1usize
    }
    out[0usize] = chi
    out[1usize] = f64(m)
    ret ok
}
