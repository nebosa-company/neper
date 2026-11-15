// The numeric core of R's rstatix on top of base R's tests: `p.adjust` (holm, hochberg, hommel,
// bonferroni, BH, BY), Games-Howell and Dunn pairwise comparisons, pairwise t tests (pooled SD,
// Welch, paired), Welch's one-way ANOVA, Friedman and Cochran's Q, the Kruskal-Wallis effect size
// (eta2 and epsilon2), Cohen's d with Hedges' correction, one-way eta squared, boxplot outliers and
// Mahalanobis distances with the 0.999 chi-squared outlier flag. Groups lie consecutively in
// `values`, `sizes[g]` long; a pair is (first, second) with first < second, as rstatix prints
// group1 and group2, and `estimate` is the mean (or mean rank) of the second minus the first.
//
// Not here: wilcox_effsize and pairwise_wilcox_test (exact and normal-approximation p of
// `wilcox.test`, with confidence intervals), cohens_d confidence intervals, a `ref.group`
// restriction (pick the pairs from the result), omega squared, and the data-frame plumbing.

use e.math
use e.math.dist
use e.math.nmath
use e.math.nmath_beta as nb
use e.mem

type GamesHowell = struct { first: usize, second: usize, estimate: f64, conf_low: f64, conf_high: f64, se: f64, statistic: f64, df: f64, p_adj: f64 }
type Dunn = struct { first: usize, second: usize, estimate: f64, statistic: f64, p: f64, p_adj: f64 }
type PairT = struct { first: usize, second: usize, p: f64, p_adj: f64 }
type Test = struct { statistic: f64, df1: f64, df2: f64, p: f64 }
error TooSmall
error Invalid

const NONE: u8 = 0u8
const BONFERRONI: u8 = 1u8
const HOLM: u8 = 2u8
const HOCHBERG: u8 = 3u8
const HOMMEL: u8 = 4u8
const BH: u8 = 5u8
const BY: u8 = 6u8

fn rs_nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn rs_mean(v: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += v[i]
        i += 1usize
    }
    ret s / f64(v.len)
}

fn rs_var(v: []const f64) -> f64 {
    let m = rs_mean(v)
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += (v[i] - m) * (v[i] - m)
        i += 1usize
    }
    ret s / f64(v.len - 1usize)
}

fn rs_group(values: []const f64, sizes: []const usize, g: usize) -> []const f64 {
    var at = 0usize
    var i = 0usize
    while i < g {
        at += sizes[i]
        i += 1usize
    }
    ret values[at..at + sizes[g]]
}

fn rs_total(sizes: []const usize) -> usize {
    var t = 0usize
    var i = 0usize
    while i < sizes.len {
        t += sizes[i]
        i += 1usize
    }
    ret t
}

// Stable insertion order of `p`, ascending or descending, as R's order().
fn rs_order(p: []const f64, descending: bool, ord: []usize) {
    var i = 0usize
    while i < p.len {
        ord[i] = i
        var j = i
        while j > 0usize {
            var swap = p[ord[j]] < p[ord[j - 1usize]]
            if descending { swap = p[ord[j]] > p[ord[j - 1usize]] }
            if !swap { break }
            let t = ord[j]
            ord[j] = ord[j - 1usize]
            ord[j - 1usize] = t
            j -= 1usize
        }
        i += 1usize
    }
}

fn rs_min1(x: f64) -> f64 {
    if x > 1.0f64 { ret 1.0f64 }
    ret x
}

