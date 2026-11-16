// R fixest feols with one or two fixed effects: the slope coefficients by alternating-projection demeaning, with the IID, heteroskedasticity-robust (HC1) and clustered (by the first fixed effect) standard errors under fixest's default small-sample corrections.
//
// Not here: other clusters and multiway clustering, instrumental variables, fixed-effect estimates, GLM families, and the other ssc settings.

use e.algo.stat.gparot as gp
use e.math
use e.mem

fn find(par: []usize, v: usize) -> usize {
    var r = v
    while par[r] != r { r = par[r] }
    ret r
}

// out: coef (k), iid se (k), hetero se (k), cluster se (k); fe2 is ignored when g2 is 0
fn feols(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, k: usize, fe1: []const usize, g1: usize, fe2: []const usize, g2: usize, out: []f64) -> err {
    let (xd, e1) = mem.alloc[f64](a, n * k)
    let (yd, e2) = mem.alloc[f64](a, n)
    let (sum1, e3) = mem.alloc[f64](a, g1 + 1usize)
    let (cn1, e4) = mem.alloc[f64](a, g1 + 1usize)
    let (sum2, e5) = mem.alloc[f64](a, g2 + 1usize)
    let (cn2, e6) = mem.alloc[f64](a, g2 + 1usize)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    var i = 0usize
    while i < g1 {
        cn1[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < g2 {
        cn2[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        cn1[fe1[i]] += 1.0f64
        if g2 > 0usize { cn2[fe2[i]] += 1.0f64 }
        i += 1usize
    }
    // demean the response and every regressor, column by column
    var c = 0usize
    while c <= k {
        i = 0usize
        while i < n {
            if c < k { xd[i * k + c] = x[i * k + c] } else { yd[i] = y[i] }
            i += 1usize
        }
        var sweep = 0usize
        while sweep < 10000usize {
            var change = 0.0f64
            var g = 0usize
            while g < g1 {
                sum1[g] = 0.0f64
                g += 1usize
            }
            i = 0usize
            while i < n {
                if c < k { sum1[fe1[i]] += xd[i * k + c] } else { sum1[fe1[i]] += yd[i] }
                i += 1usize
            }
            i = 0usize
            while i < n {
                let m = sum1[fe1[i]] / cn1[fe1[i]]
                if c < k { xd[i * k + c] -= m } else { yd[i] -= m }
                if math.abs[f64](m) > change { change = math.abs[f64](m) }
                i += 1usize
            }
            if g2 > 0usize {
                g = 0usize
                while g < g2 {
                    sum2[g] = 0.0f64
                    g += 1usize
                }
                i = 0usize
                while i < n {
                    if c < k { sum2[fe2[i]] += xd[i * k + c] } else { sum2[fe2[i]] += yd[i] }
                    i += 1usize
                }
                i = 0usize
                while i < n {
                    let m = sum2[fe2[i]] / cn2[fe2[i]]
                    if c < k { xd[i * k + c] -= m } else { yd[i] -= m }
                    if math.abs[f64](m) > change { change = math.abs[f64](m) }
                    i += 1usize
                }
            }
            if g2 == 0usize || change < 1.0e-14f64 { break }
            sweep += 1usize
        }
        c += 1usize
    }
    // OLS on the demeaned data
    let (gm, e7) = mem.alloc[f64](a, k * k)
    let (rv, e8) = mem.alloc[f64](a, k)
    let (res, e9) = mem.alloc[f64](a, n)
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    i = 0usize
    while i < k * k {
        gm[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < k {
        rv[i] = 0.0f64
        i += 1usize
    }
    var t = 0usize
    while t < n {
        i = 0usize
        while i < k {
            rv[i] += xd[t * k + i] * yd[t]
            var j = 0usize
            while j < k {
                gm[i * k + j] += xd[t * k + i] * xd[t * k + j]
                j += 1usize
            }
            i += 1usize
        }
        t += 1usize
    }
    let (gi, ge) = gp.invert(a, gm, k)
    if ge != ok { ret ge }
    i = 0usize
    while i < k {
        var s = 0.0f64
        var j = 0usize
        while j < k {
            s += gi[i * k + j] * rv[j]
            j += 1usize
        }
        out[i] = s
        i += 1usize
    }
    var rss = 0.0f64
    t = 0usize
    while t < n {
        var f = 0.0f64
        i = 0usize
        while i < k {
            f += xd[t * k + i] * out[i]
            i += 1usize
        }
        res[t] = yd[t] - f
        rss += res[t] * res[t]
        t += 1usize
    }
    // fixed-effect parameter count: G1 (+ G2 - connected components)
    var kfe = g1
    if g2 > 0usize {
        let (par, e10) = mem.alloc[usize](a, g1 + g2)
        if e10 != ok { ret e10 }
        i = 0usize
        while i < g1 + g2 {
            par[i] = i
            i += 1usize
        }
        t = 0usize
        while t < n {
            let r1 = find(par, fe1[t])
            let r2 = find(par, g1 + fe2[t])
            if r1 != r2 { par[r1] = r2 }
            t += 1usize
        }
        var comps = 0usize
        i = 0usize
        while i < g1 + g2 {
            if find(par, i) == i { comps += 1usize }
            i += 1usize
        }
        kfe = g1 + g2 - comps
    }
    let nf = f64(n)
    let kf = f64(k)
    let ktot = kf + f64(kfe)
    // IID
    let s2 = rss / (nf - ktot)
    i = 0usize
    while i < k {
        out[k + i] = math.sqrt[f64](s2 * gi[i * k + i])
        i += 1usize
    }
    // meat for HC1 and clusters
    let (meat, e11) = mem.alloc[f64](a, k * k)
    let (cs, e12) = mem.alloc[f64](a, g1 * k)
    if e11 != ok { ret e11 }
    if e12 != ok { ret e12 }
    i = 0usize
    while i < k * k {
        meat[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < g1 * k {
        cs[i] = 0.0f64
        i += 1usize
    }
    t = 0usize
    while t < n {
        i = 0usize
        while i < k {
            cs[fe1[t] * k + i] += xd[t * k + i] * res[t]
            var j = 0usize
            while j < k {
                meat[i * k + j] += xd[t * k + i] * xd[t * k + j] * res[t] * res[t]
                j += 1usize
            }
            i += 1usize
        }
        t += 1usize
    }
    var kcl = kf + 1.0f64
    if g2 > 0usize { kcl = kf + f64(g2) }
    var pass = 0usize
    while pass < 2usize {
        // pass 0 hetero, pass 1 cluster
        if pass == 1usize {
            i = 0usize
            while i < k * k {
                meat[i] = 0.0f64
                i += 1usize
            }
            var g = 0usize
            while g < g1 {
                i = 0usize
                while i < k {
                    var j = 0usize
                    while j < k {
                        meat[i * k + j] += cs[g * k + i] * cs[g * k + j]
                        j += 1usize
                    }
                    i += 1usize
                }
                g += 1usize
            }
        }
        var corr = nf / (nf - ktot)
        if pass == 1usize { corr = f64(g1) / f64(g1 - 1usize) * (nf - 1.0f64) / (nf - kcl) }
        i = 0usize
        while i < k {
            var v = 0.0f64
            var l = 0usize
            while l < k {
                var mm = 0.0f64
                var q = 0usize
                while q < k {
                    mm += meat[l * k + q] * gi[q * k + i]
                    q += 1usize
                }
                v += gi[i * k + l] * mm
                l += 1usize
            }
            out[(2usize + pass) * k + i] = math.sqrt[f64](v * corr)
            i += 1usize
        }
        pass += 1usize
    }
    ret ok
}
