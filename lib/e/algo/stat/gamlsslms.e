// R gamlss lms(y, x, families = "BCCG", method.pb = "ML"): the initial NO fit of y ~ pb(x) with a constant scale (c.crit 0.01), the BCCG fit with pb(x) in mu, sigma and nu,
// the one with the smaller AIC (k = 2) is kept, and when NO is kept it is refitted with pb(x) in sigma as well.

use e.algo.stat.gamlssfit as gf
use e.algo.stat.gamlsssmooth as sm
use e.mem

type Lms = struct { which: usize, aic0: f64, aic1: f64, fit: gf.Out }

// one fit: nsm pb(x) smoothers in the parameters flagged by sc; the design of a parameter with a smoother is the intercept and x
fn lms_fit(a: *mem.Arena, fam: usize, y: []const f64, x: []const f64, sc: []const usize, link: []const usize, c_crit: f64) -> (gf.Out, err) {
    let n = y.len
    var np = 2usize
    if fam == 4usize { np = 3usize }
    var nsm = 0usize
    var k = 0usize
    var tot = 0usize
    let (ncol, e1) = mem.alloc[usize](a, 3usize)
    if e1 != ok {
        var zo: gf.Out = zero
        ret (zo, e1)
    }
    while k < 3usize {
        ncol[k] = 0usize
        if k < np {
            ncol[k] = 1usize
            if sc[k] > 0usize { ncol[k] = 2usize }
            nsm += sc[k]
            tot += ncol[k]
        }
        k += 1usize
    }
    let (xs, e2) = mem.alloc[f64](a, n * tot + 1usize)
    let (w, e3) = mem.alloc[f64](a, n)
    let (off, e4) = mem.alloc[f64](a, 4usize * n)
    let (st, e5) = mem.alloc[f64](a, 4usize * n)
    let (hs, e6) = mem.alloc[usize](a, 3usize)
    let (stp, e7) = mem.alloc[f64](a, 3usize)
    let (smo, e8) = mem.alloc[sm.Smo](a, nsm + 1usize)
    if e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok {
        var zo: gf.Out = zero
        ret (zo, mem.Full)
    }
    var at = 0usize
    var i = 0usize
    k = 0usize
    var j = 0usize
    while k < 3usize {
        hs[k] = 0usize
        stp[k] = 1.0f64
        if k < np {
            i = 0usize
            while i < n {
                xs[at + i] = 1.0f64
                i += 1usize
            }
            at += n
            if sc[k] > 0usize {
                i = 0usize
                while i < n {
                    xs[at + i] = x[i]
                    i += 1usize
                }
                at += n
                let (t, be) = sm.pb_build(a, x, 20usize, 3usize, 2usize, 0.0f64 - 1.0f64, 0.0f64 - 1.0f64, 10.0f64, 0usize, 2.0f64)
                if be != ok {
                    var zo: gf.Out = zero
                    ret (zo, be)
                }
                smo[j] = t
                j += 1usize
            }
        }
        k += 1usize
    }
    i = 0usize
    while i < n {
        w[i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < 4usize * n {
        off[i] = 0.0f64
        st[i] = 0.0f64
        i += 1usize
    }
    let (fo, fe) = gf.fit_smo(a, smo[0usize..nsm], sc, fam, 0usize, y, w, xs, ncol, link, off, st, hs, stp, c_crit, 20usize, 0.001f64, 50usize, true, 1usize, 20usize)
    ret (fo, fe)
}

fn lms_bccg(a: *mem.Arena, y: []const f64, x: []const f64) -> (Lms, err) {
    var zl: Lms = zero
    let (sc, e1) = mem.alloc[usize](a, 3usize)
    let (link, e2) = mem.alloc[usize](a, 3usize)
    if e1 != ok || e2 != ok { ret (zl, mem.Full) }
    sc[0usize] = 1usize
    sc[1usize] = 0usize
    sc[2usize] = 0usize
    link[0usize] = 4usize
    link[1usize] = 5usize
    link[2usize] = 4usize
    let (m0, f0) = lms_fit(a, 0usize, y, x, sc, link, 0.01f64)
    if f0 != ok { ret (zl, f0) }
    let aic0 = m0.gdev + 2.0f64 * m0.df
    sc[1usize] = 1usize
    sc[2usize] = 1usize
    link[0usize] = 4usize
    link[1usize] = 5usize
    link[2usize] = 4usize
    let (m1, f1) = lms_fit(a, 4usize, y, x, sc, link, 0.001f64)
    if f1 != ok { ret (zl, f1) }
    let aic1 = m1.gdev + 2.0f64 * m1.df
    if aic1 < aic0 { ret (Lms { which: 1usize, aic0: aic0, aic1: aic1, fit: m1 }, ok) }
    sc[2usize] = 0usize
    link[0usize] = 4usize
    link[1usize] = 5usize
    let (m2, f2) = lms_fit(a, 0usize, y, x, sc, link, 0.01f64)
    if f2 != ok { ret (zl, f2) }
    ret (Lms { which: 0usize, aic0: aic0, aic1: aic1, fit: m2 }, ok)
}