// R's p.adjust in place, for p-values without NA.
fn p_adjust(a: *mem.Arena, method: u8, p: []f64) -> err {
    let n = p.len
    if n <= 1usize || method == NONE { ret ok }
    var how = method
    if n == 2usize && how == HOMMEL { how = HOCHBERG }
    let (ord, e1) = mem.alloc[usize](a, n)
    if e1 != ok { ret e1 }
    let (out, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret e2 }
    let nf = f64(n)
    if how == BONFERRONI {
        var i = 0usize
        while i < n {
            p[i] = rs_min1(p[i] * nf)
            i += 1usize
        }
        ret ok
    }
    if how == HOLM {
        rs_order(p, false, ord)
        var run = 0.0f64
        var i = 0usize
        while i < n {
            let v = f64(n - i) * p[ord[i]]
            if v > run { run = v }
            out[ord[i]] = rs_min1(run)
            i += 1usize
        }
    } else if how == HOCHBERG || how == BH || how == BY {
        rs_order(p, true, ord)
        var q = 1.0f64
        if how == BY {
            var k = 1usize
            q = 0.0f64
            while k <= n {
                q += 1.0f64 / f64(k)
                k += 1usize
            }
        }
        var run = 1.0f64
        var i = 0usize
        while i < n {
            let rank = f64(n - i)
            var v = 0.0f64
            if how == HOCHBERG { v = (f64(i) + 1.0f64) * p[ord[i]] } else { v = q * nf / rank * p[ord[i]] }
            if v < run { run = v }
            out[ord[i]] = rs_min1(run)
            i += 1usize
        }
    } else {
        rs_order(p, false, ord)
        let (ps, e3) = mem.alloc[f64](a, n)
        if e3 != ok { ret e3 }
        let (qq, e4) = mem.alloc[f64](a, n)
        if e4 != ok { ret e4 }
        let (pa, e5) = mem.alloc[f64](a, n)
        if e5 != ok { ret e5 }
        var i = 0usize
        var lowest = 0.0f64
        while i < n {
            ps[i] = p[ord[i]]
            let t = nf * ps[i] / f64(i + 1usize)
            if i == 0usize || t < lowest { lowest = t }
            i += 1usize
        }
        i = 0usize
        while i < n {
            qq[i] = lowest
            pa[i] = lowest
            i += 1usize
        }
        var m = n - 1usize
        while m >= 2usize {
            let mf = f64(m)
            let n1 = n - m + 1usize
            var q1 = 0.0f64
            var t = 0usize
            while t < m - 1usize {
                let v = mf * ps[n1 + t] / f64(t + 2usize)
                if t == 0usize || v < q1 { q1 = v }
                t += 1usize
            }
            i = 0usize
            while i < n1 {
                var v = mf * ps[i]
                if q1 < v { v = q1 }
                qq[i] = v
                i += 1usize
            }
            i = n1
            while i < n {
                qq[i] = qq[n - m]
                i += 1usize
            }
            i = 0usize
            while i < n {
                if qq[i] > pa[i] { pa[i] = qq[i] }
                i += 1usize
            }
            m -= 1usize
        }
        i = 0usize
        while i < n {
            var v = pa[i]
            if ps[i] > v { v = ps[i] }
            out[ord[i]] = v
            i += 1usize
        }
    }
    var i = 0usize
    while i < n {
        p[i] = out[i]
        i += 1usize
    }
    ret ok
}

fn rs_check(sizes: []const usize, values: []const f64, minimum: usize) -> err {
    if sizes.len < 2usize { ret Invalid }
    var g = 0usize
    while g < sizes.len {
        if sizes[g] < minimum { ret TooSmall }
        g += 1usize
    }
    if values.len < rs_total(sizes) { ret TooSmall }
    ret ok
}

// Games-Howell for every pair, with Tukey intervals at `conf`. A pair with a zero-variance group
// answers NaN statistics, as rstatix does.
fn games_howell(a: *mem.Arena, values: []const f64, sizes: []const usize, conf: f64) -> ([]GamesHowell, err) {
    let e = rs_check(sizes, values, 2usize)
    if e != ok { ret (zero, e) }
    let k = sizes.len
    let (out, ae) = mem.alloc[GamesHowell](a, k * (k - 1usize) / 2usize)
    if ae != ok { ret (zero, ae) }
    var at = 0usize
    var i = 0usize
    while i < k {
        var j = i + 1usize
        while j < k {
            let x = rs_group(values, sizes, i)
            let y = rs_group(values, sizes, j)
            let vx = rs_var(x) / f64(x.len)
            let vy = rs_var(y) / f64(y.len)
            let diff = rs_mean(y) - rs_mean(x)
            let welch = math.sqrt[f64](vx + vy)
            let num = (vx + vy) * (vx + vy)
            let den = vx * vx / f64(x.len - 1usize) + vy * vy / f64(y.len - 1usize)
            let dof = num / den
            var row = GamesHowell { first: i, second: j, estimate: diff, conf_low: rs_nan(), conf_high: rs_nan(), se: rs_nan(), statistic: rs_nan(), df: dof, p_adj: rs_nan() }
            if dof == dof && welch == welch && welch > 0.0f64 {
                let t = math.abs[f64](diff) / welch
                let se = welch * math.sqrt[f64](0.5f64)
                let q = nb.qtukey(conf, 1.0f64, f64(k), dof, true, false)
                row.statistic = t
                row.se = se
                row.p_adj = nb.ptukey(t * math.sqrt[f64](2.0f64), 1.0f64, f64(k), dof, false, false)
                row.conf_high = diff + q * se
                row.conf_low = diff - q * se
            }
            out[at] = row
            at += 1usize
            j += 1usize
        }
        i += 1usize
    }
    ret (out, ok)
}

