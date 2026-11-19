// e.algo.stat.energy's energy_hclust against energy.hclust. tests/oracle/energy_hc.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R energy_hc`; the layout is at the top of scripts/r_oracle/groups/energy_hc.R.

use e.algo.stat.energy as en
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let d = usize(x[1usize])
    let (t, e) = en.energy_hclust(a, x[3usize..3usize + n * d], n, d, x[2usize])
    if e != ok { os.exit(4) }
    var s = 0.0f64
    var i = 0usize
    if str.eq(c.name, "height") {
        while i + 1usize < n {
            s += t.height[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if str.eq(c.name, "merge") {
        while i + 1usize < n {
            s += f64(t.merge_a[i]) * f64(2usize * i + 1usize) + f64(t.merge_b[i]) * f64(2usize * i + 2usize)
            i += 1usize
        }
        ret s
    }
    while i < n {
        s += f64(t.order[i]) * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/energy_hc.json")
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
