// e.algo.stat.kspi against ks Hpi and Hpi.diag with the dscalar pilot in two to four dimensions. tests/oracle/kspi.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R kspi`; the layout is at the top of scripts/r_oracle/groups/kspi.R.

use e.algo.stat.kspi as kp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let d = usize(x[1usize])
    var h: [16]f64 = zero
    if str.eq(c.name, "Hpi.kfe") {
        if kp.hpi_kfe(a, x[6usize..6usize + n * d], n, d, usize(x[2usize]), h[0usize..16usize]) != ok { os.exit(8) }
        ret h[usize(x[4usize]) * d + usize(x[5usize])]
    }
    if str.eq(c.name, "Hscv") {
        if kp.hscv(a, x[6usize..6usize + n * d], n, d, usize(x[2usize]), x[3usize] != 0.0f64, h[0usize..16usize]) != ok { os.exit(7) }
        ret h[usize(x[4usize]) * d + usize(x[5usize])]
    }
    if kp.hpi(a, x[6usize..6usize + n * d], n, d, usize(x[2usize]), x[3usize] != 0.0f64, h[0usize..16usize]) != ok { os.exit(6) }
    ret h[usize(x[4usize]) * d + usize(x[5usize])]
}

fn brief(a: *mem.Arena, c: *const oracle.Case, got: f64) -> str {
    let (initial, builder_error) = str.builder(a, 160usize)
    if builder_error != ok { ret c.name }
    var b = initial
    let _ = str.push(&b, c.name)
    let _ = str.push(&b, "(")
    var at = 0usize
    while at < c.args.len && at < 6usize {
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
    let (golden, load_error) = oracle.load(a, "tests/oracle/kspi.json")
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
