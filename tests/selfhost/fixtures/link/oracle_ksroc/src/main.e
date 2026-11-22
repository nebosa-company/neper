// e.algo.stat.ksroc against ks kroc. tests/oracle/ksroc.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ksroc`; the layout is at the top of scripts/r_oracle/groups/ksroc.R.

use e.algo.stat.ksroc as kr
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let d = usize(x[0usize])
    let n1 = usize(x[1usize])
    let n2 = usize(x[2usize])
    let dd = d * d
    let s = 6usize + dd
    let (res, e1) = mem.alloc[f64](a, 401usize)
    if e1 != ok { os.exit(5) }
    var idx: [4]f64 = zero
    if kr.kroc(a, x[s..s + n1 * d], n1, x[s + n1 * d..s + n1 * d + n2 * d], n2, d, x[6usize..6usize + dd], x[5usize], res, idx[0usize..4usize]) != ok { os.exit(6) }
    if x[3usize] == 0.0f64 { ret res[usize(x[4usize])] }
    ret idx[usize(x[4usize])]
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
    let (golden, load_error) = oracle.load(a, "tests/oracle/ksroc.json")
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
