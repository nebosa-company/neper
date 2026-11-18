// e.algo.stat.vcdeffect's goodfit_poisson against vcd::goodfit(type = "poisson", method = "ML"). tests/oracle/vcd_goodfit.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R vcd_goodfit`; the layout of every case is at the top of scripts/r_oracle/groups/vcd_goodfit.R.

use e.algo.stat.vcdeffect as ve
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let which = usize(z[z.len - 1usize])
    var k = usize(z[0usize])
    var base = 1usize
    if str.eq(c.name, "gb") {
        // binomial rows: size first, then the count of entries and the entries
        k = usize(z[1usize])
        base = 2usize
    }
    let freq = z[base..base + k]
    let (fit, e1) = mem.alloc[f64](a, k)
    if e1 != ok { os.exit(10) }
    var lambda = 0.0f64
    var df = 0.0f64
    var e2 = ok
    if str.eq(c.name, "gb") {
        let (pr, dfb, eb) = ve.goodfit_binomial(freq, z[0usize], fit)
        lambda = pr
        df = dfb
        e2 = eb
    } else {
        let (lp, dfp, ep) = ve.goodfit_poisson(freq, fit)
        lambda = lp
        df = dfp
        e2 = ep
    }
    if e2 != ok { os.exit(11) }
    if which == 0usize { ret lambda }
    if which == 2usize { ret df }
    var s = 0.0f64
    var i = 0usize
    while i < k {
        if which == 1usize { s += fit[i] } else { s += (freq[i] - fit[i]) * (freq[i] - fit[i]) / fit[i] }
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/vcd_goodfit.json")
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
