// R irr: inter-rater reliability on a ratings matrix of ns subjects (rows) by nr raters (columns), row-major, complete cases only.
// Percentage agreement (`agree`), Cohen's kappa for two raters with the unweighted, equal, squared or user weights (`kappa2`), Fleiss'
// kappa (`kappam_fleiss`, exact or not), Light's kappa (`kappam_light`), Kendall's W (`kendall`), the mean of the pairwise correlations
// (`meancor`), Maxwell's RE (`maxwell`), Robinson's A (`robinson`), the Finn coefficient (`finn`), the intraclass correlation in all
// its eight forms (`icc`) and Krippendorff's alpha (`kripp_alpha`). Categories are given as numbers; their order is the numeric one.
//
// And `iota`. Not here: the Bhapkar and Stuart-Maxwell tests, rater.bias and relInterIntra.

use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.mem

type Test = struct { value: f64, stat: f64, p: f64 }

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn pn_two(u: f64) -> f64 { ret 2.0f64 * (1.0f64 - dist.pnorm(math.abs[f64](u), 0.0f64, 1.0f64, true, false)) }

// the sample variance (n - 1) of a vector
fn var_of(v: []const f64) -> f64 {
    let n = v.len
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += v[i]
        i += 1usize
    }
    let m = s / f64(n)
    var d = 0.0f64
    i = 0usize
    while i < n {
        d += (v[i] - m) * (v[i] - m)
        i += 1usize
    }
    ret d / f64(n - 1usize)
}

// agree(ratings, tolerance): the percentage of subjects whose ratings differ by at most tolerance
fn agree(x: []const f64, ns: usize, nr: usize, tol: f64) -> f64 {
    var k = 0usize
    var i = 0usize
    while i < ns {
        var lo = x[i * nr]
        var hi = x[i * nr]
        var j = 1usize
        while j < nr {
            if x[i * nr + j] < lo { lo = x[i * nr + j] }
            if x[i * nr + j] > hi { hi = x[i * nr + j] }
            j += 1usize
        }
        if hi - lo <= tol { k += 1usize }
        i += 1usize
    }
    ret 100.0f64 * f64(k) / f64(ns)
}

// the sorted distinct values of the first nv numbers of v
fn levels_of(a: *mem.Arena, v: []const f64) -> ([]f64, err) {
    let (t, e) = mem.alloc[f64](a, v.len)
    if e != ok { ret (t, e) }
    var i = 0usize
    while i < v.len {
        t[i] = v[i]
        i += 1usize
    }
    // insertion sort
    i = 1usize
    while i < v.len {
        let x = t[i]
        var j = i
        while j > 0usize && t[j - 1usize] > x {
            t[j] = t[j - 1usize]
            j -= 1usize
        }
        t[j] = x
        i += 1usize
    }
    var m = 0usize
    i = 0usize
    while i < v.len {
        if m == 0usize || t[i] != t[m - 1usize] {
            t[m] = t[i]
            m += 1usize
        }
        i += 1usize
    }
    ret (t[0usize..m], ok)
}

fn index_of(lev: []const f64, x: f64) -> usize {
    var i = 0usize
    while i < lev.len {
        if lev[i] == x { ret i }
        i += 1usize
    }
    ret lev.len
}

