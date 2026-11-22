// e.algo.stat.kscurv against ks kcurv. tests/oracle/kscurv.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R kscurv`; the layouts are at the top of scripts/r_oracle/groups/kscurv.R.

use e.algo.stat.kscurv as kc
use e.algo.stat.ksnd as nd
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let d = usize(x[0usize])
    let n = usize(x[1usize])
    let m = usize(x[4usize])
    let h = x[5usize..5usize + d * d]
    let s = 5usize + d * d
    let xs = x[s..s + n * d]
    if x[2usize] == 1.0f64 { ret kc.curv_contour(a, xs, n, d, h, m, x[3usize]) }
    let total = nd.pow_usize(m, d)
    let (gp, e1) = mem.alloc[f64](a, d * m)
    let (g, e2) = mem.alloc[f64](a, total)
    if e1 != ok || e2 != ok { os.exit(5) }
    if kc.curv_grid(a, xs, n, d, h, m, gp, g) != ok { os.exit(6) }
    ret g[usize(x[3usize])]
}

fn brief(a: *mem.Arena, c: *const oracle.Case, got: f64) -> str {
    let (initial, builder_error) = str.builder(a, 160usize)
    if builder_error != ok { ret c.name }
    var b = initial
    let _ = str.push(&b, c.name)
    let _ = str.push(&b, "(")
    var at = 0usize
    while at < c.args.len && at < 7usize {
        if at > 0usize { let _ = str.push(&b, ", ") }
        let _ = str.push_f64(&b, c.args[at])
        at += 1usize
    }
    let _ = str.push(&b, "..): got ")
    let _ = str.push_f64(&b, got)
    let _ = str.push(&b, ", R says ")
    let _ = str.push_f64(&b, c.want)
    ret str.done(&b)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/kscurv.json")
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
                let _ = io.print(brief(a, c, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
