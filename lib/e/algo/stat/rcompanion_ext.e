// R rcompanion beyond the effect sizes of e.algo.stat.rcompanion: pairwiseMedianTest (coin::median_test, asymptotic, on each pair of groups),
// pairwiseNominalIndependence (Fisher's exact test of 2 by c tables by enumeration, the G test with its Williams and Yates corrections, the chi-squared
// test, Cramer's V), and groupwiseMean (the trimmed mean, the traditional t interval and the bootstrap mean and the basic, normal, percentile and BCa
// intervals of boot::boot.ci, each drawn from the seeded generator in the order the package draws them).
//
// Not here: groupwiseMean on a formula with na.rm = TRUE (missing values must be removed first), several grouping variables are the caller's combined code.

use e.algo.linalg.decomp as decomp
use e.algo.rand.r as rng
use e.algo.sort
use e.algo.stat.laeken_ext as lx
use e.algo.stat.rcompanion as rc
use e.algo.stat.rstatix as rt
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn cmp_up(ctx: *u8, x: f64, y: f64) -> i32 {
    if x < y { ret 0i32 - 1i32 }
    if x > y { ret 1i32 }
    ret 0i32
}

// R's median of x
fn median_of(a: *mem.Arena, x: []const f64) -> f64 {
    let n = x.len
    let (s, e) = mem.alloc[f64](a, n)
    if e != ok { ret nan() }
    var i = 0usize
    while i < n {
        s[i] = x[i]
        i += 1usize
    }
    var ctx = 0u8
    sort.in_place_by[f64, u8](s, &ctx, cmp_up)
    if n % 2usize == 1usize { ret s[n / 2usize] }
    ret (s[n / 2usize - 1usize] + s[n / 2usize]) / 2.0f64
}

// coin::median_test(x ~ g) asymptotic p value for two groups: the score is 1 above the pooled median, the statistic the score sum of group 1, standardised by its permutation mean and variance; two-sided
fn median_test_p(a: *mem.Arena, x1: []const f64, x2: []const f64) -> f64 {
    let n1 = x1.len
    let n2 = x2.len
    let nn = n1 + n2
    let (all, e) = mem.alloc[f64](a, nn)
    if e != ok { ret nan() }
    var i = 0usize
    while i < n1 {
        all[i] = x1[i]
        i += 1usize
    }
    i = 0usize
    while i < n2 {
        all[n1 + i] = x2[i]
        i += 1usize
    }
    let med = median_of(a, all)
    var s1 = 0.0f64
    var st = 0.0f64
    i = 0usize
    while i < nn {
        var sc = 0.0f64
        if all[i] > med { sc = 1.0f64 }
        st += sc
        if i < n1 { s1 += sc }
        i += 1usize
    }
    let fn1 = f64(n1)
    let fn2 = f64(n2)
    let fnn = f64(nn)
    let mean_s = st / fnn
    let ev = fn1 * mean_s
    // sum of squared scores equals st (scores are 0 / 1)
    let vr = fn1 * fn2 / (fnn * (fnn - 1.0f64)) * (st - fnn * mean_s * mean_s)
    let z = (s1 - ev) / math.sqrt[f64](vr)
    ret 2.0f64 * dist.pnorm(0.0f64 - math.abs[f64](z), 0.0f64, 1.0f64, true, false)
}

// pairwiseMedianTest(x, g, digits, method): for every pair i < j of the k groups (codes 0..k-1) the signif'ed p value (p) and its adjustment (padj), method a p.adjust code of e.algo.stat.rstatix
fn pairwise_median_test(a: *mem.Arena, x: []const f64, g: []const usize, k: usize, digits: i64, method: u8, p: []f64, padj: []f64) -> err {
    var pair = 0usize
    var i = 0usize
    while i + 1usize < k {
        var j = i + 1usize
        while j < k {
            var c1 = 0usize
            var c2 = 0usize
            var q = 0usize
            while q < x.len {
                if g[q] == i { c1 += 1usize }
                if g[q] == j { c2 += 1usize }
                q += 1usize
            }
            let (x1, e1) = mem.alloc[f64](a, c1)
            let (x2, e2) = mem.alloc[f64](a, c2)
            if e1 != ok || e2 != ok { ret e1 }
            var k1 = 0usize
            var k2 = 0usize
            q = 0usize
            while q < x.len {
                if g[q] == i {
                    x1[k1] = x[q]
                    k1 += 1usize
                }
                if g[q] == j {
                    x2[k2] = x[q]
                    k2 += 1usize
                }
                q += 1usize
            }
            let start = mem.mark(a)
            p[pair] = rc.signif(median_test_p(a, x1, x2), digits)
            mem.reset(a, start)
            pair += 1usize
            j += 1usize
        }
        i += 1usize
    }
    var m = 0usize
    while m < pair {
        padj[m] = p[m]
        m += 1usize
    }
    let ep = rt.p_adjust(a, method, padj[0usize..pair])
    if ep != ok { ret ep }
    m = 0usize
    while m < pair {
        padj[m] = rc.signif(padj[m], 4i64)
        m += 1usize
    }
    ret ok
}

