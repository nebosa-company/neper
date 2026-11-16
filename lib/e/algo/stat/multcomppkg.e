// R multcomp glht on a linear model: the estimates K b, standard errors, t statistics and the unadjusted, Bonferroni and Holm p values (t distribution, residual degrees of freedom) of a contrast matrix K (m by p) for y on the columns of x (n by p, row-major, constant included).
//
// Not here: the single-step and free adjustments that integrate the multivariate t (Tukey, Dunnett, the default single-step), Westfall, simultaneous confidence intervals, mixed and glm models.

use e.algo.stat.gparot as gp
use e.math
use e.math.nmath_beta as nb
use e.mem

// out layout per contrast c: est[c], se[c], t[c], p[c], p_bonf[c], p_holm[c] at out[k * m + c] for k = 0 .. 5
fn glht(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, k: []const f64, m: usize, out: []f64) -> err {
    let (g, e1) = mem.alloc[f64](a, p * p)
    let (r, e2) = mem.alloc[f64](a, p)
    let (b, e3) = mem.alloc[f64](a, p)
    let (ord, e4) = mem.alloc[usize](a, m)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    var i = 0usize
    while i < p * p {
        g[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < p {
        r[i] = 0.0f64
        i += 1usize
    }
    var t = 0usize
    while t < n {
        i = 0usize
        while i < p {
            r[i] += x[t * p + i] * y[t]
            var j = 0usize
            while j < p {
                g[i * p + j] += x[t * p + i] * x[t * p + j]
                j += 1usize
            }
            i += 1usize
        }
        t += 1usize
    }
    let (gi, ge) = gp.invert(a, g, p)
    if ge != ok { ret ge }
    i = 0usize
    while i < p {
        var s = 0.0f64
        var j = 0usize
        while j < p {
            s += gi[i * p + j] * r[j]
            j += 1usize
        }
        b[i] = s
        i += 1usize
    }
    var rss = 0.0f64
    t = 0usize
    while t < n {
        var f = 0.0f64
        i = 0usize
        while i < p {
            f += x[t * p + i] * b[i]
            i += 1usize
        }
        rss += (y[t] - f) * (y[t] - f)
        t += 1usize
    }
    let df = f64(n - p)
    let s2 = rss / df
    var c = 0usize
    while c < m {
        var est = 0.0f64
        var v = 0.0f64
        i = 0usize
        while i < p {
            est += k[c * p + i] * b[i]
            var j = 0usize
            while j < p {
                v += k[c * p + i] * gi[i * p + j] * k[c * p + j]
                j += 1usize
            }
            i += 1usize
        }
        let se = math.sqrt[f64](s2 * v)
        let tv = est / se
        out[c] = est
        out[m + c] = se
        out[2usize * m + c] = tv
        out[3usize * m + c] = 2.0f64 * nb.pt(0.0f64 - math.abs[f64](tv), df, true, false)
        var bf = out[3usize * m + c] * f64(m)
        if bf > 1.0f64 { bf = 1.0f64 }
        out[4usize * m + c] = bf
        ord[c] = c
        c += 1usize
    }
    // Holm: sort the raw p ascending, multiply by (m - rank), cumulative maximum, cap at 1
    i = 1usize
    while i < m {
        let v = ord[i]
        var j = i
        while j > 0usize && out[3usize * m + ord[j - 1usize]] > out[3usize * m + v] {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = v
        i += 1usize
    }
    var run = 0.0f64
    i = 0usize
    while i < m {
        var h = out[3usize * m + ord[i]] * f64(m - i)
        if h > 1.0f64 { h = 1.0f64 }
        if h > run { run = h }
        out[5usize * m + ord[i]] = run
        i += 1usize
    }
    ret ok
}