// Average ranks of `x` (ties share the mean rank) into `out`; answers sum(t^3 - t) over the tie
// groups.
fn rs_ranks(x: []const f64, out: []f64) -> f64 {
    var ties = 0.0f64
    var i = 0usize
    while i < x.len {
        var less = 0usize
        var equal = 0usize
        var j = 0usize
        while j < x.len {
            if x[j] < x[i] { less += 1usize }
            if x[j] == x[i] { equal += 1usize }
            j += 1usize
        }
        out[i] = f64(less) + (f64(equal) + 1.0f64) / 2.0f64
        ties += f64(equal) * f64(equal) - 1.0f64
        i += 1usize
    }
    ret ties
}

// Dunn's test for every pair on the pooled ranks, adjusted by `method` over all pairs.
fn dunn(a: *mem.Arena, values: []const f64, sizes: []const usize, method: u8) -> ([]Dunn, err) {
    let e = rs_check(sizes, values, 1usize)
    if e != ok { ret (zero, e) }
    let k = sizes.len
    let n = rs_total(sizes)
    let (ranks, re) = mem.alloc[f64](a, n)
    if re != ok { ret (zero, re) }
    let ties = rs_ranks(values[0usize..n], ranks)
    let (means, me) = mem.alloc[f64](a, k)
    if me != ok { ret (zero, me) }
    var at = 0usize
    var g = 0usize
    while g < k {
        means[g] = rs_mean(ranks[at..at + sizes[g]])
        at += sizes[g]
        g += 1usize
    }
    let nf = f64(n)
    let tie_term = ties / (12.0f64 * (nf - 1.0f64))
    let base = nf * (nf + 1.0f64) / 12.0f64
    let pairs = k * (k - 1usize) / 2usize
    let (out, ae) = mem.alloc[Dunn](a, pairs)
    if ae != ok { ret (zero, ae) }
    let (ps, pe) = mem.alloc[f64](a, pairs)
    if pe != ok { ret (zero, pe) }
    var c = 0usize
    var i = 0usize
    while i < k {
        var j = i + 1usize
        while j < k {
            let diff = means[j] - means[i]
            let z = diff / math.sqrt[f64]((base - tie_term) * (1.0f64 / f64(sizes[i]) + 1.0f64 / f64(sizes[j])))
            let p = 2.0f64 * dist.pnorm(math.abs[f64](z), 0.0f64, 1.0f64, false, false)
            out[c] = Dunn { first: i, second: j, estimate: diff, statistic: z, p: p, p_adj: p }
            ps[c] = p
            c += 1usize
            j += 1usize
        }
        i += 1usize
    }
    let pa = p_adjust(a, method, ps)
    if pa != ok { ret (zero, pa) }
    c = 0usize
    while c < pairs {
        out[c].p_adj = ps[c]
        c += 1usize
    }
    ret (out, ok)
}