// Fisher's exact test of an r by c table with min(r, c) = 2 (row-major t): the sum of the probabilities of the tables with the same margins that are no more likely than the observed one (relative tolerance 1e-7)
fn fisher_p(a: *mem.Arena, t: []const f64, r: usize, c: usize) -> f64 {
    // orient as 2 rows, m columns
    var m = c
    if r != 2usize { m = r }
    let (top, e1) = mem.alloc[f64](a, m)
    let (cs, e2) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok { ret nan() }
    var tot = 0.0f64
    var r1 = 0.0f64
    var j = 0usize
    while j < m {
        var u = 0.0f64
        var l = 0.0f64
        if r == 2usize {
            u = t[j]
            l = t[c + j]
        } else {
            u = t[j * c]
            l = t[j * c + 1usize]
        }
        top[j] = u
        cs[j] = u + l
        r1 += u
        tot += u + l
        j += 1usize
    }
    // log probability of a table with first row v: sum log C(cs_j, v_j) - log C(tot, r1)
    var lobs = 0.0f64
    j = 0usize
    while j < m {
        lobs += nb.lchoose_int(cs[j], top[j])
        j += 1usize
    }
    let lden = nb.lchoose_int(tot, r1)
    let cut = lobs + math.log[f64](1.0f64 + 1.0e-7f64)
    let (v, e3) = mem.alloc[f64](a, m)
    if e3 != ok { ret nan() }
    var total = 0.0f64
    var comp = 0.0f64
    // iterative enumeration over the first row
    j = 0usize
    var left = r1
    // the minimal and maximal value in each column given the rest are tracked by recursion emulated with an explicit stack
    let (rem, e4) = mem.alloc[f64](a, m + 1usize)
    if e4 != ok { ret nan() }
    // suffix sums of column totals
    rem[m] = 0.0f64
    var q = m
    while q > 0usize {
        rem[q - 1usize] = rem[q] + cs[q - 1usize]
        q -= 1usize
    }
    let (lp, e5) = mem.alloc[f64](a, m + 1usize)
    if e5 != ok { ret nan() }
    lp[0usize] = 0.0f64
    // depth-first: v[j] from lo to hi
    var depth = 0usize
    left = r1
    let (lft, e6) = mem.alloc[f64](a, m + 1usize)
    if e6 != ok { ret nan() }
    lft[0usize] = r1
    // initialise column 0
    var lo = 0.0f64
    var started = false
    let (nxt, e7) = mem.alloc[f64](a, m + 1usize)
    if e7 != ok { ret nan() }
    nxt[0usize] = 0.0f64
    var done = false
    while !done {
        // choose v[depth] = nxt[depth] if feasible
        let rest = rem[depth + 1usize]
        var lowv = lft[depth] - rest
        if lowv < 0.0f64 { lowv = 0.0f64 }
        var highv = cs[depth]
        if lft[depth] < highv { highv = lft[depth] }
        var cand = nxt[depth]
        if cand < lowv { cand = lowv }
        if cand > highv {
            // backtrack
            if depth == 0usize {
                done = true
            } else {
                depth -= 1usize
                nxt[depth] = v[depth] + 1.0f64
            }
        } else {
            v[depth] = cand
            lp[depth + 1usize] = lp[depth] + nb.lchoose_int(cs[depth], cand)
            if depth + 1usize == m {
                // a complete table needs the rest of row 1 to be zero
                if lft[depth] - cand == 0.0f64 {
                    let lt = lp[m]
                    if lt <= cut {
                        let pv = math.exp[f64](lt - lden)
                        let tt = total + pv
                        if math.abs[f64](total) >= math.abs[f64](pv) { comp += (total - tt) + pv } else { comp += (pv - tt) + total }
                        total = tt
                    }
                }
                nxt[depth] = cand + 1.0f64
            } else {
                lft[depth + 1usize] = lft[depth] - cand
                depth += 1usize
                nxt[depth] = 0.0f64
            }
        }
    }
    var res = total + comp
    if res > 1.0f64 { res = 1.0f64 }
    ret res
}

