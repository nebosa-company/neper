// R rcompanion effect sizes (without the bootstrap intervals): epsilon-squared (the Kruskal-Wallis statistic over n - 1), Freeman's
// theta, Cliff's delta and the vargha-delaney A (`vda`), Cramer's V (with the bias correction) and Cohen's w for a contingency table.
// Every one is rounded with `signif` to the digits the package uses (3 for the rank statistics, 4 for V and w), as R returns it.
//
// Not here: the bootstrap intervals, scheirerRayHare, the pairwise median test and the nominal symmetry and independence helpers.

use e.math
use e.math.nmath as nm
use e.algo.linalg.decomp as decomp
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

// signif(x, digits)
fn signif(x: f64, digits: i64) -> f64 {
    if x == 0.0f64 || x != x { ret x }
    var ax = x
    if ax < 0.0f64 { ax = 0.0f64 - ax }
    let e = math.floor[f64]((math.log[f64](ax) / 2.302585092994046f64))
    let p = f64(digits - 1i64) - e
    let sc = math.pow[f64](10.0f64, p)
    var r = math.round[f64](x * sc) / sc
    if p < 0.0f64 {
        let sc2 = math.pow[f64](10.0f64, 0.0f64 - p)
        r = math.round[f64](x / sc2) * sc2
    }
    ret r
}

// the average ranks of x
fn ranks(a: *mem.Arena, x: []const f64) -> ([]f64, err) {
    let n = x.len
    let (r, e) = mem.alloc[f64](a, n)
    if e != ok { ret (r, e) }
    var i = 0usize
    while i < n {
        var less = 0.0f64
        var eq = 0.0f64
        var j = 0usize
        while j < n {
            if x[j] < x[i] { less += 1.0f64 }
            if x[j] == x[i] { eq += 1.0f64 }
            j += 1usize
        }
        r[i] = less + (eq + 1.0f64) / 2.0f64
        i += 1usize
    }
    ret (r, ok)
}

// the Kruskal-Wallis statistic of x by the integer groups g (0-based, k groups)
fn kruskal_stat(a: *mem.Arena, x: []const f64, g: []const usize, k: usize) -> f64 {
    let n = x.len
    let (r, e) = ranks(a, x)
    let (rs, e2) = mem.alloc[f64](a, k)
    let (ns, e3) = mem.alloc[f64](a, k)
    if e != ok || e2 != ok || e3 != ok { ret nan() }
    var j = 0usize
    while j < k {
        rs[j] = 0.0f64
        ns[j] = 0.0f64
        j += 1usize
    }
    var i = 0usize
    while i < n {
        rs[g[i]] += r[i]
        ns[g[i]] += 1.0f64
        i += 1usize
    }
    let nf = f64(n)
    var s = 0.0f64
    j = 0usize
    while j < k {
        s += rs[j] * rs[j] / ns[j]
        j += 1usize
    }
    var stat = 12.0f64 * s / (nf * (nf + 1.0f64)) - 3.0f64 * (nf + 1.0f64)
    // tie correction: 1 - sum(t^3 - t) / (n^3 - n)
    var ties = 0.0f64
    i = 0usize
    while i < n {
        var cnt = 0.0f64
        var first = true
        var q = 0usize
        while q < n {
            if x[q] == x[i] {
                cnt += 1.0f64
                if q < i { first = false }
            }
            q += 1usize
        }
        if first { ties += cnt * cnt * cnt - cnt }
        i += 1usize
    }
    stat = stat / (1.0f64 - ties / (nf * nf * nf - nf))
    ret stat
}

// epsilonSquared(x, g): kruskal.test statistic / (n - 1), signif 3
fn epsilon_squared(a: *mem.Arena, x: []const f64, g: []const usize, k: usize) -> f64 {
    ret signif(kruskal_stat(a, x, g, k) / f64(x.len - 1usize), 3i64)
}

// freemanTheta(x, g): the sum over pairs of groups of |#(Y1 > Y2) - #(Y1 < Y2)| over the sum of n1 n2 (groups in level order), signif 3
fn freeman_theta(x: []const f64, g: []const usize, k: usize) -> f64 {
    var delta = 0.0f64
    var tee = 0.0f64
    var i = 0usize
    while i + 1usize < k {
        var j = i + 1usize
        while j < k {
            var d = 0.0f64
            var n1 = 0.0f64
            var n2 = 0.0f64
            var l = 0usize
            while l < x.len {
                if g[l] == i {
                    n1 += 1.0f64
                    var m = 0usize
                    while m < x.len {
                        if g[m] == j {
                            if x[l] > x[m] { d += 1.0f64 }
                            if x[l] < x[m] { d -= 1.0f64 }
                        }
                        m += 1usize
                    }
                } else if g[l] == j {
                    n2 += 1.0f64
                }
                l += 1usize
            }
            if d < 0.0f64 { d = 0.0f64 - d }
            delta += d
            tee += n1 * n2
            j += 1usize
        }
        i += 1usize
    }
    ret signif(delta / tee, 3i64)
}

