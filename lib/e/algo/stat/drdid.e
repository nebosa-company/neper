// R DRDID: reg_did_panel, the outcome-regression difference-in-differences estimator on panel data, its ATT and analytic standard error from the influence function.
//
// Not here: the inverse-propensity and doubly robust estimators, repeated cross-sections, bootstrap inference and the improved estimators.

use e.algo.stat.carlmtest as ols
use e.math
use e.mem

// reg_did_panel(y1, y0, D, covariates)$ATT (part 0) and $se (part 1); x is n by p row-major and includes the intercept column the caller wants
fn reg_did_panel(a: *mem.Arena, dy: []const f64, d: []const f64, x: []const f64, n: usize, p: usize, part: usize) -> f64 {
    // the control rows
    var nc = 0usize
    var i = 0usize
    while i < n {
        if d[i] == 0.0f64 { nc += 1usize }
        i += 1usize
    }
    let (xc, e1) = mem.alloc[f64](a, nc * p)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let (yc, e2) = mem.alloc[f64](a, nc)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    var r = 0usize
    i = 0usize
    while i < n {
        if d[i] == 0.0f64 {
            var j = 0usize
            while j < p {
                xc[r * p + j] = x[i * p + j]
                j += 1usize
            }
            yc[r] = dy[i]
            r += 1usize
        }
        i += 1usize
    }
    let (f, e3) = ols.ols(a, xc, yc, nc, p)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    let nf = f64(n)
    // out.delta, the fitted control change at every unit
    let (od, e4) = mem.alloc[f64](a, n)
    if e4 != ok { ret 0.0f64 / 0.0f64 }
    var wt = 0.0f64
    var treat = 0.0f64
    var cont = 0.0f64
    i = 0usize
    while i < n {
        var v = 0.0f64
        var j = 0usize
        while j < p {
            v += f.beta[j] * x[i * p + j]
            j += 1usize
        }
        od[i] = v
        wt += d[i]
        treat += d[i] * dy[i]
        cont += d[i] * v
        i += 1usize
    }
    let mw = wt / nf
    let eta_t = (treat / nf) / mw
    let eta_c = (cont / nf) / mw
    let att = eta_t - eta_c
    if part == 0usize { ret att }
    // the influence function
    let (xtx, e5) = mem.alloc[f64](a, p * p)
    if e5 != ok { ret 0.0f64 / 0.0f64 }
    var u = 0usize
    while u < p {
        var v = 0usize
        while v < p {
            var s = 0.0f64
            i = 0usize
            while i < n {
                if d[i] == 0.0f64 { s += x[i * p + u] * x[i * p + v] }
                i += 1usize
            }
            xtx[u * p + v] = s / nf
            v += 1usize
        }
        u += 1usize
    }
    let (inv, e6) = mem.alloc[f64](a, p * p)
    if e6 != ok { ret 0.0f64 / 0.0f64 }
    if ols.inverse(a, xtx, p, inv) != ok { ret 0.0f64 / 0.0f64 }
    // M1 = mean over units of w.cont * x
    let (m1, e7) = mem.alloc[f64](a, p)
    if e7 != ok { ret 0.0f64 / 0.0f64 }
    u = 0usize
    while u < p {
        var s = 0.0f64
        i = 0usize
        while i < n {
            s += d[i] * x[i * p + u]
            i += 1usize
        }
        m1[u] = s / nf
        u += 1usize
    }
    let (inf, e8) = mem.alloc[f64](a, n)
    if e8 != ok { ret 0.0f64 / 0.0f64 }
    var sum = 0.0f64
    i = 0usize
    while i < n {
        let inf_t = (d[i] * dy[i] - d[i] * eta_t) / mw
        let inf_c1 = d[i] * od[i] - d[i] * eta_c
        // asy.lin.rep.ols row: w.ols * (dy - out.delta) * x_i %*% XpX^-1, then times M1
        var inf_c2 = 0.0f64
        if d[i] == 0.0f64 {
            let res = dy[i] - od[i]
            u = 0usize
            while u < p {
                var rowv = 0.0f64
                var v = 0usize
                while v < p {
                    rowv += res * x[i * p + v] * inv[v * p + u]
                    v += 1usize
                }
                inf_c2 += rowv * m1[u]
                u += 1usize
            }
        }
        let ic = (inf_c1 + inf_c2) / mw
        inf[i] = inf_t - ic
        sum += inf[i]
        i += 1usize
    }
    let mean = sum / nf
    var ss = 0.0f64
    i = 0usize
    while i < n {
        ss += (inf[i] - mean) * (inf[i] - mean)
        i += 1usize
    }
    let sd = math.sqrt[f64](ss / (nf - 1.0f64))
    ret sd * math.sqrt[f64](nf - 1.0f64) / nf
}
