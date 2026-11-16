// R ResourceSelection::hoslem.test: the Hosmer-Lemeshow goodness-of-fit statistic of a binary response y against
// fitted probabilities yhat in g groups cut at the (type 7) quantiles of yhat, with the observed and expected
// tables per group.
//
// Not here: kfold, rsf and rspf, CAIC and the used-available helpers.

use e.algo.sort
use e.algo.stat.mass as ms
use e.math
use e.math.nmath as nm
use e.mem

type Hl = struct { chisq: f64, df: f64, pvalue: f64, bins: usize }

fn cmp_up(ctx: *u8, x: f64, y: f64) -> i32 {
    if x < y { ret 0i32 - 1i32 }
    if x > y { ret 1i32 }
    ret 0i32
}

// obs0, obs1, exp0, exp1 each receive one value per occupied group (at most g); answers the statistic
fn hoslem(a: *mem.Arena, y: []const f64, yhat: []const f64, g: usize, obs0: []f64, obs1: []f64, exp0: []f64, exp1: []f64) -> (Hl, err) {
    var res: Hl = zero
    let n = y.len
    let (s, e1) = mem.alloc[f64](a, n)
    let (qq, e2) = mem.alloc[f64](a, g + 1usize)
    if e1 != ok || e2 != ok { ret (res, e1) }
    var i = 0usize
    while i < n {
        s[i] = yhat[i]
        i += 1usize
    }
    var ctx = 0u8
    sort.in_place_by[f64, u8](s, &ctx, cmp_up)
    // unique(quantile(yhat, seq(0, 1, 1 / g)))
    var nq = 0usize
    i = 0usize
    while i <= g {
        let q = ms.quant7(s, f64(i) / f64(g))
        if nq == 0usize || q != qq[nq - 1usize] {
            qq[nq] = q
            nq += 1usize
        }
        i += 1usize
    }
    let nbin = nq - 1usize
    var b = 0usize
    while b < nbin {
        obs0[b] = 0.0f64
        obs1[b] = 0.0f64
        exp0[b] = 0.0f64
        exp1[b] = 0.0f64
        b += 1usize
    }
    i = 0usize
    while i < n {
        // cut(..., include.lowest = TRUE): the first interval is closed on the left, the others are (lo, hi]
        var k = 0usize
        while k + 1usize < nbin && yhat[i] > qq[k + 1usize] { k += 1usize }
        obs0[k] += 1.0f64 - y[i]
        obs1[k] += y[i]
        exp0[k] += 1.0f64 - yhat[i]
        exp1[k] += yhat[i]
        i += 1usize
    }
    var chisq = 0.0f64
    var used = 0usize
    b = 0usize
    while b < nbin {
        let d0 = obs0[b] - exp0[b]
        let d1 = obs1[b] - exp1[b]
        chisq += d0 * d0 / exp0[b] + d1 * d1 / exp1[b]
        if obs0[b] + obs1[b] > 0.0f64 { used += 1usize }
        b += 1usize
    }
    res.chisq = chisq
    res.bins = used
    res.df = f64(used) - 2.0f64
    res.pvalue = 1.0f64 - nm.pchisq(chisq, res.df, true, false)
    ret (res, ok)
}
