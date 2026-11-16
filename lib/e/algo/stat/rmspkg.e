// R rms: the restricted cubic spline basis (rcspline.eval with norm 2 and explicit knots), ols (coefficients, standard errors, R2, sigma) and the unpenalised binary lrm (coefficients, likelihood-ratio chi-square, C index, Dxy, Nagelkerke R2, Brier score).
//
// Not here: datadist knot placement, penalised and ordinal lrm, cph and psm, validate and calibrate, anova and Predict, robust covariance.

use e.algo.stat.gparot as gp
use e.math
use e.mem

// rcspline.eval: row r of out (n by nk - 1) holds x then the nk - 2 non-linear terms
fn rcs(x: []const f64, knots: []const f64, out: []f64) {
    let k = knots.len
    let w = k - 1usize
    let norm = (knots[k - 1usize] - knots[0usize]) * (knots[k - 1usize] - knots[0usize])
    let tk = knots[k - 1usize]
    let tk1 = knots[k - 2usize]
    var i = 0usize
    while i < x.len {
        out[i * w] = x[i]
        var j = 0usize
        while j + 2usize < k {
            let a = pos3(x[i] - knots[j])
            let b = pos3(x[i] - tk1) * (tk - knots[j]) / (tk - tk1)
            let c = pos3(x[i] - tk) * (tk1 - knots[j]) / (tk - tk1)
            out[i * w + 1usize + j] = (a - b + c) / norm
            j += 1usize
        }
        i += 1usize
    }
}

fn pos3(v: f64) -> f64 {
    if v > 0.0f64 { ret v * v * v }
    ret 0.0f64
}

// ols with a constant added: out = coef (p + 1), se (p + 1), R2, sigma; x is n by p row-major
fn ols(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, out: []f64) -> err {
    let q = p + 1usize
    let (g, e1) = mem.alloc[f64](a, q * q)
    let (r, e2) = mem.alloc[f64](a, q)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    var i = 0usize
    while i < q * q {
        g[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < q {
        r[i] = 0.0f64
        i += 1usize
    }
    var t = 0usize
    while t < n {
        i = 0usize
        while i < q {
            var xi = 1.0f64
            if i > 0usize { xi = x[t * p + i - 1usize] }
            r[i] += xi * y[t]
            var j = 0usize
            while j < q {
                var xj = 1.0f64
                if j > 0usize { xj = x[t * p + j - 1usize] }
                g[i * q + j] += xi * xj
                j += 1usize
            }
            i += 1usize
        }
        t += 1usize
    }
    let (gi, ge) = gp.invert(a, g, q)
    if ge != ok { ret ge }
    i = 0usize
    while i < q {
        var s = 0.0f64
        var j = 0usize
        while j < q {
            s += gi[i * q + j] * r[j]
            j += 1usize
        }
        out[i] = s
        i += 1usize
    }
    var rss = 0.0f64
    var ym = 0.0f64
    t = 0usize
    while t < n {
        ym += y[t] / f64(n)
        t += 1usize
    }
    var tss = 0.0f64
    t = 0usize
    while t < n {
        var f = out[0usize]
        i = 1usize
        while i < q {
            f += out[i] * x[t * p + i - 1usize]
            i += 1usize
        }
        rss += (y[t] - f) * (y[t] - f)
        tss += (y[t] - ym) * (y[t] - ym)
        t += 1usize
    }
    let s2 = rss / f64(n - q)
    i = 0usize
    while i < q {
        out[q + i] = math.sqrt[f64](s2 * gi[i * q + i])
        i += 1usize
    }
    out[2usize * q] = 1.0f64 - rss / tss
    out[2usize * q + 1usize] = math.sqrt[f64](s2)
    ret ok
}

// binary lrm by Newton: out = coef (p + 1, constant first), LR chi-square, C, Dxy, Nagelkerke R2, Brier
fn lrm(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, out: []f64) -> err {
    let q = p + 1usize
    let (b, e1) = mem.alloc[f64](a, q)
    let (gr, e2) = mem.alloc[f64](a, q)
    let (h, e3) = mem.alloc[f64](a, q * q)
    let (pr, e4) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    var i = 0usize
    while i < q {
        b[i] = 0.0f64
        i += 1usize
    }
    var ll = 0.0f64
    var it = 0usize
    while it < 100usize {
        i = 0usize
        while i < q {
            gr[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < q * q {
            h[i] = 0.0f64
            i += 1usize
        }
        ll = 0.0f64
        var t = 0usize
        while t < n {
            var eta = b[0usize]
            i = 1usize
            while i < q {
                eta += b[i] * x[t * p + i - 1usize]
                i += 1usize
            }
            let pt = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - eta))
            pr[t] = pt
            if y[t] > 0.5f64 { ll += math.log[f64](pt) } else { ll += math.log[f64](1.0f64 - pt) }
            i = 0usize
            while i < q {
                var xi = 1.0f64
                if i > 0usize { xi = x[t * p + i - 1usize] }
                gr[i] += (y[t] - pt) * xi
                var j = 0usize
                while j < q {
                    var xj = 1.0f64
                    if j > 0usize { xj = x[t * p + j - 1usize] }
                    h[i * q + j] += pt * (1.0f64 - pt) * xi * xj
                    j += 1usize
                }
                i += 1usize
            }
            t += 1usize
        }
        let (inv, ie) = gp.invert(a, h, q)
        if ie != ok { ret ie }
        var step = 0.0f64
        i = 0usize
        while i < q {
            var d = 0.0f64
            var j = 0usize
            while j < q {
                d += inv[i * q + j] * gr[j]
                j += 1usize
            }
            b[i] += d
            if math.abs[f64](d) > step { step = math.abs[f64](d) }
            i += 1usize
        }
        it += 1usize
        if step < 1.0e-13f64 { break }
    }
    // likelihood at the final coefficients
    ll = 0.0f64
    var brier = 0.0f64
    var n1 = 0.0f64
    var t = 0usize
    while t < n {
        var eta = b[0usize]
        i = 1usize
        while i < q {
            eta += b[i] * x[t * p + i - 1usize]
            i += 1usize
        }
        let pt = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - eta))
        pr[t] = pt
        if y[t] > 0.5f64 {
            ll += math.log[f64](pt)
            n1 += 1.0f64
        } else {
            ll += math.log[f64](1.0f64 - pt)
        }
        brier += (pt - y[t]) * (pt - y[t]) / f64(n)
        t += 1usize
    }
    let nf = f64(n)
    let ll0 = n1 * math.log[f64](n1 / nf) + (nf - n1) * math.log[f64]((nf - n1) / nf)
    var conc = 0.0f64
    var pairs = 0.0f64
    var s = 0usize
    while s < n {
        if y[s] > 0.5f64 {
            var u = 0usize
            while u < n {
                if y[u] < 0.5f64 {
                    pairs += 1.0f64
                    if pr[s] > pr[u] { conc += 1.0f64 } else if pr[s] == pr[u] { conc += 0.5f64 }
                }
                u += 1usize
            }
        }
        s += 1usize
    }
    i = 0usize
    while i < q {
        out[i] = b[i]
        i += 1usize
    }
    let lr = 2.0f64 * (ll - ll0)
    out[q] = lr
    out[q + 1usize] = conc / pairs
    out[q + 2usize] = 2.0f64 * (conc / pairs - 0.5f64)
    out[q + 3usize] = (1.0f64 - math.exp[f64](0.0f64 - lr / nf)) / (1.0f64 - math.exp[f64](2.0f64 * ll0 / nf))
    out[q + 4usize] = brier
    ret ok
}