// kappa2: weight 0 unweighted, 1 equal, 2 squared, 3 the numeric weights in wnum (one per level)
fn kappa2(a: *mem.Arena, x: []const f64, ns: usize, weight: u8, wnum: []const f64) -> (Test, err) {
    var out = Test { value: 0.0f64, stat: 0.0f64, p: 0.0f64 }
    let (all, e0) = mem.alloc[f64](a, 2usize * ns)
    if e0 != ok { ret (out, e0) }
    var i = 0usize
    while i < ns {
        all[i] = x[i * 2usize]
        all[ns + i] = x[i * 2usize + 1usize]
        i += 1usize
    }
    let (lev, le) = levels_of(a, all)
    if le != ok { ret (out, le) }
    let nc = lev.len
    let (tt, e1) = mem.alloc[f64](a, nc * nc)
    let (wt, e2) = mem.alloc[f64](a, nc * nc)
    let (w, e3) = mem.alloc[f64](a, nc)
    let (tm1, e4) = mem.alloc[f64](a, nc)
    let (tm2, e5) = mem.alloc[f64](a, nc)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (out, e1) }
    i = 0usize
    while i < nc * nc {
        tt[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < ns {
        tt[index_of(lev, x[i * 2usize]) * nc + index_of(lev, x[i * 2usize + 1usize])] += 1.0f64
        i += 1usize
    }
    var k = 0usize
    while k < nc {
        if weight == 3u8 {
            var mn = wnum[0usize]
            var mx = wnum[0usize]
            var q = 1usize
            while q < nc {
                if wnum[q] < mn { mn = wnum[q] }
                if wnum[q] > mx { mx = wnum[q] }
                q += 1usize
            }
            w[k] = 1.0f64 - (wnum[k] - mn) / (mx - mn)
        } else if weight == 1u8 {
            w[k] = f64(nc - 1usize - k) / f64(nc - 1usize)
        } else if weight == 2u8 {
            w[k] = 1.0f64 - f64(k * k) / f64((nc - 1usize) * (nc - 1usize))
        } else {
            w[k] = 0.0f64
            if k == 0usize { w[k] = 1.0f64 }
        }
        k += 1usize
    }
    // wvec = c(sort(w), w[2:nw]); weighttab[i, j] = wvec[nw - i + j] (1-based), a Toeplitz matrix
    let (sw, e6) = mem.alloc[f64](a, nc)
    if e6 != ok { ret (out, e6) }
    i = 0usize
    while i < nc {
        sw[i] = w[i]
        i += 1usize
    }
    i = 1usize
    while i < nc {
        let v = sw[i]
        var j = i
        while j > 0usize && sw[j - 1usize] > v {
            sw[j] = sw[j - 1usize]
            j -= 1usize
        }
        sw[j] = v
        i += 1usize
    }
    let nw = nc
    var r = 0usize
    while r < nw {
        var c = 0usize
        while c < nw {
            // index into wvec: (nw - r) - 1 + c (0-based, r the 0-based row)
            let idx = nw - 1usize - r + c
            if idx < nw { wt[r * nw + c] = sw[idx] } else { wt[r * nw + c] = w[idx - nw + 1usize] }
            c += 1usize
        }
        r += 1usize
    }
    var agree_p = 0.0f64
    r = 0usize
    while r < nc {
        var c = 0usize
        while c < nc {
            agree_p += tt[r * nc + c] * wt[r * nc + c]
            c += 1usize
        }
        r += 1usize
    }
    agree_p = agree_p / f64(ns)
    r = 0usize
    while r < nc {
        tm1[r] = 0.0f64
        tm2[r] = 0.0f64
        r += 1usize
    }
    r = 0usize
    while r < nc {
        var c = 0usize
        while c < nc {
            tm1[r] += tt[r * nc + c]
            tm2[c] += tt[r * nc + c]
            c += 1usize
        }
        r += 1usize
    }
    let nsf = f64(ns)
    var chance_p = 0.0f64
    r = 0usize
    while r < nc {
        var c = 0usize
        while c < nc {
            chance_p += (tm1[r] * tm2[c] / nsf) * wt[r * nc + c]
            c += 1usize
        }
        r += 1usize
    }
    chance_p = chance_p / nsf
    let value = (agree_p - chance_p) / (1.0f64 - chance_p)
    // w.i = column sums of rep(tm2 / ns) * weighttab; w.j = row sums of rep(tm1 / ns, each) * weighttab
    var vsum = 0.0f64
    r = 0usize
    while r < nc {
        var c = 0usize
        while c < nc {
            var wi = 0.0f64
            var wj = 0.0f64
            var q = 0usize
            while q < nc {
                wi += (tm2[q] / nsf) * wt[q * nc + r]
                wj += (tm1[q] / nsf) * wt[c * nc + q]
                q += 1usize
            }
            let eij = tm1[r] * tm2[c] / nsf
            let d = wt[r * nc + c] - (wi + wj)
            vsum += (eij / nsf) * d * d
            c += 1usize
        }
        r += 1usize
    }
    let varkappa = (vsum - chance_p * chance_p) / (nsf * (1.0f64 - chance_p) * (1.0f64 - chance_p))
    let u = value / math.sqrt[f64](varkappa)
    out.value = value
    out.stat = u
    out.p = pn_two(u)
    ret (out, ok)
}

// the category counts of every subject over the raters: ns by nl row-major
fn category_table(a: *mem.Arena, x: []const f64, ns: usize, nr: usize, lev: []const f64) -> ([]f64, err) {
    let nl = lev.len
    let (t, e) = mem.alloc[f64](a, ns * nl)
    if e != ok { ret (t, e) }
    var i = 0usize
    while i < ns * nl {
        t[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < ns {
        var j = 0usize
        while j < nr {
            t[i * nl + index_of(lev, x[i * nr + j])] += 1.0f64
            j += 1usize
        }
        i += 1usize
    }
    ret (t, ok)
}

// kappam.fleiss(ratings, exact = FALSE): value, z and p (z and p are NaN for the exact form)
fn kappam_fleiss(a: *mem.Arena, x: []const f64, ns: usize, nr: usize, exact: bool) -> (Test, err) {
    var out = Test { value: 0.0f64, stat: nan(), p: nan() }
    let (lev, le) = levels_of(a, x[0usize..ns * nr])
    if le != ok { ret (out, le) }
    let nl = lev.len
    let (tt, te) = category_table(a, x, ns, nr, lev)
    if te != ok { ret (out, te) }
    let nsf = f64(ns)
    let nrf = f64(nr)
    var agree_p = 0.0f64
    var i = 0usize
    while i < ns {
        var s = 0.0f64
        var j = 0usize
        while j < nl {
            s += tt[i * nl + j] * tt[i * nl + j]
            j += 1usize
        }
        agree_p += (s - nrf) / (nrf * (nrf - 1.0f64)) / nsf
        i += 1usize
    }
    let (cs, ce) = mem.alloc[f64](a, nl)
    if ce != ok { ret (out, ce) }
    var j = 0usize
    while j < nl {
        cs[j] = 0.0f64
        i = 0usize
        while i < ns {
            cs[j] += tt[i * nl + j]
            i += 1usize
        }
        j += 1usize
    }
    var sq = 0.0f64
    j = 0usize
    while j < nl {
        sq += cs[j] * cs[j]
        j += 1usize
    }
    var chance_p = sq / ((nsf * nrf) * (nsf * nrf))
    if exact {
        // minus sum over categories of var(rater proportions) (nr - 1) / nr / (nr - 1)
        var corr = 0.0f64
        j = 0usize
        while j < nl {
            // proportions of category j for each rater
            var mean = 0.0f64
            var r = 0usize
            while r < nr {
                var cnt = 0.0f64
                i = 0usize
                while i < ns {
                    if x[i * nr + r] == lev[j] { cnt += 1.0f64 }
                    i += 1usize
                }
                mean += cnt / nsf
                r += 1usize
            }
            mean = mean / nrf
            var d = 0.0f64
            r = 0usize
            while r < nr {
                var cnt = 0.0f64
                i = 0usize
                while i < ns {
                    if x[i * nr + r] == lev[j] { cnt += 1.0f64 }
                    i += 1usize
                }
                d += (cnt / nsf - mean) * (cnt / nsf - mean)
                r += 1usize
            }
            corr += (d / (nrf - 1.0f64)) * (nrf - 1.0f64) / nrf
            j += 1usize
        }
        chance_p = chance_p - corr / (nrf - 1.0f64)
    }
    out.value = (agree_p - chance_p) / (1.0f64 - chance_p)
    if !exact {
        var s1 = 0.0f64
        var s2 = 0.0f64
        j = 0usize
        while j < nl {
            let pj = cs[j] / (nsf * nrf)
            let qj = 1.0f64 - pj
            s1 += pj * qj
            s2 += pj * qj * (qj - pj)
            j += 1usize
        }
        let varkappa = (2.0f64 / (s1 * s1 * (nsf * nrf * (nrf - 1.0f64)))) * (s1 * s1 - s2)
        out.stat = out.value / math.sqrt[f64](varkappa)
        out.p = pn_two(out.stat)
    }
    ret (out, ok)
}

// kappam.light(ratings): the mean of the pairwise unweighted kappas with Light's variance
fn kappam_light(a: *mem.Arena, x: []const f64, ns: usize, nr: usize) -> (Test, err) {
    var out = Test { value: 0.0f64, stat: 0.0f64, p: 0.0f64 }
    let (lev, le) = levels_of(a, x[0usize..ns * nr])
    if le != ok { ret (out, le) }
    let nl = lev.len
    let (pair, pe) = mem.alloc[f64](a, 2usize * ns)
    if pe != ok { ret (out, pe) }
    var tot = 0.0f64
    var npairs = 0usize
    var disprod = 1.0f64
    var i = 0usize
    while i + 1usize < nr {
        var j = i + 1usize
        while j < nr {
            var s = 0usize
            while s < ns {
                pair[s * 2usize] = x[s * nr + i]
                pair[s * 2usize + 1usize] = x[s * nr + j]
                s += 1usize
            }
            let (kt, ke) = kappa2(a, pair, ns, 0u8, pair[0usize..0usize])
            if ke != ok { ret (out, ke) }
            tot += kt.value
            npairs += 1usize
            var dis = 0.0f64
            var li = 0usize
            while li < nl {
                var lj = 0usize
                while lj < nl {
                    if li != lj {
                        var r1 = 0.0f64
                        var r2 = 0.0f64
                        s = 0usize
                        while s < ns {
                            if x[s * nr + i] == lev[li] { r1 += 1.0f64 }
                            if x[s * nr + j] == lev[lj] { r2 += 1.0f64 }
                            s += 1usize
                        }
                        dis += r1 * r2
                    }
                    lj += 1usize
                }
                li += 1usize
            }
            disprod = disprod * dis
            j += 1usize
        }
        i += 1usize
    }
    out.value = tot / f64(npairs)
    let b = f64(npairs) * disprod
    let chance_p = 1.0f64 - b / math.pow[f64](f64(ns), f64(nr * (nr - 1usize) / 2usize * 2usize))
    let varkappa = chance_p / (f64(ns) * (1.0f64 - chance_p))
    out.stat = out.value / math.sqrt[f64](varkappa)
    out.p = pn_two(out.stat)
    ret (out, ok)
}

// the average ranks of a column of the ns by nr matrix
fn rank_col(a: *mem.Arena, x: []const f64, ns: usize, nr: usize, col: usize, out: []f64) {
    var i = 0usize
    while i < ns {
        var less = 0.0f64
        var eq = 0.0f64
        var j = 0usize
        while j < ns {
            if x[j * nr + col] < x[i * nr + col] { less += 1.0f64 }
            if x[j * nr + col] == x[i * nr + col] { eq += 1.0f64 }
            j += 1usize
        }
        out[i] = less + (eq + 1.0f64) / 2.0f64
        i += 1usize
    }
}

// kendall(ratings, correct): W (Wt when corrected), the chi-squared statistic and its p value
fn kendall(a: *mem.Arena, x: []const f64, ns: usize, nr: usize, correct: bool) -> (Test, err) {
    var out = Test { value: 0.0f64, stat: 0.0f64, p: 0.0f64 }
    let (rs, e1) = mem.alloc[f64](a, ns)
    let (rc, e2) = mem.alloc[f64](a, ns)
    if e1 != ok || e2 != ok { ret (out, e1) }
    var i = 0usize
    while i < ns {
        rs[i] = 0.0f64
        i += 1usize
    }
    var tj = 0.0f64
    var c = 0usize
    while c < nr {
        rank_col(a, x, ns, nr, c, rc)
        i = 0usize
        while i < ns {
            rs[i] += rc[i]
            i += 1usize
        }
        if correct {
            // tie groups of the ranks
            i = 0usize
            while i < ns {
                var cnt = 0.0f64
                var first = true
                var j = 0usize
                while j < ns {
                    if rc[j] == rc[i] {
                        cnt += 1.0f64
                        if j < i { first = false }
                    }
                    j += 1usize
                }
                if first && cnt > 1.0f64 { tj += cnt * cnt * cnt - cnt }
                i += 1usize
            }
        }
        c += 1usize
    }
    let nsf = f64(ns)
    let nrf = f64(nr)
    var coeff = (12.0f64 * var_of(rs) * (nsf - 1.0f64)) / (nrf * nrf * (nsf * nsf * nsf - nsf))
    if correct { coeff = (12.0f64 * var_of(rs) * (nsf - 1.0f64)) / (nrf * nrf * (nsf * nsf * nsf - nsf) - nrf * tj) }
    out.value = coeff
    out.stat = nrf * (nsf - 1.0f64) * coeff
    out.p = nm.pchisq(out.stat, nsf - 1.0f64, false, false)
    ret (out, ok)
}

fn pearson(x: []const f64, ns: usize, nr: usize, c1: usize, c2: usize) -> f64 {
    var m1 = 0.0f64
    var m2 = 0.0f64
    var i = 0usize
    while i < ns {
        m1 += x[i * nr + c1]
        m2 += x[i * nr + c2]
        i += 1usize
    }
    m1 = m1 / f64(ns)
    m2 = m2 / f64(ns)
    var sxy = 0.0f64
    var sxx = 0.0f64
    var syy = 0.0f64
    i = 0usize
    while i < ns {
        let dx = x[i * nr + c1] - m1
        let dy = x[i * nr + c2] - m2
        sxy += dx * dy
        sxx += dx * dx
        syy += dy * dy
        i += 1usize
    }
    ret sxy / math.sqrt[f64](sxx * syy)
}

// meancor(ratings, fisher): the mean pairwise correlation (through Fisher's z when fisher), z and p
fn meancor(a: *mem.Arena, x: []const f64, ns: usize, nr: usize, fisher: bool) -> (Test, err) {
    var out = Test { value: 0.0f64, stat: nan(), p: nan() }
    var sum = 0.0f64
    var cnt = 0usize
    var all = 0.0f64
    var allc = 0usize
    var i = 0usize
    while i + 1usize < nr {
        var j = i + 1usize
        while j < nr {
            let r = pearson(x, ns, nr, i, j)
            all += r
            allc += 1usize
            if r < 1.0f64 && r > 0.0f64 - 1.0f64 {
                sum += 0.5f64 * math.log[f64]((1.0f64 + r) / (1.0f64 - r))
                cnt += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    if fisher {
        let mrz = sum / f64(cnt)
        out.value = (math.exp[f64](2.0f64 * mrz) - 1.0f64) / (math.exp[f64](2.0f64 * mrz) + 1.0f64)
        out.stat = out.value / math.sqrt[f64](1.0f64 / (f64(ns) - 3.0f64))
        out.p = pn_two(out.stat)
    } else {
        out.value = all / f64(allc)
    }
    ret (out, ok)
}

// maxwell(ratings): 2 sum(diag) / ns - 1 for two raters and two categories
fn maxwell(x: []const f64, ns: usize) -> f64 {
    var same = 0.0f64
    var i = 0usize
    while i < ns {
        if x[i * 2usize] == x[i * 2usize + 1usize] { same += 1.0f64 }
        i += 1usize
    }
    ret 2.0f64 * same / f64(ns) - 1.0f64
}

// the sums of squares of the ns by nr table: total, rows (MSr form) and columns
fn mean_squares(x: []const f64, ns: usize, nr: usize, rowv: []f64, colv: []f64) -> f64 {
    var i = 0usize
    while i < ns {
        var s = 0.0f64
        var j = 0usize
        while j < nr {
            s += x[i * nr + j]
            j += 1usize
        }
        rowv[i] = s / f64(nr)
        i += 1usize
    }
    var j = 0usize
    while j < nr {
        var s = 0.0f64
        i = 0usize
        while i < ns {
            s += x[i * nr + j]
            i += 1usize
        }
        colv[j] = s / f64(ns)
        j += 1usize
    }
    ret var_of(x[0usize..ns * nr])
}

// robinson(ratings)
fn robinson(a: *mem.Arena, x: []const f64, ns: usize, nr: usize) -> f64 {
    let (rowv, e1) = mem.alloc[f64](a, ns)
    let (colv, e2) = mem.alloc[f64](a, nr)
    if e1 != ok || e2 != ok { ret nan() }
    let vt = mean_squares(x, ns, nr, rowv, colv)
    let sst = vt * f64(ns * nr - 1usize)
    let ssb = var_of(rowv) * f64(nr) * f64(ns - 1usize)
    let ssw = var_of(colv) * f64(ns) * f64(nr - 1usize)
    let ssr = sst - ssb - ssw
    ret ssb / (ssb + ssr)
}

// the pieces of the ICC and Finn: MSr, MSw, MSc, MSe
fn anova_ms(a: *mem.Arena, x: []const f64, ns: usize, nr: usize) -> ([]f64, err) {
    let (ms, e0) = mem.alloc[f64](a, 4usize)
    let (rowv, e1) = mem.alloc[f64](a, ns)
    let (colv, e2) = mem.alloc[f64](a, nr)
    let (rv, e3) = mem.alloc[f64](a, nr)
    if e0 != ok { ret (ms, e0) }
    if e1 != ok { ret (ms, e1) }
    if e2 != ok { ret (ms, e2) }
    if e3 != ok { ret (ms, e3) }
    let vt = mean_squares(x, ns, nr, rowv, colv)
    let sst = vt * f64(ns * nr - 1usize)
    let msr = var_of(rowv) * f64(nr)
    var msw = 0.0f64
    var i = 0usize
    while i < ns {
        var j = 0usize
        while j < nr {
            rv[j] = x[i * nr + j]
            j += 1usize
        }
        msw += var_of(rv) / f64(ns)
        i += 1usize
    }
    let msc = var_of(colv) * f64(ns)
    let mse = (sst - msr * f64(ns - 1usize) - msc * f64(nr - 1usize)) / (f64(ns - 1usize) * f64(nr - 1usize))
    ms[0usize] = msr
    ms[1usize] = msw
    ms[2usize] = msc
    ms[3usize] = mse
    ret (ms, ok)
}

// finn(ratings, s.levels, model): the coefficient, F and p (F against Inf and ns (nr - 1) degrees of freedom)
fn finn(a: *mem.Arena, x: []const f64, ns: usize, nr: usize, slevels: f64, twoway: bool) -> (Test, err) {
    var out = Test { value: 0.0f64, stat: 0.0f64, p: 0.0f64 }
    let (ms, e) = anova_ms(a, x, ns, nr)
    if e != ok { ret (out, e) }
    let msexp = 1.0f64 / 12.0f64 * (slevels * slevels - 1.0f64)
    var den = ms[1usize]
    if twoway { den = ms[3usize] }
    out.value = 1.0f64 - den / msexp
    out.stat = msexp / den
    out.p = nb.pf(out.stat, 1.0f64 / 0.0f64, f64(ns) * f64(nr - 1usize), false, false)
    ret (out, ok)
}

type Icc = struct { value: f64, f: f64, df1: f64, df2: f64, p: f64, lbound: f64, ubound: f64 }

// icc(ratings, model, type, unit, r0, conf.level): model 0 oneway 1 twoway; type 0 consistency 1 agreement; unit 0 single 1 average
fn icc(a: *mem.Arena, x: []const f64, ns: usize, nr: usize, model: u8, kind: u8, unit: u8, r0: f64, conf: f64) -> (Icc, err) {
    var out = Icc { value: 0.0f64, f: 0.0f64, df1: 0.0f64, df2: 0.0f64, p: 0.0f64, lbound: 0.0f64, ubound: 0.0f64 }
    let (ms, e) = anova_ms(a, x, ns, nr)
    if e != ok { ret (out, e) }
    let msr = ms[0usize]
    let msw = ms[1usize]
    let msc = ms[2usize]
    let mse = ms[3usize]
    let alpha = 1.0f64 - conf
    let n = f64(ns)
    let k = f64(nr)
    var coeff = 0.0f64
    var fv = 0.0f64
    var df1 = 0.0f64
    var df2 = 0.0f64
    var lb = 0.0f64
    var ub = 0.0f64
    if unit == 0u8 {
        if model == 0u8 {
            coeff = (msr - msw) / (msr + (k - 1.0f64) * msw)
            fv = msr / msw * ((1.0f64 - r0) / (1.0f64 + (k - 1.0f64) * r0))
            df1 = n - 1.0f64
            df2 = n * (k - 1.0f64)
            let fl = (msr / msw) / nb.qf(1.0f64 - alpha / 2.0f64, n - 1.0f64, n * (k - 1.0f64), true, false)
            let fu = (msr / msw) * nb.qf(1.0f64 - alpha / 2.0f64, n * (k - 1.0f64), n - 1.0f64, true, false)
            lb = (fl - 1.0f64) / (fl + (k - 1.0f64))
            ub = (fu - 1.0f64) / (fu + (k - 1.0f64))
        } else if kind == 0u8 {
            coeff = (msr - mse) / (msr + (k - 1.0f64) * mse)
            fv = msr / mse * ((1.0f64 - r0) / (1.0f64 + (k - 1.0f64) * r0))
            df1 = n - 1.0f64
            df2 = (n - 1.0f64) * (k - 1.0f64)
            let fl = (msr / mse) / nb.qf(1.0f64 - alpha / 2.0f64, n - 1.0f64, (n - 1.0f64) * (k - 1.0f64), true, false)
            let fu = (msr / mse) * nb.qf(1.0f64 - alpha / 2.0f64, (n - 1.0f64) * (k - 1.0f64), n - 1.0f64, true, false)
            lb = (fl - 1.0f64) / (fl + (k - 1.0f64))
            ub = (fu - 1.0f64) / (fu + (k - 1.0f64))
        } else {
            coeff = (msr - mse) / (msr + (k - 1.0f64) * mse + (k / n) * (msc - mse))
            var aa = (k * r0) / (n * (1.0f64 - r0))
            var bb = 1.0f64 + (k * r0 * (n - 1.0f64)) / (n * (1.0f64 - r0))
            var v = (aa * msc + bb * mse) * (aa * msc + bb * mse) / ((aa * msc) * (aa * msc) / (k - 1.0f64) + (bb * mse) * (bb * mse) / ((n - 1.0f64) * (k - 1.0f64)))
            fv = msr / (aa * msc + bb * mse)
            df1 = n - 1.0f64
            df2 = v
            aa = (k * coeff) / (n * (1.0f64 - coeff))
            bb = 1.0f64 + (k * coeff * (n - 1.0f64)) / (n * (1.0f64 - coeff))
            v = (aa * msc + bb * mse) * (aa * msc + bb * mse) / ((aa * msc) * (aa * msc) / (k - 1.0f64) + (bb * mse) * (bb * mse) / ((n - 1.0f64) * (k - 1.0f64)))
            let fl = nb.qf(1.0f64 - alpha / 2.0f64, n - 1.0f64, v, true, false)
            let fu = nb.qf(1.0f64 - alpha / 2.0f64, v, n - 1.0f64, true, false)
            lb = (n * (msr - fl * mse)) / (fl * (k * msc + (k * n - k - n) * mse) + n * msr)
            ub = (n * (fu * msr - mse)) / (k * msc + (k * n - k - n) * mse + n * fu * msr)
        }
    } else {
        if model == 0u8 {
            coeff = (msr - msw) / msr
            fv = msr / msw * (1.0f64 - r0)
            df1 = n - 1.0f64
            df2 = n * (k - 1.0f64)
            let fl = (msr / msw) / nb.qf(1.0f64 - alpha / 2.0f64, n - 1.0f64, n * (k - 1.0f64), true, false)
            let fu = (msr / msw) * nb.qf(1.0f64 - alpha / 2.0f64, n * (k - 1.0f64), n - 1.0f64, true, false)
            lb = 1.0f64 - 1.0f64 / fl
            ub = 1.0f64 - 1.0f64 / fu
        } else if kind == 0u8 {
            coeff = (msr - mse) / msr
            fv = msr / mse * (1.0f64 - r0)
            df1 = n - 1.0f64
            df2 = (n - 1.0f64) * (k - 1.0f64)
            let fl = (msr / mse) / nb.qf(1.0f64 - alpha / 2.0f64, n - 1.0f64, (n - 1.0f64) * (k - 1.0f64), true, false)
            let fu = (msr / mse) * nb.qf(1.0f64 - alpha / 2.0f64, (n - 1.0f64) * (k - 1.0f64), n - 1.0f64, true, false)
            lb = 1.0f64 - 1.0f64 / fl
            ub = 1.0f64 - 1.0f64 / fu
        } else {
            coeff = (msr - mse) / (msr + (msc - mse) / n)
            var aa = r0 / (n * (1.0f64 - r0))
            var bb = 1.0f64 + (r0 * (n - 1.0f64)) / (n * (1.0f64 - r0))
            var v = (aa * msc + bb * mse) * (aa * msc + bb * mse) / ((aa * msc) * (aa * msc) / (k - 1.0f64) + (bb * mse) * (bb * mse) / ((n - 1.0f64) * (k - 1.0f64)))
            fv = msr / (aa * msc + bb * mse)
            df1 = n - 1.0f64
            df2 = v
            aa = (k * coeff) / (n * (1.0f64 - coeff))
            bb = 1.0f64 + (k * coeff * (n - 1.0f64)) / (n * (1.0f64 - coeff))
            v = (aa * msc + bb * mse) * (aa * msc + bb * mse) / ((aa * msc) * (aa * msc) / (k - 1.0f64) + (bb * mse) * (bb * mse) / ((n - 1.0f64) * (k - 1.0f64)))
            let fl = nb.qf(1.0f64 - alpha / 2.0f64, n - 1.0f64, v, true, false)
            let fu = nb.qf(1.0f64 - alpha / 2.0f64, v, n - 1.0f64, true, false)
            lb = (n * (msr - fl * mse)) / (fl * (msc - mse) + n * msr)
            ub = (n * (fu * msr - mse)) / (msc - mse + n * fu * msr)
        }
    }
    out.value = coeff
    out.f = fv
    out.df1 = df1
    out.df2 = df2
    out.p = nb.pf(fv, df1, df2, false, false)
    out.lbound = lb
    out.ubound = ub
    ret (out, ok)
}

// kripp.alpha(x, method): x is nraters by nobjects row-major (NaN for a missing rating); method 0 nominal 1 ordinal 2 interval 3 ratio
fn kripp_alpha(a: *mem.Arena, x: []const f64, nrat: usize, nobj: usize, method: u8) -> (f64, err) {
    // the distinct non-missing values
    let (flat, e0) = mem.alloc[f64](a, nrat * nobj)
    if e0 != ok { ret (nan(), e0) }
    var m = 0usize
    var i = 0usize
    while i < nrat * nobj {
        if x[i] == x[i] {
            flat[m] = x[i]
            m += 1usize
        }
        i += 1usize
    }
    let (lev, le) = levels_of(a, flat[0usize..m])
    if le != ok { ret (nan(), le) }
    let nv = lev.len
    let (cm, e1) = mem.alloc[f64](a, nv * nv)
    if e1 != ok { ret (nan(), e1) }
    i = 0usize
    while i < nv * nv {
        cm[i] = 0.0f64
        i += 1usize
    }
    var any_na = false
    i = 0usize
    while i < nrat * nobj {
        if x[i] != x[i] { any_na = true }
        i += 1usize
    }
    var col = 0usize
    while col < nobj {
        var mc = 1.0f64
        if any_na {
            var c = 0.0f64
            var r = 0usize
            while r < nrat {
                if x[r * nobj + col] == x[r * nobj + col] { c += 1.0f64 }
                r += 1usize
            }
            mc = c - 1.0f64
        }
        var i1 = 0usize
        while i1 + 1usize < nrat {
            var i2 = i1 + 1usize
            while i2 < nrat {
                let v1 = x[i1 * nobj + col]
                let v2 = x[i2 * nobj + col]
                if v1 == v1 && v2 == v2 {
                    let a1 = index_of(lev, v1)
                    let a2 = index_of(lev, v2)
                    var inc = 1.0f64
                    if a1 == a2 { inc = 2.0f64 }
                    cm[a1 * nv + a2] += inc / mc
                    if a1 != a2 { cm[a2 * nv + a1] = cm[a1 * nv + a2] }
                }
                i2 += 1usize
            }
            i1 += 1usize
        }
        col += 1usize
    }
    var nmv = 0.0f64
    i = 0usize
    while i < nv * nv {
        nmv += cm[i]
        i += 1usize
    }
    if nv < 2usize { ret (1.0f64, ok) }
    let (nc, e2) = mem.alloc[f64](a, nv)
    if e2 != ok { ret (nan(), e2) }
    i = 0usize
    while i < nv {
        var s = 0.0f64
        var j = 0usize
        while j < nv {
            s += cm[i * nv + j]
            j += 1usize
        }
        nc[i] = s
        i += 1usize
    }
    var sum_utd = 0.0f64
    var sum_nnd = 0.0f64
    var k = 1usize
    while k < nv {
        var c = 0usize
        while c < k {
            var d2 = 0.0f64
            if method == 0u8 { d2 = 1.0f64 }
            if method == 1u8 {
                d2 = nc[c] / 2.0f64
                var g = c + 1usize
                while g < k {
                    d2 += nc[g]
                    g += 1usize
                }
                d2 += nc[k] / 2.0f64
                d2 = d2 * d2
            }
            if method == 2u8 { d2 = (lev[c] - lev[k]) * (lev[c] - lev[k]) }
            if method == 3u8 { d2 = (lev[c] - lev[k]) * (lev[c] - lev[k]) / ((lev[c] + lev[k]) * (lev[c] + lev[k])) }
            sum_utd += cm[c * nv + k] * d2
            sum_nnd += nc[c] * nc[k] * d2
            c += 1usize
        }
        k += 1usize
    }
    ret (1.0f64 - (nmv - 1.0f64) * sum_utd / sum_nnd, ok)
}

// the sums of squares of one ns by nr matrix for iota: (SSt, SSw, SSc)
fn iota_ss(a: *mem.Arena, m: []const f64, ns: usize, nr: usize) -> (f64, f64, f64) {
    let sst = var_of(m[0usize..ns * nr]) * f64(ns * nr - 1usize)
    let (rv, e) = mem.alloc[f64](a, nr)
    let (cv, e2) = mem.alloc[f64](a, nr)
    if e != ok || e2 != ok { ret (nan(), nan(), nan()) }
    var sw = 0.0f64
    var i = 0usize
    while i < ns {
        var j = 0usize
        while j < nr {
            rv[j] = m[i * nr + j]
            j += 1usize
        }
        sw += var_of(rv) / f64(ns)
        i += 1usize
    }
    var j = 0usize
    while j < nr {
        var s = 0.0f64
        i = 0usize
        while i < ns {
            s += m[i * nr + j]
            i += 1usize
        }
        cv[j] = s / f64(ns)
        j += 1usize
    }
    ret (sst, sw * f64(ns) * f64(nr - 1usize), var_of(cv) * f64(ns) * f64(nr - 1usize))
}

// iota(ratings, scaledata, standardize): vars holds nvar ns by nr matrices one after another
fn iota(a: *mem.Arena, vars: []const f64, ns: usize, nr: usize, nvar: usize, nominal: bool, standardize: bool) -> (f64, err) {
    let sz = ns * nr
    var dos = 0.0f64
    var des = 0.0f64
    let (buf, be) = mem.alloc[f64](a, sz)
    if be != ok { ret (nan(), be) }
    var v = 0usize
    while v < nvar {
        let blk = vars[v * sz..(v + 1usize) * sz]
        if !nominal {
            var i = 0usize
            while i < sz {
                buf[i] = blk[i]
                i += 1usize
            }
            if standardize {
                var s = 0.0f64
                i = 0usize
                while i < sz {
                    s += blk[i]
                    i += 1usize
                }
                let mean = s / f64(sz)
                let sd = math.sqrt[f64](var_of(blk))
                i = 0usize
                while i < sz {
                    buf[i] = (blk[i] - mean) / sd
                    i += 1usize
                }
            }
            let (sst, ssw, ssc) = iota_ss(a, buf, ns, nr)
            dos += ssw
            des += (f64(nr) - 1.0f64) * sst + ssc
        } else {
            let (lev, le) = levels_of(a, blk)
            if le != ok { ret (nan(), le) }
            var l = 0usize
            while l < lev.len {
                var i = 0usize
                while i < sz {
                    buf[i] = 0.0f64
                    if blk[i] == lev[l] { buf[i] = 1.0f64 / math.sqrt[f64](2.0f64) }
                    i += 1usize
                }
                let (sst, ssw, ssc) = iota_ss(a, buf, ns, nr)
                dos += ssw
                des += (f64(nr) - 1.0f64) * sst + ssc
                l += 1usize
            }
        }
        v += 1usize
    }
    ret (1.0f64 - (f64(nr) * dos) / des, ok)
}