// pairwise.t.test: mode 0 pools the SD, 1 is Welch, 2 is paired (equal sizes). Two-sided.
fn pairwise_t(a: *mem.Arena, values: []const f64, sizes: []const usize, mode: u8, method: u8) -> ([]PairT, err) {
    let e = rs_check(sizes, values, 2usize)
    if e != ok { ret (zero, e) }
    let k = sizes.len
    let pairs = k * (k - 1usize) / 2usize
    let (out, ae) = mem.alloc[PairT](a, pairs)
    if ae != ok { ret (zero, ae) }
    let (ps, pe) = mem.alloc[f64](a, pairs)
    if pe != ok { ret (zero, pe) }
    var pooled = 0.0f64
    var total_df = 0.0f64
    var g = 0usize
    while g < k {
        let gv = rs_group(values, sizes, g)
        pooled += rs_var(gv) * f64(gv.len - 1usize)
        total_df += f64(gv.len - 1usize)
        g += 1usize
    }
    pooled = math.sqrt[f64](pooled / total_df)
    var c = 0usize
    var i = 0usize
    while i < k {
        var j = i + 1usize
        while j < k {
            let x = rs_group(values, sizes, i)
            let y = rs_group(values, sizes, j)
            var t = 0.0f64
            var dof = 0.0f64
            if mode == 0u8 {
                t = (rs_mean(x) - rs_mean(y)) / (pooled * math.sqrt[f64](1.0f64 / f64(x.len) + 1.0f64 / f64(y.len)))
                dof = total_df
            } else if mode == 1u8 {
                let vx = rs_var(x) / f64(x.len)
                let vy = rs_var(y) / f64(y.len)
                t = (rs_mean(x) - rs_mean(y)) / math.sqrt[f64](vx + vy)
                dof = (vx + vy) * (vx + vy) / (vx * vx / f64(x.len - 1usize) + vy * vy / f64(y.len - 1usize))
            } else {
                if x.len != y.len { ret (zero, Invalid) }
                let (d, de) = mem.alloc[f64](a, x.len)
                if de != ok { ret (zero, de) }
                var r = 0usize
                while r < x.len {
                    d[r] = x[r] - y[r]
                    r += 1usize
                }
                t = rs_mean(d) / math.sqrt[f64](rs_var(d) / f64(d.len))
                dof = f64(d.len - 1usize)
            }
            let p = 2.0f64 * nb.pt(0.0f64 - math.abs[f64](t), dof, true, false)
            out[c] = PairT { first: i, second: j, p: p, p_adj: p }
            ps[c] = p
            c += 1usize
            j += 1usize
        }
        i += 1usize
    }
    let pa = p_adjust(a, method, ps)
    if pa != ok { ret (zero, pa) }
    c = 0usize
    while c < pairs {
        out[c].p_adj = ps[c]
        c += 1usize
    }
    ret (out, ok)
}

// stats::oneway.test with var.equal = FALSE.
fn welch_anova(values: []const f64, sizes: []const usize) -> (Test, err) {
    let e = rs_check(sizes, values, 2usize)
    if e != ok { ret (zero, e) }
    let k = sizes.len
    let kf = f64(k)
    var sum_w = 0.0f64
    var g = 0usize
    while g < k {
        let gv = rs_group(values, sizes, g)
        sum_w += f64(gv.len) / rs_var(gv)
        g += 1usize
    }
    var tmp = 0.0f64
    var grand = 0.0f64
    g = 0usize
    while g < k {
        let gv = rs_group(values, sizes, g)
        let w = f64(gv.len) / rs_var(gv)
        tmp += (1.0f64 - w / sum_w) * (1.0f64 - w / sum_w) / f64(gv.len - 1usize)
        grand += w * rs_mean(gv)
        g += 1usize
    }
    tmp = tmp / (kf * kf - 1.0f64)
    grand = grand / sum_w
    var num = 0.0f64
    g = 0usize
    while g < k {
        let gv = rs_group(values, sizes, g)
        let w = f64(gv.len) / rs_var(gv)
        num += w * (rs_mean(gv) - grand) * (rs_mean(gv) - grand)
        g += 1usize
    }
    let stat = num / ((kf - 1.0f64) * (1.0f64 + 2.0f64 * (kf - 2.0f64) * tmp))
    let df2 = 1.0f64 / (3.0f64 * tmp)
    ret (Test { statistic: stat, df1: kf - 1.0f64, df2: df2, p: nb.pf(stat, kf - 1.0f64, df2, false, false) }, ok)
}

// Friedman's test on `blocks` rows of `k` measurements (row-major). With 0/1 data this is
// Cochran's Q, which is how rstatix computes cochran_qtest.
fn friedman(a: *mem.Arena, y: []const f64, blocks: usize, k: usize) -> (Test, err) {
    if blocks < 2usize || k < 2usize || y.len < blocks * k { ret (zero, TooSmall) }
    let (r, re) = mem.alloc[f64](a, k)
    if re != ok { ret (zero, re) }
    let (row, we) = mem.alloc[f64](a, k)
    if we != ok { ret (zero, we) }
    var i = 0usize
    while i < k {
        r[i] = 0.0f64
        i += 1usize
    }
    var ties = 0.0f64
    var b = 0usize
    while b < blocks {
        ties += rs_ranks(y[b * k..b * k + k], row)
        i = 0usize
        while i < k {
            r[i] += row[i]
            i += 1usize
        }
        b += 1usize
    }
    let nf = f64(blocks)
    let kf = f64(k)
    var ss = 0.0f64
    i = 0usize
    while i < k {
        let d = r[i] - nf * (kf + 1.0f64) / 2.0f64
        ss += d * d
        i += 1usize
    }
    let stat = 12.0f64 * ss / (nf * kf * (kf + 1.0f64) - ties / (kf - 1.0f64))
    ret (Test { statistic: stat, df1: kf - 1.0f64, df2: 0.0f64, p: nmath.pchisq(stat, kf - 1.0f64, false, false) }, ok)
}

