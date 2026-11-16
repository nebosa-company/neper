// R polynom (coefficients ascending): predict (Horner), deriv, integral (zero constant), poly.calc (the monic polynomial with the given roots) and poly.orth (the orthonormal
// polynomials on a set of points under the unweighted discrete inner product); and caTools colAUC for two classes.
//
// Not here: solve and the complex roots, the arithmetic operators on polynomial objects, lists of polynomials, and colAUC with more than two classes or the ROC plot.

use e.math

fn predict(c: []const f64, x: f64) -> f64 {
    var v = 0.0f64
    var i = c.len
    while i > 0usize {
        i -= 1usize
        v = v * x + c[i]
    }
    ret v
}

// the coefficients of the derivative (c.len - 1 values) into out
fn deriv(c: []const f64, out: []f64) {
    var i = 1usize
    while i < c.len {
        out[i - 1usize] = c[i] * f64(i)
        i += 1usize
    }
}

// the coefficients of the antiderivative with a zero constant term (c.len + 1 values) into out
fn integral(c: []const f64, out: []f64) {
    out[0usize] = 0.0f64
    var i = 0usize
    while i < c.len {
        out[i + 1usize] = c[i] / f64(i + 1usize)
        i += 1usize
    }
}

// poly.calc(roots): the monic polynomial prod (x - r_i), ascending, into out (roots.len + 1 values)
fn poly_calc(roots: []const f64, out: []f64) {
    out[0usize] = 1.0f64
    var k = 0usize
    while k < roots.len {
        var i = k + 1usize
        out[i] = out[i - 1usize]
        while i > 1usize {
            i -= 1usize
            out[i] = out[i - 1usize] - roots[k] * out[i]
        }
        out[0usize] = 0.0f64 - roots[k] * out[0usize]
        k += 1usize
    }
}

// inner product of two polynomials over the points
fn inner(p: []const f64, q: []const f64, pts: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < pts.len {
        s += predict(p, pts[i]) * predict(q, pts[i])
        i += 1usize
    }
    ret s
}

// poly.orth(pts, degree): the coefficients of orthonormal polynomial `which` (0 .. degree, ascending) by the three-term recurrence; work holds 4 * (degree + 2) values
fn poly_orth(pts: []const f64, degree: usize, which: usize, out: []f64, work: []f64) {
    let w = degree + 2usize
    let prev = work[0usize..w]
    let cur = work[w..2usize * w]
    let nxt = work[2usize * w..3usize * w]
    let xc = work[3usize * w..4usize * w]
    var i = 0usize
    while i < 4usize * w {
        work[i] = 0.0f64
        i += 1usize
    }
    cur[0usize] = 1.0f64
    var k = 0usize
    var prev_norm2 = 1.0f64
    while true {
        let n2 = inner(cur, cur, pts)
        if k == which {
            let nrm = math.sqrt[f64](n2)
            i = 0usize
            while i <= degree {
                out[i] = cur[i] / nrm
                i += 1usize
            }
            ret
        }
        xc[0usize] = 0.0f64
        i = 0usize
        while i + 1usize < w {
            xc[i + 1usize] = cur[i]
            i += 1usize
        }
        let alpha = inner(xc, cur, pts) / n2
        var beta = 0.0f64
        if k > 0usize { beta = n2 / prev_norm2 }
        i = 0usize
        while i < w {
            nxt[i] = xc[i] - alpha * cur[i] - beta * prev[i]
            i += 1usize
        }
        i = 0usize
        while i < w {
            prev[i] = cur[i]
            cur[i] = nxt[i]
            i += 1usize
        }
        prev_norm2 = n2
        k += 1usize
    }
}

// colAUC(x, y) for two classes (y is 0 or 1): the area under the ROC curve with ties counted half, as max(auc, 1 - auc)
fn col_auc(x: []const f64, y: []const f64) -> f64 {
    var wins = 0.0f64
    var n1 = 0.0f64
    var n0 = 0.0f64
    var i = 0usize
    while i < x.len {
        if y[i] == 1.0f64 { n1 += 1.0f64 } else { n0 += 1.0f64 }
        i += 1usize
    }
    i = 0usize
    while i < x.len {
        if y[i] == 1.0f64 {
            var j = 0usize
            while j < x.len {
                if y[j] != 1.0f64 {
                    if x[i] > x[j] { wins += 1.0f64 } else if x[i] == x[j] { wins += 0.5f64 }
                }
                j += 1usize
            }
        }
        i += 1usize
    }
    let auc = wins / (n1 * n0)
    if 1.0f64 - auc > auc { ret 1.0f64 - auc }
    ret auc
}
