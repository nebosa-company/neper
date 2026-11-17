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

fn colsum(v: []const f64, n: usize, col: usize) -> f64 {
    var total = 0.0f64
    var comp = 0.0f64
    var i = 0usize
    while i < n {
        let x = v[col * n + i]
        let t = total + x
        if math.abs[f64](total) >= math.abs[f64](x) { comp += (total - t) + x } else { comp += (x - t) + total }
        total = t
        i += 1usize
    }
    ret total + comp
}

// ResourceSelection::wrsi(y, x): the weighted resource selection index of each of the p columns of x (n by p, column-major) for the used indicator y;
// out is p rows of eight values: WRSI, zWRSI, rWRSI, Pused, Pavail, Pw, u, a
fn wrsi(a: *mem.Arena, y: []const f64, x: []const f64, n: usize, p: usize, out: []f64) -> err {
    let (xu, e1) = mem.alloc[f64](a, n * p)
    if e1 != ok { ret e1 }
    var tot = 0.0f64
    var totu = 0.0f64
    var c = 0usize
    var i = 0usize
    while c < p {
        i = 0usize
        while i < n {
            var yy = 0.0f64
            if y[i] > 0.0f64 { yy = 1.0f64 }
            xu[c * n + i] = x[c * n + i] * yy
            i += 1usize
        }
        c += 1usize
    }
    // sum(X) and sum(Xu) add the column sums in R's order
    var tc = 0.0f64
    var tcu = 0.0f64
    c = 0usize
    while c < p {
        tc += colsum(x, n, c)
        tcu += colsum(xu, n, c)
        c += 1usize
    }
    tot = tc
    totu = tcu
    c = 0usize
    while c < p {
        let sa = colsum(x, n, c)
        let su = colsum(xu, n, c)
        let pav = sa / tot
        let pus = su / totu
        let w = pus / pav
        let lw = math.log[f64](w)
        let ew = math.exp[f64](2.0f64 * lw)
        out[c * 8usize] = w
        out[c * 8usize + 1usize] = lw
        out[c * 8usize + 2usize] = (ew - 1.0f64) / (1.0f64 + ew)
        out[c * 8usize + 3usize] = pus
        out[c * 8usize + 4usize] = pav
        out[c * 8usize + 5usize] = su / sa
        out[c * 8usize + 6usize] = su
        out[c * 8usize + 7usize] = sa
        c += 1usize
    }
    ret ok
}

// ResourceSelection::CAIC for a model of log likelihood ll, k parameters and n observations: alpha AIC + (1 - alpha) BIC
fn caic(ll: f64, k: f64, n: f64, alpha: f64) -> f64 {
    ret alpha * (0.0f64 - 2.0f64 * ll + 2.0f64 * k) + (1.0f64 - alpha) * (0.0f64 - 2.0f64 * ll + math.log[f64](n) * k)
}