// GTest(x, correct): the G statistic and the p value 1 - pchisq(G, (r - 1)(c - 1)) of an r by c table (row-major); correct 0 none, 1 williams, 2 yates (2 by 2 only)
fn g_test(a: *mem.Arena, t0: []const f64, r: usize, c: usize, correct: usize) -> (f64, f64) {
    let (t, e) = mem.alloc[f64](a, r * c)
    if e != ok { ret (nan(), nan()) }
    var i = 0usize
    while i < r * c {
        t[i] = t0[i]
        i += 1usize
    }
    if correct == 2usize {
        if t[0usize] * t[3usize] - t[1usize] * t[2usize] > 0.0f64 {
            i = 0usize
            while i < 4usize {
                t[i] += 0.5f64
                i += 1usize
            }
            t[0usize] -= 1.0f64
            t[3usize] -= 1.0f64
        } else {
            i = 0usize
            while i < 4usize {
                t[i] -= 0.5f64
                i += 1usize
            }
            t[0usize] += 1.0f64
            t[3usize] += 1.0f64
        }
    }
    var n = 0.0f64
    i = 0usize
    while i < r * c {
        n += t[i]
        i += 1usize
    }
    let (sr, e1) = mem.alloc[f64](a, r)
    let (sc, e2) = mem.alloc[f64](a, c)
    if e1 != ok || e2 != ok { ret (nan(), nan()) }
    i = 0usize
    while i < r {
        sr[i] = 0.0f64
        var j = 0usize
        while j < c {
            sr[i] += t[i * c + j]
            j += 1usize
        }
        i += 1usize
    }
    var j2 = 0usize
    while j2 < c {
        sc[j2] = 0.0f64
        i = 0usize
        while i < r {
            sc[j2] += t[i * c + j2]
            i += 1usize
        }
        j2 += 1usize
    }
    var g = 0.0f64
    i = 0usize
    while i < r {
        var j = 0usize
        while j < c {
            if t[i * c + j] != 0.0f64 {
                let ex = sr[i] * sc[j] / n
                g += t[i * c + j] * math.log[f64](t[i * c + j] / ex)
            }
            j += 1usize
        }
        i += 1usize
    }
    var q = 1.0f64
    if correct == 1usize {
        var rt0 = 0.0f64
        var ct0 = 0.0f64
        i = 0usize
        while i < r {
            rt0 += 1.0f64 / sr[i]
            i += 1usize
        }
        j2 = 0usize
        while j2 < c {
            ct0 += 1.0f64 / sc[j2]
            j2 += 1usize
        }
        q = 1.0f64 + ((n * rt0 - 1.0f64) * (n * ct0 - 1.0f64)) / (6.0f64 * n * f64(c - 1usize) * f64(r - 1usize))
    }
    let stat = 2.0f64 * g / q
    let df = f64((r - 1usize) * (c - 1usize))
    ret (stat, 1.0f64 - nm.pchisq(stat, df, true, false))
}

// chisq.test(x, correct): the statistic and p value of an r by c table; the Yates correction applies to 2 by 2 tables only
fn chisq_test(t: []const f64, r: usize, c: usize, correct: bool) -> (f64, f64, f64) {
    var n = 0.0f64
    var i = 0usize
    while i < r * c {
        n += t[i]
        i += 1usize
    }
    var yates = 0.0f64
    if correct && r == 2usize && c == 2usize {
        yates = 0.5f64
        i = 0usize
        while i < r {
            var j = 0usize
            while j < c {
                var rs = 0.0f64
                var cs = 0.0f64
                var q = 0usize
                while q < c {
                    rs += t[i * c + q]
                    q += 1usize
                }
                q = 0usize
                while q < r {
                    cs += t[q * c + j]
                    q += 1usize
                }
                let d = math.abs[f64](t[i * c + j] - rs * cs / n)
                if d < yates { yates = d }
                j += 1usize
            }
            i += 1usize
        }
    }
    var stat = 0.0f64
    i = 0usize
    while i < r {
        var j = 0usize
        while j < c {
            var rs = 0.0f64
            var cs = 0.0f64
            var q = 0usize
            while q < c {
                rs += t[i * c + q]
                q += 1usize
            }
            q = 0usize
            while q < r {
                cs += t[q * c + j]
                q += 1usize
            }
            let e = rs * cs / n
            let d = math.abs[f64](t[i * c + j] - e) - yates
            stat += d * d / e
            j += 1usize
        }
        i += 1usize
    }
    let df = f64((r - 1usize) * (c - 1usize))
    ret (stat, df, nm.pchisq(stat, df, false, false))
}

