// R polynom (coefficients ascending): predict (Horner), deriv, integral (zero constant), poly.calc (the monic polynomial with the given roots) and poly.orth (the orthonormal
// polynomials on a set of points under the unweighted discrete inner product); and caTools colAUC for two classes.
//
// Not here: the arithmetic operators on polynomial objects, lists of polynomials, and colAUC with more than two classes or the ROC plot.

use e.math
use e.mem
use e.algo.stat.pracma as pr

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

// solve(p): the zeros of the polynomial (ascending coefficients), sorted by real then imaginary part as R sorts a complex vector, zeros at the origin first when present; returns the count written to re and im, or -1 when the finder fails
fn solve(a: *mem.Arena, c: []const f64, re: []f64, im: []f64) -> i64 {
    var z = 0usize
    while z < c.len && c[z] == 0.0f64 { z += 1usize }
    var n = 0usize
    while n < z {
        re[n] = 0.0f64
        im[n] = 0.0f64
        n += 1usize
    }
    if c.len < z + 2usize { ret i64(n) }
    let rest = c[z..c.len]
    if rest.len == 2usize {
        re[n] = 0.0f64 - rest[0usize] / rest[1usize]
        im[n] = 0.0f64
        n += 1usize
    } else {
        let d = pr.polyroot_c(a, rest, re[n..re.len], im[n..im.len])
        if d < 0i64 { ret 0i64 - 1i64 }
        n += usize(d)
    }
    var i = 1usize
    while i < n {
        let r0 = re[i]
        let i0 = im[i]
        var j = i
        while j > 0usize && (re[j - 1usize] > r0 || (re[j - 1usize] == r0 && im[j - 1usize] > i0)) {
            re[j] = re[j - 1usize]
            im[j] = im[j - 1usize]
            j -= 1usize
        }
        re[j] = r0
        im[j] = i0
        i += 1usize
    }
    ret i64(n)
}
