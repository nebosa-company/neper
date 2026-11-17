// R coda, the summaries beside e.algo.stat.codapkg: batchSE, summary.mcmc's statistics and gelman.transform.
//
// Not here: cramer.test (a different package, cramer), plots.

use e.algo.stat.codapkg as cd
use e.math
use e.mem

// batchSE(x, batchSize): the standard error from batch means (batches of batch draws, the remainder dropped), divided by sqrt of the full length
fn batch_se(x: []const f64, batch: usize) -> f64 {
    let nb = x.len / batch
    var grand = 0.0f64
    var b = 0usize
    while b < nb {
        var m = 0.0f64
        var i = 0usize
        while i < batch {
            m += x[b * batch + i]
            i += 1usize
        }
        grand += m / f64(batch)
        b += 1usize
    }
    grand = grand / f64(nb)
    var ss = 0.0f64
    b = 0usize
    while b < nb {
        var m = 0.0f64
        var i = 0usize
        while i < batch {
            m += x[b * batch + i]
            i += 1usize
        }
        m = m / f64(batch)
        ss += (m - grand) * (m - grand)
        b += 1usize
    }
    ret math.sqrt[f64](ss * f64(batch) / f64(nb - 1usize)) / math.sqrt[f64](f64(x.len))
}

// summary.mcmc for one series into out: (Mean, SD, Naive SE, Time-series SE)
fn mcmc_summary(a: *mem.Arena, x: []const f64, out: []f64) -> err {
    let n = f64(x.len)
    let v = cd.var_of(x)
    let (sp, o, e) = cd.spec0(a, x)
    if e != ok { ret e }
    out[0usize] = cd.mean_of(x)
    out[1usize] = math.sqrt[f64](v)
    out[2usize] = math.sqrt[f64](v / n)
    out[3usize] = math.sqrt[f64](sp / n)
    ret ok
}

// gelman.transform for the draws of one variable (all chains at once): logit when every value is in (0, 1), log when every value is positive, otherwise unchanged
fn gelman_transform(x: []f64) {
    var mn = x[0usize]
    var mx = x[0usize]
    var i = 0usize
    while i < x.len {
        if x[i] < mn { mn = x[i] }
        if x[i] > mx { mx = x[i] }
        i += 1usize
    }
    if !(mn > 0.0f64) { ret }
    i = 0usize
    while i < x.len {
        if mx < 1.0f64 { x[i] = math.log[f64](x[i] / (1.0f64 - x[i])) } else { x[i] = math.log[f64](x[i]) }
        i += 1usize
    }
}
