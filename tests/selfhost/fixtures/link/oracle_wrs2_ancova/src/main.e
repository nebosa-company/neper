// e.algo.stat.wrs2 ancova against WRS2. tests/oracle/wrs2_ancova.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R wrs2_ancova`; the layout is at the top of scripts/r_oracle/groups/wrs2_ancova.R.

use e.algo.stat.wrs2 as w
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n1 = usize(z[0usize])
    let n2 = usize(z[1usize])
    let np = usize(z[2usize])
    let row = usize(z[3usize])
    let what = usize(z[4usize])
    let pts = z[5usize..5usize + np]
    let b = 5usize + np
    let x1 = z[b..b + n1]
    let y1 = z[b + n1..b + 2usize * n1]
    let x2 = z[b + 2usize * n1..b + 2usize * n1 + n2]
    let y2 = z[b + 2usize * n1 + n2..b + 2usize * n1 + 2usize * n2]
    let (out, eo) = mem.alloc[w.AncRow](a, 5usize + np)
    if eo != ok { os.exit(4) }
    let (k, e) = w.ancova(a, x1, y1, x2, y2, 0.2f64, 1.0f64, 1.0f64, pts, out)
    if e != ok { os.exit(5) }
    if row >= k { os.exit(6) }
    if what == 0usize { ret out[row].x }
    if what == 1usize { ret f64(out[row].n1) }
    if what == 2usize { ret f64(out[row].n2) }
    if what == 3usize { ret out[row].dif }
    if what == 4usize { ret out[row].se }
    if what == 5usize { ret out[row].test }
    ret out[row].p
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/wrs2_ancova.json")
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