// cramerV(t, digits) without bias correction
fn cramer_v_digits(t: []const f64, r: usize, c: usize, digits: i64) -> f64 {
    let (chi, n) = rc.chisq_table(t, r, c)
    let phi = chi / n
    var m = f64(r) - 1.0f64
    if f64(c) - 1.0f64 < m { m = f64(c) - 1.0f64 }
    ret rc.signif(math.sqrt[f64](phi / m), digits)
}

// pairwiseNominalIndependence(x, compare, ...): for the pairs of rows (compare 0) or columns (1) of the r by c table x (row-major) the 10 values
// pFisher, pGtest, pChisq, CramerV, Chisq, df, G, then the adjusted pFisher, pGtest, pChisq; flags select what is computed (a skipped value is NaN)
// gcorr: GTest correct code; yates: the continuity correction of the chi-squared p value. out has 10 values per pair
fn pairwise_nominal_independence(a: *mem.Arena, x: []const f64, r: usize, c: usize, compare: usize, do_fisher: bool, do_g: bool, do_chisq: bool, do_cramer: bool, do_stats: bool, method: u8, gcorr: usize, yates: bool, digits: i64, out: []f64) -> err {
    var n = r
    if compare == 1usize { n = c }
    var pair = 0usize
    var i = 0usize
    while i + 1usize < n {
        var j = i + 1usize
        while j < n {
            let start = mem.mark(a)
            var rr = 2usize
            var cc = c
            if compare == 1usize {
                rr = r
                cc = 2usize
            }
            let (d, e) = mem.alloc[f64](a, rr * cc)
            if e != ok { ret e }
            if compare == 0usize {
                var q = 0usize
                while q < c {
                    d[q] = x[i * c + q]
                    d[c + q] = x[j * c + q]
                    q += 1usize
                }
            } else {
                var q = 0usize
                while q < r {
                    d[q * 2usize] = x[q * c + i]
                    d[q * 2usize + 1usize] = x[q * c + j]
                    q += 1usize
                }
            }
            let o = out[pair * 10usize..pair * 10usize + 10usize]
            var f = 0usize
            while f < 10usize {
                o[f] = nan()
                f += 1usize
            }
            if do_fisher { o[0usize] = rc.signif(fisher_p(a, d, rr, cc), digits) }
            if do_g {
                let (gs, gp) = g_test(a, d, rr, cc, gcorr)
                o[1usize] = rc.signif(gp, digits)
            }
            if do_chisq {
                let (cs, cdf, cp) = chisq_test(d, rr, cc, yates)
                o[2usize] = rc.signif(cp, digits)
            }
            if do_cramer { o[3usize] = cramer_v_digits(d, rr, cc, digits) }
            if do_stats {
                let (cs2, cdf2, cp2) = chisq_test(d, rr, cc, true)
                o[4usize] = rc.signif(cs2, digits)
                o[5usize] = rc.signif(cdf2, digits)
                let (gs2, gp2) = g_test(a, d, rr, cc, 0usize)
                o[6usize] = rc.signif(gs2, digits)
            }
            mem.reset(a, start)
            pair += 1usize
            j += 1usize
        }
        i += 1usize
    }
    var col = 0usize
    while col < 3usize {
        let (pv, e2) = mem.alloc[f64](a, pair)
        if e2 != ok { ret e2 }
        var m = 0usize
        while m < pair {
            pv[m] = out[m * 10usize + col]
            m += 1usize
        }
        var on = true
        if col == 0usize && !do_fisher { on = false }
        if col == 1usize && !do_g { on = false }
        if col == 2usize && !do_chisq { on = false }
        if on {
            let ep = rt.p_adjust(a, method, pv)
            if ep != ok { ret ep }
            m = 0usize
            while m < pair {
                out[m * 10usize + 7usize + col] = rc.signif(pv[m], digits)
                m += 1usize
            }
        } else {
            m = 0usize
            while m < pair {
                out[m * 10usize + 7usize + col] = nan()
                m += 1usize
            }
        }
        col += 1usize
    }
    ret ok
}

