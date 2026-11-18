// e.algo.stat.wrs2 mcp2atm against WRS2. tests/oracle/wrs2_mcp2atm.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R wrs2_mcp2atm`; the layout is at the top of scripts/r_oracle/groups/wrs2_mcp2atm.R.

use e.algo.stat.wrs2 as w
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let jn = usize(z[0usize])
    let kn = usize(z[1usize])
    let which = usize(z[2usize])
    let ci = usize(z[3usize])
    let what = usize(z[4usize])
    let p = jn * kn
    let (sizes, e0) = mem.alloc[usize](a, p)
    if e0 != ok { os.exit(4) }
    var total = 0usize
    var g = 0usize
    while g < p {
        sizes[g] = usize(z[5usize + g])
        total += sizes[g]
        g += 1usize
    }
    let (r, e) = w.mcp2atm(a, z[5usize + p..5usize + p + total], sizes, jn, kn, 0.2f64, which)
    if e != ok { os.exit(5) }
    if what == 0usize { ret r[ci].psihat }
    ret r[ci].p
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/wrs2_mcp2atm.json")
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
