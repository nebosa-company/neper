// R rcompanion effect sizes (without the bootstrap intervals): epsilon-squared (the Kruskal-Wallis statistic over n - 1), Freeman's
// theta, Cliff's delta and the vargha-delaney A (`vda`), Cramer's V (with the bias correction) and Cohen's w for a contingency table.
// Every one is rounded with `signif` to the digits the package uses (3 for the rank statistics, 4 for V and w), as R returns it.
//
// Not here: the bootstrap intervals, scheirerRayHare, the pairwise median test and the nominal symmetry and independence helpers.

use e.math
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
