// e.algo.stat.imputets against imputeTS. tests/oracle/imputets.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R imputets`; the layout is at the top of scripts/r_oracle/groups/imputets.R.

use e.algo.stat.imputets as it
use e.algo.rand.r as rng
use e.algo.stat.kalman as kal
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let kind = usize(x[0usize])
    let k = usize(x[1usize])
    let n = usize(x[2usize])
    let (s, e) = mem.alloc[f64](a, n)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < n {
        s[i] = x[3usize + i]
        if s[i] < 0.0f64 - 999000.0f64 { s[i] = 0.0f64 / 0.0f64 }
        i += 1usize
    }
    if str.eq(c.name, "locf") {
        let (lr, le) = it.na_locf_ts(a, s, kind >= 10usize, kind % 10usize)
        if le != ok { os.exit(7) }
        ret lr[k]
    }
    if str.eq(c.name, "maxgap") {
        // args (option 0 locf 1 nocb 2 linear 3 spline, index, n, series..., maxgap at the end)
        let mg = i64(x[3usize + n])
        var r2: []f64 = zero
        var e5 = ok
        if kind <= 1usize {
            let (q, qe) = it.na_locf_ts(a, s, kind == 1usize, 1usize)
            r2 = q
            e5 = qe
        } else {
            let (q, qe) = it.na_interpolation(a, s, kind - 2usize)
            r2 = q
            e5 = qe
        }
        if e5 != ok { os.exit(7) }
        let (fl, fe) = mem.alloc[f64](a, n)
        if fe != ok { os.exit(7) }
        var t = 0usize
        while t < n {
            fl[t] = r2[t]
            t += 1usize
        }
        it.apply_maxgap(s, fl, mg)
        ret fl[k]
    }
    if str.eq(c.name, "sea") {
        // args (algorithm, index, n, series..., period)
        let (sr, se) = it.na_seadec(a, s, usize(x[3usize + n]), kind)
        if se != ok { os.exit(7) }
        ret sr[k]
    }
    if str.eq(c.name, "split") {
        // args (algorithm, index, n, series..., period)
        let (sr, se) = it.na_seasplit(a, s, usize(x[3usize + n]), kind)
        if se != ok { os.exit(7) }
        ret sr[k]
    }
    if str.eq(c.name, "kal") {
        // args (smooth, index, n, series..., p, nit, h, T, Z, V, a, P, Pn) with T, V, P, Pn row-major
        let pp = usize(x[3usize + n])
        var o = 4usize + n
        let nit = i64(x[o - 0usize])
        o += 1usize
        let h = x[o]
        o += 1usize
        let (tm, e1) = mem.alloc[f64](a, pp * pp)
        let (zv, e2) = mem.alloc[f64](a, pp)
        let (vm, e3) = mem.alloc[f64](a, pp * pp)
        let (av, e4) = mem.alloc[f64](a, pp)
        let (pm, e5) = mem.alloc[f64](a, pp * pp)
        let (pn, e6) = mem.alloc[f64](a, pp * pp)
        if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { os.exit(5) }
        var q = 0usize
        while q < pp * pp {
            tm[q] = x[o + q]
            vm[q] = x[o + pp * pp + pp + q]
            pm[q] = x[o + 2usize * pp * pp + 2usize * pp + q]
            pn[q] = x[o + 3usize * pp * pp + 2usize * pp + q]
            q += 1usize
        }
        q = 0usize
        while q < pp {
            zv[q] = x[o + pp * pp + q]
            av[q] = x[o + 2usize * pp * pp + pp + q]
            q += 1usize
        }
        let mdl = kal.SsModel{ p: pp, tm: tm, zv: zv, h: h, vm: vm, av: av, pm: pm, pn: pn }
        let (kr, ke) = it.na_kalman_model(a, s, s, &mdl, kind == 1usize, nit)
        if ke != ok { os.exit(7) }
        ret kr[k]
    }
    if str.eq(c.name, "sts") {
        // args (smooth, index, n, series..., type, frequency)
        let (sr, se) = it.na_kalman_structts(a, s, usize(x[3usize + n]), usize(x[4usize + n]), kind == 1usize)
        if se != ok { os.exit(7) }
        ret sr[k]
    }
    if str.eq(c.name, "stats") {
        // args (which 0..7, 0, n, series...)
        var so: [8]f64 = zero
        if it.stats_na(a, s, so[0usize..8usize]) != ok { os.exit(7) }
        ret so[kind]
    }
    if str.eq(c.name, "rnd") {
        // args (seed, index, n, series..., lower or -999999, upper or -999999)
        var lo = x[3usize + n]
        var hi = x[4usize + n]
        if lo < 0.0f64 - 999000.0f64 { lo = 0.0f64 / 0.0f64 }
        if hi < 0.0f64 - 999000.0f64 { hi = 0.0f64 / 0.0f64 }
        var rg: rng.Rng = zero
        rng.seed(&rg, i64(x[0usize]))
        let (rr, re) = it.na_random(a, &rg, s, lo, hi)
        if re != ok { os.exit(7) }
        ret rr[k]
    }
    if str.eq(c.name, "repl") {
        // args (0, index, n, series..., fill)
        let (rr, re) = it.na_replace(a, s, x[3usize + n])
        if re != ok { os.exit(7) }
        ret rr[k]
    }
    if str.eq(c.name, "interp") {
        let (ir, ie) = it.na_interpolation(a, s, kind)
        if ie != ok { os.exit(7) }
        ret ir[k]
    }
    if str.eq(c.name, "mean") { ret it.na_mean_value(a, s, kind) }
    let (r, e2) = it.na_ma(a, s, k, kind)
    if e2 != ok { os.exit(6) }
    var t = 0.0f64
    i = 0usize
    while i < n {
        t += r[i] * f64(i + 1usize)
        i += 1usize
    }
    ret t
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/imputets.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
