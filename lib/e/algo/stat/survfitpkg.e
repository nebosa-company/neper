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