// ---- groupwiseMean ----

// mean(y, trim): R's trimmed mean (trim below 0.5; zero is the plain mean); tmp holds y.len values
fn trimmed_mean(y: []const f64, trim: f64, tmp: []f64, tmp2: []f64) -> f64 {
    let n = y.len
    if trim <= 0.0f64 { ret lx.rmean(y, tmp) }
    var i = 0usize
    while i < n {
        tmp[i] = y[i]
        i += 1usize
    }
    var ctx = 0u8
    sort.in_place_by[f64, u8](tmp[0usize..n], &ctx, cmp_up)
    let lo = usize(math.floor[f64](f64(n) * trim)) + 1usize
    let hi = n + 1usize - lo
    ret lx.rmean(tmp[lo - 1usize..hi], tmp2)
}

// boot(x, function(y, j) mean(y[j], trim), R): t0, the R replicate statistics and the index matrix (R by n, column-major: idx[c * R + r], 0-based)
fn draw_boot(a: *mem.Arena, r: *rng.Rng, x: []const f64, trim: f64, nrep: usize, t: []f64, idx: []usize) -> f64 {
    let n = x.len
    let (s, e) = rng.sample_int(a, r, i64(n), i64(n * nrep), true)
    let (y, e1) = mem.alloc[f64](a, n)
    let (tmp, e2) = mem.alloc[f64](a, n)
    let (tmp2, e3) = mem.alloc[f64](a, n)
    if e != ok || e1 != ok || e2 != ok || e3 != ok { ret nan() }
    var i = 0usize
    while i < n * nrep {
        idx[i] = usize(s[i] - 1i64)
        i += 1usize
    }
    var rr = 0usize
    while rr < nrep {
        i = 0usize
        while i < n {
            y[i] = x[idx[i * nrep + rr]]
            i += 1usize
        }
        t[rr] = trimmed_mean(y, trim, tmp, tmp2)
        rr += 1usize
    }
    ret trimmed_mean(x, trim, tmp, tmp2)
}

// the BCa interval with the jackknife influence values (boot uses them when there are fewer replicates than observations)
fn bca_jack(a: *mem.Arena, y: []const f64, trim: f64, t: []const f64, t0: f64, n: usize, conf: f64, out: []f64) -> err {
    let nrep = t.len
    let (l, e1) = mem.alloc[f64](a, n)
    let (yj, e2) = mem.alloc[f64](a, n)
    let (tmp, e3) = mem.alloc[f64](a, n)
    let (tmp2, e4) = mem.alloc[f64](a, n)
    let (ts, e5) = mem.alloc[f64](a, nrep)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret e1 }
    var q = 0usize
    while q < n {
        var m = 0usize
        var c = 0usize
        while c < n {
            if c != q {
                yj[m] = y[c]
                m += 1usize
            }
            c += 1usize
        }
        l[q] = f64(n - 1usize) * (t0 - trimmed_mean(yj[0usize..m], trim, tmp, tmp2))
        q += 1usize
    }
    var s2 = 0.0f64
    var s3 = 0.0f64
    q = 0usize
    while q < n {
        s2 += l[q] * l[q]
        s3 += l[q] * l[q] * l[q]
        q += 1usize
    }
    let acc = s3 / (6.0f64 * math.pow[f64](s2, 1.5f64))
    var below = 0.0f64
    q = 0usize
    while q < nrep {
        ts[q] = t[q]
        if t[q] < t0 { below += 1.0f64 }
        q += 1usize
    }
    let w = dist.qnorm(below / f64(nrep), 0.0f64, 1.0f64, true, false)
    var ctx = 0u8
    sort.in_place_by[f64, u8](ts, &ctx, cmp_up)
    var k = 0usize
    while k < 2usize {
        var al = (1.0f64 - conf) / 2.0f64
        if k == 1usize { al = (1.0f64 + conf) / 2.0f64 }
        let za = dist.qnorm(al, 0.0f64, 1.0f64, true, false)
        let adj = dist.pnorm(w + (w + za) / (1.0f64 - acc * (w + za)), 0.0f64, 1.0f64, true, false)
        out[k] = lx.norm_inter_one(ts, adj)
        k += 1usize
    }
    ret ok
}

