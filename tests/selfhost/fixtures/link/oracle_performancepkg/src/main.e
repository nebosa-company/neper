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
        if str.eq(c.name, "het") {
            let hn = usize(x[0usize])
            let hp = usize(x[1usize])
            got = pf.heteroscedasticity_p(a, x[2usize + hn..2usize + hn + hn * hp], x[2usize..2usize + hn], hn, hp)
        } else if str.eq(c.name, "lr2") {
            let ln = usize(x[1usize])
            let lp = usize(x[2usize])
            got = pf.logit_r2(a, x[3usize + ln..3usize + ln + ln * lp], x[3usize..3usize + ln], ln, lp, usize(x[0usize]))
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
