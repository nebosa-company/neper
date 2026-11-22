// e.algo.stat.ks2ddiag against ks Hpi.diag and Hscv.diag in two dimensions with the SAMSE pilot. tests/oracle/ks2ddiag.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ks2ddiag`; the layout is at the top of scripts/r_oracle/groups/ks2ddiag.R.

use e.algo.stat.ks2ddiag as kd
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    var h: [4]f64 = zero
    if str.eq(c.name, "Hscv.diag") {
        if kd.hscv_diag(a, x[3usize..3usize + 2usize * n], n, usize(x[1usize]), h[0usize..4usize]) != ok { os.exit(7) }
    } else {
        if kd.hpi_diag(a, x[3usize..3usize + 2usize * n], n, usize(x[1usize]), h[0usize..4usize]) != ok { os.exit(6) }
    }
    ret h[usize(x[2usize]) * 3usize]
}

fn brief(a: *mem.Arena, c: *const oracle.Case, got: f64) -> str {
    let (initial, builder_error) = str.builder(a, 160usize)
    if builder_error != ok { ret c.name }
    var b = initial
    let _ = str.push(&b, c.name)
    let _ = str.push(&b, "(")
    var at = 0usize
    while at < c.args.len && at < 3usize {
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
    let (golden, load_error) = oracle.load(a, "tests/oracle/ks2ddiag.json")
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
