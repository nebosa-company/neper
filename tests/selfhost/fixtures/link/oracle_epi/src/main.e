// e.algo.stat.epi against Epi::twoby2. tests/oracle/epi.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R epi`; the layout is at the top of scripts/r_oracle/groups/epi.R.

use e.algo.stat.epi as ei
use e.algo.stat.epir as ep
use e.algo.stat.performancepkg as pf
use e.algo.stat.mlogitpkg as ml
use e.mem
use e.io
use e.os
use e.str
use e.test.oracle as oracle

fn answer(ar: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "clog") {
        let cn = usize(x[0usize])
        let cj = usize(x[1usize])
        let ck = usize(x[2usize])
        let (co, ce) = mem.alloc[f64](ar, 2usize * ck + 1usize)
        let (chs, he) = mem.alloc[f64](ar, cn)
        if ce != ok || he != ok { os.exit(8) }
        var q = 0usize
        while q < cn {
            chs[q] = 0.0f64
            q += 1usize
        }
        if ml.clogit(ar, x[3usize..3usize + cn * cj * ck], chs, cn, cj, ck, false, co) != ok { os.exit(9) }
        ret co[usize(x[3usize + cn * cj * ck])]
    }
    if str.eq(c.name, "fci") {
        let (fo, fe) = mem.alloc[f64](ar, 3usize)
        if fe != ok { os.exit(6) }
        if ei.fisher_ci(ar, x[0usize], x[1usize], x[2usize], x[3usize], x[4usize], fo) != ok { os.exit(7) }
        ret fo[usize(x[5usize])]
    }
    if str.eq(c.name, "rocf") {
        let fnn = usize(x[0usize])
        let fpp = usize(x[1usize])
        let (fit, fe) = mem.alloc[f64](ar, fnn)
        if fe != ok { os.exit(4) }
        if pf.logit_fitted(ar, x[2usize + fnn..2usize + fnn + fnn * fpp], x[2usize..2usize + fnn], fnn, fpp, fit) != ok { os.exit(5) }
        let ys = x[2usize..2usize + fnn]
        let fk = usize(x[2usize + fnn + fnn * fpp])
        if fk == 1usize { ret ei.roc_auc(fit, ys) }
        if fk == 2usize { ret ei.roc_max_cut(fit, ys) }
        ret ei.roc_value(fit, ys, usize(x[3usize + fnn + fnn * fpp]), usize(x[4usize + fnn + fnn * fpp]))
    }
    if str.eq(c.name, "roc") {
        let rn = usize(x[0usize])
        let rt = x[1usize..1usize + rn]
        let rs = x[1usize + rn..1usize + 2usize * rn]
        let kind = usize(x[1usize + 2usize * rn])
        if kind == 1usize { ret ei.roc_auc(rt, rs) }
        if kind == 2usize { ret ei.roc_max_cut(rt, rs) }
        ret ei.roc_value(rt, rs, usize(x[2usize + 2usize * rn]), usize(x[3usize + 2usize * rn]))
    }
    let a = x[0usize]
    let b = x[1usize]
    let cc = x[2usize]
    let d = x[3usize]
    let w = usize(x[4usize])
    let z = 1.959963984540054f64
    if w < 3usize {
        let (e, lo, hi) = ei.bin_ci(a, a + b, z)
        if w == 0usize { ret e }
        if w == 1usize { ret lo }
        ret hi
    }
    if w < 6usize {
        let (e, lo, hi) = ei.bin_ci(cc, cc + d, z)
        if w == 3usize { ret e }
        if w == 4usize { ret lo }
        ret hi
    }
    let t = ep.Table2 { a: a, b: b, c: cc, d: d }
    if w < 9usize {
        let (e, lo, hi) = ep.risk_ratio(t, 0.95f64)
        if w == 6usize { ret e }
        if w == 7usize { ret lo }
        ret hi
    }
    if w < 12usize {
        let (e, lo, hi) = ep.odds_ratio(t, 0.95f64)
        if w == 9usize { ret e }
        if w == 10usize { ret lo }
        ret hi
    }
    if w < 15usize {
        let (e, lo, hi) = ei.newcombe(a, a + b, cc, cc + d, z)
        if w == 12usize { ret e }
        if w == 13usize { ret lo }
        ret hi
    }
    if w == 15usize { ret ei.asymptotic_p(a, b, cc, d) }
    ret ei.fisher_p(a, b, cc, d)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/epi.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