// vda: the proportion of pairs with A above B, ties counting one half (the Wilcoxon U over n1 n2)
fn vda_raw(x: []const f64, y: []const f64) -> f64 {
    var u = 0.0f64
    var i = 0usize
    while i < x.len {
        var j = 0usize
        while j < y.len {
            if x[i] > y[j] { u += 1.0f64 }
            if x[i] == y[j] { u += 0.5f64 }
            j += 1usize
        }
        i += 1usize
    }
    ret u / (f64(x.len) * f64(y.len))
}

fn vda(x: []const f64, y: []const f64) -> f64 { ret signif(vda_raw(x, y), 3i64) }

fn cliff_delta(x: []const f64, y: []const f64) -> f64 { ret signif((vda_raw(x, y) - 0.5f64) * 2.0f64, 3i64) }

// the chi-squared statistic (no continuity correction) of an r by c table, row-major, and the total
fn chisq_table(t: []const f64, r: usize, c: usize) -> (f64, f64) {
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
            var q = 0usize
            while q < r {
                cs += t[q * c + j]
                q += 1usize
            }
            let e = rs * cs / n
            chi += (t[i * c + j] - e) * (t[i * c + j] - e) / e
            j += 1usize
        }
        i += 1usize
    }
    ret (chi, n)
}

// cramerV(table, bias.correct): V = sqrt(phi / min(r - 1, c - 1)), signif 4
fn cramer_v(t: []const f64, r: usize, c: usize, bias: bool) -> f64 {
    let (chi, n) = chisq_table(t, r, c)
    var phi = chi / n
    let rf = f64(r)
    let cf = f64(c)
    if bias {
        phi = phi - (rf - 1.0f64) * (cf - 1.0f64) / (n - 1.0f64)
        if phi < 0.0f64 { phi = 0.0f64 }
        let cc = cf - (cf - 1.0f64) * (cf - 1.0f64) / (n - 1.0f64)
        let rr = rf - (rf - 1.0f64) * (rf - 1.0f64) / (n - 1.0f64)
        var m = rr - 1.0f64
        if cc - 1.0f64 < m { m = cc - 1.0f64 }
        ret signif(math.sqrt[f64](phi / m), 4i64)
    }
    var m = rf - 1.0f64
    if cf - 1.0f64 < m { m = cf - 1.0f64 }
    ret signif(math.sqrt[f64](phi / m), 4i64)
}

// cohenW(table): sqrt(sum((obs - exp)^2 / exp)) on the proportions, signif 4
fn cohen_w(t: []const f64, r: usize, c: usize) -> f64 {
    var n = 0.0f64
    var i = 0usize
    while i < r * c {
        n += t[i]
        i += 1usize
    }
    var s = 0.0f64
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
            var q = 0usize
            while q < r {
                cs += t[q * c + j]
                q += 1usize
            }
            let e = rs * cs / n / n
            let o = t[i * c + j] / n
            s += (o - e) * (o - e) / e
            j += 1usize
        }
        i += 1usize
    }
    ret signif(math.sqrt[f64](s), 4i64)
}

// the dummy-coded design of the intercept, first factor, second factor and their interaction (n rows, column-major), treatment contrasts; returns the column count
fn srh_design(x: []f64, g1: []const usize, l1: usize, g2: []const usize, l2: usize, n: usize) -> usize {
    var col = 0usize
    var i = 0usize
    while i < n {
        x[i] = 1.0f64
        i += 1usize
    }
    col = 1usize
    var a = 1usize
    while a < l1 {
        i = 0usize
        while i < n {
            if g1[i] == a { x[col * n + i] = 1.0f64 } else { x[col * n + i] = 0.0f64 }
            i += 1usize
        }
        col += 1usize
        a += 1usize
    }
    var b = 1usize
    while b < l2 {
        i = 0usize
        while i < n {
            if g2[i] == b { x[col * n + i] = 1.0f64 } else { x[col * n + i] = 0.0f64 }
            i += 1usize
        }
        col += 1usize
        b += 1usize
    }
    a = 1usize
    while a < l1 {
        b = 1usize
        while b < l2 {
            i = 0usize
            while i < n {
                if g1[i] == a && g2[i] == b { x[col * n + i] = 1.0f64 } else { x[col * n + i] = 0.0f64 }
                i += 1usize
            }
            col += 1usize
            b += 1usize
        }
        a += 1usize
    }
    ret col
}