// Kruskal-Wallis H with the tie correction.
fn kruskal_h(a: *mem.Arena, values: []const f64, sizes: []const usize) -> (f64, err) {
    let e = rs_check(sizes, values, 1usize)
    if e != ok { ret (0.0f64, e) }
    let n = rs_total(sizes)
    let (ranks, re) = mem.alloc[f64](a, n)
    if re != ok { ret (0.0f64, re) }
    let ties = rs_ranks(values[0usize..n], ranks)
    var at = 0usize
    var s = 0.0f64
    var g = 0usize
    while g < sizes.len {
        var t = 0.0f64
        var i = 0usize
        while i < sizes[g] {
            t += ranks[at + i]
            i += 1usize
        }
        s += t * t / f64(sizes[g])
        at += sizes[g]
        g += 1usize
    }
    let nf = f64(n)
    let h = (12.0f64 * s / (nf * (nf + 1.0f64)) - 3.0f64 * (nf + 1.0f64)) / (1.0f64 - ties / (nf * nf * nf - nf))
    ret (h, ok)
}

// rstatix kruskal_effsize: eta2[H] = (H - k + 1) / (n - k) clamped to [0, 1], or epsilon2 = H / (n - 1).
fn kruskal_effsize(a: *mem.Arena, values: []const f64, sizes: []const usize, epsilon: bool) -> (f64, err) {
    let (h, e) = kruskal_h(a, values, sizes)
    if e != ok { ret (0.0f64, e) }
    let n = f64(rs_total(sizes))
    if epsilon { ret (h / (n - 1.0f64), ok) }
    var es = (h - f64(sizes.len) + 1.0f64) / (n - f64(sizes.len))
    if es < 0.0f64 { es = 0.0f64 }
    if es > 1.0f64 { es = 1.0f64 }
    ret (es, ok)
}

// Cohen's d: mode 0 one sample against `mu` (x only), 1 two independent samples, 2 paired.
// `var_equal` pools the deviations about each mean over n - 2 as rstatix does; otherwise the root of
// the mean of the variances. `hedges` applies rstatix's small-sample factor.
fn cohens_d(a: *mem.Arena, mode: u8, x: []const f64, y: []const f64, mu: f64, var_equal: bool, hedges: bool) -> (f64, err) {
    if x.len < 2usize { ret (0.0f64, TooSmall) }
    if mode == 0u8 { ret ((rs_mean(x) - mu) / math.sqrt[f64](rs_var(x)), ok) }
    if y.len < 2usize { ret (0.0f64, TooSmall) }
    var d = 0.0f64
    if mode == 2u8 {
        if x.len != y.len { ret (0.0f64, Invalid) }
        let (diff, e) = mem.alloc[f64](a, x.len)
        if e != ok { ret (0.0f64, e) }
        var i = 0usize
        while i < x.len {
            diff[i] = x[i] - y[i]
            i += 1usize
        }
        d = (rs_mean(diff) - mu) / math.sqrt[f64](rs_var(diff))
        if hedges { d = d * (f64(x.len) - 2.0f64) / (f64(x.len) - 1.25f64) }
        ret (d, ok)
    }
    var sd = 0.0f64
    if var_equal {
        let ss = rs_var(x) * f64(x.len - 1usize) + rs_var(y) * f64(y.len - 1usize)
        sd = math.sqrt[f64](ss / f64(x.len + y.len - 2usize))
    } else {
        sd = math.sqrt[f64]((rs_var(x) + rs_var(y)) / 2.0f64)
    }
    d = (rs_mean(x) - rs_mean(y) - mu) / sd
    if hedges { d = d * (f64(x.len + y.len) - 3.0f64) / (f64(x.len + y.len) - 2.25f64) }
    ret (d, ok)
}

// One-way eta squared from the aov table: SS between over SS total (partial eta squared is the
// same number for one factor).
fn eta_squared(values: []const f64, sizes: []const usize) -> (f64, err) {
    let e = rs_check(sizes, values, 1usize)
    if e != ok { ret (0.0f64, e) }
    let n = rs_total(sizes)
    let grand = rs_mean(values[0usize..n])
    var total = 0.0f64
    var i = 0usize
    while i < n {
        total += (values[i] - grand) * (values[i] - grand)
        i += 1usize
    }
    var between = 0.0f64
    var g = 0usize
    while g < sizes.len {
        let m = rs_mean(rs_group(values, sizes, g))
        between += f64(sizes[g]) * (m - grand) * (m - grand)
        g += 1usize
    }
    ret (between / total, ok)
}