// bca.ci: the adjusted percentile interval; the acceleration comes from the regression empirical influence values of boot::empinf; lo and hi in out
fn bca_ci(a: *mem.Arena, y: []const f64, trim: f64, t: []const f64, t0: f64, idx: []const usize, n: usize, conf: f64, out: []f64) -> err {
    let nrep = t.len
    if nrep < n { ret bca_jack(a, y, trim, t, t0, n, conf, out) }
    // the frequency regression: columns 2..n of the frequency matrix over n
    let p = n - 1usize
    let (xm, e1) = mem.alloc[f64](a, nrep * (p + 1usize))
    if e1 != ok { ret e1 }
    var rr = 0usize
    while rr < nrep {
        xm[rr] = 1.0f64
        var c = 1usize
        while c < n {
            xm[c * nrep + rr] = 0.0f64
            c += 1usize
        }
        var i = 0usize
        while i < n {
            let col = idx[i * nrep + rr]
            if col >= 1usize { xm[col * nrep + rr] += 1.0f64 / f64(n) }
            i += 1usize
        }
        rr += 1usize
    }
    let (fit, ef) = decomp.lm_fit(a, xm, nrep, p + 1usize, t, 1.0e-11f64)
    if ef != ok { ret ef }
    let (l, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret e2 }
    l[0usize] = 0.0f64
    var c = 1usize
    while c < n {
        l[c] = fit.coef[c]
        c += 1usize
    }
    var ml = 0.0f64
    c = 0usize
    while c < n {
        ml += l[c]
        c += 1usize
    }
    ml = ml / f64(n)
    var s2 = 0.0f64
    var s3 = 0.0f64
    c = 0usize
    while c < n {
        let d = l[c] - ml
        s2 += d * d
        s3 += d * d * d
        c += 1usize
    }
    let acc = s3 / (6.0f64 * math.pow[f64](s2, 1.5f64))
    var below = 0.0f64
    rr = 0usize
    while rr < nrep {
        if t[rr] < t0 { below += 1.0f64 }
        rr += 1usize
    }
    let w = dist.qnorm(below / f64(nrep), 0.0f64, 1.0f64, true, false)
    let (ts, e3) = mem.alloc[f64](a, nrep)
    if e3 != ok { ret e3 }
    rr = 0usize
    while rr < nrep {
        ts[rr] = t[rr]
        rr += 1usize
    }
    var ctx = 0u8
    sort.in_place_by[f64, u8](ts, &ctx, cmp_up)
    var k = 0usize
    while k < 2usize {
        var al = (1.0f64 - conf) / 2.0f64
        if k == 1usize { al = (1.0f64 + conf) / 2.0f64 }
        let za = dist.qnorm(al, 0.0f64, 1.0f64, true, false)
        let adj = dist.pnorm(w + (w + za) / (1.0f64 - acc * (w + za)), 0.0f64, 1.0f64, true, false)
        out[k] = lx.norm_inter_one(ts, adj)
        k += 1usize
    }
    ret ok
}

// the kinds a bootstrap draw can report: 0 mean of the replicates, 1 / 2 basic lower / upper, 3 / 4 normal, 5 / 6 percentile, 7 / 8 BCa
fn boot_stat(a: *mem.Arena, r: *rng.Rng, x: []const f64, trim: f64, nrep: usize, conf: f64, kind: usize) -> f64 {
    let (t, e1) = mem.alloc[f64](a, nrep)
    let (idx, e2) = mem.alloc[usize](a, nrep * x.len)
    let (tmp, e3) = mem.alloc[f64](a, nrep)
    let (ci, e4) = mem.alloc[f64](a, 2usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan() }
    let t0 = draw_boot(a, r, x, trim, nrep, t, idx)
    if kind == 0usize { ret lx.rmean(t, tmp) }
    if kind <= 2usize {
        lx.boot_ci(a, t, t0, conf, 2usize, ci)
        ret ci[kind - 1usize]
    }
    if kind <= 4usize {
        lx.boot_ci(a, t, t0, conf, 1usize, ci)
        ret ci[kind - 3usize]
    }
    if kind <= 6usize {
        lx.boot_ci(a, t, t0, conf, 0usize, ci)
        ret ci[kind - 5usize]
    }
    if bca_ci(a, x, trim, t, t0, idx, x.len, conf, ci) != ok { ret nan() }
    ret ci[kind - 7usize]
}