// scheirerRayHare(y ~ x1 + x2, type = 2): out[0..3] the tie-adjusted H of x1, x2 and x1:x2, out[3..6] their chi-square p values; g1, g2 are factor codes 0 .. l - 1
fn scheirer_ray_hare(a: *mem.Arena, y: []const f64, g1: []const usize, l1: usize, g2: []const usize, l2: usize, out: []f64) -> err {
    let n = y.len
    let (r, re) = ranks(a, y)
    if re != ok { ret re }
    let (xm, e1) = mem.alloc[f64](a, n * (l1 * l2 + 1usize))
    if e1 != ok { ret e1 }
    let p = srh_design(xm, g1, l1, g2, l2, n)
    let (f1, fe1) = decomp.lm_fit(a, xm[0usize..n * p], n, p, r, 1.0e-7f64)
    if fe1 != ok { ret fe1 }
    let ss12 = sumsq_range(f1.effects, 1usize + (l1 - 1usize) + (l2 - 1usize), p)
    let ss2 = sumsq_range(f1.effects, 1usize + (l1 - 1usize), 1usize + (l1 - 1usize) + (l2 - 1usize))
    // the other order: x2 first, then x1 (the interaction column set is the same space)
    let p2 = srh_design(xm, g2, l2, g1, l1, n)
    let (f2, fe2) = decomp.lm_fit(a, xm[0usize..n * p2], n, p2, r, 1.0e-7f64)
    if fe2 != ok { ret fe2 }
    let ss1 = sumsq_range(f2.effects, 1usize + (l2 - 1usize), 1usize + (l2 - 1usize) + (l1 - 1usize))
    // the tie correction
    var tsum = 0.0f64
    var i = 0usize
    while i < n {
        var cnt = 0.0f64
        var first = true
        var j = 0usize
        while j < n {
            if r[j] == r[i] {
                cnt += 1.0f64
                if j < i { first = false }
            }
            j += 1usize
        }
        if first { tsum += cnt * cnt * cnt - cnt }
        i += 1usize
    }
    let nn = f64(n)
    let d = 1.0f64 - tsum / (nn * nn * nn - nn)
    let ms = nn * (nn + 1.0f64) / 12.0f64
    let h1 = ss1 / ms / d
    let h2 = ss2 / ms / d
    let h12 = ss12 / ms / d
    out[0usize] = h1
    out[1usize] = h2
    out[2usize] = h12
    out[3usize] = 1.0f64 - nm.pchisq(h1, f64(l1 - 1usize), true, false)
    out[4usize] = 1.0f64 - nm.pchisq(h2, f64(l2 - 1usize), true, false)
    out[5usize] = 1.0f64 - nm.pchisq(h12, f64((l1 - 1usize) * (l2 - 1usize)), true, false)
    ret ok
}

fn sumsq_range(v: []const f64, lo: usize, hi: usize) -> f64 {
    var s = 0.0f64
    var i = lo
    while i < hi {
        s += v[i] * v[i]
        i += 1usize
    }
    ret s
}

// nominalSymmetryTest(x)$Global.test.for.symmetry: the McNemar test of a 2 by 2 table (continuity corrected) or Bowker's symmetry test of a square table, the p value to three significant digits; x is n by n row-major
fn nominal_symmetry_p(x: []const f64, n: usize) -> f64 {
    var st = 0.0f64
    var i = 0usize
    while i < n {
        var j = i + 1usize
        while j < n {
            let u = x[i * n + j]
            let l = x[j * n + i]
            if n == 2usize {
                var d = math.abs[f64](u - l)
                if u != l { d = d - 1.0f64 }
                st += d * d / (u + l)
            } else {
                st += (u - l) * (u - l) / (u + l)
            }
            j += 1usize
        }
        i += 1usize
    }
    let df = f64(n * (n - 1usize) / 2usize)
    ret signif(1.0f64 - nm.pchisq(st, df, true, false), 3i64)
}
