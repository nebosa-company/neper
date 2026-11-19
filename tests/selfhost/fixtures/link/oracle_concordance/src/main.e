// e.algo.stat.coxext's pair-count concordance against survival::concordance. tests/oracle/concordance.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R concordance`; the layout is at the top of scripts/r_oracle/groups/concordance.R.

use e.algo.stat.coxext as cx
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    if c.name.len == 6usize {
        let nc = usize(z[1usize + 3usize * n])
        let r0 = 2usize + 3usize * n + nc
        let (o, e1) = mem.alloc[f64](a, 5usize * n * (nc + 1usize))
        if e1 != ok { ret 0.0f64 / 0.0f64 }
        let rows = cx.surv_split(z[1usize..1usize + n], z[1usize + n..1usize + 2usize * n], z[1usize + 2usize * n..1usize + 3usize * n], n, z[2usize + 3usize * n..2usize + 3usize * n + nc], nc, o)
        let rq = z[r0]
        if rq < 0.0f64 { ret f64(rows) }
        ret o[usize(rq) * 5usize + usize(z[r0 + 1usize])]
    }
    var out: [6]f64 = zero
    cx.concordance(z[1usize..1usize + n], z[1usize + n..1usize + 2usize * n], z[1usize + 2usize * n..1usize + 3usize * n], n, out[0usize..6usize])
    ret out[usize(z[1usize + 3usize * n])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/concordance.json")
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
