// R agricolae: the pairwise comparisons of group means after a one-way analysis of variance: LSD.test (no p adjustment), HSD.test
// (Tukey) and scheffe.test, each giving the difference of means, its p value and the confidence limits, for balanced or unbalanced groups.
//
// Not here: SNK.test and duncan.test (the package's standard error for unbalanced groups is not the pairwise one and was not recovered), waller.test,
// the non-parametric post-hoc tests, the experimental designs and AMMI.

use e.math
use e.math.nmath_beta as nb
use e.algo.linalg.lapack_gesdd as gsd
use e.algo.rand.r as rr
use e.algo.stat.algdesign_block as blk
use e.math.nmath as nm
use e.math.quadpack as qp
use e.mem

type OneWay = struct { mse: f64, df: f64, k: usize }

// y with group labels 1..k: the group means and sizes go to mean and size (k each); the residual mean square and its degrees of freedom are returned
fn one_way(y: []const f64, grp: []const usize, k: usize, mean: []f64, size: []f64) -> OneWay {
    var i = 0usize
    while i < k {
        mean[i] = 0.0f64
        size[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < y.len {
        mean[grp[i] - 1usize] += y[i]
        size[grp[i] - 1usize] += 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < k {
        mean[i] = mean[i] / size[i]
        i += 1usize
    }
    var ss = 0.0f64
    i = 0usize
    while i < y.len {
        let r = y[i] - mean[grp[i] - 1usize]
        ss += r * r
        i += 1usize
    }
    let df = f64(y.len) - f64(k)
    ret OneWay { mse: ss / df, df: df, k: k }
}

// kind 0 LSD (unadjusted t), 1 HSD (Tukey), 2 Scheffe, 3 SNK, 4 Duncan; the pair (i, j) answers difference mean_i - mean_j, the p value and the 95 percent limits at level alpha
fn pairwise(w: OneWay, mean: []const f64, size: []const f64, i: usize, j: usize, kind: usize, alpha: f64) -> (f64, f64, f64, f64) {
    if kind >= 3usize {
        let (od, op, ol, oh) = ordered_pair(w, mean, size, i, j, kind, alpha)
        ret (od, op, ol, oh)
    }
    let d = mean[i] - mean[j]
    let inv = 1.0f64 / size[i] + 1.0f64 / size[j]
    let se = math.sqrt[f64](w.mse * inv)
    var ad = d
    if ad < 0.0f64 { ad = 0.0f64 - ad }
    if kind == 0usize {
        let p = 2.0f64 * nb.pt(0.0f64 - ad / se, w.df, true, false)
        let h = nb.qt(1.0f64 - alpha / 2.0f64, w.df, true, false) * se
        ret (d, p, d - h, d + h)
    }
    if kind == 1usize {
        let s = math.sqrt[f64](w.mse / 2.0f64 * inv)
        let p = nb.ptukey(ad / s, 1.0f64, f64(w.k), w.df, false, false)
        let h = nb.qtukey(1.0f64 - alpha, 1.0f64, f64(w.k), w.df, true, false) * s
        ret (d, p, d - h, d + h)
    }
    let km1 = f64(w.k) - 1.0f64
    let p = nb.pf(d * d / (km1 * w.mse * inv), km1, w.df, false, false)
    let h = math.sqrt[f64](km1 * nb.qf(1.0f64 - alpha, km1, w.df, true, false)) * se
    ret (d, p, d - h, d + h)
}

// the SNK (kind 3) and Duncan (kind 4) comparisons of agricolae: the means are ranked in decreasing order (ties by position), a pair is compared over the number of
// ranks it spans, with the standard error sqrt(mse / n) (n the common size, or the harmonic mean of the sizes), the studentised-range critical value of that span,
// the p value rounded to four decimals as the package does, and limits dif -/+ critical value
fn ordered_pair(w: OneWay, mean: []const f64, size: []const f64, i: usize, j: usize, kind: usize, alpha: f64) -> (f64, f64, f64, f64) {
    let d = mean[i] - mean[j]
    var ad = d
    if ad < 0.0f64 { ad = 0.0f64 - ad }
    var ri = 1usize
    var rj = 1usize
    var q = 0usize
    while q < w.k {
        if mean[q] > mean[i] || (mean[q] == mean[i] && q < i) { ri += 1usize }
        if mean[q] > mean[j] || (mean[q] == mean[j] && q < j) { rj += 1usize }
        q += 1usize
    }
    var span = 1usize
    if ri >= rj { span = ri - rj + 1usize } else { span = rj - ri + 1usize }
    var same = true
    q = 1usize
    while q < w.k {
        if size[q] != size[0usize] { same = false }
        q += 1usize
    }
    var nr = size[0usize]
    if !same {
        var s = 0.0f64
        q = 0usize
        while q < w.k {
            s += 1.0f64 / size[q]
            q += 1usize
        }
        nr = 1.0f64 / (s / f64(w.k))
    }
    let sd = math.sqrt[f64](w.mse / nr)
    var pw = 1.0f64
    var level = 1.0f64 - alpha
    if kind == 4usize {
        pw = 1.0f64 / (f64(span) - 1.0f64)
        level = math.pow[f64](1.0f64 - alpha, f64(span) - 1.0f64)
    }
    let pt = nb.ptukey(ad / sd, 1.0f64, f64(span), w.df, true, false)
    let p0 = 1.0f64 - math.pow[f64](pt, pw)
    let p = math.floor[f64](p0 * 10000.0f64 + 0.5f64) / 10000.0f64
    let crit = nb.qtukey(level, 1.0f64, f64(span), w.df, true, false) * sd
    ret (d, p, d - crit, d + crit)
}

// ---- the grouping letters of agricolae's orderPvalue: the treatments in decreasing order of mean (ties by position), q holding the original indices; letter k of
// position i is bit k of mask[i] (letters a, b, c, ... in R's order). pv is the k by k matrix of the pairwise p values (the package's, rounded to four decimals).
fn group_letters(means: []const f64, pv: []const f64, n: usize, alpha: f64, q: []usize, mask: []u64) {
    var i = 0usize
    while i < n {
        var rank = 0usize
        var t = 0usize
        while t < n {
            if means[t] > means[i] || (means[t] == means[i] && t < i) { rank += 1usize }
            t += 1usize
        }
        q[rank] = i
        mask[i] = 0u64
        i += 1usize
    }
    var k = 0usize
    mask[0usize] = 1u64
    var j = 1usize
    var chequeo = 0usize
    while j < n {
        chequeo += 1usize
        if chequeo > n { break }
        var cambio1 = false
        var ii = j
        while ii <= n {
            let s = pv[q[ii - 1usize] * n + q[j - 1usize]] > alpha
            if s {
                // append letter k unless it is already the last letter of the label
                var hi = 0usize
                var any = false
                var b = 0usize
                while b < 64usize {
                    if (mask[ii - 1usize] >> u64(b)) & 1u64 == 1u64 {
                        hi = b
                        any = true
                    }
                    b += 1usize
                }
                if !any || hi != k { mask[ii - 1usize] = mask[ii - 1usize] | (1u64 << u64(k)) }
            } else {
                k += 1usize
                let cambio = ii
                cambio1 = false
                let ja = j
                mask[cambio - 1usize] = mask[cambio - 1usize] | (1u64 << u64(k))
                var v = ja
                while v <= cambio {
                    if pv[q[v - 1usize] * n + q[cambio - 1usize]] <= alpha {
                        j += 1usize
                        cambio1 = true
                    } else {
                        break
                    }
                    v += 1usize
                }
                break
            }
            ii += 1usize
        }
        if !cambio1 { j += 1usize }
    }
}

// ---- kruskal: agricolae's Kruskal-Wallis test with the post-hoc comparisons of the mean ranks (p.adj "none"): the statistic H, its chi-square p value, the error
// mean square of the ranks and the pairwise t comparisons. rmean and size are filled per group (the mean rank, the count).
type Kruskal = struct { h: f64, pchisq: f64, mse: f64, df: f64 }

fn kruskal(a: *mem.Arena, y: []const f64, grp: []const usize, k: usize, rmean: []f64, size: []f64) -> Kruskal {
    let n = y.len
    var r: Kruskal = zero
    let (rk, e) = mem.alloc[f64](a, n)
    if e != ok { ret r }
    var i = 0usize
    while i < n {
        var less = 0usize
        var eq = 0usize
        var t = 0usize
        while t < n {
            if y[t] < y[i] { less += 1usize }
            if y[t] == y[i] { eq += 1usize }
            t += 1usize
        }
        rk[i] = f64(less) + (f64(eq) + 1.0f64) / 2.0f64
        i += 1usize
    }
    var g = 0usize
    while g < k {
        rmean[g] = 0.0f64
        size[g] = 0.0f64
        g += 1usize
    }
    i = 0usize
    while i < n {
        rmean[grp[i] - 1usize] += rk[i]
        size[grp[i] - 1usize] += 1.0f64
        i += 1usize
    }
    var rs = 0.0f64
    g = 0usize
    while g < k {
        rs += rmean[g] * rmean[g] / size[g]
        g += 1usize
    }
    var ss = 0.0f64
    i = 0usize
    while i < n {
        ss += rk[i] * rk[i]
        i += 1usize
    }
    let nn = f64(n)
    let sdev = (ss - (nn * (nn + 1.0f64) * (nn + 1.0f64)) / 4.0f64) / (nn - 1.0f64)
    let h = (rs - (nn * (nn + 1.0f64) * (nn + 1.0f64)) / 4.0f64) / sdev
    g = 0usize
    while g < k {
        rmean[g] = rmean[g] / size[g]
        g += 1usize
    }
    r.h = h
    r.pchisq = 1.0f64 - nm.pchisq(h, f64(k) - 1.0f64, true, false)
    r.df = nn - f64(k)
    r.mse = sdev * ((nn - 1.0f64 - h) / (nn - f64(k)))
    ret r
}

// the pair (i, j) of the Kruskal post-hoc: difference of the mean ranks, the rounded p value and the limits
fn kruskal_pair(w: Kruskal, rmean: []const f64, size: []const f64, i: usize, j: usize, alpha: f64) -> (f64, f64, f64, f64) {
    let d = rmean[i] - rmean[j]
    let sd = math.sqrt[f64](w.mse * (1.0f64 / size[i] + 1.0f64 / size[j]))
    var ad = d
    if ad < 0.0f64 { ad = 0.0f64 - ad }
    let p0 = 2.0f64 * (1.0f64 - nb.pt(ad / sd, w.df, true, false))
    let p = math.floor[f64](p0 * 10000.0f64 + 0.5f64) / 10000.0f64
    let t = nb.qt(1.0f64 - alpha / 2.0f64, w.df, true, false)
    ret (d, p, d - t * sd, d + t * sd)
}

fn round4(p: f64) -> f64 { ret math.floor[f64](p * 10000.0f64 + 0.5f64) / 10000.0f64 }

// ---- friedman: agricolae's Friedman test of an nb by nt table (blocks by treatments, one value per cell) with the post-hoc comparisons of the rank sums; the
// within-block ranks average their ties, the statistic is adjusted for ties
type Friedman = struct { chisq: f64, pchisq: f64, f: f64, pf: f64, df: f64, a1: f64, ss: f64 }

// s receives the nt rank sums
fn friedman(a: *mem.Arena, y: []const f64, blocks: usize, nt: usize, s: []f64) -> Friedman {
    var r: Friedman = zero
    var j = 0usize
    while j < nt {
        s[j] = 0.0f64
        j += 1usize
    }
    var a1 = 0.0f64
    var i = 0usize
    while i < blocks {
        j = 0usize
        while j < nt {
            var less = 0usize
            var eq = 0usize
            var q = 0usize
            while q < nt {
                if y[i * nt + q] < y[i * nt + j] { less += 1usize }
                if y[i * nt + q] == y[i * nt + j] { eq += 1usize }
                q += 1usize
            }
            let rk = f64(less) + (f64(eq) + 1.0f64) / 2.0f64
            s[j] += rk
            a1 += rk * rk
            j += 1usize
        }
        i += 1usize
    }
    var ss = 0.0f64
    j = 0usize
    while j < nt {
        ss += s[j] * s[j]
        j += 1usize
    }
    let b = f64(blocks)
    let t = f64(nt)
    let c1 = b * t * (t + 1.0f64) * (t + 1.0f64) / 4.0f64
    let t1aj = (t - 1.0f64) * (ss - b * c1) / (a1 - c1)
    let t2aj = (b - 1.0f64) * t1aj / (b * (t - 1.0f64) - t1aj)
    r.chisq = t1aj
    r.pchisq = 1.0f64 - nm.pchisq(t1aj, t - 1.0f64, true, false)
    r.f = t2aj
    r.pf = 1.0f64 - nb.pf(t2aj, t - 1.0f64, (t - 1.0f64) * (b - 1.0f64), true, false)
    r.df = (b - 1.0f64) * (t - 1.0f64)
    r.a1 = a1
    r.ss = ss
    ret r
}

// the pair (i, j): the difference of the rank sums, the p value (four decimals), and the limits with the least significant difference rounded to two decimals
fn friedman_pair(fr: Friedman, s: []const f64, blocks: usize, i: usize, j: usize, alpha: f64) -> (f64, f64, f64, f64) {
    let d = s[i] - s[j]
    let sd = math.sqrt[f64](2.0f64 * (f64(blocks) * fr.a1 - fr.ss) / fr.df)
    var ad = d
    if ad < 0.0f64 { ad = 0.0f64 - ad }
    let p = round4(2.0f64 * (1.0f64 - nb2pt(ad / sd, fr.df)))
    let t = nb2qt(1.0f64 - alpha / 2.0f64, fr.df)
    let l = math.floor[f64](t * sd * 100.0f64 + 0.5f64) / 100.0f64
    ret (d, p, d - l, d + l)
}

fn nb2pt(x: f64, df: f64) -> f64 { ret nb.pt(x, df, true, false) }

fn nb2qt(p: f64, df: f64) -> f64 { ret nb.qt(p, df, true, false) }

// ---- waller.test: the Waller-Duncan K-ratio t test. The critical value is agricolae's bisection of t on (1, 20) (50 steps, stopping when the interval is under
// 5e-4) over four integrals on (1, Inf), each by the same QUADPACK routine R's integrate uses (qagi, tolerance eps^0.25, 100 subdivisions), rounded to three decimals.
type WCtx = struct { m: f64, q: f64, f: f64, fc: f64 }

fn wal_g(c: *WCtx, x: f64) -> f64 {
    ret math.pow[f64](x, 0.0f64 - (c.q + 3.0f64) / 2.0f64) * math.pow[f64](c.f + c.q * c.fc / x, 0.0f64 - (c.f + c.q - 1.0f64) / 2.0f64)
}

fn wal_b(c: *WCtx, x: f64) -> f64 { ret math.sqrt[f64]((c.f + c.q) * (x - 1.0f64) / (c.f * x + c.q * c.fc)) }

fn wal_h(c: *WCtx, z: f64) -> f64 {
    ret ((c.f + c.q + z * z) / (c.f + c.q - 1.0f64)) * nb.dt(z, c.q + c.f, false) + z * nb.pt(z, c.q + c.f, true, false)
}

fn wal_int(c: *WCtx, x: f64) -> f64 { ret math.sqrt[f64](x - 1.0f64) * wal_g(c, x) * wal_h(c, c.m * wal_b(c, x)) }

fn wal_integral(a: *mem.Arena, c: *WCtx, m: f64) -> f64 {
    c.m = m
    let eps = math.pow[f64](2.220446049250313e-16f64, 0.25f64)
    let (r, e) = qp.qagi[WCtx](a, c, wal_int, 1.0f64, 1i64, eps, eps, 100usize)
    if e != ok { ret 0.0f64 }
    ret r.result
}

fn waller(a: *mem.Arena, k: f64, q: f64, f: f64, fc: f64) -> f64 {
    var c = WCtx { m: 0.0f64, q: q, f: f, fc: fc }
    var a0 = 1.0f64
    var b0 = 20.0f64
    var t = 0.0f64
    var i = 0usize
    while i < 50usize {
        t = (b0 + a0) / 2.0f64
        let in0 = wal_integral(a, &c, t)
        let id0 = wal_integral(a, &c, 0.0f64 - t)
        let in1 = wal_integral(a, &c, a0)
        let id1 = wal_integral(a, &c, 0.0f64 - a0)
        let prod = (k - in0 / id0) * (k - in1 / id1)
        if prod <= 0.0f64 { b0 = t }
        if prod > 0.0f64 { a0 = t }
        var gap = b0 - a0
        if gap < 0.0f64 { gap = 0.0f64 - gap }
        if gap <= 0.0005f64 { break }
        i += 1usize
    }
    ret math.floor[f64](t * 1000.0f64 + 0.5f64) / 1000.0f64
}

// the F value of the treatment effect of a one-way layout (the between mean square over the error mean square); mean and size as filled by one_way
fn waller_fc(w: OneWay, y: []const f64, mean: []const f64, size: []const f64) -> f64 {
    var tot = 0.0f64
    var i = 0usize
    while i < y.len {
        tot += y[i]
        i += 1usize
    }
    let gm = tot / f64(y.len)
    var ssb = 0.0f64
    var g = 0usize
    while g < w.k {
        ssb += size[g] * (mean[g] - gm) * (mean[g] - gm)
        g += 1usize
    }
    ret (ssb / (f64(w.k) - 1.0f64)) / w.mse
}

// the pairwise verdicts of the Waller-Duncan test: the minimum significant difference of the pair (i, j) is tw sqrt(mse (1 / n_i + 1 / n_j))
fn waller_msd(w: OneWay, tw: f64, size: []const f64, i: usize, j: usize) -> f64 { ret tw * math.sqrt[f64](w.mse * (1.0f64 / size[i] + 1.0f64 / size[j])) }

// ---- the randomised designs of agricolae under set.seed(seed, kinds = "Mersenne-Twister") (the package's default Super-Duper generator is not available): the
// treatment of each plot, as 0-based treatment codes in plot order.

// design.crd(trt, r): the treatments in order, repeated r[i] times, then sample(y, length(y)); out has sum(r) entries; rep receives the replicate number of each plot
// (the plots of a treatment numbered in plot order)
fn design_crd(a: *mem.Arena, rng: *rr.Rng, r: []const usize, out: []usize, rep: []usize) -> err {
    var total = 0usize
    var i = 0usize
    while i < r.len {
        total += r[i]
        i += 1usize
    }
    let (y, e1) = mem.alloc[usize](a, total)
    if e1 != ok { ret e1 }
    var c = 0usize
    i = 0usize
    while i < r.len {
        var q = 0usize
        while q < r[i] {
            y[c] = i
            c += 1usize
            q += 1usize
        }
        i += 1usize
    }
    let (idx, e2) = rr.sample_int(a, rng, i64(total), i64(total), false)
    if e2 != ok { ret e2 }
    i = 0usize
    while i < total {
        out[i] = y[usize(idx[i]) - 1usize]
        i += 1usize
    }
    let (seen, e3) = mem.alloc[usize](a, r.len)
    if e3 != ok { ret e3 }
    i = 0usize
    while i < r.len {
        seen[i] = 0usize
        i += 1usize
    }
    i = 0usize
    while i < total {
        seen[out[i]] += 1usize
        rep[i] = seen[out[i]]
        i += 1usize
    }
    ret ok
}

// design.rcbd(trt, r, first): r blocks of the ntr treatments, each block sample(trt, ntr); with first FALSE the first block is the treatments in order (its draw
// is still consumed). out has ntr * r entries in plot order.
fn design_rcbd(a: *mem.Arena, rng: *rr.Rng, ntr: usize, blocks: usize, first: bool, out: []usize) -> err {
    var b = 0usize
    while b < blocks {
        let (idx, e) = rr.sample_int(a, rng, i64(ntr), i64(ntr), false)
        if e != ok { ret e }
        var j = 0usize
        while j < ntr {
            out[b * ntr + j] = usize(idx[j]) - 1usize
            if b == 0usize && !first { out[j] = j }
            j += 1usize
        }
        b += 1usize
    }
    ret ok
}

// design.lsd(trt, first): the cyclic r by r Latin square, its columns after the first permuted by sample(2:r, r - 1) and, with first, its rows by sample(1:r, r); out
// holds the treatment codes in plot order (the square read column by column, as trt[a] does). r at least 3.
fn design_lsd(a: *mem.Arena, rng: *rr.Rng, r: usize, first: bool, out: []usize) -> err {
    let (sq, e0) = mem.alloc[usize](a, r * r)
    let (cols, e1) = mem.alloc[usize](a, r)
    let (rows, e2) = mem.alloc[usize](a, r)
    if e0 != ok || e1 != ok || e2 != ok { ret e0 }
    var i = 0usize
    while i < r {
        var j = 0usize
        while j < r {
            // 1-based i + j - 1, wrapped into 1..r, stored 0-based
            sq[i * r + j] = (i + j) % r
            j += 1usize
        }
        i += 1usize
    }
    let (idx, e3) = rr.sample_int(a, rng, i64(r - 1usize), i64(r - 1usize), false)
    if e3 != ok { ret e3 }
    cols[0usize] = 0usize
    i = 1usize
    while i < r {
        // sample(2:r, r - 1) is 2:r indexed by the permutation: the 1-based column idx + 1
        cols[i] = usize(idx[i - 1usize])
        i += 1usize
    }
    i = 0usize
    while i < r {
        rows[i] = i
        i += 1usize
    }
    if first {
        let (ridx, e4) = rr.sample_int(a, rng, i64(r), i64(r), false)
        if e4 != ok { ret e4 }
        i = 0usize
        while i < r {
            rows[i] = usize(ridx[i]) - 1usize
            i += 1usize
        }
    }
    // the square after the column and row permutations, read column by column
    var c = 0usize
    while c < r {
        var q = 0usize
        while q < r {
            out[c * r + q] = sq[rows[q] * r + cols[c]]
            q += 1usize
        }
        c += 1usize
    }
    ret ok
}

// design.split over an rcbd (applied = 0) or an lsd (applied = 1): the whole-plot plan from the same stream, then sample(trt2, n2) for every whole plot, in plot order;
// plan holds the whole-plot treatments (nplot entries), sub the subplot treatments (nplot * n2, the plot's subplots together)
fn design_split(a: *mem.Arena, rng: *rr.Rng, applied: usize, n1: usize, blocks: usize, n2: usize, first: bool, plan: []usize, sub: []usize) -> err {
    var nplot = n1 * blocks
    if applied == 1usize { nplot = n1 * n1 }
    var e = ok
    if applied == 0usize {
        e = design_rcbd(a, rng, n1, blocks, first, plan)
    } else {
        e = design_lsd(a, rng, n1, first, plan)
    }
    if e != ok { ret e }
    var p = 0usize
    while p < nplot {
        let (idx, e5) = rr.sample_int(a, rng, i64(n2), i64(n2), false)
        if e5 != ok { ret e5 }
        var s = 0usize
        while s < n2 {
            sub[p * n2 + s] = usize(idx[s]) - 1usize
            s += 1usize
        }
        p += 1usize
    }
    ret ok
}

// design.bib's replication: the first r in 2..maxRep with r (k - 1) / (v - 1) and v r / k both whole numbers (0 when none)
fn bib_r(v: usize, k: usize, max_rep: usize) -> usize {
    var i = 2usize
    while i <= max_rep {
        if (i * (k - 1usize)) % (v - 1usize) == 0usize && (v * i) % k == 0usize { ret i }
        i += 1usize
    }
    ret 0usize
}

// design.bib(trt, k): AlgDesign's optBlock (D criterion, five repeats, the within-block treatment-contrast model) finds a balanced incomplete block design from the
// stream, then the blocks are permuted by sample(1:b, b) and each block's treatments by sample(1:k, k); out holds the 0-based treatments of the b * k plots
fn design_bib(a: *mem.Arena, rng: *rr.Rng, v: usize, k: usize, r: usize, out: []usize) -> err {
    let b = v * r / k
    let (x, e0) = mem.alloc[f64](a, v * (v - 1usize))
    let (sizes, e1) = mem.alloc[usize](a, b)
    let (md, e2) = mem.alloc[usize](a, b * k)
    if e0 != ok || e1 != ok || e2 != ok { ret e0 }
    var i = 0usize
    while i < v * (v - 1usize) {
        x[i] = 0.0f64
        i += 1usize
    }
    i = 1usize
    while i < v {
        x[i * (v - 1usize) + (i - 1usize)] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < b {
        sizes[i] = k
        i += 1usize
    }
    var none: [1]i64 = zero
    let (res, eb) = blk.block_optimize(a, rng, x, v, v - 1usize, sizes, none[0usize..0usize], false, 5i64)
    if eb != ok { ret eb }
    // the rows of each block sorted, 1-based as optBlock answers them
    i = 0usize
    while i < b {
        var j = 0usize
        while j < k {
            let val = res.block_array[i * k + j]
            var q = j
            while q > 0usize && res.block_array[i * k + q - 1usize] > val {
                res.block_array[i * k + q] = res.block_array[i * k + q - 1usize]
                q -= 1usize
            }
            res.block_array[i * k + q] = val
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < b * k {
        md[i] = usize(res.block_array[i]) - 1usize
        i += 1usize
    }
    let (bp, e3) = rr.sample_int(a, rng, i64(b), i64(b), false)
    if e3 != ok { ret e3 }
    let (mp, e4) = mem.alloc[usize](a, b * k)
    if e4 != ok { ret e4 }
    i = 0usize
    while i < b {
        let src = usize(bp[i]) - 1usize
        var j = 0usize
        while j < k {
            mp[i * k + j] = md[src * k + j]
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < b {
        let (bi, e5) = rr.sample_int(a, rng, i64(k), i64(k), false)
        if e5 != ok { ret e5 }
        var j = 0usize
        while j < k {
            out[i * k + j] = mp[i * k + usize(bi[j]) - 1usize]
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// ---- AMMI for a complete genotype by environment table of means with a scalar number of replicates and a given error mean square (agricolae's AMMI): the residuals of
// the additive model, their singular value decomposition, the analysis table of the interaction axes (percent and cumulative percent of the interaction sum of squares,
// degrees of freedom, sums of squares, mean squares, F and its p value, rounded as the package rounds them) and the genotype and environment scores U sqrt(L), V sqrt(L)
type Ammi = struct { rows: usize, m: usize, percent: []f64, acum: []f64, df: []f64, ss: []f64, ms: []f64, f: []f64, p: []f64, scoreg: []f64, scoree: []f64, gmean: []f64, emean: []f64 }

fn round_d(v: f64, d: i32) -> f64 {
    var m = 1.0f64
    var i = 0i32
    while i < d {
        m = m * 10.0f64
        i += 1i32
    }
    ret math.floor[f64](v * m + 0.5f64) / m
}

// y is ngen by nenv, row-major (genotypes in rows)
fn ammi(a: *mem.Arena, y: []const f64, ngen: usize, nenv: usize, nrep: f64, mse: f64) -> (Ammi, err) {
    var out: Ammi = zero
    var m = ngen
    if nenv < m { m = nenv }
    let (res, e0) = mem.alloc[f64](a, ngen * nenv)
    let (gm, e1) = mem.alloc[f64](a, ngen)
    let (em, e2) = mem.alloc[f64](a, nenv)
    if e0 != ok || e1 != ok || e2 != ok { ret (out, mem.Full) }
    var grand = 0.0f64
    var g = 0usize
    while g < ngen {
        gm[g] = 0.0f64
        g += 1usize
    }
    var e = 0usize
    while e < nenv {
        em[e] = 0.0f64
        e += 1usize
    }
    g = 0usize
    while g < ngen {
        e = 0usize
        while e < nenv {
            gm[g] += y[g * nenv + e] / f64(nenv)
            em[e] += y[g * nenv + e] / f64(ngen)
            grand += y[g * nenv + e] / f64(ngen * nenv)
            e += 1usize
        }
        g += 1usize
    }
    // column-major for the decomposition
    g = 0usize
    while g < ngen {
        e = 0usize
        while e < nenv {
            res[e * ngen + g] = y[g * nenv + e] - gm[g] - em[e] + grand
            e += 1usize
        }
        g += 1usize
    }
    let (sv, e3) = mem.alloc[f64](a, m)
    let (uu, e4) = mem.alloc[f64](a, ngen * m)
    let (vt, e5) = mem.alloc[f64](a, m * nenv)
    if e3 != ok || e4 != ok || e5 != ok { ret (out, mem.Full) }
    let es = gsd.svd_all(a, res, ngen, nenv, sv, uu, vt)
    if es != ok { ret (out, es) }
    let (ssv, e6) = mem.alloc[f64](a, m)
    let (pc, e7) = mem.alloc[f64](a, m)
    let (ac, e8) = mem.alloc[f64](a, m)
    let (dfv, e9) = mem.alloc[f64](a, m)
    let (msv, e10) = mem.alloc[f64](a, m)
    let (fv, e11) = mem.alloc[f64](a, m)
    let (pv, e12) = mem.alloc[f64](a, m)
    if e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok { ret (out, mem.Full) }
    var suma = 0.0f64
    var i = 0usize
    while i < m {
        ssv[i] = sv[i] * sv[i] * nrep
        suma += ssv[i]
        dfv[i] = 0.0f64
        ac[i] = 0.0f64
        msv[i] = 0.0f64
        fv[i] = 0.0f64
        pv[i] = 0.0f64
        i += 1usize
    }
    let dfe = f64(nenv) * (f64(ngen) - 1.0f64) * (nrep - 1.0f64)
    var rows = 0usize
    var acumula = 0.0f64
    i = 0usize
    while i + 1usize < m {
        let df = (f64(ngen) - 1.0f64) + (f64(nenv) - 1.0f64) - (2.0f64 * f64(i + 1usize) - 1.0f64)
        if df <= 0.0f64 { break }
        dfv[i] = df
        acumula += (1.0f64 / suma) * ssv[i] * 100.0f64
        ac[i] = acumula
        msv[i] = ssv[i] / df
        fv[i] = round_d(msv[i] / mse, 2i32)
        pv[i] = round_d(1.0f64 - nb.pf(fv[i], df, dfe, true, false), 4i32)
        rows += 1usize
        i += 1usize
    }
    i = 0usize
    while i < m {
        pc[i] = round_d((1.0f64 / suma) * ssv[i] * 100.0f64, 1i32)
        ac[i] = round_d(ac[i], 1i32)
        msv[i] = round_d(msv[i], 6i32)
        ssv[i] = round_d(ssv[i], 6i32)
        i += 1usize
    }
    let (sg, e13) = mem.alloc[f64](a, ngen * m)
    let (se, e14) = mem.alloc[f64](a, nenv * m)
    if e13 != ok || e14 != ok { ret (out, mem.Full) }
    var c = 0usize
    while c < m {
        let r = math.sqrt[f64](sv[c])
        g = 0usize
        while g < ngen {
            sg[g * m + c] = uu[c * ngen + g] * r
            g += 1usize
        }
        e = 0usize
        while e < nenv {
            se[e * m + c] = vt[e * m + c] * r
            e += 1usize
        }
        c += 1usize
    }
    out.rows = rows
    out.m = m
    out.percent = pc
    out.acum = ac
    out.df = dfv
    out.ss = ssv
    out.ms = msv
    out.f = fv
    out.p = pv
    out.scoreg = sg
    out.scoree = se
    out.gmean = gm
    out.emean = em
    ret (out, ok)
}

// design.lattice(trt, r) for k * k treatments: the book's treatment codes (0-based) of the r = 2 or 3 replicates in plot order (r > 3 not available). Under the hood it
// reproduces a quirk: the Latin square it needs comes from design.lsd(1:k), called with seed 0, which draws runif(1) from the running stream, takes .Random.seed[3] (the
// second state word of Super-Duper, the first Mersenne-Twister word otherwise) as its seed and reseeds with the Super-Duper generator, so the last three draws come from that
// new stream.
fn design_lattice(a: *mem.Arena, rng: *rr.Rng, k: usize, r: usize, out: []usize) -> err {
    let nt = k * k
    let (s0, e0) = rr.sample_int(a, rng, i64(nt), i64(nt), false)
    if e0 != ok { ret e0 }
    let (c1, e1) = mem.alloc[usize](a, nt)
    let (c2, e2) = mem.alloc[usize](a, nt)
    let (c3, e3) = mem.alloc[usize](a, nt)
    let (lat, e4) = mem.alloc[usize](a, nt)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret e1 }
    var i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            // c1[a, b] = s[k (a - 1) + b], 0-based codes
            c1[i * k + j] = usize(s0[i * k + j]) - 1usize
            j += 1usize
        }
        i += 1usize
    }
    // design.lsd(1:k) with seed 0: one uniform from the running stream, its state word as the new seed
    let _ = rr.unif(rng)
    var word = rng.i2
    if rng.kind != 1i64 { word = rng.mt[0usize] }
    var lrng: rr.Rng = zero
    rr.seed_super(&lrng, i64(word))
    let el = design_lsd(a, &lrng, k, true, lat)
    if el != ok { ret el }
    // c3 = t(matrix(Z[order(latino)], k)) with Z the row-major c1 and latino the square's treatment codes (as strings; a stable order)
    let (ord, e5) = mem.alloc[usize](a, nt)
    if e5 != ok { ret e5 }
    i = 0usize
    while i < nt {
        var rank = 0usize
        var q = 0usize
        while q < nt {
            if lat[q] < lat[i] || (lat[q] == lat[i] && q < i) { rank += 1usize }
            q += 1usize
        }
        ord[rank] = i
        i += 1usize
    }
    // matrix(Z[ord], k) is column-major, so its transpose has element (u, v) = Z[ord[v * k + u]]... entry (u, v) of t(.) is entry (v, u) of the matrix = Z[ord[u * k + v]]
    i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            c3[i * k + j] = c1[ord[i * k + j]]
            j += 1usize
        }
        i += 1usize
    }
    // c2 = t(c1)
    i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            c2[i * k + j] = c1[j * k + i]
            j += 1usize
        }
        i += 1usize
    }
    // the three row permutations from the reseeded stream
    let (p1, e6) = rr.sample_int(a, &lrng, i64(k), i64(k), false)
    if e6 != ok { ret e6 }
    let (p2, e7) = rr.sample_int(a, &lrng, i64(k), i64(k), false)
    if e7 != ok { ret e7 }
    let (p3, e8) = rr.sample_int(a, &lrng, i64(k), i64(k), false)
    if e8 != ok { ret e8 }
    i = 0usize
    while i < k {
        var j = 0usize
        while j < k {
            out[i * k + j] = c1[(usize(p1[i]) - 1usize) * k + j]
            out[nt + i * k + j] = c2[(usize(p2[i]) - 1usize) * k + j]
            out[2usize * nt + i * k + j] = c3[(usize(p3[i]) - 1usize) * k + j]
            j += 1usize
        }
        i += 1usize
    }
    let _ = r
    ret ok
}

// design.alpha(trt, k, r) for ntr treatments in blocks of k (ntr a multiple of k, k at least 3) and r replicates from agricolae's four alpha-generator series (I: r = 2;
// II: r = 3 with an odd number of blocks; III: r = 3 with an even number; IV: r = 4 with an odd number not divisible by 3): out holds the 0-based treatment codes of the
// r * ntr plots, replicate by replicate, block by block. Answers NotAvailable-like failure (a non-ok error) when no series applies.
error NoSeries

fn design_alpha(a: *mem.Arena, rng: *rr.Rng, ntr: usize, k: usize, r: usize, out: []usize) -> err {
    let s = ntr / k
    if ntr % k != 0usize || k < 3usize { ret NoSeries }
    let (al, e0) = mem.alloc[usize](a, k * r)
    if e0 != ok { ret e0 }
    var i = 0usize
    while i < k * r {
        al[i] = 0usize
        i += 1usize
    }
    // al[row * r + m]
    var series = 0usize
    if r == 2usize && k <= s { series = 1usize }
    if r == 3usize && s % 2usize != 0usize && k <= s { series = 2usize }
    if r == 3usize && s % 2usize == 0usize && k < s { series = 3usize }
    if r == 4usize && s % 2usize != 0usize && s % 3usize != 0usize && k <= s { series = 4usize }
    if series == 0usize { ret NoSeries }
    al[1usize * r + 1usize] = 1usize
    if series == 2usize || series == 4usize { al[1usize * r + 2usize] = s - 1usize }
    if series == 3usize { al[1usize * r + 2usize] = s / 2usize }
    if series == 4usize { al[1usize * r + 3usize] = (s + 1usize) / 2usize }
    i = 2usize
    while i < k {
        al[i * r + 1usize] = al[(i - 1usize) * r + 1usize] + 1usize
        if series == 2usize || series == 4usize { al[i * r + 2usize] = al[(i - 1usize) * r + 2usize] - 1usize }
        if series == 3usize { al[i * r + 2usize] = al[(i - 2usize) * r + 2usize] + 1usize }
        if series == 4usize { al[i * r + 3usize] = al[(i - 2usize) * r + 3usize] + 1usize }
        i += 1usize
    }
    // cc[(m * s + col) * k + row]
    let (cc, e1) = mem.alloc[usize](a, r * s * k)
    let (tmp, e2) = mem.alloc[usize](a, k)
    let (tmp2, e3) = mem.alloc[usize](a, s * k)
    if e1 != ok || e2 != ok || e3 != ok { ret e1 }
    var m = 0usize
    while m < r {
        var j = 0usize
        while j < k {
            cc[(m * s + 0usize) * k + j] = al[j * r + m]
            var c = 1usize
            while c < s {
                var v = cc[(m * s + c - 1usize) * k + j] + 1usize
                if v >= s { v = 0usize }
                cc[(m * s + c) * k + j] = v
                c += 1usize
            }
            j += 1usize
        }
        m += 1usize
    }
    m = 0usize
    while m < r {
        var j = 0usize
        while j < k {
            var c = 0usize
            while c < s {
                cc[(m * s + c) * k + j] += j * s
                c += 1usize
            }
            j += 1usize
        }
        m += 1usize
    }
    // within each block of each replicate the rows are permuted by sample(1:k, k)
    m = 0usize
    while m < r {
        var c = 0usize
        while c < s {
            let (pm, e4) = rr.sample_int(a, rng, i64(k), i64(k), false)
            if e4 != ok { ret e4 }
            var j = 0usize
            while j < k {
                tmp[j] = cc[(m * s + c) * k + usize(pm[j]) - 1usize]
                j += 1usize
            }
            j = 0usize
            while j < k {
                cc[(m * s + c) * k + j] = tmp[j]
                j += 1usize
            }
            c += 1usize
        }
        m += 1usize
    }
    // then the blocks of each replicate by sample(1:s, s)
    m = 0usize
    while m < r {
        let (pb, e5) = rr.sample_int(a, rng, i64(s), i64(s), false)
        if e5 != ok { ret e5 }
        var c = 0usize
        while c < s {
            var j = 0usize
            while j < k {
                tmp2[c * k + j] = cc[(m * s + usize(pb[c]) - 1usize) * k + j]
                j += 1usize
            }
            c += 1usize
        }
        var q = 0usize
        while q < s * k {
            cc[m * s * k + q] = tmp2[q]
            q += 1usize
        }
        m += 1usize
    }
    let (bp, e6) = rr.sample_int(a, rng, i64(ntr), i64(ntr), false)
    if e6 != ok { ret e6 }
    m = 0usize
    while m < r {
        var q = 0usize
        while q < ntr {
            out[m * ntr + q] = usize(bp[cc[m * s * k + q]]) - 1usize
            q += 1usize
        }
        m += 1usize
    }
    ret ok
}

// ---- stability.nonpar: the nonparametric stability measures of Huehn and Nassar for a k genotypes by n environments table (row-major): per genotype the mean, the rank of
// the mean, s1 (the mean absolute difference of the adjusted-yield ranks over the pairs of environments), s2 (their variance), and the Z statistics against the
// expectations es1, es2 and variances vs1, vs2
type StabNp = struct { es1: f64, es2: f64, vs1: f64, vs2: f64, chi_ind: f64, chi_sum: f64, sum_z1: f64, sum_z2: f64 }

// column-wise average-tie ranks of an k by n table
fn rank_cols(m: []const f64, k: usize, n: usize, out: []f64) {
    var j = 0usize
    while j < n {
        var i = 0usize
        while i < k {
            var less = 0usize
            var eq = 0usize
            var q = 0usize
            while q < k {
                if m[q * n + j] < m[i * n + j] { less += 1usize }
                if m[q * n + j] == m[i * n + j] { eq += 1usize }
                q += 1usize
            }
            out[i * n + j] = f64(less) + (f64(eq) + 1.0f64) / 2.0f64
            i += 1usize
        }
        j += 1usize
    }
}

// mean, rank, s1, z1, s2 and z2 go to the k-entry arrays
fn stability_nonpar(a: *mem.Arena, y: []const f64, k: usize, n: usize, mean: []f64, rank: []f64, s1: []f64, z1: []f64, s2: []f64, z2: []f64) -> (StabNp, err) {
    var out: StabNp = zero
    let (cy, e0) = mem.alloc[f64](a, k * n)
    let (rc, e1) = mem.alloc[f64](a, k * n)
    if e0 != ok || e1 != ok { ret (out, mem.Full) }
    var grand = 0.0f64
    var i = 0usize
    while i < k {
        var m = 0.0f64
        var j = 0usize
        while j < n {
            m += y[i * n + j] / f64(n)
            j += 1usize
        }
        mean[i] = m
        grand += m / f64(k)
        i += 1usize
    }
    i = 0usize
    while i < k {
        var j = 0usize
        while j < n {
            cy[i * n + j] = y[i * n + j] - (mean[i] - grand)
            j += 1usize
        }
        i += 1usize
    }
    rank_cols(cy, k, n, rc)
    let nn = f64(n) * (f64(n) - 1.0f64) / 2.0f64
    i = 0usize
    while i < k {
        var sq = 0.0f64
        var j = 0usize
        while j + 1usize < n {
            var jj = j + 1usize
            while jj < n {
                var d = rc[i * n + j] - rc[i * n + jj]
                if d < 0.0f64 { d = 0.0f64 - d }
                sq += d
                jj += 1usize
            }
            j += 1usize
        }
        s1[i] = sq / nn
        var rm = 0.0f64
        j = 0usize
        while j < n {
            rm += rc[i * n + j] / f64(n)
            j += 1usize
        }
        var v = 0.0f64
        j = 0usize
        while j < n {
            v += (rc[i * n + j] - rm) * (rc[i * n + j] - rm)
            j += 1usize
        }
        s2[i] = v / (f64(n) - 1.0f64)
        i += 1usize
    }
    let kk = f64(k)
    let fnn = f64(n)
    let k2 = kk * kk
    let es1 = (k2 - 1.0f64) / (3.0f64 * kk)
    let es2 = (k2 - 1.0f64) / 12.0f64
    let vs1 = k2 * ((kk * kk - 4.0f64) * (fnn + 3.0f64) + 30.0f64) / (45.0f64 * kk * kk * fnn * (fnn - 1.0f64))
    let vs2 = (k2 - 1.0f64) * (2.0f64 * (k2 - 4.0f64) * (fnn - 1.0f64) + 5.0f64 * (k2 - 1.0f64)) / (360.0f64 * fnn * (fnn - 1.0f64))
    var sz1 = 0.0f64
    var sz2 = 0.0f64
    i = 0usize
    while i < k {
        z1[i] = (s1[i] - es1) * (s1[i] - es1) / vs1
        z2[i] = (s2[i] - es2) * (s2[i] - es2) / vs2
        sz1 += z1[i]
        sz2 += z2[i]
        i += 1usize
    }
    // the rank of the genotype means (average ties)
    i = 0usize
    while i < k {
        var less = 0usize
        var eq = 0usize
        var q = 0usize
        while q < k {
            if mean[q] < mean[i] { less += 1usize }
            if mean[q] == mean[i] { eq += 1usize }
            q += 1usize
        }
        rank[i] = f64(less) + (f64(eq) + 1.0f64) / 2.0f64
        i += 1usize
    }
    out.es1 = es1
    out.es2 = es2
    out.vs1 = vs1
    out.vs2 = vs2
    out.chi_ind = nm.qchisq(1.0f64 - 0.05f64 / kk, 1.0f64, true, false)
    out.chi_sum = nm.qchisq(0.95f64, kk, true, false)
    out.sum_z1 = sz1
    out.sum_z2 = sz2
    ret (out, ok)
}
