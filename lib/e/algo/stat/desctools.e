// R DescTools: Skew and Kurt (methods 1, 2 and 3, the moment, sample-adjusted and Minitab-style forms), Gini (unbiased or not), MeanAD about the mean, Gmean,
// Hmean, Entropy (Shannon, base 2, of the values as frequencies) and CoefVar.
//
// Mode (the values with the largest count) and Outlier (boxplot and hampel rules) are at the end.
//
// Not here: the rest of the package (the association measures, tests and confidence intervals).

use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.mem

error TooMany

fn mean_of(x: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += x[i]
        i += 1usize
    }
    ret s / f64(x.len)
}

fn moment(x: []const f64, k: f64) -> f64 {
    let m = mean_of(x)
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += math.pow[f64](x[i] - m, k)
        i += 1usize
    }
    ret s / f64(x.len)
}

fn sd_of(x: []const f64) -> f64 {
    let m = mean_of(x)
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    ret math.sqrt[f64](s / (f64(x.len) - 1.0f64))
}

// method 1 g1 = m3 / m2^1.5; 2 G1 = g1 sqrt(n (n - 1)) / (n - 2); 3 b1 = m3 / s^3 with the (n - 1) standard deviation
fn skew(x: []const f64, method: usize) -> f64 {
    let n = f64(x.len)
    let m2 = moment(x, 2.0f64)
    let m3 = moment(x, 3.0f64)
    let g1 = m3 / math.pow[f64](m2, 1.5f64)
    if method == 1usize { ret g1 }
    if method == 2usize { ret g1 * math.sqrt[f64](n * (n - 1.0f64)) / (n - 2.0f64) }
    ret m3 / math.pow[f64](sd_of(x), 3.0f64)
}

// method 1 g2 = m4 / m2^2 - 3; 2 G2 = (n - 1) / ((n - 2)(n - 3)) ((n + 1) g2 + 6); 3 b2 = m4 / s^4 - 3 with the (n - 1) standard deviation
fn kurt(x: []const f64, method: usize) -> f64 {
    let n = f64(x.len)
    let m2 = moment(x, 2.0f64)
    let m4 = moment(x, 4.0f64)
    let g2 = m4 / (m2 * m2) - 3.0f64
    if method == 1usize { ret g2 }
    if method == 2usize { ret (n - 1.0f64) / ((n - 2.0f64) * (n - 3.0f64)) * ((n + 1.0f64) * g2 + 6.0f64) }
    ret m4 / math.pow[f64](sd_of(x), 4.0f64) - 3.0f64
}

fn sorted_copy(a: *mem.Arena, x: []const f64) -> ([]f64, err) {
    let (s, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret (s, e) }
    var i = 0usize
    while i < x.len {
        s[i] = x[i]
        i += 1usize
    }
    i = 1usize
    while i < s.len {
        let t = s[i]
        var j = i
        while j > 0usize && s[j - 1usize] > t {
            s[j] = s[j - 1usize]
            j -= 1usize
        }
        s[j] = t
        i += 1usize
    }
    ret (s, ok)
}

// Gini(x, unbiased): 2 sum i x_(i) / (n sum x) - (n + 1) / n, times n / (n - 1) when unbiased
fn gini(a: *mem.Arena, x: []const f64, unbiased: bool) -> f64 {
    let (s, e) = sorted_copy(a, x)
    if e != ok { ret 0.0f64 / 0.0f64 }
    let n = f64(x.len)
    var num = 0.0f64
    var tot = 0.0f64
    var i = 0usize
    while i < s.len {
        num += f64(i + 1usize) * s[i]
        tot += s[i]
        i += 1usize
    }
    let g = 2.0f64 * num / (n * tot) - (n + 1.0f64) / n
    if unbiased { ret g * n / (n - 1.0f64) }
    ret g
}

fn mean_ad(x: []const f64) -> f64 {
    let m = mean_of(x)
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += math.abs[f64](x[i] - m)
        i += 1usize
    }
    ret s / f64(x.len)
}

fn gmean(x: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += math.log[f64](x[i])
        i += 1usize
    }
    ret math.exp[f64](s / f64(x.len))
}

fn hmean(x: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += 1.0f64 / x[i]
        i += 1usize
    }
    ret f64(x.len) / s
}

// Entropy(x): the Shannon entropy in bits of the values taken as frequencies
fn entropy(x: []const f64) -> f64 {
    var t = 0.0f64
    var i = 0usize
    while i < x.len {
        t += x[i]
        i += 1usize
    }
    var h = 0.0f64
    i = 0usize
    while i < x.len {
        let p = x[i] / t
        if p > 0.0f64 { h -= p * math.log[f64](p) / math.log[f64](2.0f64) }
        i += 1usize
    }
    ret h
}

fn coef_var(x: []const f64) -> f64 { ret sd_of(x) / mean_of(x) }

// ---- association measures of an r by c table of counts (row-major)

fn chisq_of(t: []const f64, r: usize, c: usize) -> f64 {
    var n = 0.0f64
    var i = 0usize
    while i < r * c {
        n += t[i]
        i += 1usize
    }
    var chi = 0.0f64
    i = 0usize
    while i < r {
        var rs = 0.0f64
        var j = 0usize
        while j < c {
            rs += t[i * c + j]
            j += 1usize
        }
        j = 0usize
        while j < c {
            var cs = 0.0f64
            var k = 0usize
            while k < r {
                cs += t[k * c + j]
                k += 1usize
            }
            let e = rs * cs / n
            chi += (t[i * c + j] - e) * (t[i * c + j] - e) / e
            j += 1usize
        }
        i += 1usize
    }
    ret chi
}

fn total_of(t: []const f64) -> f64 {
    var n = 0.0f64
    var i = 0usize
    while i < t.len {
        n += t[i]
        i += 1usize
    }
    ret n
}

fn cramer_v(t: []const f64, r: usize, c: usize) -> f64 {
    var m = r
    if c < m { m = c }
    ret math.sqrt[f64](chisq_of(t, r, c) / (total_of(t) * f64(m - 1usize)))
}

fn phi_coef(t: []const f64, r: usize, c: usize) -> f64 { ret math.sqrt[f64](chisq_of(t, r, c) / total_of(t)) }

fn cont_coef(t: []const f64, r: usize, c: usize) -> f64 {
    let chi = chisq_of(t, r, c)
    ret math.sqrt[f64](chi / (chi + total_of(t)))
}

fn tschuprow_t(t: []const f64, r: usize, c: usize) -> f64 {
    ret math.sqrt[f64](chisq_of(t, r, c) / (total_of(t) * math.sqrt[f64](f64((r - 1usize) * (c - 1usize)))))
}

