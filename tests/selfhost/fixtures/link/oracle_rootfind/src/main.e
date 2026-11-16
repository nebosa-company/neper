// e.algo.stat.rootfind against stats::uniroot and rootSolve::uniroot.all. tests/oracle/rootfind.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R rootfind`; the layout is at the top of scripts/r_oracle/groups/rootfind.R.

use e.algo.stat.rootfind as rf
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/rootfind.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let x = c.args
        var got = 0.0f64
        if str.eq(c.name, "uni") {
            let (r, it, pr) = rf.uniroot(usize(x[1usize]), x[2usize], x[3usize], x[4usize])
            let w = usize(x[0usize])
            if w == 0usize { got = r }
            if w == 1usize { got = f64(it) }
            if w == 2usize { got = pr }
        } else {
            let (out, e1) = mem.alloc[f64](a, 64usize)
            if e1 != ok { os.exit(5) }
            let cnt = rf.uniroot_all(usize(x[1usize]), x[2usize], x[3usize], out)
            if str.eq(c.name, "allcount") { got = f64(cnt) } else if usize(x[0usize]) < cnt { got = out[usize(x[0usize])] } else { got = 0.0f64 - 1.0e9f64 }
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