// groupwiseMean(x, g, k, trim, conf, R, digits, ...): per group (codes 0..k-1 in sorted order) 13 values in out, 13 per group:
// n, Mean, Boot.mean, Trad.lower, Trad.upper, Basic.lower, Basic.upper, Normal.lower, Normal.upper, Percentile.lower, Percentile.upper, Bca.lower, Bca.upper;
// flags (bit 0 boot, 1 basic, 2 normal, 3 percentile, 4 bca, 5 traditional) select what is computed. The bootstraps are drawn in the order of the package:
// the Boot.mean of every group, then the basic lower of every group, the basic upper of every group, the normal lower, and so on.
fn groupwise_mean(a: *mem.Arena, r: *rng.Rng, x: []const f64, g: []const usize, k: usize, trim: f64, conf: f64, nrep: usize, digits: i64, flags: usize, out: []f64) -> err {
    var gi = 0usize
    while gi < k {
        var cnt = 0usize
        var q = 0usize
        while q < x.len {
            if g[q] == gi { cnt += 1usize }
            q += 1usize
        }
        let (xs, e) = mem.alloc[f64](a, cnt)
        let (tmp, e2) = mem.alloc[f64](a, cnt)
        let (tmp2, e3) = mem.alloc[f64](a, cnt)
        if e != ok || e2 != ok || e3 != ok { ret e }
        var c = 0usize
        q = 0usize
        while q < x.len {
            if g[q] == gi {
                xs[c] = x[q]
                c += 1usize
            }
            q += 1usize
        }
        let o = out[gi * 13usize..gi * 13usize + 13usize]
        var f = 0usize
        while f < 13usize {
            o[f] = nan()
            f += 1usize
        }
        o[0usize] = f64(cnt)
        o[1usize] = rc.signif(trimmed_mean(xs, trim, tmp, tmp2), digits)
        if (flags & 32usize) != 0usize {
            // traditional interval: mean(x) -/+ qt((1 + conf) / 2, n - 1) sd / sqrt(n), only without trimming
            if trim == 0.0f64 {
                let m = lx.rmean(xs, tmp)
                let sd = math.sqrt[f64](lx.rvar(xs, tmp))
                let nf = f64(cnt)
                let ci = nb.qt(conf + (1.0f64 - conf) / 2.0f64, nf - 1.0f64, true, false) * sd / math.sqrt[f64](nf)
                o[3usize] = rc.signif(m - ci, digits)
                o[4usize] = rc.signif(m + ci, digits)
            }
        }
        gi += 1usize
    }
    // bootstrap kinds in the package's order
    var kind = 0usize
    while kind < 9usize {
        var on = false
        if kind == 0usize && (flags & 1usize) != 0usize { on = true }
        if (kind == 1usize || kind == 2usize) && (flags & 2usize) != 0usize { on = true }
        if (kind == 3usize || kind == 4usize) && (flags & 4usize) != 0usize { on = true }
        if (kind == 5usize || kind == 6usize) && (flags & 8usize) != 0usize { on = true }
        if (kind == 7usize || kind == 8usize) && (flags & 16usize) != 0usize { on = true }
        if on {
            gi = 0usize
            while gi < k {
                var cnt = 0usize
                var q = 0usize
                while q < x.len {
                    if g[q] == gi { cnt += 1usize }
                    q += 1usize
                }
                let start = mem.mark(a)
                let (xs, e) = mem.alloc[f64](a, cnt)
                if e != ok { ret e }
                var c = 0usize
                q = 0usize
                while q < x.len {
                    if g[q] == gi {
                        xs[c] = x[q]
                        c += 1usize
                    }
                    q += 1usize
                }
                let v = boot_stat(a, r, xs, trim, nrep, conf, kind)
                mem.reset(a, start)
                var slot = 2usize
                if kind >= 1usize { slot = 4usize + kind }
                out[gi * 13usize + slot] = rc.signif(v, digits)
                gi += 1usize
            }
        }
        kind += 1usize
    }
    ret ok
}