// the concordant and discordant pair counts
fn pairs_cd(t: []const f64, r: usize, c: usize) -> (f64, f64) {
    var cc = 0.0f64
    var dd = 0.0f64
    var i = 0usize
    while i < r {
        var j = 0usize
        while j < c {
            var k = i + 1usize
            while k < r {
                var l = 0usize
                while l < c {
                    if l > j { cc += t[i * c + j] * t[k * c + l] }
                    if l < j { dd += t[i * c + j] * t[k * c + l] }
                    l += 1usize
                }
                k += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    ret (cc, dd)
}

// kind: 0 Goodman-Kruskal gamma, 1 Kendall tau-b, 2 Stuart tau-c, 3 Somers d (row), 4 Somers d (column)
fn ordinal_assoc(t: []const f64, r: usize, c: usize, kind: usize) -> f64 {
    let (cc, dd) = pairs_cd(t, r, c)
    let n = total_of(t)
    let n0 = n * (n - 1.0f64) / 2.0f64
    var n1 = 0.0f64
    var i = 0usize
    while i < r {
        var rs = 0.0f64
        var j = 0usize
        while j < c {
            rs += t[i * c + j]
            j += 1usize
        }
        n1 += rs * (rs - 1.0f64) / 2.0f64
        i += 1usize
    }
    var n2 = 0.0f64
    var j = 0usize
    while j < c {
        var cs = 0.0f64
        i = 0usize
        while i < r {
            cs += t[i * c + j]
            i += 1usize
        }
        n2 += cs * (cs - 1.0f64) / 2.0f64
        j += 1usize
    }
    if kind == 0usize { ret (cc - dd) / (cc + dd) }
    if kind == 1usize { ret (cc - dd) / math.sqrt[f64]((n0 - n1) * (n0 - n2)) }
    if kind == 2usize {
        var m = r
        if c < m { m = c }
        ret 2.0f64 * f64(m) * (cc - dd) / (n * n * f64(m - 1usize))
    }
    if kind == 3usize { ret (cc - dd) / (n0 - n2) }
    ret (cc - dd) / (n0 - n1)
}

fn row_sum(t: []const f64, r: usize, c: usize, i: usize) -> f64 {
    var s = 0.0f64
    var j = 0usize
    while j < c {
        s += t[i * c + j]
        j += 1usize
    }
    ret s
}

fn col_sum(t: []const f64, r: usize, c: usize, j: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < r {
        s += t[i * c + j]
        i += 1usize
    }
    ret s
}

// Cohen's kappa of a square table
fn cohen_kappa(t: []const f64, r: usize) -> f64 {
    let n = total_of(t)
    var po = 0.0f64
    var pe = 0.0f64
    var i = 0usize
    while i < r {
        po += t[i * r + i]
        pe += row_sum(t, r, r, i) * col_sum(t, r, r, i)
        i += 1usize
    }
    po = po / n
    pe = pe / (n * n)
    ret (po - pe) / (1.0f64 - pe)
}

// Goodman-Kruskal lambda: dir 0 symmetric, 1 "row" (the sum of column maxima), 2 "column" (the sum of row maxima)
fn lambda_gk(t: []const f64, r: usize, c: usize, dir: usize) -> f64 {
    let n = total_of(t)
    var maxr = 0.0f64
    var sum_row_max = 0.0f64
    var i = 0usize
    while i < r {
        var m = 0.0f64
        var j = 0usize
        while j < c {
            if t[i * c + j] > m { m = t[i * c + j] }
            j += 1usize
        }
        sum_row_max += m
        let rs = row_sum(t, r, c, i)
        if rs > maxr { maxr = rs }
        i += 1usize
    }
    var maxc = 0.0f64
    var sum_col_max = 0.0f64
    var j = 0usize
    while j < c {
        var m = 0.0f64
        i = 0usize
        while i < r {
            if t[i * c + j] > m { m = t[i * c + j] }
            i += 1usize
        }
        sum_col_max += m
        let cs = col_sum(t, r, c, j)
        if cs > maxc { maxc = cs }
        j += 1usize
    }
    if dir == 1usize { ret (sum_col_max - maxr) / (n - maxr) }
    if dir == 2usize { ret (sum_row_max - maxc) / (n - maxc) }
    ret (sum_col_max + sum_row_max - maxr - maxc) / (2.0f64 * n - maxr - maxc)
}

// Goodman-Kruskal tau as DescTools names the directions: 1 "row", 2 "column"
fn gk_tau(t: []const f64, r: usize, c: usize, dir: usize) -> f64 {
    let n = total_of(t)
    var sa = 0.0f64
    var sb = 0.0f64
    var i = 0usize
    while i < r {
        let rs = row_sum(t, r, c, i)
        sb += (rs / n) * (rs / n)
        var j = 0usize
        while j < c {
            let p = t[i * c + j] / n
            sa += p * p / (col_sum(t, r, c, j) / n)
            j += 1usize
        }
        i += 1usize
    }
    // sa: sum p_ij^2 / p_.j ; sb: sum p_i.^2
    var sc = 0.0f64
    var sd = 0.0f64
    var j = 0usize
    while j < c {
        let cs = col_sum(t, r, c, j)
        sd += (cs / n) * (cs / n)
        i = 0usize
        while i < r {
            let p = t[i * c + j] / n
            sc += p * p / (row_sum(t, r, c, i) / n)
            i += 1usize
        }
        j += 1usize
    }
    if dir == 1usize { ret (sa - sb) / (1.0f64 - sb) }
    ret (sc - sd) / (1.0f64 - sd)
}

fn odds_ratio(t: []const f64) -> f64 { ret t[0usize] * t[3usize] / (t[1usize] * t[2usize]) }

fn yule_q(t: []const f64) -> f64 {
    let o = odds_ratio(t)
    ret (o - 1.0f64) / (o + 1.0f64)
}

fn min_f(a: f64, b: f64) -> f64 {
    if a < b { ret a }
    ret b
}

fn max_f(a: f64, b: f64) -> f64 {
    if a > b { ret a }
    ret b
}

// BinomCI(x, n, conf, method) two-sided: part 0 the estimate, 1 the lower limit, 2 the upper. method 0 wald, 1 waldcc, 2 wilson, 3 wilsoncc, 4 agresti-coull,
// 5 jeffreys, 6 modified wilson, 7 modified jeffreys, 8 clopper-pearson, 9 arcsine, 10 logit
fn binom_ci(x: f64, n: f64, conf: f64, method: usize, part: usize) -> f64 {
    let alpha = 1.0f64 - conf
    let kappa = dist.qnorm(1.0f64 - alpha / 2.0f64, 0.0f64, 1.0f64, true, false)
    let ph = x / n
    let qh = 1.0f64 - ph
    var lo = 0.0f64
    var hi = 1.0f64
    var est = ph
    if method == 0usize || method == 1usize {
        var t = kappa * math.sqrt[f64](ph * qh) / math.sqrt[f64](n)
        if method == 1usize { t += 1.0f64 / (2.0f64 * n) }
        lo = max_f(0.0f64, ph - t)
        hi = min_f(1.0f64, ph + t)
    } else if method == 2usize || method == 6usize {
        let t1 = (x + kappa * kappa / 2.0f64) / (n + kappa * kappa)
        let t2 = kappa * math.sqrt[f64](n) / (n + kappa * kappa) * math.sqrt[f64](ph * qh + kappa * kappa / (4.0f64 * n))
        lo = max_f(0.0f64, t1 - t2)
        hi = min_f(1.0f64, t1 + t2)
        if method == 6usize {
            if (n <= 50.0f64 && (x == 1.0f64 || x == 2.0f64)) || (n >= 51.0f64 && (x == 1.0f64 || x == 2.0f64 || x == 3.0f64)) {
                lo = 0.5f64 * nm.qchisq(alpha, 2.0f64 * x, true, false) / n
            }
            if (n <= 50.0f64 && (x == n - 1.0f64 || x == n - 2.0f64)) || (n >= 51.0f64 && (x == n - 1.0f64 || x == n - 2.0f64 || x == n - 3.0f64)) {
                hi = 1.0f64 - 0.5f64 * nm.qchisq(alpha, 2.0f64 * (n - x), true, false) / n
            }
        }
    } else if method == 3usize {
        let k2 = kappa * kappa
        var l = 0.0f64
        var u = 1.0f64
        if ph != 0.0f64 { l = (2.0f64 * x + k2 - 1.0f64 - kappa * math.sqrt[f64](k2 - 2.0f64 - 1.0f64 / n + 4.0f64 * ph * (n * qh + 1.0f64))) / (2.0f64 * (n + k2)) }
        if ph != 1.0f64 { u = (2.0f64 * x + k2 + 1.0f64 + kappa * math.sqrt[f64](k2 + 2.0f64 - 1.0f64 / n + 4.0f64 * ph * (n * qh - 1.0f64))) / (2.0f64 * (n + k2)) }
        lo = max_f(0.0f64, l)
        hi = min_f(1.0f64, u)
    } else if method == 4usize {
        let xt = x + kappa * kappa / 2.0f64
        let nt = n + kappa * kappa
        let pt = xt / nt
        let t = kappa * math.sqrt[f64](pt * (1.0f64 - pt)) / math.sqrt[f64](nt)
        lo = max_f(0.0f64, pt - t)
        hi = min_f(1.0f64, pt + t)
    } else if method == 5usize {
        if x != 0.0f64 { lo = nb.qbeta(alpha / 2.0f64, x + 0.5f64, n - x + 0.5f64, true, false) } else { lo = 0.0f64 }
        if x != n { hi = nb.qbeta(1.0f64 - alpha / 2.0f64, x + 0.5f64, n - x + 0.5f64, true, false) } else { hi = 1.0f64 }
    } else if method == 7usize {
        if x == n { lo = math.pow[f64](alpha / 2.0f64, 1.0f64 / n) } else if x <= 1.0f64 { lo = 0.0f64 } else { lo = nb.qbeta(alpha / 2.0f64, x + 0.5f64, n - x + 0.5f64, true, false) }
        if x == 0.0f64 { hi = 1.0f64 - math.pow[f64](alpha / 2.0f64, 1.0f64 / n) } else if x >= n - 1.0f64 { hi = 1.0f64 } else { hi = nb.qbeta(1.0f64 - alpha / 2.0f64, x + 0.5f64, n - x + 0.5f64, true, false) }
    } else if method == 8usize {
        lo = nb.qbeta(alpha / 2.0f64, x, n - x + 1.0f64, true, false)
        hi = nb.qbeta(1.0f64 - alpha / 2.0f64, x + 1.0f64, n - x, true, false)
    } else if method == 9usize {
        let pt = (x + 0.375f64) / (n + 0.75f64)
        let s1 = math.sin[f64](math.asin[f64](math.sqrt[f64](pt)) - 0.5f64 * kappa / math.sqrt[f64](n))
        let s2 = math.sin[f64](math.asin[f64](math.sqrt[f64](pt)) + 0.5f64 * kappa / math.sqrt[f64](n))
        lo = s1 * s1
        hi = s2 * s2
    } else {
        let lh = math.log[f64](x / (n - x))
        let v = n / (x * (n - x))
        let l1 = lh - kappa * math.sqrt[f64](v)
        let l2 = lh + kappa * math.sqrt[f64](v)
        lo = math.exp[f64](l1) / (1.0f64 + math.exp[f64](l1))
        hi = math.exp[f64](l2) / (1.0f64 + math.exp[f64](l2))
    }
    if part == 0usize { ret est }
    if part == 1usize { ret lo }
    ret hi
}

// quantile(x, p) type 7 on sorted s, with R's rounding fuzz
fn quant7(s: []const f64, p: f64) -> f64 {
    let n = s.len
    let fuzz = 4.0f64 * 2.220446049250313e-16f64
    let idx = f64(n - 1usize) * p
    let lo = math.floor[f64](idx + fuzz)
    var h = idx - lo
    if math.abs[f64](h) < fuzz { h = 0.0f64 }
    let l = usize(lo)
    if h == 0.0f64 || l + 1usize >= n { ret s[l] }
    ret (1.0f64 - h) * s[l] + h * s[l + 1usize]
}

fn median_sorted(s: []const f64) -> f64 {
    let n = s.len
    if n % 2usize == 1usize { ret s[n / 2usize] }
    ret (s[n / 2usize - 1usize] + s[n / 2usize]) / 2.0f64
}

// the position-weighted sum of Winsorize(x, quantile(x, c(plo, phi)))
fn winsor_sum(a: *mem.Arena, x: []const f64, plo: f64, phi: f64) -> f64 {
    let (s, e) = sorted_copy(a, x)
    if e != ok { ret 0.0f64 / 0.0f64 }
    let lo = quant7(s, plo)
    let hi = quant7(s, phi)
    var t = 0.0f64
    var i = 0usize
    while i < x.len {
        var v = x[i]
        if v < lo { v = lo }
        if v > hi { v = hi }
        t += v * f64(i + 1usize)
        i += 1usize
    }
    ret t
}

// HodgesLehmann(x): the median of the Walsh averages (x_i + x_j) / 2, i <= j; with y, the median of the differences x_i - y_j (ny = 0 means one sample)
fn hodges_lehmann(a: *mem.Arena, x: []const f64, y: []const f64) -> f64 {
    let nx = x.len
    let ny = y.len
    var m = nx * (nx + 1usize) / 2usize
    if ny > 0usize { m = nx * ny }
    let (w, e) = mem.alloc[f64](a, m)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var k = 0usize
    var i = 0usize
    while i < nx {
        if ny == 0usize {
            var j = i
            while j < nx {
                w[k] = (x[i] + x[j]) / 2.0f64
                k += 1usize
                j += 1usize
            }
        } else {
            var j = 0usize
            while j < ny {
                w[k] = x[i] - y[j]
                k += 1usize
                j += 1usize
            }
        }
        i += 1usize
    }
    let (s, e2) = sorted_copy(a, w)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    ret median_sorted(s)
}

// MedianCI(x, conf, method = "exact") two-sided: part 0 the median, 1 and 2 the order statistics at k and n - k + 1 with k = qbinom((1 - conf) / 2, n, 0.5); 3 the achieved confidence
fn median_ci(a: *mem.Arena, x: []const f64, conf: f64, part: usize) -> f64 {
    let (s, e) = sorted_copy(a, x)
    if e != ok { ret 0.0f64 / 0.0f64 }
    let n = x.len
    if part == 0usize { ret median_sorted(s) }
    let k = nb.qbinom((1.0f64 - conf) / 2.0f64, f64(n), 0.5f64, true, false)
    let ki = usize(k)
    if part == 1usize { ret s[ki - 1usize] }
    if part == 2usize { ret s[n - ki] }
    ret 1.0f64 - 2.0f64 * nb.pbinom(k - 1.0f64, f64(n), 0.5f64, true, false)
}

// the position-weighted sum of Trim(x, trim) (what is kept, in original order); trim below 0.5 as a fraction
fn trim_sum(a: *mem.Arena, x: []const f64, trim: f64) -> f64 {
    let n = x.len
    let (s, e) = sorted_copy(a, x)
    if e != ok { ret 0.0f64 / 0.0f64 }
    let lo = usize(math.floor[f64](f64(n) * trim)) + 1usize
    let hi = n + 1usize - lo
    var t = 0.0f64
    var q = 0usize
    var i = 0usize
    while i < n {
        if x[i] >= s[lo - 1usize] && x[i] <= s[hi - 1usize] {
            q += 1usize
            t += x[i] * f64(q)
        }
        i += 1usize
    }
    ret t
}

// CochranArmitageTest on an r by 2 table (row-major) with scores 1 .. r: part 0 the statistic Z, 1 the two-sided p-value
fn cochran_armitage(t: []const f64, r: usize, part: usize) -> f64 {
    var n = 0.0f64
    var s1 = 0.0f64
    var i = 0usize
    while i < r {
        n += t[2usize * i] + t[2usize * i + 1usize]
        s1 += t[2usize * i]
        i += 1usize
    }
    var rbar = 0.0f64
    i = 0usize
    while i < r {
        rbar += (t[2usize * i] + t[2usize * i + 1usize]) * f64(i + 1usize)
        i += 1usize
    }
    rbar = rbar / n
    var s2 = 0.0f64
    var num = 0.0f64
    i = 0usize
    while i < r {
        let d = f64(i + 1usize) - rbar
        s2 += (t[2usize * i] + t[2usize * i + 1usize]) * d * d
        num += t[2usize * i] * d
        i += 1usize
    }
    let p1 = s1 / n
    let z = num / math.sqrt[f64](p1 * (1.0f64 - p1) * s2)
    if part == 0usize { ret z }
    ret 2.0f64 * dist.pnorm(math.abs[f64](z), 0.0f64, 1.0f64, false, false)
}

// the Mantel-Haenszel common odds ratio over strata of 2 by 2 tables (a, b, c, d per stratum)
fn mh_or(s: []const f64, k: usize) -> f64 {
    var num = 0.0f64
    var den = 0.0f64
    var j = 0usize
    while j < k {
        let a = s[4usize * j]
        let b = s[4usize * j + 1usize]
        let c = s[4usize * j + 2usize]
        let d = s[4usize * j + 3usize]
        let n = a + b + c + d
        num += a * d / n
        den += b * c / n
        j += 1usize
    }
    ret num / den
}

// BreslowDayTest(x) statistic (tarone false) or with Tarone's correction (true), and the p-value as part 1, on the MH odds ratio
fn breslow_day(s: []const f64, k: usize, tarone: bool, part: usize) -> f64 {
    let orh = mh_or(s, k)
    var x2 = 0.0f64
    var sa = 0.0f64
    var st = 0.0f64
    var sv = 0.0f64
    var j = 0usize
    while j < k {
        let a = s[4usize * j]
        let b = s[4usize * j + 1usize]
        let c = s[4usize * j + 2usize]
        let d = s[4usize * j + 3usize]
        let m1 = a + b
        let m2 = c + d
        let n1 = a + c
        let n2 = b + d
        // c2 z^2 + c1 z + c0 = 0 with the package's coefficients
        let c0 = 0.0f64 - m1 * n1 * orh
        let c1 = n2 - m1 + orh * (n1 + m1)
        let c2 = 1.0f64 - orh
        var lim = n1
        if m1 < lim { lim = m1 }
        var ta = 0.0f64 / 0.0f64
        if c2 == 0.0f64 {
            ta = 0.0f64 - c0 / c1
        } else {
            let disc = c1 * c1 - 4.0f64 * c2 * c0
            let sq = math.sqrt[f64](disc)
            let r1 = (0.0f64 - c1 + sq) / (2.0f64 * c2)
            let r2 = (0.0f64 - c1 - sq) / (2.0f64 * c2)
            if r1 > 0.0f64 && r1 <= lim { ta = r1 } else { ta = r2 }
        }
        let tb = m1 - ta
        let tc = n1 - ta
        let td = m2 - tc
        let v = 1.0f64 / (1.0f64 / ta + 1.0f64 / tb + 1.0f64 / tc + 1.0f64 / td)
        x2 += (a - ta) * (a - ta) / v
        sa += a
        st += ta
        sv += v
        j += 1usize
    }
    var stat = x2
    if tarone { stat = x2 - (sa - st) * (sa - st) / sv }
    if part == 0usize { ret stat }
    ret nm.pchisq(stat, f64(k - 1usize), false, false)
}

// PoissonCI(x, n, conf, method) two-sided, method 0 exact, 1 score, 2 wald, 3 byar; part 0 the rate, 1 the lower limit, 2 the upper
fn poisson_ci(x: f64, n: f64, conf: f64, method: usize, part: usize) -> f64 {
    let alpha = 1.0f64 - conf
    let z = dist.qnorm(1.0f64 - alpha / 2.0f64, 0.0f64, 1.0f64, true, false)
    let lam = x / n
    var lo = 0.0f64
    var hi = 0.0f64
    if method == 0usize {
        if x > 0.0f64 { lo = nm.qgamma(alpha / 2.0f64, x, 1.0f64, true, false) / n }
        hi = nm.qgamma(1.0f64 - alpha / 2.0f64, x + 1.0f64, 1.0f64, true, false) / n
    } else if method == 1usize {
        let t1 = (x + z * z / 2.0f64) / n
        let t2 = z * math.pow[f64](n, 0.0f64 - 0.5f64) * math.sqrt[f64](x / n + z * z / (4.0f64 * n))
        lo = t1 - t2
        hi = t1 + t2
    } else if method == 2usize {
        let t = z * math.sqrt[f64](lam / n)
        lo = lam - t
        hi = lam + t
    } else {
        let xcc = x + 0.5f64
        let zz = (z / 3.0f64) * math.sqrt[f64](1.0f64 / xcc)
        let l1 = 1.0f64 - 1.0f64 / (9.0f64 * xcc) - zz
        let u1 = 1.0f64 - 1.0f64 / (9.0f64 * xcc) + zz
        lo = xcc * l1 * l1 * l1 / n
        hi = xcc * u1 * u1 * u1 / n
    }
    if part == 0usize { ret lam }
    if part == 1usize { ret lo }
    ret hi
}

// MultinomCI(x, conf, method) for category i of counts x: method 0 goodman, 1 wald, 2 waldcc, 3 wilson; part 0 the share, 1 the lower limit, 2 the upper
fn multinom_ci(x: []const f64, i: usize, conf: f64, method: usize, part: usize) -> f64 {
    var n = 0.0f64
    var j = 0usize
    while j < x.len {
        n += x[j]
        j += 1usize
    }
    let k = f64(x.len)
    let xi = x[i]
    let p = xi / n
    var lo = 0.0f64
    var hi = 0.0f64
    if method == 0usize {
        let q = nm.qchisq(1.0f64 - (1.0f64 - conf) / k, 1.0f64, true, false)
        let s = math.sqrt[f64](q * (q + 4.0f64 * xi * (n - xi) / n))
        lo = (q + 2.0f64 * xi - s) / (2.0f64 * (n + q))
        hi = (q + 2.0f64 * xi + s) / (2.0f64 * (n + q))
    } else if method == 1usize || method == 2usize {
        let q = nm.qchisq(conf, 1.0f64, true, false)
        var t = math.sqrt[f64](q * p * (1.0f64 - p) / n)
        if method == 2usize { t += 1.0f64 / (2.0f64 * n) }
        lo = p - t
        hi = p + t
    } else {
        let q = nm.qchisq(conf, 1.0f64, true, false)
        let s = math.sqrt[f64](q * q + 4.0f64 * xi * q * (1.0f64 - p))
        lo = (q + 2.0f64 * xi - s) / (2.0f64 * (q + n))
        hi = (q + 2.0f64 * xi + s) / (2.0f64 * (q + n))
    }
    if part == 0usize { ret p }
    if part == 1usize { ret max_f(0.0f64, lo) }
    ret min_f(1.0f64, hi)
}

// ICC(ratings, type, conf) for an ns by nr matrix (row-major, subjects by raters): the six intraclass correlations from the two-way ANOVA (type 0 ICC1, 1 ICC2, 2 ICC3, 3 ICC1k, 4 ICC2k, 5 ICC3k); part 0 the estimate, 1 the lower and 2 the upper limit
fn icc(x: []const f64, ns: usize, nr: usize, conf: f64, ty: usize, part: usize) -> f64 {
    let n = f64(ns)
    let r = f64(nr)
    var gm = 0.0f64
    var i = 0usize
    while i < ns * nr {
        gm += x[i]
        i += 1usize
    }
    gm = gm / (n * r)
    var ssb = 0.0f64
    i = 0usize
    while i < ns {
        var m = 0.0f64
        var j = 0usize
        while j < nr {
            m += x[i * nr + j]
            j += 1usize
        }
        m = m / r
        ssb += r * (m - gm) * (m - gm)
        i += 1usize
    }
    var ssj = 0.0f64
    var j = 0usize
    while j < nr {
        var m = 0.0f64
        i = 0usize
        while i < ns {
            m += x[i * nr + j]
            i += 1usize
        }
        m = m / n
        ssj += n * (m - gm) * (m - gm)
        j += 1usize
    }
    var sst = 0.0f64
    i = 0usize
    while i < ns * nr {
        sst += (x[i] - gm) * (x[i] - gm)
        i += 1usize
    }
    let sse = sst - ssb - ssj
    let msb = ssb / (n - 1.0f64)
    let msj = ssj / (r - 1.0f64)
    let mse = sse / ((n - 1.0f64) * (r - 1.0f64))
    let msw = (ssj + sse) / ((r - 1.0f64) + (n - 1.0f64) * (r - 1.0f64))
    let icc1 = (msb - msw) / (msb + (r - 1.0f64) * msw)
    let icc2 = (msb - mse) / (msb + (r - 1.0f64) * mse + r * (msj - mse) / n)
    let icc3 = (msb - mse) / (msb + (r - 1.0f64) * mse)
    let icc12 = (msb - msw) / msb
    let icc22 = (msb - mse) / (msb + (msj - mse) / n)
    let icc32 = (msb - mse) / msb
    if part == 0usize {
        if ty == 0usize { ret icc1 }
        if ty == 1usize { ret icc2 }
        if ty == 2usize { ret icc3 }
        if ty == 3usize { ret icc12 }
        if ty == 4usize { ret icc22 }
        ret icc32
    }
    let alpha = 1.0f64 - conf
    let f11 = msb / msw
    let d11n = n - 1.0f64
    let d11d = n * (r - 1.0f64)
    let f21 = msb / mse
    let d21d = (n - 1.0f64) * (r - 1.0f64)
    let f1l = f11 / nb.qf(1.0f64 - alpha / 2.0f64, d11n, d11d, true, false)
    let f1u = f11 * nb.qf(1.0f64 - alpha / 2.0f64, d11d, d11n, true, false)
    let f3l = f21 / nb.qf(1.0f64 - alpha / 2.0f64, d11n, d21d, true, false)
    let f3u = f21 * nb.qf(1.0f64 - alpha / 2.0f64, d21d, d11n, true, false)
    let fj = msj / mse
    let t1 = r * icc2 * fj + n * (1.0f64 + (r - 1.0f64) * icc2) - r * icc2
    let vn = (r - 1.0f64) * (n - 1.0f64) * t1 * t1
    let t2 = n * (1.0f64 + (r - 1.0f64) * icc2) - r * icc2
    let vd = (n - 1.0f64) * r * r * icc2 * icc2 * fj * fj + t2 * t2
    let v = vn / vd
    let g3u = nb.qf(1.0f64 - alpha / 2.0f64, n - 1.0f64, v, true, false)
    let g3l = nb.qf(1.0f64 - alpha / 2.0f64, v, n - 1.0f64, true, false)
    let l3 = n * (msb - g3u * mse) / (g3u * (r * msj + (r * n - r - n) * mse) + n * msb)
    let u3 = n * (g3l * msb - mse) / (r * msj + (r * n - r - n) * mse + n * g3l * msb)
    var lo = 0.0f64
    var hi = 0.0f64
    if ty == 0usize {
        lo = (f1l - 1.0f64) / (f1l + (r - 1.0f64))
        hi = (f1u - 1.0f64) / (f1u + r - 1.0f64)
    } else if ty == 1usize {
        lo = l3
        hi = u3
    } else if ty == 2usize {
        lo = (f3l - 1.0f64) / (f3l + r - 1.0f64)
        hi = (f3u - 1.0f64) / (f3u + r - 1.0f64)
    } else if ty == 3usize {
        lo = 1.0f64 - 1.0f64 / f1l
        hi = 1.0f64 - 1.0f64 / f1u
    } else if ty == 4usize {
        lo = l3 * r / (1.0f64 + l3 * (r - 1.0f64))
        hi = u3 * r / (1.0f64 + u3 * (r - 1.0f64))
    } else {
        lo = 1.0f64 - 1.0f64 / f3l
        hi = 1.0f64 - 1.0f64 / f3u
    }
    if part == 1usize { ret lo }
    ret hi
}

// KappaM(ratings) for ns subjects by nr raters coded 0 .. nl - 1 (row-major): method 0 Fleiss, 1 Conger; part 0 the kappa, 1 and 2 the limits (Fleiss only)
fn kappa_m(x: []const f64, ns: usize, nr: usize, nl: usize, conf: f64, method: usize, part: usize) -> f64 {
    let n = f64(ns)
    let r = f64(nr)
    var agree = 0.0f64
    var i = 0usize
    var pq = 0.0f64
    var pqq = 0.0f64
    var chance_t = 0.0f64
    var l = 0usize
    while l < nl {
        var c = 0.0f64
        i = 0usize
        while i < ns {
            var j = 0usize
            while j < nr {
                if usize(x[i * nr + j]) == l { c += 1.0f64 }
                j += 1usize
            }
            i += 1usize
        }
        chance_t += c * c
        let pj = c / (n * r)
        let qj = 1.0f64 - pj
        pq += pj * qj
        pqq += pj * qj * (qj - pj)
        l += 1usize
    }
    i = 0usize
    while i < ns {
        var rs = 0.0f64
        l = 0usize
        while l < nl {
            var c = 0.0f64
            var j = 0usize
            while j < nr {
                if usize(x[i * nr + j]) == l { c += 1.0f64 }
                j += 1usize
            }
            rs += c * c
            l += 1usize
        }
        agree += (rs - r) / (r * (r - 1.0f64)) / n
        i += 1usize
    }
    var chance = chance_t / ((n * r) * (n * r))
    if method == 1usize {
        var vs = 0.0f64
        l = 0usize
        while l < nl {
            var mean = 0.0f64
            var j = 0usize
            while j < nr {
                var c = 0.0f64
                i = 0usize
                while i < ns {
                    if usize(x[i * nr + j]) == l { c += 1.0f64 }
                    i += 1usize
                }
                mean += c / n
                j += 1usize
            }
            mean = mean / r
            var ss = 0.0f64
            j = 0usize
            while j < nr {
                var c = 0.0f64
                i = 0usize
                while i < ns {
                    if usize(x[i * nr + j]) == l { c += 1.0f64 }
                    i += 1usize
                }
                ss += (c / n - mean) * (c / n - mean)
                j += 1usize
            }
            vs += ss / (r - 1.0f64)
            l += 1usize
        }
        chance = chance - vs * (r - 1.0f64) / r / (r - 1.0f64)
    }
    let value = (agree - chance) / (1.0f64 - chance)
    if part == 0usize { ret value }
    let var_k = (2.0f64 / (pq * pq * (n * r * (r - 1.0f64)))) * (pq * pq - pqq)
    let z = dist.qnorm((1.0f64 - conf) / 2.0f64, 0.0f64, 1.0f64, true, false)
    if part == 1usize { ret value + z * math.sqrt[f64](var_k) }
    ret value - z * math.sqrt[f64](var_k)
}

// DescTools Mode(x) for finite x: the values with the largest count, sorted ascending, written to out; the result is how many there are, with
// the frequency; (0, 0) when x has fewer than two values or every count is one (R gives NA there)
fn mode_of(a: *mem.Arena, x: []const f64, out: []f64) -> (usize, f64, err) {
    let n = x.len
    if n <= 1usize { ret (0usize, 0.0f64, ok) }
    let (cnt, e) = mem.alloc[usize](a, n)
    if e != ok { ret (0usize, 0.0f64, e) }
    var maxc = 0usize
    var i = 0usize
    while i < n {
        var c = 0usize
        var j = 0usize
        while j < n {
            if x[j] == x[i] { c += 1usize }
            j += 1usize
        }
        cnt[i] = c
        if c > maxc { maxc = c }
        i += 1usize
    }
    if maxc <= 1usize { ret (0usize, 0.0f64, ok) }
    var k = 0usize
    i = 0usize
    while i < n {
        if cnt[i] == maxc {
            var seen = false
            var q = 0usize
            while q < k {
                if out[q] == x[i] { seen = true }
                q += 1usize
            }
            if !seen {
                if k >= out.len { ret (0usize, 0.0f64, TooMany) }
                out[k] = x[i]
                k += 1usize
            }
        }
        i += 1usize
    }
    var p = 1usize
    while p < k {
        var q = p
        while q > 0usize && out[q - 1usize] > out[q] {
            let t = out[q]
            out[q] = out[q - 1usize]
            out[q - 1usize] = t
            q -= 1usize
        }
        p += 1usize
    }
    ret (k, f64(maxc), ok)
}

// DescTools Outlier(x, method = "boxplot"): the values below the first quartile minus 1.5 IQR or above the third quartile plus 1.5 IQR (quantile
// type 7). Returns how many and their sum.
fn outlier_box(a: *mem.Arena, x: []const f64) -> (usize, f64, err) {
    let (s, e) = sorted_copy(a, x)
    if e != ok { ret (0usize, 0.0f64, e) }
    if s.len == 0usize { ret (0usize, 0.0f64, ok) }
    let q1 = quant7(s, 0.25f64)
    let q3 = quant7(s, 0.75f64)
    let iqr = q3 - q1
    let lo = q1 - 1.5f64 * iqr
    let hi = q3 + 1.5f64 * iqr
    var cnt = 0usize
    var sum = 0.0f64
    var i = 0usize
    while i < x.len {
        if x[i] < lo || x[i] > hi {
            cnt += 1usize
            sum += x[i]
        }
        i += 1usize
    }
    ret (cnt, sum, ok)
}

// DescTools Outlier(x, method = "hampel"): the values outside the open interval median +/- 3 mad, with mad = 1.4826 * median(|x - median|).
// Returns how many and their sum.
fn outlier_hampel(a: *mem.Arena, x: []const f64) -> (usize, f64, err) {
    let (s, e) = sorted_copy(a, x)
    if e != ok { ret (0usize, 0.0f64, e) }
    if s.len == 0usize { ret (0usize, 0.0f64, ok) }
    let med = median_sorted(s)
    let (dev, e2) = mem.alloc[f64](a, x.len)
    if e2 != ok { ret (0usize, 0.0f64, e2) }
    var i = 0usize
    while i < x.len {
        dev[i] = math.abs[f64](x[i] - med)
        i += 1usize
    }
    let (ds, e3) = sorted_copy(a, dev)
    if e3 != ok { ret (0usize, 0.0f64, e3) }
    let mad = 1.4826f64 * median_sorted(ds)
    let lo = med - 3.0f64 * mad
    let hi = med + 3.0f64 * mad
    var cnt = 0usize
    var sum = 0.0f64
    i = 0usize
    while i < x.len {
        if x[i] <= lo || x[i] >= hi {
            cnt += 1usize
            sum += x[i]
        }
        i += 1usize
    }
    ret (cnt, sum, ok)
}

// ---- CCC (Lin's concordance correlation coefficient with the z-transform or asymptotic limits) and CronbachAlpha
// ccc(x, y, conf, ci): out receives (estimate, lower, upper, s.shift, l.shift, C.b); ci 0 the z-transform interval, 1 the asymptotic one
fn ccc(x: []const f64, y: []const f64, conf: f64, ci: usize, out: []f64) {
    let k = f64(x.len)
    let zv = dist.qnorm(1.0f64 - (1.0f64 - conf) / 2.0f64, 0.0f64, 1.0f64, true, false)
    let yb = mean_of(y)
    let xb = mean_of(x)
    var vy = 0.0f64
    var vx = 0.0f64
    var cxy = 0.0f64
    var i = 0usize
    while i < x.len {
        vy += (y[i] - yb) * (y[i] - yb)
        vx += (x[i] - xb) * (x[i] - xb)
        cxy += (x[i] - xb) * (y[i] - yb)
        i += 1usize
    }
    let sy2 = vy / (k - 1.0f64) * (k - 1.0f64) / k
    let sx2 = vx / (k - 1.0f64) * (k - 1.0f64) / k
    let sd1 = math.sqrt[f64](vy / (k - 1.0f64))
    let sd2 = math.sqrt[f64](vx / (k - 1.0f64))
    let r = cxy / math.sqrt[f64](vx * vy)
    let sxy = r * math.sqrt[f64](sx2 * sy2)
    let p = 2.0f64 * sxy / (sx2 + sy2 + (yb - xb) * (yb - xb))
    let v = sd1 / sd2
    let u = (yb - xb) / math.pow[f64](sx2 * sy2, 0.25f64)
    let cb = p / r
    let sep = math.sqrt[f64](((1.0f64 - r * r) * p * p * (1.0f64 - p * p) / (r * r) + (2.0f64 * p * p * p * (1.0f64 - p) * u * u / r) - 0.5f64 * math.pow[f64](p, 4.0f64) * math.pow[f64](u, 4.0f64) / (r * r)) / (k - 2.0f64))
    var lo = p - zv * sep
    var up = p + zv * sep
    if ci == 0usize {
        let t = math.log[f64]((1.0f64 + p) / (1.0f64 - p)) / 2.0f64
        let set_ = sep / (1.0f64 - p * p)
        let llt = t - zv * set_
        let ult = t + zv * set_
        lo = (math.exp[f64](2.0f64 * llt) - 1.0f64) / (math.exp[f64](2.0f64 * llt) + 1.0f64)
        up = (math.exp[f64](2.0f64 * ult) - 1.0f64) / (math.exp[f64](2.0f64 * ult) + 1.0f64)
    }
    out[0usize] = p
    out[1usize] = lo
    out[2usize] = up
    out[3usize] = v
    out[4usize] = u
    out[5usize] = cb
}

// CronbachAlpha(x, conf.level): x is n rows by nc columns row-major; out receives (alpha, lower, upper) (the limits are NaN when conf is NaN). The interval takes
// N as the total number of cells, as the package does.
fn cronbach_alpha(a: *mem.Arena, x: []const f64, n: usize, nc: usize, conf: f64, out: []f64) -> err {
    let (rs, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    var sumvar = 0.0f64
    var j = 0usize
    while j < nc {
        var m = 0.0f64
        var i = 0usize
        while i < n {
            m += x[i * nc + j]
            i += 1usize
        }
        m = m / f64(n)
        var s = 0.0f64
        i = 0usize
        while i < n {
            s += (x[i * nc + j] - m) * (x[i * nc + j] - m)
            i += 1usize
        }
        sumvar += s / f64(n - 1usize)
        j += 1usize
    }
    var i = 0usize
    while i < n {
        var s = 0.0f64
        j = 0usize
        while j < nc {
            s += x[i * nc + j]
            j += 1usize
        }
        rs[i] = s
        i += 1usize
    }
    var m = 0.0f64
    i = 0usize
    while i < n {
        m += rs[i]
        i += 1usize
    }
    m = m / f64(n)
    var tv = 0.0f64
    i = 0usize
    while i < n {
        tv += (rs[i] - m) * (rs[i] - m)
        i += 1usize
    }
    let total = tv / f64(n - 1usize)
    let res = (total - sumvar) / total * (f64(nc) / f64(nc - 1usize))
    out[0usize] = res
    out[1usize] = 0.0f64 / 0.0f64
    out[2usize] = 0.0f64 / 0.0f64
    if conf == conf {
        let nn = f64(n * nc)
        out[1usize] = 1.0f64 - (1.0f64 - res) * nb.qf(1.0f64 - (1.0f64 - conf) / 2.0f64, nn - 1.0f64, f64(nc - 1usize) * (nn - 1.0f64), true, false)
        out[2usize] = 1.0f64 - (1.0f64 - res) * nb.qf((1.0f64 - conf) / 2.0f64, nn - 1.0f64, f64(nc - 1usize) * (nn - 1.0f64), true, false)
    }
    ret ok
}

// ---- MeanCI (classic, untrimmed: the t interval, or the normal one when the standard deviation is given), VarCI (classic chi-square and Bonett), MeanSE and Herfindahl
// mean_ci writes (mean, lower, upper); sd < 0 means the sample standard deviation
fn mean_ci(x: []const f64, sd: f64, conf: f64, out: []f64) {
    let n = f64(x.len)
    let m = mean_of(x)
    var a = 0.0f64
    if sd < 0.0f64 {
        a = nb.qt((1.0f64 - conf) / 2.0f64, n - 1.0f64, true, false) * sd_of(x) / math.sqrt[f64](n)
    } else {
        a = dist.qnorm((1.0f64 - conf) / 2.0f64, 0.0f64, 1.0f64, true, false) * sd / math.sqrt[f64](n)
    }
    out[0usize] = m
    out[1usize] = m + a
    out[2usize] = m - a
}

fn var_of(x: []const f64) -> f64 {
    let s = sd_of(x)
    ret s * s
}

// var_ci(x, conf, bonett, out): (variance, lower, upper)
fn var_ci(a: *mem.Arena, x: []const f64, conf: f64, bonett: bool, out: []f64) -> err {
    let n = f64(x.len)
    let v = var_of(x)
    out[0usize] = v
    if !bonett {
        let df = n - 1.0f64
        out[1usize] = df * v / nm.qchisq((1.0f64 - conf) / 2.0f64, df, false, false)
        out[2usize] = df * v / nm.qchisq((1.0f64 - conf) / 2.0f64, df, true, false)
        ret ok
    }
    let z = dist.qnorm(1.0f64 - (1.0f64 - conf) / 2.0f64, 0.0f64, 1.0f64, true, false)
    let cc = n / (n - z)
    let (s, e) = sorted_copy(a, x)
    if e != ok { ret e }
    let trim = 1.0f64 / (2.0f64 * math.sqrt[f64](n - 4.0f64))
    let lo = usize(math.floor[f64](n * trim)) + 1usize
    let hi = x.len + 1usize - lo
    var mtr = 0.0f64
    var i = lo
    while i <= hi {
        mtr += s[i - 1usize]
        i += 1usize
    }
    mtr = mtr / f64(hi - lo + 1usize)
    let m = mean_of(x)
    var s4 = 0.0f64
    var s2 = 0.0f64
    i = 0usize
    while i < x.len {
        s4 += math.pow[f64](x[i] - mtr, 4.0f64)
        s2 += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    let gam4 = n * s4 / (s2 * s2)
    let se = cc * math.sqrt[f64]((gam4 - (n - 3.0f64) / n) / (n - 1.0f64))
    out[1usize] = math.exp[f64](math.log[f64](cc * v) - z * se)
    out[2usize] = math.exp[f64](math.log[f64](cc * v) + z * se)
    ret ok
}

fn mean_se(x: []const f64) -> f64 { ret sd_of(x) / math.sqrt[f64](f64(x.len)) }

// Herfindahl(x, n, parameter): the shares of the expanded sample raised to parameter + 1, summed, to the power 1 / parameter
fn herfindahl(x: []const f64, cnt: []const f64, parameter: f64) -> f64 {
    var tot = 0.0f64
    var i = 0usize
    while i < x.len {
        tot += x[i] * cnt[i]
        i += 1usize
    }
    var s = 0.0f64
    i = 0usize
    while i < x.len {
        s += cnt[i] * math.pow[f64](x[i] / tot, parameter + 1.0f64)
        i += 1usize
    }
    ret math.pow[f64](s, 1.0f64 / parameter)
}

// MeanCI with trim > 0 (classic method): the trimmed mean, the winsorised variance (the values below the trn-th and above the (n - trn + 1)-th order statistic, trn =
// floor(trim n) + 1, replaced by them) over n - 2 (trn - 1) - 1 degrees of freedom, and the t interval; out receives (mean, lower, upper)
fn mean_ci_trim(a: *mem.Arena, x: []const f64, trim: f64, conf: f64, out: []f64) -> err {
    let n = x.len
    let (s, e) = sorted_copy(a, x)
    if e != ok { ret e }
    let trn = usize(math.floor[f64](trim * f64(n))) + 1usize
    var hi_idx = n - trn + 1usize
    if hi_idx < 1usize { hi_idx = 1usize }
    let minval = s[trn - 1usize]
    let maxval = s[hi_idx - 1usize]
    let (w, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret e2 }
    var i = 0usize
    while i < n {
        var v = x[i]
        if v < minval { v = minval }
        if v > maxval { v = maxval }
        w[i] = v
        i += 1usize
    }
    let wv = var_of(w)
    let df = f64(n) - 2.0f64 * f64(trn - 1usize) - 1.0f64
    let se = math.sqrt[f64](wv) / ((1.0f64 - 2.0f64 * trim) * math.sqrt[f64](f64(n)))
    // R's mean(x, trim): the mean of the order statistics lo..hi, lo = floor(n trim) + 1
    let lo = usize(math.floor[f64](f64(n) * trim)) + 1usize
    let hi = n + 1usize - lo
    var m = 0.0f64
    i = lo
    while i <= hi {
        m += s[i - 1usize]
        i += 1usize
    }
    m = m / f64(hi - lo + 1usize)
    let q = nb.qt(1.0f64 - (1.0f64 - conf) / 2.0f64, df, true, false)
    out[0usize] = m
    out[1usize] = m - q * se
    out[2usize] = m + q * se
    ret ok
}

// CohenD(x) (one sample: mean / sd) and CohenD(x, y, pooled, correct) (two samples; the pooled or total standard deviation, optionally the small-sample correction
// 1 - 3 / (4 (nx + ny) - 9)); the confidence interval (a non-central t search) is not ported
fn cohen_d1(x: []const f64) -> f64 { ret mean_of(x) / sd_of(x) }

fn cohen_d2(a: *mem.Arena, x: []const f64, y: []const f64, pooled: bool, correct: bool) -> f64 {
    let nx = f64(x.len)
    let ny = f64(y.len)
    var d = mean_of(x) - mean_of(y)
    if pooled {
        d = d / math.sqrt[f64](((nx - 1.0f64) * var_of(x) + (ny - 1.0f64) * var_of(y)) / (nx + ny - 2.0f64))
    } else {
        let (c, e) = mem.alloc[f64](a, x.len + y.len)
        if e != ok { ret 0.0f64 / 0.0f64 }
        var i = 0usize
        while i < x.len {
            c[i] = x[i]
            i += 1usize
        }
        i = 0usize
        while i < y.len {
            c[x.len + i] = y[i]
            i += 1usize
        }
        d = d / sd_of(c)
    }
    if correct { d = d * (1.0f64 - 3.0f64 / (4.0f64 * (nx + ny) - 9.0f64)) }
    ret d
}