// R's quantile(x, p) type 7 over sorted `s`.
fn rs_quantile7(s: []const f64, p: f64) -> f64 {
    let h = f64(s.len - 1usize) * p
    var lo = usize(h)
    if f64(lo) > h { lo -= 1usize }
    let frac = h - f64(lo)
    if lo + 1usize >= s.len { ret s[s.len - 1usize] }
    ret s[lo] + frac * (s[lo + 1usize] - s[lo])
}

// rstatix is_outlier: 1 where x lies beyond `coef` interquartile ranges from the quartiles (1.5
// for outliers, 3 for extreme values), else 0.
fn outliers(a: *mem.Arena, x: []const f64, coef: f64, out: []u8) -> err {
    if out.len < x.len || x.len < 2usize { ret TooSmall }
    let (s, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret e }
    var i = 0usize
    while i < x.len {
        s[i] = x[i]
        var j = i
        while j > 0usize && s[j] < s[j - 1usize] {
            let t = s[j]
            s[j] = s[j - 1usize]
            s[j - 1usize] = t
            j -= 1usize
        }
        i += 1usize
    }
    let q1 = rs_quantile7(s, 0.25f64)
    let q3 = rs_quantile7(s, 0.75f64)
    let iqr = q3 - q1
    i = 0usize
    while i < x.len {
        out[i] = 0u8
        if x[i] < q1 - coef * iqr || x[i] > q3 + coef * iqr { out[i] = 1u8 }
        i += 1usize
    }
    ret ok
}

// stats::mahalanobis(x, colMeans(x), cov(x)) for `n` rows of `p` columns (row-major); the squared
// distances go to `out`. Answers the 0.999 chi-squared threshold rstatix flags outliers against.
fn mahalanobis(a: *mem.Arena, x: []const f64, n: usize, p: usize, out: []f64) -> (f64, err) {
    if n <= p || p < 1usize || x.len < n * p || out.len < n { ret (0.0f64, TooSmall) }
    let (mu, e1) = mem.alloc[f64](a, p)
    if e1 != ok { ret (0.0f64, e1) }
    let (cov, e2) = mem.alloc[f64](a, p * p)
    if e2 != ok { ret (0.0f64, e2) }
    var c = 0usize
    while c < p {
        var s = 0.0f64
        var r = 0usize
        while r < n {
            s += x[r * p + c]
            r += 1usize
        }
        mu[c] = s / f64(n)
        c += 1usize
    }
    c = 0usize
    while c < p {
        var d = 0usize
        while d < p {
            var s = 0.0f64
            var r = 0usize
            while r < n {
                s += (x[r * p + c] - mu[c]) * (x[r * p + d] - mu[d])
                r += 1usize
            }
            cov[c * p + d] = s / f64(n - 1usize)
            d += 1usize
        }
        c += 1usize
    }
    // Cholesky cov = L L^T, then the distance is |L^-1 (x - mu)|^2.
    var i = 0usize
    while i < p {
        var j = 0usize
        while j <= i {
            var s = cov[i * p + j]
            var t = 0usize
            while t < j {
                s -= cov[i * p + t] * cov[j * p + t]
                t += 1usize
            }
            if i == j {
                if !(s > 0.0f64) { ret (0.0f64, Invalid) }
                cov[i * p + i] = math.sqrt[f64](s)
            } else {
                cov[i * p + j] = s / cov[j * p + j]
            }
            j += 1usize
        }
        i += 1usize
    }
    let (z, e3) = mem.alloc[f64](a, p)
    if e3 != ok { ret (0.0f64, e3) }
    var r = 0usize
    while r < n {
        var total = 0.0f64
        i = 0usize
        while i < p {
            var s = x[r * p + i] - mu[i]
            var t = 0usize
            while t < i {
                s -= cov[i * p + t] * z[t]
                t += 1usize
            }
            z[i] = s / cov[i * p + i]
            total += z[i] * z[i]
            i += 1usize
        }
        out[r] = total
        r += 1usize
    }
    ret (nmath.qchisq(0.999f64, f64(p), true, false), ok)
}
