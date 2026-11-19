// e.algo.stat.performancepkg against performance. tests/oracle/performancepkg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R performancepkg`; the layout is at the top of scripts/r_oracle/groups/performancepkg.R.

use e.algo.stat.performancepkg as pf
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/performancepkg.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let x = c.args
        var got = 0.0f64
        if str.eq(c.name, "stdp") {
            // args (n, p, level, j, which 0 slope 1 lower 2 upper, y[n], x row-major n by p)
            let sn = usize(x[0usize])
            let sp = usize(x[1usize])
            let (so, se) = mem.alloc[f64](a, 3usize * sp)
            if se != ok { os.exit(9) }
            if pf.std_params_lm(a, x[5usize + sn..5usize + sn + sn * sp], x[5usize..5usize + sn], sn, sp, x[2usize], so) != ok { os.exit(10) }
            got = so[usize(x[4usize]) * sp + usize(x[3usize])]
        } else if str.eq(c.name, "het") {
            let hn = usize(x[0usize])
            let hp = usize(x[1usize])
            got = pf.heteroscedasticity_p(a, x[2usize + hn..2usize + hn + hn * hp], x[2usize..2usize + hn], hn, hp)
        } else if str.eq(c.name, "lr2") {
            let ln = usize(x[1usize])
            let lp = usize(x[2usize])
            got = pf.logit_r2(a, x[3usize + ln..3usize + ln + ln * lp], x[3usize..3usize + ln], ln, lp, usize(x[0usize]))
        } else if str.eq(c.name, "norm") {
            let nn = usize(x[0usize])
            let np = usize(x[1usize])
            got = pf.normality_p(a, x[2usize + nn..2usize + nn + nn * np], x[2usize..2usize + nn], nn, np)
        } else if str.eq(c.name, "zs") || str.eq(c.name, "mah") {
            let on = usize(x[1usize])
            let oq = usize(x[2usize])
            let orow = usize(x[3usize + on * oq])
            if str.eq(c.name, "zs") { got = pf.zscore_distance(a, x[3usize..3usize + on * oq], on, oq, x[0usize] == 1.0f64, orow) } else { got = pf.mahalanobis_distance(a, x[3usize..3usize + on * oq], on, oq, orow) }
        } else if str.eq(c.name, "cook") {
            let cn = usize(x[0usize])
            let cp = usize(x[1usize])
            got = pf.cook_distance(a, x[2usize + cn..2usize + cn + cn * cp], x[2usize..2usize + cn], cn, cp, usize(x[2usize + cn + cn * cp]))
        } else if str.eq(c.name, "pchk") {
            let pn = usize(x[1usize])
            let pp = usize(x[2usize])
            got = pf.poisson_checks(a, x[3usize + pn..3usize + pn + pn * pp], x[3usize..3usize + pn], pn, pp, usize(x[0usize]))
        } else if str.eq(c.name, "hl") {
            let hb = usize(x[0usize])
            let hn = usize(x[1usize])
            let hp = usize(x[2usize])
            let (ho, he) = mem.alloc[f64](a, 2usize)
            if he != ok { os.exit(4) }
            if pf.hosmer(a, x[3usize + hn..3usize + hn + hn * hp], x[3usize..3usize + hn], hn, hp, hb, ho) != ok { os.exit(5) }
            got = ho[usize(x[3usize + hn + hn * hp])]
        } else if str.eq(c.name, "lm2") {
            let mn = usize(x[1usize])
            let mp = usize(x[2usize])
            got = pf.logit_fit_measure(a, x[3usize + mn..3usize + mn + mn * mp], x[3usize..3usize + mn], mn, mp, usize(x[0usize]))
        } else if str.eq(c.name, "vif") {
            let vn = usize(x[0usize])
            let vq = usize(x[1usize])
            got = pf.vif(a, x[3usize..3usize + vn * vq], vn, vq, usize(x[2usize]))
        } else {
        let n = usize(x[1usize])
        let p = usize(x[2usize])
        got = pf.lm_index(a, x[3usize + n..3usize + n + n * p], x[3usize..3usize + n], n, p, usize(x[0usize]))
        }
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
