// R DescTools: Skew and Kurt (methods 1, 2 and 3, the moment, sample-adjusted and Minitab-style forms), Gini (unbiased or not), MeanAD about the mean, Gmean,
// Hmean, Entropy (Shannon, base 2, of the values as frequencies) and CoefVar.
//
// Not here: the rest of the package (Winsorize, Mode, the association measures, tests and confidence intervals).

use e.math
use e.mem

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
