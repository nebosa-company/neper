// e.algo.stat.tsa's cpgram against TSA's cumulative periodogram (the stats::cpgram body). tests/oracle/tsa_cpgram.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R tsa_cpgram`; the layout of every case is at the top of scripts/r_oracle/groups/tsa_cpgram.R.

use e.algo.stat.tsa as ts
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let taper = z[1usize] / 100.0f64
    let series = z[2usize..2usize + n]
    let which = usize(z[z.len - 1usize])
    let (cum, e1) = mem.alloc[f64](a, n)
    if e1 != ok { os.exit(10) }
    let (len, crit, e2) = ts.cpgram(a, series, taper, cum)
    if e2 != ok { os.exit(11) }
    var s = 0.0f64
    var k = 0usize
    while k < len {
        if which == 3usize { s += f64(k + 1usize) * cum[k] } else { s += cum[k] }
        k += 1usize
    }
    if which == 0usize { ret f64(len) }
    if which == 1usize { ret crit }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/tsa_cpgram.json")
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
