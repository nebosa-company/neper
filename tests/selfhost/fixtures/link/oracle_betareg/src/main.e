// e.algo.stat.betareg against betareg. tests/oracle/betareg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R betareg`; the layout is at the top of scripts/r_oracle/groups/betareg.R.
// Consecutive cases of one dataset share their fit.

use e.algo.stat.betareg as br
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn same(a: []const f64, b: []const f64) -> bool {
    if a.len != b.len { ret false }
    var i = 3usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn value(f: *const br.Fit, which: usize) -> f64 {
    if which < 10usize { ret f.par[which] }
    if which == 20usize { ret f.phi }
    ret f.ll
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/betareg.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    var have = false
    var cur: br.Fit = zero
    var prev: []const f64 = golden.cases[0usize].args
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let x = c.args
        if !have || !same(prev, x) {
            let n = usize(x[0usize])
            let p = usize(x[1usize])
            let (f, e) = br.fit(a, x[3usize + n..3usize + n + n * p], x[3usize..3usize + n], n, p)
            if e != ok { os.exit(5) }
            cur = f
            prev = x
            have = true
        }
        let got = value(&cur, usize(x[2usize]))
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
